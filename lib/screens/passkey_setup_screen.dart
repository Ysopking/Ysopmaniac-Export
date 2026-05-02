import 'package:flutter/material.dart';
import '../theme.dart';

class PasskeySetupScreen extends StatefulWidget {
  final Future<void> Function() onSetupComplete;

  const PasskeySetupScreen({super.key, required this.onSetupComplete});

  @override
  State<PasskeySetupScreen> createState() => _PasskeySetupScreenState();
}

class _PasskeySetupScreenState extends State<PasskeySetupScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
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
                const Icon(
                  Icons.security,
                  size: 80,
                  color: Colors.white,
                ),
                const SizedBox(height: 32),
                const Text(
                  'Sicherheit einrichten',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'FindUX schützt deine Daten ausschließlich auf diesem Gerät.\n'
                  'Bevor du fortfahren kannst, richte bitte eine Geräte-Sperre ein:\n\n'
                  '1. Öffne die Einstellungen deines Smartphones\n'
                  '2. Aktiviere Fingerabdruck, Gesichtserkennung oder PIN\n'
                  '3. Komme dann hierher zurück und tippe unten auf "Weiter"\n\n'
                  'Ohne Geräte-Sperre lässt sich FindUX nicht starten.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xE6FFFFFF),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await widget.onSetupComplete();
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: FindUXProTheme.primaryPurple,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Weiter',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
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
