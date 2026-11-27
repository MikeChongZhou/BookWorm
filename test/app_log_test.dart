import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuejian/diagnostics/app_log.dart';
import 'package:yuejian/cloud/cloud_error.dart';

void main() {
  test('persists safe metadata, rotates files and exports in order', () async {
    final folder = await Directory.systemTemp.createTemp('bookworm-log-test');
    addTearDown(() => folder.delete(recursive: true));
    final log = AppLog(directory: () async => folder, maxBytes: 300);
    for (var i = 0; i < 20; i++) {
      log.record(
        'translation',
        'attempt',
        fields: {
          'request': i,
          'http': 503,
          'apiKey': 'SECRET_API_KEY',
          'excerpt': 'PRIVATE_BOOK_TEXT',
          'model': 'sk-private-secret',
        },
      );
    }
    final output = utf8.decode(await log.export());
    expect(output, contains('"request":19'));
    expect(output, isNot(contains('SECRET_API_KEY')));
    expect(output, isNot(contains('PRIVATE_BOOK_TEXT')));
    expect(output, isNot(contains('sk-private-secret')));
    final files = await Directory(await log.path).list().toList();
    expect(files.length, lessThanOrEqualTo(4));
    for (final file in files.whereType<File>()) {
      expect(await file.length(), lessThanOrEqualTo(300));
    }
    final rows = output
        .split('\n')
        .skip(1)
        .where((s) => s.isNotEmpty)
        .map((s) => jsonDecode(s) as Map)
        .toList();
    final ids = rows.map((r) => r['request'] as int).toList();
    expect(ids, orderedEquals([...ids]..sort()));
  });

  test(
    'disk failures do not interrupt callers and export reports failure',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bookworm-log-failure',
      );
      addTearDown(() => root.delete(recursive: true));
      final blocker = File('${root.path}/not-a-directory');
      await blocker.writeAsString('x');
      final log = AppLog(directory: () async => Directory(blocker.path));
      log.record(
        'sync',
        'failed',
        fields: {'reason': 'authorization_required'},
      );
      await log.flush();
      expect(log.failed, isTrue);
      await expectLater(log.export(), throwsA(isA<FileSystemException>()));
    },
  );

  test('native invalid grant is classified without exposing error details', () {
    final error = PlatformException(
      code: 'org.openid.appauth.oauth_token',
      message: 'invalid_grant: Token has been expired or revoked.',
    );
    expect(requiresCloudSignIn(error), isTrue);
    expect(cloudFailureReason(error), 'authorization_required');
    expect(requiresCloudSignIn(const SocketException('offline')), isFalse);
  });
}
