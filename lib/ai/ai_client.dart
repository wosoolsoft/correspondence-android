/// محرك الصياغة بالذكاء الاصطناعي (عدة مزودات) مع وضع تجريبي بدون مفتاح.
/// منقول حرفيًا عن نسخة سطح المكتب: نفس الموجّهات ونفس بنية JSON.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/settings_store.dart';
import '../models/letter_doc.dart';
import '../utils/dates.dart';
import 'providers.dart';

/// خطأ في الاتصال بمزود الذكاء الاصطناعي، برسالة عربية صالحة للعرض.
class AIError implements Exception {
  final String message;
  AIError(this.message);
  @override
  String toString() => message;
}

// أسلوب الدار المستخلص من رسائل الشركة السابقة، مع مثالين كاملين (few-shot).
const systemPrompt =
    r'''أنت كاتب ديوان محترف متخصص في صياغة الرسائل الرسمية باللغة العربية الفصحى للمنشآت والشركات والمؤسسات على اختلاف أنشطتها، وفق أصول المراسلات الرسمية العربية.

قواعد الصياغة الإلزامية:
1. اللغة فصحى رسمية مهذّبة، بصيغة الجمع («نود إفادتكم»، «نرجو منكم التكرم»).
2. سطر المستلم يبدأ بلقب مناسب حسب الجهة: «الأخوة /» للشركات والبنوك والمنظمات، «الأخ /» للأفراد، «الأستاذ القدير /» أو «معالي /» لكبار المسؤولين، وينتهي بكلمة «المحترمون» للجهات و«المحتـرم» للأفراد.
3. المتن يبدأ عادةً بـ«بالإشارة إلى الموضوع أعلاه،» ثم عرض الموضوع بوضوح. وللرسائل الموجّهة لكبار المسؤولين يبدأ بعبارات تمهيدية لائقة مثل «يطيب لنا أن نتقدّم إلى مقامكم الكريم...».
4. فقرات قصيرة واضحة: فقرة للتمهيد/الوقائع، فقرة للطلب المحدد، وفقرة ختامية عند الحاجة (تأكيد التزام، شكر، تعهد).
5. المبالغ تُكتب بالأرقام مع فواصل الآلاف وتُذكر العملة، وعند الأهمية يُكتب المبلغ كتابةً بين قوسين (تفقيط). التواريخ بصيغة يوم/شهر/سنة متبوعة بحرف «م».
6. عند وجود بيانات متعددة منظمة (حسابات، مبالغ، فروع، غرامات) استخدم جدولًا أو قائمة نقاط.
7. لا تُدرج التاريخ أو المرجع أو التوقيع في المتن؛ فهي حقول منفصلة يضيفها النظام.
8. الخاتمة عبارة مجاملة مناسبة تنتهي بثلاث فواصل «،،،».
9. التزم بالحقائق الواردة في طلب المستخدم فقط، ولا تختلق أرقامًا أو تواريخ أو أسماء. إن نقصت معلومة جوهرية فاترك مكانها بين قوسين معقوفين مثل: [رقم الحساب].

أعد الناتج بصيغة JSON فقط وفق البنية التالية حرفيًا:
{
  "subject": "الموضوع: ...",
  "recipient_lines": ["السطر الأول للمستلم", "..."],
  "greeting": "تحية طيبة وبعد،",
  "body": [
    {"type": "paragraph", "text": "..."},
    {"type": "bullets", "items": ["...", "..."]},
    {"type": "table", "header": ["...", "..."], "rows": [["...", "..."]]}
  ],
  "closing": "وتقبلوا خالص التحايا،،،"
}

مثال 1 — إشعار تحويل (بيانات افتراضية للإيضاح):
{
  "subject": "الموضوع: إشعار تحويل",
  "recipient_lines": ["الأخوة / منظمة الإغاثة الدولية – المكتب الإقليمي المحترمون"],
  "greeting": "تحية طيبة وبعد،",
  "body": [
    {"type": "paragraph", "text": "بالإشارة إلى الموضوع أعلاه، نود إحاطتكم علمًا بأنه تم إيداع مبلغ وقدره 45,750,320.5 ريال إلى حساب/ المؤسسة العامة للتأمينات – المركز الرئيسي، طرف البنك الوطني التعاوني، وذلك بناءً على طلبكم بتاريخ 12/03/2025م، مرفق لكم صورة من إشعار القيد."},
    {"type": "paragraph", "text": "نرجو منكم التكرم بإيداع مبلغ وقدره 85,420.6 دولار أمريكي (فقط خمسة وثمانون ألفًا وأربعمائة وعشرون دولارًا أمريكيًا وستون سنتًا لا غير) إلى الحساب التالي:"},
    {"type": "bullets", "items": ["اسم الحساب: شركة النورس لتصدير المنتجات البحرية.", "رقم الحساب: 0000-111111-222222-333", "طرف مصرف الشرق الشامل."]},
    {"type": "paragraph", "text": "وذلك مقابل مبلغ التحويل أعلاه بالإضافة إلى مبلغ 183,000 ريال كعمولة تحويل بنسبة 0.4%، وقد تمت مصارفة المبلغ بسعر 535 ريالًا للدولار الواحد."}
  ],
  "closing": "وتفضلوا بقبول فائق الاحترام والتقدير،،،"
}

مثال 2 — طلب إعادة نظر موجّه لمسؤول رفيع (بيانات افتراضية للإيضاح):
{
  "subject": "الموضوع: طلب إعادة النظر في الغرامات المالية المفروضة على الشركة",
  "recipient_lines": ["الأستاذ القدير/ محافظ البنك المركزي المحتــرم", "الأستاذ القدير/ نائب محافظ البنك المركزي المحتــرم"],
  "greeting": "السلام عليكم ورحمة الله وبركاته،",
  "body": [
    {"type": "paragraph", "text": "يطيب لنا أن نتقدّم إلى مقامكم الكريم بأسمى آيات التقدير والاحترام، متمنّين لكم دوام الصحة والتوفيق والسداد في أداء مهامكم الوطنية. ونتشرّف بأن نرفع إلى سيادتكم هذا الطلب لإعادة النظر في الغرامات المالية المفروضة على شركتنا، وبيانها على النحو التالي:"},
    {"type": "table", "header": ["المبلغ", "التفاصيل"], "rows": [["30,000,000 ريال", "بتاريخ 05/06/2025م فُرض جزاء مالي بواقع 50% من قيمة الضمان المالي لمخالفة أحكام المادة رقم (19) الفقرة (4) من اللائحة المنظِّمة."], ["15,500,000 ريال", "بتاريخ 18/07/2025م فُرض جزاء مالي لمخالفة أحكام المادة رقم (19) الفقرة (4) والمادة رقم (8)."], ["45,500,000 ريال", "الإجمالي الكلي للغرامات المالية المفروضة"]]},
    {"type": "paragraph", "text": "نلتمس من سيادتكم التكرّم بإعادة النظر في الغرامات المالية المفروضة أعلاه وإعفاء شركتنا منها، وذلك مراعاةً للظروف الاستثنائية الصعبة، ولما لهذه الغرامات من أثرٍ بالغ على قدرة الشركة على الاستمرار في مزاولة نشاطها."},
    {"type": "paragraph", "text": "كما نجدّد لسيادتكم تأكيد التزام شركتنا التام بجميع القوانين واللوائح والتعليمات الصادرة، ونتعهّد بالحرص التام على عدم تكرار أي مخالفات مستقبلًا."}
  ],
  "closing": "وتفضلوا بقبول خالص التقدير والاحترام،،،"
}''';

