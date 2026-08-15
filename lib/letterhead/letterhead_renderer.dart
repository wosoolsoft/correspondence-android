/// محرك رسم الترويسة: يرسم صفحة Letter كاملة (8.5×11 بوصة بدقة 300DPI
/// = 2550×3300) — منقول عن مصمم الترويسة في نسخة سطح المكتب بقوالبه
/// الثلاثة (كلاسيكي / شريط ملوّن / بسيط أنيق) وإحداثياته نفسها.
/// المناطق الآمنة مأخوذة من هوامش محرك DOCX: العلوي ≈325px والسفلي ≈225px.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const lhW = 2550.0, lhH = 3300.0, lhMx = 150.0;

const lhColors = [
  Color(0xFF14532D), Color(0xFF1E3A5F), Color(0xFF7C2D12),
  Color(0xFF0F766E), Color(0xFF4C1D95), Color(0xFF374151),
  Color(0xFFB45309), Color(0xFF831843), Color(0xFF1D4ED8),
  Color(0xFF365314), Color(0xFF0E7490), Color(0xFF7F1D1D),
];

const lhTemplates = [
  (id: 'classic', label: '🏛 كلاسيكي'),
  (id: 'band', label: '🎨 شريط ملوّن'),
  (id: 'minimal', label: '◇ بسيط أنيق'),
];

// عزل اتجاهي (LRI…PDI) حول الأرقام كي لا يقلب bidi ترتيب المقاطع
// المفصولة بشرطات مثل «01-234567» في السياق العربي
const _lri = '\u2066', _pdi = '\u2069';

class LetterheadDesign {
  String template;
  Color color;
  String name;
  String nameEn;
  String address;
  String phone;
  String email;
  String website;
  ui.Image? logo;

  LetterheadDesign({
    this.template = 'classic',
    this.color = const Color(0xFF14532D),
    this.name = '',
    this.nameEn = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.website = '',
    this.logo,
  });
}

Color _shade(Color c, double f) {
  int ch(double x) => (x * f).round().clamp(0, 255);
  return Color.fromARGB(
      255, ch(c.r * 255), ch(c.g * 255), ch(c.b * 255));
}

String colorToHex(Color c) {
  String h(double v) =>
      (v * 255).round().toRadixString(16).padLeft(2, '0');
  return '#${h(c.r)}${h(c.g)}${h(c.b)}';
}

Color? colorFromHex(String? hex) {
  if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

TextPainter _tp(String text, double size, Color color,
    {FontWeight weight = FontWeight.w700,
    TextDirection dir = TextDirection.rtl}) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'PlexArabic',
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.0,
      ),
    ),
    textDirection: dir,
    maxLines: 1,
  )..layout();
}

/// تصغير حجم الخط حتى يتسع النص في العرض المتاح.
double _fitFont(String text, double size, double maxW,
    {FontWeight weight = FontWeight.w700,
    TextDirection dir = TextDirection.rtl}) {
  for (; size > 20; size -= 2) {
    if (_tp(text, size, Colors.black, weight: weight, dir: dir).width <=
        maxW) {
      break;
    }
  }
  return size;
}

enum _Align { right, left, center }

/// رسم نص بمحاذاة أفقية معينة والوسط الرأسي عند y (كما textBaseline=middle).
void _drawText(Canvas c, String text, double size, Color color, double x,
    double y,
    {FontWeight weight = FontWeight.w700,
    TextDirection dir = TextDirection.rtl,
    _Align align = _Align.right}) {
  final tp = _tp(text, size, color, weight: weight, dir: dir);
  final dx = switch (align) {
    _Align.right => x - tp.width,
    _Align.left => x,
    _Align.center => x - tp.width / 2,
  };
  tp.paint(c, Offset(dx, y - tp.height / 2));
}

/// رسم الشعار داخل صندوق مع الحفاظ على نسبته.
void _drawLogo(
    Canvas c, ui.Image img, double cx, double cy, double maxW, double maxH) {
  final s = [maxW / img.width, maxH / img.height, 1.5]
      .reduce((a, b) => a < b ? a : b);
  final w = img.width * s, h = img.height * s;
  c.drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    Rect.fromLTWH(cx - w / 2, cy - h / 2, w, h),
    Paint()..filterQuality = FilterQuality.high,
  );
}

void _rect(Canvas c, double x, double y, double w, double h, Color color) =>
    c.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = color);

/// سطور بيانات التواصل: سطر العنوان ثم سطر الهاتف/البريد/الموقع.
List<String> _contactLines(LetterheadDesign d) {
  final l2 = <String>[
    if (d.phone.isNotEmpty) 'هاتف: $_lri${d.phone}$_pdi',
    if (d.email.isNotEmpty) d.email,
    if (d.website.isNotEmpty) d.website,
  ];
  return [
    if (d.address.isNotEmpty) d.address,
    if (l2.isNotEmpty) l2.join('   •   '),
  ];
}

void _drawContact(
    Canvas c, LetterheadDesign d, Color color, double y1, double y2) {
  final lines = _contactLines(d);
  if (lines.isEmpty) return;
  final ys = lines.length == 1 ? [(y1 + y2) / 2] : [y1, y2];
  for (var i = 0; i < lines.length; i++) {
    final size = _fitFont(lines[i], 42, lhW - 2 * lhMx,
        weight: FontWeight.w600);
    _drawText(c, lines[i], size, color, lhW / 2, ys[i],
        weight: FontWeight.w600, align: _Align.center);
  }
}

