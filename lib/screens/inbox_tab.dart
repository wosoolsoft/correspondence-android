/// سجل الوارد: تسجيل الكتب الواردة من الجهات — للإشارة إليها في الردود
/// («بالإشارة إلى كتابكم رقم…») ولبناء ملف مراسلات متكامل لكل قضية.
library;

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../utils/dates.dart';

class InboxTab extends StatefulWidget {
  const InboxTab({super.key});

  @override
  State<InboxTab> createState() => _InboxTabState();
}

class _InboxTabState extends State<InboxTab>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items =
        await AppDb.instance.listIncoming(search: _searchCtrl.text.trim());
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الوارد'),
        content: Text('حذف الكتاب الوارد «${item['subject'] ?? ''}»؟ '
            'ستُزال أيضًا إشارات الرسائل الصادرة إليه.'),
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
      await AppDb.instance.deleteIncoming(item['id'] as int);
      _load();
    }
  }

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => IncomingFormScreen(incoming: item)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'inbox_fab',
        onPressed: () => _openForm(),
        icon: const Icon(Icons.move_to_inbox_outlined),
        label: const Text('كتاب وارد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'بحث بالموضوع أو الجهة أو المرجع…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _load();
                        },
                      ),
              ),
              onChanged: (_) => _load(),
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text('لا كتب واردة بعد — سجّل الوارد هنا '
                        'لتشير إليه في ردودك'))
                : ListView.builder(
                    itemCount: _items.length,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      DateTime? d;
                      try {
                        d = DateTime.parse(item['date_greg'] as String);
                      } catch (_) {}
                      return Card(
                        child: ListTile(
                          onTap: () => _openForm(item),
                          leading: Icon(Icons.mark_email_unread_outlined,
                              color: Theme.of(context).colorScheme.secondary),
                          title: Text(
                            ((item['subject'] as String?) ?? '').isEmpty
                                ? 'بدون موضوع'
                                : item['subject'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            [
                              if ((item['sender'] as String?)?.isNotEmpty ==
                                  true)
                                'من: ${item['sender']}',
                              if ((item['ref_number'] as String?)
                                      ?.isNotEmpty ==
                                  true)
                                'مرجعهم ${item['ref_number']}',
                              if (d != null) gregorianString(d),
                            ].join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(item),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class IncomingFormScreen extends StatefulWidget {
  final Map<String, dynamic>? incoming;
  const IncomingFormScreen({super.key, this.incoming});

  @override
  State<IncomingFormScreen> createState() => _IncomingFormScreenState();
}

class _IncomingFormScreenState extends State<IncomingFormScreen> {
  late final _sender = TextEditingController(
      text: (widget.incoming?['sender'] ?? '') as String);
  late final _refNumber = TextEditingController(
      text: (widget.incoming?['ref_number'] ?? '') as String);
  late final _subject = TextEditingController(
      text: (widget.incoming?['subject'] ?? '') as String);
  late final _summary = TextEditingController(
      text: (widget.incoming?['summary'] ?? '') as String);

  List<Map<String, dynamic>> _entities = [];
  int? _entityId;
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    _entityId = widget.incoming?['entity_id'] as int?;
    final dg = (widget.incoming?['date_greg'] as String?) ?? '';
    if (dg.isNotEmpty) {
      try {
        _date = DateTime.parse(dg);
      } catch (_) {}
    }
    _loadEntities();
  }

  Future<void> _loadEntities() async {
    final entities = await AppDb.instance.listEntities();
    if (!mounted) return;
    setState(() {
      _entities = entities;
      _entityId ??= entities.isNotEmpty ? entities.first['id'] as int : null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_entityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('أضف منشأة من صفحة «المنشآت» أولًا')));
      return;
    }
    if (_sender.text.trim().isEmpty && _subject.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('أدخل الجهة المرسِلة أو الموضوع على الأقل')));
      return;
    }
    final data = {
      'entity_id': _entityId,
      'sender': _sender.text.trim(),
      'ref_number': _refNumber.text.trim(),
      'date_greg':
          _date == null ? '' : _date!.toIso8601String().split('T').first,
      'subject': _subject.text.trim(),
      'summary': _summary.text.trim(),
    };
    if (widget.incoming == null) {
      await AppDb.instance.createIncoming(data);
    } else {
      await AppDb.instance
          .updateIncoming(widget.incoming!['id'] as int, data);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.incoming == null ? 'كتاب وارد جديد' : 'تعديل الوارد'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<int>(
            initialValue: _entityId,
            decoration:
                const InputDecoration(labelText: 'المنشأة المستلِمة (نحن)'),
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
          const SizedBox(height: 10),
          TextField(
            controller: _sender,
            decoration:
                const InputDecoration(labelText: 'الجهة المرسِلة (منهم)'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _refNumber,
                  decoration: const InputDecoration(labelText: 'مرجعهم'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(
                      _date == null ? 'تاريخ كتابهم' : gregorianString(_date!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'الموضوع'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _summary,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'ملخص المحتوى',
              hintText: 'يظهر للذكاء الاصطناعي عند الإشارة إلى هذا الكتاب '
                  'في ردودك — كلما كان أدق كان الرد ألزم بالوقائع',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      ),
    );
  }
}
