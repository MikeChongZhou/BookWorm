import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import 'cloud_provider.dart';

/// Uses only the signed-in user's CloudKit PRIVATE database. Never a platform relay.
class ICloudProvider implements CloudProvider {
  final String container, apiToken, environment, redirect;
  final http.Client client;
  final FlutterSecureStorage storage;
  String? _token;
  ICloudProvider({
    required this.container,
    required this.apiToken,
    required this.redirect,
    this.environment = 'production',
    http.Client? client,
    FlutterSecureStorage? storage,
  }) : client = client ?? http.Client(),
       storage =
           storage ??
           const FlutterSecureStorage(
             mOptions: MacOsOptions(usesDataProtectionKeychain: false),
           );
  factory ICloudProvider.production() => ICloudProvider(
    container: const String.fromEnvironment('ICLOUD_CONTAINER'),
    apiToken: const String.fromEnvironment('ICLOUD_API_TOKEN'),
    redirect: const String.fromEnvironment(
      'ICLOUD_REDIRECT_URI',
      defaultValue: 'bookworm://cloudkit',
    ),
    environment: const String.fromEnvironment(
      'ICLOUD_ENVIRONMENT',
      defaultValue: 'production',
    ),
  );
  @override
  String get name => 'iCloud';
  @override
  bool get configured => container.isNotEmpty && apiToken.isNotEmpty;
  Future<Map<String, dynamic>> _call(
    String operation,
    Map<String, dynamic>? body, {
    bool allowLogin = false,
  }) async {
    if (!configured) throw const CloudFailure('此构建尚未配置 iCloud 容器与登录');
    _token ??= await storage.read(key: 'bookworm_cloudkit_token');
    final url = Uri.https(
      'api.apple-cloudkit.com',
      '/database/1/$container/$environment/private/$operation',
      {'ckAPIToken': apiToken, 'ckWebAuthToken': ?_token},
    );
    late http.Response response;
    try {
      response = body == null
          ? await client.get(url).timeout(const Duration(seconds: 45))
          : await client
                .post(
                  url,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(body),
                )
                .timeout(const Duration(seconds: 45));
    } catch (_) {
      // CloudKit puts user tokens in query parameters: never surface a raw client exception URI.
      throw const CloudFailure('iCloud 网络请求失败，请检查网络后重试');
    }
    final result = Map<String, dynamic>.from(jsonDecode(response.body));
    if (result['ckWebAuthToken'] is String) {
      _token = result['ckWebAuthToken'];
      await storage.write(key: 'bookworm_cloudkit_token', value: _token);
    }
    if (result['serverErrorCode'] == 'AUTHENTICATION_REQUIRED') {
      if (!allowLogin) throw const CloudFailure('iCloud 授权已失效，请重新连接');
      final login = Uri.parse(result['redirectURL'] as String);
      if (login.scheme != 'https' ||
          !(login.host == 'apple.com' ||
              login.host.endsWith('.apple.com') ||
              login.host == 'icloud.com' ||
              login.host.endsWith('.icloud.com'))) {
        throw const CloudFailure('iCloud 登录地址无效');
      }
      final callback = Uri.parse(
        await FlutterWebAuth2.authenticate(
          url: login.toString(),
          callbackUrlScheme: Platform.isWindows
              ? redirect
              : Uri.parse(redirect).scheme,
          options: const FlutterWebAuth2Options(useWebview: false),
        ),
      );
      _token = callback.queryParameters['ckWebAuthToken'];
      if (_token == null) throw const CloudFailure('未完成 Apple 私人云授权');
      await storage.write(key: 'bookworm_cloudkit_token', value: _token);
      return _call(operation, body);
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        result['serverErrorCode'] != null) {
      throw CloudFailure(
        'iCloud 操作失败：${result['serverErrorCode'] ?? response.statusCode}',
      );
    }
    return result;
  }

  @override
  Future<void> connect() async {
    await _call('users/current', null, allowLogin: true);
  }

  @override
  Future<void> disconnect() async {
    _token = null;
    await storage.delete(key: 'bookworm_cloudkit_token');
  }

  @override
  Future<List<String>> list() async {
    final keys = <String>[];
    String? marker;
    do {
      final result = await _call('records/query', {
        'query': {'recordType': 'BookWormObject'},
        'desiredKeys': ['key'],
        'resultsLimit': 200,
        'continuationMarker': ?marker,
      });
      for (final r in result['records'] as List? ?? []) {
        if (r['serverErrorCode'] != null) continue;
        final key = r['fields']?['key']?['value'];
        if (key is String) keys.add(key);
      }
      marker = result['continuationMarker'] as String?;
    } while (marker != null);
    return keys;
  }

  String _record(String key) => sha256.convert(utf8.encode(key)).toString();
  @override
  Future<Uint8List> read(String key) async {
    final r = await _call('records/lookup', {
      'records': [
        {'recordName': _record(key)},
      ],
    });
    final records = r['records'] as List;
    if (records.isEmpty || records.first['serverErrorCode'] != null) {
      throw const CloudFailure('iCloud 文件不存在或不可读取');
    }
    final content = records.first['fields']?['data']?['value'];
    if (content is! String) throw const CloudFailure('iCloud 文件格式无效');
    return base64Decode(content);
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (bytes.length > 256 * 1024) throw const CloudFailure('iCloud 单块数据超过限制');
    final result = await _call('records/modify', {
      'operations': [
        {
          'operationType': 'forceUpdate',
          'record': {
            'recordName': _record(key),
            'recordType': 'BookWormObject',
            'fields': {
              'key': {'value': key, 'type': 'STRING'},
              'data': {'value': base64Encode(bytes), 'type': 'STRING'},
            },
          },
        },
      ],
    });
    for (final r in result['records'] as List? ?? []) {
      if (r['serverErrorCode'] != null) {
        throw CloudFailure('iCloud 写入失败：${r['serverErrorCode']}');
      }
    }
  }
}
