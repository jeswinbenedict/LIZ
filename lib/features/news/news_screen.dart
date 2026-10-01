import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/widgets/news_card.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/skeletons.dart';
import '../../shared/widgets/states.dart';
import 'news_controller.dart';

/// Technology News Feed — live tech headlines from RSS/API ingestion, updated
/// hourly and pushed in real time via Supabase Realtime.
class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(newsControllerProvider);
    final controller = ref.read(newsControllerProvider.notifier);

    final phone = context.isPhone;
    final gutter = LizSpacing.gutter(MediaQuery.sizeOf(context).width);
    const column = 760.0;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          slivers: [
            if (phone) const PhoneTopBar(),
            SliverToBoxAdapter(
              child: MaxWidth(
                maxWidth: column + gutter * 2,
                child: PageHeader(
                  title: 'Tech News',
                  subtitle: phone
                      ? null
                      : 'The day in technology, with a quick take on each '
                            'story. Updated hourly.',
                  trailing: state.live ? const _LiveBadge() : null,
                  bottom: 4,
                ),
              ),
            ),
            if (state.loading)
              const NewsListSkeletonSliver()
            else if (state.error != null && state.items.isEmpty)
              SliverToBoxAdapter(child: ErrorView(onRetry: controller.refresh))
            else if (state.items.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyView(
                  icon: Icons.newspaper_outlined,
                  title: 'No news yet',
                  message:
                      'The feed fills up as the ingestion job pulls the latest tech headlines.',
                ),
              )
            else
              MaxWidthSliver(
                maxWidth: column + gutter * 2,
                sliver: SliverPadding(
                  padding: EdgeInsets.fromLTRB(gutter - 4, 0, gutter - 4, 32),
                  sliver: SliverList.separated(
                    itemCount: state.items.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Divider(height: 1, color: context.liz.hairline),
                    ),
                    itemBuilder: (context, i) {
                      if (i >= state.items.length - 3) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => controller.loadMore(),
                        );
                      }
                      return NewsCard(item: state.items[i]);
                    },
                  ),
                ),
              ),
            if (state.loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();
  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Semantics(
      label: 'Live: new stories appear as they arrive',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: ShapeDecoration(
          color: p.positive.withValues(alpha: 0.12),
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: p.positive,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Live',
              style: LizText.footnote.copyWith(
                color: LizColors.legibleOn(
                  p.positive,
                  Color.alphaBlend(
                    p.positive.withValues(alpha: 0.12),
                    p.canvas,
                  ),
                ),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
