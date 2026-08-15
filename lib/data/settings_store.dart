/// إعدادات التطبيق: اختيار المزود والنموذج والعنوان في SharedPreferences،
/// ومفاتيح API في التخزين الآمن (Android Keystore) — لا تُكتب في أي ملف عادي.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/providers.dart';

class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ---------- المزود المختار ----------

  Future<String> getProviderId() async =>
      (await _prefs).getString('ai_provider') ?? kDefaultProvider;

  Future<void> setProviderId(String id) async =>
      (await _prefs).setString('ai_provider', id);

  // ---------- إعدادات كل مزود ----------

  Future<String> getModel(String pid) async =>
      (await _prefs).getString('model_$pid') ?? '';

  Future<void> setModel(String pid, String model) async =>
      (await _prefs).setString('model_$pid', model.trim());

  Future<String> getBaseUrl(String pid) async =>
      (await _prefs).getString('base_url_$pid') ?? '';

  Future<void> setBaseUrl(String pid, String url) async =>
      (await _prefs).setString('base_url_$pid', url.trim());

  Future<String> getApiKey(String pid) async =>
      await _secure.read(key: 'api_key_$pid') ?? '';

  Future<void> setApiKey(String pid, String key) async {
    final v = key.trim();
    if (v.isEmpty) {
      await _secure.delete(key: 'api_key_$pid');
    } else {
      await _secure.write(key: 'api_key_$pid', value: v);
    }
  }

  // ---------- سمة الواجهة ----------

  Future<String> getThemeMode() async =>
      (await _prefs).getString('theme_mode') ?? 'system';

  Future<void> setThemeMode(String mode) async =>
      (await _prefs).setString('theme_mode', mode);

  // ---------- الحل الكامل للمزود الحالي ----------

  Future<ResolvedProvider> resolveProvider([String? providerId]) async {
    final pid = providerId ?? await getProviderId();
    final preset = providerById(pid);
    final model = (await getModel(pid)).trim();
    final baseUrl = (await getBaseUrl(pid)).trim();
    return ResolvedProvider(
      id: preset.id,
      sdk: preset.sdk,
      label: preset.label,
      needsKey: preset.needsKey,
      apiKey: await getApiKey(pid),
      model: model.isNotEmpty ? model : preset.defaultModel,
      baseUrl: baseUrl.isNotEmpty ? baseUrl : preset.baseUrl,
    );
  }
}
