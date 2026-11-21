import 'dart:convert';
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
        final bytes = await compute(encodeCloudBook, (book, source));
        final parts = <Map<String, dynamic>>[];
        for (
          var start = 0, index = 0;
          start < bytes.length;
          start += chunkSize, index++
        ) {
          final end = (start + chunkSize).clamp(0, bytes.length);
          final part = Uint8List.fromList(bytes.sublist(start, end));
          final partKey = 'book-${book.id}-$index.part';
          // Re-upload incomplete chunks, never trust a name without a committed hash.
          await cloud.write(partKey, part);
          if (yieldRequested?.call() == true) {
            result.deferred = true;
            return result;
          }
          parts.add({
            'key': partKey,
            'hash': sha256.convert(part).toString(),
            'size': part.length,
          });
        }
        await cloud.write(
          key,
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({'schema': 1, 'id': book.id, 'parts': parts}),
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
          utf8.encode(jsonEncode({...book.position(), 'device': deviceId})),
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
      final manifest = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(await cloud.read(key))),
      );
      final id = manifest['id'] as String;
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
          key != 'book-$id.manifest') {
        throw const CloudFailure('云书籍标识不匹配');
      }
      if (localIds.contains(id)) continue;
      status?.call('下载本地文件中，已下载 ${result.downloaded} 个文件');
      final parts = manifest['parts'] as List;
      if (parts.length > 1000) throw const CloudFailure('云文件块数过多');
      final builder = BytesBuilder(copy: false);
      var total = 0;
      for (var index = 0; index < parts.length; index++) {
        final part = parts[index];
        if (part['key'] != 'book-$id-$index.part') {
          throw const CloudFailure('云内容路径不匹配');
        }
        final bytes = await cloud.read(part['key']);
        if (yieldRequested?.call() == true) {
          result.deferred = true;
          return result;
        }
        total += bytes.length;
        if (total > 100 * 1024 * 1024 ||
            bytes.length != part['size'] ||
            sha256.convert(bytes).toString() != part['hash']) {
          throw const CloudFailure('私人云文件校验失败，本机内容未覆盖');
        }
        builder.add(bytes);
      }
      final (book, source) = await compute(
        decodeCloudBook,
        builder.takeBytes(),
      );
      if (book.id != id || sha256.convert(source).toString() != id) {
        throw const CloudFailure('书籍原件校验失败');
      }
      await library.source(id, source);
      await library.save(book);
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
      if (b == null) continue;
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
      await library.save(b);
      await cloud.write(
        'position-${b.id}-$deviceId.json',
        Uint8List.fromList(
          utf8.encode(jsonEncode({...b.position(), 'device': deviceId})),
        ),
      );
    }
    return result;
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
