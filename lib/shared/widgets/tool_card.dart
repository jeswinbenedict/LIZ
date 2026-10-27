import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../features/track/bookmark_button.dart';
import '../models/tool.dart';
import 'badges.dart';
import 'liz_card.dart';
import 'tool_link.dart';
import 'tool_logo.dart';

/// A tool in a grid (docs/DESIGN.md §7, Tool card): squircle logo, name,
/// two-line tagline, and one line of metadata. It replaced a card carrying
/// four coloured pills, a star row, a divider and a save count — seven
/// colours competing on one card, most of them saying something secondary.
class ToolCard extends StatelessWidget {
  const ToolCard({
    super.key,
    required this.tool,
    this.onSelect,
    this.selected = false,
  });

  final Tool tool;

  /// When set, the card is in selection mode (Saved → Select): tapping it
  /// toggles selection and a check circle replaces the bookmark.
  final VoidCallback? onSelect;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final selecting = onSelect != null;
    if (!selecting) {
      return ToolLink(
        tool: tool,
        builder: (context, open) => _build(context, open),
      );
    }
    return _build(context, onSelect);
  }

  Widget _build(BuildContext context, VoidCallback? onTap) {
    final p = context.liz;
    final selecting = onSelect != null;
    final card = LizCard(
      onTap: onTap,
      semanticLabel: selecting
          ? '${tool.name}, ${selected ? 'selected' : 'not selected'} for comparison'
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ToolLogo(tool: tool, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tool.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LizText.headline.copyWith(
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        if (tool.isNew) ...[
                          const SizedBox(width: 6),
                          const LizPill(label: 'New'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tool.tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LizText.callout.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              if (selecting)
                _Check(selected: selected)
              else
                // Pulled up and to the right so its 48px target does not
                // push the text in.
                Transform.translate(
                  offset: const Offset(10, -10),
                  child: BookmarkButton(toolId: tool.id),
                ),
            ],
          ),
          const Spacer(),
          ToolMeta(tool),
        ],
      ),
    );
    if (!selecting) return card;
    // A selected card carries an accent ring, drawn outside the card so the
    // layout does not shift as it is toggled.
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: ShapeDecoration(
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(
            color: selected ? p.accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: card,
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return AnimatedContainer(
      duration: LizMotion.of(context, LizMotion.quick),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: selected ? p.accentFill : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? p.accentFill : p.hairlineStrong,
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : null,
    );
  }
}
