import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuejian/translation/translation_settings.dart';
import 'package:yuejian/translation/paragraph_lesson.dart';
import 'package:yuejian/translation/paragraph_translator.dart';
import 'package:yuejian/translation/online_services.dart';
import 'package:yuejian/translation/openrouter_login.dart';
import 'package:crypto/crypto.dart';
import 'package:yuejian/audio/reading_player.dart';
import 'package:yuejian/audio/file_audio_transport.dart';
import 'package:yuejian/models/local_book.dart';

class LessonTranslator implements ParagraphTranslator {
  int calls = 0;
  @override
  Future<ParagraphLesson> translate({
    required String original,
    required String targetLanguage,
    required String bookTitle,
    required String chapterTitle,
    required bool includeBackground,
  }) async {
    calls++;
    return ParagraphLesson(
      translation: '译文。',
      background: includeBackground ? '背景。' : '',
      sourceLanguage: 'en',
    );
  }
}

class LessonSpeech implements SpeechEngine, SpeechLanguage, SpeechTiming {
  final spoken = <String>[], languages = <String>[];
  final starts = <Duration>[];
  Completer<void>? done;
  void Function(Duration, Duration)? timing;
  @override
  bool get hasMediaClock => true;
  @override
  void playbackProgress(void Function(Duration, Duration) value) =>
      timing = value;
  @override
  void startPosition(Duration position) => starts.add(position);
  @override
  Future<void> prepare() async {}
  @override
  Future<void> speak(String text) {
    spoken.add(text);
    done = Completer<void>();
    return done!.future;
  }

  void complete() {
    if (done != null && !done!.isCompleted) done!.complete();
  }

