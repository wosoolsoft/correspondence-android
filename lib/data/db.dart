/// قاعدة البيانات المحلية (SQLite): المنشآت، الرسائل، الجهات، المراجعات…
/// المخطط مطابق لنسخة سطح المكتب (diwan) ليتيسر استيراد قاعدة قائمة لاحقًا.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

const _createStatements = <String>[
  '''
CREATE TABLE IF NOT EXISTS entities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    name_en TEXT DEFAULT '',
    letterhead TEXT DEFAULT '',
    signer_title TEXT DEFAULT 'المدير العام',
    signer_name TEXT DEFAULT '',
    default_greeting TEXT DEFAULT 'تحية طيبة وبعد،',
    default_closing TEXT DEFAULT 'وتقبلوا خالص التحايا،،،',
    active INTEGER DEFAULT 1,
    address TEXT DEFAULT '',
    phone TEXT DEFAULT '',
    email TEXT DEFAULT '',
    website TEXT DEFAULT '',
    logo TEXT DEFAULT '',
    letterhead_design TEXT DEFAULT '',
    created_at TEXT NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS letters (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_id INTEGER NOT NULL REFERENCES entities(id),
    letter_type TEXT DEFAULT 'عام',
    recipient TEXT DEFAULT '',
    subject TEXT DEFAULT '',
    ref_number TEXT DEFAULT '',
    ref_year INTEGER,
    ref_seq INTEGER,
    date_greg TEXT NOT NULL,
    use_hijri INTEGER DEFAULT 0,
    brief TEXT DEFAULT '',
    doc_json TEXT NOT NULL,
    status TEXT DEFAULT 'draft',
    docx_path TEXT DEFAULT '',
    pdf_path TEXT DEFAULT '',
    recipient_id INTEGER,
    recipient_seq INTEGER,
    tone TEXT DEFAULT 'رسمية محايدة',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS revisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    letter_id INTEGER NOT NULL REFERENCES letters(id) ON DELETE CASCADE,
    doc_json TEXT NOT NULL,
    instruction TEXT DEFAULT '',
    created_at TEXT NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS recipients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    honorific TEXT DEFAULT 'الأخوة /',
    suffix TEXT DEFAULT 'المحترمون',
    notes TEXT DEFAULT '',
    created_at TEXT NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS incoming_letters (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_id INTEGER NOT NULL REFERENCES entities(id),
    sender TEXT DEFAULT '',
    recipient_id INTEGER REFERENCES recipients(id),
    ref_number TEXT DEFAULT '',
    date_greg TEXT DEFAULT '',
    subject TEXT DEFAULT '',
    summary TEXT DEFAULT '',
    created_at TEXT NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS letter_references (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    letter_id INTEGER NOT NULL REFERENCES letters(id) ON DELETE CASCADE,
    ref_type TEXT NOT NULL CHECK (ref_type IN ('outgoing', 'incoming')),
    ref_id INTEGER NOT NULL,
    created_at TEXT NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS templates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    entity_id INTEGER REFERENCES entities(id),
    letter_type TEXT DEFAULT 'عام',
    tone TEXT DEFAULT 'رسمية محايدة',
    recipient TEXT DEFAULT '',
    doc_json TEXT NOT NULL,
    created_at TEXT NOT NULL
)''',
];

// بيانات أولية تجريبية (أسماء افتراضية للإيضاح فقط) — قابلة للتعديل والحذف.
const _seedEntities = [
  {
    'name': 'شركة مثال للصرافة',
    'name_en': 'Example Exchange Company',
    'signer_title': 'المدير العام',
    'signer_name': 'محمد محمد محمد',
    'default_greeting': 'تحية طيبة وبعد،',
    'default_closing': 'وتفضلوا بقبول خالص التقدير والاحترام،،،',
  },
  {
    'name': 'مؤسسة مثال للتجارة والاستيراد',
    'name_en': 'Example Trading & Import Est.',
    'signer_title': 'المدير العام',
    'signer_name': 'محمد محمد محمد',
    'default_greeting': 'تحية طيبة وبعد،',
    'default_closing': 'وتقبلوا خالص التحايا،،،',
  },
];

String _now() => DateTime.now().toUtc().toIso8601String().split('.').first;

