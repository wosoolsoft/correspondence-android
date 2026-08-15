/// سجل مزودات الذكاء الاصطناعي المدعومة — مطابق لنسخة سطح المكتب.
///
/// sdk == 'openai': أي مزود متوافق مع OpenAI API (يُستخدم معه baseUrl المعرَّف هنا)،
/// sdk == 'anthropic': واجهة Anthropic الرسمية (نماذج Claude).
library;

class ProviderPreset {
  final String id;
  final String label;
  final String sdk;
  final String baseUrl;
  final String defaultModel;
  final bool needsKey;
  final List<String> models;
  final String hint;
  final String keysUrl;
  final String keysLabel;

  const ProviderPreset({
    required this.id,
    required this.label,
    required this.sdk,
    this.baseUrl = '',
    this.defaultModel = '',
    this.needsKey = true,
    this.models = const [],
    this.hint = '',
    this.keysUrl = '',
    this.keysLabel = '',
  });
}

const kDefaultProvider = 'openai';

const kProviders = <ProviderPreset>[
  ProviderPreset(
    id: 'openai',
    label: 'OpenAI',
    sdk: 'openai',
    defaultModel: 'gpt-5',
    models: ['gpt-5', 'gpt-5-mini', 'gpt-5.1', 'gpt-4o'],
    hint: 'المزود الافتراضي — خوادم OpenAI الرسمية.',
    keysUrl: 'https://platform.openai.com/api-keys',
  ),
  ProviderPreset(
    id: 'anthropic',
    label: 'Anthropic (Claude)',
    sdk: 'anthropic',
    defaultModel: 'claude-opus-5',
    models: ['claude-opus-5', 'claude-sonnet-5', 'claude-haiku-4-5'],
    hint: 'نماذج Claude من Anthropic — قوية في الصياغة العربية الرسمية.',
    keysUrl: 'https://platform.claude.com/settings/keys',
  ),
  ProviderPreset(
    id: 'openrouter',
    label: 'OpenRouter',
    sdk: 'openai',
    baseUrl: 'https://openrouter.ai/api/v1',
    defaultModel: 'openai/gpt-5',
    models: [
      'openai/gpt-5',
      'anthropic/claude-opus-5',
      'google/gemini-2.5-pro',
      'deepseek/deepseek-chat',
    ],
    hint: 'بوابة واحدة لمئات النماذج من مزودات مختلفة بمفتاح واحد.',
    keysUrl: 'https://openrouter.ai/settings/keys',
  ),
  ProviderPreset(
    id: 'groq',
    label: 'Groq',
    sdk: 'openai',
    baseUrl: 'https://api.groq.com/openai/v1',
    defaultModel: 'llama-3.3-70b-versatile',
    models: ['llama-3.3-70b-versatile'],
    hint: 'استدلال فائق السرعة لنماذج مفتوحة المصدر.',
    keysUrl: 'https://console.groq.com/keys',
  ),
  ProviderPreset(
    id: 'deepseek',
    label: 'DeepSeek',
    sdk: 'openai',
    baseUrl: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
    models: ['deepseek-chat', 'deepseek-reasoner'],
    hint: 'نماذج DeepSeek بتكلفة منخفضة.',
    keysUrl: 'https://platform.deepseek.com/api_keys',
  ),
  ProviderPreset(
    id: 'together',
    label: 'Together AI',
    sdk: 'openai',
    baseUrl: 'https://api.together.xyz/v1',
    defaultModel: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
    models: ['meta-llama/Llama-3.3-70B-Instruct-Turbo'],
    hint: 'استضافة نماذج مفتوحة المصدر.',
    keysUrl: 'https://api.together.ai/settings/api-keys',
  ),
  ProviderPreset(
    id: 'ollama',
    label: 'Ollama (على جهازك)',
    sdk: 'openai',
    baseUrl: 'http://192.168.1.100:11434/v1',
    defaultModel: 'qwen3',
    needsKey: false,
    models: ['qwen3', 'gemma3', 'llama3.3'],
    hint: 'نماذج محلية على حاسوبك في نفس الشبكة — خصوصية كاملة. '
        'شغّل Ollama على الحاسوب ثم أدخل عنوانه في الشبكة المحلية '
        '(مثل http://192.168.1.100:11434/v1).',
    keysUrl: 'https://ollama.com/download',
    keysLabel: '⬇ حمّل Ollama من الموقع الرسمي وشغّله — لا حاجة لأي مفتاح',
  ),
  ProviderPreset(
    id: 'custom',
    label: 'مزود مخصص (متوافق مع OpenAI)',
    sdk: 'openai',
    needsKey: false,
    hint: 'أي خادم متوافق مع OpenAI API (مثل LM Studio أو vLLM) — '
        'أدخل عنوان الخادم واسم النموذج، والمفتاح إن لزم.',
  ),
];

ProviderPreset providerById(String id) =>
    kProviders.firstWhere((p) => p.id == id,
        orElse: () => kProviders.first);

/// إعدادات المزود المحلولة: دمج المخزَّن مع افتراضيات المزود.
class ResolvedProvider {
  final String id;
  final String sdk;
  final String label;
  final bool needsKey;
  final String apiKey;
  final String model;
  final String baseUrl;

  const ResolvedProvider({
    required this.id,
    required this.sdk,
    required this.label,
    required this.needsKey,
    required this.apiKey,
    required this.model,
    required this.baseUrl,
  });
}
