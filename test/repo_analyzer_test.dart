import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liz/app/theme.dart';
import 'package:liz/features/repo_analyzer/graph_view.dart';
import 'package:liz/features/repo_analyzer/repo_analyzer_screen.dart';
import 'package:liz/features/repo_analyzer/repo_models.dart';
import 'package:liz/features/repo_analyzer/repo_report_screen.dart';
import 'package:liz/features/repo_analyzer/repo_service.dart';

// The Repository Analyzer's screens, on a real report: spring-petclinic as
// the analysis engine reported it (test/fixtures, captured from GitHub), with
// a fake service in place of the functions.

final _fixture =
    jsonDecode(
          File('test/fixtures/repo_report_petclinic.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

Map<String, dynamic> _row({
  String status = 'done',
  int progress = 100,
  String? error,
}) => {
  'id': '11111111-1111-1111-1111-111111111111',
  'full_name': 'spring-projects/spring-petclinic',
  'ref': 'main',
  'commit_sha': 'a' * 40,
  'status': status,
  'stage': status == 'done' ? 'Done' : 'Reading files (45/94)',
  'progress': progress,
  'error': error,
  'is_private': false,
  'created_at': DateTime.now().toIso8601String(),
  'updated_at': DateTime.now().toIso8601String(),
};

class FakeService implements RepoAnalyzerService {
  FakeService({this.row});
  Map<String, dynamic>? row;
  final asked = <(String, String?)>[];
  final started = <(String, String?, String?)>[];
  String? failStartWith;

  @override
  Future<RepoBranches> branches(String url, {String? token}) async =>
      const RepoBranches('spring-projects/spring-petclinic', 'main', [
        'main',
        'gh-pages',
      ], false);

  @override
  Future<String> start(String url, {String? ref, String? token}) async {
    if (failStartWith != null) {
      throw RepoAnalyzerException(
        failStartWith!,
        code: 'not_found',
        status: 404,
      );
    }
    started.add((url, ref, token));
    return '11111111-1111-1111-1111-111111111111';
  }

  @override
  Future<List<AnalysisSummary>> mine() async => [
    AnalysisSummary.fromJson(row ?? _row()),
  ];

  @override
  Future<RepoAnalysis> get(String id) async {
    final r = row ?? _row();
    return RepoAnalysis(
      AnalysisSummary.fromJson(r),
      r['status'] == 'done'
          ? (_fixture['report'] as Map).cast<String, dynamic>()
          : null,
      r['status'] == 'done' ? _fixture['sections'] : null,
      r['status'] == 'done'
          ? {
              'overview': 'A Spring Boot sample app.',
              'howItWorks': 'Controllers render pages.',
              'learnToBuild': ['Spring Boot', 'JPA'],
            }
          : null,
    );
  }

  @override
  Future<String?> fileContent(String id, String path) async =>
      (_fixture['files'] as Map)[path] as String?;

  @override
  Future<RepoAnswer> ask(String id, String question, {String? focus}) async {
    asked.add((question, focus));
    return RepoAnswer(
      question,
      'It uses **Spring MVC** controllers [pom.xml:1].',
      const [('pom.xml', 1)],
    );
  }

  @override
  Future<void> delete(String id) async {}
}

Future<FakeService> _pump(
  WidgetTester tester,
  Widget screen, {
  FakeService? service,
  Size size = const Size(1280, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = service ?? FakeService();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(
        path: '/repos/:id',
        builder: (_, st) => RepoReportScreen(id: st.pathParameters['id']!),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [repoAnalyzerServiceProvider.overrideWithValue(s)],
      child: MaterialApp.router(
        theme: LizTheme.app(),
        routerConfig: router,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

const _report = RepoReportScreen(id: '11111111-1111-1111-1111-111111111111');

void main() {
  test('the report reads back what the engine wrote', () {
    final a = RepoAnalysis(
      AnalysisSummary.fromJson(_row()),
      (_fixture['report'] as Map).cast<String, dynamic>(),
      _fixture['sections'],
      null,
    );
    expect(a.sections, hasLength(23));
    expect(
      a.techs.map((t) => t.name),
      containsAll(['Spring Boot', 'PostgreSQL', 'Docker', 'Kubernetes']),
    );
    expect(
      a.entities.map((e) => e.name),
      containsAll(['owners', 'pets', 'visits']),
    );
    expect(a.endpoints.where((e) => e.framework == 'Spring'), isNotEmpty);
    expect(
      a.graphs.map((g) => g.id),
      containsAll(['system', 'database', 'api']),
    );
  });

  test('the diagram layout puts each node right of what points at it', () {
    final g = ArchGraph.fromJson({
      'id': 'x',
      'title': 't',
      'layout': 'flow',
      'note': '',
      'mermaid': '',
      'nodes': [
        for (final id in ['user', 'app', 'api', 'db', 'loose'])
          {'id': id, 'label': id, 'kind': 'service'},
      ],
      'edges': [
        {'from': 'user', 'to': 'app'},
        {'from': 'app', 'to': 'api'},
        {'from': 'api', 'to': 'db'},
        {'from': 'user', 'to': 'api'},
      ],
    });
    final (pos, size) = layoutGraph(g);
    expect(
      pos['user']!.dx < pos['app']!.dx &&
          pos['app']!.dx < pos['api']!.dx &&
          pos['api']!.dx < pos['db']!.dx,
      isTrue,
    );
    expect(pos['loose']!.dx, greaterThan(pos['db']!.dx));
    expect(size.width, greaterThan(0));
  });

  testWidgets('the form checks the address and starts an analysis', (
    tester,
  ) async {
    final s = await _pump(tester, const RepoAnalyzerScreen());
    expect(find.text('Repository Analyzer'), findsOneWidget);
    expect(
      find.text('spring-projects/spring-petclinic'),
      findsOneWidget,
      reason: 'past analyses are listed',
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'GitHub repository'),
      'not a repo',
    );
    await tester.tap(find.text('Analyse repository'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Paste a GitHub repository address'),
      findsOneWidget,
    );
    expect(s.started, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'GitHub repository'),
      'https://github.com/spring-projects/spring-petclinic',
    );
    await tester.tap(find.text('Load branches'));
    await tester.pumpAndSettle();
    expect(find.text('main (default)'), findsOneWidget);

    await tester.tap(find.text('Analyse repository'));
    await tester.pumpAndSettle();
    expect(
      s.started.single.$1,
      'https://github.com/spring-projects/spring-petclinic',
    );
    expect(
      s.started.single.$3,
      isNull,
      reason: 'no token unless the repository is private',
    );
    expect(
      find.text('spring-projects/spring-petclinic'),
      findsWidgets,
      reason: 'the report opens',
    );
  });

  testWidgets('a GitHub refusal is shown on the form', (tester) async {
    final s = FakeService()
      ..failStartWith = 'No public repository by that name.';
    await _pump(tester, const RepoAnalyzerScreen(), service: s);
    await tester.enterText(
      find.widgetWithText(TextField, 'GitHub repository'),
      'someone/private-thing',
    );
    await tester.tap(find.text('Analyse repository'));
    await tester.pumpAndSettle();
    expect(find.text('No public repository by that name.'), findsOneWidget);
  });

  testWidgets(
    'a private repository asks for a token, sent only with that run',
    (tester) async {
      final s = await _pump(tester, const RepoAnalyzerScreen());
      await tester.enterText(
        find.widgetWithText(TextField, 'GitHub repository'),
        'acme/secret-app',
      );
      await tester.tap(find.text('Private repository'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'GitHub token'),
        'github_pat_abc',
      );
      await tester.tap(find.text('Analyse repository'));
      await tester.pumpAndSettle();
      expect(s.started.single.$3, 'github_pat_abc');
    },
  );

  testWidgets('a running analysis shows its stage and progress', (
    tester,
  ) async {
    await _pump(
      tester,
      _report,
      service: FakeService(row: _row(status: 'running', progress: 45)),
    );
    expect(find.text('Reading files (45/94)'), findsOneWidget);
    expect(find.text('45%'), findsOneWidget);
    // Stop the poll before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed analysis says why and offers to try again', (
    tester,
  ) async {
    await _pump(
      tester,
      _report,
      service: FakeService(
        row: _row(
          status: 'failed',
          error: 'GitHub’s request limit is used up.',
        ),
      ),
    );
    expect(find.text('GitHub’s request limit is used up.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('every tab of a finished report shows what was found', (
    tester,
  ) async {
    await _pump(tester, _report);
    expect(find.text('A Spring Boot sample app.'), findsOneWidget);
    expect(find.text('1. Repository overview'), findsOneWidget);
    expect(find.text('23. Complete technical summary'), findsOneWidget);

    Future<void> open(String tab) async {
      await tester.ensureVisible(find.text(tab).first);
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
    }

    await open('Architecture');
    expect(find.byType(GraphView), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    await open('Code');
    expect(find.text('Find a file'), findsOneWidget);
    await open('Stack');
    expect(find.text('Spring Boot'), findsWidgets);
    expect(find.text('Confirmed'), findsWidgets);
    await open('API');
    expect(find.textContaining('/owners'), findsWidgets);
    await open('Data');
    expect(find.text('owners'), findsWidgets);
    await open('Build & deploy');
    expect(find.text('CI/CD workflows'), findsOneWidget);
    await open('Security & quality');
    expect(find.text('Security analysis'), findsOneWidget);
    await open('Ask');
    expect(find.text('How can I run this project locally?'), findsOneWidget);
  });

  testWidgets(
    'Explain on a diagram part asks about it, and the answer cites files',
    (tester) async {
      final s = await _pump(tester, _report);
      await tester.tap(find.text('Architecture'));
      await tester.pumpAndSettle();
      final node = find
          .descendant(
            of: find.byType(GraphView),
            matching: find.byType(InkWell),
          )
          .first;
      await tester.tap(node);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Explain this'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explain this'));
      await tester.pumpAndSettle();
      expect(s.asked, hasLength(1));
      expect(
        find.textContaining('Spring MVC', findRichText: true),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Open pom.xml at line 1'), findsOneWidget);
    },
  );

  testWidgets('a cited file opens at its line', (tester) async {
    await _pump(tester, _report);
    await tester.ensureVisible(find.text('Ask'));
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How can I run this project locally?'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Open pom.xml at line 1'));
    await tester.pumpAndSettle();
    expect(find.text('pom.xml'), findsWidgets);
    expect(find.textContaining('lines'), findsOneWidget);
  });

  for (final (name, size, scale) in [
    ('a 320-wide phone', const Size(320, 640), 1.0),
    ('text at 1.5x', const Size(375, 812), 1.5),
    ('a tablet', const Size(834, 1112), 1.0),
  ]) {
    testWidgets('the analyzer and its report fit $name', (tester) async {
      await _pump(
        tester,
        const RepoAnalyzerScreen(),
        size: size,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      await _pump(tester, _report, size: size, textScale: scale);
      for (final tab in [
        'Architecture',
        'Stack',
        'API',
        'Data',
        'Build & deploy',
        'Ask',
      ]) {
        await tester.ensureVisible(find.text(tab).first);
        await tester.tap(find.text(tab).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
    });
  }

  testWidgets('the report meets the accessibility guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _report, size: const Size(390, 844));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await _pump(tester, const RepoAnalyzerScreen(), size: const Size(390, 844));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
