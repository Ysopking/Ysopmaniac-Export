import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:findux_mobile/l10n/app_localizations.dart';
import '../logic/state_provider.dart';
import '../theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.settingsTitle.toUpperCase(),
          style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              children: [
                _buildOptionTile(
                  icon: Icons.person_outline,
                  title: 'Beruf',
                  subtitle: settings.beruf.isNotEmpty
                      ? settings.beruf
                      : 'Nicht festgelegt',
                  onTap: () => _showBerufDialog(context, ref),
                ),
                _buildOptionTile(
                  icon: Icons.language,
                  title: AppLocalizations.of(context)!.languageLabel,
                  subtitle: settings.language == 'de' ? 'Deutsch' : 'English',
                  onTap: () {
                    final newLang = settings.language == 'de' ? 'en' : 'de';
                    notifier.updateField(language: newLang);
                  },
                ),
                _buildOptionTile(
                  icon: Icons.location_on_outlined,
                  title: AppLocalizations.of(context)!.zipLabel,
                  subtitle:
                      settings.plz.isEmpty ? 'Nicht festgelegt' : settings.plz,
                  onTap: () => _showZipDialog(context, ref),
                ),
                _buildOptionTile(
                  icon: Icons.public,
                  title: AppLocalizations.of(context)!.countryLabel,
                  subtitle: settings.country.toUpperCase(),
                  onTap: () {
                    final newCountry = settings.country == 'de' ? 'at' : 'de';
                    notifier.updateField(country: newCountry);
                  },
                ),
                _buildOptionTile(
                  icon: Icons.security_rounded,
                  title: AppLocalizations.of(context)!.reviewFeedback,
                  subtitle: 'Datenexport manuell freigeben',
                  onTap: () => _showFeedbackExportDialog(context, ref),
                ),
                _buildOptionTile(
                  icon: Icons.delete_forever_outlined,
                  title: 'Alle persoenlichen Daten loeschen',
                  subtitle: 'Vault zuruecksetzen (Notbremse)',
                  onTap: () => _confirmWipe(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F5),
        borderRadius: FindUXProTheme.largeSquircleRadius,
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
              color: Colors.white, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.black, size: 24),
        ),
        title: Text(title,
            style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.black54, fontSize: 13)),
        trailing: const Icon(Icons.arrow_forward_ios,
            color: Colors.black26, size: 16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
      ),
    );
  }

  void _showZipDialog(BuildContext context, WidgetRef ref) {
    final controller =
        TextEditingController(text: ref.read(settingsProvider).plz);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.zipLabel),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'z.B. 10115'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          TextButton(
            onPressed: () {
              ref.read(settingsProvider.notifier).updateField(
                    plz: controller.text.trim(),
                  );
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.saveButton),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _showBerufDialog(BuildContext context, WidgetRef ref) {
    final controller =
        TextEditingController(text: ref.read(settingsProvider).beruf);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Beruf'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'z.B. Softwareentwickler'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          TextButton(
            onPressed: () {
              ref.read(settingsProvider.notifier).updateField(
                    beruf: controller.text.trim(),
                  );
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.saveButton),
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
            'Alle persoenlichen Daten (Beruf, PLZ, Jahrgang, Lern-Modell) werden unwiderruflich entfernt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Abbrechen')),
          TextButton(
            onPressed: () async {
              await ref.read(settingsProvider.notifier).wipeAll();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Loeschen',
                style: TextStyle(color: Colors.red)),
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
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppLocalizations.of(context)!.feedbackTitle,
                style: FindUXProTheme.titleStyle),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context)!.feedbackDesc,
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 20),
            Expanded(
              child: feedbacks.isEmpty
                  ? Center(
                      child:
                          Text(AppLocalizations.of(context)!.noFeedback))
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: FindUXProTheme.outlinePurpleButtonStyle,
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
          ],
        ),
      ),
    );
  }
}
