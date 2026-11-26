import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;

import '../models/local_book.dart';
import '../storage/local_library.dart';
import '../importing/book_importer.dart';
import 'cloud_provider.dart';

class RemotePosition {
  final String bookId, device;
  final int section, offset, modified;
  final int audioOffsetMs;
  RemotePosition(
    this.bookId,
    this.device,
    this.section,
    this.offset,
    this.modified, [
    this.audioOffsetMs = 0,
  ]);
}

class SyncResult {
  int uploaded = 0, downloaded = 0;
  bool deferred = false;
  final List<RemotePosition> positions = [];
}

class LibrarySync {
  static bool isAhead(
    int section,
    int offset,
    int audioOffsetMs,
    LocalBook book,
  ) =>
      section > book.section ||
      (section == book.section &&
          (offset > book.offset ||
              (offset == book.offset && audioOffsetMs > book.audioOffsetMs)));
  final LocalLibrary library;
  final String deviceId;
  LibrarySync(this.library, this.deviceId);
  static const chunkSize = 192 * 1024;
  Future<SyncResult> run(
    CloudProvider cloud, {
    void Function(String)? status,
    bool Function()? yieldRequested,
    LocalBook? Function(String id)? liveBook,
  }) async {
    final result = SyncResult();
    status?.call('正在检查私人云文件');
    final known = (await cloud.list()).toSet();
    var local = await library.load();
    // Immutable content chunks are committed by publishing the manifest LAST.
    for (final book in local) {
      if (yieldRequested?.call() == true) {
        result.deferred = true;
        return result;
      }
      final key = 'book-${book.id}.manifest';
      if (!known.contains(key)) {
        status?.call('上传本地文件中，已上传 ${result.uploaded} 个文件');
        final source = await library.readSource(book.id);
        if (source.isEmpty ||
            source.length > BookImporter.maxBytes ||
            await compute(sourceHash, source) != book.id) {
          throw const CloudFailure('书籍原件校验失败');
        }
        final limits = cloud is CloudTransferLimits
            ? cloud as CloudTransferLimits
            : null;
        final size = (limits?.transferChunkBytes ?? 4 * 1024 * 1024).clamp(
          192 * 1024,
          4 * 1024 * 1024,
        );
        final workers = (limits?.transferWorkers ?? 4).clamp(1, 4);
        final parts = await compute(sourceParts, (source, size));
        final meter = _TransferMeter(
          '上传',
          result.uploaded,
          source.length,
          status,
        );
        final groups = _partGroups(parts);
        await _parallel(groups.length, workers, (job) async {
          final indices = groups[job];
          final index = indices.first;
          if (yieldRequested?.call() == true) return;
          final part = parts[index];
          final partKey = part['key'] as String;
          final start = index * size;
          final bytes = Uint8List.sublistView(
            source,
            start,
            (start + size).clamp(0, source.length),
          );
          // Content-addressed objects are immutable. A listed object survives a
          // failed attempt and can safely be reused without uploading it again.
          if (!known.contains(partKey)) {
            await _retry(() => cloud.write(partKey, bytes));
            known.add(partKey);
            meter.add(bytes.length);
          } else {
            meter.reuse(bytes.length);
          }
          if (indices.length > 1) {
            meter.reuse(bytes.length * (indices.length - 1));
          }
        });
        if (yieldRequested?.call() == true) {
          result.deferred = true;
          return result;
        }
        // Publishing this small manifest is the commit. Partial books stay hidden.
        await _retry(
          () => cloud.write(
            key,
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'schema': 2,
                  'id': book.id,
                  'format': book.format,
                  'title': book.title,
                  'author': book.author,
                  'size': source.length,
                  'parts': parts,
                }),
              ),
            ),
          ),
        );
        known.add(key);
        result.uploaded++;
        status?.call('上传本地文件中，已上传 ${result.uploaded} 个文件');
      }
      await cloud.write(
        'position-${book.id}-$deviceId.json',
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              ...((liveBook?.call(book.id) ?? book).position()),
              'device': deviceId,
            }),
          ),
        ),
      );
    }
    // Refresh after uploads so per-device events never share an overwrite-prone global file.
    final keys = await cloud.list();
    final localIds = local.map((b) => b.id).toSet();
    for (final key in keys.where(
      (k) => RegExp(r'^book-[a-f0-9]{64}\.manifest$').hasMatch(k),
    )) {
      if (yieldRequested?.call() == true) {
        result.deferred = true;
        return result;
      }
      // A local book already has immutable content; do not fetch its manifest.
      final listedId = key.substring(5, key.length - '.manifest'.length);
      if (localIds.contains(listedId)) continue;
      final manifest = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(await _retry(() => cloud.read(key)))),
      );
      final id = manifest['id'] as String;
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
          key != 'book-$id.manifest') {
        throw const CloudFailure('云书籍标识不匹配');
      }
      status?.call('下载本地文件中，已下载 ${result.downloaded} 个文件');
      final downloaded = await _download(
        cloud,
        manifest,
        result.downloaded,
        status,
        yieldRequested,
      );
      if (downloaded == null) {
        result.deferred = true;
        return result;
      }
      final (book, source, staging) = downloaded;
      await library.install(book, source);
      await staging.delete(recursive: true);
      localIds.add(id);
      result.downloaded++;
      status?.call('下载本地文件中，已下载 ${result.downloaded} 个文件');
    }
    local = await library.load();
    status?.call('正在同步阅读进度');
    final map = {for (final b in local) b.id: b};
    for (final key in keys.where(
      (k) => RegExp(r'^position-[a-f0-9]{64}-[a-f0-9]+\.json$').hasMatch(k),
    )) {
      if (key.endsWith('-$deviceId.json')) continue;
      if (yieldRequested?.call() == true) {
        result.deferred = true;
        return result;
      }
      final p = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(await cloud.read(key))),
      );
      final b = map[p['id']];
      if (b == null || liveBook?.call(b.id) != null) continue;
      final section = p['section'] as int, offset = p['offset'] as int;
      if (section < 0 ||
          section >= b.sections.length ||
          offset < 0 ||
          offset > b.sections[section].text.length) {
        continue;
      }
      final audioOffset = (p['audioOffsetMs'] as int? ?? 0).clamp(
        0,
        24 * 60 * 60 * 1000,
      );
      if (isAhead(section, offset, audioOffset, b)) {
        b.locate(section, offset);
        b.audioOffsetMs = audioOffset;
        result.positions.add(
          RemotePosition(
            b.id,
            p['device'] as String,
            section,
            offset,
            p['modified'] as int,
            audioOffset,
          ),
        );
      }
    }
    for (final b in map.values) {
      if (!result.positions.any((p) => p.bookId == b.id)) continue;
      if (yieldRequested?.call() == true) {
        result.deferred = true;
        return result;
      }
      // Recheck after asynchronous cloud reads: the reader may have opened it.
      if (liveBook?.call(b.id) != null) continue;
      final saved = await library.saveRemotePosition(
        b,
        isActive: () => liveBook?.call(b.id) != null,
      );
      if (!saved) continue;
      await cloud.write(
        'position-${b.id}-$deviceId.json',
        Uint8List.fromList(
          utf8.encode(jsonEncode({...b.position(), 'device': deviceId})),
        ),
      );
    }
    return result;
  }

  Future<(LocalBook, Uint8List, Directory)?> _download(
    CloudProvider cloud,
    Map<String, dynamic> manifest,
    int completed,
    void Function(String)? status,
    bool Function()? yieldRequested,
  ) async {
    final id = manifest['id'] as String;
    final schema = manifest['schema'] as int? ?? 1;
    if (schema != 1 && schema != 2) throw const CloudFailure('请更新书虫后同步此书');
    final parts = (manifest['parts'] as List)
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    if (parts.isEmpty || parts.length > 1000) {
      throw const CloudFailure('云文件块数无效');
    }
    var total = 0;
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i];
      final hash = p['hash'];
      final size = p['size'];
      if (hash is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
          size is! int ||
          size <= 0 ||
          size > 4 * 1024 * 1024 ||
          p['key'] !=
              (schema == 1
                  ? 'book-$id-$i.part'
                  : 'book-$hash-2000000000.part')) {
        throw const CloudFailure('云内容路径或大小不匹配');
      }
      total += size;
    }
    if (total > (schema == 2 ? BookImporter.maxBytes : 100 * 1024 * 1024) ||
        (schema == 2 && manifest['size'] != total)) {
      throw const CloudFailure('云书籍大小无效');
    }
    await library.root.create(recursive: true);
    final staging = Directory('${library.root.path}/.cloud-download-$id');
    await staging.create(recursive: true);
    final limits = cloud is CloudTransferLimits
        ? cloud as CloudTransferLimits
        : null;
    final meter = _TransferMeter('下载', completed, total, status);
    final groups = _partGroups(parts);
    await _parallel(groups.length, (limits?.transferWorkers ?? 4).clamp(1, 4), (
      job,
    ) async {
      final indices = groups[job];
      final i = indices.first;
      if (yieldRequested?.call() == true) return;
      final p = parts[i];
      final cached = File('${staging.path}/${p['hash']}.part');
      if (await cached.exists()) {
        final bytes = await cached.readAsBytes();
        if (bytes.length == p['size'] &&
            await compute(sourceHash, bytes) == p['hash']) {
          meter.reuse(bytes.length * indices.length);
          return;
        }
        await cached.delete();
      }
      final bytes = await _retry(() async {
        final value = await cloud.read(p['key'] as String);
        if (value.length != p['size'] ||
            await compute(sourceHash, value) != p['hash']) {
          throw const CloudFailure('私人云文件校验失败，本机内容未覆盖');
        }
        return value;
      });
      // Temporary files are never book entries. Keep verified parts for retries.
      final partial = File('${cached.path}.$i.tmp');
      await partial.writeAsBytes(bytes, flush: true);
      if (await cached.exists()) await cached.delete();
      await partial.rename(cached.path);
      meter.add(bytes.length);
      if (indices.length > 1) meter.reuse(bytes.length * (indices.length - 1));
    });
    if (yieldRequested?.call() == true) return null;
    final joined = File('${staging.path}/source.tmp');
    final output = await joined.open(mode: FileMode.write);
    try {
      for (final p in parts) {
        await output.writeFrom(
          await File('${staging.path}/${p['hash']}.part').readAsBytes(),
        );
      }
      await output.flush();
    } finally {
      await output.close();
    }
    final bytes = await joined.readAsBytes();
    late LocalBook book;
    late Uint8List source;
    if (schema == 1) {
      (book, source) = await compute(decodeCloudBook, bytes);
    } else {
      source = bytes;
      if (!['txt', 'epub', 'pdf'].contains(manifest['format'])) {
        throw const CloudFailure('云书籍格式无效');
      }
      if (await compute(sourceHash, source) != id) {
        throw const CloudFailure('书籍原件校验失败');
      }
      status?.call('正在解析已下载书籍');
      final parsed = await BookImporter().parse(
        'book.${manifest['format']}',
        source,
      );
      book = LocalBook.fromJson(
        parsed.toJson()
          ..['title'] = manifest['title'] as String
          ..['author'] = manifest['author'] as String,
      );
    }
    if (book.id != id || await compute(sourceHash, source) != id) {
      throw const CloudFailure('书籍原件校验失败');
    }
    return (book, source, staging);
  }
}

