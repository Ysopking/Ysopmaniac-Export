import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../logic/state_provider.dart';
import '../services/security_service.dart';
import '../theme.dart';

/// Setup-Screen beim Erststart. Prueft proaktiv, ob das Geraet ueberhaupt
/// eine Biometrie / Geraete-Sperre eingerichtet hat. Falls nicht: Hinweis
/// + Direkt-Link in die Android-Sicherheitseinstellungen, statt den User
/// in einer Endlos-Schleife stecken zu lassen.
class PasskeySetupScreen extends ConsumerStatefulWidget {
  final Future<void> Function() onSetupComplete;

  const PasskeySetupScreen({super.key, required this.onSetupComplete});

  @override
  ConsumerState<PasskeySetupScreen> createState() =>
      _PasskeySetupScreenState();
}

class _PasskeySetupScreenState extends ConsumerState<PasskeySetupScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _error;
  BiometricStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Wenn der User aus den System-Einstellungen zurueckkehrt, neu pruefen.
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    final security = ref.read(securityServiceProvider);
    final s = await security.getStatus();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _openSecuritySettings() async {
    // Versuche zunaechst die Sicherheits-Einstellungen, sonst die allgemeinen.
    final candidates = [
      Uri.parse('android.settings.SECURITY_SETTINGS'),
      Uri.parse('android.settings.SETTINGS'),
    ];
    for (final uri in candidates) {
      try {
        final ok = await launchUrl(
          Uri(scheme: 'package', path: 'com.android.settings'),
          mode: LaunchMode.externalApplication,
        );
        if (ok) return;
      } catch (_) {}
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      } catch (_) {}
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Bitte oeffne die Einstellungen manuell und richte eine Geraete-Sperre ein.'),
        ),
      );
    }
  }

  Future<void> _onContinue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final security = ref.read(securityServiceProvider);
      final ok = await security.authenticate();
      if (!ok) {
        setState(() => _error = security.lastError ??
            'Authentifizierung wurde abgebrochen. Bitte erneut versuchen.');
        await _refreshStatus();
        return;
      }
      // Erfolg -> first_launch=false setzen + auth state
      ref.read(authProvider.notifier).state = true;
      await widget.onSetupComplete();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAuth = _status?.canAuthenticate ?? false;
    final hasBiometrics = _status?.hasBiometrics ?? false;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: FindUXProTheme.primaryGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Center(
                  child: Image.asset(
                    'assets/logo.png',
                    width: 120,
                    height: 120,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.security, size: 80, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 24),
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
                Text(
                  hasBiometrics
                      ? 'FindUX nutzt deinen Fingerabdruck oder die Gesichtserkennung deines Geraets, um deine Daten zu schuetzen. Tippe auf "Sperre testen", um die Einrichtung abzuschliessen.'
                      : canAuth
                          ? 'Auf diesem Geraet ist aktuell nur eine PIN / ein Muster eingerichtet. FindUX nutzt diese als Sperre. Tippe auf "Sperre testen", um die Einrichtung abzuschliessen.'
                          : 'Bevor du fortfahren kannst, brauchst du eine aktive Geraete-Sperre (Fingerabdruck, Gesichtserkennung oder PIN).',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xE6FFFFFF),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_status != null)
                  _StatusBadge(
                    label: hasBiometrics
                        ? 'Biometrie verfuegbar (${_status!.available.map(_typeLabel).join(", ")})'
                        : canAuth
                            ? 'Geraete-Sperre vorhanden'
                            : 'Keine Geraete-Sperre eingerichtet',
                    ok: canAuth,
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                if (!canAuth)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _openSecuritySettings,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.settings),
                    label: const Text('System-Einstellungen oeffnen'),
                  ),
                if (!canAuth) const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _busy || !canAuth ? null : _onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: FindUXProTheme.primaryPurple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
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
                      : Text(
                          canAuth
                              ? 'Sperre testen & fortfahren'
                              : 'Bitte erst Sperre einrichten',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : _refreshStatus,
                  child: const Text(
                    'Status erneut pruefen',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _typeLabel(BiometricType t) {
    switch (t) {
      case BiometricType.face:
        return 'Gesicht';
      case BiometricType.fingerprint:
        return 'Fingerabdruck';
      case BiometricType.iris:
        return 'Iris';
      case BiometricType.strong:
        return 'Stark';
      case BiometricType.weak:
        return 'Schwach';
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool ok;
  const _StatusBadge({required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    final color = ok ? Colors.greenAccent : Colors.amberAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
              color: color, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
