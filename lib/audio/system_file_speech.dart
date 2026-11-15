import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import 'reading_player.dart';
import 'file_audio_transport.dart';

/// iOS/Android system voices are rendered to real audio so lock-screen seeking
/// and pausing use an audio clock rather than wall-clock guesses.
class SystemFileSpeech extends DeviceSpeech
    implements SpeechResources, NextSpeech, SpeechTiming {
  final FileAudioTransport transport = FileAudioTransport();
  static const _native = MethodChannel('bookworm/system_speech');
  Map<String, String>? _voice;
  final Map<String, Future<String>> _cache = {};
  Future<void> _queue = Future.value();
  Directory? _directory;
  String? _next;
  int _number = 0, _generation = 0;
  bool _closed = false;
  void Function(int, int)? _callback;
  @override
  bool get hasMediaClock => true;
  @override
  int get chunkLimit => 160;
  @override
  Future<void> prepare() async {
    await super.prepare();
    await tts.awaitSynthCompletion(true);
    // Cache at normal rate; playback rate is applied by the audio player.
    await tts.setSpeechRate(.5);
    _directory = await (await getTemporaryDirectory()).createTemp(
      'system-speech-',
    );
    await transport.prepare();
  }

  Future<String> _generate(String text) => _cache.putIfAbsent(text, () {
    final path = '${_directory!.path}/${++_number}.wav';
    final task = _queue.catchError((_) {}).then((_) async {
      if (_closed) throw StateError('语音已关闭');
      final result = Platform.isIOS
          ? await _native
                .invokeMethod<int>('render', {
                  'text': text,
                  'path': path,
                  'voice': _voice,
                })
                .timeout(const Duration(seconds: 45))
          : await tts.synthesizeToFile(text, path, true);
      if (result == 0 ||
          !await File(path).exists() ||
          await File(path).length() < 44) {
        throw StateError('系统音色无法生成离线音频，请更换音色');
      }
      return path;
    });
    _queue = task.then<void>((_) {}).catchError((Object _) {});
    return task;
  });
  @override
  void nextText(String? text) => _next = text;
  @override
  void progress(void Function(int, int) callback) => _callback = callback;
  @override
  void playbackProgress(void Function(Duration, Duration) callback) =>
      transport.progress = callback;
  @override
  void startPosition(Duration position) => transport.start = position;
  @override
  Future<void> speak(String text) async {
    final generation = _generation;
    final path = await _generate(text);
    if (generation != _generation || _closed) return;
    for (final key
        in _cache.keys.where((s) => s != text && s != _next).toList()) {
      final obsolete = _cache.remove(key)!;
      unawaited(
        obsolete
            .then((path) async {
              final f = File(path);
              if (await f.exists()) await f.delete();
            })
            .catchError((Object _) {}),
      );
    }
    _callback?.call(0, text.length);
    await transport.play(
      path,
      prefetch: () {
        final next = _next;
        if (next != null && next.trim().isNotEmpty) {
          unawaited(
            _generate(next).then<void>((_) {}).catchError((Object _) {}),
          );
        }
      },
    );
  }

  @override
  Future<void> stop() async {
    _generation++;
    await transport.stop();
  }

  @override
  Future<void> rate(double value) async =>
      transport.speed = (value * 2).clamp(.5, 2);
  @override
  Future<void> voice(Map<String, String> value) async {
    await _queue;
    await super.voice(value);
    _voice = value;
    _cache.clear();
  }

  @override
  Future<void> close() async {
    _closed = true;
    await stop();
    await _queue;
    await tts.stop();
    await transport.close();
    if (_directory != null && await _directory!.exists()) {
      await _directory!.delete(recursive: true);
    }
  }
}
