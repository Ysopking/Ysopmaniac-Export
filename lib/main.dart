import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:findux_mobile/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'services/security_service.dart';
import 'services/learning_service.dart';
import 'services/auto_lock_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/unlock_screen.dart';
import 'screens/passkey_setup_screen.dart';
import 'screens/home_page.dart';
import 'logic/state_provider.dart';
import 'theme.dart';

Future<void> main() async {
  // Globaler Error-Handler: keine stillen Crashes mehr
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('PlatformDispatcher error: $error');
      return true;
    };

    // Stage F Haertung: FLAG_SECURE wird nativ in MainActivity.kt im
    // onCreate() gesetzt — frueher als Flutter rendert. Damit ist
    // bereits der allererste Frame (Splash, Recents-Thumbnail)
    // geschuetzt. Hier nichts mehr zu tun.

    final SecurityService securityService = SecurityService();
    final LearningService learningService = LearningService();
    bool initOk = false;

    try {
      await Hive.initFlutter();
      await securityService.initSecureBox();
      // LearningService verwendet denselben Encryption-Key wie der Vault
      final cipherKey = await securityService.getEncryptionKey();
      await learningService.init(cipherKey);
      initOk = true;
    } catch (e, st) {
      debugPrint('Initialisierungsfehler: $e\n$st');
    }

    // Provider-Overrides: dieselbe Service-Instanz wie in main()
    runApp(
      ProviderScope(
        overrides: [
          securityServiceProvider.overrideWithValue(securityService),
          learningServiceProvider.overrideWithValue(learningService),
          initFailedProvider.overrideWith((ref) => !initOk),
        ],
        child: const MyApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  late final AutoLockObserver _autoLock;

  @override
  void initState() {
    super.initState();
    _autoLock = AutoLockObserver(
      timeout: const Duration(seconds: 60),
      onLock: _lockSession,
    )..attach();
    _initApp();
  }

  @override
  void dispose() {
    _autoLock.detach();
    super.dispose();
  }

  /// Stage F: Sitzung sperren, sobald die App > 60 s im Hintergrund war.
  /// Wir setzen den Auth-State auf false — der UnlockScreen erscheint
  /// dann beim naechsten Foreground automatisch via _onGenerateRoute.
  void _lockSession() {
    if (!mounted) return;
    final auth = ref.read(authProvider);
    if (auth) {
      debugPrint('AutoLock: Sitzung nach Inaktivitaet gesperrt.');
      ref.read(authProvider.notifier).state = false;
    }
  }

  Future<void> _initApp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      ref.read(onboardingDoneProvider.notifier).state =
          prefs.getBool('onboarding_done') ?? false;
      ref.read(firstLaunchProvider.notifier).state =
          prefs.getBool('first_launch') ?? true;
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
      // KEIN automatisches Entsperren bei Auth-Fehler.
      // User muss explizit erneut auf "Entsperren" tippen.
      debugPrint('Auth error: $e');
      if (mounted) {
        ref.read(authProvider.notifier).state = false;
        ref.read(authErrorProvider.notifier).state = e.toString();
      }
    }
  }

  Future<void> _completeSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_launch', false);
    if (!mounted) return;
    ref.read(firstLaunchProvider.notifier).state = false;
    _authenticate();
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    return MaterialPageRoute(
      settings: settings,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final onboardingDone = ref.watch(onboardingDoneProvider);
          final authenticated = ref.watch(authProvider);
          final firstLaunch = ref.watch(firstLaunchProvider);

          if (firstLaunch) {
            return PasskeySetupScreen(onSetupComplete: _completeSetup);
          } else if (!authenticated) {
            return UnlockScreen(onUnlock: _authenticate);
          }

          if (settings.name == '/settings') {
            return const SettingsScreen();
          } else if (!onboardingDone) {
            return OnboardingScreen(onComplete: () {
              ref.read(onboardingDoneProvider.notifier).state = true;
            });
          } else {
            return HomePage(
              learningService: ref.read(learningServiceProvider),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
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
        darkTheme: FindUXProTheme.materialDarkTheme,
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
