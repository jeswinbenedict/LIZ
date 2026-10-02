import 'package:flutter/material.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import '../../shared/widgets/page_header.dart';

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
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.document});
  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    final heading = LizText.title3.copyWith(color: p.textPrimary);
    final paragraph = LizText.body.copyWith(
      color: p.textPrimary,
      height: 24 / 15,
    );

    return Scaffold(
      appBar: AppBar(title: PageHeading(document.title)),
      body: MaxWidth(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 56),
          children: [
            Text(
              'Last updated ${document.updated}',
              style: LizText.footnote.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              document.summary,
              style: LizText.title3.copyWith(
                color: p.textSecondary,
                fontWeight: FontWeight.w400,
                height: 27 / 18,
              ),
            ),
            for (final section in document.sections) ...[
              const SizedBox(height: 28),
              Semantics(
                container: true,
                header: true,
                child: Text(section.heading, style: heading),
              ),
              for (final line in section.body) ...[
                const SizedBox(height: 10),
                Text(line, style: paragraph),
              ],
            ],
            const SizedBox(height: 28),
            Semantics(
              container: true,
              header: true,
              child: Text('Questions', style: heading),
            ),
            const SizedBox(height: 8),
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
    required this.updated,
    required this.summary,
    required this.sections,
  });

  final String title;
  final String updated;
  final String summary;
  final List<LegalSection> sections;

  static const privacy = LegalDocument(
    title: 'Privacy policy',
    updated: '2 October 2026',
    summary:
        'Liz keeps what it needs to run your account, to keep the service '
        'working, and to learn which tools people find useful. Nothing is kept '
        'for advertising: there are no ads, no third-party trackers, and '
        'nothing is sold.',
    sections: [
      LegalSection('If you only browse', [
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
        'Tools you save without an account and the kinds of tools you say '
            'you are interested in are kept in your own browser. If you sign '
            'in, your saved tools and interests move into your account.',
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
