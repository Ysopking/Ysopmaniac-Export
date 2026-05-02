import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:findux_mobile/l10n/app_localizations.dart';
import '../logic/state_provider.dart';
import '../services/chrome_import_quick.dart';
import '../theme.dart';

/// Schlankes 4-Schritt-Onboarding im Light-Card-Stil (Option 3 aus dem
/// Mock-Up). Quellen-/Dateitypen-/Suchmaschinen-Auswahl ist bewusst raus –
/// die Quellen+Dateitypen erscheinen erst NACH der ersten Suche als
/// "Erweiterte Suche". Suchmaschine wird nicht mehr abgefragt (Default Google).
class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _page = 1;
  static const int _totalPages = 5;
  bool _chronikDone = false;

  // Schritt 1: Beschaeftigung
  String _employmentType = 'student';
  final TextEditingController _berufController = TextEditingController();

  // Schritt 2: Geburtsjahr
  late int _geburtsjahr;

  // Schritt 3: Sprache + Region + PLZ
  String _language = 'de';
  String _country = 'de';
  final TextEditingController _plzController = TextEditingController();

  // Schritt 4: Feedback + Jugendschutz
  bool _allowFeedback = false;
  bool _enableYouthProtection = true;

  static const _employmentLabels = <String, String>{
    'student': 'Student / Schueler / Azubi',
    'rentner': 'Rentner / Pension',
    'vollzeit': 'Vollzeit',
    'teilzeit': 'Teilzeit',
    'erwerbslos': 'Erwerbslos / Job-Suche',
  };

  static const _languages = <List<String>>[
    ['de', 'Deutsch'],
    ['en', 'English'],
  ];
  static const _countries = <List<String>>[
    ['de', 'Deutschland'],
    ['at', 'Oesterreich'],
    ['ch', 'Schweiz'],
    ['us', 'USA'],
    ['uk', 'Grossbritannien'],
  ];

  @override
  void initState() {
    super.initState();
    _geburtsjahr = 1990;
  }

  @override
  void dispose() {
    _berufController.dispose();
    _plzController.dispose();
    super.dispose();
  }

  bool get _needsJobrichtung =>
      _employmentType == 'vollzeit' || _employmentType == 'teilzeit';

  void _go(int p) {
    if (p < 1 || p > _totalPages) return;
    setState(() => _page = p);
  }

  Future<void> _saveAll() async {
    final notifier = ref.read(settingsProvider.notifier);
    final newState = SettingsState(
      plz: _plzController.text.trim(),
      employmentType: _employmentType,
      beruf: _needsJobrichtung ? _berufController.text.trim() : '',
      searchEngine: 'google', // fest – nicht mehr im Onboarding
      language: _language,
      country: _country,
      allowFeedback: _allowFeedback,
      enableYouthProtection: _enableYouthProtection,
      jahr: _geburtsjahr,
      sources: const ['alle'],
      files: const ['alle'],
      mode: 'standard',
      openInApp: true,
      enableVolumeShortcut: false,
    );
    await notifier.updateSettings(newState);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: Column(
          children: [
            // Kopfbereich: Titel + Schritt-Anzeige
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  const Text(
                    'FindUX Pro',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: FindUXProTheme.primaryPurple
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_page / $_totalPages',
                      style: const TextStyle(
                        color: FindUXProTheme.primaryPurple,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _page / _totalPages,
                  backgroundColor: const Color(0xFFE5E5EA),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      FindUXProTheme.primaryPurple),
                  minHeight: 6,
                ),
              ),
            ),
            // Inhalt
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: _buildPage(),
              ),
            ),
            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(
                children: [
                  if (_page > 1)
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: const BorderSide(color: Color(0xFFD1D1D6)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => _go(_page - 1),
                        child: Text(
                            AppLocalizations.of(context)!.back),
                      ),
                    ),
                  if (_page > 1) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FindUXProTheme.primaryPurple,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        HapticFeedback.selectionClick();
                        if (_page == 1 && _needsJobrichtung &&
                            _berufController.text.trim().isEmpty) {
                          _showError(
                              'Bitte gib deine Jobrichtung an (z.B. IT, Pflege, Handwerk).');
                          return;
                        }
                        if (_page == _totalPages) {
                          await _saveAll();
                          widget.onComplete();
                        } else {
                          _go(_page + 1);
                        }
                      },
                      child: Text(
                        _page == _totalPages
                            ? AppLocalizations.of(context)!.start
                            : AppLocalizations.of(context)!.next,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------- Pages ----------

  Widget _buildPage() {
    switch (_page) {
      case 1:
        return _buildPageBeruf();
      case 2:
        return _buildPageJahrgang();
      case 3:
        return _buildPageRegion();
      case 4:
        return _buildPageChronik();
      case 5:
        return _buildPageFinish();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPageChronik() {
    return _section(
      title: 'Chronik importieren',
      subtitle:
          'Damit FindUX deine Suchen besser priorisieren kann, empfehlen '
          'wir, deinen Chrome-Verlauf einmalig lokal zu importieren. '
          'Die Datei wird auf 4 Felder reduziert (Query, Domain, Titel, '
          'Wochenbucket) und sofort geloescht. Nichts verlaesst dein Geraet.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _whiteCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _chronikDone
                            ? Icons.check_circle_rounded
                            : Icons.shield_outlined,
                        color: _chronikDone
                            ? Colors.green
                            : FindUXProTheme.primaryPurple,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _chronikDone
                              ? 'Chronik wurde importiert'
                              : 'Schutz: max. 50 MB, nur http(s), '
                                  '200 k Eintraege harter Cap, '
                                  'keine Ausreisser-Bumps',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FindUXProTheme.primaryPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.history_rounded),
                    label: Text(_chronikDone
                        ? 'Erneut importieren'
                        : 'Verlauf jetzt importieren'),
                    onPressed: () async {
                      // Stage F: Ein-Klick-Import direkt hier — keine
                      // Zwischen-Navigation. File-Picker -> Analyze ->
                      // Persist -> SnackBar in einem Rutsch.
                      final ok = await quickImportChrome(context);
                      if (mounted && ok) {
                        setState(() => _chronikDone = true);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.black54,
              ),
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() => _chronikDone = true);
                _go(_page + 1);
              },
              child: const Text(
                'Habe keinen Chrome-Verlauf — ueberspringen',
                style: TextStyle(
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Du kannst das spaeter in den Einstellungen jederzeit nachholen.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageBeruf() {
    return _section(
      title: 'Was beschreibt dich am besten?',
      subtitle:
          'Wir nutzen das nur lokal, um dir passendere Quellen vorzuschlagen.',
      child: Column(
        children: [
          ..._employmentLabels.entries.map((e) => _buildRadioCard(
                value: e.key,
                groupValue: _employmentType,
                title: e.value,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _employmentType = e.key);
                },
              )),
          if (_needsJobrichtung) ...[
            const SizedBox(height: 16),
            _whiteCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Jobrichtung',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _berufController,
                    // Stage F Haertung: keine IME-Vorschlaege, keine
                    // Auto-Korrektur, kein Smart-Quotes — die Eingabe
                    // soll nicht in Personalisierungs-Modelle der Tastatur
                    // wandern.
                    autocorrect: false,
                    enableSuggestions: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    decoration: const InputDecoration(
                      hintText: 'z.B. IT, Pflege, Marketing, Handwerk',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPageJahrgang() {
    final now = DateTime.now().year;
    final years = List<int>.generate(now - 1919, (i) => now - i);
    return _section(
      title: 'Geburtsjahr',
      subtitle:
          'Hilft uns, zeitliche Filter und Themen sinnvoll vorzubelegen.',
      child: _whiteCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showYearPicker(years),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.cake_outlined,
                    color: FindUXProTheme.primaryPurple),
                const SizedBox(width: 12),
                Text('$_geburtsjahr',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                const Icon(Icons.arrow_drop_down, color: Colors.black54),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageRegion() {
    return _section(
      title: 'Sprache & Region',
      subtitle: 'Wir leiten daraus Such-Sprache und Land-Filter ab.',
      child: Column(
        children: [
          _stackedPicker(
            label: 'Sprache',
            value: _languages
                .firstWhere((l) => l[0] == _language,
                    orElse: () => ['de', 'Deutsch'])[1],
            icon: Icons.language,
            onTap: () => _showStringPicker(
              _languages,
              _language,
              (v) => setState(() => _language = v),
            ),
          ),
          const SizedBox(height: 12),
          _stackedPicker(
            label: 'Land',
            value: _countries
                .firstWhere((c) => c[0] == _country,
                    orElse: () => ['de', 'Deutschland'])[1],
            icon: Icons.public,
            onTap: () => _showStringPicker(
              _countries,
              _country,
              (v) => setState(() => _country = v),
            ),
          ),
          const SizedBox(height: 12),
          _whiteCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.location_on_outlined,
                        color: FindUXProTheme.primaryPurple, size: 20),
                    SizedBox(width: 8),
                    Text('Postleitzahl (optional)',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _plzController,
                  keyboardType: TextInputType.number,
                  // Stage F Haertung: PLZ ist personenbezogen — keine
                  // IME-Lern-Daten generieren.
                  autocorrect: false,
                  enableSuggestions: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  decoration: const InputDecoration(
                    hintText: 'z.B. 10115',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageFinish() {
    return _section(
      title: 'Fast geschafft!',
      subtitle: 'Du kannst diese Optionen spaeter jederzeit aendern.',
      child: Column(
        children: [
          _switchCard(
            icon: Icons.thumbs_up_down_outlined,
            title: 'Feedback ermoeglichen',
            subtitle: 'Hilft, deine Suche kontinuierlich zu verbessern.',
            value: _allowFeedback,
            onChanged: (v) => setState(() => _allowFeedback = v),
          ),
          const SizedBox(height: 12),
          _switchCard(
            icon: Icons.shield_outlined,
            title: 'Jugendschutz',
            subtitle: 'SafeSearch + Negativ-Filter aktivieren.',
            value: _enableYouthProtection,
            onChanged: (v) => setState(() => _enableYouthProtection = v),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FindUXProTheme.primaryPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline,
                    color: FindUXProTheme.primaryPurple, size: 22),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Deine Daten werden verschluesselt nur auf diesem Geraet gespeichert.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Bausteine ----------

  Widget _section(
      {required String title,
      required String subtitle,
      required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                letterSpacing: -0.5)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: const TextStyle(fontSize: 15, color: Colors.black54)),
        const SizedBox(height: 24),
        child,
      ],
    );
  }

  Widget _whiteCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }

  Widget _buildRadioCard({
    required String value,
    required String groupValue,
    required String title,
    required VoidCallback onTap,
  }) {
    final selected = value == groupValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? FindUXProTheme.primaryPurple.withValues(alpha: 0.08)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? FindUXProTheme.primaryPurple
                  : const Color(0xFFE5E5EA),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected
                    ? FindUXProTheme.primaryPurple
                    : Colors.black26,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stackedPicker({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return _whiteCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, color: FindUXProTheme.primaryPurple, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(value,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return _whiteCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: FindUXProTheme.primaryPurple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: FindUXProTheme.primaryPurple, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CupertinoSwitch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: FindUXProTheme.primaryPurple,
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Picker ----------

  void _showYearPicker(List<int> years) {
    final initial = years.indexOf(_geburtsjahr);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) {
        // Bottom-Insets (Gesten-Bar / Tastatur) miteinrechnen, damit der
        // OK-Button auch auf kleinen Screens nicht ueber den unteren Rand
        // hinaus schiebt. Picker-Hoehe bewusst klein gehalten (180).
        final bottom = MediaQuery.of(ctx).viewInsets.bottom +
            MediaQuery.of(ctx).viewPadding.bottom;
        return Container(
          color: Colors.white,
          padding: EdgeInsets.only(bottom: bottom),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 180,
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                        initialItem: initial < 0 ? 0 : initial),
                    itemExtent: 32,
                    onSelectedItemChanged: (i) =>
                        setState(() => _geburtsjahr = years[i]),
                    children: years
                        .map((y) => Center(child: Text('$y')))
                        .toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: CupertinoButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showStringPicker(List<List<String>> data, String currentValue,
      void Function(String) onSave) {
    final initialIndex = data.indexWhere((d) => d[0] == currentValue);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom +
            MediaQuery.of(ctx).viewPadding.bottom;
        return Container(
          color: Colors.white,
          padding: EdgeInsets.only(bottom: bottom),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 180,
                  child: CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                        initialItem:
                            initialIndex < 0 ? 0 : initialIndex),
                    itemExtent: 36,
                    onSelectedItemChanged: (i) => onSave(data[i][0]),
                    children: data
                        .map((d) => Center(child: Text(d[1])))
                        .toList(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: CupertinoButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
