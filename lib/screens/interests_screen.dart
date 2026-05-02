import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/interests_catalog.dart';
import '../logic/state_provider.dart';
import '../services/haptic_helper.dart';
import '../theme.dart';

/// Stage G: 3-Ebenen-Drill-down nach Apple-Music-Onboarding-Pattern.
///
///   Top-Kategorien (Grid)  ->  Unter-Kategorien (Liste mit Chevron)
///   ->  Items (Multi-Select Chips)
///
/// Kategorien werden nach Profil-Relevanz (employmentType, familyStatus, Alter)
/// vorsortiert. Die Top-3 relevanten Kategorien erhalten ein "Empfohlen"-Badge.
///
/// Stage 15: Custom-Eintraege pro Sub-Sektion — siehe _ItemsScreenState.
class InterestsScreen extends ConsumerWidget {
  const InterestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final selected = settings.interests;

    // Katalog nach Profil-Relevanz sortieren (stabiler Sort: gleicher Score → Originalreihenfolge)
    final sorted = kInterestsCatalog.toList();
    final scores = <String, double>{};
    for (final c in sorted) {
      scores[c.id] = categoryRelevance(
          c, settings.employmentType, settings.familyStatus, settings.jahr);
    }
    sorted.sort((a, b) => scores[b.id]!.compareTo(scores[a.id]!));

    // Top-3 nicht-null-Score-Kategorien gelten als "empfohlen"
    final recommended = sorted
        .where((c) => (scores[c.id] ?? 0) > 0)
        .take(3)
        .map((c) => c.id)
        .toSet();

