import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yuejian/screens/about_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'BookWorm',
      packageName: 'com.yuejian.yuejian',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test',
    );
  });
  testWidgets('About shows package version and accurate cloud/privacy status', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    expect(find.text('BookWorm · 书虫'), findsOneWidget);
    expect(find.text('版本 1.0.0 (1)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('隐私与数据'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('不会上传给开发者'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('当前版本说明'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('私人云登录尚未在此安装包中启用'), findsOneWidget);
    expect(find.textContaining('不加密'), findsOneWidget);
  });
  testWidgets('bundled license notices open inside the app', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('查看全部开源许可证'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('查看全部开源许可证'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
  testWidgets('failed external license link can be copied', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async => false,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/url_launcher'),
        null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Flutter 许可证'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Flutter 许可证'));
    await tester.pumpAndSettle();
    expect(find.text('无法打开链接'), findsOneWidget);
    await tester.tap(find.text('复制链接'));
    await tester.pumpAndSettle();
    expect(clipboard, 'https://github.com/flutter/flutter/blob/master/LICENSE');
  });
}
