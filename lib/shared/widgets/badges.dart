import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../models/tool.dart';

/// A small status word ("New", "Beta") or tag on a tint of its colour
/// (docs/DESIGN.md §7, Badge). Never more than one status badge on a card.
class LizPill extends StatelessWidget {
  const LizPill({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final accent = color ?? p.textSecondary;
    final tint = accent.withValues(alpha: 0.10);
    // Filled: white on the accent, so the accent is what has to darken.
    // Tinted: the accent on its own pale tint, so the text has to. Aimed a
    // little above 4.5 because a pill usually sits on a card, not bare canvas.
    final fill = filled ? LizColors.legibleOn(accent, Colors.white) : tint;
    final ink = filled
        ? Colors.white
        : LizColors.legibleOn(
            accent,
            Color.alphaBlend(tint, p.surface),
            minimum: 4.8,
          );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon != null ? 6 : 7,
        vertical: 3,
      ),
      decoration: ShapeDecoration(
        color: fill,
        shape: LizRadius.shape(LizRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: ink),
            const SizedBox(width: 3),
          ],
          // A long tag on a narrow phone would otherwise push the pill past
          // the edge of whatever row it sits in.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LizText.caption.copyWith(
                color: ink,
                letterSpacing: 0.1,
                fontFeatures: LizText.tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The colour that stands for a price, as a cue beside the word.
Color pricingColor(BuildContext context, PricingType pricing) {
  final p = context.liz;
  return switch (pricing) {
    PricingType.free => p.positive,
    PricingType.freemium => p.accent,
    PricingType.paid => p.caution,
    PricingType.unknown => p.textTertiary,
  };
}

/// A price as a coloured dot and a neutral word — "● Freemium". The colour is
/// a cue; the word is the information, so nothing depends on colour alone.
class PricingBadge extends StatelessWidget {
  const PricingBadge(this.pricing, {super.key});
  final PricingType pricing;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: p.surfaceMuted,
        shape: LizRadius.shape(LizRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: pricingColor(context, pricing)),
          const SizedBox(width: 6),
          Text(
            pricing == PricingType.unknown ? 'Price unknown' : pricing.label,
            style: LizText.footnote.copyWith(
              color: p.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A category slug as a reader would say it: `ai-video` → "Video".
String categoryLabel(String slug) {
  const known = {
    'ai-writing': 'Writing',
    'ai-video': 'Video',
    'ai-image': 'Image',
    'ai-audio': 'Audio',
    'ai-design': 'Design',
    'ai-dev': 'Dev tools',
    'ai-agents': 'Agents',
    'ai-productivity': 'Productivity',
    'ai-research': 'Research',
    'new-apps': 'New apps',
  };
  final hit = known[slug];
  if (hit != null) return hit;
  final words = slug.replaceFirst(RegExp(r'^ai-'), '').split('-');
  final text = words.where((w) => w.isNotEmpty).join(' ');
  return text.isEmpty ? slug : text[0].toUpperCase() + text.substring(1);
}

/// One line of secondary text that says what four coloured pills used to:
/// "● Freemium · Video · ★ 4.7". Unknown prices and unrated tools leave their
/// part out rather than filling it with a placeholder.
class ToolMeta extends StatelessWidget {
  const ToolMeta(this.tool, {super.key, this.showCategory = true});
  final Tool tool;
  final bool showCategory;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final style = LizText.subhead.copyWith(color: p.textSecondary);
    final parts = <InlineSpan>[];
    void sep() {
      if (parts.isNotEmpty) parts.add(const TextSpan(text: '  ·  '));
    }

    if (tool.pricingType != PricingType.unknown) {
      parts.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _Dot(color: pricingColor(context, tool.pricingType)),
          ),
        ),
      );
      parts.add(TextSpan(text: tool.pricingType.label));
    }
    if (showCategory && tool.category.isNotEmpty) {
      sep();
      parts.add(TextSpan(text: categoryLabel(tool.category)));
    }
    if (tool.ratingCount > 0) {
      sep();
      // An icon, not "★": the bundled Inter subset has no star glyph, and a
      // missing glyph makes Flutter web fetch a fallback font from Google.
      parts.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(Icons.star_rounded, size: 14, color: p.textSecondary),
          ),
        ),
      );
      parts.add(
        TextSpan(
          text: tool.avgRating.toStringAsFixed(1),
          semanticsLabel: 'rated ${tool.avgRating.toStringAsFixed(1)}',
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
        ),
      );
    }
    return Text.rich(
      TextSpan(style: style, children: parts),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
