import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuejian/cloud/cloud_provider.dart';
import 'package:yuejian/cloud/library_sync.dart';
import 'package:yuejian/importing/book_importer.dart';
import 'package:yuejian/storage/local_library.dart';

class TransferCloud implements CloudProvider, CloudTransferLimits {
  final files = <String, Uint8List>{};
  final reads = <String, int>{}, writes = <String, int>{};
  int active = 0, peak = 0, workers = 4;
  String? failRead;
  int? failWriteAfter;
  int partWrites = 0;
  @override
  int get transferChunkBytes => 192 * 1024;
  @override
  int get transferWorkers => workers;
  @override
  String get name => 'Test';
  @override
  bool get configured => true;
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<List<String>> list() async => files.keys.toList();
  @override
  Future<Uint8List> read(String key) async {
    reads.update(key, (n) => n + 1, ifAbsent: () => 1);
    if (key == failRead) throw const CloudFailure('offline');
    return files[key]!;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    writes.update(key, (n) => n + 1, ifAbsent: () => 1);
    if (key.endsWith('.part')) {
      if (failWriteAfter != null && partWrites >= failWriteAfter!) {
        throw const CloudFailure('offline');
      }
      active++;
      peak = max(peak, active);
      try {
        await Future<void>.delayed(const Duration(milliseconds: 3));
        files[key] = bytes;
        partWrites++;
      } finally {
        active--;
      }
    } else {
      files[key] = bytes;
    }
  }
}

void main() {
  Future<LocalLibrary> library() async {
    final dir = await Directory.systemTemp.createTemp('bookworm-transfer-');
    addTearDown(() => dir.delete(recursive: true));
    return LocalLibrary(dir);
  }

  Uint8List source() {
    final random = Random(42);
    return Uint8List.fromList(
      List.generate(900000, (_) => 65 + random.nextInt(26)),
    );
  }

  Future<String> seed(LocalLibrary store, Uint8List bytes) async {
    final book = await BookImporter().parse('Example.txt', bytes);
    await store.install(book, bytes);
    return book.id;
  }

  test('binary transfer sends only original bytes, bounds concurrency and skips existing manifests', () async {
    final a = await library(), b = await library();
    final bytes = source();
    final id = await seed(a, bytes);
    final cloud = TransferCloud();
    final status = <String>[];
    await LibrarySync(a, 'aaaa').run(cloud, status: status.add);
    final manifest = jsonDecode(utf8.decode(cloud.files['book-$id.manifest']!));
    expect(manifest['schema'], 2);
    expect(
      cloud.files.entries
          .where((e) => e.key.endsWith('.part'))
          .fold<int>(0, (n, e) => n + e.value.length),
      bytes.length,
    );
    expect(cloud.peak, inInclusiveRange(2, 4));
    expect(status.any((s) => s.contains('MB/s')), isTrue);
    final result = await LibrarySync(b, 'bbbb').run(cloud);
    expect(result.downloaded, 1);
    expect(await b.readSource(id), bytes);
    final manifestReads = cloud.reads['book-$id.manifest'];
    final uploads = cloud.partWrites;
    await LibrarySync(b, 'bbbb').run(cloud);
    expect(cloud.partWrites, uploads);
    expect(cloud.reads['book-$id.manifest'], manifestReads);
  });

  test('failed upload resumes committed content-addressed parts without republishing incomplete book', () async {
    final a = await library();
    final id = await seed(a, source());
    final cloud = TransferCloud()
      ..workers = 1
      ..failWriteAfter = 1;
    await expectLater(
      LibrarySync(a, 'aaaa').run(cloud),
      throwsA(isA<CloudFailure>()),
    );
    final firstKey = cloud.files.keys.single;
    expect(cloud.files.containsKey('book-$id.manifest'), isFalse);
    final writes = cloud.writes[firstKey];
    cloud.failWriteAfter = null;
    await LibrarySync(a, 'aaaa').run(cloud);
    expect(cloud.writes[firstKey], writes);
    expect(cloud.files.containsKey('book-$id.manifest'), isTrue);
  });

  test(
    'failed download retains verified temporary parts and stays out of library',
    () async {
      final a = await library(), b = await library();
      final bytes = source();
      final id = await seed(a, bytes);
      final cloud = TransferCloud()..workers = 1;
      await LibrarySync(a, 'aaaa').run(cloud);
      final manifest = jsonDecode(
        utf8.decode(cloud.files['book-$id.manifest']!),
      );
      final firstKey = manifest['parts'][0]['key'] as String;
      cloud.failRead = manifest['parts'][1]['key'];
      await expectLater(
        LibrarySync(b, 'bbbb').run(cloud),
        throwsA(isA<CloudFailure>()),
      );
      expect(await b.load(), isEmpty);
      final reads = cloud.reads[firstKey];
      cloud.failRead = null;
      await LibrarySync(b, 'bbbb').run(cloud);
      expect(cloud.reads[firstKey], reads);
      expect(await b.readSource(id), bytes);
      expect(
        await Directory('${b.root.path}/.cloud-download-$id').exists(),
        isFalse,
      );
    },
  );

  test('old manifest remains readable and repeated binary parts assemble correctly', () async {
    final legacy = await library(), receiver = await library();
    final bytes = Uint8List.fromList(utf8.encode('old book'));
    final book = await BookImporter().parse('Old.txt', bytes);
    final payload = encodeCloudBook((book, bytes));
    final cloud = TransferCloud();
    final key = 'book-${book.id}-0.part';
    cloud.files[key] = payload;
    cloud.files['book-${book.id}.manifest'] = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': 1,
          'id': book.id,
          'parts': [
            {
              'key': key,
              'hash': sha256.convert(payload).toString(),
              'size': payload.length,
            },
          ],
        }),
      ),
    );
    await LibrarySync(legacy, 'aaaa').run(cloud);
    expect(await legacy.readSource(book.id), bytes);
    final repeated = Uint8List.fromList(List.filled(192 * 1024 * 4, 65));
    final id = await seed(legacy, repeated);
    await LibrarySync(legacy, 'aaaa').run(cloud);
    await LibrarySync(receiver, 'bbbb').run(cloud);
    expect(await receiver.readSource(id), repeated);
  });
}
