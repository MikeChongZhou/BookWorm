import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuejian/models/local_book.dart';
import 'package:yuejian/storage/local_library.dart';
import 'package:yuejian/importing/book_importer.dart';
import 'package:yuejian/audio/reading_player.dart';
import 'package:yuejian/cloud/cloud_provider.dart';
import 'package:yuejian/cloud/library_sync.dart';

class MemoryCloud implements CloudProvider {
  final files = <String, Uint8List>{};
  bool damage = false;
  @override
  String get name => 'test';
  @override
  bool get configured => true;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<List<String>> list() async => files.keys.toList();
  @override
  Future<Uint8List> read(String key) async =>
      damage && key.endsWith('.part') ? Uint8List.fromList([9]) : files[key]!;
  @override
  Future<void> write(String key, Uint8List bytes) async {
    files[key] = bytes;
  }
}

class ControlledSpeech implements SpeechEngine {
  Completer<void>? pending;
  final utterances = <String>[];
  void Function(int, int)? callback;
  @override
  Future<void> prepare() async {}
  @override
  Future<void> speak(String text) {
    utterances.add(text);
    pending = Completer<void>();
    return pending!.future;
  }

  @override
  Future<void> stop() async {
    if (pending != null && !pending!.isCompleted) pending!.complete();
  }

  @override
  Future<void> rate(double rate) async {}
  @override
  Future<void> voice(Map<String, String> v) async {}
  @override
  Future<List<Map<String, String>>> voices() async => [];
  @override
  void progress(void Function(int, int) f) {
    callback = f;
  }
}

