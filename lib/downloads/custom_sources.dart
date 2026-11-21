import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 'book_catalog.dart';

Uri sourceUri(String value) {
  final uri = Uri.parse(value.trim());
  if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw const FormatException('请输入不含账号密码的 HTTPS 网址');
  }
  return uri;
}

bool bookUrl(Uri url) =>
    RegExp(r'\.(epub|pdf|txt)$', caseSensitive: false).hasMatch(url.path);

/// Parse supported OPDS/Atom catalogs and static HTML links; never run site scripts.
(List<CatalogBook>, List<String>) discoverBooks(
  (String, String, String) input,
) {
  final (body, url, source) = input;
  final base = sourceUri(url);
  final books = <CatalogBook>[];
  final pages = <String>{};
  void add(String href, String title, [String author = '', String mime = '']) {
    final resolved = base.resolve(href);
    if (resolved.scheme != 'https' || resolved.userInfo.isNotEmpty) return;
    final type = switch (mime) {
      'application/epub+zip' => 'epub',
      'application/pdf' => 'pdf',
      'text/plain' => 'txt',
      _ => null,
    };
    if (bookUrl(resolved) || type != null) {
      final label = title.trim().isEmpty
          ? Uri.decodeComponent(resolved.pathSegments.last)
          : title.trim();
      books.add(
        CatalogBook(
          id: 'custom:${sha256.convert(utf8.encode(resolved.toString()))}',
          title: label,
          author: author,
          source: source,
          pageUrl: resolved.toString(),
          format: type ?? resolved.path.split('.').last.toLowerCase(),
        ),
      );
    } else if (resolved.host == base.host && resolved.path != base.path ||
        resolved.host == base.host && resolved.query != base.query) {
      pages.add(resolved.removeFragment().toString());
    }
  }

  try {
    final xml = XmlDocument.parse(body);
    for (final entry in xml.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'entry',
    )) {
      final title =
          entry.childElements
              .where((e) => e.name.local == 'title')
              .firstOrNull
              ?.innerText ??
          '';
      final author =
          entry.childElements
              .where((e) => e.name.local == 'author')
              .firstOrNull
              ?.innerText
              .trim() ??
          '';
      for (final link in entry.childElements.where(
        (e) => e.name.local == 'link',
      )) {
        final href = link.getAttribute('href');
        if (href != null) {
          add(href, title, author, link.getAttribute('type') ?? '');
        }
      }
    }
    for (final link in xml.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'link' && e.getAttribute('rel') == 'next',
    )) {
      final href = link.getAttribute('href');
      if (href != null) add(href, '');
    }
  } on XmlException {
    /* Most websites use HTML rather than XML. */
  }
  for (final match in RegExp(
    r'''<a\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
    caseSensitive: false,
  ).allMatches(body)) {
    final title = match[2]!
        .replaceAll(RegExp('<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&nbsp;', ' ')
        .trim();
    add(match[1]!.replaceAll('&amp;', '&'), title);
  }
  return ({for (final b in books) b.id: b}.values.toList(), pages.toList());
}
