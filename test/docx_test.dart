import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:correspondence/docx/docx_engine.dart';
import 'package:correspondence/models/letter_doc.dart';

void main() {
  group('renderDocx', () {
    test('يولّد حزمة OOXML سليمة البنية بمحتوى الرسالة', () async {
      final doc = LetterDoc(
        subject: 'الموضوع: إشعار تحويل',
        recipientLines: ['الأخوة / بنك الاختبار المحترمون'],
        greeting: 'تحية طيبة وبعد،',
        body: [
          ParagraphBlock('بالإشارة إلى الموضوع أعلاه، نود إفادتكم بالآتي.'),
          BulletsBlock(['البند الأول', 'البند الثاني']),
          TableBlock([
            'المبلغ', 'البيان'
          ], [
            ['1,000 ريال', 'دفعة أولى'],
            ['2,000 ريال', 'دفعة ثانية'],
          ]),
        ],
        closing: 'وتقبلوا خالص التحايا،،،',
      );
      final bytes = await renderDocx(
        entity: {
          'name': 'شركة مثال للصرافة',
          'signer_title': 'المدير العام',
          'signer_name': 'محمد محمد',
        },
        doc: doc,
        refNumber: '26-117',
        letterDate: DateTime(2026, 8, 15),
        useHijri: false,
      );

      // توقيع ZIP
      expect(bytes[0], 0x50); // P
      expect(bytes[1], 0x4B); // K

      final archive = ZipDecoder().decodeBytes(bytes);
      final names = {for (final f in archive.files) f.name};
      expect(
          names,
          containsAll([
            '[Content_Types].xml',
            '_rels/.rels',
            'word/document.xml',
            'word/_rels/document.xml.rels',
            'word/styles.xml',
            'word/settings.xml',
            'word/footer1.xml',
          ]));
      // بلا ترويسة: لا يوجد header1.xml
      expect(names.contains('word/header1.xml'), isFalse);

      final docXml = utf8.decode(
          archive.files.firstWhere((f) => f.name == 'word/document.xml')
              .content as List<int>);
      expect(docXml, contains('الموضوع: إشعار تحويل'));
      expect(docXml, contains('المرجع: 26-117'));
      expect(docXml, contains('التاريخ: 15/08/2026 م'));
      expect(docXml, contains('<w:bidi/>')); // فقرات RTL
      expect(docXml, contains('w:val="lowKashida"')); // تبرير المتن
      expect(docXml, contains('DIN Next LT Arabic'));
      expect(docXml, contains('DecoType Thuluth')); // التحية والخاتمة
      expect(docXml, contains('F2F2F2')); // تظليل رأس الجدول
      expect(docXml, contains('<w:bidiVisual/>')); // جداول RTL
      expect(docXml, contains('شركة مثال للصرافة'));
      expect(docXml, contains('المدير العام / محمد محمد'));

      final footer = utf8.decode(
          archive.files.firstWhere((f) => f.name == 'word/footer1.xml')
              .content as List<int>);
      expect(footer, contains('PAGE'));
      expect(footer, contains('NUMPAGES'));
      expect(footer, contains('صفحة'));

      final settings = utf8.decode(
          archive.files.firstWhere((f) => f.name == 'word/settings.xml')
              .content as List<int>);
      expect(settings, contains('updateFields'));
    });

    test('سطر مستلم بصيغة احترام يُفصل في جدول من عمودين', () async {
      final bytes = await renderDocx(
        entity: {'name': 'م'},
        doc: LetterDoc(
            recipientLines: ['الأخوة / منظمة الإغاثة المحترمون'],
            body: [ParagraphBlock('نص')]),
        refNumber: '',
        letterDate: DateTime(2026, 1, 1),
        useHijri: false,
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final docXml = utf8.decode(
          archive.files.firstWhere((f) => f.name == 'word/document.xml')
              .content as List<int>);
      expect(docXml, contains('الأخوة / منظمة الإغاثة'));
      expect(docXml, contains('>المحترمون<'));
      expect(docXml, contains('w:val="end"')); // دفع الصيغة لآخر السطر
    });
  });
}
