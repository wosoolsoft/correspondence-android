/// الأرشيف: تبويبا الصادر (رسائل النظام) والوارد (كتب الجهات المسجّلة).
library;

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../utils/dates.dart';
import 'editor_screen.dart';
import 'inbox_tab.dart';

class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الأرشيف'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'الصادر'),
              Tab(text: 'الوارد'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [OutgoingTab(), InboxTab()],
        ),
      ),
    );
  }
}

class OutgoingTab extends StatefulWidget {
  const OutgoingTab({super.key});

  @override
  State<OutgoingTab> createState() => _OutgoingTabState();
}

class _OutgoingTabState extends State<OutgoingTab>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _letters = [];
  List<Map<String, dynamic>> _entities = [];
  int? _entityFilter;
  String _statusFilter = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final letters = await AppDb.instance.listLetters(
      search: _searchCtrl.text.trim(),
      entityId: _entityFilter,
      status: _statusFilter,
    );
    final entities = await AppDb.instance.listEntities(includeInactive: true);
    if (!mounted) return;
    setState(() {
      _letters = letters;
      _entities = entities;
    });
  }

  Future<void> _delete(Map<String, dynamic> letter) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الرسالة'),
        content: Text('هل تريد حذف الرسالة «${letter['subject'] ?? ''}» نهائيًا؟ '
            'لا يمكن التراجع عن الحذف.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppDb.instance.deleteLetter(letter['id'] as int);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('الكل'),
                  selected: _statusFilter.isEmpty,
                  onSelected: (_) {
                    setState(() => _statusFilter = '');
                    _load();
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('مسودة'),
                  selected: _statusFilter == 'draft',
                  onSelected: (_) {
                    setState(() => _statusFilter = 'draft');
                    _load();
                  },
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('نهائية'),
                  selected: _statusFilter == 'final',
                  onSelected: (_) {
                    setState(() => _statusFilter = 'final');
                    _load();
                  },
                ),
                const SizedBox(width: 12),
                DropdownButton<int?>(
                  value: _entityFilter,
                  hint: const Text('كل المنشآت'),
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('كل المنشآت')),
                    for (final e in _entities)
                      DropdownMenuItem(
                        value: e['id'] as int,
                        child: Text((e['name'] ?? '') as String,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _entityFilter = v);
                    _load();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _letters.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('لا توجد رسائل بعد')),
                    ],
                  )
                : ListView.builder(
                    itemCount: _letters.length,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemBuilder: (context, i) {
                      final l = _letters[i];
                      final isFinal = l['status'] == 'final';
                      final subject = ((l['subject'] as String?) ?? '')
                          .replaceFirst(RegExp(r'^الموضوع\s*[:/]\s*'), '');
                      DateTime? d;
                      try {
                        d = DateTime.parse(l['date_greg'] as String);
                      } catch (_) {}
                      return Card(
                        child: ListTile(
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    EditorScreen(letterId: l['id'] as int),
                              ),
                            );
                            _load();
                          },
                          leading: Icon(
                            isFinal
                                ? Icons.verified_outlined
                                : Icons.edit_note,
                            color: isFinal
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.secondary,
                          ),
                          title: Text(
                            subject.isEmpty ? 'بدون موضوع' : subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            [
                              if ((l['ref_number'] as String?)?.isNotEmpty ==
                                  true)
                                'المرجع ${l['ref_number']}',
                              if ((l['recipient'] as String?)?.isNotEmpty ==
                                  true)
                                l['recipient'] as String,
                              if (d != null) gregorianString(d),
                            ].join(' • '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(l),
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
