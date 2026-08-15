/// الجهات المستلمة: دفتر عناوين مع لقب المخاطبة وصيغة الاحترام لكل جهة.
library;

import 'package:flutter/material.dart';

import '../data/db.dart';

const _honorifics = [
  'الأخوة /', 'الأخ /', 'الأستاذ القدير /', 'معالي /', 'سعادة /',
];
const _suffixes = ['المحترمون', 'المحتـرم', 'المحترمة'];

class RecipientsScreen extends StatefulWidget {
  const RecipientsScreen({super.key});

  @override
  State<RecipientsScreen> createState() => _RecipientsScreenState();
}

class _RecipientsScreenState extends State<RecipientsScreen> {
  List<Map<String, dynamic>> _recipients = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final recipients = await AppDb.instance.listRecipients();
    if (!mounted) return;
    setState(() => _recipients = recipients);
  }

  Future<void> _edit([Map<String, dynamic>? r]) async {
    final name = TextEditingController(text: (r?['name'] ?? '') as String);
    final honorific =
        TextEditingController(text: (r?['honorific'] ?? 'الأخوة /') as String);
    final suffix =
        TextEditingController(text: (r?['suffix'] ?? 'المحترمون') as String);
    final notes = TextEditingController(text: (r?['notes'] ?? '') as String);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r == null ? 'جهة جديدة' : 'تعديل الجهة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'اسم الجهة'),
              ),
              const SizedBox(height: 10),
              DropdownMenu<String>(
                controller: honorific,
                requestFocusOnTap: true,
                label: const Text('لقب المخاطبة'),
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: [
                  for (final h in _honorifics)
                    DropdownMenuEntry(value: h, label: h),
                ],
              ),
              const SizedBox(height: 10),
              DropdownMenu<String>(
                controller: suffix,
                requestFocusOnTap: true,
                label: const Text('صيغة الاحترام'),
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: [
                  for (final s in _suffixes)
                    DropdownMenuEntry(value: s, label: s),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    if (name.text.trim().isEmpty) return;
    final data = {
      'name': name.text.trim(),
      'honorific': honorific.text.trim(),
      'suffix': suffix.text.trim(),
      'notes': notes.text.trim(),
    };
    if (r == null) {
      await AppDb.instance.createRecipient(data);
    } else {
      await AppDb.instance.updateRecipient(r['id'] as int, data);
    }
    _load();
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الجهة'),
        content: Text('حذف «${r['name']}»؟ رسائلها المؤرشفة تحتفظ '
            'بالاسم نصًا فلا تتأثر.'),
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
      await AppDb.instance.deleteRecipient(r['id'] as int);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الجهات المستلمة')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add_alt_outlined),
        label: const Text('جهة'),
      ),
      body: _recipients.isEmpty
          ? const Center(
              child: Text('لا توجد جهات بعد — تُحفظ الجهات الجديدة '
                  'تلقائيًا عند التوليد'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _recipients.length,
              itemBuilder: (context, i) {
                final r = _recipients[i];
                final count = (r['letters_count'] as int?) ?? 0;
                return Card(
                  child: ListTile(
                    onTap: () => _edit(r),
                    leading: const Icon(Icons.apartment_outlined),
                    title: Text((r['name'] ?? '') as String,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text([
                      '${r['honorific']} … ${r['suffix']}',
                      if (count > 0) '$count رسالة',
                    ].join(' • ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(r),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
