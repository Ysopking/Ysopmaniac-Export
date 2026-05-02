import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../coach/coach_models.dart';
import '../../coach/theme_detector.dart';
import '../../theme.dart';

/// Stage 18 — Ambient Coach
///
/// Eine kollabierte Inline-Sektion unter dem Suchfeld.
/// Header: "✨ Schaerfen — N aktiv"
/// Beim Antippen: Verfeinerungs-Chips passend zum erkannten Theme.
/// Kein Popup, kein Timer — ruhig, durch Scrollen entdeckbar.
///
/// Personalisierung (B2):
///   Beim Start und bei Theme-Wechsel werden weight_chip_*-Keys geladen.
///   Chips mit Gewicht > 1.15 erhalten einen subtilen Tint als Hinweis,
///   dass der User sie frueher oft genutzt und positiv bewertet hat.
///
///   ThemeDetector.detect() (B3) bekommt geladene weight_theme_*-Gewichte
///   als Tiebreaker wenn kein Trigger-Wort matcht.
class InlineCoachSection extends StatefulWidget {
  final String what;
  final String why;
  final void Function(CoachInjection injection, List<CoachChoice> choices) onChanged;

  const InlineCoachSection({
    super.key,
    required this.what,
    required this.why,
    required this.onChanged,
  });

  @override
  State<InlineCoachSection> createState() => _InlineCoachSectionState();
}

class _InlineCoachSectionState extends State<InlineCoachSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  final List<CoachChoice> _choices = [];
  late AnimationController _animController;
  late Animation<double> _expandAnimation;

  // B2: Gelernte Chip-Gewichte — key = "themeId__dimId__chipId"
  Map<String, double> _chipWeights = {};
  // B3: weight_theme_*-Gewichte fuer personalisierten ThemeDetector-Fallback
  Map<String, double> _themeWeights = {};

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _loadWeights();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // B2 + B3: Lerngewichte einmalig laden (oder nach Theme-Wechsel neu laden)
  Future<void> _loadWeights() async {
    final prefs = await SharedPreferences.getInstance();
    final chips = <String, double>{};
    final themes = <String, double>{};
    for (final k in prefs.getKeys()) {
      if (k.startsWith('weight_chip_')) {
        chips[k.substring('weight_chip_'.length)] = prefs.getDouble(k) ?? 1.0;
      } else if (k.startsWith('weight_theme_')) {
        themes[k] = prefs.getDouble(k) ?? 1.0;
      }
    }
    if (!mounted) return;
    setState(() {
      _chipWeights = chips;
      _themeWeights = themes;
    });
  }

  // B3: personalisierten ThemeDetector nutzen
  CoachTheme get _theme =>
      ThemeDetector.detect(widget.what, widget.why, weights: _themeWeights);

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  void _toggleChip(CoachTheme theme, CoachDimension dim, CoachChip chip) {
    HapticFeedback.selectionClick();
    setState(() {
      final existingIdx = _choices.indexWhere(
        (c) =>
            c.themeId == theme.id &&
            c.dimensionId == dim.id &&
            c.chipId == chip.id,
      );
      if (existingIdx >= 0) {
        _choices.removeAt(existingIdx);
      } else {
        if (!dim.multiSelect) {
          _choices.removeWhere(
            (c) => c.themeId == theme.id && c.dimensionId == dim.id,
          );
        }
        _choices.add(CoachChoice(
          themeId: theme.id,
          dimensionId: dim.id,
          chipId: chip.id,
          label: chip.label,
          kind: chip.kind,
          value: chip.value,
        ));
      }
    });
    widget.onChanged(
        CoachInjection.fromChoices(_choices), List.unmodifiable(_choices));
  }

  bool _isSelected(String themeId, CoachDimension dim, CoachChip chip) =>
      _choices.any(
        (c) =>
            c.themeId == themeId &&
            c.dimensionId == dim.id &&
            c.chipId == chip.id,
      );

  @override
  void didUpdateWidget(InlineCoachSection old) {
    super.didUpdateWidget(old);
    if (old.what != widget.what || old.why != widget.why) {
      final oldTheme =
          ThemeDetector.detect(old.what, old.why, weights: _themeWeights);
      final newTheme = _theme;
      if (oldTheme.id != newTheme.id) {
        setState(() {
          _choices.removeWhere((c) => c.themeId == oldTheme.id);
        });
        widget.onChanged(
            CoachInjection.fromChoices(_choices), List.unmodifiable(_choices));
        // B2: Gewichte nach Theme-Wechsel neu laden (neue Chips sichtbar)
        _loadWeights();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _choices.length;
    final theme = _theme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — immer sichtbar, nie aufdringlich
          GestureDetector(
            onTap: _toggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Text('✨', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      activeCount == 0
                          ? 'Schaerfen — 0 aktiv'
                          : 'Schaerfen — $activeCount aktiv',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: activeCount > 0
                            ? FindUXProTheme.primaryPurple
                            : Colors.black54,
                      ),
                    ),
                  ),
                  if (activeCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: FindUXProTheme.primaryPurple
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${theme.emoji} ${theme.label}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: FindUXProTheme.primaryPurple,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 20,
                      color: Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expandable body
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Colors.black.withValues(alpha: 0.06),
                  indent: 16,
                  endIndent: 16,
                ),
                const SizedBox(height: 4),
                for (final dim in theme.dimensions) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Text(
                      dim.question,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black45,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final chip in dim.chips)
                          _ChipTile(
                            chip: chip,
                            selected: _isSelected(theme.id, dim, chip),
                            onTap: () => _toggleChip(theme, dim, chip),
                            // B2: Gelernte Gewicht uebergeben
                            learnedWeight: _chipWeights[
                                    '${theme.id}__${dim.id}__${chip.id}'] ??
                                1.0,
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipTile extends StatelessWidget {
  final CoachChip chip;
  final bool selected;
  final VoidCallback onTap;
  /// B2: Lerngewicht — > 1.15 = subtiler Tint als Hinweis "oft genutzt"
  final double learnedWeight;

  const _ChipTile({
    required this.chip,
    required this.selected,
    required this.onTap,
    this.learnedWeight = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final isFav = learnedWeight > 1.15 && !selected;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? FindUXProTheme.primaryPurple
              : (isFav
                  ? FindUXProTheme.primaryPurple.withValues(alpha: 0.10)
                  : FindUXProTheme.primaryPurple.withValues(alpha: 0.06)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? FindUXProTheme.primaryPurple
                : (isFav
                    ? FindUXProTheme.primaryPurple.withValues(alpha: 0.40)
                    : FindUXProTheme.primaryPurple.withValues(alpha: 0.2)),
            width: isFav ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chip.emoji.isNotEmpty) ...[
              Text(chip.emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
            ],
            Text(
              chip.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isFav || selected
                    ? FontWeight.w700
                    : FontWeight.w600,
                color: selected
                    ? Colors.white
                    : (isFav
                        ? FindUXProTheme.primaryPurple
                        : FindUXProTheme.primaryPurple.withValues(alpha: 0.8)),
              ),
            ),
            // B2: Kleines Punkt-Badge fuer "oft genutzt"
            if (isFav) ...[
              const SizedBox(width: 5),
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: FindUXProTheme.primaryPurple,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
