import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/ui_state.dart';
import '../../core/repository/repositories.dart';
import '../../shared/models/paginated.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/tool_logo.dart';
import 'admin_widgets.dart';

/// What the admin is currently looking at.
final adminQueryProvider = uiStateProvider<AdminToolQuery>(
  // Pending first: it is the queue that needs a person, and it is the reason
  // this screen exists.
  const AdminToolQuery(status: PublishStatus.pending),
);

final adminToolsProvider = FutureProvider.autoDispose
    .family<Paginated<Tool>, AdminToolQuery>(
      (ref, query) => ref.watch(adminRepositoryProvider).adminTools(query),
    );

/// Tools ticked for a bulk action, by id.
final adminSelectionProvider = uiStateProvider<Set<String>>(const {});

/// The catalog, filtered — and reviewable in bulk.
///
/// The previous version listed the newest 200 tools with no filter and no
/// search, and published them one popup menu at a time. With 653 tools the
/// pending queue sat entirely outside that window, which is how 423 tools
/// accumulated without anyone being able to work through them.
class ContentTab extends ConsumerStatefulWidget {
  const ContentTab({super.key});

  @override
  ConsumerState<ContentTab> createState() => _ContentTabState();
}

class _ContentTabState extends ConsumerState<ContentTab> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref
          .read(adminQueryProvider.notifier)
          .update((q) => q.copyWith(search: value, offset: 0));
      ref.read(adminSelectionProvider.notifier).set({});
    });
  }

  void _setStatus(PublishStatus? status) {
    ref
        .read(adminQueryProvider.notifier)
        .update(
          (q) => q.copyWith(
            status: status,
            clearStatus: status == null,
            offset: 0,
          ),
        );
    ref.read(adminSelectionProvider.notifier).set({});
  }

  Future<void> _applyToSelection(PublishStatus status) async {
    final ids = ref.read(adminSelectionProvider).toList();
    if (ids.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    await ref.read(adminRepositoryProvider).setToolStatuses(ids, status);
    ref.read(adminSelectionProvider.notifier).set({});
    ref.invalidate(adminToolsProvider);

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${ids.length} tool${ids.length == 1 ? '' : 's'} '
            '${status == PublishStatus.published ? 'published' : status.value}',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(adminQueryProvider);
    final page = ref.watch(adminToolsProvider(query));
    final selection = ref.watch(adminSelectionProvider);

    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Filters(
          query: query,
          controller: _searchController,
          onSearch: _onSearchChanged,
          onStatus: _setStatus,
        ),
        if (selection.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 12),
            child: _BulkBar(
              count: selection.length,
              onPublish: () => _applyToSelection(PublishStatus.published),
              onHide: () => _applyToSelection(PublishStatus.hidden),
              onClear: () => ref.read(adminSelectionProvider.notifier).set({}),
            ),
          ),
        Expanded(
          child: page.when(
            loading: () => const LoadingView(),
            error: (_, _) =>
                ErrorView(onRetry: () => ref.invalidate(adminToolsProvider)),
            data: (result) => result.items.isEmpty
                ? const EmptyView(
                    icon: Icons.inbox_outlined,
                    title: 'Nothing here',
                    message: 'No tools match this filter.',
                  )
                : _ToolList(
                    tools: result.items,
                    selection: selection,
                    hasMore: result.cursor != null,
                    onToggle: (id) {
                      final next = {...selection};
                      next.contains(id) ? next.remove(id) : next.add(id);
                      ref.read(adminSelectionProvider.notifier).set(next);
                    },
                    onSelectAll: () => ref
                        .read(adminSelectionProvider.notifier)
                        .set({for (final t in result.items) t.id}),
                    onPage: (delta) {
                      ref
                          .read(adminQueryProvider.notifier)
                          .update(
                            (q) => q.copyWith(
                              offset: (q.offset + delta * q.limit).clamp(
                                0,
                                1 << 30,
                              ),
                            ),
                          );
                      ref.read(adminSelectionProvider.notifier).set({});
                    },
                    offset: query.offset,
                  ),
          ),
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.query,
    required this.controller,
    required this.onSearch,
    required this.onStatus,
  });

  final AdminToolQuery query;
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final ValueChanged<PublishStatus?> onStatus;

  static const _options = <PublishStatus?, String>{
    PublishStatus.pending: 'Pending',
    PublishStatus.published: 'Published',
    PublishStatus.hidden: 'Hidden',
    null: 'All',
  };

  @override
  Widget build(BuildContext context) {
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    final field = TextField(
      controller: controller,
      onChanged: onSearch,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search name or tagline…',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  controller.clear();
                  onSearch('');
                },
              ),
      ),
    );
    final pills = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in _options.entries)
          LizFilterPill(
            label: entry.value,
            selected: query.status == entry.key,
            onTap: () => onStatus(entry.key),
          ),
      ],
    );
    // One toolbar on a wide window: the status filter, then search.
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 24, gutter, 16),
      child: LayoutBuilder(
        builder: (context, box) => box.maxWidth >= 760
            ? Row(
                children: [
                  pills,
                  const Spacer(),
                  SizedBox(width: 320, child: field),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [field, const SizedBox(height: 12), pills],
              ),
      ),
    );
  }
}

