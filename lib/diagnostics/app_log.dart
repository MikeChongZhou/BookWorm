import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Private, bounded diagnostic metadata. Never pass exception messages,
/// book content, paths, URLs, account identifiers or credentials here.
class AppLog {
  static final instance = AppLog();
  final Future<Directory> Function() directory;
  final int maxBytes, archives;
  Future<void> _tail = Future.value();
  Directory? _folder;
  int _pending = 0, _dropped = 0;
  bool failed = false;
  static const allowedFields = {
    'request',
    'provider',
    'model',
    'background',
    'attempt',
    'attempts',
    'http',
    'elapsedMs',
    'waitMs',
    'status',
    'code',
    'type',
    'providerRequestId',
    'automatic',
    'uploaded',
    'downloaded',
    'platform',
    'version',
    'build',
    'errorType',
    'reason',
    'dropped',
  };

  AppLog({
    Future<Directory> Function()? directory,
    this.maxBytes = 1024 * 1024,
    this.archives = 3,
  }) : directory = directory ?? getApplicationSupportDirectory;

  Future<Directory> _directory() async =>
      _folder ??= await Directory('${(await directory()).path}/logs')
          .create(recursive: true);

  Future<String> get path async => (await _directory()).path;

  void record(
    String scope,
    String event, {
    Map<String, Object?> fields = const {},
  }) {
    if (_pending >= 200) {
      _dropped++;
      return;
    }
    final data = <String, Object?>{
      'time': DateTime.now().toUtc().toIso8601String(),
      'scope': _safe(scope),
      'event': _safe(event),
      for (final entry in fields.entries)
        if (allowedFields.contains(entry.key))
          entry.key: entry.value is num || entry.value is bool
              ? entry.value
              : _safe(entry.value?.toString() ?? 'unspecified'),
      if (_dropped > 0) 'dropped': _dropped,
    };
    _dropped = 0;
    _pending++;
    _tail = _tail.then((_) async {
      try {
        final folder = await _directory();
        final file = File('${folder.path}/bookworm.log');
        final line = '${jsonEncode(data)}\n';
        if (await file.exists() &&
            await file.length() + utf8.encode(line).length > maxBytes) {
          final oldest = File('${file.path}.$archives');
          if (await oldest.exists()) await oldest.delete();
          for (var i = archives - 1; i >= 1; i--) {
            final previous = File('${file.path}.$i');
            if (await previous.exists()) {
              await previous.rename('${file.path}.${i + 1}');
            }
          }
          await file.rename('${file.path}.1');
        }
        await file.writeAsString(line, mode: FileMode.append, flush: true);
        failed = false;
      } catch (_) {
        // Disk full/permissions must never interrupt reading or listening.
        failed = true;
      } finally {
        _pending--;
      }
    });
  }

  static String _safe(String value) {
    if (value.length > 160 ||
        !RegExp(r'^[A-Za-z0-9._:/() -]*$').hasMatch(value) ||
        RegExp(
          r'(?:sk-|AIza|Bearer|://|@)',
          caseSensitive: false,
        ).hasMatch(value)) {
      return '[redacted]';
    }
    return value;
  }

  Future<void> flush() => _tail;

  /// Snapshot is serialized with writes; export does not race log rotation.
  Future<Uint8List> export() {
    final result = Completer<Uint8List>();
    _tail = _tail.then((_) async {
      try {
        final folder = await _directory();
        final bytes = BytesBuilder();
        bytes.add(
          utf8.encode('BookWorm diagnostic log (UTC; metadata only)\n'),
        );
        for (var i = archives; i >= 0; i--) {
          final file = File(
            '${folder.path}/bookworm.log${i == 0 ? '' : '.$i'}',
          );
          if (await file.exists()) bytes.add(await file.readAsBytes());
        }
        if (failed) {
          throw FileSystemException('Diagnostic log could not be saved');
        }
        result.complete(bytes.takeBytes());
      } catch (e, s) {
        result.completeError(e, s);
      }
    });
    return result.future;
  }
}
