import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import '../models/local_book.dart';
import '../importing/book_importer.dart';

class LocalLibrary {
  final Directory root;
  final List<String> warnings = [];
  Future<void> _queue = Future.value();
  final Map<String, List<BookSection>> _savedContents = {};
  LocalLibrary(this.root);
  static Future<LocalLibrary> open() async {
    final base = await getApplicationSupportDirectory();
    final store = LocalLibrary(Directory('${base.path}/BookWorm'));
    await store.root.create(recursive: true);
    await store.migrate();
    return store;
  }

  String _path(String id, String suffix) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
      throw const FormatException('无效书籍标识');
    }
    return '${root.path}/$id.$suffix';
  }

  Future<void> _atomic(File file, List<int> data) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(data, flush: true);
    final backup = File('${file.path}.bak');
    if (await file.exists()) await file.copy(backup.path);
    if (Platform.isWindows && await file.exists()) await file.delete();
    await temp.rename(file.path);
    if (await backup.exists()) await backup.delete();
  }

  Future<void> serialized(Future<void> Function() action) {
    final task = _queue.catchError((_) {}).then((_) => action());
    _queue = task;
    return task;
  }

  Future<void> save(LocalBook b, {bool contentChanged = false}) {
    final position = utf8.encode(jsonEncode(b.position()));
    return serialized(() async {
      if (contentChanged || !identical(_savedContents[b.id], b.sections)) {
        final payload = b.toJson();
        final bytes = await compute(encodeBook, payload);
        await _atomic(File(_path(b.id, 'json')), bytes);
        _savedContents[b.id] = b.sections;
      }
      await _atomic(File(_path(b.id, 'position')), position);
    });
  }

  Future<void> source(String id, Uint8List bytes) =>
      serialized(() => _atomic(File(_path(id, 'source')), bytes));
  Future<Uint8List> readSource(String id) =>
      File(_path(id, 'source')).readAsBytes();
  Future<List<LocalBook>> load() async {
    await root.create(recursive: true);
    warnings.clear();
    // Recover only interrupted replacements; never silently discard damaged data.
    await for (final entity in root.list()) {
      if (entity is File && entity.path.endsWith('.json.bak')) {
        final original = File(entity.path.substring(0, entity.path.length - 4));
        if (!await original.exists()) await entity.copy(original.path);
      }
    }
    final (result, issues, migrated) = await compute(readBooks, root.path);
    warnings.addAll(issues);
    for (final book in result) {
      _savedContents[book.id] = book.sections;
      if (migrated.contains(book.id)) await save(book, contentChanged: true);
    }
    result.sort((a, b) => b.modified.compareTo(a.modified));
    return result;
  }

  Future<void> remove(LocalBook b) => serialized(() async {
    _savedContents.remove(b.id);
    for (final suffix in [
      'json',
      'source',
      'position',
      'json.bak',
      'source.bak',
      'position.bak',
    ]) {
      final f = File(_path(b.id, suffix));
      if (await f.exists()) await f.delete();
    }
  });
  Future<void> migrate() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('bookworm_migrated') == true) return;
    final raw = prefs.getString('books');
    if (raw != null) {
      final old = jsonDecode(raw) as List;
      for (final entry in old) {
        final j = Map<String, dynamic>.from(entry);
        final text = j['text'] as String;
        final id = sha256.convert(utf8.encode(text)).toString();
        if (await File(_path(id, 'json')).exists()) continue;
        final b = LocalBook(
          id: id,
          title: j['title'],
          author: j['author'],
          format: 'txt',
          sections: [BookSection('正文', text)],
        );
        b.offset = (text.length * ((j['progress'] as num?)?.toDouble() ?? 0))
            .floor()
            .clamp(0, text.length);
        await source(id, Uint8List.fromList(utf8.encode(text)));
        await save(b);
      }
    }
    // Keep legacy notes intact for later migration; no automatic deletion of user data.
    await prefs.setBool('bookworm_migrated', true);
  }
}

