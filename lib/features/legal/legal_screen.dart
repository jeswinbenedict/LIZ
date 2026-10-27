import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/widgets/top_bar.dart';

/// Where questions about these documents go. Set at build time with
/// `--dart-define=LEGAL_CONTACT=...` once there is an address to publish; until
/// then the documents point at what a reader can already do in the app.
const legalContact = String.fromEnvironment('LEGAL_CONTACT');

/// The privacy policy and terms, in the app rather than behind an external
/// link: there is no host yet to link to, and a policy that lives beside the
/// code is easier to keep true when the code changes.
///
/// Every statement in [LegalDocument.privacy] describes something the schema
/// or an Edge Function actually does — what is stored, for how long, and what
/// happens to it when an account is deleted. Change one, change the other.
///
/// Laid out as a document (docs/DESIGN.md §8): the title and date, the short
/// version in a panel, then the sections between hairlines. A wide window
/// adds a contents rail that stays in view and marks where the reader is.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, required this.document});
  final LegalDocument document;

  /// From this width the contents rail sits beside the text.
  static const railWidth = 1000.0;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  /// Space above the text, inside the scroll view.
  static const _top = 40.0;

  final _scroll = ScrollController();
  final _row = GlobalKey();
  final _rail = GlobalKey();
  late List<GlobalKey> _sections = _keys();
  int _active = 0;

  /// One per section, and one for Questions.
  List<GlobalKey> _keys() => [
    for (var i = 0; i <= widget.document.sections.length; i++) GlobalKey(),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_track);
  }

  @override
  void didUpdateWidget(LegalScreen old) {
    super.didUpdateWidget(old);
    if (old.document != widget.document) _sections = _keys();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The section whose heading was last scrolled past the top third.
  void _track() {
    if (!_scroll.hasClients) return;
    final viewport = context.findRenderObject() as RenderBox?;
    if (viewport == null) return;
    var active = 0;
    if (_scroll.position.extentAfter < 4) {
      active = _sections.length - 1;
    } else {
      for (var i = 0; i < _sections.length; i++) {
        final box =
            _sections[i].currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;
        final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
        if (top <= 180) active = i;
      }
    }
    if (active != _active) setState(() => _active = active);
  }

  void _jumpTo(int i) {
    final target = _sections[i].currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: LizMotion.of(context, LizMotion.emphasized),
      curve: LizMotion.emphasizedCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final document = widget.document;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = LizSpacing.gutter(width);
    final wide = width >= LegalScreen.railWidth;
    final phone = context.isPhone;
    final paragraph = LizText.body.copyWith(
      color: p.textPrimary,
      height: 26 / 15,
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          header: true,
          headingLevel: 1,
          child: Text(
            document.title,
            style: (phone ? LizText.title1 : LizText.largeTitle).copyWith(
              color: p.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Last updated ${document.updated}',
          style: LizText.subhead.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: 24),
        _Summary(text: document.summary),
        for (var i = 0; i < document.sections.length; i++)
          _Section(
            key: _sections[i],
            heading: document.sections[i].heading,
            children: [
              for (final line in document.sections[i].body)
                Text(line, style: paragraph),
            ],
          ),
        _Section(
          key: _sections.last,
          heading: 'Questions',
          children: [
            Text(
              legalContact.isEmpty
                  ? 'To remove everything tied to you, use Settings > Delete '
                        'account. To have a review, post or listing looked at, '
                        'use Report on it and a moderator will see it.'
                  : 'Write to $legalContact. To remove everything tied to you '
                        'straight away, use Settings > Delete account.',
              style: paragraph,
            ),
          ],
        ),
        const SizedBox(height: 40),
        _OtherDocument(document: document.other),
      ],
    );

    return Scaffold(
      appBar: LizTopBar(title: document.title, titleIsHeading: false),
      body: Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(gutter, phone ? 12 : _top, gutter, 64),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1040 : 720),
              child: wide
                  ? Row(
                      key: _row,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 232,
                          child: _StickyRail(
                            scroll: _scroll,
                            row: _row,
                            rail: _rail,
                            top: _top,
                            child: _Contents(
                              key: _rail,
                              titles: [
                                for (final s in document.sections) s.heading,
                                'Questions',
                              ],
                              active: _active,
                              onTap: _jumpTo,
                              other: document.other,
                            ),
                          ),
                        ),
                        const SizedBox(width: 64),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 720),
                              child: text,
                            ),
                          ),
                        ),
                      ],
                    )
                  : text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the contents rail in view while the text scrolls past it, and stops
/// it at the foot of the text. It stays inside the scroll view, so the wheel
/// still scrolls with the pointer over it.
class _StickyRail extends StatelessWidget {
  const _StickyRail({
    required this.scroll,
    required this.row,
    required this.rail,
    required this.top,
    required this.child,
  });
  final ScrollController scroll;
  final GlobalKey row;
  final GlobalKey rail;

  /// Where the row starts in the scrolled content.
  final double top;
  final Widget child;

