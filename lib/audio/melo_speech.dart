import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'melo_model.dart';
import 'reading_player.dart';
import 'file_audio_transport.dart';
import 'system_file_speech.dart';

/// Native inference stays on a long-lived isolate, never on the UI thread.
class MeloSpeech
    implements SpeechEngine, SpeechResources, NextSpeech, SpeechTiming {
  final FileAudioTransport _transport = FileAudioTransport();
  final Map<int, Completer<String>> _pending = {};
  final Map<String, Future<String>> _cache = {};
  ReceivePort? _receive;
  Isolate? _isolate;
  SendPort? _worker;
  Directory? _temporary;
  Future<void>? _preparing;
  void Function(int, int)? _progress;
  String? _next;
  int _sequence = 0, _generation = 0;
  bool _closed = false;

  @override
  Future<void> prepare() => _preparing ??= _prepare();
  Future<void> _prepare() async {
    await MeloModel.instance.load();
    if (!MeloModel.instance.installed) {
      throw StateError('请先在设置中下载 Melo 离线语音');
    }
    if (_closed) throw StateError('语音已关闭');
    _temporary = await (await getTemporaryDirectory()).createTemp(
      'melo-audio-',
    );
    final ready = Completer<void>();
    _receive = ReceivePort();
    _receive!.listen((dynamic message) {
      if (message is SendPort) {
        _worker = message;
        ready.complete();
      } else if (message is List && message[0] == -1) {
        if (!ready.isCompleted) ready.completeError(StateError(message[2]));
      } else if (message is List) {
        final pending = _pending.remove(message[0]);
        if (message[1] == true) {
          pending?.complete(message[2] as String);
        } else {
          pending?.completeError(StateError(message[2]));
        }
      }
    });
    _isolate = await Isolate.spawn(meloWorker, [
      _receive!.sendPort,
      await MeloModel.instance.path,
    ]);
    await ready.future.timeout(const Duration(seconds: 90));
    if (_closed) throw StateError('语音已关闭');
    await _transport.prepare();
  }

  @override
  bool get hasMediaClock => true;
  @override
  void playbackProgress(void Function(Duration, Duration) callback) =>
      _transport.progress = callback;
  @override
  void startPosition(Duration position) => _transport.start = position;

  Future<String> _generate(String text) {
    return _cache.putIfAbsent(text, () {
      final id = ++_sequence;
      final completion = Completer<String>();
      _pending[id] = completion;
      _worker!.send([id, text, '${_temporary!.path}/$id.wav']);
      return completion.future;
    });
  }

  @override
  int get chunkLimit => 80;
  @override
  void nextText(String? text) => _next = text;

  @override
  Future<void> speak(String text) async {
    await prepare();
    final generation = _generation;
    final file = await _generate(text);
    if (_closed || generation != _generation) return;
    // Keep the current and next chunks only. Files are local, temporary audio.
    final obsolete = _cache.keys.where((k) => k != text && k != _next).toList();
    for (final key in obsolete) {
      final cached = _cache.remove(key)!;
      unawaited(
        cached
            .then((p) async {
              final f = File(p);
              if (await f.exists()) await f.delete();
            })
            .catchError((Object _) {}),
      );
    }
    _progress?.call(0, text.length);
    await _transport.play(
      file,
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
    await _transport.stop();
  }

  @override
  Future<void> rate(double rate) async =>
      _transport.speed = (rate * 2).clamp(.5, 2);
  @override
  Future<void> voice(Map<String, String> voice) async {}
  @override
  Future<List<Map<String, String>>> voices() async => [
    {'name': 'Melo · 中文 / English', 'locale': 'zh-CN / en-US'},
  ];
  @override
  void progress(void Function(int, int) callback) => _progress = callback;

  @override
  Future<void> close() async {
    _closed = true;
    await stop();
    // Loading and queued inference must settle before releasing their files.
    try {
      await _preparing;
    } catch (_) {}
    if (_worker != null) {
      final id = ++_sequence;
      final released = Completer<String>();
      _pending[id] = released;
      _worker!.send([id, null]);
      await released.future;
    }
    _isolate?.kill(priority: Isolate.immediate);
    _receive?.close();
    for (final completer in _pending.values) {
      completer.completeError(StateError('语音已关闭'));
    }
    _pending.clear();
    await _transport.close();
    if (_temporary != null && await _temporary!.exists()) {
      await _temporary!.delete(recursive: true);
    }
  }
}

void meloWorker(List<dynamic> args) {
  final output = args[0] as SendPort;
  final path = args[1] as String;
  try {
    sherpa.initBindings(args.length > 2 ? args[2] as String : null);
    final tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: '$path/model.onnx',
            lexicon: '$path/lexicon.txt',
            tokens: '$path/tokens.txt',
            dictDir: '$path/dict',
          ),
          numThreads: 2,
          provider: 'cpu',
        ),
        ruleFsts: [
          'date',
          'number',
          'phone',
        ].map((r) => '$path/$r.fst').join(','),
        maxNumSentences: 1,
      ),
    );
    final incoming = ReceivePort();
    incoming.listen((dynamic message) {
      final id = message[0] as int;
      if (message[1] == null) {
        tts.free();
        output.send([id, true, 'closed']);
        incoming.close();
        return;
      }
      try {
        final audio = tts.generate(
          text: message[1] as String,
          sid: 0,
          speed: 1,
        );
        if (audio.samples.isEmpty ||
            !sherpa.writeWave(
              filename: message[2] as String,
              samples: audio.samples,
              sampleRate: audio.sampleRate,
            )) {
          throw StateError('Melo 未能生成音频');
        }
        output.send([id, true, message[2]]);
      } catch (e) {
        output.send([id, false, e.toString()]);
      }
    });
    output.send(incoming.sendPort);
  } catch (e) {
    output.send([-1, false, e.toString()]);
  }
}

