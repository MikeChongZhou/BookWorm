import 'package:flutter/material.dart';

import '../history/reading_history.dart';
import '../models/local_book.dart';
import '../l10n/app_strings.dart';

class HistoryPanel extends StatelessWidget {
  final List<LocalBook> books;
  final void Function(LocalBook) open;
  final ReadingHistory? history;
  const HistoryPanel({
    super.key,
    required this.books,
    required this.open,
    this.history,
  });
  String time(BuildContext context, int ms) {
    final minutes = ms ~/ 60000;
    return '${minutes ~/ 60} ${context.tr('小时')} ${minutes % 60} ${context.tr('分钟')}';
  }

  @override
  Widget build(BuildContext context) {
    final store = history ?? ReadingHistory.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final finished = books.where((b) => store.record(b).completed).toList();
        final reading = books
            .where((b) => store.record(b).started && !store.record(b).completed)
            .toList();
        final unread = books
            .where(
              (b) => !store.record(b).started && !store.record(b).completed,
            )
            .toList();
        final total = store.records.values.fold<int>(
          0,
          (sum, r) => sum + r.milliseconds,
        );
        Widget list(List<LocalBook> items, {bool finishedList = false}) =>
            items.isEmpty
            ? Center(child: Text(context.tr('暂无书籍')))
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final b = items[index];
                  final r = store.record(b);
                  return ListTile(
                    leading: Icon(
                      r.completed ? Icons.task_alt : Icons.menu_book_outlined,
                    ),
                    title: Text(b.title),
                    subtitle: Text(
                      '${b.author}\n${context.tr('读听时长')} · ${time(context, r.milliseconds)}',
                    ),
                    isThreeLine: true,
                    onTap: () => open(b),
                    trailing: PopupMenuButton<String>(
                      tooltip: context.tr('阅读状态'),
                      onSelected: (_) => store.complete(b, value: !r.completed),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'complete',
                          child: Text(
                            context.tr(r.completed ? '设为在读' : '标记读完'),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
        return DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  context.tr('阅读历史'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '${context.tr('累计读听时长')}\n${time(context, total)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: Text('${context.tr('读完')} ${finished.length}'),
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (c) => SizedBox(
                          height: MediaQuery.sizeOf(c).height * .7,
                          child: ListenableBuilder(
                            listenable: store,
                            builder: (_, _) => list(
                              books
                                  .where((b) => store.record(b).completed)
                                  .toList(),
                              finishedList: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Chip(label: Text('${context.tr('在读')} ${reading.length}')),
                    Chip(label: Text('${context.tr('未读')} ${unread.length}')),
                    Chip(label: Text('${context.tr('总书籍')} ${books.length}')),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  context.tr('时长从此版本起记录，包含阅读和听书，仅保存在本机。'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TabBar(
                tabs: [
                  Tab(text: context.tr('在读')),
                  Tab(text: context.tr('未读')),
                ],
              ),
              Expanded(
                child: TabBarView(children: [list(reading), list(unread)]),
              ),
            ],
          ),
        );
      },
    );
  }
}
