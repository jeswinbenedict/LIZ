import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// The pieces every tab of the admin console is built from, so the four tabs
/// read as one console (docs/DESIGN.md §8, Admin): a section heading with its
/// one-line purpose, rows in a frame, a status as a dot and a word, and a
/// figure as a tile.

/// A titled block: the heading, one line on what it is for, an optional
/// action on the heading's line, then its content.
class AdminSection extends StatelessWidget {
  const AdminSection({
    super.key,
    required this.title,
    this.description,
    this.action,
    required this.child,
    this.top = 32,
  });

  final String title;
  final String? description;
  final Widget? action;
  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  container: true,
                  header: true,
                  child: Text(
                    title,
                    style: LizText.title3.copyWith(color: p.textPrimary),
                  ),
                ),
              ),
              ?action,
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: LizText.footnote.copyWith(color: p.textSecondary),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Rows in one frame with hairlines between them — the console's list.
class AdminPanel extends StatelessWidget {
  const AdminPanel({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
      ),
      child: ClipRSuperellipse(
        borderRadius: BorderRadius.circular(LizRadius.md),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) Divider(height: 1, color: p.hairline),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One line inside a panel saying there is nothing to show.
class AdminEmpty extends StatelessWidget {
  const AdminEmpty(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    child: Text(
      text,
      style: LizText.callout.copyWith(color: context.liz.textSecondary),
    ),
  );
}

/// How a check stands: fine, worth watching, or failing.
enum AdminStatus { ok, watch, failing, neutral }

AdminStatus adminStatusFrom(String status) => switch (status) {
  'fail' || 'failed' => AdminStatus.failing,
  'warn' => AdminStatus.watch,
  'ok' || 'succeeded' => AdminStatus.ok,
  _ => AdminStatus.neutral,
};

Color adminStatusColor(LizPalette p, AdminStatus s) => switch (s) {
  AdminStatus.ok => LizColors.positive,
  AdminStatus.watch => LizColors.warn,
  AdminStatus.failing => p.danger,
  AdminStatus.neutral => p.textSecondary,
};

/// A status as a coloured dot and a word. The word carries the meaning; the
/// colour only helps it be found.
class AdminStatusLabel extends StatelessWidget {
  const AdminStatusLabel(this.status, {super.key, this.label});
  final AdminStatus status;

  /// In place of the default word (OK, Watch, Failing).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final word =
        label ??
        switch (status) {
          AdminStatus.ok => 'OK',
          AdminStatus.watch => 'Watch',
          AdminStatus.failing => 'Failing',
          AdminStatus.neutral => '—',
        };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: adminStatusColor(p, status),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          word,
          style: LizText.footnote.copyWith(
            color: p.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// A figure as a tile: what it is, the number large, and a line of context.
class AdminStat extends StatelessWidget {
  const AdminStat({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.status,
  });

  final String label;
  final String value;
  final String? detail;
  final AdminStatus? status;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Semantics(
      container: true,
      label: [label, value, ?detail].join(', '),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: p.surface,
          shape: LizRadius.shape(
            LizRadius.md,
            side: BorderSide(color: p.hairline),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LizText.subhead.copyWith(color: p.textSecondary),
                    ),
                  ),
                  if (status != null) ...[
                    const SizedBox(width: 8),
                    AdminStatusLabel(status!),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: LizText.title1.copyWith(
                  color: p.textPrimary,
                  fontFeatures: LizText.tabular,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 4),
                Text(
                  detail!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: LizText.footnote.copyWith(color: p.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "catalog freshness (hours)" → "Catalog freshness (hours)".
String sentenceCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
