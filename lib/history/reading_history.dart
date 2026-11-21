import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_book.dart';

class ReadingRecord {
  int milliseconds;
  bool started, completed;
  ReadingRecord({
    this.milliseconds = 0,
    this.started = false,
    this.completed = false,
  });
  Map<String, dynamic> toJson() => {
    'ms': milliseconds,
    'started': started,
    'completed': completed,
  };
}

/// Local history is separate from book content and synced reading positions.
class ReadingHistory extends ChangeNotifier {
  static final instance = ReadingHistory();
  static const key = 'bookworm_reading_history_v1';
  final Map<String, ReadingRecord> records = {};
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Timer? _flush;
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final json =
          jsonDecode(prefs.getString(key) ?? '{}') as Map<String, dynamic>;
      for (final entry in json.entries) {
        final value = entry.value as Map<String, dynamic>;
        final pending = records[entry.key];
        records[entry.key] = ReadingRecord(
          milliseconds:
              ((value['ms'] as num?)?.toInt() ?? 0).clamp(0, 1 << 53) +
              (pending?.milliseconds ?? 0),
          started: value['started'] == true || pending?.started == true,
          completed: pending?.completed ?? (value['completed'] == true),
        );
      }
    } catch (_) {
      /* Keep the library usable if history is damaged. */
    }
    notifyListeners();
  }

  ReadingRecord record(LocalBook book) =>
      records[book.id] ??
      ReadingRecord(
        started: book.section > 0 || book.offset > 0 || book.audioOffsetMs > 0,
      );
  void add(LocalBook book, Duration duration) {
    if (duration <= Duration.zero) return;
    final r = records.putIfAbsent(book.id, () => ReadingRecord());
    r.started = true;
    r.milliseconds += duration.inMilliseconds;
    _changed();
  }

  void complete(LocalBook book, {bool value = true}) {
    final r = records.putIfAbsent(book.id, () => ReadingRecord());
    r.started = true;
    r.completed = value;
    _changed();
    unawaited(save());
  }

  void _changed() {
    notifyListeners();
    _flush ??= Timer(const Duration(seconds: 5), () {
      _flush = null;
      unawaited(save());
    });
  }

  Future<void> save() {
    _flush?.cancel();
    _flush = null;
    final data = jsonEncode(records.map((id, r) => MapEntry(id, r.toJson())));
    _writes = _writes.catchError((Object _) {}).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, data);
    });
    return _writes;
  }
}