/// «كلاسيكي»: الاسم العربي يمينًا والإنجليزي يسارًا والشعار وسطًا، بخط مزدوج.
void _drawClassic(Canvas c, LetterheadDesign d) {
  final colW = (lhW - 2 * lhMx - (d.logo != null ? 560 : 140)) / 2;
  final arSize = _fitFont(d.name, 92, colW);
  _drawText(c, d.name, arSize, d.color, lhW - lhMx, 150);
  if (d.nameEn.isNotEmpty) {
    final enSize = _fitFont(d.nameEn, 54, colW,
        weight: FontWeight.w600, dir: TextDirection.ltr);
    _drawText(c, d.nameEn, enSize, const Color(0xFF3D4C5C), lhMx, 150,
        weight: FontWeight.w600, dir: TextDirection.ltr, align: _Align.left);
  }
  if (d.logo != null) _drawLogo(c, d.logo!, lhW / 2, 150, 480, 250);
  _rect(c, lhMx, 298, lhW - 2 * lhMx, 8, d.color);
  _rect(c, lhMx, 314, lhW - 2 * lhMx, 2, d.color);
  _rect(c, lhMx, 3126, lhW - 2 * lhMx, 2, d.color);
  _rect(c, lhMx, 3134, lhW - 2 * lhMx, 8, d.color);
  _drawContact(c, d, const Color(0xFF333D47), 3192, 3252);
}

/// «شريط ملوّن»: شريط علوي وسفلي بلون المنشأة والأسماء بالأبيض.
void _drawBand(Canvas c, LetterheadDesign d) {
  _rect(c, 0, 0, lhW, 300, d.color);
  _rect(c, 0, 300, lhW, 12, _shade(d.color, 0.72));
  var textRight = lhW - lhMx;
  if (d.logo != null) {
    const box = 224.0;
    final bx = lhW - lhMx - box, by = (300 - box) / 2;
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(bx, by, box, box), const Radius.circular(26)),
      Paint()..color = Colors.white,
    );
    _drawLogo(c, d.logo!, bx + box / 2, by + box / 2, box - 40, box - 40);
    textRight = bx - 64;
  }
  final maxW = textRight - lhMx;
  final arSize = _fitFont(d.name, 84, maxW);
  _drawText(c, d.name, arSize, Colors.white, textRight,
      d.nameEn.isNotEmpty ? 112 : 150);
  if (d.nameEn.isNotEmpty) {
    final enSize = _fitFont(d.nameEn, 46, maxW,
        weight: FontWeight.w600, dir: TextDirection.ltr);
    _drawText(c, d.nameEn, enSize, Colors.white.withValues(alpha: .88),
        textRight, 212,
        weight: FontWeight.w600, dir: TextDirection.ltr);
  }
  _rect(c, 0, 3148, lhW, 12, _shade(d.color, 0.72));
  _rect(c, 0, 3160, lhW, lhH - 3160, d.color);
  _drawContact(c, d, Colors.white, 3204, 3262);
}

/// «بسيط أنيق»: كل شيء وسط الصفحة مع خط رفيع بمعيّن صغير.
void _rule(Canvas c, Color color, double cy) {
  _rect(c, lhW / 2 - 300, cy - 2, 262, 4, color);
  _rect(c, lhW / 2 + 38, cy - 2, 262, 4, color);
  c.save();
  c.translate(lhW / 2, cy);
  c.rotate(0.785398); // 45°
  _rect(c, -11, -11, 22, 22, color);
  c.restore();
}

void _drawMinimal(Canvas c, LetterheadDesign d) {
  final hasLogo = d.logo != null;
  if (hasLogo) _drawLogo(c, d.logo!, lhW / 2, 92, 420, 148);
  final arSize = _fitFont(d.name, hasLogo ? 66 : 84, lhW - 2 * lhMx);
  _drawText(c, d.name, arSize, const Color(0xFF1C2733), lhW / 2,
      hasLogo ? 216 : 116,
      align: _Align.center);
  if (d.nameEn.isNotEmpty) {
    final enSize = _fitFont(d.nameEn, 40, lhW - 2 * lhMx,
        weight: FontWeight.w600, dir: TextDirection.ltr);
    _drawText(c, d.nameEn, enSize, const Color(0xFF55606C), lhW / 2,
        hasLogo ? 274 : 186,
        weight: FontWeight.w600, dir: TextDirection.ltr,
        align: _Align.center);
  }
  _rule(c, d.color, hasLogo ? 314 : 244);
  _rule(c, d.color, 3150);
  _drawContact(c, d, const Color(0xFF4A5563), 3204, 3260);
}

/// يرسم الترويسة كاملة بإحداثيات الصفحة الكاملة (2550×3300).
void paintLetterhead(Canvas c, LetterheadDesign d) {
  _rect(c, 0, 0, lhW, lhH, Colors.white);
  switch (d.template) {
    case 'band':
      _drawBand(c, d);
    case 'minimal':
      _drawMinimal(c, d);
    default:
      _drawClassic(c, d);
  }
}

/// توليد صورة الترويسة النهائية PNG بدقة الطباعة الكاملة.
Future<Uint8List> renderLetterheadPng(LetterheadDesign d) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, lhW, lhH));
  paintLetterhead(canvas, d);
  final image =
      await recorder.endRecording().toImage(lhW.toInt(), lhH.toInt());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// معاينة حية مصغّرة للترويسة.
class LetterheadPreview extends StatelessWidget {
  final LetterheadDesign design;
  const LetterheadPreview({super.key, required this.design});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: lhW / lhH,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CustomPaint(painter: _PreviewPainter(design)),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final LetterheadDesign design;
  _PreviewPainter(this.design);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / lhW, size.height / lhH);
    paintLetterhead(canvas, design);
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) => true;
}