  /// How far below the top of the view the rail rides.
  static const _ride = 24.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: scroll,
      child: child,
      builder: (context, child) {
        final rowBox = row.currentContext?.findRenderObject() as RenderBox?;
        final railBox = rail.currentContext?.findRenderObject() as RenderBox?;
        var dy = 0.0;
        if (scroll.hasClients &&
            rowBox != null &&
            railBox != null &&
            rowBox.hasSize &&
            railBox.hasSize) {
          final room = rowBox.size.height - railBox.size.height;
          dy = (scroll.offset - top + _ride).clamp(0.0, room < 0 ? 0.0 : room);
        }
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
    );
  }
}

/// "On this page": the sections with the current one marked, and the other
/// document under them.
class _Contents extends StatelessWidget {
  const _Contents({
    super.key,
    required this.titles,
    required this.active,
    required this.onTap,
    required this.other,
  });
  final List<String> titles;
  final int active;
  final ValueChanged<int> onTap;
  final LegalDocument other;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final label = LizText.subhead.copyWith(color: p.textSecondary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 10),
          child: Text('On this page', style: label),
        ),
        for (var i = 0; i < titles.length; i++)
          _ContentsLink(
            title: titles[i],
            selected: i == active,
            onTap: () => onTap(i),
          ),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 10),
          child: Text('Also read', style: label),
        ),
        _ContentsLink(
          title: other.title,
          selected: false,
          onTap: () => context.pushReplacement(other.path),
        ),
      ],
    );
  }
}

/// One line of the contents: a rule down its left that turns to ink for the
/// section being read.
class _ContentsLink extends StatelessWidget {
  const _ContentsLink({
    required this.title,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                width: 2,
                color: selected ? p.textPrimary : p.hairline,
              ),
            ),
          ),
          child: Text(
            title,
            style: LizText.callout.copyWith(
              color: selected ? p.textPrimary : p.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// The short version, in a panel above the full text.
class _Summary extends StatelessWidget {
  const _Summary({required this.text});
  final String text;

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
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'In short',
              style: LizText.subhead.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: LizText.title3.copyWith(
                color: p.textPrimary,
                fontWeight: FontWeight.w400,
                height: 27 / 17,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section: a hairline, its heading, its paragraphs.
class _Section extends StatelessWidget {
  const _Section({super.key, required this.heading, required this.children});
  final String heading;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: p.hairline),
          const SizedBox(height: 28),
          Semantics(
            container: true,
            header: true,
            child: Text(
              heading,
              style: LizText.title2.copyWith(color: p.textPrimary),
            ),
          ),
          for (final child in children) ...[const SizedBox(height: 12), child],
        ],
      ),
    );
  }
}

