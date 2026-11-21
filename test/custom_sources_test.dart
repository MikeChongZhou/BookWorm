import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuejian/downloads/book_catalog.dart';
import 'package:yuejian/downloads/custom_sources.dart';
import 'package:yuejian/audio/melo_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('website discovery supports multiple files, titles and same-site pagination only', () {
    final result = discoverBooks((
      '''<a href="a.epub">书一</a><a href='b.pdf'>书二</a><a href="a.epub">重复</a><a href="?page=2">下一页</a><a href="https://other.test/login">其他站</a><a href="javascript:evil()">脚本</a>''',
      'https://books.test/list',
      'source',
    ));
    expect(result.$1.length, 2);
    expect(result.$1.map((b) => b.format), ['epub', 'pdf']);
    expect(result.$2, ['https://books.test/list?page=2']);
    expect(() => sourceUri('http://books.test'), throwsFormatException);
    expect(
      () => sourceUri('https://user:password@books.test'),
      throwsFormatException,
    );
  });
  test(
    'OPDS acquisition MIME supports extensionless URLs and feed pagination',
    () {
      final result = discoverBooks((
        '''<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>书名</title><author><name>作者</name></author><link rel="http://opds-spec.org/acquisition" type="application/epub+zip" href="/download/42"/></entry><link rel="next" href="?page=2"/></feed>''',
        'https://books.test/opds',
        'source',
      ));
      expect(result.$1.single.title, '书名');
      expect(result.$1.single.format, 'epub');
      expect(result.$1.single.pageUrl, 'https://books.test/download/42');
      expect(result.$2, contains('https://books.test/opds?page=2'));
    },
  );
  test('scan previews multi-page books and saves source and cache only after confirmation', () async {
    final dir = await Directory.systemTemp.createTemp('source-test-');
    final client = MockClient(
      (r) async => http.Response(
        r.url.query.isEmpty
            ? '<a href="/a.epub">第一本</a><a href="?page=2">下一页</a>'
            : '<a href="/b.txt">第二本</a>',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      ),
    );
    final catalog = BookCatalog(client: client, directory: () async => dir);
    await catalog.load();
    final preview = await catalog.scanSource('https://books.test/list');
    expect(preview.length, 2);
    expect(catalog.books, isEmpty);
    await catalog.addSource('https://books.test/list', preview);
    final restored = BookCatalog(directory: () async => dir);
    await restored.load();
    expect(restored.customSources, ['https://books.test/list']);
    expect(restored.books.length, 2);
    await catalog.removeSource('https://books.test/list');
    expect(catalog.books, isEmpty);
    catalog.dispose();
    restored.dispose();
    await dir.delete(recursive: true);
  });
  test(
    'failed website and incompatible model configuration fail explicitly',
    () async {
      final dir = await Directory.systemTemp.createTemp('source-error-');
      final catalog = BookCatalog(
        client: MockClient((_) async => http.Response('', 503)),
        directory: () async => dir,
      );
      await expectLater(
        catalog.scanSource('https://books.test/list'),
        throwsA(isA<HttpException>()),
      );
      final model = MeloModel();
      await expectLater(
        model.install(
          downloadUrl: 'https://models.test/file',
          expectedHash: 'bad',
          expectedBytes: 5,
        ),
        throwsFormatException,
      );
      expect(model.busy, false);
      catalog.dispose();
      await dir.delete(recursive: true);
    },
  );
}
