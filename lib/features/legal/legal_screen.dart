import 'package:flutter/material.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';

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
      appBar: AppBar(title: Text(document.title)),
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
                header: true,
                child: Text(section.heading, style: heading),
              ),
              for (final line in section.body) ...[
                const SizedBox(height: 10),
                Text(line, style: paragraph),
              ],
            ],
            const SizedBox(height: 28),
            Semantics(header: true, child: Text('Questions', style: heading)),
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
    updated: '27 September 2026',
    summary:
        'Liz keeps what it needs to run your account and to keep the service '
        'working, and nothing for advertising. There are no ads, no analytics '
        'trackers, and nothing is sold.',
    sections: [
      LegalSection('If you only browse', [
        'Browsing without an account stores nothing that identifies you. Your '
            'light or dark theme choice is kept in your own browser.',
        'If the app crashes, it sends an error report: the error message, where '
            'in the code it happened, which screen you were on, the app version '
            'and the kind of browser. Reports are deleted after 30 days.',
        'Asking Liz a question, loading tool logos and reading a tool\'s release '
            'notes are free to use but limited per visitor, so they count '
            'requests against your IP address. Those counters are deleted after '
            'a day. The questions you ask Liz are not stored.',
      ]),
      LegalSection('If you have an account', [
        'Your email address and password. The password is stored only as a '
            'hash by the sign-in service; nobody can read it.',
        'What you choose to add: a display name, a bio and a picture, and the '
            'tools you save and follow, the reviews, posts, comments and likes '
            'you leave, and anything you report.',
        'Notifications sent to you inside Liz. If you turn on browser '
            'notifications, a token that lets Liz send them to that browser.',
      ]),
      LegalSection('What other people can see', [
        'Your display name, bio, picture and role, and the reviews, posts and '
            'comments you write, are public — anyone can read them without an '
            'account.',
        'What you save, what you follow, your notifications and what you '
            'report are visible only to you. Reports are also visible to '
            'moderators.',
      ]),
      LegalSection('Who else handles it', [
        'Supabase hosts the database, sign-in and server functions, and keeps '
            'its own short-lived request logs.',
        'Firebase Cloud Messaging delivers browser notifications, and only if '
            'you turn them on.',
        'Tool summaries are written by open-source models on Groq. Only the '
            'public description of a tool is sent — never anything about you.',
        'Logos are fetched by Liz\'s own server, so the sites of the tools you '
            'browse do not see your address.',
      ]),
      LegalSection('Deleting your account', [
        'Settings > Delete account removes your account at once, together with '
            'your profile, saves, follows, reviews, posts, comments, likes, '
            'notifications and notification tokens.',
        'Two things are kept without your name on them: reports you filed, so '
            'moderation decisions still make sense, and error reports, which '
            'expire after 30 days anyway.',
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
