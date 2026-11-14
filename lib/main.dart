import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/local_book.dart';
import 'storage/local_library.dart';
import 'importing/book_importer.dart';
import 'cloud/cloud_provider.dart';
import 'cloud/drive_providers.dart';
import 'cloud/icloud_provider.dart';
import 'cloud/library_sync.dart';
import 'screens/reader_screen.dart';
import 'screens/about_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReaderApp());
}

class ReaderApp extends StatelessWidget {
  final LocalLibrary? library;
  const ReaderApp({super.key, this.library});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'BookWorm · 书虫',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff48664e)),
      scaffoldBackgroundColor: const Color(0xfff6f6f0),
      fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei'],
    ),
    home: LibraryScreen(library: library),
  );
}

class LibraryScreen extends StatefulWidget {
  final LocalLibrary? library;
  const LibraryScreen({super.key, this.library});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  static const appMenu = MethodChannel('bookworm/app_menu');
  bool aboutOpen = false;
  Future<void> openAbout() async {
    if (!mounted || aboutOpen) return;
    aboutOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AboutScreen(
            enabledClouds: providers
                .where((p) => p.configured)
                .map((p) => p.name)
                .toList(),
          ),
        ),
      );
    } finally {
      aboutOpen = false;
    }
  }

  LocalLibrary? store;
  List<LocalBook> books = [];
  String? error;
  String status = '';
  String query = '';
  bool busy = false, loading = true, reading = false;
  int tab = 0;
  SharedPreferences? prefs;
  String device = '';
  Timer? autoSync;
  final providers = <CloudProvider>[
    OneDriveProvider.production(),
    ICloudProvider.production(),
    GoogleDriveProvider.production(),
  ];
  CloudProvider? active;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appMenu.setMethodCallHandler((call) async {
      if (call.method == 'showAbout') unawaited(openAbout());
    });
    unawaited(load());
    autoSync = Timer.periodic(const Duration(minutes: 1), (_) {
      if (active != null && !reading && !busy) unawaited(sync());
    });
  }

  @override
  void dispose() {
    appMenu.setMethodCallHandler(null);
    autoSync?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        active != null &&
        !reading &&
        !busy) {
      unawaited(sync());
    }
  }

  Future<void> load() async {
    try {
      prefs = await SharedPreferences.getInstance();
      device =
          prefs!.getString('bookworm_device') ??
          List.generate(
            16,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
      await prefs!.setString('bookworm_device', device);
      store = widget.library ?? await LocalLibrary.open();
      books = await store!.load();
      final cloudName = prefs!.getString('bookworm_cloud');
      active = providers
          .where((p) => p.name == cloudName && p.configured)
          .firstOrNull;
      if (store!.warnings.isNotEmpty) error = store!.warnings.join('\n');
    } catch (e) {
      error = '无法打开本地书库：$e';
    }
    if (mounted) {
      setState(() => loading = false);
      if (active != null) unawaited(sync());
    }
  }

  void toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> refresh() async {
    books = await store!.load();
    if (mounted) setState(() {});
  }

  Future<void> importBook() async {
    if (busy || store == null) return;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'epub', 'pdf'],
      );
      if (files.isEmpty) return;
      final file = files.single;
      if ((await file.length() ?? 0) > BookImporter.maxBytes) {
        toast('请选择不超过 50 MB 的书籍');
        return;
      }
      if (!mounted) return;
      setState(() {
        busy = true;
        status = '正在读取 ${file.name}';
        error = null;
      });
      final bytes = await file.readAsBytes();
      final book = await BookImporter().parse(
        file.name,
        bytes,
        status: (s) {
          if (mounted) setState(() => status = s);
        },
      );
      if (books.any((b) => b.id == book.id)) {
        toast('这本书已在书架，保留原有进度');
        return;
      }
      await store!.source(book.id, bytes);
      await store!.save(book);
      await refresh();
      toast('已导入《${book.title}》');
    } catch (e) {
      toast('导入失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          status = '';
        });
      }
    }
    if (active != null) unawaited(sync());
  }

  Future<void> openBook(LocalBook book, {bool listen = false}) async {
    if (busy || store == null) return;
    reading = true;
    try {
      final bytes = book.format == 'pdf'
          ? await store!.readSource(book.id)
          : null;
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: book,
            source: bytes,
            listen: listen,
            persist: () => store!.save(book),
          ),
        ),
      );
      await refresh();
    } catch (e) {
      toast('无法打开书籍：$e');
    } finally {
      reading = false;
    }
    if (active != null) unawaited(sync());
  }

  Future<void> sync() async {
    final cloud = active;
    if (cloud == null || busy || reading || store == null) return;
    setState(() {
      busy = true;
      status = '连接 ${cloud.name}';
    });
    try {
      final result = await LibrarySync(store!, device).run(
        cloud,
        status: (s) {
          if (mounted) setState(() => status = s);
        },
      );
      await refresh();
      for (final remote in result.positions) {
        if (!mounted) break;
        final b = books.where((b) => b.id == remote.bookId).firstOrNull;
        if (b == null) continue;
        final acknowledgement =
            'sync_ack_${cloud.name}_${remote.bookId}_${remote.device}';
        if ((prefs?.getInt(acknowledgement) ?? -1) >= remote.modified) continue;
        final use = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('《${b.title}》有另一设备的进度'),
            content: Text(
              '本机：第 ${b.section + 1} 节\n另一设备：第 ${remote.section + 1} 节\n\n是否从另一设备的位置继续？本机位置不会被静默覆盖。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('保留本机'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('使用另一进度'),
              ),
            ],
          ),
        );
        if (use == true) {
          b.locate(remote.section, remote.offset);
          await store!.save(b);
        }
        if (use != null) await prefs?.setInt(acknowledgement, remote.modified);
      }
      await refresh();
      await prefs?.setString(
        'bookworm_last_sync',
        DateTime.now().toIso8601String(),
      );
      if (mounted) {
        toast('同步完成：上传 ${result.uploaded} 本，下载 ${result.downloaded} 本');
      }
    } catch (e) {
      toast('同步未完成：$e；本机书籍已保留');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          status = '';
        });
      }
    }
  }

  Future<void> connect(CloudProvider cloud) async {
    if (busy) return;
    if (!cloud.configured) {
      await showCloudUnavailable(context, cloud.name);
      return;
    }
    setState(() {
      busy = true;
      status = '授权 ${cloud.name}';
    });
    try {
      await cloud.connect();
      active = cloud;
      await prefs!.setString('bookworm_cloud', cloud.name);
    } catch (e) {
      toast('连接未完成：$e');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          status = '';
        });
      }
    }
    if (active == cloud) await sync();
  }

  Future<void> remove(LocalBook book) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('移除本机副本？'),
        content: const Text('删除本机保存的书籍和进度。原始导入文件不变。私人云副本保留，下次同步会重新下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('移除本机'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        await store!.remove(book);
        await refresh();
      } catch (e) {
        toast('移除失败：$e');
      }
    }
  }

  Widget cloudPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        '我的私人云',
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 12),
      const Text('只在本人各设备之间传递书籍与读听位置。书籍按普通文件保存，不经过书虫服务器。'),
      const SizedBox(height: 24),
      if (providers.every((p) => !p.configured)) ...[
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('当前测试版尚未启用三家私人云的账号登录。你可以继续使用本地读听；云同步将在完成接入并更新安装包后启用。'),
          ),
        ),
        const SizedBox(height: 12),
      ],
      ...providers.map(
        (cloud) => Card(
          elevation: 0,
          color: Colors.white,
          child: ListTile(
            leading: Icon(
              cloud.name == 'iCloud'
                  ? Icons.cloud_outlined
                  : Icons.cloud_sync_outlined,
            ),
            title: Text(cloud.name),
            subtitle: Text(
              active == cloud
                  ? '当前同步来源'
                  : cloud.configured
                  ? '可以连接'
                  : '本版本尚未启用登录',
            ),
            trailing: cloud.configured
                ? OutlinedButton(
                    onPressed: busy ? null : () => connect(cloud),
                    child: Text(active == cloud ? '重新授权' : '连接'),
                  )
                : TextButton(
                    onPressed: () => showCloudUnavailable(context, cloud.name),
                    child: const Text('查看说明'),
                  ),
          ),
        ),
      ),
      const SizedBox(height: 20),
      if (active != null)
        Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : sync,
              icon: const Icon(Icons.sync),
              label: const Text('立即同步'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      await active!.disconnect();
                      active = null;
                      await prefs!.remove('bookworm_cloud');
                      if (mounted) setState(() {});
                    },
              child: const Text('断开同步'),
            ),
          ],
        ),
      const SizedBox(height: 24),
      const Text(
        '同一书库使用一个主云；连接其他云会切换同步来源。\nApp 打开时、读听返回书架后与停留书架期间会尝试同步。后台同步时机由系统决定。',
        style: TextStyle(color: Colors.grey),
      ),
      if (prefs?.getString('bookworm_last_sync') != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            '最近同步：${prefs!.getString('bookworm_last_sync')!.replaceFirst('T', ' ').split('.').first}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 800;
    final visible = books
        .where(
          (b) => '${b.title} ${b.author}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: tab,
                onDestinationSelected: (v) => setState(() => tab = v),
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    label: Text('书架'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.headphones_outlined),
                    label: Text('听书'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.cloud_outlined),
                    label: Text('私人云'),
                  ),
                ],
              ),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_stories,
                          color: Color(0xff48664e),
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          '书虫',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                          ),
                        ),
                        if (wide) ...[
                          const SizedBox(width: 12),
                          const Text(
                            'BookWorm',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                        const Spacer(),
                        IconButton(
                          tooltip: '关于书虫',
                          onPressed: openAbout,
                          icon: const Icon(Icons.info_outline),
                        ),
                        if (active != null)
                          IconButton(
                            onPressed: busy ? null : sync,
                            tooltip: '同步私人云',
                            icon: const Icon(Icons.sync),
                          ),
                        if (MediaQuery.sizeOf(context).width < 480)
                          IconButton.filled(
                            tooltip: '导入书籍',
                            onPressed: busy || loading || store == null
                                ? null
                                : importBook,
                            icon: const Icon(Icons.add),
                          )
                        else
                          FilledButton.icon(
                            onPressed: busy || loading || store == null
                                ? null
                                : importBook,
                            icon: const Icon(Icons.add),
                            label: const Text('导入书籍'),
                          ),
                      ],
                    ),
                  ),
                  if (busy) ...[
                    const LinearProgressIndicator(),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(status),
                    ),
                  ],
                  if (error != null)
                    MaterialBanner(
                      content: Text(error!),
                      actions: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              error = null;
                              loading = true;
                            });
                            unawaited(load());
                          },
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                            padding: EdgeInsets.symmetric(
                              horizontal: wide ? 40 : 20,
                              vertical: 20,
                            ),
                            children: tab == 2
                                ? [cloudPanel()]
                                : [
                                    Text(
                                      tab == 0 ? '我的书架' : '听书空间',
                                      style: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      tab == 0
                                          ? '把喜欢的文字，留在身边。'
                                          : '从上次停下的那句话，继续听。',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    TextField(
                                      onChanged: (v) =>
                                          setState(() => query = v),
                                      decoration: InputDecoration(
                                        hintText: '搜索书名、作者',
                                        prefixIcon: const Icon(Icons.search),
                                        filled: true,
                                        fillColor: Colors.white,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 28),
                                    if (visible.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 60,
                                        ),
                                        child: Column(
                                          children: [
                                            const Icon(
                                              Icons.menu_book_outlined,
                                              size: 68,
                                              color: Color(0xffa7b39e),
                                            ),
                                            const SizedBox(height: 20),
                                            Text(
                                              query.isEmpty
                                                  ? '从一本书开始'
                                                  : '没有找到这本书',
                                              style: const TextStyle(
                                                fontSize: 22,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            const Text(
                                              '本地导入 TXT、EPUB、PDF · 无需会员听书',
                                              style: TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                            const SizedBox(height: 24),
                                            OutlinedButton.icon(
                                              onPressed: busy || store == null
                                                  ? null
                                                  : importBook,
                                              icon: const Icon(Icons.add),
                                              label: const Text('选择本地文件'),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Wrap(
                                        spacing: 24,
                                        runSpacing: 26,
                                        children: visible
                                            .map(
                                              (b) => SizedBox(
                                                width: wide ? 165 : 145,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    InkWell(
                                                      onTap: () => openBook(
                                                        b,
                                                        listen: tab == 1,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      child: Container(
                                                        height: 210,
                                                        width: 165,
                                                        padding:
                                                            const EdgeInsets.all(
                                                              20,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              [
                                                                const Color(
                                                                  0xffdce4d5,
                                                                ),
                                                                const Color(
                                                                  0xffe9dfd0,
                                                                ),
                                                                const Color(
                                                                  0xffdce3e7,
                                                                ),
                                                              ][books.indexOf(
                                                                    b,
                                                                  ) %
                                                                  3],
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          boxShadow: const [
                                                            BoxShadow(
                                                              color: Color(
                                                                0x16000000,
                                                              ),
                                                              blurRadius: 12,
                                                              offset: Offset(
                                                                3,
                                                                6,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Container(
                                                              width: 24,
                                                              height: 3,
                                                              color:
                                                                  const Color(
                                                                    0xff48664e,
                                                                  ),
                                                            ),
                                                            const SizedBox(
                                                              height: 20,
                                                            ),
                                                            Text(
                                                              b.title,
                                                              maxLines: 4,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: const TextStyle(
                                                                fontSize: 23,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            const Spacer(),
                                                            Text(
                                                              b.author,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            b.title,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                          ),
                                                        ),
                                                        PopupMenuButton<String>(
                                                          tooltip: '书籍操作',
                                                          onSelected: (s) {
                                                            if (s == 'remove') {
                                                              unawaited(
                                                                remove(b),
                                                              );
                                                            } else {
                                                              unawaited(
                                                                openBook(
                                                                  b,
                                                                  listen: true,
                                                                ),
                                                              );
                                                            }
                                                          },
                                                          itemBuilder: (_) =>
                                                              const [
                                                                PopupMenuItem(
                                                                  value:
                                                                      'listen',
                                                                  child: Text(
                                                                    '从当前位置听书',
                                                                  ),
                                                                ),
                                                                PopupMenuItem(
                                                                  value:
                                                                      'remove',
                                                                  child: Text(
                                                                    '移除本机副本',
                                                                  ),
                                                                ),
                                                              ],
                                                        ),
                                                      ],
                                                    ),
                                                    Text(
                                                      '${b.format.toUpperCase()} · ${(b.progress * 100).round()}% · 仅本人',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    const SizedBox(height: 30),
                                    const Text(
                                      '私人书籍保存在本机；连接私人云后可在本人设备间同步。',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (v) => setState(() => tab = v),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  label: '书架',
                ),
                NavigationDestination(
                  icon: Icon(Icons.headphones_outlined),
                  label: '听书',
                ),
                NavigationDestination(
                  icon: Icon(Icons.cloud_outlined),
                  label: '私人云',
                ),
              ],
            ),
    );
  }
}
