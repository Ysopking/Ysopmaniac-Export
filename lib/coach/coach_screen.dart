import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import '../logic/state_provider.dart';
import '../logic/query_builder.dart';
import 'coach_models.dart';
import 'themes_catalog.dart';
import 'quality_estimator.dart';

/// Coach-Screen (Vollbild). User waehlt aus Themen-Chips, sieht Quality-Score,
/// kann Vorschau einsehen / editieren und schliesslich suchen.
///
/// Ergebnis (ueber Navigator.pop):
///   - CoachResult(skipped: true)             -> "Direkt suchen" Button
///   - CoachResult(choices: [...])            -> normale Suche mit Auswahl
///   - CoachResult(overrideQuery: '...')      -> User hat manuell editiert
///   - null                                    -> User hat zurueckgenavigiert
///
/// Personalisierung (B1):
///   Beim Start werden weight_chip_*-Keys aus SharedPreferences gelesen.
///   Chips mit Gewicht > 1.30 werden automatisch vorausgewaehlt.
///   Chips mit Gewicht > 1.15 erhalten ein "★ Oft genutzt"-Badge.
///
///   QualityEstimator (B4) wird mit QualityPersonalization aufgerufen:
///   bevorzugter Modus + Zufriedenheits-Score aus weight_mode_*.
class CoachScreen extends ConsumerStatefulWidget {
  final CoachTheme initialTheme;
  final String what;
  final String why;
  final String currentMode;
  final List<String> currentSources;
  final List<String> currentFiles;

  const CoachScreen({
    super.key,
    required this.initialTheme,
    required this.what,
    required this.why,
    required this.currentMode,
    required this.currentSources,
    required this.currentFiles,
  });

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  late CoachTheme _theme;
  // Map: dimensionId -> Set chipIds
  final Map<String, Set<String>> _selected = {};
  // Map: dimensionId -> custom term
  final Map<String, String> _custom = {};
  String _previewText = '';
  bool _previewExpanded = false;
  final TextEditingController _previewCtrl = TextEditingController();
  final TextEditingController _customCtrl = TextEditingController();

  // B1: Gelernte Chip-Praeferenzen aus SharedPreferences
  // key = "themeId__dimId__chipId", value = true wenn Gewicht > 1.15
  Map<String, bool> _learnedFav = {};
  // Chips mit Gewicht > 1.30 werden vorausgewaehlt
  Set<String> _learnedPre = {};
  // B4: Personalisierungs-Daten fuer QualityEstimator
  double _personalSatisfaction = 0.5;
  String _personalPreferredMode = 'standard';

  @override
  void initState() {
    super.initState();
    _theme = widget.initialTheme;
    _rebuildPreview();
    _loadLearnedData();
  }

