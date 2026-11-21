import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

import '../downloads/book_catalog.dart';
import '../downloads/custom_sources.dart';

class SourcesScreen extends StatefulWidget {
  final BookCatalog catalog;
  const SourcesScreen({super.key, required this.catalog});
  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  final url = TextEditingController();
  String? error, previewUrl;
  bool busy = false;
  List<CatalogBook> preview = [];
  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  Future<void> scan() async {
    setState(() {
      busy = true;
      error = null;
      preview = [];
      previewUrl = null;
    });
    try {
      final normalized = sourceUri(url.text).toString();
      final found = await widget.catalog.scanSource(normalized);
      if (mounted) {
        setState(() {
          preview = found;
          previewUrl = normalized;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('管理书源'))),
    body: ListenableBuilder(
      listenable: widget.catalog,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            context.tr(
              '输入单本或多本书籍汇集网站。支持 OPDS、静态网页中的 EPUB／PDF／TXT 下载链接和同站分页；每次最多扫描 30 页、1000 本。需要登录或 JavaScript 的网站需单独适配。',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: context.tr('书籍网站网址'),
              hintText: 'https://…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy ? null : scan,
            child: Text(context.tr(busy ? '正在检查连接并识别书籍…' : '检查连接并预览')),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (preview.isNotEmpty) ...[
            Text(context.tr('找到 ${preview.length} 本书，确认来源与下载权限后添加。')),
            for (final b in preview.take(10))
              ListTile(
                title: Text(b.title),
                subtitle: Text(b.pageUrl, maxLines: 2),
              ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await widget.catalog.addSource(previewUrl!, preview);
                        if (mounted) {
                          setState(() {
                            preview = [];
                            url.clear();
                          });
                        }
                      } catch (e) {
                        if (mounted) setState(() => error = '$e');
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: Text(context.tr('添加此书源')),
            ),
          ],
          const Divider(),
          ListTile(
            title: Text(context.tr('内置书源')),
            subtitle: Text(
              context.tr(
                '文硕阁（GitHub）\nStandard Ebooks\n大陆可用性需在当前网络检查，网页可访问不代表文件可下载。',
              ),
            ),
          ),
          for (final source in widget.catalog.customSources)
            ListTile(
              title: Text(source),
              subtitle: Text(context.tr('每天随目录检查更新；移除书源保留已下载书籍')),
              trailing: IconButton(
                tooltip: context.tr('移除书源'),
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: busy
                    ? null
                    : () => widget.catalog.removeSource(source),
              ),
            ),
        ],
      ),
    ),
  );
}
