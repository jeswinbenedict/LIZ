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

    final count = saved.value?.length ?? 0;
    return Scaffold(
      bottomNavigationBar: selecting
          ? _SelectionBar(
              count: selection.length,
              onCompare: () {
                final ids = selection.join(',');
                setSelecting(false);
                context.push('/compare?ids=$ids');
              },
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
                    : count == 1
                    ? 'One tool you are keeping an eye on.'
                    : '$count tools you are keeping an eye on.',
                trailing: hasTools
                    ? OutlinedButton.icon(
                        onPressed: () => setSelecting(!selecting),
                        icon: Icon(
                          selecting ? Icons.check : Icons.compare_arrows,
                          size: 18,
                        ),
                        label: Text(selecting ? 'Done' : 'Select'),
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
                  child: MaxWidth(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 48),
                      child: SizedBox(
                        width: double.infinity,
                        child: _SavedEmpty(
                          signedIn: signedIn,
                          onSignIn: () => _promptSignIn(context),
                        ),
                      ),
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
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.devices_outlined, size: 20, color: p.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Saved in this browser only.',
                style: LizText.callout.copyWith(color: p.textPrimary),
              ),
            ),
            OutlinedButton(
              onPressed: onSignIn,
              child: const Text('Keep everywhere'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Along the bottom while choosing: how many are picked, and Compare once
/// there are two. Replaces a floating button that covered the last cards.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.count, required this.onCompare});
  final int count;
  final VoidCallback onCompare;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    final hint = switch (count) {
      0 => 'Choose two or three tools',
      1 => '1 chosen — pick one more',
      _ => '$count of $kMaxCompare chosen',
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.hairline)),
      ),
      child: SafeArea(
        top: false,
        // Its own height only: MaxWidth centres, which would fill the page.
        child: Align(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        hint,
                        style: LizText.callout.copyWith(color: p.textSecondary),
                      ),
                    ),
                  ),
                  if (count >= 2)
                    FilledButton.icon(
                      onPressed: onCompare,
                      icon: const Icon(Icons.compare_arrows, size: 18),
                      label: Text('Compare $count'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nothing saved: say what saving is for, in three lines, and give the one
/// way forward — find a tool, or (for a guest) sign in to keep the list.
class _SavedEmpty extends StatelessWidget {
  const _SavedEmpty({required this.signedIn, required this.onSignIn});
  final bool signedIn;
  final VoidCallback onSignIn;

  static const _points = [
    (Icons.bookmark_outline, 'Save', 'Tap the bookmark on any tool.'),
    (
      Icons.notifications_none,
      'Hear about it',
      'Liz tells you when its price changes or it starts rising.',
    ),
    (
      Icons.compare_arrows,
      'Compare',
      'Put two or three side by side before you choose.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.lg,
          side: BorderSide(color: p.hairline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              header: true,
              headingLevel: 2,
              child: Text(
                signedIn ? 'Nothing saved yet' : 'Save tools to revisit them',
                style: LizText.title3.copyWith(color: p.textPrimary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              signedIn
                  ? 'Your shortlist of AI tools lives here.'
                  : 'No account needed. Sign in to keep your list on every '
                        'device.',
              style: LizText.callout.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                for (final (icon, title, text) in _points)
                  SizedBox(
                    width: 260,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: ShapeDecoration(
                            color: p.surfaceMuted,
                            shape: LizRadius.shape(
                              LizRadius.sm,
                              side: BorderSide(color: p.hairline),
                            ),
                          ),
                          child: Icon(icon, size: 17, color: p.textPrimary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: LizText.subhead.copyWith(
                                  color: p.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                text,
                                style: LizText.footnote.copyWith(
                                  color: p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Find a tool'),
                ),
                if (!signedIn)
                  OutlinedButton(
                    onPressed: onSignIn,
                    child: const Text('Sign in'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
