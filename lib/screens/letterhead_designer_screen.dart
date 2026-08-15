/// مصمّم الترويسة: يولّد ترويسة احترافية من بيانات المنشأة بثلاثة قوالب
/// ولون أساسي وشعار اختياري، مع معاينة حية — ويعتمدها ترويسةً للمنشأة.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../data/db.dart';
import '../letterhead/letterhead_renderer.dart';

class LetterheadDesignerScreen extends StatefulWidget {
  final Map<String, dynamic> entity;
  const LetterheadDesignerScreen({super.key, required this.entity});

  @override
  State<LetterheadDesignerScreen> createState() =>
      _LetterheadDesignerScreenState();
}

class _LetterheadDesignerScreenState extends State<LetterheadDesignerScreen> {
  late final _name =
      TextEditingController(text: (widget.entity['name'] ?? '') as String);
  late final _nameEn =
      TextEditingController(text: (widget.entity['name_en'] ?? '') as String);
  late final _address =
      TextEditingController(text: (widget.entity['address'] ?? '') as String);
  late final _phone =
      TextEditingController(text: (widget.entity['phone'] ?? '') as String);
  late final _email =
      TextEditingController(text: (widget.entity['email'] ?? '') as String);
  late final _website =
      TextEditingController(text: (widget.entity['website'] ?? '') as String);

  String _template = 'classic';
  Color _color = lhColors.first;
  ui.Image? _logo;
  String _logoFile = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // استرجاع التصميم المحفوظ (القالب واللون) إن وُجد
    try {
      final saved = jsonDecode(
          (widget.entity['letterhead_design'] as String?) ?? '{}');
      if (saved is Map) {
        if (lhTemplates.any((t) => t.id == saved['template'])) {
          _template = saved['template'] as String;
        }
        _color = colorFromHex(saved['color'] as String?) ?? _color;
      }
    } catch (_) {}
    _logoFile = (widget.entity['logo'] as String?) ?? '';
    _loadSavedLogo();
    for (final c in [_name, _nameEn, _address, _phone, _email, _website]) {
      c.addListener(() => setState(() {}));
    }
  }

  Future<void> _loadSavedLogo() async {
    if (_logoFile.isEmpty) return;
    final dir = await AppDb.instance.letterheadsDir();
    final f = File(p.join(dir.path, _logoFile));
    if (await f.exists()) {
      final img = await decodeImageFromList(await f.readAsBytes());
      if (mounted) setState(() => _logo = img);
    }
  }

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final img = await decodeImageFromList(bytes);
    final dir = await AppDb.instance.letterheadsDir();
    final ext =
        p.extension(picked.path).isEmpty ? '.png' : p.extension(picked.path);
    final name = 'logo_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(p.join(dir.path, name)).writeAsBytes(bytes);
    setState(() {
      _logo = img;
      _logoFile = name;
    });
  }

  LetterheadDesign get _design => LetterheadDesign(
        template: _template,
        color: _color,
        name: _name.text.trim(),
        nameEn: _nameEn.text.trim(),
        address: _address.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        website: _website.text.trim(),
        logo: _logo,
      );

  Future<void> _apply() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اسم المنشأة مطلوب للترويسة')));
      return;
    }
    setState(() => _saving = true);
    try {
      final bytes = await renderLetterheadPng(_design);
      final dir = await AppDb.instance.letterheadsDir();
      final fileName = 'lh_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(p.join(dir.path, fileName)).writeAsBytes(bytes);
      await AppDb.instance.updateEntity(widget.entity['id'] as int, {
        'name': _name.text.trim(),
        'name_en': _nameEn.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'website': _website.text.trim(),
        'letterhead': fileName,
        'logo': _logoFile,
        'letterhead_design':
            jsonEncode({'template': _template, 'color': colorToHex(_color)}),
      });
      if (!mounted) return;
      Navigator.of(context).pop(fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذّر توليد الترويسة: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎨 مصمّم الترويسة'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _apply,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('اعتماد'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LetterheadPreview(design: _design),
          const SizedBox(height: 14),
          _label('القالب'),
          SegmentedButton<String>(
            segments: [
              for (final t in lhTemplates)
                ButtonSegment(
                    value: t.id,
                    label: Text(t.label, style: const TextStyle(fontSize: 12))),
            ],
            selected: {_template},
            onSelectionChanged: (s) => setState(() => _template = s.first),
          ),
          const SizedBox(height: 12),
          _label('اللون الأساسي'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in lhColors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: _color == c
                        ? const Icon(Icons.check,
                            color: Colors.white, size: 18)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _label('الشعار (اختياري — يفضَّل PNG بخلفية شفافة)'),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickLogo,
                icon: const Icon(Icons.image_outlined),
                label: Text(_logo == null ? 'اختيار شعار' : 'استبدال الشعار'),
              ),
              const SizedBox(width: 8),
              if (_logo != null)
                TextButton(
                  onPressed: () => setState(() {
                    _logo = null;
                    _logoFile = '';
                  }),
                  child: const Text('إزالة'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _label('بيانات المنشأة'),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'الاسم العربي'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameEn,
            decoration: const InputDecoration(labelText: 'الاسم الإنجليزي'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'العنوان'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(
                labelText: 'الهاتف (رقم أو أكثر)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _website,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'الموقع الإلكتروني'),
          ),
          const SizedBox(height: 8),
          Text(
            'تُحفظ هذه البيانات في بطاقة المنشأة أيضًا، ويمكنك لاحقًا تعديل '
            'أي حقل وإعادة توليد الترويسة بنفس القالب واللون. تُولَّد الصورة '
            'بدقة الطباعة الكاملة (2550×3300 ≈ 300DPI) وتُعتمد ترويسةً '
            'للمنشأة فور الاعتماد.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: .65),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _apply,
            icon: const Icon(Icons.check),
            label: const Text('اعتماد الترويسة'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: .75),
            )),
      );
}
