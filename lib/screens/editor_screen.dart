/// محرر الرسالة: تحرير كل الحقول والكتل، التنقيح بالذكاء،
/// معاينة PDF، والتصدير والمشاركة.
library;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../ai/ai_client.dart' show AIError;
import '../data/db.dart';
import '../models/letter_doc.dart';
import '../services/letter_service.dart';
import '../utils/dates.dart';

sealed class _EditBlock {
  void dispose();
}

class _ParaEdit extends _EditBlock {
  final TextEditingController ctrl;
  _ParaEdit(String text) : ctrl = TextEditingController(text: text);
  @override
  void dispose() => ctrl.dispose();
}

class _BulletsEdit extends _EditBlock {
  final List<TextEditingController> items;
  _BulletsEdit(List<String> texts)
      : items = [for (final t in texts) TextEditingController(text: t)];
  @override
  void dispose() {
    for (final c in items) {
      c.dispose();
    }
  }
}

class _TableEdit extends _EditBlock {
  final List<TextEditingController> header;
  final List<List<TextEditingController>> rows;
  _TableEdit(List<String> h, List<List<String>> r)
      : header = [for (final t in h) TextEditingController(text: t)],
        rows = [
          for (final row in r)
            [for (final c in row) TextEditingController(text: c)]
        ];
  int get cols {
    var m = header.length;
    for (final r in rows) {
      if (r.length > m) m = r.length;
    }
    return m == 0 ? 1 : m;
  }

  @override
  void dispose() {
    for (final c in header) {
      c.dispose();
    }
    for (final r in rows) {
      for (final c in r) {
        c.dispose();
      }
    }
  }
}

class EditorScreen extends StatefulWidget {
  final int letterId;
  const EditorScreen({super.key, required this.letterId});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  Map<String, dynamic>? _letter;
  Map<String, dynamic>? _entity;
  List<Map<String, dynamic>> _references = [];
  List<Map<String, dynamic>> _thread = [];

