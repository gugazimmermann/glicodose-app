import 'package:flutter/material.dart';

import 'package:diabetes_app/app.dart';
import 'package:diabetes_app/screens/history_screen.dart';
import 'package:diabetes_app/screens/home_screen.dart';
import 'package:diabetes_app/screens/profile_screen.dart';
import 'package:diabetes_app/widgets/app_logo.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.services});

  final AppServices services;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _titles = ['Nova dose', 'Histórico', 'Perfil'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(services: widget.services, embedded: true),
      HistoryScreen(services: widget.services, embedded: true),
      ProfileScreen(services: widget.services, embedded: true),
    ];

    return Scaffold(
      appBar: AppBar(
        title: AppBarLogoTitle(title: _titles[_index]),
      ),
      body: IndexedStack(
        index: _index,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
          if (value == 1) {
            widget.services.notifyEntriesChanged();
          }
        },
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
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
