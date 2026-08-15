/// إدارة المنشآت: الاسم والموقّع والتحية والخاتمة وصورة الترويسة.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../data/db.dart';
import 'letterhead_designer_screen.dart';

class EntitiesScreen extends StatefulWidget {
  const EntitiesScreen({super.key});

  @override
  State<EntitiesScreen> createState() => _EntitiesScreenState();
}

class _EntitiesScreenState extends State<EntitiesScreen> {
  List<Map<String, dynamic>> _entities = [];
  Directory? _lhDir;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entities = await AppDb.instance.listEntities(includeInactive: true);
    final dir = await AppDb.instance.letterheadsDir();
    if (!mounted) return;
    setState(() {
      _entities = entities;
      _lhDir = dir;
    });
  }

  String? _letterheadPath(Map<String, dynamic> e) {
    final lh = (e['letterhead'] as String?) ?? '';
    if (lh.isEmpty || _lhDir == null) return null;
    final path = p.join(_lhDir!.path, lh);
    return File(path).existsSync() ? path : null;
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنشأة'),
        content: Text('حذف «${e['name']}»؟ إن كانت لها رسائل محفوظة '
            'فستُعطَّل فقط حفاظًا على الأرشيف.'),
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
    if (ok != true) return;
    final result = await AppDb.instance.deleteEntity(e['id'] as int);
    if (!mounted) return;
    if (result['deactivated'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('للمنشأة ${result['letters']} رسالة — '
            'عُطّلت بدلًا من حذفها ويمكن إعادة تفعيلها.'),
      ));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المنشآت')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const EntityFormScreen()));
          _load();
        },
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('منشأة'),
      ),
      body: _entities.isEmpty
          ? const Center(child: Text('لا توجد منشآت — أضف الأولى'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _entities.length,
              itemBuilder: (context, i) {
                final e = _entities[i];
                final active = e['active'] == 1;
                final lhPath = _letterheadPath(e);
                return Card(
                  child: ListTile(
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => EntityFormScreen(entity: e)));
                      _load();
                    },
                    leading: lhPath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(File(lhPath),
                                width: 44, height: 44, fit: BoxFit.cover),
                          )
                        : const Icon(Icons.business_outlined, size: 36),
                    title: Text((e['name'] ?? '') as String,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: active
                              ? null
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: .45),
                        )),
                    subtitle: Text([
                      if (((e['signer_name'] as String?) ?? '').isNotEmpty)
                        '${e['signer_title']} / ${e['signer_name']}'
                      else if (((e['signer_title'] as String?) ?? '')
                          .isNotEmpty)
                        e['signer_title'] as String,
                      if (!active) 'معطَّلة',
                    ].join(' • ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(e),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class EntityFormScreen extends StatefulWidget {
  final Map<String, dynamic>? entity;
  const EntityFormScreen({super.key, this.entity});

  @override
  State<EntityFormScreen> createState() => _EntityFormScreenState();
}

class _EntityFormScreenState extends State<EntityFormScreen> {
  late final _name =
      TextEditingController(text: (widget.entity?['name'] ?? '') as String);
  late final _nameEn =
      TextEditingController(text: (widget.entity?['name_en'] ?? '') as String);
  late final _signerTitle = TextEditingController(
      text: (widget.entity?['signer_title'] ?? 'المدير العام') as String);
  late final _signerName = TextEditingController(
      text: (widget.entity?['signer_name'] ?? '') as String);
  late final _greeting = TextEditingController(
      text: (widget.entity?['default_greeting'] ?? 'تحية طيبة وبعد،')
          as String);
  late final _closing = TextEditingController(
      text: (widget.entity?['default_closing'] ?? 'وتقبلوا خالص التحايا،،،')
          as String);
  String _letterhead = '';
  String? _letterheadFullPath;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    _letterhead = (widget.entity?['letterhead'] ?? '') as String;
    _active = widget.entity == null || widget.entity!['active'] == 1;
    _resolveLetterheadPath();
  }

  Future<void> _resolveLetterheadPath() async {
    if (_letterhead.isEmpty) return;
    final dir = await AppDb.instance.letterheadsDir();
    final path = p.join(dir.path, _letterhead);
    if (File(path).existsSync() && mounted) {
      setState(() => _letterheadFullPath = path);
    }
  }

  Future<void> _openDesigner() async {
    // أحدث بيانات المنشأة من القاعدة (قد تكون عدّلت الترويسة سابقًا)
    final entity =
        await AppDb.instance.getEntity(widget.entity!['id'] as int);
    if (entity == null || !mounted) return;
    final fileName = await Navigator.of(context).push<String>(
      MaterialPageRoute(
          builder: (_) => LetterheadDesignerScreen(entity: entity)),
    );
    if (fileName != null) {
      setState(() => _letterhead = fileName);
      await _resolveLetterheadPath();
    }
  }

  Future<void> _pickLetterhead() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final dir = await AppDb.instance.letterheadsDir();
    final ext = p.extension(picked.path).isEmpty ? '.png' : p.extension(picked.path);
    final name = 'lh_${DateTime.now().millisecondsSinceEpoch}$ext';
    final dest = p.join(dir.path, name);
    await File(picked.path).copy(dest);
    setState(() {
      _letterhead = name;
      _letterheadFullPath = dest;
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اسم المنشأة مطلوب')));
      return;
    }
    final data = {
      'name': _name.text.trim(),
      'name_en': _nameEn.text.trim(),
      'signer_title': _signerTitle.text.trim(),
      'signer_name': _signerName.text.trim(),
      'default_greeting': _greeting.text.trim(),
      'default_closing': _closing.text.trim(),
      'letterhead': _letterhead,
      'active': _active ? 1 : 0,
    };
    if (widget.entity == null) {
      await AppDb.instance.createEntity(data);
    } else {
      await AppDb.instance.updateEntity(widget.entity!['id'] as int, data);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entity == null ? 'منشأة جديدة' : 'تعديل المنشأة'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'اسم المنشأة'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameEn,
            decoration:
                const InputDecoration(labelText: 'الاسم بالإنجليزية (اختياري)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _signerTitle,
            decoration: const InputDecoration(labelText: 'صفة الموقّع'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _signerName,
            decoration: const InputDecoration(labelText: 'اسم الموقّع'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _greeting,
            decoration: const InputDecoration(labelText: 'التحية الافتراضية'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _closing,
            decoration: const InputDecoration(labelText: 'الخاتمة الافتراضية'),
          ),
          if (widget.entity != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('منشأة فعّالة'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          const SizedBox(height: 14),
          Text('الترويسة (صورة صفحة كاملة تُطبع خلف النص)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .75),
              )),
          const SizedBox(height: 8),
          if (_letterheadFullPath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(_letterheadFullPath!),
                  height: 220, fit: BoxFit.contain),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _pickLetterhead,
                icon: const Icon(Icons.image_outlined),
                label: Text(_letterhead.isEmpty
                    ? 'رفع ترويسة جاهزة'
                    : 'استبدال الترويسة'),
              ),
              if (widget.entity != null)
                FilledButton.tonalIcon(
                  onPressed: _openDesigner,
                  icon: const Icon(Icons.palette_outlined),
                  label: const Text('🎨 تصميم الترويسة'),
                ),
              if (_letterhead.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    _letterhead = '';
                    _letterheadFullPath = null;
                  }),
                  child: const Text('إزالة'),
                ),
            ],
          ),
          if (widget.entity == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'احفظ المنشأة أولًا ثم افتحها لتصميم ترويسة احترافية '
                'من بياناتها بمصمّم الترويسة المدمج.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .6),
                ),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
