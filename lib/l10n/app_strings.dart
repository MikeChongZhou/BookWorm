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
  r"^找到 (\d+) 本书，确认来源与下载权限后添加。$": [
    "Found {1} books. Check the source and download permissions before adding.",
    "Se encontraron {1} libros. Comprueba la fuente y los permisos antes de añadir.",
  ],
  r"^第 (\d+) 章 · 共 (\d+) 章$": ["Chapter {1} of {2}", "Capítulo {1} de {2}"],
  r"^第 (\d+) 章$": ["Chapter {1}", "Capítulo {1}"],
  r"^每 (\d+) 秒翻页$": ["Turn every {1} seconds", "Pasar cada {1} segundos"],
  r"^找到 (\d+) 本书$": ["{1} books found", "{1} libros encontrados"],
  r"^公版书目录已更新 · (\d+) 本$": [
    "Catalog updated · {1} books",
    "Catálogo actualizado · {1} libros",
  ],
  r"^正在更新 Standard Ebooks · 第 (\d+) 页$": [
    "Updating Standard Ebooks · page {1}",
    "Actualizando Standard Ebooks · página {1}",
  ],
  r"^最近更新：(.+)$": ["Last updated: {1}", "Última actualización: {1}"],
  r"^下载中 · (.+) MB$": ["Downloading · {1} MB", "Descargando · {1} MB"],
  r"^下载未完成，可重试：(.+)$": [
    "Download incomplete. Retry: {1}",
    "Descarga incompleta. Reintenta: {1}",
  ],

  r"^上传本地文件中，已上传 (\d+) 个文件 · ([\d.]+/[\d.]+) MB · ([\d.]+) MB/s$": [
    "Uploading · {1} files uploaded · {2} MB · {3} MB/s",
    "Subiendo · {1} archivos · {2} MB · {3} MB/s",
  ],
  r"^下载本地文件中，已下载 (\d+) 个文件 · ([\d.]+/[\d.]+) MB · ([\d.]+) MB/s$": [
    "Downloading · {1} files downloaded · {2} MB · {3} MB/s",
    "Descargando · {1} archivos · {2} MB · {3} MB/s",
  ],
  r"^上传本地文件中，已上传 (\d+) 个文件$": [
    "Uploading local files · {1} files uploaded",
    "Subiendo archivos locales · {1} archivos subidos",
  ],
  r"^下载本地文件中，已下载 (\d+) 个文件$": [
    "Downloading local files · {1} files downloaded",
    "Descargando archivos locales · {1} archivos descargados",
  ],
  r"^同步完成：已上传 (\d+) 个文件，已下载 (\d+) 个文件$": [
    "Sync complete · {1} uploaded, {2} downloaded",
    "Sincronización completa · {1} subidos, {2} descargados",
  ],
  r"^语音设置失败：(.+)$": [
    "Speech settings failed: {1}",
    "Error de configuración de voz: {1}",
  ],
  r"^下载 Melo 模型中：(\d+)%$": [
    "Downloading Melo model: {1}%",
    "Descargando modelo Melo: {1}%",
  ],
  r"^校验并安装 Melo 模型中：(\d+)%$": [
    "Verifying and installing Melo: {1}%",
    "Verificando e instalando Melo: {1}%",
  ],

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
