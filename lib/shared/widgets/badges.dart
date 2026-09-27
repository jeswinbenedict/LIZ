import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../models/tool.dart';
import 'time_ago.dart';

/// Small pill used for pricing, "New", "Rising", etc.
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
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    final tint = accent.withValues(alpha: 0.12);
    // Filled: white on the accent, so the accent is what has to darken.
    // Tinted: the accent on its own pale tint, so the text has to. A pill
    // usually sits on a card rather than bare surface, so aim a little above
    // the 4.5 minimum to leave room for the difference.
    final fill = filled ? LizColors.legibleOn(accent, Colors.white) : tint;
    final ink = filled
        ? Colors.white
        : LizColors.legibleOn(
            accent,
            Color.alphaBlend(tint, scheme.surface),
            minimum: 4.8,
          );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon != null ? 8 : 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(LizRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: 4),
          ],
          // A long tag on a narrow phone would otherwise push the pill past
          // the edge of whatever row it sits in.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PricingBadge extends StatelessWidget {
  const PricingBadge(this.pricing, {super.key});
  final PricingType pricing;

  @override
  Widget build(BuildContext context) {
    final (color, _) = switch (pricing) {
      PricingType.free => (LizColors.positive, 'Free'),
      PricingType.freemium => (LizColors.brand, 'Freemium'),
      PricingType.paid => (LizColors.warn, 'Paid'),
      PricingType.unknown => (Colors.grey, 'Unknown'),
    };
    return LizPill(label: pricing.label, color: color);
  }
}

class TrendBadge extends StatelessWidget {
  const TrendBadge(this.tool, {super.key});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    // Live mode: a unique leaderboard position (#1, #2, …). Mock/demo mode
    // (no rank): fall back to the compact trend score.
    final rank = tool.trendRank;
    return LizPill(
      label: rank != null ? '#$rank' : compactCount(tool.trendScore.round()),
      color: LizColors.rising,
      icon: Icons.trending_up,
    );
  }
}
