import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuejian/main.dart';
import 'package:yuejian/storage/local_library.dart';
import 'package:yuejian/models/local_book.dart';

void main() {
  testWidgets('local-only library and private cloud choices', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ReaderApp(library: EmptyLibrary()));
    await tester.pumpAndSettle();
    expect(find.text('我的书架'), findsOneWidget);
    expect(find.text('选择本地文件'), findsOneWidget);
    expect(find.text('书城'), findsNothing);
    expect(find.text('会员'), findsNothing);
    await tester.tap(find.text('私人云'));
    await tester.pumpAndSettle();
    for (final name in ['OneDrive', 'iCloud', 'Google Drive']) {
      expect(find.text(name), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });
}

class EmptyLibrary extends LocalLibrary {
  EmptyLibrary() : super(Directory('/unused-test-library'));
  @override
  Future<List<LocalBook>> load() async => [];
}