class SelectedSpeech
    implements SpeechEngine, SpeechResources, NextSpeech, SpeechTiming {
  SpeechEngine? _engine;
  Future<void>? _preparing;
  bool _closed = false;
  void Function(int, int)? _callback;
  void Function(Duration, Duration)? _timing;
  @override
  Future<void> prepare() => _preparing ??= _prepare();
  Future<void> _prepare() async {
    await MeloModel.instance.load();
    if (_closed) throw StateError('语音已关闭');
    final engine = MeloModel.instance.selected == 'melo'
        ? MeloSpeech()
        : (Platform.isIOS || Platform.isAndroid
              ? SystemFileSpeech()
              : DeviceSpeech());
    _engine = engine;
    if (_callback != null) engine.progress(_callback!);
    if (_timing != null && engine is SpeechTiming) {
      (engine as SpeechTiming).playbackProgress(_timing!);
    }
    await engine.prepare();
  }

  @override
  bool get hasMediaClock =>
      _engine is SpeechTiming && (_engine as SpeechTiming).hasMediaClock;
  @override
  void playbackProgress(void Function(Duration, Duration) callback) {
    _timing = callback;
    final engine = _engine;
    if (engine is SpeechTiming) {
      (engine as SpeechTiming).playbackProgress(callback);
    }
  }

  @override
  void startPosition(Duration position) {
    final engine = _engine;
    if (engine is SpeechTiming) {
      (engine as SpeechTiming).startPosition(position);
    }
  }

  @override
  Future<void> speak(String text) async {
    await prepare();
    await _engine!.speak(text);
  }

  @override
  Future<void> stop() async => _engine?.stop();
  @override
  Future<void> rate(double value) async {
    await prepare();
    await _engine!.rate(value);
  }

  @override
  Future<void> voice(Map<String, String> value) async {
    await prepare();
    await _engine!.voice(value);
  }

  @override
  Future<List<Map<String, String>>> voices() async {
    await prepare();
    return _engine!.voices();
  }

  @override
  void progress(void Function(int, int) callback) {
    _callback = callback;
    _engine?.progress(callback);
  }

  @override
  int get chunkLimit => _engine is MeloSpeech ? 80 : 180;
  @override
  void nextText(String? text) {
    final engine = _engine;
    if (engine is NextSpeech) (engine as NextSpeech).nextText(text);
  }

  @override
  Future<void> close() async {
    _closed = true;
    try {
      await _preparing;
    } catch (_) {}
    final engine = _engine;
    if (engine is SpeechResources) {
      await (engine as SpeechResources).close();
    } else {
      await engine?.stop();
    }
  }
}
