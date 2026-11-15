import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuejian/audio/melo_model.dart';
import 'package:yuejian/audio/melo_speech.dart';

void main() {
  test(
    'verified model extracts and native worker generates then releases',
    () async {
      final staging = await Directory.systemTemp.createTemp(
        'bookworm-melo-test-',
      );
      addTearDown(() => staging.delete(recursive: true));
      await File(Platform.environment['BOOKWORM_MELO_ARCHIVE']!)
          .copy('${staging.path}/model.tar.bz2');
      await Isolate.run(() => extractMelo(staging.path));
      expect(
        await File('${staging.path}/${MeloModel.folder}/.complete')
            .readAsString(),
        MeloModel.archiveHash,
      );
      final receive = ReceivePort();
      final messages = StreamIterator<dynamic>(receive);
      final worker = await Isolate.spawn(meloWorker, [
        receive.sendPort,
        '${staging.path}/${MeloModel.folder}',
        Platform.environment['BOOKWORM_SHERPA_LIB']!,
      ]);
      addTearDown(() {
        worker.kill();
        receive.close();
      });
      await messages.moveNext();
      expect(messages.current, isA<SendPort>());
      final send = messages.current as SendPort;
      final wav = '${staging.path}/test.wav';
      send.send([1, '书虫离线听书测试。今天是2026年11月15日。', wav]);
      await messages.moveNext();
      expect(messages.current, [1, true, wav]);
      final bytes = await File(wav).readAsBytes();
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      expect(bytes.length, greaterThan(10000));
      send.send([2, null]);
      await messages.moveNext();
      expect(messages.current, [2, true, 'closed']);
      await messages.cancel();
    },
    skip: Platform.environment['BOOKWORM_MELO_ARCHIVE'] == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
