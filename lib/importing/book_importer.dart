import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/local_book.dart';

class BookImporter {
  static const maxBytes = 50 * 1024 * 1024;
  Future<LocalBook> parse(
    String name,
    Uint8List bytes, {
    void Function(String)? status,
  }) async {
    if (bytes.isEmpty) throw const FormatException('文件为空');
    if (bytes.length > maxBytes) {
      throw const FormatException('第一版支持不超过 50 MB 的文件');
    }
    final format = name.split('.').last.toLowerCase();
    var title = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
    var author = '未知作者';
    late List<BookSection> sections;
    if (format == 'txt') {
      String text;
      try {
        text = utf8.decode(bytes).replaceFirst('\uFEFF', '');
      } catch (_) {
        throw const FormatException('TXT 请先转换为 UTF-8 编码');
      }
      if (text.trim().isEmpty) throw const FormatException('文件没有可读正文');
      sections = splitText(text);
    } else if (format == 'epub') {
      final parsed = epub(bytes);
      title = parsed.$1.isEmpty ? title : parsed.$1;
      author = parsed.$2;
      sections = parsed.$3;
    } else if (format == 'pdf') {
      status?.call('正在解析 PDF 页面');
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openData(
        bytes,
        sourceName: sha256.convert(bytes).toString(),
        passwordProvider: () => null,
      );
      try {
        if (document.pages.length > 2000) {
          throw const FormatException('第一版支持最多 2,000 页 PDF');
        }
        sections = [];
        for (final page in document.pages) {
          status?.call('提取 PDF 文本 ${page.pageNumber}/${document.pages.length}');
          final text = await page.loadText();
          sections.add(
            BookSection('第 ${page.pageNumber} 页', text?.fullText ?? ''),
          );
        }
      } finally {
        await document.dispose();
      }
    } else {
      throw const FormatException('支持 TXT、EPUB、PDF 文件');
    }
    if (sections.isEmpty) throw const FormatException('未找到正文或页面');
    return LocalBook(
      id: sha256.convert(bytes).toString(),
      title: title,
      author: author,
      format: format,
      sections: sections,
    );
  }

  static List<BookSection> splitText(String text, {String heading = '正文'}) {
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final chapters = <BookSection>[];
    var title = heading;
    final buffer = StringBuffer();
    void flush() {
      if (buffer.toString().trim().isNotEmpty) {
        final s = buffer.toString().trim();
        var start = 0;
        var part = 1;
        while (start < s.length) {
          var end = (start + 1600).clamp(0, s.length);
          if (end < s.length) {
            final cut = s.lastIndexOf(RegExp(r'[。！？\n]'), end - 1);
            if (cut > start + 500) end = cut + 1;
            if (end < s.length &&
                s.codeUnitAt(end - 1) >= 0xD800 &&
                s.codeUnitAt(end - 1) <= 0xDBFF) {
              end--;
            }
          }
          chapters.add(
            BookSection(
              part == 1 ? title : '$title · $part',
              s.substring(start, end),
            ),
          );
          start = end;
          part++;
        }
      }
      buffer.clear();
    }

    for (final line in text.split('\n')) {
      if (RegExp(
            r'^(第[零〇一二三四五六七八九十百千万\d]+[章回节卷部]|chapter\s+\d+)',
            caseSensitive: false,
          ).hasMatch(line.trim()) &&
          line.length < 100) {
        flush();
        title = line.trim();
      } else {
        buffer.writeln(line);
      }
    }
    flush();
    return chapters;
  }

  static (String, String, List<BookSection>) epub(Uint8List bytes) {
    final zip = ZipDecoder().decodeBytes(bytes, verify: true);
    if (zip.length > 5000) throw const FormatException('EPUB 文件数量超过安全限制');
    var total = 0;
    for (final f in zip) {
      total += f.size;
      if (total > 100 * 1024 * 1024) {
        throw const FormatException('EPUB 解压大小超过安全限制');
      }
    }
    String read(String path) {
      final f = zip.findFile(path);
      if (f == null || f.size > 10 * 1024 * 1024) {
        throw FormatException('EPUB 资源无效：$path');
      }
      return utf8.decode(f.content);
    }

    XmlDocument xml(String s) {
      if (s.contains('<!ENTITY') ||
          s.contains('<!DOCTYPE') && s.contains('SYSTEM')) {
        throw const FormatException('EPUB 含不支持的外部实体');
      }
      return XmlDocument.parse(s);
    }

    final container = xml(read('META-INF/container.xml'));
    final opfPath = container.descendants
        .whereType<XmlElement>()
        .firstWhere((e) => e.name.local == 'rootfile')
        .getAttribute('full-path')!;
    if (zip.findFile('META-INF/encryption.xml') != null) {
      throw const FormatException('暂不支持加密／DRM EPUB');
    }
    final opf = xml(read(opfPath));
    final elements = opf.descendants.whereType<XmlElement>();
    String meta(String n) =>
        elements
            .where((e) => e.name.local == n)
            .map((e) => e.innerText.trim())
            .firstOrNull ??
        '';
    final manifest = <String, String>{};
    for (final e in elements.where((e) => e.name.local == 'item')) {
      final id = e.getAttribute('id'), href = e.getAttribute('href');
      if (id != null && href != null) manifest[id] = href;
    }
    final base = Uri(path: opfPath);
    final result = <BookSection>[];
    for (final e in elements.where((e) => e.name.local == 'itemref')) {
      final href = manifest[e.getAttribute('idref')];
      if (href == null) continue;
      final path = Uri.decodeComponent(base.resolve(href).path);
      if (path.startsWith('/') || path.contains('..')) {
        throw const FormatException('EPUB 路径无效');
      }
      final doc = xml(read(path));
      final body = doc.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'body')
          .firstOrNull;
      if (body == null) continue;
      final out = StringBuffer();
      void visit(XmlNode node) {
        if (node is XmlText) {
          out.write(node.value);
          return;
        }
        if (node is XmlElement) {
          if (['script', 'style', 'nav'].contains(node.name.local)) return;
          for (final child in node.children) {
            visit(child);
          }
          if ([
            'p',
            'div',
            'br',
            'h1',
            'h2',
            'h3',
            'li',
            'section',
          ].contains(node.name.local)) {
            out.writeln();
          }
        }
      }

      visit(body);
      final heading =
          body.descendants
              .whereType<XmlElement>()
              .where((e) => ['h1', 'h2', 'h3'].contains(e.name.local))
              .map((e) => e.innerText.trim())
              .firstOrNull ??
          '第 ${result.length + 1} 章';
      result.addAll(splitText(out.toString(), heading: heading));
    }
    return (
      meta('title'),
      meta('creator').isEmpty ? '未知作者' : meta('creator'),
      result,
    );
  }
}
