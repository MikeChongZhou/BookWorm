import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'cloud_provider.dart';

class OAuthSession {
  final String provider,
      clientId,
      authorizationEndpoint,
      tokenEndpoint,
      scope,
      redirect;
  final http.Client client;
  final FlutterSecureStorage storage;
  String? _access;
  DateTime _expires = DateTime(2000);
  bool _googleInitialized = false;
  OAuthSession({
    required this.provider,
    required this.clientId,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.scope,
    required this.redirect,
    http.Client? client,
    FlutterSecureStorage? storage,
  }) : client = client ?? http.Client(),
       storage =
           storage ??
           const FlutterSecureStorage(
             mOptions: MacOsOptions(usesDataProtectionKeychain: false),
           );
  String random() =>
      base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256)))
          .replaceAll('=', '');
  Future<String> token({bool interactive = false}) async {
    if (provider == 'google' &&
        (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return _nativeGoogle(interactive);
    }
    if (_access != null && DateTime.now().isBefore(_expires)) return _access!;
    final refresh = await storage.read(key: 'bookworm_${provider}_refresh');
    if (refresh != null) {
      try {
        return await _exchange({
          'grant_type': 'refresh_token',
          'refresh_token': refresh,
          'client_id': clientId,
          'scope': scope,
        });
      } on CloudFailure {
        if (!interactive) rethrow;
      }
    }
    if (!interactive) throw const CloudFailure('私人云授权已失效，请重新连接');
    if (clientId.isEmpty) throw const CloudFailure('此构建尚未配置云端登录，请见云配置说明');
    final verifier = random(), state = random();
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final url = Uri.parse(authorizationEndpoint).replace(
      queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': scope,
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        if (provider == 'google') 'access_type': 'offline',
        if (provider == 'google') 'prompt': 'consent',
      },
    );
    final result = Uri.parse(
      await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: Platform.isWindows
            ? redirect
            : Uri.parse(redirect).scheme,
        options: const FlutterWebAuth2Options(useWebview: false),
      ),
    );
    if (result.queryParameters['state'] != state) {
      throw const CloudFailure('云登录校验失败，请重试');
    }
    final code = result.queryParameters['code'];
    if (code == null) throw const CloudFailure('未完成云授权');
    return _exchange({
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': code,
      'redirect_uri': redirect,
      'code_verifier': verifier,
    });
  }

  Future<String> _nativeGoogle(bool interactive) async {
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize(
        clientId: Platform.isAndroid
            ? null
            : (clientId.isEmpty ? null : clientId),
        serverClientId:
            const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID').isEmpty
            ? null
            : const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
      );
      _googleInitialized = true;
    }
    GoogleSignInAccount? account;
    final attempt = GoogleSignIn.instance.attemptLightweightAuthentication();
    if (attempt != null) account = await attempt;
    if (account == null && interactive) {
      account = await GoogleSignIn.instance.authenticate();
    }
    if (account == null) throw const CloudFailure('请连接 Google Drive');
    final scopes = [scope];
    var auth = await account.authorizationClient.authorizationForScopes(scopes);
    if (auth == null && interactive) {
      auth = await account.authorizationClient.authorizeScopes(scopes);
    }
    if (auth == null) throw const CloudFailure('Google Drive 授权不足，请重新连接');
    return auth.accessToken;
  }

  Future<String> _exchange(Map<String, String> data) async {
    final response = await client
        .post(
          Uri.parse(tokenEndpoint),
          body: {
            ...data,
            if (provider == 'google' &&
                Platform.isWindows &&
                const String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET')
                    .isNotEmpty)
              'client_secret': const String.fromEnvironment(
                'GOOGLE_DESKTOP_CLIENT_SECRET',
              ),
          },
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw const CloudFailure('云授权失效，请重新连接');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _access = json['access_token'] as String?;
    if (_access == null) throw const CloudFailure('云服务未返回有效授权');
    _expires = DateTime.now().add(
      Duration(seconds: ((json['expires_in'] as num?)?.toInt() ?? 3600) - 90),
    );
    final refresh = json['refresh_token'] as String?;
    if (refresh != null) {
      await storage.write(key: 'bookworm_${provider}_refresh', value: refresh);
    }
    return _access!;
  }

  Future<http.Response> request(
    String method,
    Uri url, {
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    final token = await this.token();
    final request = http.Request(method, url)
      ..headers.addAll({'Authorization': 'Bearer $token', ...?headers});
    if (body != null) request.bodyBytes = body;
    final response = await http.Response.fromStream(await client.send(request))
        .timeout(const Duration(minutes: 3));
    if (response.statusCode == 401) {
      _access = null;
      _expires = DateTime(2000);
      throw const CloudFailure('私人云授权过期，请重新连接');
    }
    if (response.statusCode == 429) throw const CloudFailure('云服务请求过多，请稍后同步');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudFailure('云操作失败（${response.statusCode}），本机文件已保留');
    }
    return response;
  }

  Future<void> disconnect() async {
    _access = null;
    _expires = DateTime(2000);
    await storage.delete(key: 'bookworm_${provider}_refresh');
    if (provider == 'google' && _googleInitialized) {
      await GoogleSignIn.instance.signOut();
    }
  }
}
