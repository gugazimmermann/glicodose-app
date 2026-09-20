import 'package:flutter/material.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/screens/history_screen.dart';
import 'package:diabetes_app/screens/home_screen.dart';
import 'package:diabetes_app/screens/profile_screen.dart';
import 'package:diabetes_app/screens/support_screen.dart';
import 'package:diabetes_app/utils/user_facing_error.dart';
import 'package:diabetes_app/widgets/app_logo.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.services});

  final AppServices services;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _titles = ['Dose', 'Histórico', 'Apoiar', 'Perfil'];

  @override
  void initState() {
    super.initState();
    _index = widget.services.selectedTabIndex.value;
    widget.services.selectedTabIndex.addListener(_onTabRequested);
  }

  @override
  void dispose() {
    widget.services.selectedTabIndex.removeListener(_onTabRequested);
    super.dispose();
  }

  void _onTabRequested() {
    final next = widget.services.selectedTabIndex.value;
    if (!mounted || next == _index) return;
    setState(() => _index = next);
    if (next == 1) {
      widget.services.notifyEntriesChanged();
    }
  }

  void _selectTab(int value) {
    setState(() => _index = value);
    widget.services.selectedTabIndex.value = value;
    if (value == 1) {
      widget.services.notifyEntriesChanged();
    }
  }

  Future<void> _exportHistory(String value) async {
    try {
      final entries = await widget.services.entries.listEntries(limit: 500);
      if (value == 'csv') {
        await widget.services.export.shareCsv(entries);
      } else if (value == 'report') {
        final profile = await widget.services.profile.fetchCurrent();
        await widget.services.export.sharePdfLikeReport(
          profile: profile,
          entries: entries,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(services: widget.services, embedded: true),
      HistoryScreen(services: widget.services, embedded: true),
      SupportScreen(services: widget.services, embedded: true),
      ProfileScreen(services: widget.services, embedded: true),
    ];

    return Scaffold(
      appBar: AppBar(
        title: AppBarLogoTitle(title: _titles[_index]),
        actions: [
          if (_index == 1)
            PopupMenuButton<String>(
              tooltip: 'Exportar',
              onSelected: _exportHistory,
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'csv', child: Text('Exportar CSV')),
                PopupMenuItem(
                  value: 'report',
                  child: Text('Relatório para consulta'),
                ),
              ],
            ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.water_drop_outlined),
            selectedIcon: Icon(Icons.water_drop),
            label: 'Dose',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Histórico',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Apoiar',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
