import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../importing/book_importer.dart';
import '../models/local_book.dart';
import '../storage/local_library.dart';
import 'custom_sources.dart';

class CatalogBook {
  final String id, title, author, source, pageUrl;
  final String format;
  const CatalogBook({
    required this.id,
    required this.title,
    required this.author,
    required this.source,
    required this.pageUrl,
    this.format = 'epub',
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'source': source,
    'pageUrl': pageUrl,
    'format': format,
  };
  factory CatalogBook.fromJson(Map<String, dynamic> j) => CatalogBook(
    id: j['id'],
    title: j['title'],
    author: j['author'],
    source: j['source'],
    pageUrl: j['pageUrl'],
    format: j['format'] ?? 'epub',
  );
}

/// No catalog request, import, or parsing blocks navigation or the audio handler.
/// A failed source keeps its last successful snapshot.
class BookCatalog extends ChangeNotifier {
  final http.Client client;
  final Future<Directory> Function() directory;
  BookCatalog({http.Client? client, Future<Directory> Function()? directory})
    : client = client ?? http.Client(),
      directory = directory ?? catalogDirectory;
  static Future<Directory> catalogDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/public-catalog',
  );
  static const wenshuoge =
      'https://raw.githubusercontent.com/zhpelo/wenshuoge/main/文硕阁公版书目录.csv';
  static const standard = 'https://standardebooks.org/ebooks';
  List<CatalogBook> books = [];
  List<String> customSources = [];
  int _sourceRevision = 0;
  Future<List<CatalogBook>> scanSource(String url) async {
    final start = sourceUri(url);
    final folder = await directory();
    await folder.create(recursive: true);
    final pending = <String>[start.toString()], seen = <String>{};
    final found = <String, CatalogBook>{};
    for (var i = 0; pending.isNotEmpty && i < 30; i++) {
      if (shouldYield?.call() == true) {
        deferred = true;
        throw const FormatException('目录更新已延后，优先读书与听书');
      }
      final page = pending.removeAt(0);
      if (!seen.add(page)) continue;
      try {
        final body = await _getCached(sourceUri(page), folder);
        final result = await compute(discoverBooks, (
          body!,
          page,
          start.toString(),
        ));
        for (final book in result.$1) {
          found[book.id] = book;
          if (found.length >= 1000) break;
        }
        for (final next in result.$2) {
          if (!seen.contains(next) &&
              !pending.contains(next) &&
              pending.length < 100) {
            pending.add(next);
          }
        }
      } catch (e) {
        if (i == 0 || deferred) rethrow;
      }
      if (found.length >= 1000) break;
    }
    if (found.isEmpty) {
      throw const FormatException(
        '未识别可下载书籍：支持 OPDS 和含 EPUB／PDF／TXT 链接的静态网站；不支持需要登录或 JavaScript 的页面',
      );
    }
    return found.values.toList();
  }

  Future<void> addSource(String url, List<CatalogBook> preview) async {
    _sourceRevision++;
    final normalized = sourceUri(url).toString();
    if (!customSources.contains(normalized)) customSources.add(normalized);
    books = {
      ...{for (final b in books) b.id: b},
      ...{for (final b in preview) b.id: b},
    }.values.toList();
    await (await SharedPreferences.getInstance()).setStringList(
      'custom_book_sources',
      customSources,
    );
    await _saveCatalog();
    _notify();
  }

  Future<void> removeSource(String url) async {
    _sourceRevision++;
    customSources.remove(url);
    books.removeWhere((b) => b.source == url);
    await (await SharedPreferences.getInstance()).setStringList(
      'custom_book_sources',
      customSources,
    );
    await _saveCatalog();
    _notify();
  }

  Future<void> _saveCatalog() async {
    final folder = await directory();
    await folder.create(recursive: true);
    await File('${folder.path}/catalog.json')
        .writeAsString(await compute(encodeCatalog, books));
  }

