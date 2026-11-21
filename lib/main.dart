import 'dart:io';

import 'cloud/native_icloud_provider.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'settings/language_settings.dart';
import 'screens/settings_screen.dart';
import 'l10n/app_strings.dart';

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
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
import 'audio/book_audio_handler.dart';
import 'downloads/book_catalog.dart';
import 'screens/downloads_screen.dart';
import 'screens/history_screen.dart';
import 'history/reading_history.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BookAudioHandler.initialize();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'MeloTTS model · MyShell.ai',
    ], await rootBundle.loadString('assets/licenses/melo.txt'));
  });
  runApp(const ReaderApp());
}

class ReaderApp extends StatefulWidget {
  final LocalLibrary? library;
  final List<CloudProvider>? cloudProviders;
  const ReaderApp({super.key, this.library, this.cloudProviders});
  @override
  State<ReaderApp> createState() => _ReaderAppState();
}

class _ReaderAppState extends State<ReaderApp> {
  final languages = LanguageSettings();
  bool ready = false;
  @override
  void initState() {
    super.initState();
    languages.load().whenComplete(() {
      if (mounted) setState(() => ready = true);
    });
  }

  @override
  void dispose() {
    languages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LanguageScope(
    settings: languages,
    child: ListenableBuilder(
      listenable: languages,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'BookWorm',
        locale: languages.locale,
        supportedLocales: AppStrings.supportedLocales,
        localeResolutionCallback: AppStrings.resolve,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff48664e)),
          scaffoldBackgroundColor: const Color(0xfff6f6f0),
          fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei'],
        ),
        home: ready
            ? LibraryScreen(
                library: widget.library,
                cloudProviders: widget.cloudProviders,
              )
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    ),
  );
}

class LibraryScreen extends StatefulWidget {
  final LocalLibrary? library;
  final List<CloudProvider>? cloudProviders;
  const LibraryScreen({super.key, this.library, this.cloudProviders});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  static const appMenu = MethodChannel('bookworm/app_menu');
  String t(String text) => mounted ? context.tr(text) : text;
  final revision = ValueNotifier(0);
  bool settingsOpen = false;
  bool cloudOpen = false;
  void update(VoidCallback action) {
    if (!mounted) return;
    setState(action);
    revision.value++;
  }

