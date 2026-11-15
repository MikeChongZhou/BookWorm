import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuejian/importing/book_importer.dart';
import 'package:yuejian/screens/reader_screen.dart';
import 'package:yuejian/storage/local_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'local Hongloumeng EPUB imports without blocking and paginates losslessly',
    () async {
      final path = Platform.environment['BOOKWORM_EPUB_TEST'];
      final source = await File(path!).readAsBytes();
      var ticks = 0;
      final heartbeat = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => ticks++,
      );
      final watch = Stopwatch()..start();
      final book = await BookImporter().parse('红楼梦.epub', source);
      final importMs = watch.elapsedMilliseconds;
      heartbeat.cancel();
      expect(book.sections.length, greaterThanOrEqualTo(120));
      expect(book.sections.length, lessThan(150));
      expect(ticks, greaterThan(0));
      final longest = book.sections.reduce(
        (a, b) => a.text.length > b.text.length ? a : b,
      );
      watch.reset();
      final pages = paginateChapter(
        longest.text,
        const TextStyle(fontSize: 21, height: 1.8),
        const Size(350, 550),
        TextScaler.noScaling,
      );
      final paginationMs = watch.elapsedMilliseconds;
      expect(
        pages.map((p) => longest.text.substring(p.start, p.end)).join(),
        longest.text,
      );
      final root = await Directory.systemTemp.createTemp('hongloumeng-perf-');
      addTearDown(() => root.delete(recursive: true));
      final store = LocalLibrary(root);
      await store.save(book);
      final original = await File('${root.path}/${book.id}.json')
          .readAsString();
      watch.reset();
      for (var i = 0; i < 10; i++) {
        book.locate(3, i * 10);
        await store.save(book);
      }
      final saveMs = watch.elapsedMilliseconds;
      expect(
        await File('${root.path}/${book.id}.json').readAsString(),
        original,
      );
      watch.reset();
      final restored = await store.load();
      final loadMs = watch.elapsedMilliseconds;
      expect(restored.single.offset, 90);
      final summary = {
        'file_bytes': source.length,
        'chapters': book.sections.length,
        'characters': book.sections.fold<int>(
          0,
          (sum, s) => sum + s.text.length,
        ),
        'cover_bytes': book.cover?.length,
        'import_ms': importMs,
        'ui_heartbeat_during_import': ticks,
        'longest_chapter_characters': longest.text.length,
        'pagination_ms_test_font': paginationMs,
        'pages_longest_chapter': pages.length,
        'ten_progress_saves_ms': saveMs,
        'load_ms': loadMs,
        'body_unchanged_by_progress_saves': true,
      };
      await File('dist/hongloumeng-performance.json')
          .writeAsString(jsonEncode(summary));
      // Original book contents are never copied into the repository or test report.
      // ignore: avoid_print
      print(jsonEncode(summary));
    },
    skip: Platform.environment['BOOKWORM_EPUB_TEST'] == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
