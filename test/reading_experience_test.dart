import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuejian/audio/chapter_timeline.dart';
import 'package:yuejian/audio/file_audio_transport.dart';
import 'package:yuejian/audio/reading_player.dart';
import 'package:yuejian/audio/book_audio_handler.dart';
import 'package:yuejian/downloads/book_catalog.dart';
import 'package:yuejian/models/local_book.dart';
import 'package:yuejian/storage/local_library.dart';
import 'package:yuejian/screens/reader_screen.dart';
import 'package:yuejian/main.dart';
import 'package:yuejian/importing/book_importer.dart';
import 'package:yuejian/cloud/library_sync.dart';

import 'package:yuejian/history/reading_history.dart';

import 'local_features_test.dart' show ControlledSpeech, MemoryCloud, tick;

LocalBook sample() => LocalBook(
  id: 'sample',
  title: '测试长篇',
  author: '作者',
  format: 'epub',
  sections: [
    BookSection('第一章', '第一句。第二句。${'第三句很长，用于验证分页和翻页方向。' * 100}'),
    const BookSection('第二章', '下一章。'),
  ],
);

class ClockSpeech extends ControlledSpeech implements SpeechTiming {
  void Function(Duration, Duration)? clock;
  Duration start = Duration.zero;
  @override
  Future<void> speak(String text) {
    final result = super.speak(text);
    clock?.call(start, const Duration(seconds: 40));
    return result;
  }

  @override
  bool get hasMediaClock => true;
  @override
  void startPosition(Duration position) => start = position;
  @override
  void playbackProgress(void Function(Duration, Duration) callback) =>
      clock = callback;
}

class BlockingCloud extends MemoryCloud {
  final blocker = Completer<List<String>>();
  @override
  String get name => 'blocking';
  @override
  Future<List<String>> list() => blocker.future;
}

class FakeLibrary extends LocalLibrary {
  final LocalBook book;
  FakeLibrary([LocalBook? book])
    : book = book ?? sample(),
      super(Directory('/unused-test-library'));
  @override
  Future<List<LocalBook>> load() async => [book];
  @override
  Future<void> save(LocalBook b, {bool contentChanged = false}) async {}
}

