/// المراسلات الرسمية — توليد الرسائل الرسمية العربية بالذكاء الاصطناعي.
/// كل البيانات محلية على الجهاز؛ الاستثناء الوحيد نص الرسالة الذي يُرسل
/// لمزود الذكاء الاصطناعي الذي يختاره المستخدم عند التوليد أو التنقيح.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/settings_store.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

/// رفع القيمة يعيد بناء الشجرة كاملة (تُستدعى initState من جديد) —
/// يُستخدم بعد استيراد نسخة احتياطية لتظهر البيانات الجديدة فورًا.
final appEpoch = ValueNotifier<int>(0);

ThemeMode themeModeFromName(String name) => switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  themeModeNotifier.value =
      themeModeFromName(await SettingsStore.instance.getThemeMode());
  runApp(const CorrespondenceApp());
}

class CorrespondenceApp extends StatelessWidget {
  const CorrespondenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => MaterialApp(
        title: 'المراسلات الرسمية',
        debugShowCheckedModeBanner: false,
        theme: lightTheme(),
        darkTheme: darkTheme(),
        themeMode: mode,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ValueListenableBuilder<int>(
          valueListenable: appEpoch,
          builder: (context, epoch, _) => HomeShell(key: ValueKey(epoch)),
        ),
      ),
    );
  }
}
