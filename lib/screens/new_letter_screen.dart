/// شاشة «رسالة جديدة»: المنشأة، الجهة، النوع، الحدّة، المضمون — ثم التوليد.
library;

import 'package:flutter/material.dart';

import '../ai/ai_client.dart' show AIError, tones, defaultTone;
import '../data/db.dart';
import '../services/letter_service.dart';
import '../widgets/references_picker.dart';
import 'editor_screen.dart';

const _letterTypes = [
  'عام', 'طلب', 'إشعار تحويل', 'تفويض', 'إلغاء تفويض',
  'رد', 'تذكير', 'شكر', 'اعتذار', 'مطالبة',
];

class NewLetterScreen extends StatefulWidget {
  const NewLetterScreen({super.key});

  @override
  State<NewLetterScreen> createState() => _NewLetterScreenState();
}

class _NewLetterScreenState extends State<NewLetterScreen> {
  final _recipientCtrl = TextEditingController();
  final _typeCtrl = TextEditingController(text: 'عام');
  final _greetingCtrl = TextEditingController();
  final _briefCtrl = TextEditingController();

  List<Map<String, dynamic>> _entities = [];
  List<String> _recipientNames = [];
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _refs = [];
  int? _entityId;
  String _tone = defaultTone;
  bool _useHijri = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entities = await AppDb.instance.listEntities();
    final recipients = await AppDb.instance.listRecipients();
    final templates = await AppDb.instance.listTemplates();
    if (!mounted) return;
    setState(() {
      _entities = entities;
      _recipientNames =
          [for (final r in recipients) (r['name'] ?? '') as String];
      _templates = templates;
      _entityId ??= entities.isNotEmpty ? entities.first['id'] as int : null;
    });
  }

  Future<void> _pickReferences() async {
    final picked = await showReferencesPicker(context, initial: _refs);
    if (picked != null) setState(() => _refs = picked);
  }

  Future<void> _createFromTemplate(Map<String, dynamic> template) async {
    setState(() => _busy = true);
    try {
      final letter = await LetterService.instance
          .createFromTemplate(template['id'] as int);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EditorScreen(letterId: letter['id'] as int),
      ));
      _load();
    } on ServiceError catch (e) {
      _snack(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTemplate(Map<String, dynamic> template) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف القالب'),
        content: Text('حذف القالب «${template['name']}»؟'),
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
      await AppDb.instance.deleteTemplate(template['id'] as int);
      _load();
    }
  }

  Future<void> _generate({required bool demo}) async {
    final entityId = _entityId;
    if (entityId == null) {
      _snack('أضف منشأة من صفحة «المنشآت» أولًا', error: true);
      return;
    }
    if (_briefCtrl.text.trim().isEmpty && !demo) {
      _snack('اكتب مضمون الرسالة أولًا', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final letter = await LetterService.instance.generate(
        entityId: entityId,
        brief: _briefCtrl.text,
        recipient: _recipientCtrl.text,
        letterType: _typeCtrl.text.trim().isEmpty ? 'عام' : _typeCtrl.text.trim(),
        tone: _tone,
        greeting: _greetingCtrl.text.trim(),
        useHijri: _useHijri,
        demo: demo,
        references: [
          for (final r in _refs) {'type': r['type'], 'id': r['id']}
        ],
      );
      if (!mounted) return;
      _briefCtrl.clear();
      setState(() => _refs = []);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EditorScreen(letterId: letter['id'] as int),
      ));
      _load(); // الجهات الجديدة تُحفظ تلقائيًا — حدّث الاقتراحات
    } on AIError catch (e) {
      _snack(e.message, error: true);
    } on ServiceError catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('حدث خطأ غير متوقع: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    return Scaffold(
      appBar: AppBar(title: const Text('رسالة جديدة')),
      body: _entities.isEmpty
          ? _emptyState()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_templates.isNotEmpty) ...[
                  _label('💠 قوالبك المحفوظة — إنشاء فوري دون ذكاء اصطناعي'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final t in _templates)
                        InputChip(
                          avatar: const Icon(Icons.copy_all_outlined, size: 16),
                          label: Text((t['name'] ?? '') as String),
                          onPressed:
                              _busy ? null : () => _createFromTemplate(t),
                          onDeleted: () => _deleteTemplate(t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                _label('المنشأة المرسِلة'),
                DropdownButtonFormField<int>(
                  initialValue: _entityId,
                  items: [
                    for (final e in _entities)
                      DropdownMenuItem(
                        value: e['id'] as int,
                        child: Text((e['name'] ?? '') as String,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _entityId = v),
                ),
                const SizedBox(height: 12),
                _label('الجهة المستلمة'),
                Autocomplete<String>(
                  optionsBuilder: (t) {
                    final q = t.text.trim();
                    if (q.isEmpty) return const Iterable<String>.empty();
                    return _recipientNames.where((n) => n.contains(q));
                  },
                  onSelected: (v) => _recipientCtrl.text = v,
                  fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                    ctrl.addListener(() => _recipientCtrl.text = ctrl.text);
                    return TextField(
                      controller: ctrl,
                      focusNode: focus,
                      decoration: const InputDecoration(
                          hintText: 'مثل: البنك المركزي — تُحفظ تلقائيًا'),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _label('نوع الرسالة'),
                DropdownMenu<String>(
                  controller: _typeCtrl,
                  requestFocusOnTap: true,
                  enableFilter: false,
                  expandedInsets: EdgeInsets.zero,
                  dropdownMenuEntries: [
                    for (final t in _letterTypes)
                      DropdownMenuEntry(value: t, label: t),
                  ],
                ),
                const SizedBox(height: 12),
                _label('حدّة الرسالة'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in tones.keys)
                      ChoiceChip(
                        label: Text(t),
                        selected: _tone == t,
                        onSelected: (_) => setState(() => _tone = t),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _label('التحية (اختياري)'),
                TextField(
                  controller: _greetingCtrl,
                  decoration: const InputDecoration(
                      hintText: 'الافتراضي: تحية المنشأة المحفوظة'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إظهار التاريخ الهجري مع الميلادي'),
                  value: _useHijri,
                  onChanged: (v) => setState(() => _useHijri = v),
                ),
                _label('الإشارة إلى مراسلات سابقة (اختياري)'),
                if (_refs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final r in _refs)
                          InputChip(
                            avatar: Icon(
                              r['type'] == 'outgoing'
                                  ? Icons.call_made
                                  : Icons.call_received,
                              size: 16,
                            ),
                            label: Text(
                              (r['label'] ?? '') as String,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onDeleted: () =>
                                setState(() => _refs.remove(r)),
                          ),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickReferences,
                  icon: const Icon(Icons.link),
                  label: Text(_refs.isEmpty
                      ? 'اختيار مراسلات للإشارة إليها'
                      : 'تعديل الإشارات (${_refs.length})'),
                ),
                const SizedBox(height: 12),
                _label('مضمون الرسالة'),
                TextField(
                  controller: _briefCtrl,
                  maxLines: 7,
                  decoration: const InputDecoration(
                    hintText: 'اكتب الوقائع والمبالغ والتواريخ والمطلوب '
                        'بلغتك العادية…',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _generate(demo: false),
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_busy ? 'جارٍ التوليد…' : 'توليد بالذكاء الاصطناعي'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _generate(demo: true),
                  icon: const Icon(Icons.bolt_outlined),
                  label: const Text('توليد تجريبي (بدون ذكاء اصطناعي)'),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.business_outlined, size: 56),
              const SizedBox(height: 12),
              const Text('لا توجد منشآت بعد',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('أضف منشأتك (الاسم والموقّع والترويسة) '
                  'من صفحة «المنشآت» ثم عد لإنشاء أول رسالة.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('تحديث')),
            ],
          ),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .75),
            )),
      );
}
