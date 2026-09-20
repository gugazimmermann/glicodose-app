import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/screens/disclaimer_screen.dart';
import 'package:diabetes_app/screens/history_screen.dart';
import 'package:diabetes_app/screens/home_screen.dart';
import 'package:diabetes_app/screens/login_screen.dart';
import 'package:diabetes_app/screens/main_shell.dart';
import 'package:diabetes_app/screens/profile_screen.dart';
import 'package:diabetes_app/screens/splash_screen.dart';
import 'package:diabetes_app/services/auth_service.dart';
import 'package:diabetes_app/services/entry_service.dart';
import 'package:diabetes_app/services/export_service.dart';
import 'package:diabetes_app/services/insulin_service.dart';
import 'package:diabetes_app/services/iob_badge_service.dart';
import 'package:diabetes_app/services/profile_service.dart';
import 'package:diabetes_app/services/reminder_service.dart';
import 'package:diabetes_app/services/speech_service.dart';
import 'package:diabetes_app/services/support_service.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/widgets/app_logo.dart';

class AppServices {
  AppServices(SupabaseClient client)
      : auth = AuthService(client),
        profile = ProfileService(client),
        entries = EntryService(client),
        insulin = InsulinService(client),
        speech = SpeechService(client),
        support = SupportService(),
        reminders = ReminderService(),
        export = const ExportService() {
    iobBadge = IobBadgeService(entries: entries, profile: profile);
  }

  final AuthService auth;
  final ProfileService profile;
  final EntryService entries;
  final InsulinService insulin;
  final SpeechService speech;
  final SupportService support;
  final ReminderService reminders;
  final ExportService export;
  late final IobBadgeService iobBadge;

  /// Bumped whenever entries are created/updated/deleted so History reloads.
  final ValueNotifier<int> entriesRevision = ValueNotifier<int>(0);

  /// Shell bottom-nav index: 0 Dose, 1 Histórico, 2 Apoiar, 3 Perfil.
  final ValueNotifier<int> selectedTabIndex = ValueNotifier<int>(0);

  void notifyEntriesChanged() {
    entriesRevision.value++;
  }

  void goToHistoryTab() {
    selectedTabIndex.value = 1;
    notifyEntriesChanged();
  }
}

class DiabetesApp extends StatefulWidget {
  const DiabetesApp({super.key, required this.services});

  final AppServices services;

  @override
  State<DiabetesApp> createState() => _DiabetesAppState();
}

class _DiabetesAppState extends State<DiabetesApp> with WidgetsBindingObserver {
  StreamSubscription<AuthState>? _authSub;
  Timer? _badgeTimer;
  bool _loggedIn = false;
  bool _showSplash = true;

  AppServices get services => widget.services;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    services.entriesRevision.addListener(_onEntriesChanged);
    _loggedIn = services.auth.currentSession != null;
    _authSub = services.auth.authStateChanges.listen(_onAuthState);
    if (_loggedIn) {
      _onLoggedIn();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _stopBadgeTimer();
    services.entriesRevision.removeListener(_onEntriesChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onAuthState(AuthState state) {
    final loggedIn = state.session != null;
    if (loggedIn == _loggedIn) return;
    _loggedIn = loggedIn;
    if (loggedIn) {
      _onLoggedIn();
    } else {
      _onLoggedOut();
    }
  }

  void _onLoggedIn() {
    unawaited(() async {
      await services.iobBadge.ensureReady();
      await services.iobBadge.refresh();
      try {
        final settings = await services.reminders.loadSettings();
        await services.reminders.saveAndReschedule(settings);
      } catch (_) {}
    }());
    _startBadgeTimer();
    final userId = services.auth.currentUser?.id;
    if (userId != null) {
      unawaited(services.support.logIn(userId));
    }
  }

  void _onLoggedOut() {
    _stopBadgeTimer();
    unawaited(services.iobBadge.clear());
    unawaited(services.support.logOut());
  }

  void _onEntriesChanged() {
    if (!_loggedIn) return;
    unawaited(() async {
      await services.iobBadge.ensureReady();
      await services.iobBadge.refresh();
    }());
  }

  void _startBadgeTimer() {
    _stopBadgeTimer();
    _badgeTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (_loggedIn) {
        unawaited(services.iobBadge.refresh());
      }
    });
  }

  void _stopBadgeTimer() {
    _badgeTimer?.cancel();
    _badgeTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _loggedIn) {
      unawaited(() async {
        await services.iobBadge.ensureReady();
        await services.iobBadge.refresh();
      }());
      _startBadgeTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopBadgeTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GlicoDose',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _showSplash
          ? SplashScreen(
              onFinished: () {
                if (!mounted) return;
                setState(() => _showSplash = false);
              },
            )
          : AuthGate(services: services),
      routes: {
        '/login': (_) => LoginScreen(services: services),
        '/profile': (_) => ProfileScreen(services: services),
        '/home': (_) => HomeScreen(services: services),
        '/history': (_) => HistoryScreen(services: services),
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: services.auth.authStateChanges,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? services.auth.currentSession;
        if (session == null) {
          return LoginScreen(services: services);
        }
        return ProfileGate(services: services);
      },
    );
  }
}

class ProfileGate extends StatefulWidget {
  const ProfileGate({super.key, required this.services});

  final AppServices services;

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  late Future<Profile?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = widget.services.profile.fetchCurrent();
  }

  void _reload() {
    setState(() {
      _profileFuture = widget.services.profile.fetchCurrent();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Profile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            backgroundColor: AppColors.surface,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  AppLogo(size: 88, showTitle: true, titleSize: 26),
                  SizedBox(height: 24),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Erro ao carregar perfil: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final profile = snapshot.data;
        if (profile?.isComplete != true) {
          return ProfileScreen(
            services: widget.services,
            isOnboarding: true,
            onSaved: _reload,
          );
        }
        if (!profile!.hasAcceptedDisclaimer) {
          return DisclaimerScreen(
            services: widget.services,
            onAccepted: _reload,
          );
        }
        return MainShell(services: widget.services);
      },
    );
  }
}
