import 'package:flutter_test/flutter_test.dart';

import 'package:correspondence/models/letter_doc.dart';
import 'package:correspondence/pdf/pdf_engine.dart';

void main() {
  group('LetterDoc.normalize', () {
    test('يطبّع بنية سليمة كاملة', () {
      final doc = LetterDoc.normalize({
        'subject': 'الموضوع: اختبار',
        'recipient_lines': ['الأخوة / بنك الاختبار المحترمون'],
        'greeting': 'تحية طيبة وبعد،',
        'body': [
          {'type': 'paragraph', 'text': 'فقرة أولى.'},
          {
            'type': 'bullets',
            'items': ['بند 1', 'بند 2']
          },
          {
            'type': 'table',
            'header': ['المبلغ', 'البيان'],
            'rows': [
              ['1000', 'دفعة أولى']
            ]
          },
        ],
        'closing': 'وتقبلوا خالص التحايا،،،',
      });
      expect(doc.subject, 'الموضوع: اختبار');
      expect(doc.recipientLines, hasLength(1));
      expect(doc.body, hasLength(3));
      expect(doc.body[0], isA<ParagraphBlock>());
      expect(doc.body[1], isA<BulletsBlock>());
      expect(doc.body[2], isA<TableBlock>());
    });

    test('يتجاهل الكتل المعطوبة وقيم null', () {
      final doc = LetterDoc.normalize({
        'subject': null,
        'recipient_lines': 'سطر واحد نصًا',
        'body': [
          {'type': 'paragraph', 'text': ''},
          {'type': 'paragraph', 'text': 'سليمة'},
          {'type': 'bullets', 'items': null},
          'نص خام',
          {'type': 'غير معروف'},
        ],
      });
      expect(doc.subject, '');
      expect(doc.recipientLines, ['سطر واحد نصًا']);
      expect(doc.body, hasLength(1));
      expect((doc.body.first as ParagraphBlock).text, 'سليمة');
      expect(doc.greeting, 'تحية طيبة وبعد،');
      expect(doc.closing, 'وتقبلوا خالص التحايا،،،');
    });

    test('التحويل ذهابًا وإيابًا يحفظ البنية', () {
      final doc = LetterDoc(
        subject: 'الموضوع: تجربة',
        recipientLines: ['الأخ / فلان المحتـرم'],
        body: [ParagraphBlock('نص')],
      );
      final round = LetterDoc.fromJsonString(doc.toJsonString());
      expect(round.subject, doc.subject);
      expect(round.recipientLines, doc.recipientLines);
      expect(round.body, hasLength(1));
    });
  });

  group('splitHonorific', () {
    test('يفصل صيغة الاحترام عن الاسم', () {
      final (name, suffix) =
          splitHonorific('الأخوة / بنك الاختبار المحترمون');
      expect(name, 'الأخوة / بنك الاختبار');
      expect(suffix, 'المحترمون');
    });

    test('يتعامل مع التطويل في «المحتـرم»', () {
      final (name, suffix) = splitHonorific('الأخ / فلان المحتـرم');
      expect(name, 'الأخ / فلان');
      expect(suffix, 'المحتـرم');
    });

    test('سطر بلا صيغة احترام يعود كما هو', () {
      final (name, suffix) = splitHonorific('معالي وزير المالية');
      expect(name, 'معالي وزير المالية');
      expect(suffix, '');
    });
  });
}