  bool refreshing = false, disposed = false, loaded = false;
  bool _checkingDaily = false;
  bool deferred = false;
  bool Function()? shouldYield;
  Future<void>? _loading;
  String status = '', error = '';
  final Map<String, String> downloadStates = {};
  final Set<String> completed = {};
  final Set<String> _downloading = {};
  final List<http.Client> _transfers = [];
  DateTime? updated;
  void _notify() {
    if (!disposed) notifyListeners();
  }

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    final folder = await directory();
    try {
      final file = File('${folder.path}/catalog.json');
      if (await file.exists()) {
        books = await compute(decodeCatalog, await file.readAsString());
      }
    } catch (_) {
      error = '书库缓存暂不可用，将尝试更新';
    }
    final prefs = await SharedPreferences.getInstance();
    customSources = prefs.getStringList('custom_book_sources') ?? [];
    updated = DateTime.tryParse(prefs.getString('catalog_updated') ?? '');
    completed.addAll(prefs.getStringList('catalog_downloaded') ?? []);
    loaded = true;
    _notify();
  }

  Future<void> refreshDaily() async {
    if (_checkingDaily || disposed) return;
    _checkingDaily = true;
    try {
      await load();
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (prefs.getString('catalog_scan_day') == today && !deferred) return;
      await prefs.setString('catalog_scan_day', today);
      await refresh();
      if (deferred) await prefs.remove('catalog_scan_day');
    } catch (e) {
      error = '目录更新未完成：$e';
      _notify();
    } finally {
      _checkingDaily = false;
    }
  }

  Future<String?> _getCached(Uri uri, Directory folder) async {
    final name = sha256.convert(utf8.encode(uri.toString())).toString();
    final file = File('${folder.path}/$name.cache');
    final etagFile = File('${file.path}.etag');
    final headers = <String, String>{
      'User-Agent': 'BookWorm/1.0 (public ebook catalog)',
    };
    if (await file.exists() && await etagFile.exists()) {
      headers['If-None-Match'] = await etagFile.readAsString();
    }
    final response = await client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 40));
    if (response.statusCode == 304 && await file.exists()) {
      return file.readAsString();
    }
    if (response.statusCode != 200) {
      throw HttpException('书源返回 HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.length > 24 * 1024 * 1024) {
      throw const FormatException('目录过大');
    }
    final text = utf8.decode(response.bodyBytes);
    await file.writeAsString(text);
    final etag = response.headers['etag'];
    if (etag != null) await etagFile.writeAsString(etag);
    return text;
  }

  Future<void> refresh() async {
    if (refreshing || disposed) return;
    refreshing = true;
    deferred = false;
    error = '';
    status = '正在更新公版书目录';
    _notify();
    final map = {for (final book in books) book.id: book};
    final sourceRevision = _sourceRevision;
    final failures = <String>[];
    var succeeded = false;
    try {
      final folder = await directory();
      await folder.create(recursive: true);
      try {
        final csv = await _getCached(Uri.parse(wenshuoge), folder);
        final additions = await compute(parseWenshuoge, csv!);
        if (additions.isEmpty) throw const FormatException('未识别文硕阁目录');
        map.removeWhere((id, book) => book.source == '文硕阁');
        for (final book in additions) {
          map[book.id] = book;
        }
        succeeded = true;
        books = map.values.toList();
        _notify();
      } catch (e) {
        failures.add('文硕阁：$e');
      }
      try {
        final additions = <CatalogBook>[];
        var next = Uri.parse('$standard?per-page=48');
        final seen = <String>{};
        for (var page = 1; page <= 100; page++) {
          if (shouldYield?.call() == true) {
            deferred = true;
            break;
          }
          if (disposed || !seen.add(next.toString())) break;
          status = '正在更新 Standard Ebooks · 第 $page 页';
          _notify();
          final html = await _getCached(next, folder);
          final result = await compute(parseStandardPage, (
            html!,
            next.toString(),
          ));
          additions.addAll(result.$1);
          if (result.$2 == null) break;
          next = Uri.parse(result.$2!);
          // Be polite to the public site; no authentication or feed bypass.
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        if (additions.isEmpty && !deferred) {
          throw const FormatException('未识别 Standard Ebooks 目录');
        }
        if (!deferred) {
          map.removeWhere((id, book) => book.source == 'Standard Ebooks');
        }
        for (final book in additions) {
          map[book.id] = book;
        }
        succeeded = true;
      } catch (e) {
        failures.add('Standard Ebooks：$e');
      }
      for (final source in customSources.toList()) {
        if (shouldYield?.call() == true) {
          deferred = true;
          break;
        }
        try {
          final additions = await scanSource(source);
          map.removeWhere((id, b) => b.source == source);
          for (final b in additions) {
            map[b.id] = b;
          }
          succeeded = true;
        } catch (e) {
          failures.add('$source：$e');
        }
      }
      if (sourceRevision != _sourceRevision) {
        map.removeWhere((_, b) => b.id.startsWith('custom:'));
        for (final b in books.where((b) => customSources.contains(b.source))) {
          map[b.id] = b;
        }
      }
      books = map.values.toList();
      if (succeeded) {
        final encoded = await compute(encodeCatalog, books);
        final temporary = File('${folder.path}/catalog.json.tmp');
        await temporary.writeAsString(encoded);
        final destination = File('${folder.path}/catalog.json');
        if (Platform.isWindows && await destination.exists()) {
          await destination.delete();
        }
        await temporary.rename(destination.path);
        updated = DateTime.now();
        await (await SharedPreferences.getInstance()).setString(
          'catalog_updated',
          updated!.toIso8601String(),
        );
      }
      error = failures.join('\n');
      status = deferred
          ? '目录更新已延后，优先读书与听书'
          : succeeded
          ? '公版书目录已更新 · ${books.length} 本'
          : '更新未完成，仍可浏览已缓存目录';
    } finally {
      refreshing = false;
      _notify();
    }
  }

  Future<void> download(
    CatalogBook item,
    LocalLibrary library,
    void Function(LocalBook) imported,
  ) async {
    if (disposed || _downloading.contains(item.id)) return;
    // One transfer at a time bounds bandwidth and memory while reading/listening.
    if (_downloading.isNotEmpty) {
      downloadStates[item.id] = '另一文件正在下载，请稍后重试';
      _notify();
      return;
    }
    _downloading.add(item.id);
    downloadStates[item.id] = '正在获取下载地址';
    _notify();
    final transfer = http.Client();
    _transfers.add(transfer);
    Directory? staging;
    RandomAccessFile? sink;
    try {
      Uri url;
      if (item.source == '文硕阁') {
        final id = item.id.replaceFirst('wenshuoge:', '');
        if (!RegExp(r'^\d+$').hasMatch(id)) {
          throw const FormatException('书籍编号无效');
        }
        final response = await transfer
            .get(
              Uri.parse(
                'https://api.github.com/repos/zhpelo/wenshuoge/contents/ebookfiles/$id',
              ),
              headers: {'User-Agent': 'BookWorm/1.0'},
            )
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw HttpException('下载地址暂不可用：${response.statusCode}');
        }
        final files = await compute(decodeJsonList, response.body);
        final file = files
            .where(
              (f) =>
                  (f['name'] as String? ?? '').toLowerCase().endsWith('.epub'),
            )
            .firstOrNull;
        if (file == null) throw const FormatException('此书暂未提供 EPUB');
        url = Uri.parse(file['download_url']);
        if (url.host != 'raw.githubusercontent.com' ||
            !url.path.startsWith('/zhpelo/wenshuoge/')) {
          throw const FormatException('书源下载地址无效');
        }
      } else if (customSources.contains(item.source)) {
        url = sourceUri(item.pageUrl);
        if (!['epub', 'pdf', 'txt'].contains(item.format)) {
          throw const FormatException('未识别可下载格式');
        }
      } else {
        final page = Uri.parse(item.pageUrl);
        if (page.scheme != 'https' ||
            page.host != 'standardebooks.org' ||
            !page.path.startsWith('/ebooks/')) {
          throw const FormatException('书源页面地址无效');
        }
        final response = await transfer
            .get(Uri.parse(item.pageUrl))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw HttpException('书籍页面暂不可用：${response.statusCode}');
        }
        url = Uri.parse(
          await compute(standardDownloadUrl, (response.body, item.pageUrl)),
        );
      }
      var response = await transfer
          .send(http.Request('GET', url))
          .timeout(const Duration(seconds: 40));
      // The public download page uses an HTML refresh to the actual EPUB.
      // Follow only the explicitly supplied same-origin EPUB refresh, no scripts.
      for (
        var hop = 0;
        hop < 3 &&
            item.source == 'Standard Ebooks' &&
            (response.headers['content-type'] ?? '').contains('html');
        hop++
      ) {
        final html = utf8.decode(
          await readLimitedResponse(response, 512 * 1024),
        );
        url = Uri.parse(
          await compute(standardRefreshUrl, (html, url.toString())),
        );
        response = await transfer
            .send(http.Request('GET', url))
            .timeout(const Duration(seconds: 40));
      }
      if (response.statusCode != 200) {
        throw HttpException('下载失败：HTTP ${response.statusCode}');
      }
      if ((response.contentLength ?? 0) > BookImporter.maxBytes) {
        throw const FormatException('书籍超过 50 MB 限制');
      }
      staging = await (await getTemporaryDirectory()).createTemp(
        'bookworm-download-',
      );
      final partial = File('${staging.path}/book.part');
      sink = await partial.open(mode: FileMode.write);
      var received = 0;
      var last = DateTime.now();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        received += chunk.length;
        if (received > BookImporter.maxBytes) {
          throw const FormatException('书籍超过 50 MB 限制');
        }
        await sink.writeFrom(chunk);
        if (DateTime.now().difference(last).inMilliseconds > 250) {
          downloadStates[item.id] =
              '下载中 · ${(received / 1048576).toStringAsFixed(1)} MB';
          last = DateTime.now();
          _notify();
        }
      }
      // HTTP may transparently inflate gzip, whose wire length differs from the stream.
      final encoding = response.headers['content-encoding'];
      if ((encoding == null || encoding == 'identity') &&
          response.contentLength != null &&
          received != response.contentLength) {
        throw const FormatException('下载不完整');
      }
      await sink.flush();
      await sink.close();
      sink = null;
      downloadStates[item.id] = '正在导入本地书架';
      _notify();
      final data = await partial.readAsBytes();
      final extension = customSources.contains(item.source)
          ? item.format
          : 'epub';
      final book = await BookImporter().parse('${item.title}.$extension', data);
      final existing = (await library.load())
          .where((b) => b.id == book.id)
          .firstOrNull;
      if (existing == null) await library.install(book, data);
      completed.add(item.id);
      await (await SharedPreferences.getInstance()).setStringList(
        'catalog_downloaded',
        completed.toList(),
      );
      downloadStates[item.id] = '已下载到本地书架';
      imported(existing ?? book);
    } catch (e) {
      downloadStates[item.id] = '下载未完成，可重试：$e';
    } finally {
      transfer.close();
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          /* Preserve the download error. */
        }
      }
      if (staging != null) {
        try {
          await staging.delete(recursive: true);
        } catch (_) {
          /* Temporary cleanup can retry on OS maintenance. */
        }
      }
      _transfers.remove(transfer);
      _downloading.remove(item.id);
      _notify();
    }
  }

  bool downloading(String id) => _downloading.contains(id);
  @override
  void dispose() {
    disposed = true;
    client.close();
    for (final client in _transfers) {
      client.close();
    }
    super.dispose();
  }
}

