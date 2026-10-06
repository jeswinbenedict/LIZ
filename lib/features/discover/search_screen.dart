import 'dart:async';

import 'package:flutter/material.dart';
import '../../shared/widgets/liz_mark.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/telemetry/analytics.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/skeletons.dart';
import '../../shared/widgets/pricing_filter.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/tool_card.dart';

/// Search across tool name, tagline, description, tags, and category.
/// A search is the words and, optionally, a price. Both are part of the key,
/// so the filtered and unfiltered results are cached separately rather than
/// one being served back under the other.
typedef SearchKey = ({String query, PricingType? pricing});

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<Tool>, SearchKey>((ref, key) async {
      // Typing "video editor" used to leave a cached result for every prefix the
      // debounce happened to fire on, each holding up to thirty tools.
      if (key.query.trim().length < 2) return [];
      final results = await ref
          .watch(contentRepositoryProvider)
          .searchTools(key.query, pricing: key.pricing);
      // What people look for, and whether Liz had it: the list of questions
      // the catalog cannot answer yet.
      Analytics.track(
        'search',
        props: {'q': clip(key.query.trim(), 100), 'results': results.length},
      );
      return results;
    });

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  String _query = '';
  PricingType? _pricing;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery ?? '';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = (query: _query, pricing: _pricing);
    final results = ref.watch(searchResultsProvider(key));
    final width = MediaQuery.sizeOf(context).width;
    final columns = gridColumnsFor(width);
    final gutter = LizSpacing.gutter(width);
    final p = context.liz;
    final count = _query.trim().length < 2 ? null : results.value?.length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: 64,
        // The field is the title: this screen exists to be typed into. Its
        // heading is for screen readers only — a visible "Search" above a
        // search box would only repeat it.
        title: Padding(
          padding: EdgeInsets.only(right: gutter),
          child: MaxWidth(
            maxWidth: 720,
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              style: LizText.body.copyWith(color: p.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search tools, tags, categories…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.cancel, size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
      body: MaxWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              header: true,
              headingLevel: 1,
              label: 'Search tools',
              child: const SizedBox(width: 1, height: 1),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      count == null
                          ? ''
                          : count == 1
                          ? '1 tool'
                          : '$count tools',
                      style: LizText.subhead.copyWith(color: p.textSecondary),
                    ),
                  ),
                  PricingFilter(
                    selected: _pricing,
                    onChanged: (value) => setState(() => _pricing = value),
                  ),
                ],
              ),
            ),
            Expanded(child: _results(results, columns, gutter)),
          ],
        ),
      ),
    );
  }

  /// Three words or more reads as a description of a job ("edit a podcast
  /// with AI"), which Ask Liz answers by meaning. Offered, not forced: the
  /// words may still be a name.
  bool get _readsAsQuestion =>
      _query.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length >=
      3;

  Widget _askLizRow(double gutter) {
    final p = context.liz;
    final q = _query.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 0),
      child: Material(
        color: p.accentSoft,
        shape: LizRadius.shape(LizRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(
            Uri(path: '/ask', queryParameters: {'q': q}).toString(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                LizMark.icon(size: 20, color: p.textPrimary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ask Liz: \u201c$q\u201d',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LizText.callout.copyWith(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward, size: 18, color: p.textPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _results(AsyncValue<List<Tool>> results, int columns, double gutter) {
    final key = (query: _query, pricing: _pricing);
    final list = _resultList(results, columns, gutter, key);
    if (_query.trim().length < 2 || !_readsAsQuestion) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _askLizRow(gutter),
        Expanded(child: list),
      ],
    );
  }

  Widget _resultList(
    AsyncValue<List<Tool>> results,
    int columns,
    double gutter,
    SearchKey key,
  ) {
    return _query.trim().length < 2
        ? const EmptyView(
            icon: Icons.search,
            title: 'Search Liz',
            message: 'Find AI tools by name, tag, or what they do.',
          )
        : results.when(
            loading: () => const ToolGridSkeleton(),
            error: (_, _) => ErrorView(
              onRetry: () => ref.invalidate(searchResultsProvider(key)),
            ),
            data: (tools) => tools.isEmpty
                ? EmptyView(
                    icon: Icons.search_off,
                    title: 'No results for "$_query"',
                    // With a price chosen, the likelier culprit is the
                    // filter, not the words.
                    message: _pricing == null
                        ? 'Try a broader term.'
                        : 'Try a broader term, or any price.',
                  )
                : GridView.builder(
                    padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      mainAxisExtent: toolCardExtent(context),
                    ),
                    itemCount: tools.length,
                    itemBuilder: (context, i) => ToolCard(tool: tools[i]),
                  ),
          );
  }
}
