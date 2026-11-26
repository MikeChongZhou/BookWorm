import 'package:flutter/services.dart';

import 'cloud_provider.dart';

/// Apple's system account and the app's registered iCloud container, with no folder picker.
/// Non-Apple clients use a separate account-based provider; iCloud Drive has no equivalent native API there.
class NativeICloudProvider implements CloudProvider, CloudTransferLimits {
  static const channel = MethodChannel('bookworm/icloud');
  final String container;
  const NativeICloudProvider(this.container);
  factory NativeICloudProvider.production() =>
      const NativeICloudProvider(String.fromEnvironment('ICLOUD_CONTAINER'));
  @override
  int get transferChunkBytes => 1024 * 1024;
  @override
  int get transferWorkers => 2;
  @override
  String get name => 'iCloud';
  @override
  bool get configured =>
      container.startsWith('iCloud.') && container.length > 7;
  static bool validKey(String key) => RegExp(
    r'^(book-[a-f0-9]{64}(?:-\d+\.part|\.manifest)|position-[a-f0-9]{64}-[a-f0-9]+\.json)$',
  ).hasMatch(key);
  Future<T?> call<T>(String method, [Map<String, Object>? arguments]) async {
    if (!configured) throw const CloudFailure('此构建尚未配置 iCloud 容器与登录');
    try {
      return await channel
          .invokeMethod<T>(method, {'container': container, ...?arguments})
          .timeout(const Duration(seconds: 90));
    } on PlatformException catch (e) {
      throw CloudFailure(switch (e.code) {
        'account' => '请在系统设置中登录 Apple 账号并启用 iCloud Drive',
        'configuration' => 'iCloud 容器或签名权限未配置，请更新安装包',
        'downloading' => 'iCloud 正在下载书籍，请稍后重试；本机内容已保留',
        _ => 'iCloud 读写失败，请检查网络和 iCloud Drive 后重试',
      });
    } on MissingPluginException {
      throw const CloudFailure('此安装包没有 iCloud 原生支持，请更新安装包');
    }
  }

  @override
  Future<void> connect() async {
    await call<void>('connect');
  }

  @override
  Future<void> disconnect() async {
    // Disconnecting sync never signs out of the system Apple account or deletes cloud data.
  }
  @override
  Future<List<String>> list() async => (await call<List<Object?>>('list') ?? [])
      .whereType<String>()
      .where(validKey)
      .toList();
  @override
  Future<Uint8List> read(String key) async {
    if (!validKey(key)) {
      throw const CloudFailure('云内容路径不匹配');
    }
    final bytes = await call<Uint8List>('read', {'key': key});
    if (bytes == null || bytes.length > 2 * 1024 * 1024) {
      throw const CloudFailure('iCloud 文件格式无效');
    }
    return bytes;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (!validKey(key) || bytes.length > 2 * 1024 * 1024) {
      throw const CloudFailure('iCloud 文件格式无效');
    }
    await call<void>('write', {'key': key, 'bytes': bytes});
  }
}
