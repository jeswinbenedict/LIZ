import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/config/env.dart';
import '../../core/telemetry/analytics.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/tool_link.dart';

/// The badge a maker embeds on their own site, linking back to the tool's
/// page on Liz. The images are written by the prerenderer (badge_svg in
/// scrapers/liz_scraper/prerender.py) at `/badge/<slug>.svg` and
/// `/badge/<slug>-dark.svg`; this offers the snippet to paste.
class MakerBadge {
  const MakerBadge({required this.tool, required this.base, this.dark = false});
  final Tool tool;
  final String base;
  final bool dark;

  static const width = 136;
  static const height = 48;

  String get pageUrl => '$base${toolPath(tool)}';
  String get imageUrl => '$base/badge/${tool.slug}${dark ? '-dark' : ''}.svg';
  String get alt => '${tool.name} on Liz';

  String get html =>
      '<a href="$pageUrl"><img src="$imageUrl" alt="${_attr(alt)}" '
      'width="$width" height="$height"></a>';

  String get markdown => '[![${_md(alt)}]($imageUrl)]($pageUrl)';

  static String _attr(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _md(String s) => s.replaceAll(RegExp(r'[\[\]]'), '');

  /// Null where Liz has no public address to link to (a native build with
  /// no SITE_URL), or for a tool without a page of its own.
  static MakerBadge? of(Tool tool, {bool dark = false}) =>
      from(tool, Env.resolvedSiteUrl, dark: dark);

  static MakerBadge? from(Tool tool, String base, {bool dark = false}) {
    final clean = base.trim().replaceAll(RegExp(r'/+$'), '');
    if (tool.slug.isEmpty || clean.isEmpty) return null;
    return MakerBadge(tool: tool, base: clean, dark: dark);
  }
}

/// Does nothing where Liz has no public address to link to.
Future<void> showMakerBadgeSheet(
  BuildContext context,
  Tool tool, {
  String? base,
}) async {
  final badge = MakerBadge.from(tool, base ?? Env.resolvedSiteUrl);
  if (badge == null) return;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
      ),
      child: _BadgeSheet(badge: badge),
    ),
  );
}

/// The quiet line at the foot of a tool page that leads to the sheet.
class MakerBadgeRow extends StatelessWidget {
  const MakerBadgeRow({super.key, required this.tool});
  final Tool tool;

  @override
  Widget build(BuildContext context) {
    if (MakerBadge.of(tool) == null) return const SizedBox.shrink();
    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Made ${tool.name}? Show it on your site.',
              style: LizText.callout.copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => showMakerBadgeSheet(context, tool),
            child: const Text('Get a badge'),
          ),
        ],
      ),
    );
  }
}

class _BadgeSheet extends StatefulWidget {
  const _BadgeSheet({required this.badge});
  final MakerBadge badge;

  @override
  State<_BadgeSheet> createState() => _BadgeSheetState();
}

class _BadgeSheetState extends State<_BadgeSheet> {
  bool _dark = false;

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    Analytics.track('share', toolId: widget.badge.tool.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what copied')));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final tool = widget.badge.tool;
    final badge = MakerBadge(tool: tool, base: widget.badge.base, dark: _dark);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(
          'A badge for ${tool.name}',
          style: LizText.title3.copyWith(color: p.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Links visitors to this page. It reads “Rising on Liz” while the '
          'tool is rising and “Listed on Liz” otherwise, updated daily.',
          style: LizText.callout.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 20),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Light')),
            ButtonSegment(value: true, label: Text('Dark')),
          ],
          selected: {_dark},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _dark = s.first),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _dark ? LizPalette.dark.canvas : LizPalette.light.canvas,
            borderRadius: BorderRadius.circular(LizRadius.md),
            border: Border.all(color: p.hairline),
          ),
          child: BadgePreview(
            rising: tool.isRising,
            palette: _dark ? LizPalette.dark : LizPalette.light,
          ),
        ),
        const SizedBox(height: 20),
        _Snippet(
          label: 'HTML',
          code: badge.html,
          onCopy: () => _copy(badge.html, 'HTML'),
        ),
        const SizedBox(height: 12),
        _Snippet(
          label: 'Markdown (for a README)',
          code: badge.markdown,
          onCopy: () => _copy(badge.markdown, 'Markdown'),
        ),
      ],
    );
  }
}

/// The badge drawn natively, matching the SVG the prerenderer writes, so the
/// sheet can show it without fetching an image the web renderer cannot draw.
class BadgePreview extends StatelessWidget {
  const BadgePreview({super.key, required this.rising, required this.palette});
  final bool rising;
  final LizPalette palette;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: rising ? 'Rising on Liz' : 'Listed on Liz',
      child: ExcludeSemantics(
        child: Container(
          width: MakerBadge.width.toDouble(),
          height: MakerBadge.height.toDouble(),
          padding: const EdgeInsets.only(left: 16, right: 14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.hairlineStrong),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rising ? 'RISING ON' : 'LISTED ON',
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: palette.textSecondary,
                      ),
                    ),
                    Text(
                      'Liz',
                      style: TextStyle(
                        fontSize: 19,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              rising
                  ? Icon(Icons.trending_up, size: 22, color: palette.rising)
                  : Icon(Icons.check_circle, size: 20, color: palette.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _Snippet extends StatelessWidget {
  const _Snippet({
    required this.label,
    required this.code,
    required this.onCopy,
  });
  final String label;
  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: LizText.subhead.copyWith(color: p.textPrimary),
              ),
            ),
            TextButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.surfaceMuted,
            borderRadius: BorderRadius.circular(LizRadius.sm),
          ),
          child: SelectableText(
            code,
            style: LizText.footnote.copyWith(
              color: p.textSecondary,
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Consolas', 'Menlo', 'Courier'],
            ),
          ),
        ),
      ],
    );
  }
}
