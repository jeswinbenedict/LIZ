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
import '../../shared/widgets/top_bar.dart';

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

  /// Set the words from outside the field (a suggestion), and search now.
  void _search(String value) {
    _debounce?.cancel();
    _controller.text = value;
    _controller.selection = TextSelection.collapsed(offset: value.length);
    setState(() => _query = value);
  }

  @override
  Widget build(BuildContext context) {
    final key = (query: _query, pricing: _pricing);
    final results = ref.watch(searchResultsProvider(key));
    final width = MediaQuery.sizeOf(context).width;
    final columns = gridColumnsFor(width);
    final gutter = LizSpacing.gutter(width);
    final phone = context.isPhone;
    final p = context.liz;
    final searching = _query.trim().length >= 2;
    final count = searching ? results.value?.length : null;

    return Scaffold(
      // Back always works: to the page before, or to Discover when search
      // was opened by its address. The page's heading is the field's.
      appBar: const LizTopBar(title: 'Search', titleIsHeading: false),
      body: MaxWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              header: true,
              headingLevel: 1,
              label: 'Search tools',
              child: const SizedBox(width: 1, height: 1),
            ),
            // The field is the page: this screen exists to be typed into.
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, phone ? 8 : 28, gutter, 0),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                style: (phone ? LizText.body : LizText.title3).copyWith(
                  color: p.textPrimary,
                  fontWeight: FontWeight.w400,
                ),
                decoration: InputDecoration(
                  hintText: 'Search tools, tags, categories…',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: phone ? 14 : 18,
                  ),
                  prefixIcon: const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.search, size: 22),
                  ),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => _search(''),
                        ),
                ),
              ),
            ),
            // What came back, and the one filter — on a line of their own.
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 12),
              child: Row(
                children: [
                  Expanded(
                    child: count == null
                        ? Text(
                            searching ? 'Searching…' : 'Suggestions',
                            style: LizText.subhead.copyWith(
                              color: p.textSecondary,
                            ),
                          )
                        : Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: count == 1 ? '1 tool' : '$count tools',
                                  style: LizText.subhead.copyWith(
                                    color: p.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: LizText.tabular,
                                  ),
                                ),
                                TextSpan(
                                  text: ' for \u201c${_query.trim()}\u201d',
                                  style: LizText.subhead.copyWith(
                                    color: p.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  if (searching)
                    PricingFilter(
                      selected: _pricing,
                      onChanged: (value) => setState(() => _pricing = value),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: Divider(height: 1, color: p.hairline),
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
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
      child: Material(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go(
            Uri(path: '/ask', queryParameters: {'q': q}).toString(),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const LizMark(size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ask Liz: \u201c$q\u201d',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LizText.callout.copyWith(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Answers by what a tool does, not only its name.',
                        style: LizText.footnote.copyWith(
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.arrow_forward, size: 18, color: p.textSecondary),
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
        ? _Suggestions(gutter: gutter, onPick: _search)
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
                        ? 'Try a broader term, or describe the job to Ask '
                              'Liz.'
                        : 'Try a broader term, or any price.',
                    action: _pricing == null
                        ? OutlinedButton(
                            onPressed: () => context.go(
                              Uri(
                                path: '/ask',
                                queryParameters: {'q': _query.trim()},
                              ).toString(),
                            ),
                            child: const Text('Ask Liz'),
                          )
                        : OutlinedButton(
                            onPressed: () => setState(() => _pricing = null),
                            child: const Text('Any price'),
                          ),
                  )
                : GridView.builder(
                    padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 32),
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

/// Before anything is typed: what people look for, one tap away, and a
/// pointer to Ask Liz for a job rather than a name. An empty page with a
/// magnifying glass in the middle told nobody anything.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.gutter, required this.onPick});
  final double gutter;
  final ValueChanged<String> onPick;

  static const _popular = [
    'video editing',
    'transcription',
    'image generation',
    'coding assistant',
    'voice',
    'writing',
    'open source',
    'meeting notes',
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 20, gutter, 32),
      children: [
        Text(
          'Popular searches',
          style: LizText.label.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final term in _popular)
              ActionChip(
                avatar: Icon(Icons.search, size: 16, color: p.textSecondary),
                label: Text(term),
                onPressed: () => onPick(term),
              ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          'Know the job, not the name?',
          style: LizText.label.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 12),
        Material(
          color: p.surface,
          shape: LizRadius.shape(
            LizRadius.md,
            side: BorderSide(color: p.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.go('/ask'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const LizMark(size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ask Liz',
                          style: LizText.callout.copyWith(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Describe what you need — \u201cturn a podcast into '
                          'clips\u201d — and get tools that do it.',
                          style: LizText.footnote.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.arrow_forward, size: 18, color: p.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
