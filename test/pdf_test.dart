import 'package:flutter_test/flutter_test.dart';

import 'package:correspondence/models/letter_doc.dart';
import 'package:correspondence/pdf/pdf_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renderPdf يولّد ملف PDF سليمًا لرسالة تجريبية', () async {
    final doc = LetterDoc(
      subject: 'الموضوع: إفادة',
      recipientLines: ['الأخوة / الجهة المستلمة المحترمون'],
      greeting: 'تحية طيبة وبعد،',
      body: [
        ParagraphBlock('بالإشارة إلى الموضوع أعلاه، نود إفادتكم بالآتي:'),
        ParagraphBlock('[مضمون الرسالة]'),
        BulletsBlock(['بند أول', 'بند ثانٍ']),
        TableBlock(['المبلغ', 'البيان'], [
          ['1,000', 'دفعة'],
        ]),
        ParagraphBlock('نرجو منكم التكرم بالاطلاع واتخاذ اللازم.'),
      ],
      closing: 'وتقبلوا خالص التحايا،،،',
    );
    final bytes = await renderPdf(
      entity: {
        'name': 'شركة مثال للصرافة',
        'signer_title': 'المدير العام',
        'signer_name': 'محمد محمد محمد',
      },
      doc: doc,
      refNumber: '26-1',
      letterDate: DateTime(2026, 8, 15),
      useHijri: false,
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
