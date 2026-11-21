import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'reading_player.dart';

class BookAudioHandler extends BaseAudioHandler {
  static BookAudioHandler? instance;
  static Future<void> initialize() async {
    if (instance != null) return;
    if (Platform.isLinux) {
      instance = BookAudioHandler();
      return;
    }
    instance = await AudioService.init<BookAudioHandler>(
      builder: BookAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.fairyphoenix.bookworm.listening',
        androidNotificationChannelName: 'BookWorm 听书',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        rewindInterval: Duration(seconds: 20),
        fastForwardInterval: Duration(seconds: 20),
      ),
    );
  }

  ReadingPlayer? _player;
  ReadingPlayer? get player => _player;
  AudioSession? _session;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  StreamSubscription<void>? _noisy;
  bool _resumeAfterInterruption = false;
  Future<void>? _interruptionPause;
  Future<void> handleInterruption(AudioInterruptionEvent event) async {
    if (event.begin) {
      _resumeAfterInterruption =
          _resumeAfterInterruption ||
          (_player?.playing ?? false) ||
          (_player?.buffering ?? false);
      _interruptionPause = _player?.pause();
      await _interruptionPause;
    } else {
      await _interruptionPause;
      final resume =
          _resumeAfterInterruption &&
          (event.type == AudioInterruptionType.pause ||
              event.type == AudioInterruptionType.duck);
      _resumeAfterInterruption = false;
      if (resume) await play();
    }
  }

  int _section = -1;
  Uri? _art;
  String _state = '';
  DateTime _published = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> attach(ReadingPlayer player) async {
    final previous = _player;
    if (identical(previous, player)) {
      _publish();
      return;
    }
    if (previous != null && !identical(previous, player)) {
      previous.removeListener(_publish);
      await previous.pause();
      previous.dispose();
    }
    _player = player;
    _section = -1;
    _art = null;
    player.beforePlay = _activate;
    player.addListener(_publish);
    _publish();
    final cover = player.book.cover;
    if (cover != null) {
      final file = File(
        '${(await getTemporaryDirectory()).path}/bookworm-cover-${player.book.id}.jpg',
      );
      await file.writeAsBytes(cover);
      if (identical(_player, player)) {
        _art = file.uri;
        _section = -1;
        _publish();
      }
    }
  }

  Future<void> _activate() async {
    if (Platform.isWindows || Platform.isLinux) return;
    _session ??= await AudioSession.instance;
    await _session!.configure(const AudioSessionConfiguration.speech());
    _interruptions ??= _session!.interruptionEventStream.listen((event) {
      unawaited(handleInterruption(event));
    });
    _noisy ??= _session!.becomingNoisyEventStream.listen((_) {
      _resumeAfterInterruption = false;
      unawaited(pause());
    });
    if (!await _session!.setActive(true)) throw StateError('音频会话暂不可用，请稍后重试');
  }

  void _publish() {
    final p = _player;
    if (p == null || p.disposed) return;
    final key = '${p.playing}/${p.buffering}/${p.book.section}/${p.error}';
    if (_state == key &&
        DateTime.now().difference(_published).inMilliseconds < 750) {
      return;
    }
    _state = key;
    _published = DateTime.now();
    if (_section != p.book.section || mediaItem.value?.duration != p.duration) {
      _section = p.book.section;
      mediaItem.add(
        MediaItem(
          id: '${p.book.id}/${p.book.section}',
          title: p.book.title,
          artist: p.book.sections[p.book.section].title,
          album: p.book.author,
          duration: p.duration,
          artUri: _art,
          extras: {'durationEstimated': !p.durationExact},
        ),
      );
    }
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.rewind,
          p.playing || p.buffering ? MediaControl.pause : MediaControl.play,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: p.error != null
            ? AudioProcessingState.error
            : p.buffering
            ? AudioProcessingState.buffering
            : AudioProcessingState.ready,
        playing: p.playing || p.buffering,
        updatePosition: p.position,
        bufferedPosition: p.position,
        speed: p.speed * 2,
      ),
    );
  }

  Future<void> detach(ReadingPlayer player) async {
    if (!identical(_player, player)) return;
    player.removeListener(_publish);
    player.beforePlay = null;
    _player = null;
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle, playing: false),
    );
    mediaItem.add(null);
    try {
      await _session?.setActive(false);
    } catch (e) {
      debugPrint('Audio session release failed: $e');
    }
  }

  @override
  Future<void> play() async {
    final p = _player;
    if (p != null) unawaited(p.play());
  }

  @override
  Future<void> pause() async {
    _resumeAfterInterruption = false;
    await _player?.pause();
  }

  @override
  Future<void> stop() async {
    await pause();
    playbackState.add(
      playbackState.value.copyWith(processingState: AudioProcessingState.idle),
    );
  }

  @override
  Future<void> seek(Duration position) async => _player?.seekTime(position);
  @override
  Future<void> rewind() async => _player?.jump(-20);
  @override
  Future<void> fastForward() async => _player?.jump(20);
  @override
  Future<void> skipToNext() async {
    final p = _player;
    if (p != null && p.book.section + 1 < p.book.sections.length) {
      await p.seek(p.book.section + 1, 0);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final p = _player;
    if (p != null && p.book.section > 0) await p.seek(p.book.section - 1, 0);
  }

  @override
  Future<void> setSpeed(double speed) async => _player?.setSpeed(speed / 2);
}
