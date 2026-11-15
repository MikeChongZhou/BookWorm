import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

abstract interface class SpeechTiming {
  bool get hasMediaClock;
  void playbackProgress(
    void Function(Duration position, Duration duration) callback,
  );
  void startPosition(Duration position);
}

/// One media clock for rendered system speech and Melo speech, including resume.
class FileAudioTransport {
  final AudioPlayer player = AudioPlayer();
  Completer<void>? _done;
  StreamSubscription<void>? _completed;
  StreamSubscription<Duration>? _position;
  void Function(Duration, Duration)? progress;
  Duration start = Duration.zero, _duration = Duration.zero;
  double speed = 1;
  int _generation = 0;
  bool closed = false;
  Future<void> prepare() async {
    // Flutter frame callbacks stop when the screen is locked. The media clock
    // must keep polling native playback independently of UI frames.
    player.positionUpdater = TimerPositionUpdater(
      getPosition: () async {
        try {
          return await player.getCurrentPosition();
        } catch (e, stack) {
          _fail(e, stack);
          return null;
        }
      },
      interval: const Duration(milliseconds: 250),
    );
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
        android: const AudioContextAndroid(
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
    _completed = player.onPlayerComplete.listen((_) {
      progress?.call(_duration, _duration);
      if (_done?.isCompleted == false) _done!.complete();
    }, onError: _fail);
    _position = player.onPositionChanged.listen((p) {
      if (_duration > Duration.zero) progress?.call(p, _duration);
    }, onError: _fail);
  }

  void _fail(Object error, StackTrace stack) {
    if (!closed && _done?.isCompleted == false) {
      _done!.completeError(error, stack);
    }
  }

  Future<void> play(String file, {void Function()? prefetch}) async {
    if (closed) return;
    final generation = _generation;
    final done = Completer<void>();
    // Source errors can arrive before the caller reaches the completion await.
    unawaited(done.future.catchError((Object _) {}));
    _done = done;
    try {
      _duration = Duration.zero;
      await player.setSource(DeviceFileSource(file));
      if (generation != _generation || closed) return;
      _duration = await player.getDuration() ?? Duration.zero;
      final position = Duration(
        milliseconds: start.inMilliseconds.clamp(0, _duration.inMilliseconds),
      );
      start = Duration.zero;
      await player.setPlaybackRate(speed);
      if (position > Duration.zero) await player.seek(position);
      if (generation != _generation || closed) return;
      await player.resume();
      if (generation != _generation || closed) {
        await player.stop();
        return;
      }
      progress?.call(position, _duration);
      prefetch?.call();
      await done.future;
    } finally {
      if (identical(_done, done)) _done = null;
    }
  }

  Future<void> stop() async {
    _generation++;
    if (_done?.isCompleted == false) _done!.complete();
    await player.stop();
  }

  Future<void> close() async {
    closed = true;
    await stop();
    await _completed?.cancel();
    await _position?.cancel();
    await player.dispose();
  }
}
