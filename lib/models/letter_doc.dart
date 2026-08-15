/// نماذج البيانات: بنية الرسالة الرسمية (LetterDoc) وكتلها.
/// مطابقة تمامًا لبنية JSON في نسخة سطح المكتب لتوافق الأرشيف.
library;

import 'dart:convert';

sealed class Block {
  Map<String, dynamic> toJson();
}

class ParagraphBlock extends Block {
  String text;
  ParagraphBlock(this.text);

  @override
  Map<String, dynamic> toJson() => {'type': 'paragraph', 'text': text};
}

class BulletsBlock extends Block {
  List<String> items;
  BulletsBlock(this.items);

  @override
  Map<String, dynamic> toJson() => {'type': 'bullets', 'items': items};
}

class TableBlock extends Block {
  List<String> header;
  List<List<String>> rows;
  TableBlock(this.header, this.rows);

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'table', 'header': header, 'rows': rows};
}

/// المحتوى الكامل للرسالة كما يولّده الذكاء الاصطناعي ويحرّره المستخدم.
class LetterDoc {
  String subject;
  List<String> recipientLines;
  String greeting;
  List<Block> body;
  String closing;

  LetterDoc({
    this.subject = '',
    List<String>? recipientLines,
    this.greeting = 'تحية طيبة وبعد،',
    List<Block>? body,
    this.closing = 'وتقبلوا خالص التحايا،،،',
  })  : recipientLines = recipientLines ?? [],
        body = body ?? [];

  Map<String, dynamic> toJson() => {
        'subject': subject,
        'recipient_lines': recipientLines,
        'greeting': greeting,
        'body': [for (final b in body) b.toJson()],
        'closing': closing,
      };

  String toJsonString() => jsonEncode(toJson());

  /// تحويل JSON قادم من النموذج إلى LetterDoc بتحمّل كامل للبنى المعطوبة:
  /// أنواع خاطئة تُتجاهل، وقيم null لا تتحول إلى النص "null".
  static LetterDoc normalize(dynamic raw) {
    String s(dynamic v, [String def = '']) =>
        (v is String || v is num) ? v.toString().trim() : def;

    final map = raw is Map ? raw : <String, dynamic>{};
    final bodyRaw = map['body'];
    final blocks = <Block>[];
    if (bodyRaw is List) {
      for (final b in bodyRaw) {
        if (b is! Map) continue;
        final t = b['type'];
        if (t == 'paragraph' && s(b['text']).isNotEmpty) {
          blocks.add(ParagraphBlock(s(b['text'])));
        } else if (t == 'bullets' && b['items'] is List) {
          final items = [
            for (final i in b['items'] as List)
              if (s(i).isNotEmpty) s(i)
          ];
          if (items.isNotEmpty) blocks.add(BulletsBlock(items));
        } else if (t == 'table') {
          final headerRaw = b['header'];
          final rowsRaw = b['rows'];
          final header = headerRaw is List
              ? [for (final h in headerRaw) s(h)]
              : <String>[];
          final rows = <List<String>>[
            if (rowsRaw is List)
              for (final r in rowsRaw)
                if (r is List && r.isNotEmpty) [for (final c in r) s(c)]
          ];
          if (rows.isNotEmpty || header.isNotEmpty) {
            blocks.add(TableBlock(header, rows));
          }
        }
      }
    }
    var rec = map['recipient_lines'];
    if (rec is String) rec = [rec];
    final recLines = rec is List
        ? [
            for (final x in rec)
              if (s(x).isNotEmpty) s(x)
          ]
        : <String>[];
    final greeting = s(map['greeting'], 'تحية طيبة وبعد،');
    final closing = s(map['closing'], 'وتقبلوا خالص التحايا،،،');
    return LetterDoc(
      subject: s(map['subject']),
      recipientLines: recLines,
      greeting: greeting.isEmpty ? 'تحية طيبة وبعد،' : greeting,
      body: blocks,
      closing: closing.isEmpty ? 'وتقبلوا خالص التحايا،،،' : closing,
    );
  }

  static LetterDoc fromJsonString(String json) {
    try {
      return normalize(jsonDecode(json));
    } catch (_) {
      return LetterDoc();
    }
  }
}
