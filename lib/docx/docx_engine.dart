/// توليد ملف Word للرسالة: ترويسة خلفية، اتجاه RTL، جداول ونقاط.
///
/// نقل حرفي لمحرك DOCX في نسخة سطح المكتب (docx_engine.py) بكتابة OOXML
/// مباشرة: صفحة Letter‏ 8.5×11 بوصة، خط DIN Next LT Arabic (تسمية فقط —
/// يعرضه Word على الحاسوب)، متن 13pt مُبرَّر (lowKashida)، إطار موحّد
/// للتاريخ والمرجع، كتلة توقيع، ترقيم «صفحة X من Y»، والترويسة صورة
/// تملأ الصفحة خلف النص.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';

import '../models/letter_doc.dart';
import '../utils/dates.dart';

const arabicFont = 'DIN Next LT Arabic';
// خط ثلث عربي للتحية والخاتمة (نفس المستخدم في رسائل العينات الأصلية)
const greetingFont = 'DecoType Thuluth';
const greetingPt = 16.0;
const bodyPt = 13.0;
const _pageWTw = 12240, _pageHTw = 15840; // Letter بوحدة twips
const _marginsTw = (top: 1560, right: 758, bottom: 1080, left: 426);

const _nsW =
    'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
const _nsR =
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
const _nsWp =
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"';
const _nsA = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"';
const _nsPic =
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// نص run بتنسيقه: خط، حجم، عريض/مسطّر، واتجاه RTL —
/// (w:b وحده لا يجعل النص العربي عريضًا؛ يلزم w:bCs معه).
String _run(String text,
    {double pt = bodyPt,
    bool bold = false,
    bool underline = false,
    String font = arabicFont}) {
  final sz = (pt * 2).round();
  return '<w:r><w:rPr>'
      '<w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="$font"/>'
      '${bold ? '<w:b/><w:bCs/>' : ''}'
      '<w:sz w:val="$sz"/><w:szCs w:val="$sz"/>'
      '${underline ? '<w:u w:val="single"/>' : ''}'
      '<w:rtl/>'
      '</w:rPr><w:t xml:space="preserve">${_esc(text)}</w:t></w:r>';
}

/// خصائص فقرة RTL: محاذاة وتباعد (تباعد مفرد كما في رسائل العينات).
String _pPr(
    {String? jc,
    int afterPt = 6,
    bool keepNext = false,
    int? rightIndentTw}) {
  return '<w:pPr>'
      '${keepNext ? '<w:keepNext/>' : ''}'
      '<w:bidi/>'
      '<w:spacing w:before="0" w:after="${afterPt * 20}" w:line="240" w:lineRule="auto"/>'
      '${rightIndentTw != null ? '<w:ind w:right="$rightIndentTw"/>' : ''}'
      '${jc != null ? '<w:jc w:val="$jc"/>' : ''}'
      '</w:pPr>';
}

String _p(String runs,
        {String? jc,
        int afterPt = 6,
        bool keepNext = false,
        int? rightIndentTw}) =>
    '<w:p>${_pPr(jc: jc, afterPt: afterPt, keepNext: keepNext, rightIndentTw: rightIndentTw)}$runs</w:p>';

/// حقل Word تلقائي (PAGE/NUMPAGES) بتنسيق مطابق.
String _field(String instr, {double pt = 9}) {
  final sz = (pt * 2).round();
  return '<w:fldSimple w:instr=" $instr ">'
      '<w:r><w:rPr>'
      '<w:rFonts w:ascii="$arabicFont" w:hAnsi="$arabicFont" w:cs="$arabicFont"/>'
      '<w:b/><w:bCs/><w:sz w:val="$sz"/><w:szCs w:val="$sz"/><w:rtl/>'
      '</w:rPr><w:t>1</w:t></w:r></w:fldSimple>';
}

String _boxBorders() =>
    '<w:tcBorders>${['top', 'start', 'bottom', 'end'].map((s) => '<w:$s w:val="single" w:sz="4" w:space="0" w:color="BFBFBF"/>').join()}</w:tcBorders>';

/// جدول أحادي الخلية بإطار رمادي خفيف محاذٍ ليسار الصفحة (نهاية سطر RTL)
/// وبعرض تلقائي بحسب المحتوى — لإطار التاريخ/المرجع وإطار التوقيع.
String _lightBoxedTable(String paragraphs) {
  return '<w:tbl><w:tblPr>'
      '<w:bidiVisual/>'
      '<w:tblW w:w="0" w:type="auto"/>'
      '<w:jc w:val="end"/>'
      '</w:tblPr>'
      '<w:tblGrid><w:gridCol w:w="3000"/></w:tblGrid>'
      '<w:tr><w:tc><w:tcPr>'
      '<w:tcW w:w="0" w:type="auto"/>'
      '${_boxBorders()}'
      '<w:tcMar>'
      '<w:top w:w="80" w:type="dxa"/><w:bottom w:w="120" w:type="dxa"/>'
      '<w:start w:w="150" w:type="dxa"/><w:end w:w="150" w:type="dxa"/>'
      '</w:tcMar>'
      '</w:tcPr>$paragraphs</w:tc></w:tr></w:tbl>';
}

