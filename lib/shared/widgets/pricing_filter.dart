import 'package:flutter/material.dart';

import '../models/tool.dart';

/// Filter a list by what a tool costs.
///
/// Price is the first thing most people filter on, but it is one question with
/// four answers — a menu rather than a row of chips, and it wears the current
/// answer on its face so the filter is never silently on.
///
/// Shared by Discover, Search and Saved. It began inside Discover only, so the
/// same question could be asked of the catalog but not of your own list or of
/// search results, which is exactly where people narrow things down.
class PricingFilter extends StatelessWidget {
  const PricingFilter({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// Null means any price.
  final PricingType? selected;
  final ValueChanged<PricingType?> onChanged;

  static const labels = <PricingType?, String>{
    null: 'Any price',
    PricingType.free: 'Free',
    PricingType.freemium: 'Freemium',
    PricingType.paid: 'Paid',
  };

  /// Whether [tool] belongs under [filter]. For lists already in memory, where
  /// asking the server again would be slower than looking.
  static bool matches(Tool tool, PricingType? filter) =>
      filter == null || tool.pricingType == filter;

  @override
  Widget build(BuildContext context) {
    final on = selected != null;
    final scheme = Theme.of(context).colorScheme;

    return PopupMenuButton<PricingType?>(
      tooltip: 'Filter by price',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final entry in labels.entries)
          PopupMenuItem<PricingType?>(
            value: entry.key,
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: entry.key == selected
                      ? Icon(Icons.check, size: 18, color: scheme.primary)
                      : null,
                ),
                Text(entry.value),
              ],
            ),
          ),
      ],
      child: Chip(
        label: Text(labels[selected]!),
        avatar: Icon(
          Icons.sell_outlined,
          size: 17,
          color: on ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
        ),
        backgroundColor: on ? scheme.secondaryContainer : null,
        side: on ? BorderSide.none : null,
      ),
    );
  }
}
