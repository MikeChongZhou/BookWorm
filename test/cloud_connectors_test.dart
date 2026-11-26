import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yuejian/cloud/icloud_provider.dart';
import 'package:yuejian/cloud/cloud_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuejian/cloud/oauth_session.dart';
import 'package:yuejian/cloud/drive_providers.dart';

class FakeSession extends OAuthSession {
  FakeSession(http.Client client)
    : super(
        provider: 'test',
        clientId: 'test',
        authorizationEndpoint: 'https://example.com/auth',
        tokenEndpoint: 'https://example.com/token',
        scope: 'test',
        redirect: 'bookworm://oauth',
        client: client,
      );
  @override
  Future<String> token({bool interactive = false}) async => 'test-token';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Google Drive lists once for concurrent new files, not before every upload',
    () async {
      var listings = 0, uploads = 0;
      final client = MockClient((r) async {
        if (r.method == 'GET') {
          listings++;
          return http.Response(jsonEncode({'files': []}), 200);
        }
        if (r.method == 'POST') {
          return http.Response(
            '',
            200,
            headers: {
              'location':
                  'https://www.googleapis.com/upload-session/${uploads++}',
            },
          );
        }
        return http.Response(
          jsonEncode({'id': 'file-${r.url.pathSegments.last}'}),
          200,
        );
      });
      final drive = GoogleDriveProvider(FakeSession(client));
      await Future.wait(
        List.generate(4, (i) => drive.write('new-$i', Uint8List.fromList([i]))),
      );
      expect(listings, 1);
      expect(uploads, 4);
    },
  );
  test('concurrent OAuth requests share one refresh exchange', () async {
    FlutterSecureStorage.setMockInitialValues({
      'bookworm_test_refresh': 'refresh-token',
    });
    var exchanges = 0;
    final session = OAuthSession(
      provider: 'test',
      clientId: 'id',
      authorizationEndpoint: 'https://example.com/auth',
      tokenEndpoint: 'https://example.com/token',
      scope: 'test',
      redirect: 'bookworm://oauth',
      client: MockClient((r) async {
        exchanges++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return http.Response(
          jsonEncode({
            'access_token': 'access',
            'refresh_token': 'rotated',
            'expires_in': 3600,
          }),
          200,
        );
      }),
    );
    expect(
      await Future.wait(List.generate(4, (_) => session.token())),
      List.filled(4, 'access'),
    );
    expect(exchanges, 1);
  });
  test('CloudKit uses private database and rotates user token', () async {
    FlutterSecureStorage.setMockInitialValues({
      'bookworm_cloudkit_token': 'old-token',
    });
    final client = MockClient((request) async {
      expect(request.url.path, contains('/private/users/current'));
      expect(request.url.queryParameters['ckWebAuthToken'], 'old-token');
      return http.Response(
        jsonEncode({'ckWebAuthToken': 'new-token', 'userRecordName': 'user'}),
        200,
      );
    });
    final provider = ICloudProvider(
      container: 'iCloud.test',
      apiToken: 'api',
      redirect: 'bookworm://cloudkit',
      client: client,
    );
    await provider.connect();
    expect(
      await const FlutterSecureStorage().read(key: 'bookworm_cloudkit_token'),
      'new-token',
    );
  });
  test('CloudKit network failure never displays token-bearing URI', () async {
    FlutterSecureStorage.setMockInitialValues({
      'bookworm_cloudkit_token': 'sensitive-token',
    });
    final client = MockClient((request) async {
      throw http.ClientException('failed', request.url);
    });
    final provider = ICloudProvider(
      container: 'iCloud.test',
      apiToken: 'private-api',
      redirect: 'bookworm://cloudkit',
      client: client,
    );
    try {
      await provider.connect();
      fail('should fail');
    } on CloudFailure catch (e) {
      expect(e.message, isNot(contains('sensitive-token')));
      expect(e.message, isNot(contains('private-api')));
    }
  });
  test(
    'OneDrive uses item metadata and never forwards bearer to download host',
    () async {
      final calls = <http.Request>[];
      final client = MockClient((r) async {
        calls.add(r);
        if (r.url.host == 'graph.microsoft.com') {
          return http.Response(
            jsonEncode({
              '@microsoft.graph.downloadUrl': 'https://files.example.com/book',
            }),
            200,
          );
        }
        expect(r.headers.containsKey('Authorization'), isFalse);
        expect(r.headers.containsKey('authorization'), isFalse);
        return http.Response('source', 200);
      });
      final provider = OneDriveProvider(FakeSession(client));
      final bytes = await provider.read('book-abc.part');
      expect(utf8.decode(bytes), 'source');
      expect(calls.first.url.path, endsWith('approot:/book-abc.part'));
    },
  );
  test(
    'Google Drive lists appDataFolder and selects latest duplicate name',
    () async {
      var calls = 0;
      final client = MockClient((r) async {
        if (calls++ == 0) {
          expect(r.url.queryParameters['spaces'], 'appDataFolder');
          return http.Response(
            jsonEncode({
              'files': [
                {'id': 'new', 'name': 'same'},
                {'id': 'old', 'name': 'same'},
              ],
            }),
            200,
          );
        }
        expect(r.url.path, endsWith('/new'));
        expect(r.url.queryParameters['alt'], 'media');
        return http.Response('book', 200);
      });
      final provider = GoogleDriveProvider(FakeSession(client));
      expect(await provider.list(), ['same']);
      expect(utf8.decode(await provider.read('same')), 'book');
    },
  );
}