// درجات حدّة الرسالة وتوجيه الصياغة لكل درجة
const tones = <String, String>{
  'ودّية': 'نبرة دافئة ولطيفة: وسّع عبارات الشكر والتقدير، وقدّم الطلب بصيغة '
      'رجاء ودّي، وتجنّب أي تلميح للعتاب.',
  'رسمية محايدة': 'الأسلوب الرسمي المعتاد: مهذّب ومحايد، عرض واضح للوقائع '
      'والطلب دون تشديد أو مجاملة زائدة.',
  'حازمة': 'نبرة حازمة: طالِب بالحق بوضوح ومباشرة، سمِّ المسؤولية، وحدّد '
      'المطلوب ومهلة زمنية إن أمكن، مع بقاء كامل الاحترام واللياقة.',
  'شديدة اللهجة': 'نبرة شديدة رسمية: سجّل الاعتراض أو الاستنكار صراحة، أشِر '
      'إلى تحفّظ المنشأة على ما حدث وإلى حقها في اتخاذ ما تراه من '
      'إجراءات (نظامية أو تصعيدية) عند عدم التجاوب، دون أي إساءة '
      'أو خروج عن أدب المخاطبة الرسمية.',
};
const defaultTone = 'رسمية محايدة';

/// تحليل JSON بتسامح: يتجاوز أسوار الشيفرة ```json وأي نص حول الكائن —
/// بعض المزودات/النماذج لا تدعم فرض JSON فتعيده داخل نص حر.
Map<String, dynamic> parseJsonLenient(String? raw) {
  var text = (raw ?? '').trim();
  if (text.startsWith('```')) {
    text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
  }
  dynamic parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end <= start) {
      throw AIError('أعاد النموذج ردًا غير صالح، حاول مرة أخرى.');
    }
    try {
      parsed = jsonDecode(text.substring(start, end + 1));
    } on FormatException {
      throw AIError('أعاد النموذج ردًا غير صالح، حاول مرة أخرى.');
    }
  }
  if (parsed is! Map) {
    throw AIError('أعاد النموذج ردًا غير متوقع البنية، حاول مرة أخرى.');
  }
  if (parsed.isEmpty) {
    // كائن فارغ {} يعني فشل التوليد — لا نحفظ رسالة فارغة برقم مرجعي
    throw AIError('أعاد النموذج ردًا فارغًا، حاول مرة أخرى.');
  }
  return Map<String, dynamic>.from(parsed);
}

