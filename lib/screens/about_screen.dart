import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// App-specific copy; upstream notices remain available in Flutter's license registry.
const bookwormPublisher = String.fromEnvironment(
  'BOOKWORM_PUBLISHER',
  defaultValue: 'Fairy Phoenix Foundation',
);

class AboutScreen extends StatefulWidget {
  final List<String> enabledClouds;
  const AboutScreen({super.key, this.enabledClouds = const []});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? info;
  bool versionFailed = false;

  @override
  void initState() {
    super.initState();
    loadVersion();
  }

  Future<void> loadVersion() async {
    try {
      final value = await PackageInfo.fromPlatform();
      if (mounted) setState(() => info = value);
    } catch (_) {
      if (mounted) setState(() => versionFailed = true);
    }
  }

  String get versionLabel => info == null
      ? (versionFailed ? '版本信息暂不可用' : '正在读取版本…')
      : '版本 ${info!.version} (${info!.buildNumber})';

  Future<void> openLink(String address) async {
    try {
      if (await launchUrl(
        Uri.parse(address),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Preserve a useful fallback on devices without an external URL handler.
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('无法打开链接'),
        content: SelectableText(address),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: address));
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('复制链接'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget section(String title, List<Widget> children) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget link(String label, String url) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: const Icon(Icons.open_in_new, size: 18),
    onTap: () => openLink(url),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于书虫 · About')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 8),
            const Icon(Icons.auto_stories, size: 64, color: Color(0xff48664e)),
            const SizedBox(height: 16),
            Text(
              'BookWorm · 书虫',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(versionLabel, textAlign: TextAlign.center),
            if (bookwormPublisher.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('开发者：$bookwormPublisher', textAlign: TextAlign.center),
              Text(
                '版权所有 © 2026 $bookwormPublisher',
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            section('关于 BookWorm', const [
              Text('导入自己的电子书，安静阅读，或用系统语音继续听。支持 iOS、Android、Windows 和 macOS。'),
            ]),
            section('使用说明', const [
              Text('1. 在书架点击“导入书籍”，选择本地 TXT、EPUB 或 PDF。'),
              SizedBox(height: 10),
              Text('2. 打开书籍阅读，或点击“从当前位置听书”；可调整系统声音、语速和定时停止。'),
              SizedBox(height: 10),
              Text('3. 阅读和听书共用位置。选中文字可调整听书起点，进度会自动保存在本机。'),
              SizedBox(height: 10),
              Text('4. 私人云启用后，本人各设备需要连接同一个云服务、同一个账号，才能传递书籍与读听进度。'),
            ]),
            section('隐私与数据', const [
              Text('书籍和读听进度保存在你的设备上；启用同步后，也保存在你授权的私人云中，不会上传给开发者。'),
              SizedBox(height: 10),
              Text('按你的选择，书籍以普通文件保存，不加密。私人云账号授权凭据仍由系统安全存储保护。'),
              SizedBox(height: 10),
              Text('导入不会改写原始文件。本机移除不会删除云副本，后续同步可能重新下载。'),
            ]),
            section('当前版本说明', [
              Text(
                widget.enabledClouds.isEmpty
                    ? '私人云登录尚未在此安装包中启用。当前可使用本地导入、阅读和听书；这不是云盘账号登录失败。'
                    : '此安装包已启用 ${widget.enabledClouds.join('、')} 登录入口。实际同步需要完成本人账号授权。',
              ),
              const SizedBox(height: 10),
              const Text(
                '支持 UTF-8 TXT、EPUB 文字与章节、PDF 原版阅读。EPUB 暂不保留复杂图文排版；无文本层的扫描 PDF 暂不能朗读。',
              ),
              const SizedBox(height: 10),
              const Text('系统语音的音色和可用性取决于设备上的语音资源。后台、锁屏和媒体键仍需逐平台完善验证。'),
            ]),
            section('第三方软件声明', [
              const Text(
                '使用 Flutter／Dart、PDFium、pdfrx、系统语音及云连接等开源组件。各组件版权与许可证归原作者所有。',
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('查看全部开源许可证'),
                subtitle: const Text('包含随应用打包的许可原文与版权声明'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'BookWorm · 书虫',
                  applicationVersion: info == null
                      ? null
                      : '${info!.version} (${info!.buildNumber})',
                  applicationLegalese: bookwormPublisher.isEmpty
                      ? null
                      : 'Copyright © 2026 $bookwormPublisher.',
                ),
              ),
              link(
                'Flutter 许可证',
                'https://github.com/flutter/flutter/blob/master/LICENSE',
              ),
              link(
                'Dart 许可证',
                'https://github.com/dart-lang/sdk/blob/main/LICENSE',
              ),
              link(
                'PDFium 许可证',
                'https://pdfium.googlesource.com/pdfium/+/refs/heads/main/LICENSE',
              ),
              link(
                'pdfrx 许可证',
                'https://github.com/espresso3389/pdfrx/blob/master/LICENSE',
              ),
              if (Platform.isMacOS || Platform.isIOS)
                link('Swift 许可证', 'https://www.swift.org/LICENSE.txt'),
            ]),
            section('项目与反馈', [
              link(
                'GitHub 项目（私有仓库，需访问权限）',
                'https://github.com/MikeChongZhou/BookWorm',
              ),
              link(
                '问题反馈（需仓库访问权限）',
                'https://github.com/MikeChongZhou/BookWorm/issues',
              ),
            ]),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
}

Future<void> showCloudUnavailable(BuildContext context, String cloudName) =>
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$cloudName 尚未启用'),
        content: const Text(
          '此测试版本尚未启用该云服务的登录，无法完成账号授权和同步。\n\n无需更换云盘账号；本地导入、阅读和听书仍可正常使用。启用云服务后，需要更新安装包再连接。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
