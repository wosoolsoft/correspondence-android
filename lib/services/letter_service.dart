/// العمليات الجوهرية: توليد الرسائل وتنقيحها وتصديرها،
/// مع الترقيم المرجعي المزدوج — منقول عن services.py في نسخة سطح المكتب.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../ai/ai_client.dart' as ai;
import '../data/db.dart';
import '../docx/docx_engine.dart';
import '../models/letter_doc.dart';
import '../pdf/pdf_engine.dart';

/// خطأ عمليات برسالة عربية صالحة للعرض.
class ServiceError implements Exception {
  final String message;
  ServiceError(this.message);
  @override
  String toString() => message;
}

class LetterService {
  LetterService._();
  static final LetterService instance = LetterService._();

  final _db = AppDb.instance;

  /// يحل الإشارات {type, id} إلى تفاصيلها الكاملة للحقن في الموجّه.
  Future<List<Map<String, dynamic>>> resolveReferences(
      List<Map<String, dynamic>>? references) async {
    final out = <Map<String, dynamic>>[];
    for (final ref in references ?? const <Map<String, dynamic>>[]) {
      final rid = ref['id'];
      if (rid is! int) continue;
      if (ref['type'] == 'outgoing') {
        final src = await _db.getLetter(rid);
        if (src != null) {
          out.add({
            'type': 'outgoing',
            'id': src['id'],
            'ref_number': src['ref_number'],
            'date_greg': src['date_greg'],
            'subject': src['subject'],
            'party': src['recipient'],
            'doc': src['doc'],
          });
        }
      } else if (ref['type'] == 'incoming') {
        final src = await _db.getIncoming(rid);
        if (src != null) {
          out.add({
            'type': 'incoming',
            'id': src['id'],
            'ref_number': src['ref_number'],
            'date_greg': src['date_greg'],
            'subject': src['subject'],
            'party': src['sender'],
            'summary': src['summary'],
          });
        }
      }
    }
    return out;
  }

  /// التدفق الكامل لتوليد رسالة جديدة وحفظها في الأرشيف برقم مرجعي.
  Future<Map<String, dynamic>> generate({
    required int entityId,
    required String brief,
    String recipient = '',
    String letterType = 'عام',
    String tone = ai.defaultTone,
    String greeting = '',
    bool useHijri = false,
    bool demo = false,
    int? recipientId,
    bool saveRecipient = true,
    List<Map<String, dynamic>>? references,
  }) async {
    final entity = await _db.getEntity(entityId);
    if (entity == null) throw ServiceError('المنشأة غير موجودة');
    brief = brief.trim();
    if (brief.isEmpty && !demo) {
      throw ServiceError('اكتب مضمون الرسالة أولًا');
    }

    // الجهة المستلمة: جهة محفوظة، أو حفظ تلقائي للجهة الجديدة
    recipient = recipient.trim();
    Map<String, dynamic>? recipientRec;
    if (recipientId != null) {
      recipientRec = await _db.getRecipient(recipientId);
    } else if (recipient.isNotEmpty && saveRecipient) {
      recipientRec = await _db.findOrCreateRecipient(recipient);
    }
    final recipientName =
        (recipientRec?['name'] as String?)?.trim().isNotEmpty == true
            ? recipientRec!['name'] as String
            : recipient;

    final refs = await resolveReferences(references);
    final effectiveTone = ai.tones.containsKey(tone) ? tone : ai.defaultTone;
    final LetterDoc doc;
    if (demo) {
      doc = ai.demoLetter(
        entity: entity,
        letterType: letterType,
        recipient: recipientName,
        brief: brief,
        greetingPref: greeting,
        tone: effectiveTone,
        recipientInfo: recipientRec,
        references: refs,
      );
    } else {
      doc = await ai.generateLetter(
        entity: entity,
        letterType: letterType,
        recipient: recipientName,
        brief: brief,
        greetingPref: greeting,
        tone: effectiveTone,
        recipientInfo: recipientRec,
        references: refs,
      );
    }

    final today = DateTime.now();
    final (refNumber, refSeq) = await _db.nextRef(entityId, today.year);
    final recipientSeq = recipientRec != null
        ? await _db.nextRecipientSeq(entityId, recipientRec['id'] as int)
        : null;
    final letter = await _db.createLetter({
      'entity_id': entityId,
      'letter_type': letterType,
      'recipient': recipientName.isNotEmpty
          ? recipientName
          : doc.recipientLines.join(' | '),
      'recipient_id': recipientRec?['id'],
      'recipient_seq': recipientSeq,
      'tone': effectiveTone,
      'subject': doc.subject,
      'ref_number': refNumber,
      'ref_year': today.year,
      'ref_seq': refSeq,
      'date_greg':
          today.toIso8601String().split('T').first, // yyyy-MM-dd
      'use_hijri': useHijri,
      'brief': brief,
      'doc_json': doc.toJsonString(),
    });
    if (refs.isNotEmpty) {
      await _db.setLetterReferences(letter['id'] as int, [
        for (final r in refs) {'type': r['type'], 'id': r['id']}
      ]);
    }
    letter['entity'] = entity;
    return letter;
  }

