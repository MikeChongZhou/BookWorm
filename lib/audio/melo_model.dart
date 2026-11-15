import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared, device-local model installation. Books and cloud storage are untouched.
class MeloModel extends ChangeNotifier {
  static final instance = MeloModel();
  static const folder = 'vits-melo-tts-zh_en';
  static const archiveHash =
      'e58351ed7149f290a54534538badd4077cdbe6fddc964b24d0bee870415d1514';
  static const archiveBytes = 167006755;
  String selected = 'system';
  bool installed = false, busy = false;
  int received = 0;
  String? error;
  String phase = '';
  Future<void>? _loading;
  Future<Directory> get root async => Directory(
    '${(await getApplicationSupportDirectory()).path}/speech-models',
  );
  Future<String> get path async => '${(await root).path}/$folder';

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    selected =
        (await SharedPreferences.getInstance()).getString(
              'bookworm_speech_engine',
            ) ==
            'melo'
        ? 'melo'
        : 'system';
    installed = await File('${await path}/.complete').exists();
    notifyListeners();
  }

  Future<void> select(String value) async {
    if (value != 'system' && value != 'melo') throw ArgumentError(value);
    if (value == 'melo' && !installed) {
      throw StateError('请先在设置中下载 Melo 离线语音');
    }
    if (!await (await SharedPreferences.getInstance()).setString(
      'bookworm_speech_engine',
      value,
    )) {
      throw StateError('无法保存语音设置');
    }
    selected = value;
    notifyListeners();
  }

  Future<void> install() async {
    if (busy) return;
    busy = true;
    received = 0;
    error = null;
    phase = '下载 Melo 模型中';
    notifyListeners();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    Directory? work;
    try {
      final base = await root;
      await base.create(recursive: true);
      work = await base.createTemp('melo-install-');
      final archive = File('${work.path}/model.tar.bz2');
      final request = await client.getUrl(
        Uri.parse(
          'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$folder.tar.bz2',
        ),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode != 200) {
        throw HttpException('模型下载失败：HTTP ${response.statusCode}');
      }
      final sink = archive.openWrite();
      var lastUpdate = DateTime.now();
      try {
        await for (final bytes in response.timeout(
          const Duration(seconds: 60),
        )) {
          received += bytes.length;
          if (received > archiveBytes) throw const FormatException('模型大小不匹配');
          sink.add(bytes);
          if (DateTime.now().difference(lastUpdate).inMilliseconds > 200) {
            notifyListeners();
            lastUpdate = DateTime.now();
          }
        }
      } finally {
        await sink.close();
      }
      if (received != archiveBytes) throw const FormatException('模型下载不完整');
      phase = '校验并安装 Melo 模型中';
      notifyListeners();
      final digest = await sha256.bind(archive.openRead()).first;
      if (digest.toString() != archiveHash) {
        throw const FormatException('模型校验失败，请重新下载');
      }
      final stagingPath = work.path;
      await compute(extractMelo, stagingPath);
      final destination = Directory(await path);
      if (await destination.exists()) await destination.delete(recursive: true);
      await Directory('${work.path}/$folder').rename(destination.path);
      installed = true;
    } catch (e) {
      error = e.toString();
    } finally {
      client.close(force: true);
      if (work != null && await work.exists()) {
        await work.delete(recursive: true);
      }
      busy = false;
      phase = '';
      notifyListeners();
    }
  }
}

/// File-backed decoding keeps the 182 MiB model out of Dart's UI heap.
void extractMelo(String staging) {
  final compressed = InputFileStream('$staging/model.tar.bz2');
  final tarPath = '$staging/model.tar';
  final output = OutputFileStream(tarPath);
  try {
    BZip2Decoder().decodeStream(compressed, output, verify: true);
  } finally {
    compressed.closeSync();
    output.closeSync();
  }
  final input = InputFileStream(tarPath);
  try {
    final archive = TarDecoder().decodeStream(input, verify: true);
    for (final entry in archive) {
      final parts = entry.name.replaceAll('\\', '/').split('/');
      if (parts.first != MeloModel.folder ||
          parts.contains('..') ||
          entry.isSymbolicLink) {
        throw const FormatException('不安全的模型文件路径');
      }
    }
    extractArchiveToDiskSync(
      archive,
      staging,
      throwOnError: true,
      maxSize: 300 * 1024 * 1024,
    );
  } finally {
    input.closeSync();
  }
  final folder = '$staging/${MeloModel.folder}';
  for (final name in [
    'model.onnx',
    'tokens.txt',
    'lexicon.txt',
    'date.fst',
    'number.fst',
    'phone.fst',
  ]) {
    if (!File('$folder/$name').existsSync()) {
      throw FormatException('模型缺少文件：$name');
    }
  }
  if (!Directory('$folder/dict').existsSync()) {
    throw const FormatException('模型缺少词典');
  }
  File('$folder/.complete').writeAsStringSync(MeloModel.archiveHash);
}
