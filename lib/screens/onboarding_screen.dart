import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logic/state_provider.dart';
import '../screens/interests_screen.dart';
import '../services/chrome_import_quick.dart';
import '../services/haptic_helper.dart';
import '../theme.dart';

/// Apple-UX-Onboarding (Stage G):
///
/// Frueher: 5 Schritte (Beschaeftigung, Geburtsjahr, Region+PLZ,
/// Chronik, Feedback+Jugendschutz) — User musste 12+ Taps absolvieren,
/// bevor irgendwas suchbar war.
///
/// Jetzt: EIN Hero-Screen mit genau einem primaeren Knopf
/// "Verlauf importieren & loslegen". Defaults werden direkt geschrieben.
/// Stammdaten kann der User spaeter in den Settings ergaenzen — bzw.
/// die Home-Page bittet ihn ohnehin via Stammdaten-Pill darum, sobald
/// die Suche schwach wird (kontextuelle Frage statt Voraus-Befragung).
///
/// Apple-Vorbild: Setup-Assistant (iOS 17), Wallet-First-Run, Maps.
class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _busy = false;

  Future<void> _persistDefaults() async {
    final notifier = ref.read(settingsProvider.notifier);
    // Defaults ENTSPRECHEN _defaultSettings im state_provider.dart;
    // wir speichern sie explizit, damit der Vault einen klaren
    // "User hat akzeptiert"-Snapshot bekommt.
    await notifier.updateSettings(const SettingsState(
      plz: '',
      employmentType: 'student',
      beruf: '',
      searchEngine: 'google',
      language: 'de',
      country: 'de',
      allowFeedback: false,
      enableYouthProtection: true,
      jahr: 1990,
      sources: ['alle'],
      files: ['alle'],
      mode: 'standard',
      openInApp: true,
      enableVolumeShortcut: false,
    ));
  }

  Future<void> _handleImport() async {
    if (_busy) return;
    setState(() => _busy = true);
    Haptics.tap();
    final ok = await quickImportChrome(context);
    if (!mounted) return;
    if (ok) {
      Haptics.done();
    }
    await _persistDefaults();
    if (!mounted) return;
    widget.onComplete();
  }

  Future<void> _handleSkip() async {
    if (_busy) return;
    setState(() => _busy = true);
    Haptics.pick();
    await _persistDefaults();
    if (!mounted) return;
    widget.onComplete();
  }

  Future<void> _handleInterests() async {
    if (_busy) return;
    setState(() => _busy = true);
    Haptics.tap();
    // Defaults schreiben, damit settingsProvider mit leeren Interessen
    // initialisiert ist und die InterestsScreen sofort lesen/schreiben kann.
    await _persistDefaults();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InterestsScreen()),
    );
    if (!mounted) return;
    Haptics.done();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero-Bereich (oben gross, viel Whitespace)
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Markenzeichen — das echte runde Lila-Logo
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: FindUXProTheme.primaryPurple
                                    .withValues(alpha: 0.22),
                                blurRadius: 28,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Container(
                                color: FindUXProTheme.primaryPurple,
                                alignment: Alignment.center,
                                child: const Icon(Icons.search_rounded,
                                    size: 56, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'Willkommen bei\nFindUX Pro',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 34,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.0,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Bessere Suchergebnisse in Sekunden — '
                          'ohne Konto, ohne Cloud.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.35,
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                        SizedBox(height: media.size.height * 0.06),
                        // Vertrauens-Punkte
                        _trustRow(
                          icon: Icons.lock_outline_rounded,
                          text: 'Alles bleibt verschluesselt auf dem Geraet.',
                        ),
                        const SizedBox(height: 12),
                        _trustRow(
                          icon: Icons.bolt_outlined,
                          text: 'Ein Tap importiert deinen Chrome-Verlauf.',
                        ),
                        const SizedBox(height: 12),
                        _trustRow(
                          icon: Icons.delete_outline_rounded,
                          text:
                              'Die Datei wird sofort nach dem Import geloescht.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Aktions-Bereich (unten, Daumen-Reichweite)
              _heroButton(
                label: _busy
                    ? 'Einen Moment …'
                    : 'Verlauf importieren & loslegen',
                icon: Icons.history_rounded,
                onTap: _busy ? null : _handleImport,
                busy: _busy,
              ),
              const SizedBox(height: 10),
              // Sekundaerer CTA: Interessen waehlen statt Verlauf importieren.
              // Bewusst Outline-Style — kein Konkurrenz-Lila zum Hero-Button.
              OutlinedButton.icon(
                onPressed: _busy ? null : _handleInterests,
                style: OutlinedButton.styleFrom(
                  foregroundColor: FindUXProTheme.primaryPurple,
                  side: BorderSide(
                    color: FindUXProTheme.primaryPurple
                        .withValues(alpha: 0.45),
                    width: 1.4,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text(
                  'Statt Verlauf: Interessen waehlen',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _handleSkip,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black54,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text(
                  'Ohne alles starten',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Du kannst alles jederzeit in den Einstellungen aendern.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trustRow({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon,
            size: 20, color: FindUXProTheme.primaryPurple),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              height: 1.35,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: FindUXProTheme.primaryPurple,
        borderRadius: BorderRadius.circular(20),
        boxShadow: onTap == null
            ? []
            : [
                BoxShadow(
                  color: FindUXProTheme.primaryPurple
                      .withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
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
