/// توليد PDF للرسالة: ترويسة خلفية، اتجاه RTL، جداول ونقاط.
///
/// المواصفات منقولة عن محرك DOCX في نسخة سطح المكتب: صفحة Letter‏ 8.5×11 بوصة،
/// متن 13pt مُبرَّر، إطار خفيف للتاريخ/المرجع أعلى يسار الصفحة، كتلة توقيع
/// بإطار مثله، والترويسة صورة تملأ الصفحة خلف النص، مع ترقيم «صفحة X من Y».
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/letter_doc.dart';
import '../utils/dates.dart';

// الهوامش بالنقاط — محوّلة من قيم twips في محرك DOCX (تقسيم على 20)
const _marginTop = 78.0;
const _marginRight = 37.9;
const _marginBottom = 54.0;
const _marginLeft = 21.3;
const _bodyPt = 13.0;
const _greetingPt = 16.0;

final _borderGrey = PdfColor.fromInt(0xFFBFBFBF);
final _headerFill = PdfColor.fromInt(0xFFF2F2F2);

class PdfFonts {
  final pw.Font base;
  final pw.Font bold;

  /// خط النسخ التقليدي (أميري) للتحية والخاتمة — بديل DecoType Thuluth.
  /// ملاحظة: خط Aref Ruqaa كان يفجّر علة في مقلّص الخطوط بمكتبة pdf
  /// («Bad state: No element» مع كلمات مثل «تقبلوا») فاستُبدل بأميري.
  final pw.Font calligraphy;
  PdfFonts(this.base, this.bold, this.calligraphy);

  static PdfFonts? _cached;

  static Future<PdfFonts> load() async {
    if (_cached != null) return _cached!;
    final base = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'));
    final bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'));
    final calligraphy =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Bold.ttf'));
    return _cached = PdfFonts(base, bold, calligraphy);
  }
}

/// يفصل صيغة الاحترام الختامية (المحترمون/المحترم/المحترمة، ولو بتطويل)
/// عن بقية سطر المستلم.
(String, String) splitHonorific(String line) {
  final idx = line.trimRight().lastIndexOf(RegExp(r'\s'));
  if (idx > 0) {
    final name = line.substring(0, idx).trimRight();
    final last = line.substring(idx).trim();
    if (RegExp(r'^المح[ـ]*ت[ـ]*رم(ون|ة)?$').hasMatch(last)) {
      return (name, last);
    }
  }
  return (line, '');
}

/// جدول أحادي الخلية بإطار رمادي خفيف — لإطار التاريخ/المرجع وإطار التوقيع.
pw.Widget _lightBox(pw.Widget child) => pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _borderGrey, width: 0.5),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 7.5, vertical: 4),
      child: child,
    );

pw.Widget _metaBox(PdfFonts fonts, String refNumber, DateTime letterDate,
    bool useHijri) {
  final h = useHijri ? hijriString(letterDate) : '';
  final dateTxt = h.isNotEmpty
      ? 'التاريخ: $h الموافق ${gregorianString(letterDate)}'
      : 'التاريخ: ${gregorianString(letterDate)}';
  final style = pw.TextStyle(font: fonts.bold, fontSize: 12);
  return pw.Align(
    alignment: pw.Alignment.centerLeft,
    child: _lightBox(pw.Text(
      refNumber.isNotEmpty ? '$dateTxt   المرجع: $refNumber' : dateTxt,
      style: style,
      textDirection: pw.TextDirection.rtl,
    )),
  );
}

pw.Widget _recipientLine(PdfFonts fonts, String line) {
  final (name, suffix) = splitHonorific(line);
  final style = pw.TextStyle(font: fonts.bold, fontSize: 14);
  if (suffix.isEmpty) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Text(line, style: style, textDirection: pw.TextDirection.rtl),
    );
  }
  // الاسم يمينًا وصيغة الاحترام مدفوعة لأقصى يسار السطر
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Row(
      children: [
        pw.Expanded(
          child:
              pw.Text(name, style: style, textDirection: pw.TextDirection.rtl),
        ),
        pw.Text(suffix, style: style, textDirection: pw.TextDirection.rtl),
      ],
    ),
  );
}

