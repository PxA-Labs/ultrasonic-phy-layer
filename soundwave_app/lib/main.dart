// Soundwave App — main entry point.
// Initializes state management and renders the material app.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'screens/dashboard.dart';
import 'screens/monitor.dart';
import 'screens/settings.dart';

void main() {
  runApp(const SoundwaveApp());
}

class SoundwaveApp extends StatelessWidget {
  final AppState? appState;
  const SoundwaveApp({super.key, this.appState});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => appState ?? AppState(),
      child: MaterialApp(
        title: 'Soundwave',
        theme: ThemeData.dark().copyWith(
          primaryColor: const Color(0xFF0D47A1),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF0D47A1),
            secondary: Color(0xFF00BCD4),
          ),
        ),
        home: const MainShell(),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final List<Widget> _screens = const [
    DashboardScreen(),
    MonitorScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Monitor'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
