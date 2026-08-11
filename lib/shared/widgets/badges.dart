import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../models/tool.dart';

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
    final c = color ?? scheme.primary;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon != null ? 8 : 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? c : c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(LizRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: filled ? Colors.white : c),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : c,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
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
  const TrendBadge(this.score, {super.key});
  final double score;

  @override
  Widget build(BuildContext context) {
    return LizPill(
      label: '${score.round()}',
      color: LizColors.rising,
      icon: Icons.trending_up,
    );
  }
}
