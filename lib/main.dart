import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:findux_mobile/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/security_service.dart';
import 'services/learning_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/home_page.dart';
import 'logic/state_provider.dart';
import 'theme.dart';

Future<void> _requestPermissions() async {
  // Internet-Berechtigung (normalerweise automatisch)
  await Permission.internet.request();

  // Biometrische Authentifizierung
  await Permission.sensors.request(); // Für Biometrie

  // Speicher-Berechtigung für Hive/SharedPreferences (intern)
  // await Permission.storage.request(); // Nicht notwendig für interne Speicherung
}

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

  // Berechtigungen anfragen
  await _requestPermissions();

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
    final prefs = await SharedPreferences.getInstance();
    ref.read(onboardingDoneProvider.notifier).state = prefs.getBool('onboarding_done') ?? false;
    await ref.read(settingsProvider.notifier).loadSettings();
    _authenticate();
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

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute(
      settings: settings,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final onboardingDone = ref.watch(onboardingDoneProvider);
          final authenticated = ref.watch(authProvider);

          // Launch-Lock: Only request passkey on app start
          if (!authenticated) {
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
    final locale = Locale(settings.language);

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
