import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:findux_mobile/l10n/app_localizations.dart';
import '../theme.dart';

class PasskeySetupScreen extends StatefulWidget {
  final Future<void> Function() onSetupComplete;

  const PasskeySetupScreen({super.key, required this.onSetupComplete});

  @override
  _PasskeySetupScreenState createState() => _PasskeySetupScreenState();
}

class _PasskeySetupScreenState extends State<PasskeySetupScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: FindUXProTheme.primaryGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.security,
                  size: 80,
                  color: Colors.white,
                ),
                const SizedBox(height: 32),
                Text(
                  'Sicherheit einrichten',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Um FindUX zu verwenden, richten Sie bitte eine Sicherheitsmethode ein:\n\n'
                  '1. Gehen Sie zu den Einstellungen Ihres Geräts\n'
                  '2. Suchen Sie nach "Sicherheit" oder "Biometrie"\n'
                  '3. Richten Sie Fingerabdruck, Gesichtserkennung oder PIN ein\n\n'
                  'Danach können Sie FindUX sicher verwenden.',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: () async {
                    await widget.onSetupComplete();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: FindUXProTheme.primaryPurple,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'Ich habe es eingerichtet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    // Für Demo-Zwecke trotzdem fortfahren
                    await widget.onSetupComplete();
                  },
                  child: Text(
                    'Überspringen (Demo)',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}