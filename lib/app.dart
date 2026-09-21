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
import 'package:diabetes_app/services/basal_service.dart';
import 'package:diabetes_app/services/dose_reminder_service.dart';
import 'package:diabetes_app/services/entry_service.dart';
import 'package:diabetes_app/services/export_service.dart';
import 'package:diabetes_app/services/glicemia_service.dart';
import 'package:diabetes_app/services/health_platform_service.dart';
import 'package:diabetes_app/services/insulin_service.dart';
import 'package:diabetes_app/services/iob_badge_service.dart';
import 'package:diabetes_app/services/iob_live_controller.dart';
import 'package:diabetes_app/services/librelinkup_service.dart';
import 'package:diabetes_app/services/meal_favorites_service.dart';
import 'package:diabetes_app/services/profile_service.dart';
import 'package:diabetes_app/services/push_token_service.dart';
import 'package:diabetes_app/services/speech_service.dart';
import 'package:diabetes_app/services/support_service.dart';
import 'package:diabetes_app/services/theme_preference_service.dart';
import 'package:diabetes_app/services/widget_health_sync.dart';
import 'package:diabetes_app/theme/app_theme.dart';
import 'package:diabetes_app/widgets/app_logo.dart';

class AppServices {
  factory AppServices(SupabaseClient client) {
    final profile = ProfileService(client);
    final entries = EntryService(client);
    final badge = IobBadgeService(entries: entries, profile: profile);
    return AppServices.compose(
      auth: AuthService(client),
      profile: profile,
      entries: entries,
      basal: BasalService(client),
      glicemias: GlicemiaService(client),
      insulin: InsulinService(client),
      speech: SpeechService(client),
      libre: LibreLinkUpService(client),
      support: SupportService(),
      export: const ExportService(),
      favorites: MealFavoritesService(),
      reminders: DoseReminderService(),
      healthPlatform: HealthPlatformService(),
      pushTokens: PushTokenService(client),
      iobBadge: badge,
      iobLive: IobLiveController(
        entries: entries,
        profile: profile,
        badge: badge,
      ),
    );
  }

  /// Wire arbitrary service instances (fakes in tests, real in production).
  AppServices.compose({
    required this.auth,
    required this.profile,
    required this.entries,
    required this.basal,
    required this.glicemias,
    required this.insulin,
    required this.speech,
    required this.libre,
    required this.support,
    required this.export,
    required this.favorites,
    required this.reminders,
    required this.healthPlatform,
    required this.pushTokens,
    required this.iobBadge,
    required this.iobLive,
  });

  final AuthService auth;
  final ProfileService profile;
  final EntryService entries;
  final BasalService basal;
  final GlicemiaService glicemias;
  final InsulinService insulin;
  final SpeechService speech;
  final LibreLinkUpService libre;
  final SupportService support;
  final ExportService export;
  final MealFavoritesService favorites;
  final DoseReminderService reminders;
  final HealthPlatformService healthPlatform;
  final PushTokenService pushTokens;
  final IobBadgeService iobBadge;
  final IobLiveController iobLive;

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
    services.iobLive.start();
    unawaited(services.iobLive.refreshFromNetwork());
    final userId = services.auth.currentUser?.id;
    if (userId != null) {
      unawaited(services.support.logIn(userId));
    }
    unawaited(services.pushTokens.register());
    unawaited(_syncBasalReminders());
    unawaited(_syncHealthPrefToWidget());
  }

  Future<void> _syncHealthPrefToWidget() async {
    try {
      final profile = await services.profile.fetchCurrent(applyTheme: false);
      if (profile == null) return;
      await WidgetHealthSync.setEnabled(profile.healthSyncEnabled);
    } catch (_) {}
  }

  Future<void> _syncBasalReminders() async {
    try {
      final profile = await services.profile.fetchCurrent(applyTheme: false);
      if (profile == null) return;
      await services.reminders.syncBasalFromProfile(
        enabled: profile.basalReminderEnabled,
        timesMinutes: profile.basalTimesMinutes,
        timezone: profile.timezone,
        insulinName: profile.basalInsulinName,
        doseU: profile.basalDoseU,
      );
    } catch (_) {}
  }

  void _onLoggedOut() {
    unawaited(services.iobLive.clear());
    unawaited(services.support.logOut());
    unawaited(services.pushTokens.unregister());
    unawaited(services.reminders.cancelBasalReminders());
  }

  void _onEntriesChanged() {
    if (!_loggedIn) return;
    unawaited(services.iobLive.refreshFromNetwork());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_loggedIn) return;
    if (state == AppLifecycleState.resumed) {
      // Ensure timer is running after process resume; refresh from network.
      services.iobLive.start();
      unawaited(services.iobLive.refreshFromNetwork());
      unawaited(WidgetHealthSync.refresh(lookback: const Duration(hours: 12)));
    } else if (state == AppLifecycleState.detached) {
      services.iobLive.stop();
    }
    // Keep ticking while paused so the status notification can update
    // while the process is still alive.
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemePreferenceService.mode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'GlicoDose',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
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
          final colors = AppColors.of(context);
          return Scaffold(
            backgroundColor: colors.surface,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppLogo(size: 88, showTitle: true, titleSize: 26),
                  const SizedBox(height: 24),
                  const SizedBox(
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