Uint8List encodeCloudBook((LocalBook, Uint8List) input) {
  final metadata = input.$1.toJson()
    ..['section'] = 0
    ..['offset'] = 0
    ..['audioOffsetMs'] = 0;
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({'book': metadata, 'source': base64Encode(input.$2)}),
    ),
  );
}

(LocalBook, Uint8List) decodeCloudBook(Uint8List bytes) {
  final payload = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)));
  final metadata = Map<String, dynamic>.from(payload['book']);
  var book = LocalBook.fromJson(metadata);
  final source = base64Decode(payload['source']);
  if (book.format == 'epub' && (metadata['schema'] as int? ?? 1) < 3) {
    final corrected = parseTextBook(('original.epub', source));
    if (corrected.id == book.id) book = restoreBookPosition(book, corrected);
  }
  return (book, source);
}

String sourceHash(Uint8List bytes) => sha256.convert(bytes).toString();
List<Map<String, dynamic>> sourceParts((Uint8List, int) input) {
  final (bytes, size) = input;
  return [
    for (var i = 0; i < bytes.length; i += size)
      (() {
        final part = Uint8List.sublistView(
          bytes,
          i,
          (i + size).clamp(0, bytes.length),
        );
        final hash = sourceHash(part);
        return <String, dynamic>{
          'key': 'book-$hash-2000000000.part',
          'hash': hash,
          'size': part.length,
        };
      })(),
  ];
}

