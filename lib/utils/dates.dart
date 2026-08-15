/// تواريخ هجرية وميلادية بصيغة الرسائل الرسمية — مطابق لنسخة سطح المكتب.
library;

import 'package:hijri/hijri_calendar.dart';

const hijriMonths = [
  'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر', 'جمادى الأولى', 'جمادى الآخرة',
  'رجب', 'شعبان', 'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة',
];

const _arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

String toArabicDigits(String text) {
  final sb = StringBuffer();
  for (final code in text.codeUnits) {
    if (code >= 0x30 && code <= 0x39) {
      sb.write(_arabicDigits[code - 0x30]);
    } else {
      sb.writeCharCode(code);
    }
  }
  return sb.toString();
}

/// مثال: «٢٥ صفر ١٤٤٨ هـ».
String hijriString(DateTime g) {
  try {
    final h = HijriCalendar.fromDate(g);
    final day = toArabicDigits(h.hDay.toString());
    final year = toArabicDigits(h.hYear.toString());
    return '$day ${hijriMonths[h.hMonth - 1]} $year هـ';
  } catch (_) {
    return '';
  }
}

/// مثال: «08/08/2026 م».
String gregorianString(DateTime g) {
  final d = g.day.toString().padLeft(2, '0');
  final m = g.month.toString().padLeft(2, '0');
  return '$d/$m/${g.year} م';
}

/// تحويل تاريخ ISO إلى الصيغة الرسمية «يوم/شهر/سنةم» — لسياق المراجع في الموجّه.
String fmtIsoDate(String? iso) {
  if (iso == null || iso.isEmpty) return 'غير محدد';
  final parts = iso.split('T').first.split('-');
  if (parts.length < 3) return iso;
  return '${parts[2]}/${parts[1]}/${parts[0]}م';
}