Future<void> tick() async {
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'UTF-8 preserves full chapters; pagination belongs to the reader',
    () async {
      final text = '第一章 初见\n${'风吹过树梢。' * 600}\n第二章 后来\n雨停了。';
      final book = await BookImporter().parse(
        '测试.TXT',
        Uint8List.fromList(utf8.encode(text)),
      );
      expect(book.sections.length, 2);
      expect(book.sections.first.text.length, greaterThan(1600));
      expect(book.sections.last.title, '第二章 后来');
      expect(book.sections.map((s) => s.text).join(), contains('雨停了。'));
    },
  );
  test('EPUB follows spine rather than archive order and reads metadata', () {
    final archive = Archive();
    void file(String path, String text) => archive.addFile(
      ArchiveFile(path, utf8.encode(text).length, utf8.encode(text)),
    );
    file(
      'META-INF/container.xml',
      '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>',
    );
    file(
      'OEBPS/book.opf',
      '<package><metadata><title>春天</title><creator>作者甲</creator></metadata><manifest><item id="b" href="b.xhtml"/><item id="a" href="a.xhtml"/></manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>',
    );
    file('OEBPS/b.xhtml', '<html><body><h1>第二章</h1><p>乙。</p></body></html>');
    file(
      'OEBPS/a.xhtml',
      '<html><body><h1>第一章</h1><p>甲。</p><script>bad()</script></body></html>',
    );
    final result = BookImporter.epub(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
    expect(result.$1, '春天');
    expect(result.$2, '作者甲');
    expect(result.$3.first.text, contains('甲。'));
    expect(result.$3.last.text, contains('乙。'));
    expect(result.$3.map((s) => s.text).join(), isNot(contains('bad()')));
  });
  test('EPUB narrative mentioning an earlier chapter is never removed as a heading', () {
    final archive = Archive();
    void file(String name, String text) => archive.addFile(
      ArchiveFile(name, utf8.encode(text).length, utf8.encode(text)),
    );
    file(
      'META-INF/container.xml',
      '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
    );
    file(
      'book.opf',
      '<package><metadata><title>测试</title></metadata><manifest><item id="a" href="a.xhtml"/></manifest><spine><itemref idref="a"/></spine></package>',
    );
    const paragraph = '第四回中既将薛家母子在荣府内寄居等事略已表明，此回则暂不能写矣。';
    file(
      'a.xhtml',
      '<html><body><h1>第五回</h1><p>$paragraph</p><p>随后继续正文。</p></body></html>',
    );
    final result = BookImporter.epub(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
    expect(result.$3.length, 1);
    expect(result.$3.single.title, '第五回');
    expect(result.$3.single.text, contains(paragraph));
  });
  test('unsupported encoding and empty inputs fail explicitly', () async {
    await expectLater(
      BookImporter().parse('空.txt', Uint8List(0)),
      throwsFormatException,
    );
    await expectLater(
      BookImporter().parse('坏.txt', Uint8List.fromList([0xff, 0xff])),
      throwsFormatException,
    );
  });
  test('ordinary local files persist and malformed book is retained', () async {
    final root = await Directory.systemTemp.createTemp('bookworm_store');
    addTearDown(() => root.delete(recursive: true));
    final store = LocalLibrary(root);
    final book = await BookImporter().parse(
      '本地.txt',
      Uint8List.fromList(utf8.encode('第一句。第二句。')),
    );
    await store.source(book.id, Uint8List.fromList(utf8.encode('第一句。第二句。')));
    await store.save(book);
    book.locate(0, 4);
    await store.save(book);
    final loaded = await store.load();
    expect(loaded.single.offset, 4);
    expect(
      await File('${root.path}/${book.id}.json').readAsString(),
      contains('第一句'),
    );
    await File('${root.path}/broken.json').writeAsString('{broken');
    expect((await store.load()).length, 1);
    expect(store.warnings, isNotEmpty);
    expect(await File('${root.path}/broken.json').exists(), isTrue);
  });
  test('migration preserves legacy progress and original data', () async {
    final root = await Directory.systemTemp.createTemp('bookworm_migration');
    addTearDown(() => root.delete(recursive: true));
    SharedPreferences.setMockInitialValues({
      'books': jsonEncode([
        {
          'id': 'old',
          'title': '旧书',
          'author': '甲',
          'text': '12345678',
          'progress': .5,
        },
      ]),
      'notes': ['旧笔记'],
    });
    final store = LocalLibrary(root);
    await store.migrate();
    await store.migrate();
    final books = await store.load();
    expect(books.length, 1);
    expect(books.single.offset, 4);
    expect((await SharedPreferences.getInstance()).getStringList('notes'), [
      '旧笔记',
    ]);
  });
  test('sync transfers original book and merges furthest position', () async {
    final a = await Directory.systemTemp.createTemp('bookworm_a'),
        b = await Directory.systemTemp.createTemp('bookworm_b');
    addTearDown(() async {
      await a.delete(recursive: true);
      await b.delete(recursive: true);
    });
    final sa = LocalLibrary(a), sb = LocalLibrary(b);
    final source = Uint8List.fromList(utf8.encode('一段正文。二段正文。'));
    final book = await BookImporter().parse('同步.txt', source);
    await sa.source(book.id, source);
    await sa.save(book);
    final cloud = MemoryCloud();
    final uploadStatus = <String>[];
    await LibrarySync(sa, 'aaaa').run(cloud, status: uploadStatus.add);
    expect(uploadStatus, contains('上传本地文件中，已上传 0 个文件'));
    expect(uploadStatus, contains('上传本地文件中，已上传 1 个文件'));
    final downloadStatus = <String>[];
    final result = await LibrarySync(
      sb,
      'bbbb',
    ).run(cloud, status: downloadStatus.add);
    expect(downloadStatus, contains('下载本地文件中，已下载 0 个文件'));
    expect(downloadStatus, contains('下载本地文件中，已下载 1 个文件'));
    expect(result.downloaded, 1);
    expect(
      sha256.convert(await sb.readSource(book.id)),
      sha256.convert(source),
    );
    book.locate(0, 5);
    await sa.save(book);
    await LibrarySync(sa, 'aaaa').run(cloud);
    final next = await LibrarySync(sb, 'bbbb').run(cloud);
    expect(next.positions.single.offset, 5);
    expect((await sb.load()).single.offset, 5);
    final repeated = await LibrarySync(sb, 'bbbb').run(cloud);
    expect(repeated.downloaded, 0);
  });
  test(
    'sync rejects corrupted chunks without committing a partial book',
    () async {
      final a = await Directory.systemTemp.createTemp('bookworm_c'),
          b = await Directory.systemTemp.createTemp('bookworm_d');
      addTearDown(() async {
        await a.delete(recursive: true);
        await b.delete(recursive: true);
      });
      final sa = LocalLibrary(a), sb = LocalLibrary(b);
      final source = Uint8List.fromList(utf8.encode('不能丢失的正文'));
      final book = await BookImporter().parse('检查.txt', source);
      await sa.source(book.id, source);
      await sa.save(book);
      final cloud = MemoryCloud();
      await LibrarySync(sa, 'aaaa').run(cloud);
      cloud.damage = true;
      await expectLater(
        LibrarySync(sb, 'bbbb').run(cloud),
        throwsA(isA<CloudFailure>()),
      );
      expect(await sb.load(), isEmpty);
    },
  );
  test(
    'TTS pause resumes exact reported character and stops stale completion',
    () async {
      final book = LocalBook(
        id: 'id',
        title: '甲',
        author: '乙',
        format: 'txt',
        sections: [const BookSection('正文', '甲乙丙丁戊己庚辛壬癸。')],
      );
      final speech = ControlledSpeech();
      final player = ReadingPlayer(book, speech, () async {});
      final first = player.play();
      await tick();
      expect(player.playing, isTrue);
      speech.callback!(4, 5);
      expect(book.offset, 4);
      await player.pause();
      await first;
      expect(book.offset, 4);
      final second = player.play();
      await tick();
      expect(speech.utterances.last, startsWith('戊'));
      await player.pause();
      await second;
      player.dispose();
    },
  );
}
