import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../translation/translation_settings.dart';
import '../translation/online_services.dart';
import '../translation/openrouter_login.dart';

import 'package:url_launcher/url_launcher.dart';

class TranslationSettingsCard extends StatefulWidget {
  const TranslationSettingsCard({super.key});
  @override
  State<TranslationSettingsCard> createState() =>
      _TranslationSettingsCardState();
}

class _TranslationSettingsCardState extends State<TranslationSettingsCard> {
  final settings = TranslationSettings.instance;
  String? error;
  bool authorized = false, loggingIn = false;
  final loginService = OpenRouterLogin();
  @override
  void initState() {
    super.initState();
    settings.load().then((_) => refreshCredential()).catchError((Object e) {
      if (mounted) setState(() => error = '$e');
    });
  }

  Future<void> save(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> refreshCredential() async {
    if (settings.provider != 'online' || settings.onlineEndpoint.isEmpty) {
      if (mounted) setState(() => authorized = false);
      return;
    }
    final present = await settings.hasOnlineCredential;
    if (mounted) setState(() => authorized = present);
  }

  Future<void> bindOpenRouter() async {
    setState(() {
      loggingIn = true;
      error = null;
    });
    try {
      final key = await loginService.login();
      // Bind only to OpenRouter's fixed endpoint, never an editable redirect.
      await settings.update(
        provider: 'online',
        endpoint: OnlineTranslationService.byId('openrouter').endpoint,
        apiKey: key,
      );
      await refreshCredential();
    } catch (_) {
      if (mounted) setState(() => error = context.tr('登录未完成，请重试或手动绑定 API 密钥'));
    } finally {
      if (mounted) setState(() => loggingIn = false);
    }
  }

  Future<void> openKeyPage() async {
    final service = OnlineTranslationService.byId(settings.onlineService);
    try {
      if (service.keyPage.isEmpty ||
          !await launchUrl(
            Uri.parse(service.keyPage),
            mode: LaunchMode.externalApplication,
          )) {
        throw StateError('无法打开服务页面');
      }
    } catch (_) {
      if (mounted) setState(() => error = context.tr('无法打开服务页面'));
    }
  }

  Future<void> configure() async {
    final local = settings.provider == 'local';
    final preset = OnlineTranslationService.byId(settings.onlineService);
    final endpoint = TextEditingController(text: settings.endpoint);
    final model = TextEditingController(text: settings.model);
    final key = TextEditingController();
    String? dialogError;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(context.tr(local ? '本地翻译服务' : '在线翻译服务')),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr(
                      local
                          ? '连接本机或局域网 Ollama。手机上的 localhost 指手机本身。Android 局域网请使用电脑的 .local 主机名或 HTTPS 地址。不会自动下载模型。'
                          : '支持 OpenAI 兼容的 Chat Completions 服务。启用在线翻译后，当前段落、书名和章节会发送到此服务；可能产生服务费用。',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (local || preset.id == 'custom')
                    TextField(
                      controller: endpoint,
                      decoration: InputDecoration(
                        labelText: context.tr(
                          local ? 'Ollama 地址' : 'API 基础地址（例如 https://服务地址/v1）',
                        ),
                      ),
                    ),
                  TextField(
                    controller: model,
                    decoration: InputDecoration(labelText: context.tr('模型名称')),
                  ),
                  if (!local)
                    TextField(
                      controller: key,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: context.tr('API 密钥（留空保留已有密钥）'),
                      ),
                    ),
                  if (dialogError != null)
                    Text(
                      dialogError!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(context.tr('取消')),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  if (model.text.trim().isEmpty) throw StateError('请填写模型名称');
                  TranslationSettings.validateEndpoint(
                    endpoint.text.trim(),
                    local: local,
                  );
                  await settings.update(
                    endpoint: endpoint.text,
                    model: model.text,
                    apiKey: key.text.trim().isEmpty ? null : key.text,
                  );
                  if (c.mounted) Navigator.pop(c);
                } catch (e) {
                  update(() => dialogError = '$e');
                }
              },
              child: Text(context.tr('保存')),
            ),
          ],
        ),
      ),
    );
    await refreshCredential();
    endpoint.dispose();
    model.dispose();
    key.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('翻译阅读'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(context.tr('每段依次播放：原文 → 译文 → 可选背景介绍 → 原文复读。')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('开启翻译阅读')),
              value: settings.enabled,
              onChanged: (v) => save(() => settings.update(enabled: v)),
            ),
            DropdownButtonFormField<String>(
              key: ValueKey('translation-provider-${settings.provider}'),
              initialValue: settings.provider,
              decoration: InputDecoration(labelText: context.tr('翻译方式')),
              items: [
                DropdownMenuItem(
                  value: 'local',
                  child: Text(context.tr('本地模型（Ollama）')),
                ),
                DropdownMenuItem(
                  value: 'online',
                  child: Text(context.tr('在线服务')),
                ),
              ],
              onChanged: (v) {
                if (v != null && !loggingIn) {
                  save(() async {
                    if (v == 'online' && settings.onlineEndpoint.isEmpty) {
                      await settings.selectService('openrouter');
                    } else {
                      await settings.update(provider: v);
                    }
                    await refreshCredential();
                  });
                }
              },
            ),
            if (settings.provider == 'online') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('translation-service-${settings.onlineService}'),
                initialValue: settings.onlineService,
                decoration: InputDecoration(labelText: context.tr('在线翻译服务')),
                items: OnlineTranslationService.all
                    .map(
                      (s) => DropdownMenuItem(
                        value: s.id,
                        child: Text(context.tr(s.name)),
                      ),
                    )
                    .toList(),
                onChanged: loggingIn
                    ? null
                    : (v) {
                        if (v != null) {
                          save(() async {
                            await settings.selectService(v);
                            await refreshCredential();
                          });
                        }
                      },
              ),
              if (OnlineTranslationService.byId(settings.onlineService)
                  .models
                  .isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'preset-model-${settings.onlineService}-${settings.onlineModel}',
                  ),
                  initialValue: settings.onlineModel,
                  decoration: InputDecoration(labelText: context.tr('翻译模型')),
                  items:
                      {
                            ...OnlineTranslationService.byId(
                              settings.onlineService,
                            ).models,
                            settings.onlineModel,
                          }
                          .where((m) => m.isNotEmpty)
                          .map(
                            (m) => DropdownMenuItem(value: m, child: Text(m)),
                          )
                          .toList(),
                  onChanged: loggingIn
                      ? null
                      : (v) {
                          if (v != null) save(() => settings.update(model: v));
                        },
                ),
              ],
              const SizedBox(height: 8),
              Text(context.tr('地址和默认模型已自动填写；在线调用使用服务商的 API 额度，可能产生费用。')),
              Text(context.tr(authorized ? '已安全保存授权' : '尚未绑定授权')),
              if (settings.onlineService == 'openrouter')
                FilledButton.icon(
                  onPressed: loggingIn ? null : bindOpenRouter,
                  icon: const Icon(Icons.login),
                  label: Text(
                    context.tr(loggingIn ? '正在等待登录授权' : '登录 OpenRouter 并授权'),
                  ),
                ),
              if (settings.onlineService == 'openai' ||
                  settings.onlineService == 'gemini') ...[
                Text(context.tr('网页账号登录不等于 API 授权；请登录官方页面获取 API 密钥，首次绑定一次即可。')),
                OutlinedButton.icon(
                  onPressed: loggingIn ? null : openKeyPage,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(context.tr('登录官方页面并获取密钥')),
                ),
              ],
              if (authorized)
                TextButton(
                  onPressed: loggingIn
                      ? null
                      : () => save(() async {
                          await settings.clearOnlineCredential();
                          await refreshCredential();
                        }),
                  child: Text(context.tr('移除本机授权')),
                ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('translation-target-${settings.targetLanguage}'),
              initialValue: settings.targetLanguage,
              decoration: InputDecoration(labelText: context.tr('目标语言')),
              items: TranslationSettings.languages.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        e.key == 'system' ? context.tr(e.value) : e.value,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) save(() => settings.update(targetLanguage: v));
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('加入背景介绍')),
              subtitle: Text(context.tr('与播放页面共用此开关；模型生成的背景介绍仅供辅助理解。')),
              value: settings.includeBackground,
              onChanged: (v) =>
                  save(() => settings.update(includeBackground: v)),
            ),
            OutlinedButton.icon(
              onPressed: loggingIn ? null : configure,
              icon: const Icon(Icons.tune),
              label: Text(context.tr('配置翻译服务')),
            ),
            Text(context.tr('朗读使用当前语音引擎；Melo 仅支持中文和英文，其他语言请选择系统语音并安装对应音色。')),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
  );
}
