import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:findux_mobile/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'services/security_service.dart';
import 'services/learning_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/passkey_setup_screen.dart';
import 'screens/home_page.dart';
import 'logic/state_provider.dart';
import 'theme.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Vereinfachte Initialisierung für stabileren Start
  try {
    await Hive.initFlutter();

    final securityService = SecurityService();
    await securityService.initSecureBox();

    // LearningService optional machen
    final learningService = LearningService();
    await learningService.init();
    // await learningService.checkAndAnalyze(); // Temporär deaktiviert

  } catch (e) {
    // Bei Fehlern trotzdem starten
    debugPrint('Initialisierungsfehler: $e');
  }



  runApp(
    ProviderScope(
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      ref.read(onboardingDoneProvider.notifier).state = prefs.getBool('onboarding_done') ?? false;
      ref.read(firstLaunchProvider.notifier).state = prefs.getBool('first_launch') ?? true;
      await ref.read(settingsProvider.notifier).loadSettings();
    } catch (e) {
      debugPrint('initApp error: $e');
    }
    if (mounted) _authenticate();
  }

  Future<void> _authenticate() async {
    try {
      final securityService = ref.read(securityServiceProvider);
      final authenticated = await securityService.authenticate();
      if (mounted) {
        ref.read(authProvider.notifier).state = authenticated;
      }
    } catch (e) {
      // Bei Auth-Fehlern trotzdem entsperren für Demo-Zwecke
      debugPrint('Auth error: $e');
      if (mounted) {
        ref.read(authProvider.notifier).state = true;
      }
    }
  }

  Future<void> _completeSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_launch', false);
    ref.read(firstLaunchProvider.notifier).state = false;
    // Nach Setup direkt authentifizieren
    _authenticate();
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute(
      settings: settings,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final onboardingDone = ref.watch(onboardingDoneProvider);
          final authenticated = ref.watch(authProvider);

          // Launch-Lock: Require passkey setup on first launch
          final firstLaunch = ref.watch(firstLaunchProvider);
          if (firstLaunch) {
            return PasskeySetupScreen(onSetupComplete: _completeSetup);
          } else if (!authenticated) {
            return UnlockScreen(onUnlock: _authenticate);
          }

          if (settings.name == '/settings') {
            return SettingsScreen();
          } else if (!onboardingDone) {
            return OnboardingScreen(onComplete: () {
              ref.read(onboardingDoneProvider.notifier).state = true;
            });
          } else {
            return HomePage(learningService: ref.read(learningServiceProvider));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    // Defensive: nur unterstützte Locales setzen, sonst Fallback auf Deutsch
    const supported = {'de', 'en', 'fr', 'es', 'it'};
    final lang = supported.contains(settings.language) ? settings.language : 'de';
    final locale = Locale(lang);

    if (Platform.isIOS) {
      return CupertinoApp(
        title: 'FindYouX',
        theme: FindUXProTheme.cupertinoTheme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        onGenerateRoute: _onGenerateRoute,
        initialRoute: '/',
        debugShowCheckedModeBanner: false,
      );
    } else {
      return MaterialApp(
        title: 'FindYouX',
        theme: FindUXProTheme.materialTheme,
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.system,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        onGenerateRoute: _onGenerateRoute,
        initialRoute: '/',
        debugShowCheckedModeBanner: false,
      );
    }
  }
}