  Future<void> openCloud() async {
    if (!mounted || cloudOpen) return;
    cloudOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (pageContext) => ValueListenableBuilder<int>(
            valueListenable: revision,
            builder: (_, value, child) => Scaffold(
              appBar: AppBar(title: Text(pageContext.tr('私人云'))),
              body: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (status.isNotEmpty) syncStatusBar(),
                  cloudPanel(),
                ],
              ),
            ),
          ),
        ),
      );
    } finally {
      cloudOpen = false;
    }
  }

  Future<void> openSettings() async {
    if (!mounted || settingsOpen) return;
    settingsOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (pageContext) => Scaffold(
            appBar: AppBar(title: Text(pageContext.tr('设置'))),
            body: ListView(
              padding: const EdgeInsets.all(24),
              children: [settingsPanel()],
            ),
          ),
        ),
      );
    } finally {
      settingsOpen = false;
    }
  }

  Widget settingsPanel() =>
      SettingsPanel(openCloud: openCloud, openAbout: openAbout);
  Widget miniPlayer(bool wide, Widget? navigation) {
    final handler = BookAudioHandler.instance;
    if (handler == null) return navigation ?? const SizedBox.shrink();
    return StreamBuilder(
      stream: handler.playbackState,
      builder: (context, snapshot) {
        final p = handler.player;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (p != null && p.ready && !p.disposed)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: SafeArea(
                  top: false,
                  bottom: wide,
                  child: ListTile(
                    leading: const Icon(Icons.headphones_outlined),
                    title: Text(
                      p.book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      p.book.sections[p.book.section].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () =>
                        openBook(p.book, listen: true, autoPlay: false),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: t(p.playing || p.buffering ? '暂停听书' : '播放'),
                          icon: Icon(
                            p.playing || p.buffering
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          onPressed: () async {
                            if (p.playing || p.buffering) {
                              await handler.pause();
                              unawaited(dailySync());
                              if (catalog.deferred) {
                                unawaited(catalog.refreshDaily());
                              }
                            } else {
                              await handler.play();
                            }
                          },
                        ),
                        IconButton(
                          tooltip: t('关闭听书'),
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            await handler.stop();
                            await handler.detach(p);
                            p.dispose();
                            unawaited(dailySync());
                            if (catalog.deferred) {
                              unawaited(catalog.refreshDaily());
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ?navigation,
          ],
        );
      },
    );
  }

  Widget syncStatusBar() => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: Text(status, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (hasRemotePositions)
            TextButton(
              onPressed: busy || consuming ? null : () => sync(),
              child: Text(t('检查其他设备进度')),
            ),
        ],
      ),
    ),
  );
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
  bool syncing = false;
  bool checkingDailySync = false;
  bool deferredCloudSync = false;
  bool hasRemotePositions = false;
  String? openingBook;
  bool get consuming =>
      reading ||
      (BookAudioHandler.instance?.player?.playing ?? false) ||
      (BookAudioHandler.instance?.player?.buffering ?? false);
  int tab = 0;
  SharedPreferences? prefs;
  String device = '';
  Timer? autoSync;
  final catalog = BookCatalog();
  late final providers =
      widget.cloudProviders ??
      <CloudProvider>[
        OneDriveProvider.production(),
        if (Platform.isIOS || Platform.isMacOS)
          NativeICloudProvider.production()
        else
          ICloudProvider.production(),
        GoogleDriveProvider.production(),
      ];
  CloudProvider? active;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    catalog.shouldYield = () => consuming;
    appMenu.setMethodCallHandler((call) async {
      if (call.method == 'showAbout') unawaited(openAbout());
      if (call.method == 'showSettings') unawaited(openSettings());
    });
    unawaited(load());
    autoSync = Timer.periodic(const Duration(hours: 1), (_) {
      unawaited(dailySync());
      if (!consuming) unawaited(catalog.refreshDaily());
    });
  }

  @override
  void dispose() {
    appMenu.setMethodCallHandler(null);
    autoSync?.cancel();
    catalog.dispose();
    revision.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        active != null &&
        !reading &&
        !busy) {
      unawaited(dailySync());
    }
  }

  Future<void> load() async {
    try {
      prefs = await SharedPreferences.getInstance();
      unawaited(ReadingHistory.instance.load());
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
      if (widget.library == null) unawaited(catalog.refreshDaily());
      final cloudName = prefs!.getString('bookworm_cloud');
      active = providers
          .where((p) => p.name == cloudName && p.configured)
          .firstOrNull;
      if (store!.warnings.isNotEmpty) error = store!.warnings.join('\n');
    } catch (e) {
      error = '无法打开本地书库：$e';
    }
    if (mounted) {
      update(() => loading = false);
      if (active != null) unawaited(dailySync());
    }
  }

  void toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> refresh() async {
    books = await store!.load();
    if (mounted) update(() {});
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
        toast(t('请选择不超过 50 MB 的书籍'));
        return;
      }
      if (!mounted) return;
      update(() {
        busy = true;
        status = t('正在读取 ${file.name}');
        error = null;
      });
      final bytes = await file.readAsBytes();
      final book = await BookImporter().parse(
        file.name,
        bytes,
        status: (s) {
          if (mounted) update(() => status = t(s));
        },
      );
      if (books.any((b) => b.id == book.id)) {
        toast(t('这本书已在书架，保留原有进度'));
        return;
      }
      await store!.source(book.id, bytes);
      await store!.save(book);
      await refresh();
      toast(t('已导入《${book.title}》'));
    } catch (e) {
      toast(t('导入失败：$e'));
    } finally {
      if (mounted) {
        update(() {
          busy = false;
          status = '';
        });
      }
    }
    if (active != null) unawaited(dailySync());
  }

  Future<void> openBook(
    LocalBook book, {
    bool listen = false,
    bool autoPlay = true,
  }) async {
    if (store == null || openingBook != null || reading) return;
    if (busy && !syncing) {
      toast(t('正在处理书籍，请稍候'));
      return;
    }
    update(() => openingBook = book.id);
    final current = BookAudioHandler.instance?.player;
    if (current != null && current.book.id == book.id) book = current.book;
    reading = true;
    try {
      await WidgetsBinding.instance.endOfFrame;
      final bytes = book.format == 'pdf'
          ? await store!.readSource(book.id)
          : null;
      if (!mounted) return;
      update(() => openingBook = null);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: book,
            source: bytes,
            listen: listen,
            autoPlay: listen && autoPlay,
            persist: () => store!.save(book),
          ),
        ),
      );
      await refresh();
    } catch (e) {
      toast(t('无法打开书籍：$e'));
    } finally {
      reading = false;
      if (mounted) update(() => openingBook = null);
    }
    if (catalog.deferred && !consuming) unawaited(catalog.refreshDaily());
    if (active != null) unawaited(dailySync());
  }

  Future<void> dailySync() async {
    final cloud = active;
    if (cloud == null ||
        busy ||
        consuming ||
        prefs == null ||
        checkingDailySync) {
      return;
    }
    checkingDailySync = true;
    try {
      final day = DateTime.now().toIso8601String().substring(0, 10);
      final key = 'bookworm_sync_day_${cloud.name}';
      if (prefs!.getString(key) == day && !deferredCloudSync) return;
      // Record the attempt to prevent failed/offline accounts retrying continuously.
      await prefs!.setString(key, day);
      deferredCloudSync = false;
      if (active == cloud) await sync(automatic: true);
    } finally {
      checkingDailySync = false;
    }
  }

  Future<void> sync({bool automatic = false}) async {
    if (consuming) {
      update(() => status = t('同步已延后，优先读书与听书'));
      return;
    }
    final cloud = active;
    if (cloud == null || busy || reading || store == null) return;
    update(() {
      busy = true;
      syncing = true;
      status = t('连接 ${cloud.name}');
    });
    try {
      final result = await LibrarySync(store!, device).run(
        cloud,
        yieldRequested: () => consuming,
        status: (s) {
          if (mounted) update(() => status = t(s));
        },
      );
      deferredCloudSync = result.deferred;
      if (result.deferred) {
        await prefs?.remove('bookworm_sync_day_${cloud.name}');
      }
      if (reading) {
        update(
          () => status = t(
            result.deferred
                ? '同步已延后，优先读书与听书'
                : '同步完成：已上传 ${result.uploaded} 个文件，已下载 ${result.downloaded} 个文件',
          ),
        );
        return;
      }
      await refresh();
      // Sync has already persisted the furthest position, independent of timestamps.
      final player = BookAudioHandler.instance?.player;
      if (player != null && !player.playing && !player.buffering) {
        final merged = books.where((b) => b.id == player.book.id).firstOrNull;
        if (merged != null &&
            LibrarySync.isAhead(
              merged.section,
              merged.offset,
              merged.audioOffsetMs,
              player.book,
            )) {
          player.book.locate(merged.section, merged.offset);
          player.book.audioOffsetMs = merged.audioOffsetMs;
        }
      }
      hasRemotePositions = false;
      await refresh();
      await prefs?.setString(
        'bookworm_last_sync',
        DateTime.now().toIso8601String(),
      );
      await prefs?.setString(
        'bookworm_sync_day_${cloud.name}',
        DateTime.now().toIso8601String().substring(0, 10),
      );
      if (mounted) {
        update(
          () => status =
              t(
                '同步完成：已上传 ${result.uploaded} 个文件，已下载 ${result.downloaded} 个文件',
              ) +
              (hasRemotePositions ? ' · ${t('有其他设备进度，可手动查看')}' : ''),
        );
      }
    } catch (e) {
      if (mounted) update(() => status = t('同步未完成：$e；本机书籍已保留'));
    } finally {
      if (mounted) {
        update(() {
          busy = false;
          syncing = false;
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
    update(() {
      busy = true;
      status = t('授权 ${cloud.name}');
    });
    try {
      await cloud.connect();
      active = cloud;
      await prefs!.setString('bookworm_cloud', cloud.name);
    } catch (e) {
      toast(t('连接未完成：$e'));
    } finally {
      if (mounted) {
        update(() {
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
        title: Text(t('移除本机副本？')),
        content: Text(t('删除本机保存的书籍和进度。原始导入文件不变。私人云副本保留，下次同步会重新下载。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t('移除本机')),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        final handler = BookAudioHandler.instance;
        final current = handler?.player;
        if (current != null && current.book.id == book.id) {
          await handler!.stop();
          await handler.detach(current);
          current.dispose();
        }
        await store!.remove(book);
        await refresh();
      } catch (e) {
        toast(t('移除失败：$e'));
      }
    }
  }

  Widget cloudPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        t('我的私人云'),
        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
      ),
      SizedBox(height: 12),
      Text(t('只在本人各设备之间传递书籍与读听位置。书籍按普通文件保存，不经过书虫服务器。')),
      SizedBox(height: 24),
      if (providers.every((p) => !p.configured)) ...[
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              t('当前测试版尚未启用三家私人云的账号登录。你可以继续使用本地读听；云同步将在完成接入并更新安装包后启用。'),
            ),
          ),
        ),
        SizedBox(height: 12),
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
                  ? t('当前同步来源')
                  : cloud.configured
                  ? t('可以连接')
                  : t('本版本尚未启用登录'),
            ),
            trailing: cloud.configured
                ? OutlinedButton(
                    onPressed: busy ? null : () => connect(cloud),
                    child: Text(active == cloud ? t('重新授权') : t('连接')),
                  )
                : TextButton(
                    onPressed: () => showCloudUnavailable(context, cloud.name),
                    child: Text(t('查看说明')),
                  ),
          ),
        ),
      ),
      SizedBox(height: 20),
      if (active != null)
        Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : sync,
              icon: Icon(Icons.sync),
              label: Text(t('立即同步')),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      await active!.disconnect();
                      active = null;
                      await prefs!.remove('bookworm_cloud');
                      if (mounted) update(() {});
                    },
              child: Text(t('断开同步')),
            ),
          ],
        ),
      SizedBox(height: 24),
      Text(
        t(
          '同一书库使用一个主云；连接其他云会切换同步来源。\n自动同步每天最多一次，读听期间延后执行；也可手动立即同步。应用关闭期间的执行时机由系统决定。',
        ),
        style: TextStyle(color: Colors.grey),
      ),
      if (prefs?.getString('bookworm_last_sync') != null)
        Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            t(
              '最近同步：${prefs!.getString('bookworm_last_sync')!.replaceFirst('T', ' ').split('.').first}',
            ),
            style: TextStyle(fontSize: 12, color: Colors.grey),
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
                onDestinationSelected: (v) => update(() => tab = v),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  NavigationRailDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    label: Text(t('书架')),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.history),
                    label: Text(t('历史')),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.download_outlined),
                    label: Text(t('下载')),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    label: Text(t('设置')),
                  ),
                ],
              ),
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_stories,
                          color: Color(0xff48664e),
                          size: 30,
                        ),
                        SizedBox(width: 12),
                        Text(
                          t('书虫'),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                          ),
                        ),
                        if (wide) ...[
                          SizedBox(width: 12),
                          Text(
                            'BookWorm',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                        Spacer(),
                        IconButton(
                          tooltip: t('关于书虫'),
                          onPressed: openAbout,
                          icon: Icon(Icons.info_outline),
                        ),
                        if (active != null)
                          IconButton(
                            onPressed: busy ? null : sync,
                            tooltip: t('同步私人云'),
                            icon: Icon(Icons.sync),
                          ),
                        if (MediaQuery.sizeOf(context).width < 480)
                          IconButton.filled(
                            tooltip: t('导入书籍'),
                            onPressed: busy || loading || store == null
                                ? null
                                : importBook,
                            icon: Icon(Icons.add),
                          )
                        else
                          FilledButton.icon(
                            onPressed: busy || loading || store == null
                                ? null
                                : importBook,
                            icon: Icon(Icons.add),
                            label: Text(t('导入书籍')),
                          ),
                      ],
                    ),
                  ),
                  if (openingBook != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(t('正在打开书籍…')),
                        ],
                      ),
                    ),
                  if (status.isNotEmpty) syncStatusBar(),
                  if (error != null)
                    MaterialBanner(
                      content: Text(t(error!)),
                      actions: [
                        TextButton(
                          onPressed: () {
                            update(() {
                              error = null;
                              loading = true;
                            });
                            unawaited(load());
                          },
                          child: Text(t('重试')),
                        ),
                      ],
                    ),
                  Expanded(
                    child: tab == 1 && !loading
                        ? HistoryPanel(
                            books: books,
                            open: (book) => openBook(book, listen: false),
                          )
                        : tab == 2
                        ? DownloadsPanel(
                            catalog: catalog,
                            library: store,
                            imported: (book) {
                              books = [
                                book,
                                ...books.where((b) => b.id != book.id),
                              ];
                              if (mounted) update(() {});
                            },
                          )
                        : loading
                        ? Center(child: CircularProgressIndicator())
                        : ListView(
                            padding: EdgeInsets.symmetric(
                              horizontal: wide ? 40 : 20,
                              vertical: 20,
                            ),
                            children: tab == 3
                                ? [settingsPanel()]
                                : [
                                    Text(
                                      tab == 0 ? t('我的书架') : t('听书空间'),
                                      style: TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      tab == 0
                                          ? t('把喜欢的文字，留在身边。')
                                          : t('从上次停下的那句话，继续听。'),
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                    SizedBox(height: 24),
                                    TextField(
                                      onChanged: (v) => update(() => query = v),
                                      decoration: InputDecoration(
                                        hintText: t('搜索书名、作者'),
                                        prefixIcon: Icon(Icons.search),
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
                                    SizedBox(height: 28),
                                    if (visible.isEmpty)
                                      Padding(
                                        padding: EdgeInsets.symmetric(
                                          vertical: 60,
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(
                                              Icons.menu_book_outlined,
                                              size: 68,
                                              color: Color(0xffa7b39e),
                                            ),
                                            SizedBox(height: 20),
                                            Text(
                                              query.isEmpty
                                                  ? t('从一本书开始')
                                                  : t('没有找到这本书'),
                                              style: TextStyle(fontSize: 22),
                                            ),
                                            SizedBox(height: 12),
                                            Text(
                                              t('本地导入 TXT、EPUB、PDF · 无需会员听书'),
                                              style: TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                            SizedBox(height: 24),
                                            OutlinedButton.icon(
                                              onPressed: busy || store == null
                                                  ? null
                                                  : importBook,
                                              icon: Icon(Icons.add),
                                              label: Text(t('选择本地文件')),
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
                                                        padding: EdgeInsets.all(
                                                          20,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color:
                                                              [
                                                                Color(
                                                                  0xffdce4d5,
                                                                ),
                                                                Color(
                                                                  0xffe9dfd0,
                                                                ),
                                                                Color(
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
                                                          boxShadow: [
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
                                                              color: Color(
                                                                0xff48664e,
                                                              ),
                                                            ),
                                                            SizedBox(
                                                              height: 20,
                                                            ),
                                                            Text(
                                                              b.title,
                                                              maxLines: 4,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                fontSize: 23,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                            Spacer(),
                                                            Text(
                                                              b.author,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(height: 12),
                                                    Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            b.title,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                        PopupMenuButton<String>(
                                                          tooltip: t('书籍操作'),
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
                                                          itemBuilder: (_) => [
                                                            PopupMenuItem(
                                                              value: 'listen',
                                                              child: Text(
                                                                t('从当前位置听书'),
                                                              ),
                                                            ),
                                                            PopupMenuItem(
                                                              value: 'remove',
                                                              child: Text(
                                                                t('移除本机副本'),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                    Text(
                                                      t(
                                                        '${b.format.toUpperCase()} · ${(b.progress * 100).round()}% · 仅本人',
                                                      ),
                                                      style: TextStyle(
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
                                    SizedBox(height: 30),
                                    Text(
                                      t('私人书籍保存在本机；连接私人云后可在本人设备间同步。'),
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
      bottomNavigationBar: miniPlayer(
        wide,
        wide
            ? null
            : NavigationBar(
                selectedIndex: tab,
                onDestinationSelected: (v) => update(() => tab = v),
                destinations: [
                  NavigationDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    label: t('书架'),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history),
                    label: t('历史'),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.download_outlined),
                    label: t('下载'),
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.settings_outlined),
                    label: t('设置'),
                  ),
                ],
              ),
      ),
    );
  }
}