  @override
  Future<void> stop() async => complete();
  @override
  Future<void> language(String code) async => languages.add(code);
  @override
  Future<void> rate(double value) async {}
  @override
  Future<void> voice(Map<String, String> value) async {}
  @override
  Future<List<Map<String, String>>> voices() async => [];
  @override
  void progress(void Function(int, int) callback) {}
}

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  throw StateError('Playback did not reach expected step');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  LocalBook book() => LocalBook(
    id: 'lesson',
    title: 'Book',
    author: 'Author',
    format: 'txt',
    sections: [const BookSection('Chapter', 'Hello.')],
  );

  test('service presets fill endpoint and model without reusing another service key', () async {
    final s = TranslationSettings();
    for (final id in ['openrouter', 'openai', 'gemini']) {
      await s.selectService(id);
      final preset = OnlineTranslationService.byId(id);
      expect(s.provider, 'online');
      expect(s.onlineService, id);
      expect(s.endpoint, preset.endpoint);
      expect(s.model, preset.models.first);
    }
    await s.update(apiKey: 'gemini-test');
    expect(await s.hasOnlineCredential, isTrue);
    await s.selectService('openai');
    expect(await s.hasOnlineCredential, isFalse);
    await s.selectService('gemini');
    expect(await s.hasOnlineCredential, isTrue);
    await s.clearOnlineCredential();
    expect(await s.hasOnlineCredential, isFalse);
    s.dispose();
  });
  test('OpenRouter login uses per-attempt PKCE and validates callback before exchanging code', () async {
    String? challenge;
    var exchanges = 0;
    final client = MockClient((r) async {
      exchanges++;
      expect(r.url.toString(), 'https://openrouter.ai/api/v1/auth/keys');
      expect(r.headers['authorization'], isNull);
      final body = jsonDecode(r.body);
      expect(body['code'], 'single-use-code');
      expect(body['code_challenge_method'], 'S256');
      expect(
        base64UrlEncode(
          sha256.convert(utf8.encode(body['code_verifier'])).bytes,
        ).replaceAll('=', ''),
        challenge,
      );
      return http.Response(jsonEncode({'key': 'test-user-key'}), 200);
    });
    final login = OpenRouterLogin(
      client: client,
      authenticate: (url, callback) async {
        final auth = Uri.parse(url);
        expect(auth.host, 'openrouter.ai');
        challenge = auth.queryParameters['code_challenge'];
        final target = Uri.parse(auth.queryParameters['callback_url']!);
        return target
            .replace(
              queryParameters: {
                ...target.queryParameters,
                'code': 'single-use-code',
              },
            )
            .toString();
      },
    );
    expect(await login.login(), 'test-user-key');
    expect(exchanges, 1);
    final bad = OpenRouterLogin(
      client: client,
      authenticate: (url, callback) async {
        final target = Uri.parse(
          Uri.parse(url).queryParameters['callback_url']!,
        );
        return target
            .replace(
              queryParameters: {'state': 'wrong', 'code': 'single-use-code'},
            )
            .toString();
      },
    );
    await expectLater(bad.login(), throwsStateError);
    expect(exchanges, 1);
    client.close();
  });
  test(
    'target defaults to system and background toggles serialize and persist',
    () async {
      final s = TranslationSettings();
      await s.load();
      expect(s.targetLanguage, 'system');
      expect(s.resolvedTarget, isNotEmpty);
      await Future.wait([s.toggleBackground(), s.toggleBackground()]);
      expect(s.includeBackground, isTrue);
      await s.toggleBackground();
      final reloaded = TranslationSettings();
      await reloaded.load();
      expect(reloaded.includeBackground, isFalse);
      s.dispose();
      reloaded.dispose();
    },
  );
  test('player speaks original, target translation, background, original again without moving source progress early', () async {
    final s = TranslationSettings();
    await s.update(enabled: true, targetLanguage: 'zh');
    final speech = LessonSpeech(),
        translator = LessonTranslator(),
        source = book();
    final p = ReadingPlayer(
      source,
      speech,
      () async {},
      translationSettings: s,
      translator: translator,
    );
    addTearDown(p.dispose);
    addTearDown(s.dispose);
    final play = p.play();
    for (var i = 1; i <= 4; i++) {
      await waitFor(() => speech.spoken.length == i);
      expect(source.offset, 0);
      speech.complete();
    }
    await play;
    expect(speech.spoken, ['Hello.', '译文。', '背景。', 'Hello.']);
    expect(speech.languages, ['en', 'zh', 'zh', 'en']);
    expect(source.offset, 6);
    expect(translator.calls, 1);
  });
  test('playback background toggle skips optional phase and pause resumes translation audio rather than original', () async {
    final s = TranslationSettings();
    await s.update(enabled: true, targetLanguage: 'zh');
    final speech = LessonSpeech(), translator = LessonTranslator();
    final p = ReadingPlayer(
      book(),
      speech,
      () async {},
      translationSettings: s,
      translator: translator,
    );
    addTearDown(p.dispose);
    addTearDown(s.dispose);
    final first = p.play();
    await waitFor(() => speech.spoken.length == 1);
    speech.complete();
    await waitFor(() => speech.spoken.length == 2);
    speech.timing?.call(const Duration(seconds: 2), const Duration(seconds: 8));
    await p.pause();
    await first;
    await s.toggleBackground();
    final second = p.play();
    await waitFor(() => speech.spoken.length == 3);
    expect(speech.spoken.last, '译文。');
    expect(speech.starts.last, const Duration(seconds: 2));
    speech.complete();
    await waitFor(() => speech.spoken.length == 4);
    expect(speech.spoken.last, 'Hello.');
    speech.complete();
    await second;
    expect(speech.spoken, isNot(contains('背景。')));
    expect(translator.calls, 1);
  });
  test(
    'turning background on during translation adds the optional explanation',
    () async {
      final s = TranslationSettings();
      await s.update(
        enabled: true,
        includeBackground: false,
        targetLanguage: 'zh',
      );
      final speech = LessonSpeech(), translator = LessonTranslator();
      final p = ReadingPlayer(
        book(),
        speech,
        () async {},
        translationSettings: s,
        translator: translator,
      );
      addTearDown(p.dispose);
      addTearDown(s.dispose);
      final play = p.play();
      await waitFor(() => speech.spoken.length == 1);
      speech.complete();
      await waitFor(() => speech.spoken.length == 2);
      await s.toggleBackground();
      speech.complete();
      await waitFor(() => speech.spoken.length == 3);
      expect(speech.spoken.last, '背景。');
      speech.complete();
      await waitFor(() => speech.spoken.length == 4);
      speech.complete();
      await play;
      expect(translator.calls, 2);
    },
  );
  test(
    'turning background off while it is speaking skips to the original repeat',
    () async {
      final s = TranslationSettings();
      await s.update(enabled: true, targetLanguage: 'zh');
      final speech = LessonSpeech();
      final p = ReadingPlayer(
        book(),
        speech,
        () async {},
        translationSettings: s,
        translator: LessonTranslator(),
      );
      addTearDown(p.dispose);
      addTearDown(s.dispose);
      final play = p.play();
      await waitFor(() => speech.spoken.length == 1);
      speech.complete();
      await waitFor(() => speech.spoken.length == 2);
      speech.complete();
      await waitFor(() => speech.spoken.length == 3);
      await s.toggleBackground();
      await waitFor(() => speech.spoken.length == 4);
      expect(speech.spoken.last, 'Hello.');
      speech.complete();
      await play;
    },
  );
  test('local and online adapters use selected endpoints and scope API keys to the configured service', () async {
    final s = TranslationSettings();
    await s.update(endpoint: 'http://127.0.0.1:11434', model: 'local-model');
    final requests = <http.Request>[];
    final client = MockClient((r) async {
      requests.add(r);
      final output = jsonEncode({
        'translation': '译文',
        'background': '',
        'sourceLanguage': 'en',
      });
      return http.Response(
        jsonEncode(
          r.url.path == '/api/chat'
              ? {
                  'message': {'content': output},
                }
              : {
                  'choices': [
                    {
                      'message': {'content': output},
                    },
                  ],
                },
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final t = ConfiguredParagraphTranslator(s, client: client);
    Future<ParagraphLesson> invoke() => t.translate(
      original: 'Hello',
      targetLanguage: 'zh',
      bookTitle: 'Book',
      chapterTitle: 'One',
      includeBackground: false,
    );
    await invoke();
    expect(requests.last.url.path, '/api/chat');
    final prompt =
        (jsonDecode(requests.last.body)['messages'] as List).first['content']
            as String;
    expect(prompt, contains('Classical or Literary Chinese'));
    expect(prompt, contains('Old or Middle English'));
    expect(prompt, contains('Never skip translation'));
    expect(requests.last.headers['authorization'], isNull);
    await s.update(
      provider: 'online',
      endpoint: 'https://example.com/v1',
      model: 'remote',
      apiKey: 'test-key',
    );
    await invoke();
    expect(requests.last.url.path, '/v1/chat/completions');
    expect(requests.last.headers['authorization'], 'Bearer test-key');
    await s.update(endpoint: 'https://other.example/v1');
    await invoke();
    expect(requests.last.headers['authorization'], isNull);
    expect(
      () => TranslationSettings.validateEndpoint(
        'http://example.com',
        local: false,
      ),
      throwsFormatException,
    );
    s.dispose();
    client.close();
  });
  test('transient Gemini 503 retries the same model and succeeds', () async {
    final s = TranslationSettings();
    await s.selectService('gemini');
    await s.update(model: 'gemini-3.8-flash', apiKey: 'private-test-key');
    var calls = 0;
    final delays = <Duration>[];
    final client = MockClient((r) async {
      calls++;
      expect(r.url.path, '/v1beta/openai/chat/completions');
      expect(jsonDecode(r.body)['model'], 'gemini-3.8-flash');
      if (calls < 3) {
        return http.Response(
          jsonEncode({
            'error': {'status': 'UNAVAILABLE'},
          }),
          503,
        );
      }
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'translation': 'Translated',
                  'background': '',
                  'sourceLanguage': 'en',
                }),
              },
            },
          ],
        }),
        200,
      );
    });
    final translator = ConfiguredParagraphTranslator(
      s,
      client: client,
      retryWait: (d) async {
        delays.add(d);
      },
    );
    final result = await translator.translate(
      original: 'Hello',
      targetLanguage: 'zh',
      bookTitle: 'Book',
      chapterTitle: 'One',
      includeBackground: false,
    );
    expect(result.translation, 'Translated');
    expect(calls, 3);
    expect(delays.length, 2);
    expect(delays[1], greaterThan(delays[0]));
    s.dispose();
    client.close();
  });
  test('persistent 503 reports safe service status; authorization failures do not retry', () async {
    final s = TranslationSettings();
    await s.selectService('gemini');
    var calls = 0, code = 503;
    final client = MockClient((_) async {
      calls++;
      return http.Response(
        jsonEncode({
          'error': {
            'status': 'UNAVAILABLE',
            'message': 'private-key-and-book-excerpt',
          },
        }),
        code,
      );
    });
    final translator = ConfiguredParagraphTranslator(
      s,
      client: client,
      retryWait: (_) async {},
    );
    Future<ParagraphLesson> invoke() => translator.translate(
      original: 'Hello',
      targetLanguage: 'zh',
      bookTitle: 'Book',
      chapterTitle: 'One',
      includeBackground: false,
    );
    await expectLater(
      invoke(),
      throwsA(
        predicate(
          (e) =>
              e.toString().contains('HTTP 503 (UNAVAILABLE)') &&
              !e.toString().contains('private-key-and-book-excerpt'),
        ),
      ),
    );
    expect(calls, 3);
    code = 403;
    calls = 0;
    await expectLater(
      invoke(),
      throwsA(predicate((e) => e.toString().contains('HTTP 403'))),
    );
    expect(calls, 1);
    s.dispose();
    client.close();
  });
  test('pausing translation prevents another automatic retry', () async {
    final s = TranslationSettings();
    await s.selectService('gemini');
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('{}', 503);
    });
    late ConfiguredParagraphTranslator translator;
    translator = ConfiguredParagraphTranslator(
      s,
      client: client,
      retryWait: (_) async {
        translator.cancelPending();
      },
    );
    await expectLater(
      translator.translate(
        original: 'Hello',
        targetLanguage: 'zh',
        bookTitle: 'Book',
        chapterTitle: 'One',
        includeBackground: false,
      ),
      throwsStateError,
    );
    expect(calls, 1);
    s.dispose();
    client.close();
  });
  test('model errors stop translated playback without marking source paragraph complete', () async {
    final s = TranslationSettings();
    await s.update(
      enabled: true,
      endpoint: 'http://127.0.0.1:11434',
      model: 'test',
    );
    final client = MockClient((_) async => http.Response('failed', 500));
    final source = book();
    final p = ReadingPlayer(
      source,
      LessonSpeech(),
      () async {},
      translationSettings: s,
      translator: ConfiguredParagraphTranslator(s, client: client),
    );
    await p.play();
    expect(p.error, contains('HTTP 500'));
    expect(source.offset, 0);
    expect(p.playing, isFalse);
    p.dispose();
    s.dispose();
    client.close();
  });
}
