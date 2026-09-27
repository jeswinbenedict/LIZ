import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/breakpoints.dart';
import '../../core/providers.dart';
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
      return ref
          .watch(contentRepositoryProvider)
          .searchTools(key.query, pricing: key.pricing);
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
    final columns = gridColumnsFor(MediaQuery.sizeOf(context).width);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: 'Search tools, tags, categories…',
            filled: false,
            border: InputBorder.none,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
        ),
      ),
      body: MaxWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: PricingFilter(
                selected: _pricing,
                onChanged: (value) => setState(() => _pricing = value),
              ),
            ),
            Expanded(child: _results(results, columns)),
          ],
        ),
      ),
    );
  }

  Widget _results(AsyncValue<List<Tool>> results, int columns) {
    final key = (query: _query, pricing: _pricing);
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
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      mainAxisExtent: toolCardExtent(context),
                    ),
                    itemCount: tools.length,
                    itemBuilder: (context, i) => ToolCard(tool: tools[i]),
                  ),
          );
  }
}
