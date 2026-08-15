/// الإعدادات: مزود الذكاء الاصطناعي (المفتاح والنموذج والعنوان) وسمة الواجهة.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_client.dart' show AIError, testProvider;
import '../ai/providers.dart';
import '../data/db.dart';
import '../data/settings_store.dart';
import '../main.dart' show themeModeNotifier, themeModeFromName, appEpoch;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _store = SettingsStore.instance;
  final _modelCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();

  String _providerId = kDefaultProvider;
  String _themeName = 'system';
  bool _showKey = false;
  bool _testing = false;
  bool _backupBusy = false;

  ProviderPreset get _preset => providerById(_providerId);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    _providerId = await _store.getProviderId();
    _themeName = await _store.getThemeMode();
    await _loadProviderFields();
  }

  Future<void> _loadProviderFields() async {
    final model = await _store.getModel(_providerId);
    final baseUrl = await _store.getBaseUrl(_providerId);
    final apiKey = await _store.getApiKey(_providerId);
    if (!mounted) return;
    setState(() {
      _modelCtrl.text = model;
      _baseUrlCtrl.text = baseUrl;
      _apiKeyCtrl.text = apiKey;
    });
  }

  Future<void> _save() async {
    await _store.setProviderId(_providerId);
    await _store.setModel(_providerId, _modelCtrl.text);
    await _store.setBaseUrl(_providerId, _baseUrlCtrl.text);
    await _store.setApiKey(_providerId, _apiKeyCtrl.text);
    _snack('تم حفظ الإعدادات');
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      await _save();
      await testProvider();
      _snack('الاتصال ناجح — المزود جاهز للتوليد ✅');
    } on AIError catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('فشل الاختبار: $e', error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _backupBusy = true);
    try {
      final path = await AppDb.instance.exportBackup();
      await Share.shareXFiles(
        [XFile(path)],
        text: 'نسخة احتياطية من بيانات «المراسلات الرسمية»',
      );
      _snack('أُنشئت النسخة الاحتياطية وجاهزة للمشاركة');
    } catch (e) {
      _snack('تعذّر إنشاء النسخة: $e', error: true);
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _importBackup() async {
    final picked = await FilePicker.platform.pickFiles();
    final path = picked?.files.single.path;
    if (path == null) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استيراد نسخة احتياطية'),
        content: const Text(
            'سيستبدل الاستيراد كل بياناتك الحالية (الرسائل والمنشآت والجهات '
            'والوارد والقوالب) ببيانات الملف المختار.\n\n'
            'يُقبل ملف قاعدة نسخة سطح المكتب أو نسخة احتياطية من هذا '
            'التطبيق، وستُحفظ نسخة أمان من بياناتك الحالية تلقائيًا قبل '
            'الاستبدال.\n\n'
            'ملاحظة: صور الترويسات لا تُنقل مع القاعدة — أعد رفعها من صفحة '
            '«المنشآت» بعد الاستيراد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('استيراد'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _backupBusy = true);
    try {
      await AppDb.instance.importBackup(path);
      appEpoch.value++; // إعادة تحميل كل الشاشات على البيانات الجديدة
      _snack('تم الاستيراد بنجاح ✅');
    } on FormatException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('تعذّر الاستيراد: $e', error: true);
    } finally {
      if (mounted) setState(() => _backupBusy = false);
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
    final preset = _preset;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('مزود الذكاء الاصطناعي'),
          DropdownButtonFormField<String>(
            initialValue: _providerId,
            items: [
              for (final p in kProviders)
                DropdownMenuItem(value: p.id, child: Text(p.label)),
            ],
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _providerId = v);
              await _loadProviderFields();
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: Text(preset.hint,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .65),
                )),
          ),
          if (preset.keysUrl.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(preset.keysUrl),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(preset.keysLabel.isNotEmpty
                    ? preset.keysLabel
                    : 'إنشاء مفتاح API من موقع ${preset.label}'),
              ),
            ),
          if (preset.needsKey || _providerId == 'custom') ...[
            const SizedBox(height: 6),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: !_showKey,
              decoration: InputDecoration(
                labelText: 'مفتاح API',
                helperText: 'يُحفظ مشفّرًا في مخزن مفاتيح النظام (Keystore)',
                suffixIcon: IconButton(
                  icon: Icon(
                      _showKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _modelCtrl,
            decoration: InputDecoration(
              labelText: 'النموذج',
              hintText: preset.defaultModel.isEmpty
                  ? 'اسم النموذج'
                  : 'الافتراضي: ${preset.defaultModel}',
            ),
          ),
          if (preset.models.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                children: [
                  for (final m in preset.models)
                    ActionChip(
                      label: Text(m, style: const TextStyle(fontSize: 12)),
                      onPressed: () =>
                          setState(() => _modelCtrl.text = m),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _baseUrlCtrl,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'عنوان الخادم (اختياري)',
              hintText: preset.baseUrl.isEmpty
                  ? 'اتركه فارغًا للافتراضي'
                  : 'الافتراضي: ${preset.baseUrl}',
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: Text(_testing ? 'جارٍ الاختبار…' : 'اختبار الاتصال'),
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          _sectionTitle('سمة الواجهة'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'system', label: Text('النظام')),
              ButtonSegment(value: 'light', label: Text('فاتحة')),
              ButtonSegment(value: 'dark', label: Text('داكنة')),
            ],
            selected: {_themeName},
            onSelectionChanged: (s) async {
              final v = s.first;
              setState(() => _themeName = v);
              await _store.setThemeMode(v);
              themeModeNotifier.value = themeModeFromName(v);
            },
          ),
          const Divider(height: 32),
          _sectionTitle('النسخ الاحتياطي'),
          Text(
            'تصدير قاعدة البيانات كاملة (الرسائل والمنشآت والجهات والوارد '
            'والقوالب) ملفًا واحدًا تشاركه أو تحفظه، أو استيراد ملف سابق — '
            'بما في ذلك قاعدة نسخة Windows.',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: .7),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _backupBusy ? null : _exportBackup,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('تصدير ومشاركة'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _backupBusy ? null : _importBackup,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('استيراد نسخة'),
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          _sectionTitle('الخصوصية'),
          Text(
            'كل بياناتك (الرسائل، المنشآت، الترويسات، الإعدادات) محلية على '
            'جهازك بالكامل. الاستثناء الوحيد: نص الرسالة يُرسل إلى مزود '
            'الذكاء الاصطناعي المُعدّ أعلاه عند التوليد أو التنقيح.',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: .7),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );
}
