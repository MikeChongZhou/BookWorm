import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuejian/l10n/app_strings.dart';
import 'package:yuejian/main.dart';
import 'package:yuejian/settings/language_settings.dart';

import 'widget_test.dart' show EmptyLibrary;

void main() {
  test('language defaults to system and persists explicit choice', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = LanguageSettings();
    await settings.load();
    expect(settings.value, 'system');
    expect(settings.locale, isNull);
    await settings.select('es');
    final restored = LanguageSettings();
    await restored.load();
    expect(restored.locale, const Locale('es'));
    await restored.select('system');
    expect(restored.locale, isNull);
    expect(
      (await SharedPreferences.getInstance()).getString('bookworm_language'),
      'system',
    );
    settings.dispose();
    restored.dispose();
  });
  test(
    'unknown language follows system; locale resolution has explicit fallback',
    () async {
      SharedPreferences.setMockInitialValues({'bookworm_language': 'invalid'});
      final settings = LanguageSettings();
      await settings.load();
      expect(settings.locale, isNull);
      expect(
        AppStrings.resolve(const Locale('zh', 'TW'), []),
        const Locale('zh'),
      );
      expect(AppStrings.resolve(const Locale('fr'), []), const Locale('en'));
      expect(const AppStrings(Locale('es')).translate('设置'), 'Ajustes');
      settings.dispose();
    },
  );
  testWidgets(
    'settings contains cloud; app language changes immediately and follows system again',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(ReaderApp(library: EmptyLibrary()));
      await tester.pumpAndSettle();
      expect(find.text('My library'), findsOneWidget);
      expect(find.text('Private cloud'), findsNothing);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Follow system'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('简体中文').last);
      await tester.pumpAndSettle();
      expect(find.text('应用语言'), findsWidgets);
      expect(find.text('私人云'), findsOneWidget);
      await tester.tap(find.text('私人云'));
      await tester.pumpAndSettle();
      expect(find.text('我的私人云'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跟随系统').last);
      await tester.pumpAndSettle();
      expect(find.text('App language'), findsWidgets);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('es')];
      await tester.pumpAndSettle();
      expect(find.text('Ajustes'), findsWidgets);
      expect(find.text('Nube privada'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('macOS Settings menu channel opens settings', (tester) async {
    SharedPreferences.setMockInitialValues({'bookworm_language': 'zh'});
    await tester.pumpWidget(ReaderApp(library: EmptyLibrary()));
    await tester.pumpAndSettle();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'bookworm/app_menu',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('showSettings'),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(find.text('应用语言'), findsWidgets);
    expect(find.text('私人云'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