  final _subjectCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  final _greetingCtrl = TextEditingController();
  final _closingCtrl = TextEditingController();
  List<TextEditingController> _recipientCtrls = [];
  List<_EditBlock> _blocks = [];
  DateTime _date = DateTime.now();
  bool _useHijri = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _refCtrl.dispose();
    _greetingCtrl.dispose();
    _closingCtrl.dispose();
    _disposeDocControllers();
    super.dispose();
  }

  void _disposeDocControllers() {
    for (final c in _recipientCtrls) {
      c.dispose();
    }
    for (final b in _blocks) {
      b.dispose();
    }
  }

  Future<void> _load() async {
    final letter = await AppDb.instance.getLetter(widget.letterId);
    if (letter == null || !mounted) return;
    final entity = await AppDb.instance.getEntity(letter['entity_id'] as int);
    final references =
        await AppDb.instance.getLetterReferences(widget.letterId);
    final thread = await AppDb.instance.getThread(widget.letterId);
    final doc = LetterDoc.normalize(letter['doc']);
    _disposeDocControllers();
    setState(() {
      _letter = letter;
      _entity = entity;
      _references = references;
      _thread = thread;
      _subjectCtrl.text = doc.subject;
      _refCtrl.text = (letter['ref_number'] as String?) ?? '';
      _greetingCtrl.text = doc.greeting;
      _closingCtrl.text = doc.closing;
      _recipientCtrls = [
        for (final l in doc.recipientLines) TextEditingController(text: l)
      ];
      _blocks = [
        for (final b in doc.body)
          switch (b) {
            ParagraphBlock() => _ParaEdit(b.text),
            BulletsBlock() => _BulletsEdit(b.items),
            TableBlock() => _TableEdit(b.header, b.rows),
          }
      ];
      _useHijri = letter['use_hijri'] == 1;
      try {
        _date = DateTime.parse(letter['date_greg'] as String);
      } catch (_) {
        _date = DateTime.now();
      }
    });
  }

  LetterDoc _collectDoc() => LetterDoc(
        subject: _subjectCtrl.text.trim(),
        recipientLines: [
          for (final c in _recipientCtrls)
            if (c.text.trim().isNotEmpty) c.text.trim()
        ],
        greeting: _greetingCtrl.text.trim(),
        closing: _closingCtrl.text.trim(),
        body: [
          for (final b in _blocks)
            switch (b) {
              _ParaEdit() when b.ctrl.text.trim().isNotEmpty =>
                ParagraphBlock(b.ctrl.text.trim()),
              _BulletsEdit() when b.items.any((c) => c.text.trim().isNotEmpty) =>
                BulletsBlock([
                  for (final c in b.items)
                    if (c.text.trim().isNotEmpty) c.text.trim()
                ]),
              _TableEdit() => TableBlock(
                  [for (final c in b.header) c.text.trim()],
                  [
                    for (final r in b.rows) [for (final c in r) c.text.trim()]
                  ],
                ),
              _ => null,
            }
        ].whereType<Block>().toList(),
      );

  Future<void> _save({bool silent = false}) async {
    final doc = _collectDoc();
    await AppDb.instance.updateLetter(widget.letterId, {
      'doc_json': doc.toJsonString(),
      'subject': doc.subject,
      'ref_number': _refCtrl.text.trim(),
      'date_greg': _date.toIso8601String().split('T').first,
      'use_hijri': _useHijri ? 1 : 0,
    });
    if (!silent) _snack('تم حفظ الرسالة');
  }

  Future<void> _preview() async {
    await _save(silent: true);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('معاينة الرسالة')),
        body: PdfPreview(
          build: (_) => LetterService.instance.buildPdf(widget.letterId),
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          pdfFileName: '${LetterService.instance.safeFilename(_letter!)}.pdf',
        ),
      ),
    ));
  }

  Future<void> _export() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('تصدير الرسالة ومشاركتها',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF'),
              subtitle: const Text('جاهز للإرسال والطباعة من أي جهاز'),
              onTap: () => Navigator.of(ctx).pop('pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Word (DOCX)'),
              subtitle: const Text('قابل للتحرير في Microsoft Word — '
                  'بنفس تنسيق نسخة سطح المكتب'),
              onTap: () => Navigator.of(ctx).pop('docx'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    setState(() => _busy = true);
    try {
      await _save(silent: true);
      if (choice == 'pdf') {
        final (path, bytes) =
            await LetterService.instance.exportPdf(widget.letterId);
        await Printing.sharePdf(
          bytes: bytes,
          filename: path.split(RegExp(r'[\\/]')).last,
        );
      } else {
        final (path, _) =
            await LetterService.instance.exportDocx(widget.letterId);
        await Share.shareXFiles([
          XFile(path,
              mimeType: 'application/vnd.openxmlformats-officedocument'
                  '.wordprocessingml.document')
        ]);
      }
      await _load();
      _snack('تم التصدير — الرسالة معتمدة نهائية الآن');
    } on ServiceError catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('تعذّر التصدير: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviseSheet() async {
    final ctrl = TextEditingController();
    final instruction = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('التنقيح بالذكاء الاصطناعي',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'مثل: اجعل النبرة أشد حزمًا، وأضف مهلة أسبوع'),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('تنقيح'),
            ),
          ],
        ),
      ),
    );
    if (instruction == null || instruction.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await _save(silent: true);
      await LetterService.instance.revise(widget.letterId, instruction);
      await _load();
      _snack('تم التنقيح');
    } on AIError catch (e) {
      _snack(e.message, error: true);
    } on ServiceError catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAsTemplate() async {
    final ctrl = TextEditingController(
        text: ((_letter?['subject'] as String?) ?? '')
            .replaceFirst(RegExp(r'^الموضوع\s*[:/]\s*'), ''));
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حفظ كقالب'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم القالب'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await _save(silent: true);
      await LetterService.instance.saveAsTemplate(widget.letterId, name);
      _snack('حُفظ القالب «${name.trim()}» — تجده في صفحة «رسالة جديدة»');
    } on ServiceError catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _deleteLetter() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الرسالة'),
        content: const Text(
            'هل تريد حذف هذه الرسالة نهائيًا؟ لا يمكن التراجع عن الحذف.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppDb.instance.deleteLetter(widget.letterId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final letter = _letter;
    if (letter == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isFinal = letter['status'] == 'final';
    return Scaffold(
      appBar: AppBar(
        title: Text(_entity?['name'] as String? ?? 'تحرير الرسالة',
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'حفظ',
            icon: const Icon(Icons.save_outlined),
            onPressed: _busy ? null : () => _save(),
          ),
          IconButton(
            tooltip: 'تنقيح بالذكاء',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: _busy ? null : _reviseSheet,
          ),
          IconButton(
            tooltip: 'معاينة PDF',
            icon: const Icon(Icons.visibility_outlined),
            onPressed: _busy ? null : _preview,
          ),
          IconButton(
            tooltip: 'تصدير ومشاركة',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: _busy ? null : _export,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'template') _saveAsTemplate();
              if (v == 'delete') _deleteLetter();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'template',
                child: ListTile(
                  leading: Icon(Icons.copy_all_outlined),
                  title: Text('حفظ كقالب'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('حذف الرسالة'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      label: Text(isFinal ? 'نهائية' : 'مسودة'),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (letter['tone'] != null)
                      Chip(
                        label: Text(letter['tone'] as String),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (letter['recipient_seq'] != null)
                      Chip(
                        label: Text(
                            'الرسالة رقم ${letter['recipient_seq']} إلى هذه الجهة'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                if (_references.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final r in _references)
                        ActionChip(
                          avatar: Icon(
                            r['type'] == 'outgoing'
                                ? Icons.call_made
                                : Icons.call_received,
                            size: 16,
                          ),
                          label: Text(
                            '${r['type'] == 'outgoing' ? 'كتابنا' : 'كتابهم'} '
                            '${(r['ref_number'] as String?)?.isNotEmpty == true ? r['ref_number'] : 'بدون مرجع'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: r['type'] == 'outgoing'
                              ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => EditorScreen(
                                          letterId: r['id'] as int)))
                              : null,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _refCtrl,
                        decoration: const InputDecoration(labelText: 'المرجع'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(gregorianString(_date)),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إظهار التاريخ الهجري'),
                  subtitle: _useHijri ? Text(hijriString(_date)) : null,
                  value: _useHijri,
                  onChanged: (v) => setState(() => _useHijri = v),
                ),
                _sectionTitle('المستلم'),
                for (var i = 0; i < _recipientCtrls.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(controller: _recipientCtrls[i]),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => setState(() {
                            _recipientCtrls.removeAt(i).dispose();
                          }),
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => setState(
                      () => _recipientCtrls.add(TextEditingController())),
                  icon: const Icon(Icons.add),
                  label: const Text('سطر مستلم'),
                ),
                _sectionTitle('التحية'),
                TextField(controller: _greetingCtrl),
                _sectionTitle('الموضوع'),
                TextField(controller: _subjectCtrl),
                _sectionTitle('المتن'),
                for (var i = 0; i < _blocks.length; i++) _blockCard(i),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _blocks.add(_ParaEdit(''))),
                      icon: const Icon(Icons.notes),
                      label: const Text('فقرة'),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(
                          () => _blocks.add(_BulletsEdit(['']))),
                      icon: const Icon(Icons.format_list_bulleted),
                      label: const Text('نقاط'),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _blocks.add(_TableEdit(
                            ['', ''],
                            [
                              ['', '']
                            ],
                          ))),
                      icon: const Icon(Icons.table_chart_outlined),
                      label: const Text('جدول'),
                    ),
                  ],
                ),
                _sectionTitle('الخاتمة'),
                TextField(controller: _closingCtrl),
                if (_thread.length > 1) ...[
                  _sectionTitle('🧵 سلسلة المراسلات'),
                  Card(
                    child: Column(
                      children: [
                        for (final item in _thread)
                          ListTile(
                            dense: true,
                            selected: item['current'] == true,
                            leading: Icon(
                              item['kind'] == 'outgoing'
                                  ? Icons.call_made
                                  : Icons.call_received,
                              size: 20,
                              color: item['kind'] == 'outgoing'
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.secondary,
                            ),
                            title: Text(
                              ((item['subject'] as String?) ?? '')
                                      .replaceFirst(
                                          RegExp(r'^الموضوع\s*[:/]\s*'), '')
                                      .trim()
                                      .isEmpty
                                  ? 'بدون موضوع'
                                  : ((item['subject'] as String?) ?? '')
                                      .replaceFirst(
                                          RegExp(r'^الموضوع\s*[:/]\s*'), ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                item['kind'] == 'outgoing'
                                    ? 'صادرة${item['current'] == true ? ' (الحالية)' : ''}'
                                    : 'واردة',
                                if ((item['ref_number'] as String?)
                                        ?.isNotEmpty ==
                                    true)
                                  'المرجع ${item['ref_number']}',
                                fmtIsoDate(item['date_greg'] as String?),
                              ].join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: item['kind'] == 'outgoing' &&
                                    item['current'] != true
                                ? () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => EditorScreen(
                                            letterId: item['id'] as int)))
                                : null,
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _blockCard(int i) {
    final b = _blocks[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  switch (b) {
                    _ParaEdit() => 'فقرة',
                    _BulletsEdit() => 'نقاط',
                    _TableEdit() => 'جدول',
                  },
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: i == 0
                      ? null
                      : () => setState(() {
                            final x = _blocks.removeAt(i);
                            _blocks.insert(i - 1, x);
                          }),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: i == _blocks.length - 1
                      ? null
                      : () => setState(() {
                            final x = _blocks.removeAt(i);
                            _blocks.insert(i + 1, x);
                          }),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => setState(() {
                    _blocks.removeAt(i).dispose();
                  }),
                ),
              ],
            ),
            switch (b) {
              _ParaEdit() => TextField(controller: b.ctrl, maxLines: null),
              _BulletsEdit() => Column(
                  children: [
                    for (var j = 0; j < b.items.length; j++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            const Text('• '),
                            Expanded(
                                child: TextField(controller: b.items[j])),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 18),
                              onPressed: () => setState(() {
                                b.items.removeAt(j).dispose();
                              }),
                            ),
                          ],
                        ),
                      ),
                    TextButton.icon(
                      onPressed: () => setState(
                          () => b.items.add(TextEditingController())),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('بند'),
                    ),
                  ],
                ),
              _TableEdit() => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        children: [
                          Row(children: [
                            for (final c in b.header) _tableCell(c, true),
                          ]),
                          for (final r in b.rows)
                            Row(children: [
                              for (final c in r) _tableCell(c, false),
                            ]),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() => b.rows.add([
                                for (var c = 0; c < b.cols; c++)
                                  TextEditingController()
                              ])),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('صف'),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            b.header.add(TextEditingController());
                            for (final r in b.rows) {
                              r.add(TextEditingController());
                            }
                          }),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('عمود'),
                        ),
                      ],
                    ),
                  ],
                ),
            },
          ],
        ),
      ),
    );
  }

  Widget _tableCell(TextEditingController c, bool isHeader) => Container(
        width: 140,
        padding: const EdgeInsets.all(2),
        child: TextField(
          controller: c,
          maxLines: null,
          style: TextStyle(
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
              fontSize: 13),
        ),
      );
}
