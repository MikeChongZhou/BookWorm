import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/local_book.dart';

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
  String? error;
  double speed = .5;
  int _generation = 0, _base = 0, _spokenSection = 0;
  Timer? _sleep;
  DateTime? sleepDeadline;
  ReadingPlayer(this.book, this.engine, this.persist) {
    engine.progress((start, end) {
      if (!playing || disposed || book.section != _spokenSection) return;
      book.locate(book.section, _base + start);
      notifyListeners();
    });
  }
  Future<void> _save() async {
    try {
      await persist();
    } catch (e) {
      error = '保存进度失败：$e';
      playing = false;
    }
  }

  Future<void> initialize() async {
    await engine.prepare();
    await engine.rate(speed);
    ready = true;
  }

  static int chunkEnd(String text, int start, [int limit = 180]) {
    var end = (start + limit).clamp(0, text.length);
    if (end < text.length) {
      final cut = text.lastIndexOf(RegExp(r'[。！？；.!?\n]'), end - 1);
      if (cut > start + 30) end = cut + 1;
      if (text.codeUnitAt(end - 1) >= 0xD800 &&
          text.codeUnitAt(end - 1) <= 0xDBFF) {
        end--;
      }
    }
    return end;
  }

  Future<void> play() async {
    if (playing || disposed) return;
    final generation = ++_generation;
    error = null;
    try {
      if (!ready) await initialize();
      if (generation != _generation || disposed) return;
      playing = true;
      notifyListeners();
      while (playing && generation == _generation && !disposed) {
        final index = book.section, text = book.sections[index].text;
        if (book.offset >= text.length) {
          if (index == book.sections.length - 1 || stopAtSection) {
            playing = false;
            break;
          }
          book.locate(index + 1, 0);
          await _save();
          notifyListeners();
          continue;
        }
        final limit = engine is NextSpeech
            ? (engine as NextSpeech).chunkLimit
            : 180;
        final start = book.offset, end = chunkEnd(text, start, limit);
        _base = start;
        _spokenSection = index;
        final utterance = text.substring(start, end);
        if (engine is NextSpeech) {
          final next = end < text.length
              ? text.substring(end, chunkEnd(text, end, limit))
              : null;
          (engine as NextSpeech).nextText(next);
        }
        if (utterance.trim().isNotEmpty) await engine.speak(utterance);
        if (generation != _generation || disposed) return;
        book.locate(index, end);
        await _save();
        notifyListeners();
      }
    } catch (e) {
      if (generation == _generation && !disposed) {
        error = '听书失败：$e';
        playing = false;
      }
    }
    if (generation == _generation && !disposed) {
      playing = false;
      await _save();
      notifyListeners();
    }
  }

  Future<void> pause() async {
    _generation++;
    playing = false;
    await engine.stop();
    await _save();
    if (!disposed) notifyListeners();
  }

  Future<void> seek(int section, int offset) async {
    final resume = playing;
    await pause();
    book.locate(section, offset);
    await _save();
    if (!disposed) notifyListeners();
    if (resume) unawaited(play());
  }

  Future<void> setSpeed(double value) async {
    final resume = playing;
    await pause();
    speed = value;
    await engine.rate(speed);
    if (!disposed) notifyListeners();
    if (resume) unawaited(play());
  }

  Future<void> setVoice(Map<String, String> value) async {
    final resume = playing;
    await pause();
    await engine.voice(value);
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
    if (engine is SpeechResources) {
      unawaited((engine as SpeechResources).close());
    } else {
      unawaited(engine.stop());
    }
    super.dispose();
  }
}