  @override
  void dispose() {
    _previewCtrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  // ---------- B1 + B4: Lerngewichte laden ----------

  Future<void> _loadLearnedData() async {
    final prefs = await SharedPreferences.getInstance();
    final fav = <String, bool>{};
    final pre = <String>{};
    double bestModeW = 0.0;
    String bestMode = 'standard';

    for (final k in prefs.getKeys()) {
      if (k.startsWith('weight_chip_')) {
        final w = prefs.getDouble(k) ?? 1.0;
        final chipKey = k.substring('weight_chip_'.length);
        if (w > 1.15) fav[chipKey] = true;
        if (w > 1.30) pre.add(chipKey);
      }
      if (k.startsWith('weight_mode_')) {
        final w = prefs.getDouble(k) ?? 1.0;
        if (w > bestModeW) {
          bestModeW = w;
          bestMode = k.substring('weight_mode_'.length);
        }
      }
    }

    // Approximation overallSatisfaction aus mode-Gewichten:
    // Gewicht 1.0 = neutral (0.5), 2.5 = sehr hoch (1.0)
    final sat = bestModeW > 1.0
        ? ((bestModeW - 1.0) / 1.5).clamp(0.0, 1.0)
        : 0.5;

    if (!mounted) return;
    setState(() {
      _learnedFav = fav;
      _learnedPre = pre;
      _personalSatisfaction = sat;
      _personalPreferredMode = bestMode;
    });

    // Vorauswahl: Chips mit Gewicht > 1.30 fuer aktuelles Theme markieren
    if (pre.isNotEmpty) {
      bool anyAdded = false;
      for (final dim in _theme.dimensions) {
        for (final chip in dim.chips) {
          final key = '${_theme.id}__${dim.id}__${chip.id}';
          if (pre.contains(key)) {
            _selected.putIfAbsent(dim.id, () => <String>{}).add(chip.id);
            anyAdded = true;
          }
        }
      }
      if (anyAdded && mounted) _rebuildPreview();
    }
  }

  // ---------- Query / Preview ----------

  List<CoachChoice> _collectChoices() {
    final result = <CoachChoice>[];
    for (final dim in _theme.dimensions) {
      final picks = _selected[dim.id] ?? const <String>{};
      for (final chipId in picks) {
        final chip = dim.chips.firstWhere((c) => c.id == chipId);
        if (chip.value.isEmpty && chip.kind == ChipKind.term) continue;
        result.add(CoachChoice(
          themeId: _theme.id,
          dimensionId: dim.id,
          chipId: chip.id,
          label: chip.label,
          kind: chip.kind,
          value: chip.value,
        ));
      }
      final custom = _custom[dim.id];
      if (custom != null && custom.isNotEmpty) {
        result.add(CoachChoice(
          themeId: _theme.id,
          dimensionId: dim.id,
          chipId: 'custom',
          label: custom,
          kind: ChipKind.custom,
          value: custom,
        ));
      }
    }
    return result;
  }

  Future<void> _rebuildPreview() async {
    final choices = _collectChoices();
    final injection = CoachInjection.fromChoices(choices);
    final settings = ref.read(settingsProvider);
    final q = await FindUXQueryBuilder().buildQuery(
      what: widget.what,
      why: widget.why,
      filters: [
        ...widget.currentSources.where((s) => s != 'alle'),
        ...widget.currentFiles.where((s) => s != 'alle'),
      ],
      settings: {
        'plz': settings.plz,
        'beruf': settings.beruf,
        'employmentType': settings.employmentType,
        'familyStatus': settings.familyStatus,
        'interests': settings.interests,
        'searchengine': settings.searchEngine,
        'enableYouthProtection': settings.enableYouthProtection,
        'language': settings.language,
        'country': settings.country,
        'jahr': settings.jahr,
      },
      mode: injection.modeOverride ?? widget.currentMode,
      coachInjection: injection,
    );
    if (!mounted) return;
    setState(() {
      _previewText = q;
      if (!_previewCtrl.text.isNotEmpty || !_previewExpanded) {
        _previewCtrl.text = q;
      }
    });
  }

  void _toggleChip(CoachDimension dim, CoachChip chip) {
    HapticFeedback.selectionClick();
    setState(() {
      final cur = _selected.putIfAbsent(dim.id, () => <String>{});
      if (cur.contains(chip.id)) {
        cur.remove(chip.id);
      } else {
        if (!dim.multiSelect) cur.clear();
        cur.add(chip.id);
      }
    });
    _rebuildPreview();
  }

  Future<void> _addCustom(CoachDimension dim) async {
    _customCtrl.clear();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(dim.question),
        content: TextField(
          controller: _customCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Eigenes Stichwort...'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, _customCtrl.text.trim()),
              child: const Text('Hinzufuegen')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _custom[dim.id] = result);
      _rebuildPreview();
    }
  }

