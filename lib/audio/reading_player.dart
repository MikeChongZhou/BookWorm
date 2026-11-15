import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/local_book.dart';
import 'chapter_timeline.dart';
import 'file_audio_transport.dart';

abstract class SpeechEngine {
  Future<void> prepare();
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> rate(double rate);
  Future<void> voice(Map<String, String> voice);
  Future<List<Map<String, String>>> voices();
  void progress(void Function(int start, int end) callback);
}

abstract interface class SpeechResources {
  Future<void> close();
}

abstract interface class NextSpeech {
  int get chunkLimit;
  void nextText(String? text);
}

class DeviceSpeech implements SpeechEngine {
  final FlutterTts tts = FlutterTts();
  Completer<void>? _failure;
  @override
  Future<void> prepare() async {
    await tts.awaitSpeakCompletion(true);
    await tts.setLanguage('zh-CN');
    if (Platform.isIOS) {
      await tts.setSharedInstance(true);
      await tts.autoStopSharedSession(false);
      await tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
      ], IosTextToSpeechAudioMode.spokenAudio);
    }
    tts.setErrorHandler((message) {
      if (_failure != null && !_failure!.isCompleted) {
        _failure!.completeError(StateError(message));
      }
    });
  }

  @override
  Future<void> speak(String text) async {
    final failure = Completer<void>();
    _failure = failure;
    try {
      await Future.any<void>([
        tts.speak(text).then((result) {
          if (result == 0) throw StateError('系统语音未能播放，请检查语音资源');
        }),
        failure.future,
      ]);
    } finally {
      if (identical(_failure, failure)) _failure = null;
    }
  }

  @override
  Future<void> stop() async {
    if (_failure != null && !_failure!.isCompleted) _failure!.complete();
    await tts.stop();
  }

  @override
  Future<void> rate(double value) async {
    await tts.setSpeechRate(value);
  }

  @override
  Future<void> voice(Map<String, String> value) async {
    await tts.setVoice(value);
  }

  @override
  Future<List<Map<String, String>>> voices() async {
    final values = await tts.getVoices;
    if (values is! List) return [];
    return values
        .map(
          (v) => Map<String, String>.from(
            (v as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
          ),
        )
        .toList();
  }

  @override
  void progress(void Function(int, int) callback) {
    tts.setProgressHandler((text, start, end, word) => callback(start, end));
  }
}

