import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../settings/language_settings.dart';

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
      ],
    );
  }
}
