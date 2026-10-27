import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// A message — an error, a confirmation, a warning — as a quiet panel:
/// the colour is in the icon, the words stay in ink. Announced to screen
/// readers when it appears, and optionally titled.
class LizNotice extends StatelessWidget {
  const LizNotice({
    super.key,
    required this.text,
    required this.color,
    required this.icon,
    this.title,
  });
  final String text;
  final Color color;
  final IconData icon;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final fill = Color.alphaBlend(color.withValues(alpha: 0.06), p.surface);
    // Its own node, so the message is announced on its own rather than read
    // as the tail of the field hint above it.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: ShapeDecoration(
          color: fill,
          shape: LizRadius.shape(
            LizRadius.md,
            side: BorderSide(color: color.withValues(alpha: 0.35)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                icon,
                size: 18,
                color: LizColors.legibleOn(color, fill),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: LizText.headline.copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    text,
                    style: LizText.callout.copyWith(
                      color: title == null ? p.textPrimary : p.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