pw.Widget _table(PdfFonts fonts, TableBlock block) {
  final cols = [
    block.header.length,
    for (final r in block.rows) r.length,
  ].fold(1, (a, b) => a > b ? a : b);

  pw.Widget cell(String text, {bool isHeader = false}) => pw.Container(
        color: isHeader ? _headerFill : null,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        alignment: isHeader ? pw.Alignment.center : pw.Alignment.centerRight,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            font: isHeader ? fonts.bold : fonts.base,
            fontSize: _bodyPt - 1,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
      );

  List<pw.Widget> cellsOf(List<String> row, {bool isHeader = false}) => [
        for (var c = 0; c < cols; c++)
          cell(c < row.length ? row[c] : '', isHeader: isHeader)
      ];

  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Table(
      border: pw.TableBorder.all(color: _borderGrey, width: 0.5),
      children: [
        if (block.header.isNotEmpty)
          pw.TableRow(children: cellsOf(block.header, isHeader: true)),
        for (final row in block.rows) pw.TableRow(children: cellsOf(row)),
      ],
    ),
  );
}

pw.Widget _signatureBox(PdfFonts fonts, Map<String, dynamic> entity) {
  final signer = [
    entity['signer_title'],
    entity['signer_name'],
  ].where((x) => x is String && x.isNotEmpty).join(' / ');
  return pw.Align(
    alignment: pw.Alignment.centerLeft,
    child: _lightBox(pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          (entity['name'] ?? '') as String,
          style: pw.TextStyle(
            font: fonts.bold,
            fontSize: 14,
            decoration: pw.TextDecoration.underline,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
        if (signer.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(
              signer,
              style: pw.TextStyle(font: fonts.bold, fontSize: _bodyPt),
              textDirection: pw.TextDirection.rtl,
            ),
          ),
      ],
    )),
  );
}

/// توليد ملف الرسالة النهائي بصيغة PDF — يعيد البايتات جاهزة للحفظ أو المشاركة.
Future<Uint8List> renderPdf({
  required Map<String, dynamic> entity,
  required LetterDoc doc,
  required String refNumber,
  required DateTime letterDate,
  required bool useHijri,
  String? letterheadPath,
}) async {
  final fonts = await PdfFonts.load();

  pw.MemoryImage? letterhead;
  if (letterheadPath != null && letterheadPath.isNotEmpty) {
    final f = File(letterheadPath);
    if (await f.exists()) {
      letterhead = pw.MemoryImage(await f.readAsBytes());
    }
  }

  final bodyStyle = pw.TextStyle(font: fonts.base, fontSize: _bodyPt);

  final content = <pw.Widget>[
    _metaBox(fonts, refNumber, letterDate, useHijri),
    pw.SizedBox(height: 10),
    for (final line in doc.recipientLines) _recipientLine(fonts, line),
    if (doc.greeting.isNotEmpty)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
        child: pw.Text(
          doc.greeting,
          style: pw.TextStyle(font: fonts.calligraphy, fontSize: _greetingPt),
          textDirection: pw.TextDirection.rtl,
        ),
      ),
    if (doc.subject.isNotEmpty)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2, bottom: 8),
        child: pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            doc.subject,
            style: pw.TextStyle(
              font: fonts.bold,
              fontSize: _bodyPt,
              decoration: pw.TextDecoration.underline,
            ),
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
          ),
        ),
      ),
    for (final block in doc.body)
      switch (block) {
        ParagraphBlock() => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(
              block.text,
              style: bodyStyle,
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.justify,
            ),
          ),
        BulletsBlock() => pw.Padding(
            padding: const pw.EdgeInsets.only(right: 17, bottom: 2),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final item in block.items)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 2),
                    child: pw.Text(
                      '•  $item',
                      style: bodyStyle,
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
              ],
            ),
          ),
        TableBlock() => _table(fonts, block),
      },
    pw.SizedBox(height: 8),
    if (doc.closing.isNotEmpty)
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            doc.closing,
            style: pw.TextStyle(font: fonts.calligraphy, fontSize: _greetingPt),
            textDirection: pw.TextDirection.rtl,
          ),
        ),
      ),
    _signatureBox(fonts, entity),
  ];

  final document = pw.Document();
  document.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.letter.copyWith(
        marginTop: _marginTop,
        marginRight: _marginRight,
        marginBottom: _marginBottom,
        marginLeft: _marginLeft,
      ),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
      buildBackground: letterhead == null
          ? null
          : (context) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Image(letterhead!, fit: pw.BoxFit.contain),
              ),
    ),
    footer: (context) => pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 6),
      child: pw.Text(
        'صفحة ${context.pageNumber} من ${context.pagesCount}',
        style: pw.TextStyle(font: fonts.bold, fontSize: 9),
        textDirection: pw.TextDirection.rtl,
      ),
    ),
    build: (context) => content,
  ));
  return document.save();
}
