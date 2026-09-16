import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diabetes_app/models/profile.dart';
import 'package:diabetes_app/screens/disclaimer_screen.dart';
import 'package:diabetes_app/screens/history_screen.dart';
import 'package:diabetes_app/screens/home_screen.dart';
import 'package:diabetes_app/screens/login_screen.dart';
import 'package:diabetes_app/screens/main_shell.dart';
import 'package:diabetes_app/screens/profile_screen.dart';
import 'package:diabetes_app/services/auth_service.dart';
import 'package:diabetes_app/services/entry_service.dart';
import 'package:diabetes_app/services/insulin_service.dart';
import 'package:diabetes_app/services/profile_service.dart';
import 'package:diabetes_app/services/speech_service.dart';
import 'package:diabetes_app/theme/app_theme.dart';

class AppServices {
  AppServices(SupabaseClient client)
      : auth = AuthService(client),
        profile = ProfileService(client),
        entries = EntryService(client),
        insulin = InsulinService(client),
        speech = SpeechService(client);

  final AuthService auth;
  final ProfileService profile;
  final EntryService entries;
  final InsulinService insulin;
  final SpeechService speech;
}

class DiabetesApp extends StatelessWidget {
  const DiabetesApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diabetes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: AuthGate(services: services),
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
                children: [
                  Image.asset(
                    'images/glucosemeter.png',
                    width: 72,
                    height: 72,
                  ),
                  const SizedBox(height: 20),
                  const CircularProgressIndicator(color: AppColors.primary),
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
