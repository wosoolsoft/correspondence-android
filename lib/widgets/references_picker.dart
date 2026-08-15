/// منتقي «الإشارة إلى مراسلات سابقة»: اختيار رسائل صادرة من الأرشيف
/// وكتب واردة من سجل الوارد، لتُحقن في موجّه التوليد.
library;

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../utils/dates.dart';

/// عنصر إشارة مختار: {'type': outgoing|incoming, 'id': int, 'label': نص للعرض}.
Future<List<Map<String, dynamic>>?> showReferencesPicker(
  BuildContext context, {
  List<Map<String, dynamic>> initial = const [],
}) {
  return showModalBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReferencesSheet(initial: initial),
  );
}

class _ReferencesSheet extends StatefulWidget {
  final List<Map<String, dynamic>> initial;
  const _ReferencesSheet({required this.initial});

  @override
  State<_ReferencesSheet> createState() => _ReferencesSheetState();
}

class _ReferencesSheetState extends State<_ReferencesSheet> {
  bool _showIncoming = false;
  List<Map<String, dynamic>> _outgoing = [];
  List<Map<String, dynamic>> _incoming = [];
  late final Set<(String, int)> _selected = {
    for (final r in widget.initial) (r['type'] as String, r['id'] as int)
  };
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final outgoing = await AppDb.instance.listLetters();
    final incoming = await AppDb.instance.listIncoming();
    if (!mounted) return;
    setState(() {
      _outgoing = outgoing;
      _incoming = incoming;
      _loading = false;
    });
  }

  String _labelOf(Map<String, dynamic> item, String type) {
    final ref = (item['ref_number'] as String?) ?? '';
    final subject = ((item['subject'] as String?) ?? '')
        .replaceFirst(RegExp(r'^الموضوع\s*[:/]\s*'), '');
    final prefix = type == 'outgoing' ? 'كتابنا' : 'كتابكم';
    return [
      '$prefix ${ref.isEmpty ? 'بدون مرجع' : ref}',
      if (subject.isNotEmpty) subject,
    ].join(' — ');
  }

  void _finish() {
    final result = <Map<String, dynamic>>[];
    for (final (type, id) in _selected) {
      final list = type == 'outgoing' ? _outgoing : _incoming;
      final item = list.where((x) => x['id'] == id).firstOrNull;
      if (item != null) {
        result.add({'type': type, 'id': id, 'label': _labelOf(item, type)});
      }
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final list = _showIncoming ? _incoming : _outgoing;
    final type = _showIncoming ? 'incoming' : 'outgoing';
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (context, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text('الإشارة إلى مراسلات سابقة',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                TextButton(
                  onPressed: _finish,
                  child: Text('تم (${_selected.length})'),
                ),
              ],
            ),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('صادرة من أرشيفنا')),
              ButtonSegment(value: true, label: Text('واردة إلينا')),
            ],
            selected: {_showIncoming},
            onSelectionChanged: (s) =>
                setState(() => _showIncoming = s.first),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? Center(
                        child: Text(_showIncoming
                            ? 'لا كتب واردة — سجّلها من الأرشيف ← الوارد'
                            : 'لا رسائل صادرة بعد'))
                    : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final item = list[i];
                          final id = item['id'] as int;
                          final key = (type, id);
                          final checked = _selected.contains(key);
                          DateTime? d;
                          try {
                            d = DateTime.parse(item['date_greg'] as String);
                          } catch (_) {}
                          final party = _showIncoming
                              ? (item['sender'] as String?)
                              : (item['recipient'] as String?);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(key);
                              } else {
                                _selected.remove(key);
                              }
                            }),
                            title: Text(
                              _labelOf(item, type),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: Text(
                              [
                                if (party?.isNotEmpty == true) party!,
                                if (d != null) gregorianString(d),
                              ].join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
