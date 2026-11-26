import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'translation_settings_card.dart';
import '../settings/language_settings.dart';
import '../audio/melo_model.dart';
import '../audio/book_audio_handler.dart';

import 'package:shared_preferences/shared_preferences.dart';

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
        const TranslationSettingsCard(),
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
  Future<void> customModel() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final url = TextEditingController(text: prefs.getString('custom_melo_url'));
    final hash = TextEditingController(
      text: prefs.getString('custom_melo_hash'),
    );
    final size = TextEditingController(
      text: prefs.getInt('custom_melo_bytes')?.toString(),
    );
    final result = await showDialog<List<String>>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.tr('添加模型网址')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr(
                  '仅接受兼容当前 Melo VITS 中文／英文引擎的 tar.bz2 模型包，目录须为 vits-melo-tts-zh_en，含 ONNX、词表与词典。其他模型架构需额外适配。请确认模型许可证允许使用。',
                ),
              ),
              TextField(
                controller: url,
                decoration: InputDecoration(
                  labelText: context.tr('HTTPS 模型包网址'),
                ),
              ),
              TextField(
                controller: hash,
                decoration: InputDecoration(labelText: 'SHA-256'),
              ),
              TextField(
                controller: size,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: context.tr('文件大小（字节）')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, [
              url.text.trim(),
              hash.text.trim(),
              size.text.trim(),
            ]),
            child: Text(context.tr('校验并安装')),
          ),
        ],
      ),
    );
    // Dialog fields may still be animating out; dispose after the route animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    url.dispose();
    hash.dispose();
    size.dispose();
    if (result == null || !mounted) return;
    final player = BookAudioHandler.instance?.player;
    if (player != null && (player.playing || player.buffering)) {
      setState(() => error = context.tr('请先停止听书再更换模型，当前播放不会被打断'));
      return;
    }
    try {
      if (player != null) {
        await BookAudioHandler.instance?.stop();
        await BookAudioHandler.instance?.detach(player);
        player.dispose();
      }
      await model.install(
        downloadUrl: result[0],
        expectedHash: result[1],
        expectedBytes: int.tryParse(result[2]) ?? 0,
      );
      if (mounted) setState(() => error = model.error);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

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
            TextButton.icon(
              onPressed: model.busy ? null : customModel,
              icon: const Icon(Icons.add_link),
              label: Text(context.tr('添加模型网址')),
            ),
            const SizedBox(height: 8),
            Text(context.tr('Melo 暂按语音片段续播，暂停后可能重读当前片段；不提供逐字时间对齐。')),
            if (model.busy)
              Text(
                context.tr(
                  '${model.phase}：${(model.received / model.totalBytes * 100).clamp(0, 100).toStringAsFixed(0)}%',
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
