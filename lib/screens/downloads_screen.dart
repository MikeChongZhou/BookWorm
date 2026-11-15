import 'package:flutter/material.dart';

import '../downloads/book_catalog.dart';
import '../storage/local_library.dart';
import '../models/local_book.dart';
import '../l10n/app_strings.dart';

class DownloadsPanel extends StatefulWidget {
  final BookCatalog catalog;
  final LocalLibrary? library;
  final void Function(LocalBook) imported;
  const DownloadsPanel({
    super.key,
    required this.catalog,
    required this.library,
    required this.imported,
  });
  @override
  State<DownloadsPanel> createState() => _DownloadsPanelState();
}

class _DownloadsPanelState extends State<DownloadsPanel> {
  String query = '', source = 'all';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.catalog,
    builder: (context, _) {
      final catalog = widget.catalog;
      final normalized = query.trim().toLowerCase();
      final matches = catalog.books
          .where(
            (b) =>
                (source == 'all' || source == b.source) &&
                '${b.title} ${b.author}'.toLowerCase().contains(normalized),
          )
          .toList();
      return CustomScrollView(
        key: const PageStorageKey('public-catalog-scroll'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('公版书下载'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('来源：文硕阁公版书目录、Standard Ebooks。免费下载到本地书架，支持离线读听。'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.tr('公版标注来自书源；Standard Ebooks 按美国公版范围整理，不同地区可能不同。'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) => setState(() => query = value),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      hintText: context.tr('搜索书名、作者'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value in ['all', '文硕阁', 'Standard Ebooks'])
                        ChoiceChip(
                          label: Text(
                            value == 'all' ? context.tr('全部') : value,
                          ),
                          selected: source == value,
                          onSelected: (_) => setState(() => source = value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr(
                            catalog.status.isEmpty
                                ? '书库目录每天检查一次，离线时可搜索缓存目录。'
                                : catalog.status,
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: catalog.refreshing ? null : catalog.refresh,
                        child: Text(context.tr('更新目录')),
                      ),
                    ],
                  ),
                  if (catalog.updated != null)
                    Text(
                      context.tr(
                        '最近更新：${catalog.updated!.toLocal().toString().split('.').first}',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (catalog.error.isNotEmpty)
                    Text(
                      context.tr(catalog.error),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(context.tr('找到 ${matches.length} 本书')),
                ],
              ),
            ),
          ),
          if (matches.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  context.tr(
                    catalog.refreshing
                        ? '目录正在后台更新，可先继续读书或听书。'
                        : '没有找到书籍，可以调整搜索或更新目录。',
                  ),
                ),
              ),
            ),
          SliverList.builder(
            itemCount: matches.length,
            itemBuilder: (c, i) {
              final book = matches[i];
              final status = catalog.downloadStates[book.id];
              final done = catalog.completed.contains(book.id);
              return ListTile(
                key: ValueKey(book.id),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(book.title),
                subtitle: Text(
                  '${book.author}\n${book.source}${status == null ? '' : '\n${context.tr(status)}'}',
                ),
                isThreeLine: true,
                trailing: TextButton.icon(
                  onPressed:
                      widget.library == null || catalog.downloading(book.id)
                      ? null
                      : () => catalog.download(
                          book,
                          widget.library!,
                          widget.imported,
                        ),
                  icon: Icon(
                    done ? Icons.download_done : Icons.download_outlined,
                  ),
                  label: Text(context.tr(done ? '重新下载' : '下载')),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      );
    },
  );
}