  /// إنشاء مسودة فورية من قالب محفوظ — بمرجع وتاريخ جديدين، دون ذكاء اصطناعي.
  Future<Map<String, dynamic>> createFromTemplate(int templateId) async {
    final template = await _db.getTemplate(templateId);
    if (template == null) throw ServiceError('القالب غير موجود');
    Map<String, dynamic>? entity;
    final tEntityId = template['entity_id'];
    if (tEntityId is int) entity = await _db.getEntity(tEntityId);
    if (entity == null) {
      final entities = await _db.listEntities();
      if (entities.isEmpty) {
        throw ServiceError('أضف منشأة من صفحة «المنشآت» أولًا');
      }
      entity = entities.first;
    }
    final entityId = entity['id'] as int;
    final doc = LetterDoc.normalize(template['doc']);
    final recipient = ((template['recipient'] as String?) ?? '').trim();
    Map<String, dynamic>? recipientRec;
    if (recipient.isNotEmpty) {
      recipientRec = await _db.findOrCreateRecipient(recipient);
    }
    final today = DateTime.now();
    final (refNumber, refSeq) = await _db.nextRef(entityId, today.year);
    final recipientSeq = recipientRec != null
        ? await _db.nextRecipientSeq(entityId, recipientRec['id'] as int)
        : null;
    final letter = await _db.createLetter({
      'entity_id': entityId,
      'letter_type': template['letter_type'] ?? 'عام',
      'recipient':
          recipient.isNotEmpty ? recipient : doc.recipientLines.join(' | '),
      'recipient_id': recipientRec?['id'],
      'recipient_seq': recipientSeq,
      'tone': template['tone'] ?? ai.defaultTone,
      'subject': doc.subject,
      'ref_number': refNumber,
      'ref_year': today.year,
      'ref_seq': refSeq,
      'date_greg': today.toIso8601String().split('T').first,
      'use_hijri': false,
      'brief': '',
      'doc_json': doc.toJsonString(),
    });
    letter['entity'] = entity;
    return letter;
  }

  /// حفظ رسالة قائمة قالبًا شخصيًا يُعاد استخدامه.
  Future<void> saveAsTemplate(int letterId, String name) async {
    final letter = await _db.getLetter(letterId);
    if (letter == null) throw ServiceError('الرسالة غير موجودة');
    if (name.trim().isEmpty) throw ServiceError('اسم القالب مطلوب');
    await _db.createTemplate({
      'name': name.trim(),
      'entity_id': letter['entity_id'],
      'letter_type': letter['letter_type'],
      'tone': letter['tone'],
      'recipient': letter['recipient'],
      'doc_json': jsonEncode(letter['doc']),
    });
  }

  /// تنقيح رسالة قائمة بالذكاء الاصطناعي مع حفظ النسخة السابقة في المراجعات.
  Future<Map<String, dynamic>> revise(int letterId, String instruction) async {
    final letter = await _db.getLetter(letterId);
    if (letter == null) throw ServiceError('الرسالة غير موجودة');
    if (instruction.trim().isEmpty) {
      throw ServiceError('اكتب توجيه التعديل أولًا');
    }
    final entity = await _db.getEntity(letter['entity_id'] as int);
    final current = LetterDoc.normalize(letter['doc']);
    final references = await _db.getLetterReferences(letterId);
    final newDoc = await ai.reviseLetter(
      entity: entity!,
      doc: current,
      instruction: instruction,
      references: references,
    );
    await _db.addRevision(letterId, jsonEncode(letter['doc']), instruction);
    final updated = await _db.updateLetter(letterId, {
      'doc_json': newDoc.toJsonString(),
      'subject': newDoc.subject,
      'recipient': newDoc.recipientLines.join(' | '),
    });
    updated!['entity'] = entity;
    return updated;
  }

