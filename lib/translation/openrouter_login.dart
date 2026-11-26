import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

/// The app never handles an account password. PKCE exchanges a one-use code
/// for an account-owned API key; callers store the key in secure storage only.
class OpenRouterLogin {
  final http.Client? client;
  final Future<String> Function(String url, String callback)? authenticate;
  bool _busy = false;
  OpenRouterLogin({this.client, this.authenticate});
  static String randomValue() =>
      base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)))
          .replaceAll('=', '');
  Future<String> login() async {
    if (_busy) throw StateError('登录正在进行');
    _busy = true;
    final transport = client ?? http.Client();
    try {
      final verifier = randomValue(), state = randomValue();
      final challenge = base64UrlEncode(
        sha256.convert(utf8.encode(verifier)).bytes,
      ).replaceAll('=', '');
      final callback = Uri.parse(
        Platform.isWindows ? 'http://localhost:43823/' : 'bookworm://oauth',
      );
      final redirect = callback.replace(queryParameters: {'state': state});
      final url = Uri.https('openrouter.ai', '/auth', {
        'callback_url': redirect.toString(),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      });
      final result = authenticate != null
          ? await authenticate!(
              url.toString(),
              Platform.isWindows ? callback.toString() : callback.scheme,
            )
          : await FlutterWebAuth2.authenticate(
              url: url.toString(),
              callbackUrlScheme: Platform.isWindows
                  ? callback.toString()
                  : callback.scheme,
              options: const FlutterWebAuth2Options(useWebview: false),
            );
      final returned = Uri.parse(result);
      if (returned.userInfo.isNotEmpty ||
          returned.hasFragment ||
          returned.scheme != callback.scheme ||
          returned.host != callback.host ||
          returned.port != callback.port ||
          returned.path != callback.path ||
          returned.queryParameters['state'] != state) {
        throw StateError('登录回调校验失败');
      }
      final code = returned.queryParameters['code'];
      if (code == null || code.isEmpty) throw StateError('未完成 OpenRouter 授权');
      final request =
          http.Request('POST', Uri.https('openrouter.ai', '/api/v1/auth/keys'))
            ..followRedirects = false
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode({
              'code': code,
              'code_verifier': verifier,
              'code_challenge_method': 'S256',
            });
      final response = await http.Response.fromStream(
        await transport.send(request),
      ).timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        throw StateError('OpenRouter 授权交换失败（${response.statusCode}）');
      }
      final value = jsonDecode(response.body);
      final key = value is Map ? value['key'] : null;
      if (key is! String || key.trim().isEmpty || key.length > 2048) {
        throw StateError('OpenRouter 没有返回有效授权');
      }
      return key.trim();
    } on http.ClientException {
      throw StateError('无法连接 OpenRouter，请检查网络');
    } on FormatException {
      throw StateError('OpenRouter 授权响应无效');
    } finally {
      _busy = false;
      if (client == null) transport.close();
    }
  }
}
