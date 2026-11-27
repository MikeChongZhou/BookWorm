import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../diagnostics/app_log.dart';
import '../l10n/app_strings.dart';

class DiagnosticsCard extends StatefulWidget {
  const DiagnosticsCard({super.key});
  @override
  State<DiagnosticsCard> createState() => _DiagnosticsCardState();
}

class _DiagnosticsCardState extends State<DiagnosticsCard> {
  bool exporting = false;
  late final directory = AppLog.instance.path;

  Future<void> export() async {
    setState(() => exporting = true);
    try {
      AppLog.instance.record('diagnostics', 'export_requested');
      final bytes = await AppLog.instance.export();
      if (!mounted) return;
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        ':',
        '-',
      );
      final result = await FilePicker.saveFile(
        fileName: 'BookWorm-logs-$stamp.txt',
        bytes: bytes,
        mimeType: 'text/plain',
        dialogTitle: context.tr('导出日志'),
      );
      if (mounted && result != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tr('日志已导出'))));
      }
    } catch (e) {
      AppLog.instance.record(
        'diagnostics',
        'export_failed',
        fields: {'errorType': e.runtimeType.toString()},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('日志导出失败，请检查存储空间或保存位置后重试'))),
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('诊断日志'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(context.tr('仅保存在本机，最多约 4 MB；不记录密钥、登录令牌、书籍正文或译文，不自动上传。')),
          const SizedBox(height: 8),
          FutureBuilder<String>(
            future: directory,
            builder: (context, snapshot) => SelectableText(
              snapshot.hasError ? context.tr('无法访问日志目录') : snapshot.data ?? '',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: exporting ? null : export,
            icon: const Icon(Icons.file_download_outlined),
            label: Text(context.tr(exporting ? '正在导出日志' : '导出日志')),
          ),
        ],
      ),
    ),
  );
}
