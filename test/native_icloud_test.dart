import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuejian/cloud/cloud_provider.dart';
import 'package:yuejian/cloud/native_icloud_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const provider = NativeICloudProvider('iCloud.com.fairyphoenix.bookworm');
  final key = 'book-${'a' * 64}-0.part';
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeICloudProvider.channel, null);
  });
  test(
    'uses registered app container without any picker or password',
    () async {
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeICloudProvider.channel, (call) async {
            methods.add(call.method);
            expect((call.arguments as Map)['container'], provider.container);
            return switch (call.method) {
              'list' => [key, '../other-app', 'unrelated'],
              'read' => Uint8List.fromList([1, 2, 3]),
              _ => null,
            };
          });
      await provider.connect();
      expect(await provider.list(), [key]);
      expect(await provider.read(key), [1, 2, 3]);
      await provider.write(key, Uint8List.fromList([1, 2, 3]));
      await provider.disconnect();
      expect(methods, ['connect', 'list', 'read', 'write']);
    },
  );
  test(
    'missing account and invalid keys fail without exposing paths',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            NativeICloudProvider.channel,
            (_) async => throw PlatformException(
              code: 'account',
              message: 'private/account/path',
            ),
          );
      await expectLater(
        provider.connect(),
        throwsA(
          isA<CloudFailure>().having(
            (e) => e.message,
            'message',
            isNot(contains('private/account')),
          ),
        ),
      );
      await expectLater(
        provider.read('../secret'),
        throwsA(isA<CloudFailure>()),
      );
      expect(const NativeICloudProvider('').configured, false);
    },
  );
}
