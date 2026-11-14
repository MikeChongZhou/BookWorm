import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yuejian/main.dart';
import 'package:yuejian/storage/local_library.dart';
import 'package:yuejian/models/local_book.dart';

void main() {
  testWidgets('local-only library and private cloud choices', (tester) async {
    SharedPreferences.setMockInitialValues({'bookworm_language': 'zh'});
    PackageInfo.setMockInitialValues(
      appName: 'BookWorm',
      packageName: 'test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'test',
    );
    await tester.pumpWidget(ReaderApp(library: EmptyLibrary()));
    await tester.pumpAndSettle();
    expect(find.text('我的书架'), findsOneWidget);
    expect(find.text('选择本地文件'), findsOneWidget);
    expect(find.text('书城'), findsNothing);
    expect(find.text('会员'), findsNothing);
    await tester.tap(find.byTooltip('关于书虫'));
    await tester.pumpAndSettle();
    expect(find.text('关于书虫 · About'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('我的私人云'), findsNothing);
    await tester.tap(find.text('私人云'));
    await tester.pumpAndSettle();
    for (final name in ['OneDrive', 'iCloud', 'Google Drive']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('连接'), findsNothing);
    await tester.tap(find.text('查看说明').first);
    await tester.pumpAndSettle();
    expect(find.text('OneDrive 尚未启用'), findsOneWidget);
    expect(find.textContaining('无需更换云盘账号'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class EmptyLibrary extends LocalLibrary {
  EmptyLibrary() : super(Directory('/unused-test-library'));
  @override
  Future<List<LocalBook>> load() async => [];
}
