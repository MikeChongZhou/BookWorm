import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuejian/audio/book_audio_handler.dart';
import 'package:yuejian/models/local_book.dart';
import 'package:yuejian/screens/reader_screen.dart';

class LifecycleProbe extends WidgetsBindingObserver {
  final states = <String>[];
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      states.add(state.name);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real system speech advances with media-session controls', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final previousEngine = prefs.getString('bookworm_speech_engine');
    addTearDown(() async {
      if (previousEngine == null) {
        await prefs.remove('bookworm_speech_engine');
      } else {
        await prefs.setString('bookworm_speech_engine', previousEngine);
      }
    });
    await prefs.setString('bookworm_speech_engine', 'system');
    await BookAudioHandler.initialize();
    final book = LocalBook(
      id: 'background-audio-test',
      title: '书虫后台播放验收',
      author: 'BookWorm',
      format: 'txt',
      sections: [
        BookSection('第一章 · 后台音频', '清晨，阳光落在窗边。这是书虫的离线听书测试。锁屏后，故事仍然继续。' * 30),
      ],
    );
    final root = await getApplicationDocumentsDirectory();
    final report = File('${root.path}/background-audio-test.json');
    final probe = LifecycleProbe();
    WidgetsBinding.instance.addObserver(probe);
    addTearDown(() => WidgetsBinding.instance.removeObserver(probe));
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: book,
          source: null,
          listen: false,
          persist: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(200, 400));
    await tester.pumpAndSettle();
    // Start from the service so the same path is exercised by lock-screen play.
    final handler = BookAudioHandler.instance!;
    await tester.runAsync(() async {
      await handler.play();
      final timeout = DateTime.now().add(const Duration(seconds: 45));
      while ((handler.player?.position.inMilliseconds ?? 0) < 1000 &&
          DateTime.now().isBefore(timeout)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final p = handler.player!;
      expect(p.error, isNull);
      expect(p.playing, isTrue);
      expect(handler.mediaItem.value?.title, book.title);
      final initial = p.position.inMilliseconds;
      // ignore: avoid_print
      print('BACKGROUND_AUDIO_READY');
      await report.writeAsString(
        jsonEncode({'stage': 'playing-ready', 'initial_ms': initial}),
      );
      // A tester can background the simulator or device during this interval.
      // Timers run on the real audio isolate, not the widget test clock.
      await Future<void>.delayed(const Duration(seconds: 90));
      final after = p.position.inMilliseconds;
      final stillPlaying = p.playing;
      await handler.pause();
      final paused = p.position.inMilliseconds;
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(p.position.inMilliseconds, paused);
      await handler.fastForward();
      expect(p.position.inMilliseconds, greaterThan(paused));
      await handler.rewind();
      expect((p.position.inMilliseconds - paused).abs(), lessThan(1000));
      await report.writeAsString(
        jsonEncode({
          'stage': 'completed',
          'initial_ms': initial,
          'after_ms': after,
          'advanced_ms': after - initial,
          'still_playing_before_pause': stillPlaying,
          'pause_and_20_second_controls_passed': true,
          'error': p.error,
        }),
      );
      final result =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      result['lifecycle_states'] = probe.states;
      await report.writeAsString(jsonEncode(result));
      // ignore: avoid_print
      print('BACKGROUND_AUDIO_RESULT ${jsonEncode(result)}');
      expect(stillPlaying, isTrue);
      expect(after - initial, greaterThan(20000));
    });
    await tester.pumpWidget(const SizedBox());
  });
}