const _timeout = Duration(seconds: 120);

Never _throwConnectionError() => throw AIError(
    'انقطع الاتصال بخوادم الذكاء الاصطناعي — تأكد من اتصال الإنترنت '
    '(أو أن الخادم المحلي يعمل) وحاول مجددًا.');

Future<http.Response> _post(
    Uri url, Map<String, String> headers, Map<String, dynamic> body) async {
  try {
    return await http
        .post(url,
            headers: {'Content-Type': 'application/json', ...headers},
            body: jsonEncode(body))
        .timeout(_timeout);
  } on TimeoutException {
    _throwConnectionError();
  } on SocketException {
    _throwConnectionError();
  } on http.ClientException {
    _throwConnectionError();
  }
}

String _decodeBody(http.Response r) {
  try {
    return utf8.decode(r.bodyBytes);
  } catch (_) {
    return r.body;
  }
}

/// استدعاء أي مزود متوافق مع OpenAI API (OpenAI، OpenRouter، Groq، Ollama…).
Future<Map<String, dynamic>> _openaiChatJson(
    ResolvedProvider p, List<Map<String, String>> messages) async {
  final base = (p.baseUrl.isEmpty ? 'https://api.openai.com/v1' : p.baseUrl)
      .replaceFirst(RegExp(r'/+$'), '');
  final url = Uri.parse('$base/chat/completions');
  final headers = {
    'Authorization': 'Bearer ${p.apiKey.isEmpty ? 'no-key' : p.apiKey}'
  };
  var resp = await _post(url, headers, {
    'model': p.model,
    'messages': messages,
    'response_format': {'type': 'json_object'},
  });
  if (resp.statusCode == 400) {
    // بعض المزودات المتوافقة لا تدعم response_format — أعد المحاولة دونه
    resp = await _post(url, headers, {'model': p.model, 'messages': messages});
  }
  _checkStatus(resp, p);
  final data = jsonDecode(_decodeBody(resp));
  final choices = data is Map ? data['choices'] : null;
  final msg = (choices is List && choices.isNotEmpty && choices.first is Map)
      ? (choices.first['message'] ?? {})
      : {};
  final content = (msg is Map ? msg['content'] : null) as String?;
  if (content == null || content.trim().isEmpty) {
    // رفض أو فلترة: content يعود فارغًا (وقد يشرح refusal السبب)
    final refusal =
        ((msg is Map ? msg['refusal'] : null) as String?)?.trim() ?? '';
    throw AIError(refusal.isNotEmpty
        ? 'اعتذر النموذج عن تنفيذ هذا الطلب: $refusal'
        : 'أعاد النموذج ردًا فارغًا — حاول مجددًا أو غيّر النموذج '
            'من صفحة «الإعدادات».');
  }
  return parseJsonLenient(content);
}

