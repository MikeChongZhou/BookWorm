import 'dart:convert';

import 'online_services.dart';

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TranslationSettings extends ChangeNotifier {
  static final instance = TranslationSettings();
  bool enabled = false, includeBackground = true;
  String targetLanguage = 'system', provider = 'local';
  String localEndpoint = 'http://127.0.0.1:11434', localModel = '';
  String get onlineService =>
      OnlineTranslationService.forEndpoint(onlineEndpoint).id;
  String onlineEndpoint = '', onlineModel = '';
  static const languages = {
    'system': '跟随系统',
    'zh': '简体中文',
    'en': 'English',
    'es': 'Español',
    'ja': '日本語',
    'fr': 'Français',
    'de': 'Deutsch',
  };
  static const locales = {
    'zh': 'zh-CN',
    'en': 'en-US',
    'es': 'es-ES',
    'ja': 'ja-JP',
    'fr': 'fr-FR',
    'de': 'de-DE',
  };
  String get resolvedTarget => targetLanguage == 'system'
      ? PlatformDispatcher.instance.locale.toLanguageTag()
      : targetLanguage;
  String get endpoint => provider == 'local' ? localEndpoint : onlineEndpoint;
  String get model => provider == 'local' ? localModel : onlineModel;
  String get fingerprint => '$provider|$endpoint|$model|$resolvedTarget';
  static const secure = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool('translation_enabled') ?? false;
    includeBackground = p.getBool('translation_background') ?? true;
    final target = p.getString('translation_target') ?? 'system';
    targetLanguage = languages.containsKey(target) ? target : 'system';
    provider = p.getString('translation_provider') == 'online'
        ? 'online'
        : 'local';
    localEndpoint = p.getString('translation_local_endpoint') ?? localEndpoint;
    localModel = p.getString('translation_local_model') ?? '';
    onlineEndpoint = p.getString('translation_online_endpoint') ?? '';
    onlineModel = p.getString('translation_online_model') ?? '';
    final defaults = OnlineTranslationService.forEndpoint(onlineEndpoint)
        .models;
    if (onlineModel.isEmpty && defaults.isNotEmpty) {
      onlineModel = defaults.first;
    }
    notifyListeners();
  }

  Future<void> update({
    bool? enabled,
    bool? includeBackground,
    String? targetLanguage,
    String? provider,
    String? endpoint,
    String? model,
    String? apiKey,
    bool toggleBackground = false,
  }) async {
    await load();
    final task = _writes.catchError((_) {}).then((_) async {
      if (targetLanguage != null && !languages.containsKey(targetLanguage)) {
        throw ArgumentError('Unsupported target language');
      }
      final nextProvider = provider ?? this.provider;
      if (!['local', 'online'].contains(nextProvider)) {
        throw ArgumentError('Invalid provider');
      }
      final p = await SharedPreferences.getInstance();
      final nextEnabled = enabled ?? this.enabled;
      final nextBackground = toggleBackground
          ? !this.includeBackground
          : includeBackground ?? this.includeBackground;
      final nextTarget = targetLanguage ?? this.targetLanguage;
      final nextEndpoint =
          endpoint?.trim() ??
          (nextProvider == 'local' ? localEndpoint : onlineEndpoint);
      final nextModel =
          model?.trim() ?? (nextProvider == 'local' ? localModel : onlineModel);
      if (endpoint != null && nextEndpoint.isNotEmpty) {
        validateEndpoint(nextEndpoint, local: nextProvider == 'local');
      }
      if (apiKey != null) {
        await secure.write(
          key: credentialKey(nextEndpoint),
          value: apiKey.trim(),
        );
      }
      for (final entry in {
        'translation_enabled': nextEnabled,
        'translation_background': nextBackground,
      }.entries) {
        if (!await p.setBool(entry.key, entry.value)) {
          throw StateError('无法保存翻译阅读设置');
        }
      }
      for (final entry in {
        'translation_target': nextTarget,
        'translation_provider': nextProvider,
        'translation_${nextProvider}_endpoint': nextEndpoint,
        'translation_${nextProvider}_model': nextModel,
      }.entries) {
        if (!await p.setString(entry.key, entry.value)) {
          throw StateError('无法保存翻译阅读设置');
        }
      }
      this.enabled = nextEnabled;
      this.includeBackground = nextBackground;
      this.targetLanguage = nextTarget;
      this.provider = nextProvider;
      if (nextProvider == 'local') {
        localEndpoint = nextEndpoint;
        localModel = nextModel;
      } else {
        onlineEndpoint = nextEndpoint;
        onlineModel = nextModel;
      }
      notifyListeners();
    });
    _writes = task;
    await task;
  }

  Future<void> toggleBackground() => update(toggleBackground: true);
  Future<void> selectService(String id) async {
    await load();
    final service = OnlineTranslationService.byId(id);
    if (service.id == 'custom') {
      await update(
        provider: 'online',
        endpoint: onlineService == 'custom' ? onlineEndpoint : '',
        model: onlineService == 'custom' ? onlineModel : '',
      );
      return;
    }
    await update(
      provider: 'online',
      endpoint: service.endpoint,
      model: service.models.first,
    );
  }

  Future<bool> get hasOnlineCredential async =>
      (await secure.read(key: credentialKey(onlineEndpoint)))?.isNotEmpty ??
      false;
  Future<void> clearOnlineCredential() async {
    await secure.delete(key: credentialKey(onlineEndpoint));
    notifyListeners();
  }

  static String credentialKey(String endpoint) =>
      'translation_online_${sha256.convert(utf8.encode(endpoint.replaceFirst(RegExp(r"/$"), "")))}';
  static Uri validateEndpoint(String value, {required bool local}) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (local
            ? !['http', 'https'].contains(uri.scheme)
            : uri.scheme != 'https')) {
      throw const FormatException('请填写有效服务地址；在线服务必须使用 HTTPS，地址中不要包含密钥');
    }
    if (local && uri.scheme == 'http') {
      final host = uri.host.toLowerCase();
      final namedLocal = host == 'localhost' || host.endsWith('.local');
      final loopback =
          host == '127.0.0.1' || host == '::1' || host == '10.0.2.2';
      final ip = InternetAddress.tryParse(host);
      final bytes = ip?.rawAddress;
      final privateIp =
          bytes != null &&
          bytes.length == 4 &&
          (bytes[0] == 10 ||
              (bytes[0] == 192 && bytes[1] == 168) ||
              (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31));
      if (!namedLocal && !loopback && (!privateIp || Platform.isAndroid)) {
        throw const FormatException(
          'HTTP 仅用于本机或私人局域网；Android 请选择 .local 主机名或 HTTPS 地址',
        );
      }
    }
    return uri;
  }
}
