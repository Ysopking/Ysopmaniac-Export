import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:findux_mobile/l10n/app_localizations.dart';
import '../logic/state_provider.dart';
import '../screens/interests_screen.dart';
import '../services/chrome_import_quick.dart';
import '../services/haptic_helper.dart';
import '../theme.dart';
import '../data/locale_catalog.dart';
import '../coach/precision_advisor.dart';
import '../services/pin_rotation_checker.dart';

/// Apple-UX-Settings (Stage G):
///
/// Frueher: 14 Tiles auf einer Ebene, jede in eigener Card mit Schatten,
/// 4 Sektionen — visuelles Rauschen ueberall, jeder Toggle gleich
/// gewichtet, jede Aktion gleich laut.
///
/// Jetzt im iOS-Stil:
/// - 3 inhaltliche Bloecke ("Ueber mich", "Suche", "Datenschutz")
/// - jeder Block ist EINE weisse Card, in der Zeilen durch
///   Haar-Linien getrennt sind (kein Schatten pro Zeile)
/// - die "lautesten" Aktionen oben, Power-User-Optionen hinter
///   "Erweitert" (progressive disclosure)
/// - destruktive Aktionen visuell separiert am Ende
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _showAdvancedAboutMe = false;
  bool _showAdvancedSearch = false;
  // E1: Lernprofil-Panel — async geladen
  PrecisionRecommendation? _profileAdvice;
  bool _profileLoading = false;

  static const _employmentLabels = <String, String>{
    'student': 'Student / Schueler / Azubi',
    'rentner': 'Rentner / Pension',
    'vollzeit': 'Vollzeit',
    'teilzeit': 'Teilzeit',
    'erwerbslos': 'Erwerbslos / Job-Suche',
  };

  static const _familyStatusLabels = <String, String>{
    'single': 'Ledig / Single',
    'familie': 'Familie / mit Kindern',
    'alleinerziehend': 'Alleinerziehend',
  };

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (_profileLoading) return;
    setState(() => _profileLoading = true);
    final rec = await PrecisionAdvisor.analyze();
    if (mounted) setState(() { _profileAdvice = rec; _profileLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final needsJob = settings.employmentType == 'vollzeit' ||
        settings.employmentType == 'teilzeit';
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black, size: 20),
          onPressed: () {
            Haptics.tap();
            Navigator.pop(context);
          },
        ),
        title: Text(
          l10n.settingsTitle,
          style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // -------- Block 1: Ueber mich --------
          _sectionLabel('Ueber mich'),
          _groupCard(children: [
            _row(
              icon: Icons.person_outline_rounded,
              title: 'Beschaeftigung',
              value: _employmentLabels[settings.employmentType] ??
                  settings.employmentType,
              onTap: () => _showEmploymentPicker(
                  context, ref, settings.employmentType),
            ),
            if (needsJob)
              _row(
                icon: Icons.work_outline_rounded,
                title: 'Jobrichtung',
                value: settings.beruf.isEmpty
                    ? 'Optional'
                    : settings.beruf,
                onTap: () => _showTextDialog(
                  context,
                  title: 'Jobrichtung',
                  hint: 'z.B. IT, Pflege, Marketing, Handwerk',
                  initial: settings.beruf,
                  onSave: (v) => notifier.updateField(beruf: v),
                ),
              ),
            _row(
              icon: Icons.family_restroom_rounded,
              title: 'Familienstatus',
              value: _familyStatusLabels[settings.familyStatus] ??
                  settings.familyStatus,
              onTap: () => _showFamilyStatusPicker(
                  context, ref, settings.familyStatus),
            ),
            _row(
              icon: Icons.cake_outlined,
              title: 'Geburtsjahr',
              value: '${settings.jahr}',
              onTap: () => _showYearPicker(context, ref, settings.jahr),
            ),
            _row(
              icon: Icons.interests_outlined,
              title: 'Meine Interessen',
              value: settings.interests.isEmpty
                  ? 'Hinzufuegen'
                  : '${settings.interests.length} ausgewaehlt',
              onTap: () {
                Haptics.tap();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const InterestsScreen()),
                );
              },
            ),
            _expandRow(
              expanded: _showAdvancedAboutMe,
              onToggle: () => setState(
                  () => _showAdvancedAboutMe = !_showAdvancedAboutMe),
              hiddenCount: 3,
            ),
            if (_showAdvancedAboutMe) ...[
              _row(
                icon: Icons.location_on_outlined,
                title: l10n.zipLabel,
                value: settings.plz.isEmpty ? 'Optional' : settings.plz,
                onTap: () => _showTextDialog(
                  context,
                  title: l10n.zipLabel,
                  hint: 'z.B. 10115',
                  initial: settings.plz,
                  keyboard: TextInputType.number,
                  onSave: (v) => notifier.updateField(plz: v),
                ),
              ),
              _row(
                icon: Icons.language_rounded,
                title: l10n.languageLabel,
                value: () {
                  final lang = kLanguages.firstWhere(
                    (l) => l.code == settings.language,
                    orElse: () => kLanguages.first,
                  );
                  return '${lang.flag} ${lang.nativeLabel}';
                }(),
                onTap: () => _showLanguagePicker(context, ref, settings.language),
              ),
              _row(
                icon: Icons.public_rounded,
                title: l10n.countryLabel,
                value: () {
                  final c = kCountries.firstWhere(
                    (c) => c.code == settings.country,
                    orElse: () => const LocaleCountry(code:'de',flag:'🇩🇪',label:'Deutschland'),
                  );
                  return '${c.flag} ${c.label}';
                }(),
                onTap: () => _showCountryPicker(context, ref, settings.country),
              ),
            ],
          ]),

          // -------- Block 2: Suche --------
          _sectionLabel('Suche'),
          _groupCard(children: [
            _toggleRow(
              icon: Icons.open_in_new_rounded,
              title: 'In privatem Browser oeffnen',
              subtitle: 'Daten werden beim Schliessen verworfen',
              value: settings.openInApp,
              onChanged: (v) => notifier.updateField(openInApp: v),
            ),
            // Stage 14: Wenn das Geburtsjahr Alter <18 ergibt, ist der
            // Jugendschutz Pflicht und der Toggle wird gesperrt — der
            // angezeigte Wert ist dann unabhaengig vom rohen Feld immer
            // ON, der Subtitle erklaert warum.
            _toggleRow(
              icon: Icons.shield_outlined,
              title: 'Jugendschutz',
              subtitle: settings.isMinor
                  ? 'Automatisch aktiv (Geburtsjahr unter 18)'
                  : 'SafeSearch + Negativ-Filter',
              value: settings.effectiveYouthProtection,
              enabled: !settings.isMinor,
              onChanged: (v) =>
                  notifier.updateField(enableYouthProtection: v),
            ),
            _expandRow(
              expanded: _showAdvancedSearch,
              onToggle: () => setState(
                  () => _showAdvancedSearch = !_showAdvancedSearch),
              hiddenCount: 1,
            ),
            if (_showAdvancedSearch) ...[
              _toggleRow(
                icon: Icons.volume_up_outlined,

          // -------- Block 3: Datenschutz --------
          // Stage 14: Feedback-Export entfernt — Bewertungen sind jetzt
          // verpflichtend pro neuer Suchrichtung und werden ausschliesslich
          // lokal in der Lern-Engine verwendet (kein Export, kein Versand).
          _sectionLabel('Datenschutz'),
          _groupCard(children: [
            // FLAG_SECURE ist in MainActivity.kt IMMER hart gesetzt
            // (kein Toggle moeglich). SecureFlag hebt es nur kurzzeitig
            // fuer den eingebauten In-App-Browser auf (max 3 Screenshots
            // / 30 s). Der Toggle ist deshalb als Read-Only dargestellt.
            _toggleRow(
              icon: Icons.no_photography_outlined,
              title: 'Screenshots blockieren',
              subtitle: 'Immer aktiv — schuetzt vor Screenshots und Aufnahmen',
              value: true,
              onChanged: (_) {},
              enabled: false,
            ),
            _row(
              icon: Icons.history_rounded,
              title: 'Chrome-Verlauf importieren',
              value: 'Ein Tap',
              onTap: () {
                Haptics.tap();
                quickImportChrome(context);
              },
            ),
          ]),

          // -------- Notbremse separiert --------
          // -------- Block 4: Mein Suchprofil (E1) --------
          _sectionLabel('Mein Suchprofil'),
          _buildProfileCard(),

          // -------- Block 5: Datensicherheit --------
          _sectionLabel('Datensicherheit'),
          _groupCard(children: [
            // C1: TLS-Pin-Ablauf-Warnung (immer sichtbar wenn < 60 Tage)
            if (PinRotationChecker.isPinExpiringSoon)
              _infoRow(
                icon: Icons.security_update_warning_rounded,
                title: 'TLS-Update empfohlen',
                subtitle:
                    'Sicherheits-Pins laufen bald ab (vor ${PinRotationChecker.pinExpiration})',
                color: Colors.orange,
              ),
            // E2: Nur Lernprofil zuruecksetzen
            _row(
              icon: Icons.restart_alt_rounded,
              title: 'Nur Lernprofil zuruecksetzen',
              value: 'Gewichte',
              onTap: () => _confirmResetWeights(context, ref),
            ),
          ]),

          const SizedBox(height: 12),
          _groupCard(
            children: [
              _row(
                icon: Icons.delete_forever_outlined,
                title: 'Alle persoenlichen Daten loeschen',
                value: 'Notbremse',
                destructive: true,
                onTap: () => _confirmWipe(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Alle Eingaben bleiben verschluesselt auf diesem Geraet.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.black.withValues(alpha: 0.45),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Bausteine im iOS-Settings-Stil ----------

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black54,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );

  /// Eine "Card-Gruppe": EIN weisses Container, Zeilen durch Hairlines.
  Widget _groupCard({required List<Widget> children}) {
    final separated = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      separated.add(children[i]);
      if (i < children.length - 1) {
        separated.add(const Padding(
          padding: EdgeInsets.only(left: 56),
          child: Divider(
              height: 1,
              thickness: 0.5,
              color: Color(0xFFE5E5EA)),
        ));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: separated),
    );
  }

  /// Standard-Zeile: Icon + Titel links, Wert + Chevron rechts.
  Widget _row({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive
        ? const Color(0xFFE53935)
        : FindUXProTheme.primaryPurple;
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color:
                      destructive ? color : Colors.black87,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.black26, size: 22),
          ],
        ),
      ),
    );
  }

  /// Toggle-Zeile: Icon + Titel + Subtitle links, Switch rechts.
  Widget _toggleRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    // Stage 14: Wenn enabled=false, wird der Switch ausgegraut und
    // ignoriert Taps — fuer "Pflicht-ON-Zustaende" wie der erzwungene
    // Jugendschutz bei Minderjaehrigen.
    bool enabled = true,
  }) {
    final iconColor = enabled
        ? FindUXProTheme.primaryPurple
        : FindUXProTheme.primaryPurple.withValues(alpha: 0.45);
    final titleColor = enabled ? Colors.black87 : Colors.black54;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.9,
            child: CupertinoSwitch(
              value: value,
              activeTrackColor: FindUXProTheme.primaryPurple,
              onChanged: enabled
                  ? (v) {
                      Haptics.pick();
                      onChanged(v);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// "Mehr anzeigen / Weniger" — progressive disclosure.
  Widget _expandRow({
    required bool expanded,
    required VoidCallback onToggle,
    required int hiddenCount,
  }) {
    return InkWell(
      onTap: () {
        Haptics.tap();
        onToggle();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const SizedBox(width: 40),
            Expanded(
              child: Text(
                expanded ? 'Weniger anzeigen' : 'Mehr anzeigen',
                style: const TextStyle(
                  fontSize: 14,
                  color: FindUXProTheme.primaryPurple,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!expanded)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: FindUXProTheme.primaryPurple
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '+$hiddenCount',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: FindUXProTheme.primaryPurple,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            Icon(
              expanded
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              color: FindUXProTheme.primaryPurple,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Picker / Dialoge ----------

  void _showEmploymentPicker(
      BuildContext context, WidgetRef ref, String current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Beschaeftigung',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            ..._employmentLabels.entries.map((e) => RadioListTile<String>(
                  title: Text(e.value),
                  value: e.key,
                  groupValue: current,
                  activeColor: FindUXProTheme.primaryPurple,
                  onChanged: (v) {
                    if (v != null) {
                      Haptics.pick();
                      ref
                          .read(settingsProvider.notifier)
                          .updateField(employmentType: v);
                      // Beschaeftigung geaendert → Starter-Gewichte
                      // (weight_employment_*, weight_kw_*, weight_filter_*,
                      // weight_mode_*) fuer den neuen Typ neu einsetzen.
                      // Fire-and-forget, da onChanged nicht async ist.
                      // ignore: discarded_futures
                      ref
                          .read(learningServiceProvider)
                          .seedStarterWeights(v);
                    }
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showFamilyStatusPicker(
      BuildContext context, WidgetRef ref, String current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Familienstatus',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            ..._familyStatusLabels.entries.map((e) => RadioListTile<String>(
                  title: Text(e.value),
                  value: e.key,
                  groupValue: current,
                  activeColor: FindUXProTheme.primaryPurple,
                  onChanged: (v) {
                    if (v != null) {
                      Haptics.pick();
                      ref
                          .read(settingsProvider.notifier)
                          .updateField(familyStatus: v);
                      // Familienstatus geaendert → Familiengewichte
                      // (weight_family_*, zugehoerige kw/domain/filter)
                      // fuer den neuen Status neu einsetzen.
                      // ignore: discarded_futures
                      ref
                          .read(learningServiceProvider)
                          .seedStarterFamilyWeights(v);
                    }
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showYearPicker(BuildContext context, WidgetRef ref, int current) {
    final now = DateTime.now().year;
    final years = List<int>.generate(now - 1919, (i) => now - i);
    final initial = years.indexOf(current);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        // Stage 14 Fix: KEINE feste Hoehe mehr. Auf Geraeten mit Gesten-
        // Leiste (Android 10+, iPhone X+) addiert SafeArea ~24-34 px Bottom-
        // Inset, was zusammen mit dem CupertinoButton (~48 px) und dem
        // 220 px-Picker das alte fixe 280 px-Container deutlich
        // ueberschritten und einen "BOTTOM OVERFLOWED BY X PIXELS"-
        // Flutter-Debug-Banner unten am Bildschirm angezeigt hat.
        // Loesung: intrinsische Hoehe via MainAxisSize.min — der
        // Container nimmt genau so viel Platz wie noetig.
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 220,
                child: CupertinoPicker(
                  scrollController: FixedExtentScrollController(
                      initialItem: initial < 0 ? 0 : initial),
                  itemExtent: 36,
                  onSelectedItemChanged: (i) {
                    Haptics.pick();
                    ref
                        .read(settingsProvider.notifier)
                        .updateField(jahr: years[i]);
                  },
                  children:
                      years.map((y) => Center(child: Text('$y'))).toList(),
                ),
              ),
              CupertinoButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTextDialog(
    BuildContext context, {
    required String title,
    required String hint,
    required String initial,
    required ValueChanged<String> onSave,
    TextInputType keyboard = TextInputType.text,
  }) {
    final controller = TextEditingController(text: initial);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: keyboard,
          // Stage F Haertung: keine IME-Lerndaten, keine Auto-Korrektur.
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          TextButton(
            onPressed: () {
              Haptics.done();
              onSave(controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _showLanguagePicker(
      BuildContext ctx, WidgetRef ref, String current) async {
    final notifier = ref.read(settingsProvider.notifier);
    await showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5F5F7),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Suchsprache',
                    style: FindUXProTheme.headlineStyle.copyWith(
                        fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
              ...kLanguages.map((lang) {
                final sel = lang.code == current;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Haptics.pick();
                      notifier.updateField(language: lang.code);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: sel
                            ? FindUXProTheme.primaryPurple.withValues(alpha: 0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text(lang.flag, style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(lang.nativeLabel,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: sel
                                          ? FindUXProTheme.primaryPurple
                                          : Colors.black87,
                                    )),
                                Text(lang.germanLabel,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.black45)),
                              ],
                            ),
                          ),
                          if (sel)
                            Icon(Icons.check_rounded,
                                color: FindUXProTheme.primaryPurple, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCountryPicker(
      BuildContext ctx, WidgetRef ref, String current) async {
    final notifier = ref.read(settingsProvider.notifier);
    final picked = await showModalBottomSheet<String>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettingsCountryPickerSheet(selected: current),
    );
    if (picked != null) {
      notifier.updateField(country: picked);
    }
  }

  void _confirmWipe(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wirklich loeschen?'),
        content: const Text(
            'Alle persoenlichen Daten (Beschaeftigung, PLZ, Jahrgang, '
            'Lern-Modell) werden unwiderruflich entfernt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          TextButton(
            onPressed: () async {
              Haptics.warn();
              await ref.read(settingsProvider.notifier).wipeAll();
              if (context.mounted) {
                // In-Memory-Zustand zuruecksetzen: ohne diese Zeilen
                // bleibt die App auf der Home-Seite stecken (onboarding-
                // Done + auth bleiben im RAM true), obwohl alle Daten
                // geloescht sind. Das Routing in main.dart prueft diese
                // Provider und navigiert beim naechsten Rebuild automatisch
                // zum OnboardingScreen.
                ref.read(authProvider.notifier).state = false;
                ref.read(onboardingDoneProvider.notifier).state = false;
                Navigator.pop(context);
              }
            },
            child:
                const Text('Loeschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmResetWeights(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lernprofil zuruecksetzen?'),
        content: const Text(
            'Alle adaptiven Gewichte (Suchstil, bevorzugte Quellen, '
            'Coach-Chip-Praeferenzen) werden auf den Startzustand '
            'zurueckgesetzt. Deine Stammdaten (PLZ, Beruf, Interessen) '
            'bleiben erhalten.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          TextButton(
            onPressed: () async {
              await ref
                  .read(learningServiceProvider)
                  .resetLearningWeights();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Lernprofil wurde zurueckgesetzt.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                // E1: Profil-Karte neu laden
                _loadProfile();
              }
            },
            child: const Text('Zuruecksetzen',
                style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final adv = _profileAdvice;
    if (_profileLoading) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(children: const [
          SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Lade Profil…',
              style: TextStyle(color: Colors.black54, fontSize: 14)),
        ]),
      );
    }
    if (adv == null || !adv.hasData) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(20),
        child: const Text(
          'Noch keine Profil-Daten — starte deine ersten Suchen und '
          'gib Bewertungen ab.',
          style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
        ),
      );
    }
    final satPct = (adv.overallSatisfaction * 100).round();
    final modeLabel = adv.preferredMode == 'precise'
        ? 'Praezise'
        : adv.preferredMode == 'discover'
            ? 'Entdecken'
            : adv.preferredMode == 'recent'
                ? 'Aktuell'
                : 'Standard';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _profileStat(
            icon: Icons.tune_rounded,
            label: 'Bevorzugter Modus',
            value: modeLabel,
          ),
          const Padding(
            padding: EdgeInsets.only(left: 56),
            child:
                Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
          ),
          _profileStat(
            icon: Icons.spellcheck_rounded,
            label: 'Ø Wörter pro Suche',
            value: '${adv.avgWordCountSuccess}',
          ),
          const Padding(
            padding: EdgeInsets.only(left: 56),
            child:
                Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
          ),
          _profileStat(
            icon: Icons.thumb_up_alt_outlined,
            label: 'Zufriedenheitsquote',
            value: '$satPct % (${adv.totalRated} Bewertungen)',
          ),
          if (adv.filterHint.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(left: 56),
              child: Divider(
                  height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
            ),
            _profileStat(
              icon: Icons.library_books_outlined,
              label: 'Lieblingsquellen',
              value: adv.filterHint,
            ),
          ],
          if (adv.topThemeLabel != null) ...[
            const Padding(
              padding: EdgeInsets.only(left: 56),
              child: Divider(
                  height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
            ),
            _profileStat(
              icon: Icons.lightbulb_outline_rounded,
              label: 'Haeufigstes Thema',
              value: adv.topThemeLabel!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _profileStat(
      {required IconData icon,
      required String label,
      required String value}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: FindUXProTheme.primaryPurple, size: 22),
          const SizedBox(width: 18),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    letterSpacing: -0.2)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String title,
    required String subtitle,
    Color color = Colors.black54,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: -0.2)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12.5, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Stage 14: _showFeedbackExportDialog entfernt — Bewertungen werden
  // jetzt verpflichtend pro neuer Suchrichtung aufgenommen und
  // ausschliesslich lokal im Lern-Modell verwendet (kein Export, kein
  // Versand). Die zugehoerigen l10n-Strings (feedbackTitle, feedbackDesc,
  // noFeedback, deleteFeedback, sendFeedbackSafe, reviewFeedback) bleiben
  // als orphans im generierten l10n-File — sie schaden nicht.
}


class _SettingsCountryPickerSheet extends StatefulWidget {
  final String selected;
  const _SettingsCountryPickerSheet({required this.selected});
  @override
  State<_SettingsCountryPickerSheet> createState() =>
      _SettingsCountryPickerSheetState();
}

class _SettingsCountryPickerSheetState
    extends State<_SettingsCountryPickerSheet> {
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
            : kCountries
                .where((c) =>
                    c.label.toLowerCase().contains(q) || c.code.contains(q))
                .toList();
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
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 8),
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
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 2),
                        decoration: BoxDecoration(
                          color: sel
                              ? FindUXProTheme.primaryPurple
                                  .withValues(alpha: 0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Text(c.flag,
                                style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                c.label,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: sel
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: sel
                                      ? FindUXProTheme.primaryPurple
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            Text(c.code.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black38)),
                            if (sel)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Icon(Icons.check_rounded,
                                    size: 18,
                                    color: FindUXProTheme.primaryPurple),
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