/// استدعاء نماذج Claude عبر واجهة Anthropic الرسمية.
Future<Map<String, dynamic>> _anthropicChatJson(
    ResolvedProvider p, List<Map<String, String>> messages) async {
  final base = (p.baseUrl.isEmpty ? 'https://api.anthropic.com' : p.baseUrl)
      .replaceFirst(RegExp(r'/+$'), '');
  final url = Uri.parse('$base/v1/messages');
  final system = messages
      .where((m) => m['role'] == 'system')
      .map((m) => m['content'] ?? '')
      .join('\n\n');
  final chat = [for (final m in messages) if (m['role'] != 'system') m];
  final resp = await _post(url, {
    'x-api-key': p.apiKey,
    'anthropic-version': '2023-06-01',
  }, {
    'model': p.model,
    'max_tokens': 16000,
    'system': system,
    'messages': chat,
  });
  _checkStatus(resp, p);
  final data = jsonDecode(_decodeBody(resp));
  if (data is Map && data['stop_reason'] == 'refusal') {
    throw AIError('اعتذر النموذج عن تنفيذ هذا الطلب — '
        'أعد صياغة مضمون الرسالة وحاول مجددًا.');
  }
  final content = data is Map ? data['content'] : null;
  var text = '';
  if (content is List) {
    for (final b in content) {
      if (b is Map && b['type'] == 'text') {
        text = (b['text'] ?? '') as String;
        break;
      }
    }
  }
  return parseJsonLenient(text);
}

void _checkStatus(http.Response resp, ResolvedProvider p) {
  final code = resp.statusCode;
  if (code >= 200 && code < 300) return;
  if (code == 401 || code == 403) {
    throw AIError('مفتاح ${p.label} غير صالح أو منتهٍ — '
        'راجع صفحة «الإعدادات».');
  }
  if (code == 429) {
    throw AIError('تم تجاوز حد الاستخدام أو الرصيد لدى ${p.label} — '
        'حاول بعد قليل أو راجع حسابك.');
  }
  if (code == 404) {
    throw AIError('النموذج «${p.model}» غير متاح لدى ${p.label} — '
        'غيّر النموذج من صفحة «الإعدادات».');
  }
  var detail = _decodeBody(resp);
  try {
    final err = jsonDecode(detail);
    if (err is Map) {
      final e = err['error'];
      detail = (e is Map ? e['message'] : e ?? err['message'])?.toString() ??
          detail;
    }
  } catch (_) {}
  if (detail.length > 300) detail = detail.substring(0, 300);
  throw AIError('تعذّر الاتصال بمزود الذكاء الاصطناعي: $detail');
}

Future<Map<String, dynamic>> _chatJson(
    List<Map<String, String>> messages) async {
  final p = await SettingsStore.instance.resolveProvider();
  if (p.needsKey && p.apiKey.isEmpty) {
    throw AIError('لم يتم إعداد مفتاح ${p.label} بعد. أدخل المفتاح من صفحة '
        '«الإعدادات»، أو استخدم زر «توليد تجريبي» لتجربة النظام بدون '
        'ذكاء اصطناعي.');
  }
  if (p.model.isEmpty) {
    throw AIError('حدد اسم النموذج من صفحة «الإعدادات» أولًا.');
  }
  if (p.sdk == 'anthropic') return _anthropicChatJson(p, messages);
  return _openaiChatJson(p, messages);
}

