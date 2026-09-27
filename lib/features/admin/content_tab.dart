import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/ui_state.dart';
import '../../core/repository/repositories.dart';
import '../../shared/models/paginated.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/tool_logo.dart';

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

    return Column(
      children: [
        _Filters(
          query: query,
          controller: _searchController,
          onSearch: _onSearchChanged,
          onStatus: _setStatus,
        ),
        if (selection.isNotEmpty)
          _BulkBar(
            count: selection.length,
            onPublish: () => _applyToSelection(PublishStatus.published),
            onHide: () => _applyToSelection(PublishStatus.hidden),
            onClear: () => ref.read(adminSelectionProvider.notifier).set({}),
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
                    onSelectAll: () =>
                        ref.read(adminSelectionProvider.notifier).set({
                          for (final t in result.items) t.id,
                        }),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
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
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        controller.clear();
                        onSearch('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in _options.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: query.status == entry.key,
                  showCheckmark: false,
                  onSelected: (_) => onStatus(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$count selected',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onPublish,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Publish'),
            ),
            TextButton.icon(
              onPressed: onHide,
              icon: const Icon(Icons.visibility_off_outlined, size: 18),
              label: const Text('Hide'),
            ),
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
    final scheme = Theme.of(context).colorScheme;

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: tools.length + 2,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Text(
                  'Showing ${offset + 1}–${offset + tools.length}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onSelectAll,
                  child: const Text('Select page'),
                ),
              ],
            ),
          );
        }

        if (i == tools.length + 1) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: offset == 0 ? null : () => onPage(-1),
                  icon: const Icon(Icons.chevron_left, size: 18),
                  label: const Text('Previous'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: hasMore ? () => onPage(1) : null,
                  icon: const Icon(Icons.chevron_right, size: 18),
                  label: const Text('Next'),
                ),
              ],
            ),
          );
        }

        final tool = tools[i - 1];
        final selected = selection.contains(tool.id);

        return CheckboxListTile(
          value: selected,
          onChanged: (_) => onToggle(tool.id),
          controlAffinity: ListTileControlAffinity.leading,
          secondary: ToolLogo(tool: tool, size: 40),
          title: Text(tool.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tool.tagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StatusPill(status: tool.status),
                  Text(
                    '${tool.source ?? 'manual'} · ${tool.category}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              // The reason the gate held it, so the queue can be worked
              // through by cause rather than row by row.
              if (tool.holdReason != null) ...[
                const SizedBox(height: 4),
                Text(
                  tool.holdReason!,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: scheme.error,
                  ),
                ),
              ],
            ],
          ),
          isThreeLine: true,
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final PublishStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (status) {
      PublishStatus.published => (LizColors.positive, 'Published'),
      PublishStatus.pending => (LizColors.rising, 'Pending'),
      PublishStatus.hidden => (scheme.onSurfaceVariant, 'Hidden'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(LizRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
