import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:findux_mobile/l10n/app_localizations.dart';
import '../logic/state_provider.dart';
import '../theme.dart';
import 'chrome_import_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _employmentLabels = <String, String>{
    'student': 'Student / Schueler / Azubi',
    'rentner': 'Rentner / Pension',
    'vollzeit': 'Vollzeit',
    'teilzeit': 'Teilzeit',
    'erwerbslos': 'Erwerbslos / Job-Suche',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final needsJob = settings.employmentType == 'vollzeit' ||
        settings.employmentType == 'teilzeit';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.settingsTitle,
          style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          _sectionLabel('Profil'),
          _optionTile(
            icon: Icons.person_outline,
            title: 'Beschaeftigung',
            subtitle: _employmentLabels[settings.employmentType] ??
                settings.employmentType,
            onTap: () =>
                _showEmploymentPicker(context, ref, settings.employmentType),
          ),
          if (needsJob)
            _optionTile(
              icon: Icons.work_outline,
              title: 'Jobrichtung',
              subtitle: settings.beruf.isEmpty
                  ? 'Nicht festgelegt'
                  : settings.beruf,
              onTap: () => _showTextDialog(
                context,
                title: 'Jobrichtung',
                hint: 'z.B. IT, Pflege, Marketing, Handwerk',
                initial: settings.beruf,
                onSave: (v) => notifier.updateField(beruf: v),
              ),
            ),
          _optionTile(
            icon: Icons.cake_outlined,
            title: 'Geburtsjahr',
            subtitle: '${settings.jahr}',
            onTap: () => _showYearPicker(context, ref, settings.jahr),
          ),
          _optionTile(
            icon: Icons.location_on_outlined,
            title: AppLocalizations.of(context)!.zipLabel,
            subtitle:
                settings.plz.isEmpty ? 'Nicht festgelegt' : settings.plz,
            onTap: () => _showTextDialog(
              context,
              title: AppLocalizations.of(context)!.zipLabel,
              hint: 'z.B. 10115',
              initial: settings.plz,
              keyboard: TextInputType.number,
              onSave: (v) => notifier.updateField(plz: v),
            ),
          ),
          const SizedBox(height: 8),
          _sectionLabel('Region & Sprache'),
          _optionTile(
            icon: Icons.language,
            title: AppLocalizations.of(context)!.languageLabel,
            subtitle: settings.language == 'de' ? 'Deutsch' : 'English',
            onTap: () => notifier.updateField(
                language: settings.language == 'de' ? 'en' : 'de'),
          ),
          _optionTile(
            icon: Icons.public,
            title: AppLocalizations.of(context)!.countryLabel,
            subtitle: settings.country.toUpperCase(),
            onTap: () => notifier.updateField(
                country: settings.country == 'de' ? 'at' : 'de'),
          ),
          const SizedBox(height: 8),
          _sectionLabel('Suche & Browser'),
          _toggleTile(
            icon: Icons.open_in_browser,
            title: 'Ergebnisse in der App oeffnen',
            subtitle: settings.openInApp
                ? 'Custom Tabs / In-App Browser-View'
                : 'Externer Browser',
            value: settings.openInApp,
            onChanged: (v) => notifier.updateField(openInApp: v),
          ),
          _toggleTile(
            icon: Icons.shield_outlined,
            title: 'Jugendschutz',
            subtitle: settings.enableYouthProtection
                ? 'SafeSearch + Negativ-Filter aktiv'
                : 'Aus',
            value: settings.enableYouthProtection,
            onChanged: (v) =>
                notifier.updateField(enableYouthProtection: v),
          ),
          _toggleTile(
            icon: Icons.thumbs_up_down_outlined,
            title: 'Feedback ermoeglichen',
            subtitle: settings.allowFeedback
                ? 'Lern-Modell wird verfeinert'
                : 'Aus',
            value: settings.allowFeedback,
            onChanged: (v) => notifier.updateField(allowFeedback: v),
          ),
          const SizedBox(height: 8),
          _sectionLabel('Datenschutz'),
          _optionTile(
            icon: Icons.history_rounded,
            title: 'Chrome-Verlauf importieren',
            subtitle: 'Reduziert auf 4 Felder, Datei wird geloescht',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ChromeImportScreen()),
            ),
          ),
          _optionTile(
            icon: Icons.security_rounded,
            title: AppLocalizations.of(context)!.reviewFeedback,
            subtitle: 'Datenexport manuell freigeben',
            onTap: () => _showFeedbackExportDialog(context, ref),
          ),
          _optionTile(
            icon: Icons.delete_forever_outlined,
            title: 'Alle persoenlichen Daten loeschen',
            subtitle: 'Vault zuruecksetzen (Notbremse)',
            destructive: true,
            onTap: () => _confirmWipe(context, ref),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------- Section + Tiles ----------

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            color: Colors.black54,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      );

  Widget _optionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: destructive
                ? Colors.red.withValues(alpha: 0.1)
                : FindUXProTheme.primaryPurple.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              color: destructive ? Colors.red : FindUXProTheme.primaryPurple,
              size: 20),
        ),
        title: Text(title,
            style: TextStyle(
                color: destructive ? Colors.red : Colors.black87,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
        subtitle: Text(subtitle,
            style:
                const TextStyle(color: Colors.black54, fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios,
            color: Colors.black26, size: 14),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
      ),
    );
  }

  Widget _toggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: SwitchListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: FindUXProTheme.primaryPurple.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              color: FindUXProTheme.primaryPurple, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w700,
                fontSize: 15)),
        subtitle: Text(subtitle,
            style:
                const TextStyle(color: Colors.black54, fontSize: 12)),
        value: value,
        activeThumbColor: FindUXProTheme.primaryPurple,
        onChanged: (v) {
          HapticFeedback.selectionClick();
          onChanged(v);
        },
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
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ..._employmentLabels.entries.map((e) => RadioListTile<String>(
                  title: Text(e.value),
                  value: e.key,
                  groupValue: current,
                  activeColor: FindUXProTheme.primaryPurple,
                  onChanged: (v) {
                    if (v != null) {
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
                  onSelectedItemChanged: (i) => ref
                      .read(settingsProvider.notifier)
                      .updateField(jahr: years[i]),
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
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          TextButton(
            onPressed: () {
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
            'Alle persoenlichen Daten (Beschaeftigung, PLZ, Jahrgang, Lern-Modell) werden unwiderruflich entfernt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          TextButton(
            onPressed: () async {
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
