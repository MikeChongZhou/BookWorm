import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuejian/audio/reading_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'uses installed language list without unsupported availability method',
    () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return switch (call.method) {
          'getLanguages' => ['en_US', 'zh-CN'],
          'setLanguage' => 1,
          _ => throw MissingPluginException(),
        };
      });
      await DeviceSpeech().language('en');
      expect(methods, ['getLanguages', 'setLanguage']);
    },
  );

  test('missing voice does not attempt language switch', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getLanguages');
      return ['en-US'];
    });
    await expectLater(DeviceSpeech().language('ja'), throwsStateError);
  });

  test('native language switch failure is reported', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return call.method == 'getLanguages' ? ['en-US'] : 0;
    });
    await expectLater(DeviceSpeech().language('en'), throwsStateError);
  });
}