  /// بايتات PDF للمعاينة أو التصدير — من الحالة المحفوظة للرسالة.
  Future<Uint8List> buildPdf(int letterId) async {
    final letter = await _db.getLetter(letterId);
    if (letter == null) throw ServiceError('الرسالة غير موجودة');
    final entity = await _db.getEntity(letter['entity_id'] as int);
    if (entity == null) throw ServiceError('المنشأة غير موجودة');
    final doc = LetterDoc.normalize(letter['doc']);

    String? letterheadPath;
    final lh = (entity['letterhead'] as String?) ?? '';
    if (lh.isNotEmpty) {
      final dir = await _db.letterheadsDir();
      final f = File(p.join(dir.path, lh));
      if (await f.exists()) letterheadPath = f.path;
    }

    DateTime letterDate;
    try {
      letterDate = DateTime.parse(letter['date_greg'] as String);
    } catch (_) {
      letterDate = DateTime.now();
    }

    return renderPdf(
      entity: entity,
      doc: doc,
      refNumber: (letter['ref_number'] as String?) ?? '',
      letterDate: letterDate,
      useHijri: letter['use_hijri'] == 1,
      letterheadPath: letterheadPath,
    );
  }

  /// اسم ملف فريد وآمن: «{id} - {المرجع} - {الموضوع}» بعد تعقيم كامل.
  String safeFilename(Map<String, dynamic> letter) {
    final subject = ((letter['subject'] as String?) ?? '')
        .replaceFirst(RegExp(r'^الموضوع\s*[:/]\s*'), '');
    final parts = [
      '${letter['id']}',
      (letter['ref_number'] as String?) ?? '',
      subject,
    ];
    var base = parts
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .join(' - ');
    base = base.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]+'), ' ');
    base = base.replaceAll(RegExp(r'\s+'), ' ').trim();
    base = base.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
    if (base.length > 120) base = base.substring(0, 120);
    return base.isEmpty ? '${letter['id']}' : base;
  }

  /// تصدير الرسالة إلى PDF في مجلد الإخراج واعتمادها نهائية.
  /// يعيد (مسار الملف، البايتات).
  Future<(String, Uint8List)> exportPdf(int letterId) async {
    final letter = await _db.getLetter(letterId);
    if (letter == null) throw ServiceError('الرسالة غير موجودة');
    final bytes = await buildPdf(letterId);
    final dir = await _db.outputDir();
    final path = p.join(dir.path, '${safeFilename(letter)}.pdf');
    await File(path).writeAsBytes(bytes);
    await _db.updateLetter(letterId, {'pdf_path': path, 'status': 'final'});
    return (path, bytes);
  }

  /// تصدير الرسالة إلى Word (DOCX) واعتمادها نهائية — بنفس مواصفات
  /// محرك سطح المكتب. يعيد (مسار الملف، البايتات).
  Future<(String, Uint8List)> exportDocx(int letterId) async {
    final letter = await _db.getLetter(letterId);
    if (letter == null) throw ServiceError('الرسالة غير موجودة');
    final entity = await _db.getEntity(letter['entity_id'] as int);
    if (entity == null) throw ServiceError('المنشأة غير موجودة');
    final doc = LetterDoc.normalize(letter['doc']);

    Uint8List? letterheadBytes;
    var letterheadExt = 'png';
    final lh = (entity['letterhead'] as String?) ?? '';
    if (lh.isNotEmpty) {
      final dir = await _db.letterheadsDir();
      final f = File(p.join(dir.path, lh));
      if (await f.exists()) {
        letterheadBytes = await f.readAsBytes();
        final ext = p.extension(lh).replaceFirst('.', '').toLowerCase();
        if (ext.isNotEmpty) letterheadExt = ext;
      }
    }

    DateTime letterDate;
    try {
      letterDate = DateTime.parse(letter['date_greg'] as String);
    } catch (_) {
      letterDate = DateTime.now();
    }

    final bytes = await renderDocx(
      entity: entity,
      doc: doc,
      refNumber: (letter['ref_number'] as String?) ?? '',
      letterDate: letterDate,
      useHijri: letter['use_hijri'] == 1,
      letterheadBytes: letterheadBytes,
      letterheadExt: letterheadExt,
    );
    final dir = await _db.outputDir();
    final path = p.join(dir.path, '${safeFilename(letter)}.docx');
    await File(path).writeAsBytes(bytes);
    await _db.updateLetter(letterId, {'docx_path': path, 'status': 'final'});
    return (path, bytes);
  }
}