/// What to do with the ticked rows: publish (the action this queue exists
/// for, so the one filled button) or hide.
class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.count,
    required this.onPublish,
    required this.onHide,
    required this.onClear,
  });

  final int count;
  final VoidCallback onPublish;
  final VoidCallback onHide;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: p.surfaceMuted,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairlineStrong),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$count selected',
                style: LizText.callout.copyWith(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onHide,
              icon: const Icon(Icons.visibility_off_outlined, size: 18),
              label: const Text('Hide'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onPublish,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Publish'),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Clear selection',
              icon: const Icon(Icons.close, size: 20),
              onPressed: onClear,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolList extends StatelessWidget {
  const _ToolList({
    required this.tools,
    required this.selection,
    required this.hasMore,
    required this.offset,
    required this.onToggle,
    required this.onSelectAll,
    required this.onPage,
  });

  final List<Tool> tools;
  final Set<String> selection;
  final bool hasMore;
  final int offset;
  final ValueChanged<String> onToggle;
  final VoidCallback onSelectAll;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 48),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Showing ${offset + 1}–${offset + tools.length}',
                style: LizText.footnote.copyWith(
                  color: p.textSecondary,
                  fontFeatures: LizText.tabular,
                ),
              ),
            ),
            TextButton(
              onPressed: onSelectAll,
              child: const Text('Select page'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AdminPanel(
          children: [
            for (final tool in tools)
              _ToolRow(
                tool: tool,
                selected: selection.contains(tool.id),
                onToggle: () => onToggle(tool.id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: offset == 0 ? null : () => onPage(-1),
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('Previous'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: hasMore ? () => onPage(1) : null,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('Next'),
            ),
          ],
        ),
      ],
    );
  }
}

/// One tool in the queue: tick, logo, name and status, tagline, where it
/// came from, and — when the gate held it — why.
class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.tool,
    required this.selected,
    required this.onToggle,
  });

  final Tool tool;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return MergeSemantics(
      child: InkWell(
        onTap: onToggle,
        child: Container(
          color: selected ? p.surfaceMuted : null,
          padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: selected, onChanged: (_) => onToggle()),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ToolLogo(tool: tool, size: 36),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tool.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LizText.callout.copyWith(
                              color: p.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _StatusPill(status: tool.status),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tool.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LizText.footnote.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tool.source ?? 'manual'} · ${tool.category}',
                      style: LizText.footnote.copyWith(color: p.textTertiary),
                    ),
                    // The reason the gate held it, so the queue can be
                    // worked through by cause rather than row by row.
                    if (tool.holdReason != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.info_outline,
                              size: 14,
                              color: LizColors.warn,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tool.holdReason!,
                              style: LizText.footnote.copyWith(
                                color: p.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final PublishStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
    PublishStatus.published => const AdminStatusLabel(
      AdminStatus.ok,
      label: 'Published',
    ),
    PublishStatus.pending => const AdminStatusLabel(
      AdminStatus.watch,
      label: 'Pending',
    ),
    PublishStatus.hidden => const AdminStatusLabel(
      AdminStatus.neutral,
      label: 'Hidden',
    ),
  };
}
