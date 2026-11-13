// Soundwave App — main entry point.
// Initializes state management and renders the material app.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'onboarding/onboarding_screen.dart';
import 'state/app_state.dart';
import 'state/settings_store.dart';
import 'state/ui_preferences.dart';
import 'screens/dashboard.dart';
import 'screens/monitor.dart';
import 'screens/settings.dart';
import 'services/mic_permission.dart';
import 'theme/soundwave_theme.dart';
import 'widgets/mic_permission_gate.dart';

void main() {
  runApp(const SoundwaveApp());
}

class SoundwaveApp extends StatelessWidget {
  final AppState? appState;
  final UiPreferences? uiPreferences;
  const SoundwaveApp({super.key, this.appState, this.uiPreferences});

  static AppState _defaultAppState() {
    final state = AppState(store: SharedPreferencesSettingsStore());
    state.restoreSettings();
    return state;
  }

  static UiPreferences _defaultUiPreferences() {
    final store =
        SharedPreferencesSettingsStore(prefix: UiPreferences.storePrefix);
    return UiPreferences(store: store)..restore();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => appState ?? _defaultAppState(),
        ),
        ChangeNotifierProvider(
          create: (_) => uiPreferences ?? _defaultUiPreferences(),
        ),
      ],
      child: Consumer<UiPreferences>(
        builder: (context, prefs, _) => MaterialApp(
          title: 'Soundwave',
          theme: SoundwaveTheme.light,
          darkTheme: SoundwaveTheme.dark,
          themeMode: prefs.themeMode,
          home: const AppRoot(),
        ),
      ),
    );
  }
}

/// Shows the onboarding tutorial on first launch, then the main shell.
///
/// Microphone permission has one flow: on first launch the onboarding
/// microphone page explains and requests it, so the launch-time
/// [MicPermissionGate] stays quiet for the rest of that session. On later
/// launches the gate explains and asks again only if access is still missing
/// (and starting capture asks via MicPermission.ensureGranted as before).
class AppRoot extends StatefulWidget {
  /// Overrides platform detection for the gate and the onboarding
  /// permission button (tests).
  final bool? micGateEnabled;
  final Future<bool> Function() checkMicGranted;
  final Future<bool> Function() requestMic;

  const AppRoot({
    super.key,
    this.micGateEnabled,
    this.checkMicGranted = MicPermission.isGranted,
    this.requestMic = MicPermission.request,
  });

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool _onboardedThisSession = false;

  void _finishOnboarding(UiPreferences prefs) {
    setState(() => _onboardedThisSession = true);
    prefs.completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<UiPreferences>();
    if (!prefs.isLoaded) {
      // Preferences load in a frame or two; avoid flashing the wrong screen.
      return const Scaffold();
    }
    if (!prefs.onboardingComplete) {
      return OnboardingScreen(
        onFinished: () => _finishOnboarding(prefs),
        requestMicPermission: widget.requestMic,
        // Same platform switch as the gate: no button where there is no
        // runtime permission to ask for.
        showMicPermissionButton: widget.micGateEnabled,
      );
    }
    if (_onboardedThisSession) return const MainShell();
    return MicPermissionGate(
      enabled: widget.micGateEnabled,
      checkGranted: widget.checkMicGranted,
      requestPermission: widget.requestMic,
      child: const MainShell(),
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
