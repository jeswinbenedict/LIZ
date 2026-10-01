import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The browser tab's title while [child] is on screen, restored when it
/// leaves.
///
/// Search engines read the title after the page's script has run, so a tool
/// page whose static HTML says "Koi.rest — … | Liz" (liz_scraper.prerender)
/// must keep saying so once the app has drawn — MaterialApp's own title
/// replaced it with "Liz". Flutter's Title widget sets the title but never
/// puts it back, which left the last tool's name on the Discover tab.
class PageTitle extends StatefulWidget {
  const PageTitle({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  /// What every other screen is called.
  static const defaultTitle = 'Liz — Discover the next big AI tool';

  /// A tool page's title, cut the way liz_scraper.prerender cuts it, so the
  /// title before and after the app loads is the same string.
  static String forTool(String name, String tagline) {
    final text = tagline.trim().isEmpty ? name : '$name — ${tagline.trim()}';
    return '${_clip(text, 70)} | Liz';
  }

  /// The alternatives page's title, as the prerendered page carries it.
  static String forAlternatives(String name) =>
      '${_clip('Alternatives to $name', 70)} | Liz';

  static String _clip(String text, int limit) {
    final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= limit) return t;
    final cut = t.substring(0, limit - 1);
    final space = cut.lastIndexOf(' ');
    return '${space > 0 ? cut.substring(0, space) : cut}…';
  }

  @override
  State<PageTitle> createState() => _PageTitleState();
}

class _PageTitleState extends State<PageTitle> {
  void _set(String label) {
    SystemChrome.setApplicationSwitcherDescription(
      ApplicationSwitcherDescription(label: label),
    );
  }

  @override
  void initState() {
    super.initState();
    _set(widget.title);
  }

  @override
  void didUpdateWidget(PageTitle old) {
    super.didUpdateWidget(old);
    if (old.title != widget.title) _set(widget.title);
  }

  @override
  void dispose() {
    _set(PageTitle.defaultTitle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
