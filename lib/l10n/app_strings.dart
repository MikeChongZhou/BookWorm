import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'translations.dart';

class AppStrings {
  final Locale locale;
  const AppStrings(this.locale);
  static const supportedLocales = [Locale('zh'), Locale('en'), Locale('es')];
  static const delegate = _StringsDelegate();
  static Locale resolve(Locale? locale, Iterable<Locale> supported) =>
      supportedLocales.firstWhere(
        (l) => l.languageCode == locale?.languageCode,
        orElse: () => const Locale('en'),
      );

  String translate(String text) {
    if (locale.languageCode == 'zh') return text;
    final index = locale.languageCode == 'es' ? 1 : 0;
    final exact = translations[text];
    if (exact != null) return exact[index];
    // Templates only match UI-owned strings; book titles and book contents are untouched.
    for (final entry in dynamicTranslations.entries) {
      final match = RegExp(entry.key, dotAll: true).firstMatch(text);
      if (match == null) continue;
      return entry.value[index].replaceAllMapped(
        RegExp(r'\{(\d+)\}'),
        (m) => match.group(int.parse(m[1]!)) ?? '',
      );
    }
    return text;
  }
}

extension TranslateContext on BuildContext {
  String tr(String text) =>
      Localizations.of<AppStrings>(this, AppStrings)?.translate(text) ?? text;
}

class _StringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _StringsDelegate();
  @override
  bool isSupported(Locale locale) => AppStrings.supportedLocales.any(
    (l) => l.languageCode == locale.languageCode,
  );
  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture(AppStrings(locale));
  @override
  bool shouldReload(_StringsDelegate old) => false;
}

const dynamicTranslations = <String, List<String>>{
  r'^版本 (.+)$': ['Version {1}', 'Versión {1}'],
  r'^开发者：(.+)$': ['Developer: {1}', 'Desarrollador: {1}'],
  r'^版权所有 © (.+)$': ['Copyright © {1}', 'Derechos de autor © {1}'],
  r'^(.+) 许可证$': ['{1} license', 'Licencia de {1}'],
  r'^(.+) 尚未启用$': ['{1} is not configured', '{1} no está configurado'],
  r'^正在读取 (.+)$': ['Reading {1}', 'Leyendo {1}'],
  r'^已导入《(.+)》$': ['Imported “{1}”', 'Se importó «{1}»'],
  r'^连接 (.+)$': ['Connecting to {1}', 'Conectando a {1}'],
  r'^授权 (.+)$': ['Authorizing {1}', 'Autorizando {1}'],
  r'^最近同步：(.+)$': ['Last sync: {1}', 'Última sincronización: {1}'],
  r'^同步完成：上传 (\d+) 本，下载 (\d+) 本$': [
    'Sync complete: {1} uploaded, {2} downloaded',
    'Sincronización completa: {1} subidos, {2} descargados',
  ],
  r'^《(.+)》有另一设备的进度$': [
    'Another device has a position for “{1}”',
    'Otro dispositivo tiene una posición para «{1}»',
  ],
  r'^本机：第 (\d+) 节\n另一设备：第 (\d+) 节\n\n是否从另一设备的位置继续？本机位置不会被静默覆盖。$': [
    'This device: section {1}\nOther device: section {2}\n\nContinue from the other position? Your local position is only changed if you choose it.',
    'Este dispositivo: sección {1}\nOtro dispositivo: sección {2}\n\n¿Continuar desde la otra posición? La posición local solo cambia si lo eliges.',
  ],
  r'^(.+) · 仅本人$': ['{1} · Private', '{1} · Privado'],
  r'^(\d+) 分钟$': ['{1} min', '{1} min'],
  r'^停止时间 (.+)$': ['Stop at {1}', 'Detener a las {1}'],
  r'^此安装包已启用 (.+) 登录入口。实际同步需要完成本人账号授权。$': [
    'Sign-in is configured for {1}. Sync requires your account authorization.',
    'El inicio de sesión está configurado para {1}. La sincronización requiere tu autorización.',
  ],
  r'^无法打开本地书库：(.+)$': [
    'Cannot open the local library: {1}',
    'No se puede abrir la biblioteca local: {1}',
  ],
  r'^导入失败：(.+)$': ['Import failed: {1}', 'No se pudo importar: {1}'],
  r'^无法打开书籍：(.+)$': [
    'Cannot open book: {1}',
    'No se puede abrir el libro: {1}',
  ],
  r'^同步未完成：(.+)；本机书籍已保留$': [
    'Sync incomplete: {1}. Local books are preserved.',
    'Sincronización incompleta: {1}. Se conservan los libros locales.',
  ],
  r'^连接未完成：(.+)$': ['Connection incomplete: {1}', 'Conexión incompleta: {1}'],
  r'^移除失败：(.+)$': ['Removal failed: {1}', 'No se pudo eliminar: {1}'],
  r'^保存进度失败：(.+)$': [
    'Could not save progress: {1}',
    'No se pudo guardar el progreso: {1}',
  ],
  r'^进度未能保存，请重试：(.+)$': [
    'Progress not saved. Retry: {1}',
    'Progreso no guardado. Reintenta: {1}',
  ],
  r'^读取系统声音失败：(.+)$': [
    'Could not load system voices: {1}',
    'No se pudieron cargar las voces: {1}',
  ],
};