/// فحص سريع للإعداد الحالي — يرمي AIError برسالة عربية عند أي خلل.
Future<void> testProvider() async {
  await _chatJson([
    {'role': 'system', 'content': 'أجب بصيغة JSON فقط.'},
    {'role': 'user', 'content': 'أعد الكائن التالي حرفيًا: {"ok": true}'},
  ]);
}

/// يبني مقطع «المراسلات المرجعية» الذي يُحقن في موجّه التوليد.
String referencesContext(List<Map<String, dynamic>>? references) {
  if (references == null || references.isEmpty) return '';
  final lines = <String>[
    '\nمراسلات سابقة يجب الإشارة إليها في متن الرسالة والالتزام بوقائعها حرفيًا:'
  ];
  for (var i = 0; i < references.length; i++) {
    final r = references[i];
    final n = i + 1;
    if (r['type'] == 'outgoing') {
      final doc = r['doc'];
      final bodyText = StringBuffer();
      if (doc is Map && doc['body'] is List) {
        for (final b in doc['body'] as List) {
          if (b is Map && b['type'] == 'paragraph') {
            bodyText.write('${b['text'] ?? ''} ');
          }
        }
      }
      var bt = bodyText.toString();
      if (bt.length > 1200) bt = bt.substring(0, 1200);
      lines.add('$n) رسالة صادرة منا — مرجعنا: ${r['ref_number'] ?? 'بدون'} '
          'بتاريخ ${fmtIsoDate(r['date_greg'] as String?)} — ${r['subject'] ?? ''} '
          '— موجهة إلى: ${r['party'] ?? ''} — نص متنها: $bt');
    } else {
      lines.add('$n) رسالة واردة إلينا من ${r['party'] ?? 'جهة'} — '
          'مرجعهم: ${r['ref_number'] ?? 'بدون'} '
          'بتاريخ ${fmtIsoDate(r['date_greg'] as String?)} — ${r['subject'] ?? ''} '
          '— ملخصها: ${r['summary'] ?? ''}');
    }
  }
  lines.add('التزم بالآتي: افتتح المتن بصيغة الإشارة الرسمية المناسبة '
      '(«بالإشارة إلى كتابنا رقم (…) وتاريخ …» للصادر، و«بالإشارة إلى كتابكم '
      'رقم (…) وتاريخ …» للوارد)، واذكر أرقام المراجع والتواريخ كما هي دون '
      'تغيير، ولا تختلق أي مرجع أو واقعة غير مذكورة أعلاه أو في طلب المستخدم.');
  return '${lines.join('\n')}\n';
}

/// توليد رسالة كاملة من وصف المستخدم.
Future<LetterDoc> generateLetter({
  required Map<String, dynamic> entity,
  required String letterType,
  required String recipient,
  required String brief,
  String greetingPref = '',
  String tone = defaultTone,
  Map<String, dynamic>? recipientInfo,
  List<Map<String, dynamic>>? references,
}) async {
  final toneGuide = tones[tone] ?? tones[defaultTone]!;
  var honorificHint = '';
  if (recipientInfo != null) {
    honorificHint = '\n- لقب مخاطبة هذه الجهة المعتمد لدينا: '
        '«${recipientInfo['honorific'] ?? 'الأخوة /'} ${recipientInfo['name'] ?? recipient} '
        '${recipientInfo['suffix'] ?? 'المحترمون'}» — استخدمه في سطر المستلم.';
  }
  final greeting = greetingPref.isNotEmpty
      ? greetingPref
      : ((entity['default_greeting'] as String?) ?? 'تحية طيبة وبعد،');
  final userMsg = '''صِغ رسالة رسمية جديدة بالمواصفات التالية:

- الجهة المرسِلة (منشأتنا): ${entity['name']}
- نوع الرسالة: $letterType
- الجهة المستلمة: $recipient$honorificHint
- التحية المفضلة: $greeting
- حدّة الرسالة المطلوبة: $tone — $toneGuide
${referencesContext(references)}
مضمون الرسالة كما وصفه المستخدم:
$brief

أعد JSON فقط.''';
  final raw = await _chatJson([
    {'role': 'system', 'content': systemPrompt},
    {'role': 'user', 'content': userMsg},
  ]);
  return LetterDoc.normalize(raw);
}

