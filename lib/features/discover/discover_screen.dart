import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/adaptive_shell.dart';
import '../../app/responsive/breakpoints.dart';
import '../../core/providers.dart';
import '../../shared/models/category.dart';
import '../../shared/widgets/tool_grid_sliver.dart';
import 'discover_controller.dart';
import 'rising_carousel.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key, this.initialCategory});
  final String? initialCategory;

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(discoverCategoryProvider.notifier).state =
            widget.initialCategory;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sort = ref.watch(discoverSortProvider);
    final category = ref.watch(discoverCategoryProvider);
    final key = FeedKey(sort: sort, category: category);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(toolFeedProvider);
            await ref.read(toolFeedProvider(key).notifier).refresh();
          },
          child: MaxWidth(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  floating: true,
                  titleSpacing: 20,
                  title: context.isPhone
                      ? const LizWordmark()
                      : Text('Discover',
                          style: Theme.of(context).textTheme.headlineSmall),
                  actions: [
                    IconButton(
                      tooltip: 'Search',
                      icon: const Icon(Icons.search),
                      onPressed: () => context.push('/search'),
                    ),
                    IconButton(
                      tooltip: 'Ask Liz',
                      icon: const Icon(Icons.auto_awesome_outlined),
                      onPressed: () => context.go('/ask'),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                const SliverToBoxAdapter(child: RisingCarousel()),
                const SliverToBoxAdapter(child: _CategoryChips()),
                const SliverToBoxAdapter(child: _SortBar()),
                ToolGridSliver(feedKey: key),
                LoadMoreFooter(feedKey: key),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChips extends ConsumerWidget {
  const _CategoryChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selected = ref.watch(discoverCategoryProvider);

    return categoriesAsync.when(
      loading: () => const SizedBox(height: 48),
      error: (_, __) => const SizedBox(height: 0),
      data: (categories) => SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _chip(context, ref, label: 'All', slug: null, selected: selected == null),
            for (final Category c in categories)
              _chip(context, ref,
                  label: c.name, slug: c.slug, selected: selected == c.slug),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, WidgetRef ref,
      {required String label, required String? slug, required bool selected}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) =>
            ref.read(discoverCategoryProvider.notifier).state = slug,
      ),
    );
  }
}

class _SortBar extends ConsumerWidget {
  const _SortBar();

  static const _labels = {
    ToolSort.trending: 'Trending',
    ToolSort.rising: 'Rising',
    ToolSort.newest: 'New',
    ToolSort.topRated: 'Top rated',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(discoverSortProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in _labels.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(entry.value),
                  selected: sort == entry.key,
                  onSelected: (_) => ref
                      .read(discoverSortProvider.notifier)
                      .state = entry.key,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