Uint8List encodeBook(Map<String, dynamic> value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

(List<LocalBook>, List<String>, Set<String>) readBooks(String folder) {
  final books = <LocalBook>[], issues = <String>[], migrated = <String>{};
  for (final entity in Directory(folder).listSync()) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    try {
      final json = Map<String, dynamic>.from(
        jsonDecode(entity.readAsStringSync()),
      );
      final id = json['id'] as String;
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
        throw const FormatException('无效书籍标识');
      }
      final position = File('$folder/$id.position');
      final backup = File('$folder/$id.position.bak');
      final saved = position.existsSync() ? position : backup;
      if (saved.existsSync()) {
        try {
          final p = Map<String, dynamic>.from(
            jsonDecode(saved.readAsStringSync()),
          );
          if (p['id'] == id) {
            for (final key in [
              'section',
              'offset',
              'modified',
              'audioOffsetMs',
            ]) {
              if (p.containsKey(key)) json[key] = p[key];
            }
          }
        } catch (_) {
          issues.add('阅读进度文件损坏，已保留书籍与原进度');
        }
      }
      var book = LocalBook.fromJson(json);
      if ((json['schema'] as int? ?? 1) < 3) {
        book = mergeLegacySections(book);
        final original = File('$folder/$id.source');
        if (book.format == 'epub' && original.existsSync()) {
          try {
            final corrected = parseTextBook((
              'original.epub',
              original.readAsBytesSync(),
            ));
            if (corrected.id == book.id) {
              book = restoreBookPosition(book, corrected);
            }
          } catch (_) {
            /* A damaged original must never discard readable saved text. */
          }
        }
        migrated.add(book.id);
      }
      books.add(book);
    } catch (_) {
      issues.add('无法读取 ${entity.uri.pathSegments.last}，文件已保留');
    }
  }
  return (books, issues, migrated);
}

LocalBook restoreBookPosition(LocalBook previous, LocalBook corrected) {
  final oldText = previous.sections[previous.section].text;
  final start = previous.offset.clamp(0, oldText.length);
  final anchorStart = (start - 24).clamp(0, oldText.length);
  final anchor = oldText.substring(
    anchorStart,
    (start + 40).clamp(0, oldText.length),
  );
  final relative = start - anchorStart;
  var section = corrected.sections.indexWhere(
    (s) => s.title == previous.sections[previous.section].title,
  );
  var offset = 0;
  if (anchor.trim().isNotEmpty) {
    if (section >= 0) offset = corrected.sections[section].text.indexOf(anchor);
    if (section < 0 || offset < 0) {
      section = corrected.sections.indexWhere((s) => s.text.contains(anchor));
      if (section >= 0) {
        offset = corrected.sections[section].text.indexOf(anchor);
      }
    }
    if (offset >= 0) offset += relative;
  }
  if (section < 0) {
    section = previous.section.clamp(0, corrected.sections.length - 1);
  }
  if (offset < 0) {
    offset = previous.offset.clamp(0, corrected.sections[section].text.length);
  }
  return LocalBook(
    id: previous.id,
    title: previous.title,
    author: previous.author,
    format: previous.format,
    sections: corrected.sections,
    cover: corrected.cover ?? previous.cover,
    section: section,
    offset: offset,
    modified: previous.modified,
    audioOffsetMs: previous.audioOffsetMs,
  );
}

LocalBook mergeLegacySections(LocalBook book) {
  if (book.format == 'pdf') return book;
  final sections = <BookSection>[];
  var section = 0, offset = 0;
  for (var i = 0; i < book.sections.length; i++) {
    final current = book.sections[i];
    final match = RegExp(r'^(.*) · (\d+)$').firstMatch(current.title);
    final continuation =
        match != null && sections.isNotEmpty && sections.last.title == match[1];
    final base = continuation ? sections.last.text.length + 2 : 0;
    if (continuation) {
      sections[sections.length - 1] = BookSection(
        sections.last.title,
        '${sections.last.text}\n\n${current.text}',
      );
    } else {
      sections.add(current);
    }
    if (i == book.section) {
      section = sections.length - 1;
      offset = base + book.offset;
    }
  }
  return LocalBook(
    id: book.id,
    title: book.title,
    author: book.author,
    format: book.format,
    sections: sections,
    cover: book.cover,
    section: section,
    offset: offset,
    modified: book.modified,
    audioOffsetMs: book.audioOffsetMs,
  );
}
