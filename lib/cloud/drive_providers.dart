import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'cloud_provider.dart';
import 'oauth_session.dart';

class OneDriveProvider implements CloudProvider {
  final OAuthSession session;
  OneDriveProvider(this.session);
  factory OneDriveProvider.production() => OneDriveProvider(
    OAuthSession(
      provider: 'onedrive',
      clientId: const String.fromEnvironment('ONEDRIVE_CLIENT_ID'),
      authorizationEndpoint:
          'https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize',
      tokenEndpoint:
          'https://login.microsoftonline.com/consumers/oauth2/v2.0/token',
      scope: 'offline_access Files.ReadWrite.AppFolder',
      redirect: Platform.isWindows
          ? 'http://localhost:43821/'
          : 'bookworm://oauth',
    ),
  );
  @override
  String get name => 'OneDrive';
  @override
  bool get configured => session.clientId.isNotEmpty;
  Uri path(String value) => Uri.parse(
    'https://graph.microsoft.com/v1.0/me/drive/special/approot$value',
  );
  @override
  Future<void> connect() async {
    await session.token(interactive: true);
  }

  @override
  Future<void> disconnect() => session.disconnect();
  @override
  Future<List<String>> list() async {
    Uri? url = path('/children?\$select=name&\$top=200');
    final keys = <String>[];
    while (url != null) {
      final j = jsonDecode((await session.request('GET', url)).body) as Map;
      keys.addAll((j['value'] as List).map((v) => v['name'] as String));
      final next = j['@odata.nextLink'] as String?;
      url = next == null ? null : Uri.parse(next);
      if (url != null &&
          (url.scheme != 'https' || url.host != 'graph.microsoft.com')) {
        throw const CloudFailure('云服务分页地址无效');
      }
    }
    return keys;
  }

  @override
  Future<Uint8List> read(String key) async {
    // Graph content redirects to a short-lived download URL. Do not forward the bearer token.
    final meta = jsonDecode(
      (await session.request(
        'GET',
        path(':/${Uri.encodeComponent(key)}'),
      )).body,
    ) as Map;
    final download = Uri.parse(meta['@microsoft.graph.downloadUrl'] as String);
    if (download.scheme != 'https') throw const CloudFailure('下载地址无效');
    final response = await session.client
        .get(download)
        .timeout(const Duration(minutes: 3));
    if (response.statusCode != 200) throw const CloudFailure('私人云下载失败');
    if (response.bodyBytes.length > 100 * 1024 * 1024) {
      throw const CloudFailure('云文件过大');
    }
    return response.bodyBytes;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    await session.request(
      'PUT',
      path(':/${Uri.encodeComponent(key)}:/content'),
      headers: {'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
  }
}

class GoogleDriveProvider implements CloudProvider {
  final OAuthSession session;
  final Map<String, String> _ids = {};
  bool _listed = false;
  Future<List<String>>? _listing;
  Future<void> _ensureListed() async {
    if (_listed) return;
    final pending = _listing ??= list();
    try {
      await pending;
    } finally {
      if (identical(_listing, pending)) _listing = null;
    }
  }

  GoogleDriveProvider(this.session);
  factory GoogleDriveProvider.production() => GoogleDriveProvider(
    OAuthSession(
      provider: 'google',
      clientId: const String.fromEnvironment('GOOGLE_CLIENT_ID'),
      authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
      tokenEndpoint: 'https://oauth2.googleapis.com/token',
      scope: 'https://www.googleapis.com/auth/drive.appdata',
      redirect: Platform.isWindows
          ? 'http://localhost:43822/'
          : const String.fromEnvironment(
              'GOOGLE_REDIRECT_URI',
              defaultValue: 'bookworm://oauth',
            ),
    ),
  );
  @override
  String get name => 'Google Drive';
  @override
  bool get configured => session.clientId.isNotEmpty;
  @override
  Future<void> connect() async {
    await session.token(interactive: true);
    await list();
  }

  @override
  Future<void> disconnect() async {
    _ids.clear();
    _listed = false;
    await session.disconnect();
  }

  @override
  Future<List<String>> list() async {
    _ids.clear();
    String? page;
    do {
      final url = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'spaces': 'appDataFolder',
        'q': 'trashed = false',
        'fields': 'nextPageToken,files(id,name)',
        'orderBy': 'modifiedTime desc',
        'pageSize': '1000',
        'pageToken': ?page,
      });
      final j = jsonDecode((await session.request('GET', url)).body) as Map;
      for (final f in j['files'] as List) {
        _ids.putIfAbsent(f['name'] as String, () => f['id'] as String);
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);
    _listed = true;
    return _ids.keys.toList();
  }

  @override
  Future<Uint8List> read(String key) async {
    await _ensureListed();
    final id = _ids[key];
    if (id == null) throw const CloudFailure('云文件不存在');
    final r = await session.request(
      'GET',
      Uri.https('www.googleapis.com', '/drive/v3/files/$id', {'alt': 'media'}),
    );
    if (r.bodyBytes.length > 100 * 1024 * 1024) {
      throw const CloudFailure('云文件过大');
    }
    return r.bodyBytes;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    await _ensureListed();
    final id = _ids[key];
    final url = Uri.https(
      'www.googleapis.com',
      id == null ? '/upload/drive/v3/files' : '/upload/drive/v3/files/$id',
      {'uploadType': 'resumable'},
    );
    final response = await session.request(
      id == null ? 'POST' : 'PATCH',
      url,
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'application/octet-stream',
        'X-Upload-Content-Length': '${bytes.length}',
      },
      body: utf8.encode(
        jsonEncode({
          'name': key,
          if (id == null) 'parents': ['appDataFolder'],
        }),
      ),
    );
    final location = response.headers['location'];
    if (location == null) throw const CloudFailure('未获得 Google 上传会话');
    final target = Uri.parse(location);
    if (target.scheme != 'https' ||
        !(target.host == 'www.googleapis.com' ||
            target.host.endsWith('.googleapis.com'))) {
      throw const CloudFailure('上传地址无效');
    }
    final result = await session.request(
      'PUT',
      target,
      headers: {'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
    final j = jsonDecode(result.body) as Map;
    if (j['id'] != null) _ids[key] = j['id'] as String;
  }
}