Future<T> _retry<T>(Future<T> Function() action) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await action();
    } catch (_) {
      if (attempt == 2) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 500 * (1 << attempt)));
    }
  }
}

Future<void> _parallel(
  int count,
  int workers,
  Future<void> Function(int) action,
) async {
  var index = 0;
  var failed = false;
  await Future.wait(
    List.generate(workers.clamp(1, count), (_) async {
      while (!failed && index < count) {
        final current = index++;
        try {
          await action(current);
        } catch (_) {
          failed = true;
          rethrow;
        }
      }
    }),
  );
}

class _TransferMeter {
  final String direction;
  final int completed, total;
  final void Function(String)? status;
  final watch = Stopwatch()..start();
  int transferred = 0, done = 0, lastUpdate = -1000;
  _TransferMeter(this.direction, this.completed, this.total, this.status);
  void add(int bytes) {
    transferred += bytes;
    reuse(bytes);
  }

  void reuse(int bytes) {
    done += bytes;
    if (watch.elapsedMilliseconds - lastUpdate < 250 && done < total) return;
    lastUpdate = watch.elapsedMilliseconds;
    final rate =
        transferred /
        (watch.elapsedMilliseconds.clamp(1, 1 << 40) / 1000) /
        1048576;
    status?.call(
      '$direction本地文件中，已$direction $completed 个文件 · '
      '${(done / 1048576).toStringAsFixed(1)}/${(total / 1048576).toStringAsFixed(1)} MB · ${rate.toStringAsFixed(2)} MB/s',
    );
  }
}

List<List<int>> _partGroups(List<Map<String, dynamic>> parts) {
  final groups = <String, List<int>>{};
  for (var i = 0; i < parts.length; i++) {
    (groups[parts[i]['hash'] as String] ??= []).add(i);
  }
  return groups.values.toList();
}
