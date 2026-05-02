import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:findux_mobile/l10n/app_localizations.dart';
import '../logic/state_provider.dart';
import '../services/chrome_import_quick.dart';
import '../services/haptic_helper.dart';
import '../theme.dart';

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

  static const _employmentLabels = <String, String>{
    'student': 'Student / Schueler / Azubi',
    'rentner': 'Rentner / Pension',
    'vollzeit': 'Vollzeit',
    'teilzeit': 'Teilzeit',
    'erwerbslos': 'Erwerbslos / Job-Suche',
  };

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
              icon: Icons.cake_outlined,
              title: 'Geburtsjahr',
              value: '${settings.jahr}',
              onTap: () => _showYearPicker(context, ref, settings.jahr),
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
                value: settings.language == 'de' ? 'Deutsch' : 'English',
                onTap: () => notifier.updateField(
                    language: settings.language == 'de' ? 'en' : 'de'),
              ),
              _row(
                icon: Icons.public_rounded,
                title: l10n.countryLabel,
                value: settings.country.toUpperCase(),
                onTap: () => notifier.updateField(
                    country: settings.country == 'de' ? 'at' : 'de'),
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
            _toggleRow(
              icon: Icons.shield_outlined,
              title: 'Jugendschutz',
              subtitle: 'SafeSearch + Negativ-Filter',
              value: settings.enableYouthProtection,
              onChanged: (v) =>
                  notifier.updateField(enableYouthProtection: v),
            ),
            _expandRow(
              expanded: _showAdvancedSearch,
              onToggle: () => setState(
                  () => _showAdvancedSearch = !_showAdvancedSearch),
              hiddenCount: 2,
            ),
            if (_showAdvancedSearch) ...[
              _toggleRow(
                icon: Icons.volume_up_outlined,
                title: 'Doppel-Lauter startet Suche',
                subtitle: '2x Lauter-Taste innerhalb 600 ms',
                value: settings.enableVolumeShortcut,
                onChanged: (v) =>
                    notifier.updateField(enableVolumeShortcut: v),
              ),
              _toggleRow(
                icon: Icons.thumbs_up_down_outlined,
                title: 'Feedback ermoeglichen',
                subtitle: 'Lern-Modell wird verfeinert',
                value: settings.allowFeedback,
                onChanged: (v) => notifier.updateField(allowFeedback: v),
              ),
            ],
          ]),

          // -------- Block 3: Datenschutz --------
          _sectionLabel('Datenschutz'),
          _groupCard(children: [
            _row(
              icon: Icons.history_rounded,
              title: 'Chrome-Verlauf importieren',
              value: 'Ein Tap',
              onTap: () {
                Haptics.tap();
                quickImportChrome(context);
              },
            ),
            _row(
              icon: Icons.security_rounded,
              title: l10n.reviewFeedback,
              value: 'Manuell freigeben',
              onTap: () => _showFeedbackExportDialog(context, ref),
            ),
          ]),

          // -------- Notbremse separiert --------
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
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon,
              color: FindUXProTheme.primaryPurple, size: 22),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
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
              onChanged: (v) {
                Haptics.pick();
                onChanged(v);
              },
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
        height: 280,
        color: Colors.white,
        child: SafeArea(
          child: Column(
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
              if (context.mounted) Navigator.pop(context);
            },
            child:
                const Text('Loeschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showFeedbackExportDialog(BuildContext context, WidgetRef ref) {
    final learningService = ref.read(learningServiceProvider);
    final feedbacks = learningService.getFeedbackForReview();

    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30), topRight: Radius.circular(30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.feedbackTitle,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context)!.feedbackDesc,
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 20),
            Expanded(
              child: feedbacks.isEmpty
                  ? Center(
                      child: Text(
                          AppLocalizations.of(context)!.noFeedback))
                  : ListView.builder(
                      itemCount: feedbacks.length,
                      itemBuilder: (context, i) {
                        final f = feedbacks[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: const Color(0xFFF0F0F5),
                              borderRadius: BorderRadius.circular(16)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                      f['rating'] == 'up'
                                          ? Icons.thumb_up
                                          : Icons.thumb_down,
                                      color: f['rating'] == 'up'
                                          ? Colors.green
                                          : Colors.red,
                                      size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                      f['timestamp']
                                          .toString()
                                          .substring(0, 10),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                              if (f['comment'] != null &&
                                  f['comment'].toString().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(f['comment'],
                                      style: const TextStyle(
                                          fontStyle: FontStyle.italic)),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  Haptics.warn();
                  await learningService.clearAllFeedback();
                  if (context.mounted) Navigator.pop(context);
                },
                child:
                    Text(AppLocalizations.of(context)!.deleteFeedback),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
