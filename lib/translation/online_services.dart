/// Provider defaults verified against official documentation on 2026-11-26.
class OnlineTranslationService {
  final String id, name, endpoint, keyPage;
  final List<String> models;
  const OnlineTranslationService(
    this.id,
    this.name,
    this.endpoint,
    this.keyPage,
    this.models,
  );
  static const all = [
    OnlineTranslationService(
      'openrouter',
      'OpenRouter',
      'https://openrouter.ai/api/v1',
      'https://openrouter.ai/settings/keys',
      [
        'openai/gpt-4.1-mini',
        'google/gemini-3.5-flash-lite',
        'openai/gpt-4.1-nano',
      ],
    ),
    OnlineTranslationService(
      'openai',
      'OpenAI（ChatGPT 系列）',
      'https://api.openai.com/v1',
      'https://platform.openai.com/api-keys',
      ['gpt-4.1-mini', 'gpt-4.1-nano'],
    ),
    OnlineTranslationService(
      'gemini',
      'Google Gemini',
      'https://generativelanguage.googleapis.com/v1beta/openai',
      'https://aistudio.google.com/apikey',
      ['gemini-3.5-flash-lite', 'gemini-3.8-flash'],
    ),
    OnlineTranslationService('custom', '自定义兼容服务', '', '', []),
  ];
  static OnlineTranslationService byId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => all.last);
  static OnlineTranslationService forEndpoint(String endpoint) =>
      all.firstWhere(
        (s) =>
            s.endpoint.isNotEmpty &&
            s.endpoint == endpoint.replaceFirst(RegExp(r'/$'), ''),
        orElse: () => all.last,
      );
}