/// تنقيح رسالة قائمة بناءً على توجيه المستخدم.
Future<LetterDoc> reviseLetter({
  required Map<String, dynamic> entity,
  required LetterDoc doc,
  required String instruction,
  List<Map<String, dynamic>>? references,
}) async {
  final userMsg =
      '''هذه رسالة رسمية قائمة (بصيغة JSON) صادرة عن: ${entity['name']}

${doc.toJsonString()}
${referencesContext(references)}
المطلوب تعديلها وفق التوجيه التالي مع الحفاظ على الأسلوب الرسمي وبقية المحتوى كما هو ما لم يطلب التوجيه غير ذلك:
$instruction

أعد الرسالة كاملة بعد التعديل بصيغة JSON فقط وبنفس البنية.''';
  final raw = await _chatJson([
    {'role': 'system', 'content': systemPrompt},
    {'role': 'user', 'content': userMsg},
  ]);
  return LetterDoc.normalize(raw);
}

/// توليد تجريبي بدون ذكاء اصطناعي — لتجربة النظام قبل إعداد المفتاح.
LetterDoc demoLetter({
  required Map<String, dynamic> entity,
  required String letterType,
  required String recipient,
  required String brief,
  String greetingPref = '',
  String tone = defaultTone,
  Map<String, dynamic>? recipientInfo,
  List<Map<String, dynamic>>? references,
}) {
  var rec = recipient.trim().isEmpty ? 'الجهة المستلمة' : recipient.trim();
  if (recipientInfo != null) {
    rec = '${recipientInfo['honorific'] ?? 'الأخوة /'} $rec '
        '${recipientInfo['suffix'] ?? 'المحترمون'}';
  } else if (!rec.startsWith('الأخ') &&
      !rec.startsWith('الأست') &&
      !rec.startsWith('معالي') &&
      !rec.startsWith('سعادة')) {
    rec = 'الأخوة / $rec المحترمون';
  }
  var opening = 'بالإشارة إلى الموضوع أعلاه، نود إفادتكم بالآتي:';
  if (references != null && references.isNotEmpty) {
    final r = references.first;
    final who = r['type'] == 'outgoing' ? 'كتابنا رقم' : 'كتابكم رقم';
    final subj = ((r['subject'] ?? '') as String).replaceFirst('الموضوع: ', '');
    opening = 'بالإشارة إلى $who (${r['ref_number'] ?? '…'}) '
        'وتاريخ ${fmtIsoDate(r['date_greg'] as String?)} '
        'بشأن ${subj.isEmpty ? '…' : subj}، نود إفادتكم بالآتي:';
  }
  final greeting = greetingPref.isNotEmpty
      ? greetingPref
      : ((entity['default_greeting'] as String?)?.isNotEmpty == true
          ? entity['default_greeting'] as String
          : 'تحية طيبة وبعد،');
  return LetterDoc(
    subject: 'الموضوع: ${letterType != 'عام' ? letterType : 'إفادة'}',
    recipientLines: [rec],
    greeting: greeting,
    body: [
      ParagraphBlock(opening),
      ParagraphBlock(brief.trim().isEmpty ? '[مضمون الرسالة]' : brief.trim()),
      ParagraphBlock(
          'نرجو منكم التكرم بالاطلاع واتخاذ اللازم، ولكم جزيل الشكر.'),
    ],
    closing: (entity['default_closing'] as String?)?.isNotEmpty == true
        ? entity['default_closing'] as String
        : 'وتقبلوا خالص التحايا،،،',
  );
}
