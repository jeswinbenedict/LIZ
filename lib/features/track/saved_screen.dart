import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/ui_state.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/pricing_filter.dart';
import '../../shared/widgets/skeletons.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/tool_card.dart';
import '../auth/sign_in_view.dart';
import 'track_controller.dart';

/// Tools selected for side-by-side comparison from the Saved screen.
final compareSelectionProvider = uiStateProvider<Set<String>>(const {});

/// Whether Saved is in selection mode (the Select button in its header).
final savedSelectingProvider = uiStateProvider<bool>(false);

/// Price filter on the Saved list. Filtered in memory: the list is already
/// loaded and short, so asking the server again would only be slower.
final savedPricingProvider = uiStateProvider<PricingType?>(null);

/// The most tools a comparison holds; more columns stop fitting a screen.
const kMaxCompare = 3;

/// Your saved tools. Comparing works the way selecting photos does: Select,
/// tap two or three, Compare. It replaced a checkbox that sat over each
/// tool's logo on every card, all the time.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    final saved = ref.watch(bookmarkedToolsProvider);
    final selection = ref.watch(compareSelectionProvider);
    final selecting = ref.watch(savedSelectingProvider);
    final pricing = ref.watch(savedPricingProvider);
    final width = MediaQuery.sizeOf(context).width;
    final columns = gridColumnsFor(width);
    final gutter = LizSpacing.gutter(width);
    final phone = context.isPhone;
    final hasTools = saved.value?.isNotEmpty ?? false;

    void setSelecting(bool on) {
      ref.read(savedSelectingProvider.notifier).set(on);
      if (!on) ref.read(compareSelectionProvider.notifier).set(const {});
    }

    return Scaffold(
      floatingActionButton: selecting && selection.length >= 2
          ? FloatingActionButton.extended(
              onPressed: () {
                final ids = selection.join(',');
                setSelecting(false);
                context.push('/compare?ids=$ids');
              },
              icon: const Icon(Icons.compare_arrows),
              label: Text('Compare ${selection.length}'),
            )
          : null,
      body: CustomScrollView(
        slivers: [
          if (phone) const PhoneTopBar(),
          SliverToBoxAdapter(
            child: MaxWidth(
              child: PageHeader(
                title: 'Saved',
                subtitle: !hasTools
                    ? null
                    : selecting
                    ? 'Choose two or three tools to compare.'
                    : 'Tools you are keeping an eye on.',
                trailing: hasTools
                    ? TextButton(
                        onPressed: () => setSelecting(!selecting),
                        child: Text(selecting ? 'Done' : 'Select'),
                      )
                    : null,
                bottom: 8,
              ),
            ),
          ),
          if (!signedIn && hasTools)
            SliverToBoxAdapter(
              child: MaxWidth(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 8),
                  child: _GuestNotice(onSignIn: () => _promptSignIn(context)),
                ),
              ),
            ),
          saved.when(
            loading: () => const ToolGridSkeletonSliver(count: 4),
            error: (_, _) => SliverToBoxAdapter(
              child: ErrorView(
                onRetry: () => ref.invalidate(bookmarkedToolsProvider),
              ),
            ),
            data: (all) {
              if (all.isEmpty) {
                return SliverToBoxAdapter(
                  child: EmptyView(
                    icon: Icons.bookmark_border,
                    title: signedIn
                        ? 'Nothing saved yet'
                        : 'Save tools to revisit them',
                    message: signedIn
                        ? 'Tap the bookmark on any tool to save it here.'
                        : 'Tap the bookmark on any tool — no account '
                              'needed. Sign in to keep your list on every '
                              'device.',
                    action: signedIn
                        ? null
                        : OutlinedButton(
                            onPressed: () => _promptSignIn(context),
                            child: const Text('Sign in'),
                          ),
                  ),
                );
              }
              final tools = [
                for (final tool in all)
                  if (PricingFilter.matches(tool, pricing)) tool,
              ];
              return SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: MaxWidth(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: PricingFilter(
                            selected: pricing,
                            onChanged: (value) => ref
                                .read(savedPricingProvider.notifier)
                                .set(value),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (tools.isEmpty)
                    SliverToBoxAdapter(
                      child: EmptyView(
                        icon: Icons.sell_outlined,
                        title: 'Nothing saved at this price',
                        message:
                            'You have ${all.length} saved — try any price.',
                        action: TextButton(
                          onPressed: () =>
                              ref.read(savedPricingProvider.notifier).set(null),
                          child: const Text('Show all'),
                        ),
                      ),
                    )
                  else
                    MaxWidthSliver(
                      sliver: SliverPadding(
                        padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 96),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                mainAxisExtent: toolCardExtent(context),
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => ToolCard(
                              tool: tools[i],
                              selected: selection.contains(tools[i].id),
                              onSelect: selecting
                                  ? () =>
                                        _toggleSelect(context, ref, tools[i].id)
                                  : null,
                            ),
                            childCount: tools.length,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _toggleSelect(BuildContext context, WidgetRef ref, String id) {
    final current = ref.read(compareSelectionProvider);
    final next = current.toSet();
    if (next.contains(id)) {
      next.remove(id);
    } else if (next.length < kMaxCompare) {
      next.add(id);
    } else {
      // Say why the tap did nothing, rather than ignoring it.
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Compare up to $kMaxCompare tools at a time'),
          ),
        );
      return;
    }
    ref.read(compareSelectionProvider.notifier).set(next);
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

/// A reminder, not a wall: the list works without an account, and signing in
/// only moves it somewhere it cannot be lost.
class _GuestNotice extends StatelessWidget {
  const _GuestNotice({required this.onSignIn});
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: p.accentSoft,
        shape: LizRadius.shape(LizRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.devices_outlined, size: 20, color: p.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Saved in this browser only.',
                style: LizText.callout.copyWith(color: p.textPrimary),
              ),
            ),
            TextButton(
              onPressed: onSignIn,
              child: const Text('Keep everywhere'),
            ),
          ],
        ),
      ),
    );
  }
}