// أعمدة أُضيفت بعد الإصدار الأول في نسخة سطح المكتب — تُرحَّل تلقائيًا
// عند استيراد قاعدة diwan.db قديمة لا تحتويها.
const _letterMigrations = [
  ('recipient_id', 'INTEGER'),
  ('recipient_seq', 'INTEGER'),
  ("tone", "TEXT DEFAULT 'رسمية محايدة'"),
];
const _entityMigrations = [
  ('address', "TEXT DEFAULT ''"),
  ('phone', "TEXT DEFAULT ''"),
  ('email', "TEXT DEFAULT ''"),
  ('website', "TEXT DEFAULT ''"),
  ('logo', "TEXT DEFAULT ''"),
  ('letterhead_design', "TEXT DEFAULT ''"),
];

class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();
  Database? _db;

  Future<String> dbPath() async =>
      p.join(await getDatabasesPath(), 'correspondence.db');

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      await dbPath(),
      version: 1,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onOpen: _ensureSchema,
    );
    return _db!;
  }

  /// إنشاء/ترحيل المخطط عند كل فتح — متسامح مع قاعدة مستوردة من نسخة
  /// سطح المكتب (ينشئ الجداول الناقصة ويضيف الأعمدة المستحدثة).
  Future<void> _ensureSchema(Database d) async {
    for (final stmt in _createStatements) {
      await d.execute(stmt);
    }
    Future<void> addMissing(
        String table, List<(String, String)> migrations) async {
      final existing = {
        for (final r in await d.rawQuery('PRAGMA table_info($table)'))
          r['name'] as String
      };
      for (final (col, ddl) in migrations) {
        if (!existing.contains(col)) {
          await d.execute('ALTER TABLE $table ADD COLUMN $col $ddl');
        }
      }
    }

    await addMissing('letters', _letterMigrations);
    await addMissing('entities', _entityMigrations);
    final count = Sqflite.firstIntValue(
            await d.rawQuery('SELECT COUNT(*) FROM entities')) ??
        0;
    if (count == 0) {
      for (final e in _seedEntities) {
        await d.insert('entities', {...e, 'created_at': _now()});
      }
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// مجلد صور الترويسات داخل مساحة التطبيق الخاصة.
  Future<Directory> letterheadsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'letterheads'));
    await dir.create(recursive: true);
    return dir;
  }

  /// مجلد الملفات المصدَّرة.
  Future<Directory> outputDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'output'));
    await dir.create(recursive: true);
    return dir;
  }

  // ---------- المنشآت ----------

  Future<List<Map<String, dynamic>>> listEntities(
      {bool includeInactive = false}) async {
    final d = await db;
    return d.query('entities',
        where: includeInactive ? null : 'active = 1', orderBy: 'id');
  }

  Future<Map<String, dynamic>?> getEntity(int id) async {
    final d = await db;
    final rows = await d.query('entities', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>> createEntity(Map<String, dynamic> data) async {
    final d = await db;
    final id = await d.insert('entities', {
      'name': data['name'] ?? '',
      'name_en': data['name_en'] ?? '',
      'letterhead': data['letterhead'] ?? '',
      'signer_title': data['signer_title'] ?? 'المدير العام',
      'signer_name': data['signer_name'] ?? '',
      'default_greeting': data['default_greeting'] ?? 'تحية طيبة وبعد،',
      'default_closing': data['default_closing'] ?? 'وتقبلوا خالص التحايا،،،',
      'address': data['address'] ?? '',
      'phone': data['phone'] ?? '',
      'email': data['email'] ?? '',
      'website': data['website'] ?? '',
      'created_at': _now(),
    });
    return (await getEntity(id))!;
  }

  Future<Map<String, dynamic>?> updateEntity(
      int id, Map<String, dynamic> data) async {
    const fields = [
      'name', 'name_en', 'letterhead', 'signer_title', 'signer_name',
      'default_greeting', 'default_closing', 'active',
      'address', 'phone', 'email', 'website', 'logo', 'letterhead_design',
    ];
    final updates = {
      for (final f in fields)
        if (data.containsKey(f) && data[f] != null) f: data[f]
    };
    if (updates.isNotEmpty) {
      final d = await db;
      await d.update('entities', updates, where: 'id = ?', whereArgs: [id]);
    }
    return getEntity(id);
  }

  /// حذف منشأة؛ إن كانت لها رسائل محفوظة تُعطَّل بدلًا من حذفها حفاظًا على الأرشيف.
  Future<Map<String, dynamic>> deleteEntity(int id) async {
    final d = await db;
    final count = Sqflite.firstIntValue(await d.rawQuery(
            'SELECT COUNT(*) FROM letters WHERE entity_id = ?', [id])) ??
        0;
    if (count > 0) {
      await d.update('entities', {'active': 0},
          where: 'id = ?', whereArgs: [id]);
      return {'deleted': false, 'deactivated': true, 'letters': count};
    }
    await d.delete('entities', where: 'id = ?', whereArgs: [id]);
    return {'deleted': true, 'deactivated': false, 'letters': 0};
  }

  // ---------- الجهات المستلمة ----------

  Future<List<Map<String, dynamic>>> listRecipients() async {
    final d = await db;
    return d.rawQuery('''
      SELECT r.*, (SELECT COUNT(*) FROM letters l WHERE l.recipient_id = r.id)
             AS letters_count
      FROM recipients r ORDER BY r.name''');
  }

  Future<Map<String, dynamic>?> getRecipient(int id) async {
    final d = await db;
    final rows = await d.query('recipients', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>> createRecipient(
      Map<String, dynamic> data) async {
    final d = await db;
    final id = await d.insert('recipients', {
      'name': (data['name'] ?? '').toString().trim(),
      'honorific': data['honorific'] ?? 'الأخوة /',
      'suffix': data['suffix'] ?? 'المحترمون',
      'notes': data['notes'] ?? '',
      'created_at': _now(),
    });
    return (await getRecipient(id))!;
  }

  Future<Map<String, dynamic>?> updateRecipient(
      int id, Map<String, dynamic> data) async {
    const fields = ['name', 'honorific', 'suffix', 'notes'];
    final updates = {
      for (final f in fields)
        if (data.containsKey(f) && data[f] != null) f: data[f]
    };
    if (updates.isNotEmpty) {
      final d = await db;
      await d.update('recipients', updates, where: 'id = ?', whereArgs: [id]);
    }
    return getRecipient(id);
  }

  /// حذف جهة مستلمة؛ رسائلها المؤرشفة تحتفظ بالاسم نصًا فلا تتأثر.
  Future<void> deleteRecipient(int id) async {
    final d = await db;
    await d.update('letters', {'recipient_id': null},
        where: 'recipient_id = ?', whereArgs: [id]);
    await d.delete('recipients', where: 'id = ?', whereArgs: [id]);
  }

  /// يعيد الجهة المطابقة للاسم أو ينشئها تلقائيًا.
  Future<Map<String, dynamic>> findOrCreateRecipient(String name) async {
    final d = await db;
    final rows =
        await d.query('recipients', where: 'name = ?', whereArgs: [name.trim()]);
    if (rows.isNotEmpty) return rows.first;
    return createRecipient({'name': name.trim()});
  }

  // ---------- الترقيم المرجعي ----------

  /// الترقيم العام: يقترح المرجع التالي بصيغة «yy-seq» لكل منشأة وسنة.
  Future<(String, int)> nextRef(int entityId, int year) async {
    final d = await db;
    final r = Sqflite.firstIntValue(await d.rawQuery(
        'SELECT MAX(ref_seq) FROM letters WHERE entity_id = ? AND ref_year = ?',
        [entityId, year]));
    final seq = (r ?? 0) + 1;
    return ('${year % 100}-$seq', seq);
  }

  /// الترقيم الخاص: تسلسل رسائل المنشأة إلى جهة مستلمة بعينها.
  Future<int> nextRecipientSeq(int entityId, int recipientId) async {
    final d = await db;
    final r = Sqflite.firstIntValue(await d.rawQuery(
        'SELECT MAX(recipient_seq) FROM letters'
        ' WHERE entity_id = ? AND recipient_id = ?',
        [entityId, recipientId]));
    return (r ?? 0) + 1;
  }

  // ---------- الرسائل ----------

  Future<Map<String, dynamic>> createLetter(Map<String, dynamic> data) async {
    final d = await db;
    final now = _now();
    final id = await d.insert('letters', {
      'entity_id': data['entity_id'],
      'letter_type': data['letter_type'] ?? 'عام',
      'recipient': data['recipient'] ?? '',
      'subject': data['subject'] ?? '',
      'ref_number': data['ref_number'] ?? '',
      'ref_year': data['ref_year'],
      'ref_seq': data['ref_seq'],
      'date_greg': data['date_greg'],
      'use_hijri': data['use_hijri'] == true ? 1 : 0,
      'brief': data['brief'] ?? '',
      'doc_json': data['doc_json'],
      'status': data['status'] ?? 'draft',
      'recipient_id': data['recipient_id'],
      'recipient_seq': data['recipient_seq'],
      'tone': data['tone'] ?? 'رسمية محايدة',
      'created_at': now,
      'updated_at': now,
    });
    return (await getLetter(id))!;
  }

  Future<Map<String, dynamic>?> getLetter(int id) async {
    final d = await db;
    final rows = await d.query('letters', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final letter = Map<String, dynamic>.from(rows.first);
    try {
      letter['doc'] = jsonDecode(letter.remove('doc_json') as String);
    } catch (_) {
      letter['doc'] = <String, dynamic>{};
    }
    return letter;
  }

  Future<List<Map<String, dynamic>>> listLetters(
      {String search = '', int? entityId, String status = ''}) async {
    final d = await db;
    var q = '''
      SELECT l.id, l.entity_id, l.letter_type, l.recipient, l.subject,
             l.ref_number, l.date_greg, l.status, l.updated_at,
             l.recipient_seq, l.tone, e.name AS entity_name
      FROM letters l JOIN entities e ON e.id = l.entity_id WHERE 1=1''';
    final vals = <Object?>[];
    if (search.isNotEmpty) {
      q += ' AND (l.subject LIKE ? OR l.recipient LIKE ? OR l.ref_number LIKE ?)';
      vals.addAll(List.filled(3, '%$search%'));
    }
    if (entityId != null) {
      q += ' AND l.entity_id = ?';
      vals.add(entityId);
    }
    if (status.isNotEmpty) {
      q += ' AND l.status = ?';
      vals.add(status);
    }
    q += ' ORDER BY l.id DESC LIMIT 500';
    return d.rawQuery(q, vals);
  }

  Future<Map<String, dynamic>?> updateLetter(
      int id, Map<String, dynamic> data) async {
    const fields = [
      'letter_type', 'recipient', 'subject', 'ref_number', 'ref_year',
      'ref_seq', 'date_greg', 'use_hijri', 'brief', 'doc_json', 'status',
      'docx_path', 'pdf_path', 'recipient_id', 'recipient_seq', 'tone',
    ];
    final updates = <String, Object?>{
      for (final f in fields)
        if (data.containsKey(f) && data[f] != null) f: data[f]
    };
    if (updates.isNotEmpty) {
      updates['updated_at'] = _now();
      final d = await db;
      await d.update('letters', updates, where: 'id = ?', whereArgs: [id]);
    }
    return getLetter(id);
  }

  Future<void> deleteLetter(int id) async {
    final d = await db;
    await d.delete('revisions', where: 'letter_id = ?', whereArgs: [id]);
    await d.delete('letter_references',
        where: 'letter_id = ?', whereArgs: [id]);
    await d.delete('letter_references',
        where: "ref_type = 'outgoing' AND ref_id = ?", whereArgs: [id]);
    await d.delete('letters', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addRevision(
      int letterId, String docJson, String instruction) async {
    final d = await db;
    await d.insert('revisions', {
      'letter_id': letterId,
      'doc_json': docJson,
      'instruction': instruction,
      'created_at': _now(),
    });
  }

  // ---------- سجل الوارد ----------

  Future<List<Map<String, dynamic>>> listIncoming(
      {String search = '', int? entityId}) async {
    final d = await db;
    var q = '''
      SELECT i.*, e.name AS entity_name
      FROM incoming_letters i JOIN entities e ON e.id = i.entity_id
      WHERE 1=1''';
    final vals = <Object?>[];
    if (search.isNotEmpty) {
      q += ' AND (i.subject LIKE ? OR i.sender LIKE ?'
          ' OR i.ref_number LIKE ? OR i.summary LIKE ?)';
      vals.addAll(List.filled(4, '%$search%'));
    }
    if (entityId != null) {
      q += ' AND i.entity_id = ?';
      vals.add(entityId);
    }
    q += ' ORDER BY i.id DESC LIMIT 500';
    return d.rawQuery(q, vals);
  }

  Future<Map<String, dynamic>?> getIncoming(int id) async {
    final d = await db;
    final rows =
        await d.query('incoming_letters', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>> createIncoming(
      Map<String, dynamic> data) async {
    final d = await db;
    final id = await d.insert('incoming_letters', {
      'entity_id': data['entity_id'],
      'sender': data['sender'] ?? '',
      'recipient_id': data['recipient_id'],
      'ref_number': data['ref_number'] ?? '',
      'date_greg': data['date_greg'] ?? '',
      'subject': data['subject'] ?? '',
      'summary': data['summary'] ?? '',
      'created_at': _now(),
    });
    return (await getIncoming(id))!;
  }

  Future<Map<String, dynamic>?> updateIncoming(
      int id, Map<String, dynamic> data) async {
    const fields = [
      'entity_id', 'sender', 'recipient_id', 'ref_number',
      'date_greg', 'subject', 'summary',
    ];
    final updates = {
      for (final f in fields)
        if (data.containsKey(f) && data[f] != null) f: data[f]
    };
    if (updates.isNotEmpty) {
      final d = await db;
      await d.update('incoming_letters', updates,
          where: 'id = ?', whereArgs: [id]);
    }
    return getIncoming(id);
  }

  Future<void> deleteIncoming(int id) async {
    final d = await db;
    await d.delete('letter_references',
        where: "ref_type = 'incoming' AND ref_id = ?", whereArgs: [id]);
    await d.delete('incoming_letters', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- إشارات الرسائل ----------

  /// يستبدل إشارات الرسالة: refs عناصرها {type: outgoing|incoming, id: int}.
  Future<void> setLetterReferences(
      int letterId, List<Map<String, dynamic>> refs) async {
    final d = await db;
    await d.delete('letter_references',
        where: 'letter_id = ?', whereArgs: [letterId]);
    for (final r in refs) {
      final type = r['type'];
      final id = r['id'];
      if ((type == 'outgoing' || type == 'incoming') && id is int) {
        await d.insert('letter_references', {
          'letter_id': letterId,
          'ref_type': type,
          'ref_id': id,
          'created_at': _now(),
        });
      }
    }
  }

  /// يعيد إشارات الرسالة مع تفاصيل كل مرجع جاهزة للعرض والحقن في الموجّه.
  Future<List<Map<String, dynamic>>> getLetterReferences(int letterId) async {
    final d = await db;
    final rows = await d.query('letter_references',
        columns: ['ref_type', 'ref_id'],
        where: 'letter_id = ?',
        whereArgs: [letterId],
        orderBy: 'id');
    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      if (row['ref_type'] == 'outgoing') {
        final letter = await getLetter(row['ref_id'] as int);
        if (letter != null) {
          out.add({
            'type': 'outgoing',
            'id': letter['id'],
            'ref_number': letter['ref_number'],
            'date_greg': letter['date_greg'],
            'subject': letter['subject'],
            'party': letter['recipient'],
            'doc': letter['doc'],
          });
        }
      } else {
        final inc = await getIncoming(row['ref_id'] as int);
        if (inc != null) {
          out.add({
            'type': 'incoming',
            'id': inc['id'],
            'ref_number': inc['ref_number'],
            'date_greg': inc['date_greg'],
            'subject': inc['subject'],
            'party': inc['sender'],
            'summary': inc['summary'],
          });
        }
      }
    }
    return out;
  }

  /// سلسلة المراسلات: كل الرسائل المرتبطة بهذه الرسالة عبر الإشارات
  /// (في الاتجاهين، بما فيها الرسائل التي تشترك معها في وارد واحد).
  Future<List<Map<String, dynamic>>> getThread(int letterId,
      {int limit = 50}) async {
    final d = await db;
    final seenOut = <int>{letterId};
    final seenIn = <int>{};
    final frontier = <int>[letterId];
    while (frontier.isNotEmpty && seenOut.length + seenIn.length < limit) {
      final lid = frontier.removeLast();
      // ما تشير إليه هذه الرسالة
      for (final row in await d.query('letter_references',
          columns: ['ref_type', 'ref_id'],
          where: 'letter_id = ?',
          whereArgs: [lid])) {
        final rid = row['ref_id'] as int;
        if (row['ref_type'] == 'outgoing') {
          if (seenOut.add(rid)) frontier.add(rid);
        } else if (seenIn.add(rid)) {
          // رسائل أخرى تشير إلى نفس الوارد تنتمي لنفس القضية
          for (final r2 in await d.query('letter_references',
              columns: ['letter_id'],
              where: "ref_type = 'incoming' AND ref_id = ?",
              whereArgs: [rid])) {
            final l2 = r2['letter_id'] as int;
            if (seenOut.add(l2)) frontier.add(l2);
          }
        }
      }
      // الرسائل التي تشير إلى هذه الرسالة
      for (final row in await d.query('letter_references',
          columns: ['letter_id'],
          where: "ref_type = 'outgoing' AND ref_id = ?",
          whereArgs: [lid])) {
        final l2 = row['letter_id'] as int;
        if (seenOut.add(l2)) frontier.add(l2);
      }
    }

    final items = <Map<String, dynamic>>[];
    for (final lid in seenOut) {
      final rows = await d.query('letters',
          columns: ['id', 'ref_number', 'date_greg', 'subject', 'recipient', 'status'],
          where: 'id = ?',
          whereArgs: [lid]);
      if (rows.isNotEmpty) {
        items.add({
          'kind': 'outgoing',
          'current': lid == letterId,
          ...rows.first,
        });
      }
    }
    for (final iid in seenIn) {
      final rows = await d.query('incoming_letters',
          columns: ['id', 'ref_number', 'date_greg', 'subject', 'sender'],
          where: 'id = ?',
          whereArgs: [iid]);
      if (rows.isNotEmpty) {
        final m = Map<String, dynamic>.from(rows.first);
        m['recipient'] = m.remove('sender');
        items.add({'kind': 'incoming', 'current': false, ...m});
      }
    }
    items.sort((a, b) {
      final byDate = ((a['date_greg'] ?? '') as String)
          .compareTo((b['date_greg'] ?? '') as String);
      return byDate != 0 ? byDate : (a['id'] as int).compareTo(b['id'] as int);
    });
    return items;
  }

  // ---------- القوالب ----------

  Future<List<Map<String, dynamic>>> listTemplates() async {
    final d = await db;
    return d.rawQuery('''
      SELECT t.id, t.name, t.letter_type, t.tone, t.recipient,
             t.entity_id, t.created_at, e.name AS entity_name
      FROM templates t LEFT JOIN entities e ON e.id = t.entity_id
      ORDER BY t.name''');
  }

  Future<Map<String, dynamic>?> getTemplate(int id) async {
    final d = await db;
    final rows = await d.query('templates', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final t = Map<String, dynamic>.from(rows.first);
    try {
      t['doc'] = jsonDecode(t.remove('doc_json') as String);
    } catch (_) {
      t['doc'] = <String, dynamic>{};
    }
    return t;
  }

  Future<Map<String, dynamic>> createTemplate(
      Map<String, dynamic> data) async {
    final d = await db;
    final id = await d.insert('templates', {
      'name': data['name'],
      'entity_id': data['entity_id'],
      'letter_type': data['letter_type'] ?? 'عام',
      'tone': data['tone'] ?? 'رسمية محايدة',
      'recipient': data['recipient'] ?? '',
      'doc_json': data['doc_json'],
      'created_at': _now(),
    });
    return (await getTemplate(id))!;
  }

  Future<void> deleteTemplate(int id) async {
    final d = await db;
    await d.delete('templates', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- النسخ الاحتياطي والاستيراد ----------

  /// نسخة احتياطية: يغلق القاعدة وينسخ ملفها إلى مجلد الإخراج ويعيد المسار.
  Future<String> exportBackup() async {
    final src = await dbPath();
    final dir = await outputDir();
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:T]'), '-')
        .split('.')
        .first;
    final dest = p.join(dir.path, 'correspondence-backup-$ts.db');
    await close();
    await File(src).copy(dest);
    return dest;
  }

  /// استيراد قاعدة (من هذا التطبيق أو من نسخة سطح المكتب diwan.db):
  /// يتحقق من البنية، يحفظ نسخة أمان من القاعدة الحالية، ثم يستبدلها.
  /// الترحيلات (الأعمدة المستحدثة) تُطبَّق تلقائيًا عند إعادة الفتح.
  Future<void> importBackup(String srcPath) async {
    // التحقق: ملف SQLite يحوي جدولي الرسائل والمنشآت على الأقل
    Database candidate;
    try {
      candidate = await openReadOnlyDatabase(srcPath);
    } catch (_) {
      throw const FormatException('الملف ليس قاعدة بيانات SQLite صالحة');
    }
    try {
      final tables = {
        for (final r in await candidate.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table'"))
          r['name'] as String
      };
      if (!tables.contains('letters') || !tables.contains('entities')) {
        throw const FormatException(
            'القاعدة لا تحوي جداول النظام (letters/entities) — '
            'اختر ملف diwan.db أو نسخة احتياطية من هذا التطبيق');
      }
    } finally {
      await candidate.close();
    }

    final main = await dbPath();
    await close();
    // نسخة أمان من القاعدة الحالية قبل الاستبدال
    final dir = await outputDir();
    final ts = DateTime.now().millisecondsSinceEpoch;
    if (await File(main).exists()) {
      await File(main).copy(p.join(dir.path, 'safety-before-import-$ts.db'));
    }
    await File(srcPath).copy(main);
    await db; // إعادة الفتح فورًا لتطبيق الترحيلات
  }
}
