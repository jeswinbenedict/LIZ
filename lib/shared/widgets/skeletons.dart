import 'package:flutter/material.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';

/// Placeholders shaped like the content that is about to arrive.
///
/// A centred spinner tells someone that something is happening but not what,
/// and the page jumps when the real content lands. Blocks in the layout the
/// cards will occupy make the wait read as "this is loading" instead of "this
/// is broken", and the arrival is a fill rather than a jolt.

/// One shimmering block. A [width] of null stretches to the available space.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = LizRadius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Sweeps a soft highlight across its children so the placeholder reads as
/// pending rather than as an empty grey layout.
///
/// The sweep stops when the platform asks for reduced motion; a repeating
/// animation is exactly what that setting exists to silence.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final highlight = Theme.of(context).colorScheme.surface;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) {
          // Slide a band of light across the full width, entering from the
          // left and leaving on the right over one cycle.
          final travel = _controller.value * 2 - 0.5;
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              highlight.withValues(alpha: 0.55),
              Colors.transparent,
            ],
            stops: [
              (travel - 0.25).clamp(0.0, 1.0),
              travel.clamp(0.0, 1.0),
              (travel + 0.25).clamp(0.0, 1.0),
            ],
          ).createShader(bounds);
        },
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Wraps a set of placeholder shapes: shimmering, announced once as loading,
/// and otherwise invisible to a screen reader.
class _SkeletonScope extends StatelessWidget {
  const _SkeletonScope({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      // The shapes carry no meaning of their own — the one label above says
      // everything a screen reader needs while the content is on its way.
      child: ExcludeSemantics(child: Shimmer(child: child)),
    );
  }
}

/// A single tool card placeholder, laid out like ToolCard.
class ToolCardSkeleton extends StatelessWidget {
  const ToolCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(LizSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 52, height: 52, radius: LizRadius.md),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 116, height: 15),
                      SizedBox(height: 8),
                      SkeletonBox(height: 11),
                      SizedBox(height: 6),
                      SkeletonBox(width: 90, height: 11),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SkeletonBox(height: 11),
            const SizedBox(height: 6),
            const SkeletonBox(height: 11),
            const Spacer(),
            Row(
              children: const [
                SkeletonBox(width: 74, height: 20),
                SizedBox(width: 8),
                SkeletonBox(width: 54, height: 20),
                Spacer(),
                SkeletonBox(width: 28, height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The grid of tool placeholders shown while the first page of a feed loads.
/// Mirrors the geometry of the real grid so nothing shifts on arrival.
class ToolGridSkeletonSliver extends StatelessWidget {
  const ToolGridSkeletonSliver({super.key, this.count = 6});
  final int count;

  @override
  Widget build(BuildContext context) {
    final columns = gridColumnsFor(MediaQuery.sizeOf(context).width);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      sliver: SliverToBoxAdapter(
        child: _SkeletonScope(
          label: 'Loading tools',
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent: toolCardExtent(context),
            ),
            itemCount: count,
            itemBuilder: (_, __) => const ToolCardSkeleton(),
          ),
        ),
      ),
    );
  }
}

/// The scrollable version, for screens that show a grid without slivers.
class ToolGridSkeleton extends StatelessWidget {
  const ToolGridSkeleton({super.key, this.count = 6});
  final int count;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(slivers: [ToolGridSkeletonSliver(count: count)]);
  }
}

/// Placeholders for the news feed: image strip, headline, two lines of snippet.
class NewsListSkeletonSliver extends StatelessWidget {
  const NewsListSkeletonSliver({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      sliver: SliverToBoxAdapter(
        child: _SkeletonScope(
          label: 'Loading news',
          child: Column(
            children: [
              for (var i = 0; i < count; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SkeletonBox(height: 168, radius: LizRadius.lg),
                        Padding(
                          padding: const EdgeInsets.all(LizSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              SkeletonBox(width: 96, height: 16),
                              SizedBox(height: 12),
                              SkeletonBox(height: 15),
                              SizedBox(height: 8),
                              SkeletonBox(height: 11),
                              SizedBox(height: 6),
                              SkeletonBox(width: 200, height: 11),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