void main() {
  test(
    'audio history counts rendered playback, excluding paused time and seeks',
    () async {
      SharedPreferences.setMockInitialValues({});
      final book = LocalBook(
        id: 'history-clock',
        title: '计时',
        author: '',
        format: 'txt',
        sections: [BookSection('正文', '长句，' * 200)],
      );
      final engine = ClockSpeech();
      final player = ReadingPlayer(book, engine, () async {});
      ReadingHistory.instance.records.remove(book.id);
      unawaited(player.play());
      await tick();
      engine.clock!(const Duration(seconds: 10), const Duration(seconds: 40));
      expect(ReadingHistory.instance.record(book).milliseconds, 10000);
      await player.pause();
      engine.clock!(const Duration(seconds: 20), const Duration(seconds: 40));
      await player.jump(20);
      expect(ReadingHistory.instance.record(book).milliseconds, 10000);
      unawaited(player.play());
      await tick();
      engine.clock!(
        engine.start + const Duration(seconds: 5),
        const Duration(seconds: 40),
      );
      expect(ReadingHistory.instance.record(book).milliseconds, 15000);
      await player.pause();
      player.dispose();
      await ReadingHistory.instance.save();
    },
  );
  test(
    'duck interruptions resume, while an explicit user pause prevents resuming',
    () async {
      SharedPreferences.setMockInitialValues({});
      final handler = BookAudioHandler();
      final player = ReadingPlayer(sample(), ClockSpeech(), () async {});
      await handler.attach(player);
      player.beforePlay = () async {};
      unawaited(player.play());
      await tick();
      await handler.handleInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.duck),
      );
      expect(player.playing, false);
      await handler.handleInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.duck),
      );
      await tick();
      expect(player.playing, true);
      await handler.handleInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await handler.pause();
      await handler.handleInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await tick();
      expect(player.playing, false);
      await handler.detach(player);
      player.dispose();
      await ReadingHistory.instance.save();
    },
  );
  testWidgets('automatic sync adopts furthest position without a dialog', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'bookworm_language': 'zh',
      'bookworm_cloud': 'test',
      'bookworm_device': 'bbbb',
    });
    final id = '1' * 64;
    final book = LocalBook(
      id: id,
      title: '进度测试',
      author: '作者',
      format: 'txt',
      sections: [const BookSection('正文', '甲乙丙丁戊己庚辛壬癸。')],
    );
    final cloud = MemoryCloud();
    cloud.files['book-$id.manifest'] = utf8.encode(
      jsonEncode({'schema': 1, 'id': id, 'parts': []}),
    );
    cloud.files['position-$id-aaaa.json'] = utf8.encode(
      jsonEncode({
        'id': id,
        'device': 'aaaa',
        'section': 0,
        'offset': 5,
        'modified': 100,
      }),
    );
    await tester.pumpWidget(
      ReaderApp(library: FakeLibrary(book), cloudProviders: [cloud]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(book.offset, 5);
    expect(find.text('检查其他设备进度'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('audio session survives returning from the reader', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final previous = BookAudioHandler.instance;
    final handler = BookAudioHandler();
    BookAudioHandler.instance = handler;
    final book = sample(), engine = ClockSpeech();
    final player = ReadingPlayer(book, engine, () async {});
    await handler.attach(player);
    player.beforePlay = () async {};
    unawaited(player.play());
    await tester.pump();
    Future<void> cleanup() async {
      if (!player.disposed) {
        await player.pause();
        await handler.detach(player);
        player.dispose();
      }
      BookAudioHandler.instance = previous;
    }

    addTearDown(cleanup);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ReaderScreen(
                    book: book,
                    source: null,
                    listen: true,
                    autoPlay: false,
                    persist: () async {},
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回书架'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(player.playing, isTrue);
    expect(player.disposed, isFalse);
    expect(handler.player, same(player));
    await tester.pumpWidget(const SizedBox());
    await cleanup();
  });
  test(
    'sync yields safely to reading, then resumes uncommitted chunks',
    () async {
      final a = await Directory.systemTemp.createTemp('sync-yield-a-');
      final b = await Directory.systemTemp.createTemp('sync-yield-b-');
      addTearDown(() async {
        await a.delete(recursive: true);
        await b.delete(recursive: true);
      });
      final first = LocalLibrary(a), second = LocalLibrary(b);
      final source = utf8.encode('这是不可丢失的正文。' * 20000);
      final book = await BookImporter().parse('长书.txt', source);
      await first.source(book.id, source);
      await first.save(book);
      final cloud = MemoryCloud();
      final interrupted = await LibrarySync(first, 'aaaa').run(
        cloud,
        yieldRequested: () => cloud.files.keys.any((k) => k.endsWith('.part')),
      );
      expect(interrupted.deferred, isTrue);
      expect(interrupted.uploaded, 0);
      expect(cloud.files.keys.any((k) => k.endsWith('.manifest')), isFalse);
      await LibrarySync(second, 'bbbb').run(cloud);
      expect(await second.load(), isEmpty);
      final resumed = await LibrarySync(first, 'aaaa').run(cloud);
      expect(resumed.uploaded, 1);
      final downloaded = await LibrarySync(second, 'bbbb').run(cloud);
      expect(downloaded.downloaded, 1);
      expect(await second.readSource(book.id), source);
    },
  );
  test(
    'sentence ranges preserve decimals and text; timeline seeks measured media',
    () {
      final timeline = ChapterTimeline('价格3.14万元。下一句！最后一句');
      expect(timeline.sentences.length, 3);
      expect(
        timeline.text.substring(
          timeline.sentences.first.start,
          timeline.sentences.first.end,
        ),
        '价格3.14万元。',
      );
      timeline.measured[timeline.chunks.first.start] = const Duration(
        seconds: 30,
      );
      final (span, within) = timeline.atTime(const Duration(seconds: 20));
      expect(span.start, 0);
      expect(within.inSeconds, 20);
    },
  );
  test('audio pause resumes native media offset and 20-second jump', () async {
    final book = sample(), speech = ClockSpeech();
    final p = ReadingPlayer(book, speech, () async {});
    unawaited(p.play());
    await tick();
    speech.clock!(const Duration(seconds: 9), const Duration(seconds: 40));
    expect(p.position.inSeconds, 9);
    await p.pause();
    expect(book.audioOffsetMs, 9000);
    unawaited(p.play());
    await tick();
    expect(speech.start.inSeconds, 9);
    await p.jump(20);
    await tick();
    expect(speech.start.inSeconds, 29);
    await p.pause();
    p.dispose();
  });
  test('progress saves do not rewrite novel text, and old sections migrate losslessly', () async {
    final root = await Directory.systemTemp.createTemp('reader-io-');
    addTearDown(() => root.delete(recursive: true));
    final library = LocalLibrary(root), book = sample();
    await library.save(book);
    final file = File('${root.path}/${book.id}.json');
    final before = await file.readAsString();
    book.locate(0, 20);
    await library.save(book);
    expect(await file.readAsString(), before);
    expect((await library.load()).single.offset, 20);
    final legacy = LocalBook(
      id: 'old',
      title: '旧书',
      author: '作者',
      format: 'epub',
      sections: [
        const BookSection('第一回', '甲乙'),
        const BookSection('第一回 · 2', '丙丁'),
        const BookSection('第二回', '戊己'),
      ],
      section: 1,
      offset: 1,
    );
    final merged = mergeLegacySections(legacy);
    expect(merged.sections.length, 2);
    expect(merged.offset, 5);
    expect(merged.section, 0);
    expect(merged.sections.first.text, '甲乙\n\n丙丁');
  });
  test('catalog CSV supports multiline quotes; Standard parser ignores unrelated links', () {
    final csv = '编号,书名,副标题,作者,简介\r\n1,"书,名",,作者,"一行\n二行"\r\n';
    expect(parseWenshuoge(csv).single.title, '书,名');
    final page = parseStandardPage((
      '''<html><a href="/honeypot"/><ol class="ebooks-list grid"><li about="/ebooks/author/book"><span property="schema:name">A Book</span><p property="schema:author">An Author</p></li></ol><a rel="next" href="/ebooks?page=2"/></html>''',
      'https://standardebooks.org/ebooks',
    ));
    expect(page.$1.single.title, 'A Book');
    expect(page.$2, 'https://standardebooks.org/ebooks?page=2');
    expect(
      standardDownloadUrl((
        '<html><a href="/ebooks/a/b/downloads/a_b.epub"/></html>',
        'https://standardebooks.org/ebooks/a/b',
      )),
      'https://standardebooks.org/ebooks/a/b/downloads/a_b.epub',
    );
  });
  test(
    'catalog refresh once per day, cached results survive a failed source',
    () async {
      SharedPreferences.setMockInitialValues({});
      final folder = await Directory.systemTemp.createTemp('catalog-test-');
      addTearDown(() => folder.delete(recursive: true));
      var requests = 0;
      final catalog = BookCatalog(
        directory: () async => folder,
        client: MockClient((request) async {
          requests++;
          if (request.url.host == 'raw.githubusercontent.com') {
            return http.Response.bytes(
              utf8.encode('编号,书名,副标题,作者\n1,论语,,孔子\n'),
              200,
            );
          }
          return http.Response(
            '<html><ol class="ebooks-list"><li about="/ebooks/a/b"><span property="schema:name">Book</span></li></ol></html>',
            200,
          );
        }),
      );
      await catalog.refreshDaily();
      expect(catalog.books.length, 2);
      await catalog.refreshDaily();
      expect(requests, 2);
      catalog.dispose();
      final failed = BookCatalog(
        directory: () async => folder,
        client: MockClient((r) async => http.Response('', 503)),
      );
      await failed.load();
      await failed.refresh();
      expect(failed.books.length, 2);
      expect(failed.error, contains('503'));
      failed.dispose();
    },
  );
  testWidgets(
    'opening a book remains responsive while private-cloud sync is blocked',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'bookworm_language': 'zh',
        'bookworm_cloud': 'blocking',
      });
      final cloud = BlockingCloud();
      await tester.pumpWidget(
        ReaderApp(library: FakeLibrary(), cloudProviders: [cloud]),
      );
      await tester.pumpAndSettle();
      expect(find.text('正在检查私人云文件'), findsOneWidget);
      await tester.tap(find.text('测试长篇').first);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(find.text('第一章'), findsOneWidget);
      cloud.blocker.complete([]);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'player controls, reading toolbar and requested swipe directions',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final book = sample(), speech = ClockSpeech();
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            book: book,
            source: null,
            listen: false,
            persist: () async {},
            speechEngine: speech,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 480));
      await tester.pumpAndSettle();
      for (final text in ['播放', '目录', '笔记', '自动翻页', '颜色', '字号']) {
        expect(find.text(text), findsOneWidget);
      }
      await tester.fling(
        find.byType(RichText).first,
        const Offset(400, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(book.offset, greaterThan(0));
      await tester.fling(
        find.byType(RichText).first,
        const Offset(-400, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(book.offset, 0);
      await tester.tap(find.text('播放'));
      await tester.pumpAndSettle();
      expect(find.text('原文'), findsOneWidget);
      expect(find.byTooltip('回退20秒'), findsOneWidget);
      expect(find.byTooltip('快进20秒'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
