import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../features/track/bookmark_button.dart';
import '../models/tool.dart';
import 'badges.dart';
import 'rating_stars.dart';
import 'time_ago.dart';
import 'tool_logo.dart';

/// The primary discovery unit — a tappable tool card used across feeds/grids.
class ToolCard extends StatelessWidget {
  const ToolCard({super.key, required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: () => context.push('/tool/${tool.id}'),
        child: Padding(
          padding: const EdgeInsets.all(LizSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ToolLogo(tool: tool, size: 52),
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
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (tool.isNew) ...[
                              const SizedBox(width: 6),
                              const LizPill(
                                  label: 'NEW',
                                  color: LizColors.positive,
                                  filled: true),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tool.tagline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, height: 1.25),
                        ),
                      ],
                    ),
                  ),
                  BookmarkButton(toolId: tool.id),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PricingBadge(tool.pricingType),
                  TrendBadge(tool.trendScore),
                  for (final tag in tool.tags.take(2))
                    LizPill(label: '#$tag', color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (tool.ratingCount > 0) ...[
                    RatingStars(tool.avgRating, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      tool.avgRating.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(' (${tool.ratingCount})',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ] else
                    Text('No ratings yet',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  const Spacer(),
                  Icon(Icons.bookmark_border,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(compactCount(tool.saveCount),
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