class ReadingPlayer extends ChangeNotifier {
  final LocalBook book;
  final SpeechEngine engine;
  final Future<void> Function() persist;
  bool playing = false, ready = false, disposed = false, stopAtSection = false;
  bool buffering = false;
  String? error;
  double speed = .5;
  int _generation = 0, _base = 0, _spokenSection = -1;
  Timer? _sleep, _ticker;
  DateTime? sleepDeadline;
  final Map<int, ChapterTimeline> _timelines = {};
  final Stopwatch _clock = Stopwatch();
  Duration _within = Duration.zero;
  Future<void>? _initializing;
  Future<void> Function()? beforePlay;
  DateTime _lastSave = DateTime.now();
  ReadingPlayer(this.book, this.engine, this.persist) {
    engine.progress((start, end) {
      if (!playing || disposed || book.section != _spokenSection) return;
      if (!mediaClock) book.locate(book.section, _base + start);
      notifyListeners();
    });
    if (engine is SpeechTiming) {
      (engine as SpeechTiming).playbackProgress((position, duration) {
        if (!playing || disposed || book.section != _spokenSection) return;
        _within = position;
        book.audioOffsetMs = position.inMilliseconds;
        final span = timeline.chunkAt(_base);
        if (span.start == _base && duration > Duration.zero) {
          timeline.measured[_base] = duration;
        }
        buffering = false;
        notifyListeners();
      });
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!playing || disposed || buffering) return;
      if (!mediaClock) {
        _within = Duration(
          milliseconds: (_clock.elapsedMilliseconds * speed * 2).round(),
        );
      }
      if (DateTime.now().difference(_lastSave).inSeconds >= 5) {
        _lastSave = DateTime.now();
        unawaited(_save());
      }
      notifyListeners();
    });
  }
  bool get mediaClock =>
      engine is SpeechTiming && (engine as SpeechTiming).hasMediaClock;
  ChapterTimeline get timeline => _timelines.putIfAbsent(
    book.section,
    () => ChapterTimeline(book.sections[book.section].text),
  );
  Duration get duration => timeline.duration;
  bool get durationExact => timeline.exact;
  Duration get position {
    final base = (_spokenSection == book.section)
        ? timeline.timeAt(_base) + _within
        : timeline.timeAt(book.offset) +
              Duration(milliseconds: book.audioOffsetMs);
    return Duration(
      milliseconds: base.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
  }

  SpeechSpan get sentence => timeline.sentenceAt(book.offset);
  Future<void> _save() async {
    try {
      await persist();
    } catch (e) {
      error = '保存进度失败：$e';
      playing = false;
      unawaited(engine.stop());
    }
  }

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    await engine.prepare();
    await engine.rate(speed);
    ready = true;
  }

  static int chunkEnd(String text, int start, [int limit = 180]) {
    var end = (start + limit).clamp(0, text.length);
    if (end < text.length) {
      final cut = text.lastIndexOf(RegExp(r'[。！？；.!?\n]'), end - 1);
      if (cut > start + 30) end = cut + 1;
      final unit = text.codeUnitAt(end - 1);
      if (unit >= 0xd800 && unit <= 0xdbff) end--;
    }
    return end;
  }

  Future<void> play() async {
    if (playing || buffering || disposed) return;
    final generation = ++_generation;
    error = null;
    buffering = true;
    notifyListeners();
    try {
      if (!ready) await initialize();
      await beforePlay?.call();
      if (generation != _generation || disposed) return;
      playing = true;
      notifyListeners();
      while (playing && generation == _generation && !disposed) {
        final index = book.section, text = book.sections[index].text;
        if (book.offset >= text.length) {
          if (index == book.sections.length - 1 || stopAtSection) break;
          book.locate(index + 1, 0);
          _spokenSection = -1;
          await _save();
          notifyListeners();
          continue;
        }
        final start = book.offset;
        final end = timeline.chunkAt(start).end;
        if (end <= start) {
          book.locate(index, text.length);
          continue;
        }
        _base = start;
        _spokenSection = index;
        _within = Duration(milliseconds: book.audioOffsetMs);
        if (mediaClock) (engine as SpeechTiming).startPosition(_within);
        final utterance = text.substring(start, end);
        if (engine is NextSpeech) {
          final next = end < text.length
              ? text.substring(end, timeline.chunkAt(end).end)
              : null;
          (engine as NextSpeech).nextText(next);
        }
        buffering = mediaClock;
        _clock
          ..reset()
          ..start();
        notifyListeners();
        if (utterance.trim().isNotEmpty) await engine.speak(utterance);
        if (generation != _generation || disposed) return;
        _clock.stop();
        if (!mediaClock && timeline.chunkAt(start).start == start) {
          timeline.measured[start] = Duration(
            milliseconds: (_clock.elapsedMilliseconds * speed * 2).round(),
          );
        }
        book.locate(index, end);
        _within = Duration.zero;
        _spokenSection = -1;
        if (DateTime.now().difference(_lastSave).inSeconds >= 5) {
          _lastSave = DateTime.now();
          await _save();
        }
        notifyListeners();
      }
    } catch (e) {
      if (generation == _generation && !disposed) {
        error = '听书失败：$e';
      }
    }
    if (generation == _generation && !disposed) {
      playing = false;
      buffering = false;
      _clock.stop();
      await _save();
      notifyListeners();
    }
  }

  Future<void> pause() async {
    _generation++;
    playing = false;
    buffering = false;
    _clock.stop();
    if (_spokenSection == book.section && mediaClock) {
      book.audioOffsetMs = _within.inMilliseconds;
    }
    await engine.stop();
    await _save();
    if (!disposed) notifyListeners();
  }

  Future<void> seek(int section, int offset) async {
    final resume = playing || buffering;
    await pause();
    book.locate(section, offset);
    _spokenSection = -1;
    _within = Duration.zero;
    await _save();
    if (!disposed) notifyListeners();
    if (resume) unawaited(play());
  }

  Future<void> seekTime(Duration target) async {
    final resume = playing || buffering;
    final time = Duration(
      milliseconds: target.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    final (span, within) = timeline.atTime(time);
    await pause();
    book.locate(book.section, span.start);
    if (mediaClock) {
      book.audioOffsetMs = within.inMilliseconds;
    } else if (span.end > span.start) {
      final ratio =
          within.inMilliseconds / timeline.lengthOf(span).inMilliseconds;
      book.locate(
        book.section,
        span.start + ((span.end - span.start) * ratio).floor(),
      );
    }
    _spokenSection = -1;
    _within = Duration.zero;
    await _save();
    if (!disposed) notifyListeners();
    if (resume) unawaited(play());
  }

  Future<void> jump(int seconds) =>
      seekTime(position + Duration(seconds: seconds));
  Future<void> setSpeed(double value) async {
    final resume = playing || buffering;
    await pause();
    speed = value;
    await initialize();
    await engine.rate(speed);
    if (!disposed) notifyListeners();
    if (resume) unawaited(play());
  }

  Future<void> setVoice(Map<String, String> value) async {
    final resume = playing || buffering;
    await pause();
    await initialize();
    await engine.voice(value);
    _timelines.clear();
    if (resume) unawaited(play());
  }

  void sleep(int minutes) {
    _sleep?.cancel();
    sleepDeadline = minutes == 0
        ? null
        : DateTime.now().add(Duration(minutes: minutes));
    if (minutes > 0) {
      _sleep = Timer(Duration(minutes: minutes), () {
        sleepDeadline = null;
        unawaited(pause());
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    playing = false;
    _generation++;
    _sleep?.cancel();
    _ticker?.cancel();
    _clock.stop();
    if (engine is SpeechResources) {
      unawaited((engine as SpeechResources).close());
    } else {
      unawaited(engine.stop());
    }
    super.dispose();
  }
}
