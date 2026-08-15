/// الهيكل الرئيسي: شريط تنقل سفلي بين الشاشات الخمس.
library;

import 'package:flutter/material.dart';

import 'archive_screen.dart';
import 'entities_screen.dart';
import 'new_letter_screen.dart';
import 'recipients_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          NewLetterScreen(),
          ArchiveScreen(),
          EntitiesScreen(),
          RecipientsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.edit_note), label: 'رسالة جديدة'),
          NavigationDestination(
              icon: Icon(Icons.archive_outlined), label: 'الأرشيف'),
          NavigationDestination(
              icon: Icon(Icons.business_outlined), label: 'المنشآت'),
          NavigationDestination(
              icon: Icon(Icons.contacts_outlined), label: 'الجهات'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
        ],
      ),
    );
  }
}