/// إطار خفيف أعلى يسار الصفحة يجمع التاريخ والمرجع في سطر واحد.
String _metaBox(String refNumber, DateTime letterDate, bool useHijri) {
  final h = useHijri ? hijriString(letterDate) : '';
  final dateTxt = h.isNotEmpty
      ? 'التاريخ: $h الموافق ${gregorianString(letterDate)}'
      : 'التاريخ: ${gregorianString(letterDate)}';
  var runs = _run(dateTxt, pt: 12, bold: true);
  if (refNumber.isNotEmpty) {
    runs += _run('  ', pt: 12);
    runs += _run('المرجع: $refNumber', pt: 12, bold: true);
  }
  return _lightBoxedTable(_p(runs, afterPt: 0));
}

/// يفصل صيغة الاحترام الختامية (المحترمون/المحترم/المحترمة، ولو بتطويل)
/// عن بقية سطر المستلم.
(String, String) _splitHonorific(String line) {
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

/// سطور المستلم: الاسم يمينًا وصيغة الاحترام مدفوعة لأقصى يسار السطر
/// (عبر جدول خفي بلا حدود — سلوك ثابت في Word وLibreOffice).
String _recipientTable(List<String> lines) {
  const textW = _pageWTw - 758 - 426;
  const suffixW = 2200;
  const nameW = textW - suffixW;
  final rows = StringBuffer();
  for (final line in lines) {
    final (name, suffix) = _splitHonorific(line);
    rows.write('<w:tr>'
        '<w:tc><w:tcPr><w:tcW w:w="$nameW" w:type="dxa"/></w:tcPr>'
        '${_p(_run(name, pt: 14, bold: true), afterPt: 2)}</w:tc>'
        '<w:tc><w:tcPr><w:tcW w:w="$suffixW" w:type="dxa"/></w:tcPr>'
        '${_p(suffix.isEmpty ? '' : _run(suffix, pt: 14, bold: true), jc: 'end', afterPt: 2)}</w:tc>'
        '</w:tr>');
  }
  return '<w:tbl><w:tblPr>'
      '<w:bidiVisual/>'
      '<w:tblW w:w="$textW" w:type="dxa"/>'
      '<w:tblLayout w:type="fixed"/>'
      '</w:tblPr>'
      '<w:tblGrid><w:gridCol w:w="$nameW"/><w:gridCol w:w="$suffixW"/></w:tblGrid>'
      '$rows</w:tbl>';
}

/// جدول بيانات من كتلة table: حدود كاملة، رأس مظلّل عريض وسط الخلية.
String _dataTable(TableBlock block) {
  var cols = block.header.length;
  for (final r in block.rows) {
    if (r.length > cols) cols = r.length;
  }
  if (cols == 0) cols = 1;
  const totalW = _pageWTw - 758 - 426;
  final colW = totalW ~/ cols;

  String cell(String text, {bool isHeader = false}) => '<w:tc><w:tcPr>'
      '<w:tcW w:w="$colW" w:type="dxa"/>'
      '${isHeader ? '<w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>' : ''}'
      '</w:tcPr>'
      '${_p(_run(text, pt: bodyPt - 1, bold: isHeader), jc: isHeader ? 'center' : null, afterPt: 2)}'
      '</w:tc>';

  String row(List<String> data, {bool isHeader = false}) =>
      '<w:tr>${List.generate(cols, (c) => cell(c < data.length ? data[c] : '', isHeader: isHeader)).join()}</w:tr>';

  final borders =
      '<w:tblBorders>${['top', 'start', 'bottom', 'end', 'insideH', 'insideV'].map((s) => '<w:$s w:val="single" w:sz="4" w:space="0" w:color="auto"/>').join()}</w:tblBorders>';

  return '<w:tbl><w:tblPr>'
      '<w:bidiVisual/>'
      '<w:tblW w:w="$totalW" w:type="dxa"/>'
      '<w:jc w:val="center"/>'
      '$borders'
      '<w:tblLayout w:type="fixed"/>'
      '</w:tblPr>'
      '<w:tblGrid>${List.filled(cols, '<w:gridCol w:w="$colW"/>').join()}</w:tblGrid>'
      '${block.header.isNotEmpty ? row(block.header, isHeader: true) : ''}'
      '${block.rows.map(row).join()}'
      '</w:tbl>';
}

/// كتلة توقيع المنشأة داخل إطار خفيف: الإطار يسار الصفحة والنص داخله يمينًا.
String _signatureBox(Map<String, dynamic> entity) {
  final ps = StringBuffer(_p(
      _run((entity['name'] ?? '') as String,
          pt: 14, bold: true, underline: true),
      afterPt: 2));
  final signer = [entity['signer_title'], entity['signer_name']]
      .where((x) => x is String && x.isNotEmpty)
      .join(' / ');
  if (signer.isNotEmpty) {
    ps.write(_p(_run(signer, pt: bodyPt, bold: true), afterPt: 2));
  }
  return _lightBoxedTable(ps.toString());
}

/// فقرة الإنهاء بعد الجدول الختامي — بارتفاع شبه معدوم كي لا تحجز سطرًا.
String _terminator() => '<w:p><w:pPr>'
    '<w:spacing w:before="0" w:after="0" w:line="40" w:lineRule="exact"/>'
    '<w:rPr><w:sz w:val="4"/><w:szCs w:val="4"/></w:rPr>'
    '</w:pPr></w:p>';

/// ترويسة خلف النص تملأ الصفحة (مع الحفاظ على النسبة) — نفس anchor سطح المكتب.
String _headerXml(int cx, int cy) => '<?xml version="1.0" encoding="UTF-8" '
    'standalone="yes"?>\n<w:hdr $_nsW $_nsR $_nsWp $_nsA $_nsPic>'
    '<w:p><w:pPr><w:spacing w:before="0" w:after="0"/></w:pPr>'
    '<w:r><w:drawing>'
    '<wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" '
    'relativeHeight="0" behindDoc="1" locked="0" layoutInCell="1" allowOverlap="1">'
    '<wp:simplePos x="0" y="0"/>'
    '<wp:positionH relativeFrom="page"><wp:align>center</wp:align></wp:positionH>'
    '<wp:positionV relativeFrom="page"><wp:align>center</wp:align></wp:positionV>'
    '<wp:extent cx="$cx" cy="$cy"/>'
    '<wp:effectExtent l="0" t="0" r="0" b="0"/>'
    '<wp:wrapNone/>'
    '<wp:docPr id="101" name="Letterhead"/>'
    '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
    '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    '<pic:pic>'
    '<pic:nvPicPr><pic:cNvPr id="101" name="Letterhead"/><pic:cNvPicPr/></pic:nvPicPr>'
    '<pic:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
    '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
    '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
    '</pic:pic>'
    '</a:graphicData></a:graphic>'
    '</wp:anchor>'
    '</w:drawing></w:r></w:p></w:hdr>';

/// ترقيم «صفحة X من Y» وسط منطقة التذييل.
String _footerXml() => '<?xml version="1.0" encoding="UTF-8" '
    'standalone="yes"?>\n<w:ftr $_nsW $_nsR>'
    '<w:p>${_pPr(jc: 'center', afterPt: 0)}'
    '${_run('صفحة ', pt: 9, bold: true)}${_field('PAGE')}'
    '${_run(' من ', pt: 9, bold: true)}${_field('NUMPAGES')}'
    '</w:p></w:ftr>';

String _documentXml(Map<String, dynamic> entity, LetterDoc doc,
    String refNumber, DateTime letterDate, bool useHijri, bool hasLetterhead) {
  final body = StringBuffer();

  // التاريخ والمرجع في سطر واحد داخل إطار خفيف أعلى يسار الصفحة
  body.write(_metaBox(refNumber, letterDate, useHijri));
  body.write(_p('', afterPt: 3)); // فاصل بعد إطار البيانات

  if (doc.recipientLines.isNotEmpty) {
    body.write(_recipientTable(doc.recipientLines));
  }
  if (doc.greeting.isNotEmpty) {
    body.write(_p(
        _run(doc.greeting, pt: greetingPt, bold: true, font: greetingFont),
        afterPt: 4));
  }
  if (doc.subject.isNotEmpty) {
    body.write(_p(_run(doc.subject, pt: bodyPt, bold: true, underline: true),
        jc: 'center', afterPt: 8));
  }

  // المتن — الكتلة الأخيرة تبقى مع كتلة التوقيع (keepNext) فلا ينفرد
  // الإطار وحده بصفحة في الرسائل الطويلة
  for (var i = 0; i < doc.body.length; i++) {
    final block = doc.body[i];
    final isLast = i == doc.body.length - 1;
    switch (block) {
      case ParagraphBlock():
        body.write(_p(_run(block.text),
            jc: 'lowKashida', afterPt: 4, keepNext: isLast));
      case BulletsBlock():
        for (var j = 0; j < block.items.length; j++) {
          body.write(_p(_run('•  ${block.items[j]}'),
              afterPt: 2,
              rightIndentTw: 340,
              keepNext: isLast && j == block.items.length - 1));
        }
      case TableBlock():
        body.write(_dataTable(block));
        body.write(_p('', afterPt: 2, keepNext: isLast));
    }
  }

  body.write(_p('', afterPt: 2)); // فاصل قبل الخاتمة

  if (doc.closing.isNotEmpty) {
    body.write(_p(
        _run(doc.closing, pt: greetingPt, bold: true, font: greetingFont),
        jc: 'center',
        afterPt: 6,
        keepNext: true));
  }

  body.write(_signatureBox(entity));
  body.write(_terminator());

  final headerRef =
      hasLetterhead ? '<w:headerReference w:type="default" r:id="rId3"/>' : '';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<w:document $_nsW $_nsR $_nsWp $_nsA $_nsPic>'
      '<w:body>$body'
      '<w:sectPr>'
      '$headerRef'
      '<w:footerReference w:type="default" r:id="rId4"/>'
      '<w:pgSz w:w="$_pageWTw" w:h="$_pageHTw"/>'
      '<w:pgMar w:top="${_marginsTw.top}" w:right="${_marginsTw.right}" '
      'w:bottom="${_marginsTw.bottom}" w:left="${_marginsTw.left}" '
      'w:header="720" w:footer="1200" w:gutter="0"/>'
      '</w:sectPr>'
      '</w:body></w:document>';
}

String _stylesXml() => '<?xml version="1.0" encoding="UTF-8" '
    'standalone="yes"?>\n<w:styles $_nsW>'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
    '<w:name w:val="Normal"/><w:qFormat/></w:style></w:styles>';

// مطالبة Word بتحديث الحقول (عدد الصفحات) عند فتح الملف
String _settingsXml() => '<?xml version="1.0" encoding="UTF-8" '
    'standalone="yes"?>\n<w:settings $_nsW>'
    '<w:updateFields w:val="true"/></w:settings>';

String _contentTypesXml(String? imageExt) {
  final img = switch (imageExt) {
    'png' => '<Default Extension="png" ContentType="image/png"/>',
    'jpg' ||
    'jpeg' =>
      '<Default Extension="$imageExt" ContentType="image/jpeg"/>',
    _ => '',
  };
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '$img'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
      '${imageExt != null ? '<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>' : ''}'
      '<Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
      '</Types>';
}

const _relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>';

String _documentRelsXml(bool hasLetterhead) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>'
    '${hasLetterhead ? '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/>' : ''}'
    '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>'
    '</Relationships>';

String _headerRelsXml(String imageExt) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.$imageExt"/>'
    '</Relationships>';

/// أبعاد الترويسة داخل الصفحة بوحدة EMU (ملء الصفحة مع الحفاظ على النسبة).
Future<(int, int)> _letterheadEmu(Uint8List imageBytes) async {
  final codec = await ui.instantiateImageCodec(imageBytes);
  final frame = await codec.getNextFrame();
  final iw = frame.image.width, ih = frame.image.height;
  frame.image.dispose();
  codec.dispose();
  const pageWEmu = 7772400; // 8.5in
  const pageHEmu = 10058400; // 11in
  final scale =
      [pageWEmu / iw, pageHEmu / ih].reduce((a, b) => a < b ? a : b);
  return ((iw * scale).round(), (ih * scale).round());
}

/// توليد ملف الرسالة النهائي بصيغة DOCX — يعيد البايتات جاهزة للحفظ.
Future<Uint8List> renderDocx({
  required Map<String, dynamic> entity,
  required LetterDoc doc,
  required String refNumber,
  required DateTime letterDate,
  required bool useHijri,
  Uint8List? letterheadBytes,
  String letterheadExt = 'png',
}) async {
  final hasLetterhead = letterheadBytes != null;
  final ext = letterheadExt.toLowerCase() == 'jpeg'
      ? 'jpeg'
      : (letterheadExt.toLowerCase() == 'jpg' ? 'jpg' : 'png');

  final archive = Archive();
  // النصوص عربية — ترميز UTF-8 صريح
  void addText(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addText('[Content_Types].xml', _contentTypesXml(hasLetterhead ? ext : null));
  addText('_rels/.rels', _relsXml);
  addText(
      'word/document.xml',
      _documentXml(
          entity, doc, refNumber, letterDate, useHijri, hasLetterhead));
  addText('word/_rels/document.xml.rels', _documentRelsXml(hasLetterhead));
  addText('word/styles.xml', _stylesXml());
  addText('word/settings.xml', _settingsXml());
  addText('word/footer1.xml', _footerXml());

  if (hasLetterhead) {
    final (cx, cy) = await _letterheadEmu(letterheadBytes);
    addText('word/header1.xml', _headerXml(cx, cy));
    addText('word/_rels/header1.xml.rels', _headerRelsXml(ext));
    archive.addFile(ArchiveFile(
        'word/media/image1.$ext', letterheadBytes.length, letterheadBytes));
  }

  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
