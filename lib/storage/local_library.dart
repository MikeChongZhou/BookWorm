import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_book.dart';

class LocalLibrary {
  final Directory root;
  final List<String> warnings = [];
  Future<void> _queue = Future.value();
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

  Future<void> save(LocalBook b) => serialized(
    () =>
        _atomic(File(_path(b.id, 'json')), utf8.encode(jsonEncode(b.toJson()))),
  );
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
    final result = <LocalBook>[];
    await for (final e in root.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        result.add(
          LocalBook.fromJson(
            Map<String, dynamic>.from(jsonDecode(await e.readAsString())),
          ),
        );
      } catch (_) {
        warnings.add('无法读取 ${e.uri.pathSegments.last}，文件已保留');
      }
    }
    result.sort((a, b) => b.modified.compareTo(a.modified));
    return result;
  }

  Future<void> remove(LocalBook b) => serialized(() async {
    for (final suffix in ['json', 'source', 'json.bak', 'source.bak']) {
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
