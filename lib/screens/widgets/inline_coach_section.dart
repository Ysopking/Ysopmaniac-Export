import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../coach/coach_models.dart';
import '../../coach/theme_detector.dart';
import '../../theme.dart';

/// Stage 18 — Ambient Coach
///
/// Eine kollabierte Inline-Sektion unter dem Suchfeld.
/// Header: "✨ Schärfen — N aktiv"
/// Beim Antippen: Verfeinerungs-Chips passend zum erkannten Theme.
/// Kein Popup, kein Timer — ruhig, durch Scrollen entdeckbar.
class InlineCoachSection extends StatefulWidget {
  final String what;
  final String why;
  final ValueChanged<CoachInjection> onChanged;

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
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  CoachTheme get _theme => ThemeDetector.detect(widget.what, widget.why);

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
    widget.onChanged(CoachInjection.fromChoices(_choices));
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
      final oldTheme = ThemeDetector.detect(old.what, old.why);
      final newTheme = ThemeDetector.detect(widget.what, widget.why);
      if (oldTheme.id != newTheme.id) {
        setState(() {
          _choices.removeWhere((c) => c.themeId == oldTheme.id);
        });
        widget.onChanged(CoachInjection.fromChoices(_choices));
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
                          ? 'Schärfen — 0 aktiv'
                          : 'Schärfen — $activeCount aktiv',
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

  const _ChipTile({
    required this.chip,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? FindUXProTheme.primaryPurple
              : FindUXProTheme.primaryPurple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? FindUXProTheme.primaryPurple
                : FindUXProTheme.primaryPurple.withValues(alpha: 0.2),
            width: 1,
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
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : FindUXProTheme.primaryPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