Future<Uint8List> readLimitedResponse(
  http.StreamedResponse response,
  int limit,
) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in response.stream.timeout(
    const Duration(seconds: 30),
  )) {
    if (bytes.length + chunk.length > limit) {
      throw const FormatException('书源响应过大');
    }
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

String standardRefreshUrl((String, String) input) {
  final doc = XmlDocument.parse(input.$1);
  final content = doc.descendants
      .whereType<XmlElement>()
      .where(
        (e) =>
            e.name.local == 'meta' &&
            (e.getAttribute('http-equiv') ?? '').toLowerCase() == 'refresh',
      )
      .firstOrNull
      ?.getAttribute('content');
  final match = content == null
      ? null
      : RegExp(r'url\s*=\s*(.+)$', caseSensitive: false).firstMatch(content);
  if (match == null) throw const FormatException('书源未返回 EPUB 下载地址');
  final uri = Uri.parse(input.$2).resolve(match[1]!.trim());
  if (uri.scheme != 'https' ||
      uri.host != 'standardebooks.org' ||
      !uri.path.startsWith('/ebooks/') ||
      !uri.path.endsWith('.epub')) {
    throw const FormatException('书源跳转地址无效');
  }
  return uri.toString();
}

List<dynamic> decodeJsonList(String text) => jsonDecode(text) as List;
List<CatalogBook> decodeCatalog(String text) => (jsonDecode(text) as List)
    .map((j) => CatalogBook.fromJson(Map<String, dynamic>.from(j)))
    .toList();
String encodeCatalog(List<CatalogBook> books) =>
    jsonEncode(books.map((b) => b.toJson()).toList());

/// RFC 4180 CSV, including quoted newlines, commas and escaped quotes.
List<CatalogBook> parseWenshuoge(String csv) {
  final result = <CatalogBook>[];
  final row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  void finishRow() {
    row.add(field.toString());
    field = StringBuffer();
    if (row.length >= 4 &&
        RegExp(r'^\d+$').hasMatch(row[0].trim()) &&
        row[1].trim().isNotEmpty) {
      final id = row[0].trim();
      result.add(
        CatalogBook(
          id: 'wenshuoge:$id',
          title: row[1].trim(),
          author: row[3].trim(),
          source: '文硕阁',
          pageUrl:
              'https://github.com/zhpelo/wenshuoge/tree/main/ebookfiles/$id',
        ),
      );
    }
    row.clear();
  }

  for (var i = 0; i < csv.length; i++) {
    final c = csv[i];
    if (c == '"') {
      if (quoted && i + 1 < csv.length && csv[i + 1] == '"') {
        field.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (c == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((c == '\n' || c == '\r') && !quoted) {
      finishRow();
      if (c == '\r' && i + 1 < csv.length && csv[i + 1] == '\n') i++;
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) finishRow();
  return result;
}

(List<CatalogBook>, String?) parseStandardPage((String, String) input) {
  final base = Uri.parse(input.$2);
  final doc = XmlDocument.parse(input.$1);
  final result = <CatalogBook>[];
  final list = doc.descendants
      .whereType<XmlElement>()
      .where(
        (e) =>
            e.name.local == 'ol' &&
            (e.getAttribute('class') ?? '').split(' ').contains('ebooks-list'),
      )
      .firstOrNull;
  if (list != null) {
    for (final entry in list.childElements.where((e) => e.name.local == 'li')) {
      final path = entry.getAttribute('about');
      if (path == null || !path.startsWith('/ebooks/')) continue;
      final title = entry.descendants
          .whereType<XmlElement>()
          .where((e) => e.getAttribute('property') == 'schema:name')
          .firstOrNull
          ?.innerText
          .trim();
      final author =
          entry.descendants
              .whereType<XmlElement>()
              .where((e) => e.getAttribute('property') == 'schema:author')
              .firstOrNull
              ?.innerText
              .trim() ??
          '';
      if (title == null || title.isEmpty) continue;
      result.add(
        CatalogBook(
          id: 'standard:$path',
          title: title,
          author: author,
          source: 'Standard Ebooks',
          pageUrl: base.resolve(path).toString(),
        ),
      );
    }
  }
  final next = doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'a' && e.getAttribute('rel') == 'next')
      .firstOrNull
      ?.getAttribute('href');
  final uri = next == null ? null : base.resolve(next);
  if (uri != null &&
      (uri.host != 'standardebooks.org' || uri.path != '/ebooks')) {
    throw const FormatException('目录分页地址无效');
  }
  return (result, uri?.toString());
}

String standardDownloadUrl((String, String) input) {
  final base = Uri.parse(input.$2);
  final doc = XmlDocument.parse(input.$1);
  final candidates = doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'a')
      .map((e) => e.getAttribute('href') ?? '')
      .where((s) => s.endsWith('.epub') && !s.endsWith('.kepub.epub'))
      .toList();
  if (candidates.isEmpty) throw const FormatException('此书暂未提供 EPUB');
  final href =
      candidates.where((s) => !s.endsWith('_advanced.epub')).firstOrNull ??
      candidates.first;
  final uri = base.resolve(href);
  if (uri.host != 'standardebooks.org' || uri.scheme != 'https') {
    throw const FormatException('书源下载地址无效');
  }
  return uri.toString();
}
