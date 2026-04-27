import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logic/state_provider.dart';
import '../theme.dart';

class SettingsScreen extends ConsumerWidget {
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
        title: const Text(
          'ÜBER FIND UX PRO',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 18),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              children: [
                _buildOptionTile(
                  icon: Icons.person_outline,
                  title: 'Autoren',
                  subtitle: settings.beruf.isNotEmpty ? settings.beruf : 'Profile oder Autoren',
                  onTap: () {},
                ),
                _buildOptionTile(
                  icon: Icons.card_giftcard_outlined,
                  title: 'Produkte',
                  subtitle: 'Subtitle der Produkte',
                  onTap: () {},
                ),
                _buildOptionTile(
                  icon: Icons.settings_outlined,
                  title: 'Einstellungen',
                  subtitle: 'App-Präferenzen verwalten',
                  onTap: () {},
                ),
                _buildOptionTile(
                  icon: Icons.description_outlined,
                  title: 'Bedingungen',
                  subtitle: 'Rechtliche Hinweise',
                  onTap: () {},
                ),
                _buildOptionTile(
                  icon: Icons.help_outline,
                  title: 'Unterstützung',
                  subtitle: 'Hilfe und Support',
                  onTap: () {},
                ),
              ],
            ),
          ),
          // "Finde mehr heraus" Button
          Padding(
            padding: const EdgeInsets.all(32),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: FindUXProTheme.primaryPurple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: FindUXProTheme.largeSquircleRadius),
                  padding: const EdgeInsets.symmetric(vertical: 20),
                ),
                onPressed: () {
                  HapticFeedback.heavyImpact();
                },
                child: const Text(
                  'Finde mehr heraus',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.black, size: 24),
        ),
        title: Text(title, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 13)),
        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.black26, size: 16),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
      ),
    );
  }
}
