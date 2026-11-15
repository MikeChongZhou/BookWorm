import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuejian/downloads/book_catalog.dart';
import 'package:yuejian/storage/local_library.dart';

class LiveNetwork extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'daily live scan and both real source downloads import locally',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        SharedPreferences.setMockInitialValues({});
        final folder = await Directory.systemTemp.createTemp(
          'bookworm-live-catalog-',
        );
        addTearDown(() => folder.delete(recursive: true));
        final catalog = BookCatalog(
          directory: () async => Directory('${folder.path}/catalog'),
        );
        addTearDown(catalog.dispose);
        final library = LocalLibrary(Directory('${folder.path}/library'));
        await catalog.refreshDaily();
        expect(catalog.error, isEmpty);
        final chinese = catalog.books
            .where((b) => b.id == 'wenshuoge:2')
            .single;
        final english = catalog.books
            .where((b) => b.source == 'Standard Ebooks')
            .first;
        final imports = <String>[];
        await catalog.download(
          chinese,
          library,
          (book) => imports.add(book.id),
        );
        expect(catalog.downloadStates[chinese.id], '已下载到本地书架');
        await catalog.download(
          english,
          library,
          (book) => imports.add(book.id),
        );
        expect(catalog.downloadStates[english.id], '已下载到本地书架');
        expect(imports.length, 2);
        final local = await library.load();
        expect(local.length, 2);
        expect(local.every((b) => b.readable), isTrue);
        final report = {
          'catalog_total': catalog.books.length,
          'wenshuoge_count': catalog.books
              .where((b) => b.source == '文硕阁')
              .length,
          'standard_count': catalog.books
              .where((b) => b.source == 'Standard Ebooks')
              .length,
          'downloaded_titles': local.map((b) => b.title).toList(),
          'both_sources_downloaded_and_imported': true,
        };
        await File('dist/catalog-live-test-result.json')
            .writeAsString(jsonEncode(report));
        // ignore: avoid_print
        print(jsonEncode(report));
      }, LiveNetwork());
    },
    skip: Platform.environment['BOOKWORM_CATALOG_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
