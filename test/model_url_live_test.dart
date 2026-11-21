import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuejian/audio/melo_model.dart';
import 'package:yuejian/audio/melo_speech.dart';

class ModelNetwork extends HttpOverrides {}

class TemporaryModel extends MeloModel {
  final Directory directory;
  TemporaryModel(this.directory);
  @override
  Future<Directory> get root async => directory;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'custom model URL verifies, installs and generates real audio in isolated storage',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        SharedPreferences.setMockInitialValues({});
        final folder = await Directory.systemTemp.createTemp(
          'bookworm-model-url-',
        );
        addTearDown(() => folder.delete(recursive: true));
        final model = TemporaryModel(folder);
        final url =
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${MeloModel.folder}.tar.bz2';
        await model.install(
          downloadUrl: url,
          expectedHash: MeloModel.archiveHash,
          expectedBytes: MeloModel.archiveBytes,
        );
        expect(model.error, isNull);
        expect(model.installed, true);
        expect(
          (await SharedPreferences.getInstance()).getString('custom_melo_url'),
          url,
        );
        final receive = ReceivePort();
        final stream = StreamIterator<dynamic>(receive);
        final worker = await Isolate.spawn(meloWorker, [
          receive.sendPort,
          await model.path,
          Platform.environment['BOOKWORM_SHERPA_LIB']!,
        ]);
        addTearDown(() {
          worker.kill();
          receive.close();
        });
        await stream.moveNext();
        expect(stream.current, isA<SendPort>());
        final send = stream.current as SendPort;
        final wav = '${folder.path}/custom-model-test.wav';
        send.send([1, '书虫网址模型安装测试，离线听书正常。', wav]);
        await stream.moveNext();
        expect(stream.current, [1, true, wav]);
        expect((await File(wav).readAsBytes()).length, greaterThan(10000));
        send.send([2, null]);
        await stream.moveNext();
        expect(stream.current, [2, true, 'closed']);
        await stream.cancel();
      }, ModelNetwork());
    },
    skip: Platform.environment['BOOKWORM_MODEL_URL_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
