import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../settings/language_settings.dart';
import '../audio/melo_model.dart';

class SettingsPanel extends StatelessWidget {
  final VoidCallback openCloud;
  final VoidCallback openAbout;
  const SettingsPanel({
    super.key,
    required this.openCloud,
    required this.openAbout,
  });
  @override
  Widget build(BuildContext context) {
    final language = LanguageScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('设置'),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('应用语言'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey(language.value),
                  initialValue: language.value,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: context.tr('应用语言'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'system',
                      child: Text(context.tr('跟随系统')),
                    ),
                    const DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                    const DropdownMenuItem(value: 'en', child: Text('English')),
                    const DropdownMenuItem(value: 'es', child: Text('Español')),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    try {
                      await language.select(value);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.tr('无法保存语言设置，请重试'))),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),
                Text(context.tr('语言选择会保存在本机，跟随系统时会随系统语言变化。')),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(context.tr('私人云')),
            trailing: const Icon(Icons.chevron_right),
            onTap: openCloud,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(context.tr('关于书虫')),
            trailing: const Icon(Icons.chevron_right),
            onTap: openAbout,
          ),
        ),
        const SpeechSettingsCard(),
      ],
    );
  }
}

class SpeechSettingsCard extends StatefulWidget {
  const SpeechSettingsCard({super.key});
  @override
  State<SpeechSettingsCard> createState() => _SpeechSettingsCardState();
}

class _SpeechSettingsCardState extends State<SpeechSettingsCard> {
  final model = MeloModel.instance;
  String? error;
  int selectionRevision = 0;
  @override
  void initState() {
    super.initState();
    model.load().catchError((Object e) {
      if (mounted) setState(() => error = e.toString());
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('听书语音'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('speech-${model.selected}-$selectionRevision'),
              initialValue: model.selected,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: context.tr('语音引擎'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'system',
                  child: Text(context.tr('系统自带 TTS')),
                ),
                const DropdownMenuItem(
                  value: 'melo',
                  child: Text('MeloTTS · 中文 / English'),
                ),
              ],
              onChanged: model.busy
                  ? null
                  : (value) async {
                      if (value == null) return;
                      setState(() => error = null);
                      if (value == 'melo' && !model.installed) {
                        await model.install();
                      }
                      if (value == 'melo' && !model.installed) {
                        if (mounted) {
                          setState(() {
                            error = model.error;
                            selectionRevision++;
                          });
                        }
                        return;
                      }
                      try {
                        await model.select(value);
                      } catch (e) {
                        if (mounted) setState(() => error = e.toString());
                      } finally {
                        if (mounted) setState(() => selectionRevision++);
                      }
                    },
            ),
            const SizedBox(height: 12),
            Text(context.tr('系统语音使用设备已安装的音色。Melo 首次需下载约 167 MB，安装后可离线听书。')),
            const SizedBox(height: 8),
            Text(context.tr('Melo 暂按语音片段续播，暂停后可能重读当前片段；不提供逐字时间对齐。')),
            if (model.busy)
              Text(
                context.tr(
                  '${model.phase}：${(model.received / MeloModel.archiveBytes * 100).clamp(0, 100).toStringAsFixed(0)}%',
                ),
              ),
            if (!model.busy)
              Text(
                context.tr(model.installed ? 'Melo 离线模型已安装' : 'Melo 离线模型未安装'),
              ),
            if (error != null || model.error != null)
              Text(
                context.tr('语音设置失败：${error ?? model.error}'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (!model.installed && !model.busy)
              TextButton(
                onPressed: () async {
                  await model.install();
                },
                child: Text(context.tr('下载 Melo 离线模型')),
              ),
          ],
        ),
      ),
    ),
  );
}
