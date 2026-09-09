import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/breakpoints.dart';
import '../../core/providers.dart';
import '../../shared/models/tool.dart';
import '../../shared/widgets/skeletons.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/tool_card.dart';

/// Search across tool name, tagline, description, tags, and category.
final searchResultsProvider = FutureProvider.autoDispose
    .family<List<Tool>, String>((ref, query) async {
      // Typing "video editor" used to leave a cached result for every prefix the
      // debounce happened to fire on, each holding up to thirty tools.
      if (query.trim().length < 2) return [];
      return ref.watch(contentRepositoryProvider).searchTools(query);
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
    final results = ref.watch(searchResultsProvider(_query));
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
        child: _query.trim().length < 2
            ? const EmptyView(
                icon: Icons.search,
                title: 'Search Liz',
                message: 'Find AI tools by name, tag, or what they do.',
              )
            : results.when(
                loading: () => const ToolGridSkeleton(),
                error: (_, __) => ErrorView(
                  onRetry: () => ref.invalidate(searchResultsProvider(_query)),
                ),
                data: (tools) => tools.isEmpty
                    ? EmptyView(
                        icon: Icons.search_off,
                        title: 'No results for "$_query"',
                        message: 'Try a broader term.',
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
              ),
      ),
    );
  }
}
