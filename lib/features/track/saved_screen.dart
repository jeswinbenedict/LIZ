import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/adaptive_shell.dart';
import '../../app/responsive/breakpoints.dart';
import '../../core/providers.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/skeletons.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/tool_card.dart';
import '../auth/sign_in_view.dart';
import 'track_controller.dart';

/// Tools selected for side-by-side comparison from the Saved screen.
final compareSelectionProvider = StateProvider<Set<String>>((ref) => {});

class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    final saved = ref.watch(bookmarkedToolsProvider);
    final selection = ref.watch(compareSelectionProvider);
    final columns = gridColumnsFor(MediaQuery.sizeOf(context).width);

    return Scaffold(
      floatingActionButton: selection.length >= 2
          ? FloatingActionButton.extended(
              onPressed: () =>
                  context.push('/compare?ids=${selection.join(',')}'),
              icon: const Icon(Icons.compare_arrows),
              label: Text('Compare ${selection.length}'),
            )
          : null,
      body: SafeArea(
        child: MaxWidth(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                titleSpacing: 20,
                title: context.isPhone
                    ? const LizWordmark()
                    : Text(
                        'Saved',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
              ),
              if (!signedIn)
                SliverToBoxAdapter(
                  child: EmptyView(
                    icon: Icons.bookmark_border,
                    title: 'Save tools to revisit them',
                    message: 'Sign in to build your list and compare tools.',
                    action: FilledButton(
                      onPressed: () => _promptSignIn(context),
                      child: const Text('Sign in'),
                    ),
                  ),
                )
              else
                saved.when(
                  loading: () => const ToolGridSkeletonSliver(count: 4),
                  error: (_, __) => SliverToBoxAdapter(
                    child: ErrorView(
                      onRetry: () => ref.invalidate(bookmarkedToolsProvider),
                    ),
                  ),
                  data: (tools) => tools.isEmpty
                      ? const SliverToBoxAdapter(
                          child: EmptyView(
                            icon: Icons.bookmark_border,
                            title: 'Nothing saved yet',
                            message:
                                'Tap the bookmark on any tool to save it here.',
                          ),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: 14,
                                  crossAxisSpacing: 14,
                                  mainAxisExtent: toolCardExtent(context) + 28,
                                ),
                            delegate: SliverChildBuilderDelegate(
                              (context, i) => _SelectableToolCard(
                                tool: tools[i],
                                selected: selection.contains(tools[i].id),
                                onToggleSelect: () =>
                                    _toggleSelect(ref, tools[i].id),
                              ),
                              childCount: tools.length,
                            ),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleSelect(WidgetRef ref, String id) {
    final current = ref.read(compareSelectionProvider);
    final next = current.toSet();
    if (next.contains(id)) {
      next.remove(id);
    } else if (next.length < 3) {
      next.add(id);
    }
    ref.read(compareSelectionProvider.notifier).state = next;
  }

  void _promptSignIn(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SignInView(onSignedIn: () => Navigator.of(ctx).pop()),
      ),
    );
  }
}

class _SelectableToolCard extends StatelessWidget {
  const _SelectableToolCard({
    required this.tool,
    required this.selected,
    required this.onToggleSelect,
  });
  final Tool tool;
  final bool selected;
  final VoidCallback onToggleSelect;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ToolCard(tool: tool),
        Positioned(
          top: 6,
          left: 6,
          child: Tooltip(
            message: 'Select to compare',
            child: Material(
              color: Colors.transparent,
              child: Checkbox(
                value: selected,
                onChanged: (_) => onToggleSelect(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