  void _switchTheme() async {
    final picked = await showModalBottomSheet<CoachTheme>(
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
              padding: EdgeInsets.all(16),
              child: Text('Anderes Thema waehlen',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ...ThemesCatalog.all.map((t) => ListTile(
                  leading: Text(t.emoji,
                      style: const TextStyle(fontSize: 24)),
                  title: Text(t.label),
                  selected: t.id == _theme.id,
                  selectedTileColor: FindUXProTheme.primaryPurple
                      .withValues(alpha: 0.08),
                  onTap: () => Navigator.pop(ctx, t),
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked != null && picked.id != _theme.id) {
      setState(() {
        _theme = picked;
        _selected.clear();
        _custom.clear();
      });
      _rebuildPreview();
      // Vorauswahl fuer neues Theme neu anwenden
      if (_learnedPre.isNotEmpty) {
        for (final dim in _theme.dimensions) {
          for (final chip in dim.chips) {
            final key = '${_theme.id}__${dim.id}__${chip.id}';
            if (_learnedPre.contains(key)) {
              _selected.putIfAbsent(dim.id, () => <String>{}).add(chip.id);
            }
          }
        }
        if (mounted) _rebuildPreview();
      }
    }
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final choices = _collectChoices();
    // B4: Personalisierter QualityEstimator
    final qr = QualityEstimator.estimate(
      what: widget.what,
      why: widget.why,
      choices: choices,
      personalization: QualityPersonalization(
        overallSatisfaction: _personalSatisfaction,
        preferredMode: _personalPreferredMode,
        currentMode: widget.currentMode,
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: _switchTheme,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_theme.emoji,
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(_theme.label,
                    style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: -0.3),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.expand_more, color: Colors.black54, size: 20),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
                context, const CoachResult(skipped: true)),
            child: const Text('Direkt'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Tippe Antworten an, um deine Suche zu schaerfen.',
                    style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.6),
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 12),
                ..._theme.dimensions.map(_buildDimensionCard),
                const SizedBox(height: 8),
                _buildPreviewCard(),
                const SizedBox(height: 80),
              ],
            ),
          ),
          _buildFooter(qr, choices),
        ],
      ),
    );
  }

  Widget _buildDimensionCard(CoachDimension dim) {
    final selected = _selected[dim.id] ?? const <String>{};
    final custom = _custom[dim.id];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dim.question,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...dim.chips.map((chip) {
                final isSel = selected.contains(chip.id);
                final chipKey = '${_theme.id}__${dim.id}__${chip.id}';
                final isFav = _learnedFav[chipKey] == true && !isSel;
                return _chipButton(
                  label: chip.emoji.isEmpty
                      ? chip.label
                      : '${chip.emoji} ${chip.label}',
                  isSel: isSel,
                  isFav: isFav,
                  onTap: () => _toggleChip(dim, chip),
                );
              }),
              if (dim.allowCustom)
                _chipButton(
                  label: custom != null && custom.isNotEmpty
                      ? '✏️ $custom'
                      : '＋ Eigenes…',
                  isSel: custom != null && custom.isNotEmpty,
                  onTap: () => _addCustom(dim),
                  outlined: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipButton({
    required String label,
    required bool isSel,
    required VoidCallback onTap,
    bool outlined = false,
    bool isFav = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSel
                  ? FindUXProTheme.primaryPurple
                  : (outlined
                      ? Colors.transparent
                      : (isFav
                          ? FindUXProTheme.primaryPurple.withValues(alpha: 0.10)
                          : const Color(0xFFF0F0F5))),
              border: outlined && !isSel
                  ? Border.all(
                      color: FindUXProTheme.primaryPurple
                          .withValues(alpha: 0.6),
                      style: BorderStyle.solid)
                  : (isFav && !isSel
                      ? Border.all(
                          color: FindUXProTheme.primaryPurple
                              .withValues(alpha: 0.35),
                          width: 1)
                      : null),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(
                  color: isSel
                      ? Colors.white
                      : (outlined
                          ? FindUXProTheme.primaryPurple
                          : (isFav
                              ? FindUXProTheme.primaryPurple
                              : Colors.black87)),
                  fontSize: 13,
                  fontWeight: isSel || isFav
                      ? FontWeight.w700
                      : FontWeight.w500,
                )),
          ),
          // B1: Kleines Stern-Badge fuer oft genutzte Chips
          if (isFav)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                width: 14,
                height: 14,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: FindUXProTheme.primaryPurple,
                  shape: BoxShape.circle,
                ),
                child: const Text('★',
                    style: TextStyle(
                        fontSize: 7,
                        color: Colors.white,
                        height: 1)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard() {
    return Container(
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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _previewExpanded,
          onExpansionChanged: (v) => setState(() => _previewExpanded = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: const Icon(Icons.code,
              color: FindUXProTheme.primaryPurple),
          title: const Text('Google-Vorschau',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14)),
          subtitle: Text(
            _previewText.length > 90
                ? '${_previewText.substring(0, 87)}…'
                : _previewText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 11, color: Colors.black54),
          ),
          children: [
            const Text(
              'Du kannst die fertige Anfrage hier manuell anpassen:',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _previewCtrl,
              maxLines: null,
              style: const TextStyle(
                  fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFFF0F0F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(
                      () => _previewCtrl.text = _previewText),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Auf Coach zuruecksetzen',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(QualityResult qr, List<CoachChoice> choices) {
    final scoreColor = qr.score >= 70
        ? Colors.green
        : (qr.score >= 40 ? Colors.orange : Colors.red);
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Qualitaet',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.black54)),
              const SizedBox(width: 8),
              Text('${qr.score}/100',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: scoreColor)),
              const Spacer(),
              if (qr.warnings.isNotEmpty)
                Tooltip(
                  message: qr.warnings.join('\n'),
                  triggerMode: TooltipTriggerMode.tap,
                  child: const Icon(Icons.info_outline,
                      color: Colors.orange, size: 16),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: qr.score / 100.0,
              minHeight: 6,
              backgroundColor: Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: FindUXProTheme.primaryPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: () {
                HapticFeedback.mediumImpact();
                final override = _previewCtrl.text.trim();
                Navigator.pop(
                    context,
                    CoachResult(
                      choices: choices,
                      overrideQuery: (override.isNotEmpty &&
                              override != _previewText)
                          ? override
                          : null,
                    ));
              },
              icon: const Icon(Icons.bolt_rounded),
              label: Text(
                  choices.isEmpty
                      ? 'Suchen'
                      : 'Suchen mit ${choices.length} Verfeinerung${choices.length == 1 ? "" : "en"}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