/// The other document, at the foot: read it next without a trip back. It
/// replaces this one, so Back still returns to where the reader came from.
class _OtherDocument extends StatelessWidget {
  const _OtherDocument({required this.document});
  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return Material(
      color: p.surface,
      shape: LizRadius.shape(LizRadius.md, side: BorderSide(color: p.hairline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.pushReplacement(document.path),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Also read',
                      style: LizText.footnote.copyWith(color: p.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      document.title,
                      style: LizText.headline.copyWith(color: p.textPrimary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, size: 20, color: p.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class LegalSection {
  const LegalSection(this.heading, this.body);
  final String heading;
  final List<String> body;
}

class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.path,
    required this.updated,
    required this.summary,
    required this.sections,
  });

  final String title;

  /// Where the document lives in the app.
  final String path;
  final String updated;
  final String summary;
  final List<LegalSection> sections;

  /// The other document, offered at the foot of this one.
  LegalDocument get other => identical(this, privacy) ? terms : privacy;

  static const privacy = LegalDocument(
    title: 'Privacy policy',
    path: '/privacy',
    updated: '5 October 2026',
    summary:
        'Liz keeps what it needs to run your account, to keep the service '
        'working, and to learn which tools people find useful. Nothing is kept '
        'for advertising: there are no ads, no third-party trackers, and '
        'nothing is sold.',
    sections: [
      LegalSection('Every visit', [
        'On your first visit Liz gives your browser a random ID. With it, Liz '
            'counts which pages and tools are viewed, which tool websites '
            'you visit from Liz, what is saved, and what is searched for or '
            'asked. This is how "Rising" knows what people are interested in, '
            'and how Liz learns what its catalog is missing. It also records '
            'how long the first screen took to appear, so Liz can tell when '
            'it has become slow. The ID is not '
            'linked to your name, it is not a cookie, and no IP address is '
            'stored with it. Clearing your browser\'s site data resets it.',
        'The words you type into search or ask Liz are kept for 90 days and '
            'then deleted. The counts are kept for 13 months.',
        'Using Liz needs an account. Anything saved in your browser before '
            'it did moves into your account when you sign in.',
        'If the app crashes, it sends an error report: the error message, where '
            'in the code it happened, which screen you were on, the app version '
            'and the kind of browser. Reports are deleted after 30 days.',
        'Asking Liz a question, loading tool logos and reading a tool\'s release '
            'notes are free to use but limited per visitor, so they count '
            'requests against your IP address. Those counters are deleted after '
            'a day.',
      ]),
      LegalSection('If you have an account', [
        'Your email address and password, or the Google account you sign in '
            'with. The password is stored only as a hash by the sign-in '
            'service; nobody can read it.',
        'What you choose to add: a display name, a bio and a picture; the '
            'tools you save and the people you follow; the kinds of tools you '
            'are interested in and which alerts you want; the reviews, posts, '
            'comments and likes you leave; and anything you report.',
        'Notifications sent to you inside Liz. If you turn on browser '
            'notifications, a token that lets Liz send them to that browser.',
        'While you are signed in, the usage counts above are linked to your '
            'account, so Liz can tell you when a tool you saved changes.',
        'If you are a moderator, the setup for your authenticator app. Its '
            'secret is held by the sign-in service, not by Liz.',
      ]),
      LegalSection('What other people can see', [
        'Your display name, bio, picture and role, and the reviews, posts and '
            'comments you write, are public — anyone can read them without an '
            'account.',
        'What you save, who you follow, your interests and alert choices, '
            'your notifications and what you report are visible only to you. '
            'Reports are also visible to moderators.',
      ]),
      LegalSection('Who else handles it', [
        'Supabase hosts the database and server functions, and keeps its own '
            'short-lived request logs.',
        'Firebase Authentication, from Google, handles signing in: it holds '
            'your email address, your password hash or Google sign-in, and '
            'your authenticator setup if you have one, and sends the emails '
            'for confirming an address, resetting a password and signing in '
            'with a link.',
        'Firebase Cloud Messaging delivers browser notifications, and only if '
            'you turn them on.',
        'Tool summaries and the quick takes on news stories are written by '
            'open-source models on Groq, or on another host of open-source '
            'models when Groq is unavailable. Only public text is sent — a '
            'tool\'s description, a story\'s headline and summary — never '
            'anything about you.',
        'Logos are copied to Liz\'s own storage or fetched by Liz\'s own '
            'server, so the sites of the tools you browse do not see your '
            'address.',
      ]),
      LegalSection('Getting a copy', [
        'Settings > Download my data saves a file with what your account '
            'holds: your profile, interests and alert choices, saved tools, '
            'the people you follow, your reviews, posts and notifications. '
            'Usage counts are not in it, because they are tied to a random '
            'browser ID rather than to you.',
      ]),
      LegalSection('Deleting your account', [
        'Settings > Delete account removes your account at once, together with '
            'your sign-in, profile, interests and alert choices, saves, follows, '
            'reviews, posts, comments, likes, notifications and notification '
            'tokens.',
        'Three things are kept without your name on them: reports you filed, '
            'so moderation decisions still make sense; usage counts, which '
            'expire as described above; and error reports, which expire after '
            '30 days anyway.',
      ]),
      LegalSection('Changes', [
        'If this policy changes, the date at the top changes with it. A change '
            'that collects something new will be announced in the app first.',
      ]),
    ],
  );

  static const terms = LegalDocument(
    title: 'Terms of service',
    path: '/terms',
    updated: '27 September 2026',
    summary:
        'Liz is a free directory of AI tools. Use it, share what you think of '
        'the tools, and treat other people decently.',
    sections: [
      LegalSection('The catalog', [
        'Listings are gathered automatically from public sources such as '
            'Product Hunt, Hacker News and GitHub, and their summaries are '
            'written by software. They can be out of date or wrong. Check '
            'pricing and terms on the tool\'s own site before you rely on them.',
        'A listing is not an endorsement, and Liz is not responsible for the '
            'tools or sites it links to.',
      ]),
      LegalSection('Your account', [
        'Keep your password to yourself; what happens under your account is '
            'your responsibility. You can delete your account at any time from '
            'Settings.',
      ]),
      LegalSection('What you post', [
        'Reviews, posts and comments stay yours. By posting them you let Liz '
            'show them publicly for as long as they are up.',
        'Do not post anything unlawful, harassing, hateful or sexually '
            'explicit, do not impersonate anyone, do not spam, and do not '
            'review a tool you make or are paid to promote without saying so.',
        'Anyone can report content. Something several established accounts '
            'report is hidden automatically until a moderator reviews it, and '
            'moderators can hide anything that breaks these rules.',
      ]),
      LegalSection('Fair use of the service', [
        'Do not try to get round rate limits, reach data that is not yours, or '
            'disrupt the service for other people. Reading the public catalog '
            'is fine; hammering it is not.',
      ]),
      LegalSection('No warranty', [
        'Liz is provided as it is, without any promise that it will be '
            'available, accurate or fit for a particular purpose. To the extent '
            'the law allows, Liz is not liable for losses that come from using '
            'it or from relying on what it says.',
      ]),
      LegalSection('Changes', [
        'These terms can change. The date at the top says when they last did, '
            'and continuing to use Liz after a change means accepting it.',
      ]),
    ],
  );
}
