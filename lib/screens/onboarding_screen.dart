import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logic/state_provider.dart';
import '../screens/interests_screen.dart';
import '../services/chrome_import_quick.dart';
import '../services/haptic_helper.dart';
import '../data/locale_catalog.dart';
import '../theme.dart';

/// Stage 15: Pflicht-Stammdaten-Wizard.
///
/// Frueher: Hero-Screen mit drei Buttons — User konnte alles ueberspringen
/// und landete mit Default-Werten im Hauptscreen, Settings sahen leer aus.
///
/// Jetzt: 6-Schritt-Wizard. "Weiter" ist erst klickbar, wenn die
/// Pflichtfelder des aktuellen Schritts erfuellt sind:
///
///   0  Willkommen           (Pflicht: Tap auf Weiter)
///   1  Geburtsjahr          (Pflicht — Jahr aktiv im Picker waehlen,
///                            wegen Jugendschutz-Auto-Lock <18)
///   2  Beschaeftigung       (Pflicht — beeinflusst Such-Heuristik)
///   3  PLZ                  (Optional — Weiter geht auch leer)
///   4  Sprache + Land       (Pflicht, mit Default DE/DE — also nur
///                            ein Tap zum Bestaetigen noetig)
///   5  Interessen ODER      (Pflicht — eines der beiden muss erledigt
///      Verlauf-Import        sein, damit das Lern-Modell startet)
///
/// Erst nach Schritt 5 -> persistAll -> onComplete -> Hauptscreen.
class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;
  const OnboardingScreen({super.key, required this.onComplete});

  @override
  ConsumerState<OnboardingScreen> createState() =>
      _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _kTotalSteps = 7;

  // Aktueller Schritt-Index 0..5
  int _step = 0;

  // Pflicht-Erfuellung: pro Schritt true sobald User aktiv interagiert hat
  bool _yearPicked = false;
  bool _jobPicked = false;
  bool _interestsDone = false;
  bool _importDone = false;

  // Lokale Eingabe-Puffer — werden erst beim Onboarding-Ende persistiert
  // (bzw. vor dem Oeffnen von InterestsScreen / Chrome-Import).
  final _plzController = TextEditingController();
  int _yearLocal = 1990;
  String _jobLocal = 'student';
  String _familyStatus = 'single'; // 'single' | 'familie' | 'alleinerziehend'
  String _languageLocal = 'de';
  String _countryLocal = 'de';

  // Vom Wizard gesammelte Werte (nur hier verwendet, bis persistAll())
  int? _birthYear;
  List<String>? _interestsSelected;

  bool _busy = false;

  static const _employmentLabels = <String, String>{
    'student': 'Student / Schueler / Azubi',
    'rentner': 'Rentner / Pension',
    'vollzeit': 'Vollzeit',
    'teilzeit': 'Teilzeit',
    'erwerbslos': 'Erwerbslos / Job-Suche',
  };

  @override
  void dispose() {
    _plzController.dispose();
    super.dispose();
  }

  // Pflicht-Pruefung pro Schritt
  bool get _stepValid {
    switch (_step) {
      case 0:
        return true; // Welcome: nur Tap auf Weiter
      case 1:
        return _yearPicked;
      case 2:
        return _jobPicked;
      case 3:
        return true; // Familienstatus hat Default
      case 4:
        return true; // PLZ optional
      case 5:
        return true; // Sprache/Land hat Default
      case 6:
        return _interestsDone || _importDone;
      default:
        return false;
    }
  }

  Future<void> _persistAll() async {
    final notifier = ref.read(settingsProvider.notifier);
    // Stage 15: bereits gewaehlte Interessen NICHT ueberschreiben —
    // wenn der User in Schritt 5 schon InterestsScreen besucht hat,
    // sind die im Provider und sollen erhalten bleiben.
    final currentInterests = ref.read(settingsProvider).interests;
     await notifier.updateSettings(SettingsState(
       plz: _plzController.text.trim(),
       employmentType: _jobLocal,
       familyStatus: _familyStatus,
       beruf: '',
       searchEngine: 'google',
       language: 'de',
       country: 'de',
       allowFeedback: true,
       enableYouthProtection: true,
       jahr: _birthYear ?? 1990,
       sources: const ['alle'],
       files: const ['alle'],
       mode: 'standard',
       openInApp: true,
       enableVolumeShortcut: false,
       interests: _interestsSelected?.isEmpty ?? true ? const [] : _interestsSelected!.toList(growable: false),
       autoSearchDelay: 300,
       disableScreenshots: true,
     ));
  }

  Future<void> _onNext() async {
    if (!_stepValid || _busy) return;
    Haptics.tap();
    if (_step < _kTotalSteps - 1) {
      setState(() => _step += 1);
    } else {
      setState(() => _busy = true);
      await _persistAll();
      if (!mounted) return;
      // Starter-Gewichte einmalig basierend auf Beschaeftigung + Familienstatus setzen
      await ref.read(learningServiceProvider).seedStarterWeights(_jobLocal);
      if (!mounted) return;
      await ref.read(learningServiceProvider).seedStarterFamilyWeights(_familyStatus);
      if (!mounted) return;
      Haptics.done();
      widget.onComplete();
    }
  }

  void _onBack() {
    if (_step == 0 || _busy) return;
    Haptics.tap();
    setState(() => _step -= 1);
  }

  Future<void> _runInterests() async {
    if (_busy) return;
    setState(() => _busy = true);
    Haptics.tap();
    // Provider muss initialisiert sein, bevor InterestsScreen schreibt.
    await _persistAll();
    if (!mounted) return;
    await Navigator.of(context).push(const 
      MaterialPageRoute(builder: (_) => const InterestsScreen()),
    );
    if (!mounted) return;
    final hasAny = ref.read(settingsProvider).interests.isNotEmpty;
    setState(() {
      _busy = false;
      _interestsDone = hasAny;
    });
    if (hasAny) Haptics.done();
  }

  Future<void> _runImport() async {
    if (_busy) return;
    setState(() => _busy = true);
    Haptics.tap();
    await _persistAll();
    if (!mounted) return;
    final ok = await quickImportChrome(context);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _importDone = true;
    });
    if (ok) Haptics.done();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            _ProgressBar(step: _step + 1, total: _kTotalSteps),const 
            Expanded(child: _buildStep(_step)),
            _BottomBar(
              showBack: _step > 0,
              isLast: _step == _kTotalSteps - 1,
              enabled: _stepValid && !_busy,
              busy: _busy,
              onBack: _onBack,
              onNext: _onNext,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int s) {
    switch (s) {
      case 0:
        return _step0Welcome();
      case 1:
        return _step1Year();
      case 2:
        return _step2Job();
      case 3:
        return _step3Family();
      case 4:
        return _step4Plz();
      case 5:
        return _step5Locale();
      case 6:
        return _step6Action();
      default:
        return const SizedBox();
    }
  }

  // ---------- Schritte ----------

  Widget _step0Welcome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        children: [
          const SizedBox(height: 16),const 
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [const 
                BoxShadow(
                  color: FindUXProTheme.primaryPurple
                      .withValues(alpha: 0.22),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
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
                      size: 48, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Willkommen bei\nFindUX Pro',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.0,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 12),const 
          Text(
            'In wenigen Schritten richten wir die App so ein, dass '
            'deine Suchen besser werden — komplett ohne Konto, '
            'ohne Cloud, alles bleibt verschluesselt auf diesem Geraet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: Colors.black.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          _trustRow(Icons.lock_outline_rounded,
              'Alles verschluesselt im Geraete-Vault.'),
          const SizedBox(height: 10),
          _trustRow(Icons.bolt_outlined,
              'Lernt aus deinen Suchgewohnheiten.'),
          const SizedBox(height: 10),
          _trustRow(Icons.delete_outline_rounded,
              'Du kannst alles jederzeit loeschen.'),
        ],
      ),
    );
  }

  Widget _step1Year() {
    final now = DateTime.now().year;
    final years = List<int>.generate(now - 1919, (i) => now - i);
    final initial = years.indexOf(_yearLocal);
    return _StepLayout(
      title: 'Geburtsjahr',
      subtitle:
          'Brauchen wir fuer den Jugendschutz. Bei Alter unter 18 wird '
          'sicheres Suchen automatisch erzwungen.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [const 
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 220,
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(
                    initialItem: initial < 0 ? 0 : initial),
                itemExtent: 36,
                onSelectedItemChanged: (i) {
                  Haptics.pick();
                  setState(() {
                    _yearLocal = years[i];
                    _yearPicked = true;
                  });
                },
                children: years
                    .map((y) => Center(
                          child: Text(
                            '$y',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 14),const 
          Text(
            _yearPicked
                ? 'Ausgewaehlt: $_yearLocal'
                : 'Bitte scrollen, um dein Geburtsjahr zu waehlen.',
            style: TextStyle(
              fontSize: 14,
              color: _yearPicked
                  ? FindUXProTheme.primaryPurple
                  : Colors.black54,
              fontWeight:
                  _yearPicked ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _step2Job() {
    return _StepLayout(
      title: 'Beschaeftigung',
      subtitle: 'Beeinflusst, wie wir deine Suchen formulieren — z.B. '
          'wissenschaftliche Quellen fuer Studenten, Fachportale fuer '
          'Vollzeit-Berufe.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in _employmentLabels.entries)
            _RadioRow(
              label: e.value,
              selected: _jobLocal == e.key,
              onTap: () {
                Haptics.pick();
                setState(() {
                  _jobLocal = e.key;
                  _jobPicked = true;
                });
              },
            ),
        ],
      ),
    );
  }


  static const _familyLabels = <String, String>{
    'single':          'Single / Paar (keine Kinder)',
    'familie':         'Familie',
    'alleinerziehend': 'Alleinerziehend',
  };

  Widget _step3Family() {
    return _StepLayout(
      title: 'Familiensituation',
      subtitle: 'Eine leichte Voranpassung der Such-Heuristik — '
          'wird durch deine Interessen und deinen Verlauf weiter verfeinert.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _familyLabels.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SegmentChip(
              label: e.value,
              selected: _familyStatus == e.key,
              onTap: () {
                Haptics.pick();
                setState(() => _familyStatus = e.key);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _step4Plz() {
    return _StepLayout(
      title: 'Postleitzahl',
      subtitle: 'Optional — kann lokale Suchen verbessern (z.B. '
          '"Restaurant in der Naehe"). Du kannst diesen Schritt auch '
          'leer lassen.',
      child: TextField(
        controller: _plzController,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enableSuggestions: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        maxLength: 5,
        decoration: InputDecoration(
          hintText: 'z.B. 79100',
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 16),
        ),
        style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _step5Locale() {
    return _StepLayout(
      title: 'Sprache & Land',
      subtitle: 'Mit welcher Sprache suchst du? Und in welchem Land bist du?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Suchsprache',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.black54,
                  letterSpacing: 0.5)),
          const SizedBox(height: 10),
          // 2×3 Sprach-Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.8,
            ),
            itemCount: kLanguages.length,
            itemBuilder: (_, i) {
              final lang = kLanguages[i];
              final sel = _languageLocal == lang.code;
              return GestureDetector(
                onTap: () {
                  Haptics.pick();
                  setState(() => _languageLocal = lang.code);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: sel ? const Color(0xFF6C4AB6) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sel ? const Color(0xFF6C4AB6) : Colors.black12,
                      width: sel ? 1.8 : 1,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: [const 
                      Text(lang.flag, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 7),const 
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [const 
                            Text(lang.nativeLabel,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: sel ? Colors.white : Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis),const 
                            Text(lang.germanLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: sel ? Colors.white70 : Colors.black45,
                                ),
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text('Land',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.black54,
                  letterSpacing: 0.5)),
          const SizedBox(height: 8),
          // Land-Picker-Button: öffnet Suchbare Bottom-Sheetconst 
          GestureDetector(
            onTap: () => _pickCountry(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: Row(
                children: [const 
                  Text(
                    kCountries.firstWhere(
                      (c) => c.code == _countryLocal,
                      orElse: () => const LocaleCountry(code:'de',flag:'🇩🇪',label:'Deutschland'),
                    ).flag,
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 10),const 
                  Expanded(
                    child: Text(
                      kCountries.firstWhere(
                        (c) => c.code == _countryLocal,
                        orElse: () => const LocaleCountry(code:'de',flag:'🇩🇪',label:'Deutschland'),
                      ).label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded, color: Colors.black38, size: 22),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCountry() async {
    Haptics.tap();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CountryPickerSheet(selected: _countryLocal),
    );
    if (picked != null && mounted) {
      setState(() => _countryLocal = picked);
    }
  }

  Widget _step6Action() {
    final interestsCount =
        ref.watch(settingsProvider).interests.length;
    return _StepLayout(
      title: 'Letzter Schritt',
      subtitle: 'Wir brauchen einen Startpunkt fuer das Lern-Modell — '
          'entweder du waehlst Interessen ODER importierst deinen '
          'Chrome-Verlauf. Eines von beiden reicht (gerne auch beides).',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionCard(
            icon: Icons.tune_rounded,
            title: 'Interessen waehlen',
            subtitle: _interestsDone
                ? 'Erledigt — $interestsCount ausgewaehlt'
                : 'Aus 12 Bereichen mit je 6 Themen — auch eigene '
                    'Eintraege moeglich.',
            done: _interestsDone,
            onTap: _runInterests,
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.history_rounded,
            title: 'Chrome-Verlauf importieren',
            subtitle: _importDone
                ? 'Verlauf importiert — Datei direkt geloescht.'
                : 'Wir lesen einmalig deine Chrome-History (.zip / .csv) '
                    'und loeschen die Datei danach sofort.',
            done: _importDone,
            onTap: _runImport,
          ),
          const SizedBox(height: 16),
          if (!_stepValid)const 
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Mindestens eines der beiden waehlen, um fortzufahren.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- Helpers ----------

  Widget _trustRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const 
        Icon(icon, size: 18, color: FindUXProTheme.primaryPurple),
        const SizedBox(width: 12),const 
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

// ===================== Helper Widgets =====================

class _StepLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _StepLayout({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const 
          Text(title,
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                  color: Colors.black)),
          const SizedBox(height: 10),const 
          Text(subtitle,
              style: TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                  color: Colors.black.withValues(alpha: 0.6))),
          const SizedBox(height: 28),
          child,
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int step;
  final int total;
  const _ProgressBar({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [const 
          Text('Schritt $step von $total',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54)),
          const SizedBox(width: 12),const 
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: step / total,
                minHeight: 4,
                backgroundColor: Colors.black.withValues(alpha: 0.06),
                valueColor: const AlwaysStoppedAnimation<Color>(
                    FindUXProTheme.primaryPurple),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool showBack;
  final bool isLast;
  final bool enabled;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onNext;
  const _BottomBar({
    required this.showBack,
    required this.isLast,
    required this.enabled,
    required this.busy,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          if (showBack)const 
            TextButton(
              onPressed: busy ? null : onBack,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 14),
                foregroundColor: Colors.black54,
              ),
              child: const Text('Zurueck',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          const Spacer(),const 
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: enabled
                  ? FindUXProTheme.primaryPurple
                  : Colors.black.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              boxShadow: enabled
                  ? [const 
                      BoxShadow(
                        color: FindUXProTheme.primaryPurple
                            .withValues(alpha: 0.32),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: enabled ? onNext : null,
                child: Container(
                  constraints:
                      const BoxConstraints(minHeight: 52, minWidth: 140),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (busy) ...[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],const 
                      Text(isLast ? 'Fertig' : 'Weiter',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2)),
                      if (!busy) ...[
                        const SizedBox(width: 8),const 
                        Icon(
                            isLast
                                ? Icons.check_rounded
                                : Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 18),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? FindUXProTheme.primaryPurple
                    : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: Row(
              children: [const 
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: selected
                          ? FindUXProTheme.primaryPurple
                          : Colors.black87,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle_rounded,
                      color: FindUXProTheme.primaryPurple, size: 22)
                elseconst 
                  Icon(Icons.radio_button_unchecked_rounded,
                      color: Colors.black.withValues(alpha: 0.25),
                      size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          color: selected
              ? FindUXProTheme.primaryPurple
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? FindUXProTheme.primaryPurple
                : Colors.black.withValues(alpha: 0.08),
            width: 1.4,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : Colors.black87,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback onTap;
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: done
                  ? FindUXProTheme.primaryPurple
                      .withValues(alpha: 0.6)
                  : Colors.transparent,
              width: 1.6,
            ),
          ),
          child: Row(
            children: [const 
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: FindUXProTheme.primaryPurple
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    color: FindUXProTheme.primaryPurple, size: 22),
              ),
              const SizedBox(width: 14),const 
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [const 
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                            letterSpacing: -0.3)),
                    const SizedBox(height: 4),const 
                    Text(subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: done
                              ? FindUXProTheme.primaryPurple
                              : Colors.black.withValues(alpha: 0.55),
                          fontWeight: done
                              ? FontWeight.w700
                              : FontWeight.w500,
                        )),
                  ],
                ),
              ),
              if (done)
                const Icon(Icons.check_circle_rounded,
                    color: FindUXProTheme.primaryPurple, size: 22)
              else
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.black26, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}


class _CountryPickerSheet extends StatefulWidget {
  final String selected;
  const _CountryPickerSheet({required this.selected});
  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _ctrl = TextEditingController();
  List<LocaleCountry> _filtered = kCountries;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final q = _ctrl.text.toLowerCase().trim();
      setState(() {
        _filtered = q.isEmpty
            ? kCountries
            : kCountries.where((c) =>
                c.label.toLowerCase().contains(q) ||
                c.code.contains(q)).toList();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5F5F7),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),const 
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),const 
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Land suchen...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),const 
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: _filtered.length,
                itemExtent: 52,
                itemBuilder: (_, i) {
                  final c = _filtered[i];
                  final sel = c.code == widget.selected;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, c.code),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        decoration: BoxDecoration(
                          color: sel ? const Color(0xFF6C4AB6).withValues(alpha:0.08) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [const 
                            Text(c.flag, style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 12),const 
                            Expanded(
                              child: Text(
                                c.label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                  color: sel ? const Color(0xFF6C4AB6) : Colors.black87,
                                ),
                              ),
                            ),const 
                            Text(c.code.toUpperCase(),
                                style: const TextStyle(fontSize: 12, color: Colors.black38)),
                            if (sel)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(Icons.check_rounded,
                                    size: 18, color: Color(0xFF6C4AB6)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