    // Personalisierter Untertitel
    final hasProfile = settings.employmentType != 'student' ||
        settings.familyStatus != 'single' ||
        settings.jahr != 1990;
    final subtitle = hasProfile
        ? 'Passend fuer dein Profil sortiert. Tippe tief, '
          'um das Lern-Modell zu schalten.'
        : 'Tippe ein Thema an und gehe so tief, wie du moechtest. '
          'Deine Auswahl bleibt verschluesselt auf diesem Geraet.';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black, size: 20),
          onPressed: () {
            Haptics.tap();
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Meine Interessen',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          if (selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: FindUXProTheme.primaryPurple
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${selected.length}',
                    style: const TextStyle(
                      color: FindUXProTheme.primaryPurple,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasProfile) ...[
                  const Icon(Icons.auto_awesome_rounded,
                      size: 14, color: Color(0xFF6C4AB6)),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              itemCount: sorted.length,
              itemBuilder: (ctx, i) {
                final c = sorted[i];
                final n = countSelectedInTop(c.id, selected);
                return _CategoryTile(
                  category: c,
                  count: n,
                  recommended: recommended.contains(c.id),
                  onTap: () {
                    Haptics.tap();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              _SubcategoryScreen(category: c)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final InterestCategory category;
  final int count;
  final bool recommended;
  final VoidCallback onTap;
  const _CategoryTile({
    required this.category,
    required this.count,
    required this.onTap,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = count > 0;
    // recommended && !isSelected → leichter Lila-Hintergrund als Hinweis
    final bgColor = isSelected
        ? Colors.white
        : recommended
            ? const Color(0xFFF3EEFF)
            : Colors.white;
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? FindUXProTheme.primaryPurple.withValues(alpha: 0.5)
                  : recommended
                      ? FindUXProTheme.primaryPurple.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.04),
              width: (isSelected || recommended) ? 1.6 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(category.emoji,
                      style: const TextStyle(fontSize: 32)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category.label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isSelected
                            ? '$count ausgewaehlt'
                            : '${category.subs.length} Themen',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? FindUXProTheme.primaryPurple
                              : Colors.black54,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Häkchen wenn ausgewählt
              if (isSelected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: FindUXProTheme.primaryPurple,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
              // Stern-Badge wenn empfohlen (und noch nicht ausgewählt)
              if (recommended && !isSelected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: FindUXProTheme.primaryPurple,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Empfohlen',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------- Ebene 2: Unter-Kategorien --------

class _SubcategoryScreen extends ConsumerWidget {
  final InterestCategory category;
  const _SubcategoryScreen({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(settingsProvider).interests;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black, size: 20),
          onPressed: () {
            Haptics.tap();
            Navigator.pop(context);
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(category.emoji,
                style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              category.label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
            child: Text(
              'Waehle ein Thema, um genauer zu werden.',
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < category.subs.length; i++) ...[
                  _SubRow(
                    sub: category.subs[i],
                    count: countSelectedInSub(
                        category.id, category.subs[i].id, selected),
                    onTap: () {
                      Haptics.tap();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ItemsScreen(
                            category: category,
                            sub: category.subs[i],
                          ),
                        ),
                      );
                    },
                  ),
                  if (i < category.subs.length - 1)
                    const Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: Divider(
                        height: 1,
                        thickness: 0.5,
                        color: Color(0xFFE5E5EA),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubRow extends StatelessWidget {
  final InterestSubcategory sub;
  final int count;
  final VoidCallback onTap;
  const _SubRow({
    required this.sub,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                sub.label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: FindUXProTheme.primaryPurple
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: FindUXProTheme.primaryPurple,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              )
            else
              Text(
                '${sub.items.length}',
                style: const TextStyle(
                  color: Colors.black38,
                  fontSize: 13,
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
}

// -------- Ebene 3: Multi-Select Items + Stage-15 Custom-Items --------

/// Stage 15: User-eigene Eintraege pro Sub-Sektion.
///
/// Speicher-Format:
///   * Pfad in `interests`-Liste:  `<top>/<sub>/_c_<slug>`
///       (z.B. `musik/rap/_c_eigener_kuenstler`).
///       Der `_c_`-Prefix unterscheidet Custom- von Katalog-Items.
///       Slug (lowercased + ASCII + underscores) ist gleichzeitig der
///       Lern-Modell-Token, daher fliessen Custom-Eintraege exakt
///       genauso in `applyInterestBumps` ein wie Katalog-Eintraege.
///
///   * Original-Label (mit Gross-/Kleinschreibung + Spaces):
///       SharedPreferences-Key `custom_interest_labels` als JSON-Map
///       `{pfad: label}`. Damit zeigt der Chip "Roger Federer" statt
///       "roger federer" — die Slug-Form sieht der User nie.
class _ItemsScreen extends ConsumerStatefulWidget {
  final InterestCategory category;
  final InterestSubcategory sub;
  const _ItemsScreen({required this.category, required this.sub});

  @override
  ConsumerState<_ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<_ItemsScreen> {
  static const _kLabelsKey = 'custom_interest_labels';

  Map<String, String> _customLabels = <String, String>{};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadLabels();
  }

  String _path(String itemId) =>
      '${widget.category.id}/${widget.sub.id}/$itemId';
  String _customPathPrefix() =>
      '${widget.category.id}/${widget.sub.id}/_c_';

  /// Slugify deutscher Text -> ASCII-lowercase + underscores.
  /// Gleiche Form wie kInterestsCatalog-IDs, damit das Lern-Modell
  /// diese Tokens identisch behandelt (weight_kw_<token>).
  String _slugify(String s) {
    var x = s.toLowerCase().trim();
    x = x
        .replaceAll('ä', 'ae')
        .replaceAll('ö', 'oe')
        .replaceAll('ü', 'ue')
        .replaceAll('ß', 'ss');
    x = x.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    x = x.replaceAll(RegExp(r'^_+|_+$'), '');
    return x;
  }

  Future<void> _loadLabels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLabelsKey);
      if (raw != null && raw.isNotEmpty) {
        final m = json.decode(raw);
        if (m is Map) {
          _customLabels = m.map(
              (k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    } catch (_) {
      // ignore - fallback auf leere Map
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _saveLabels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLabelsKey, json.encode(_customLabels));
    } catch (_) {
      // ignore - non-fatal
    }
  }

  void _toggle(String itemId) {
    final p = _path(itemId);
    final selected = ref.read(settingsProvider).interests;
    final next = List<String>.from(selected);
    if (next.contains(p)) {
      next.remove(p);
      Haptics.tap();
    } else {
      next.add(p);
      Haptics.pick();
    }
    ref.read(settingsProvider.notifier).updateField(interests: next);
  }

  Future<void> _addCustom() async {
    final controller = TextEditingController();
    final hintItem = widget.sub.items.isNotEmpty
        ? widget.sub.items.first.label
        : 'Stichwort';
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eigener Eintrag in ${widget.sub.label}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          // Stage F Haertung: keine IME-Lerndaten / Auto-Korrektur.
          autocorrect: false,
          enableSuggestions: false,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          decoration: InputDecoration(
            hintText: 'z.B. $hintItem',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Hinzufuegen'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (input == null || input.isEmpty) return;
    final slug = _slugify(input);
    if (slug.isEmpty) return;
    final path = '${_customPathPrefix()}$slug';
    final selected = ref.read(settingsProvider).interests;
    if (selected.contains(path)) {
      // Bereits vorhanden -> nur Label aktualisieren (User hat
      // moeglicherweise andere Schreibweise eingegeben).
      _customLabels[path] = input;
      await _saveLabels();
      Haptics.tap();
      if (mounted) setState(() {});
      return;
    }
    final next = List<String>.from(selected)..add(path);
    _customLabels[path] = input;
    await _saveLabels();
    ref.read(settingsProvider.notifier).updateField(interests: next);
    Haptics.pick();
    if (mounted) setState(() {});
  }

  Future<void> _removeCustom(String path) async {
    final selected = ref.read(settingsProvider).interests;
    final next = List<String>.from(selected)..remove(path);
    _customLabels.remove(path);
    await _saveLabels();
    ref.read(settingsProvider.notifier).updateField(interests: next);
    Haptics.tap();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(settingsProvider).interests;
    final prefix = _customPathPrefix();
    final customPaths =
        selected.where((p) => p.startsWith(prefix)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.black, size: 20),
          onPressed: () {
            Haptics.tap();
            Navigator.pop(context);
          },
        ),
        title: Text(
          widget.sub.label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
            child: Text(
              'Mehrfachauswahl moeglich. Antippen zum Setzen oder Loesen. '
              'Mit + kannst du eigene Eintraege hinzufuegen.',
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.black.withValues(alpha: 0.6),
              ),
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in widget.sub.items)
                _ItemChip(
                  item: item,
                  selected: selected.contains(_path(item.id)),
                  onTap: () => _toggle(item.id),
                ),
              if (_loaded)
                for (final p in customPaths)
                  _CustomChip(
                    label: _customLabels[p] ??
                        // Fallback aus Pfad rekonstruieren, falls Label-
                        // Map verloren ging.
                        p
                            .substring(prefix.length)
                            .replaceAll('_', ' '),
                    onTap: () => _removeCustom(p),
                  ),
              _AddCustomChip(onTap: _addCustom),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemChip extends StatelessWidget {
  final InterestItem item;
  final bool selected;
  final VoidCallback onTap;
  const _ItemChip({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? FindUXProTheme.primaryPurple
              : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? FindUXProTheme.primaryPurple
                : Colors.black.withValues(alpha: 0.08),
            width: 1.4,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: FindUXProTheme.primaryPurple
                        .withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded,
                  color: Colors.white, size: 16),
              const SizedBox(width: 6),
            ],
            Text(
              item.label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : Colors.black87,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stage 15: User-eigener Interesse-Chip mit X zum Entfernen.
class _CustomChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _CustomChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        decoration: BoxDecoration(
          color: FindUXProTheme.primaryPurple,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: FindUXProTheme.primaryPurple,
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: FindUXProTheme.primaryPurple
                  .withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.close_rounded,
                color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}

/// Stage 15: Plus-Chip am Ende jeder Item-Liste.
class _AddCustomChip extends StatelessWidget {
  final VoidCallback onTap;
  const _AddCustomChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color:
                FindUXProTheme.primaryPurple.withValues(alpha: 0.55),
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded,
                color: FindUXProTheme.primaryPurple, size: 18),
            const SizedBox(width: 6),
            const Text(
              'Eigener Eintrag',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: FindUXProTheme.primaryPurple,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
