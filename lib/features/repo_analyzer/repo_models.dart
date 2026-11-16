/// The Repository Analyzer's records, as the app reads them from
/// `repo_analyses` (supabase/migrations/0064) and the analyze-repo function.
///
/// The report is stored as JSON written by supabase/functions/_shared/repo;
/// these classes read it defensively, so a field a newer analysis adds or an
/// older one lacks never breaks the page.
library;

List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
    : const [];
List<String> _strings(Object? v) =>
    v is List ? v.map((e) => e.toString()).toList() : const [];
String _s(Object? v, [String fallback = '']) => v?.toString() ?? fallback;
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

enum AnalysisStatus { queued, running, done, failed }

AnalysisStatus _status(Object? v) => switch (v) {
  'done' => AnalysisStatus.done,
  'failed' => AnalysisStatus.failed,
  'queued' => AnalysisStatus.queued,
  _ => AnalysisStatus.running,
};

/// One row of the list: no report attached.
class AnalysisSummary {
  const AnalysisSummary({
    required this.id,
    required this.fullName,
    required this.ref,
    required this.commitSha,
    required this.status,
    required this.stage,
    required this.progress,
    required this.error,
    required this.isPrivate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AnalysisSummary.fromJson(Map<String, dynamic> j) => AnalysisSummary(
    id: _s(j['id']),
    fullName: _s(j['full_name']),
    ref: _s(j['ref']),
    commitSha: j['commit_sha'] as String?,
    status: _status(j['status']),
    stage: j['stage'] as String?,
    progress: _i(j['progress']),
    error: j['error'] as String?,
    isPrivate: j['is_private'] == true,
    createdAt: DateTime.tryParse(_s(j['created_at'])) ?? DateTime.now(),
    updatedAt: DateTime.tryParse(_s(j['updated_at'])) ?? DateTime.now(),
  );

  static const columns =
      'id, full_name, ref, commit_sha, status, stage, progress, error, '
      'is_private, created_at, updated_at';

  final String id;
  final String fullName;
  final String ref;
  final String? commitSha;
  final AnalysisStatus status;
  final String? stage;
  final int progress;
  final String? error;
  final bool isPrivate;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get shortSha =>
      (commitSha ?? '').length >= 7 ? commitSha!.substring(0, 7) : '';

  /// Still working, as far as anyone can tell: a run whose row has not moved
  /// for minutes was stopped by the platform and will not finish.
  bool get inProgress =>
      (status == AnalysisStatus.running || status == AnalysisStatus.queued) &&
      DateTime.now().difference(updatedAt) < const Duration(minutes: 6);

  bool get stalled =>
      (status == AnalysisStatus.running || status == AnalysisStatus.queued) &&
      !inProgress;
}

class ReportItem {
  const ReportItem(this.label, this.value, this.refs);
  factory ReportItem.fromJson(Map<String, dynamic> j) =>
      ReportItem(_s(j['label']), j['value'] as String?, _strings(j['refs']));
  final String label;
  final String? value;
  final List<String> refs;
}

class ReportSection {
  const ReportSection(
    this.id,
    this.title,
    this.summary,
    this.items,
    this.graphs,
  );
  factory ReportSection.fromJson(Map<String, dynamic> j) => ReportSection(
    _s(j['id']),
    _s(j['title']),
    _s(j['summary']),
    _maps(j['items']).map(ReportItem.fromJson).toList(),
    _strings(j['graphs']),
  );
  final String id;
  final String title;
  final String summary;
  final List<ReportItem> items;
  final List<String> graphs;
}

class GraphNode {
  const GraphNode(this.id, this.label, this.kind, this.detail, this.refs);
  factory GraphNode.fromJson(Map<String, dynamic> j) => GraphNode(
    _s(j['id']),
    _s(j['label']),
    _s(j['kind'], 'module'),
    j['detail'] as String?,
    _strings(j['refs']),
  );
  final String id;
  final String label;
  final String kind;
  final String? detail;
  final List<String> refs;
}

class GraphEdge {
  const GraphEdge(this.from, this.to, this.label);
  factory GraphEdge.fromJson(Map<String, dynamic> j) =>
      GraphEdge(_s(j['from']), _s(j['to']), j['label'] as String?);
  final String from;
  final String to;
  final String? label;
}

class ArchGraph {
  const ArchGraph(
    this.id,
    this.title,
    this.flow,
    this.nodes,
    this.edges,
    this.note,
    this.mermaid,
  );
  factory ArchGraph.fromJson(Map<String, dynamic> j) => ArchGraph(
    _s(j['id']),
    _s(j['title']),
    j['layout'] != 'network',
    _maps(j['nodes']).map(GraphNode.fromJson).toList(),
    _maps(j['edges']).map(GraphEdge.fromJson).toList(),
    _s(j['note']),
    _s(j['mermaid']),
  );
  final String id;
  final String title;
  final bool flow;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final String note;
  final String mermaid;
}

class Tech {
  const Tech(
    this.name,
    this.category,
    this.confirmed,
    this.purpose,
    this.evidence,
  );
  factory Tech.fromJson(Map<String, dynamic> j) => Tech(
    _s(j['name']),
    _s(j['category']),
    j['confidence'] != 'inferred',
    _s(j['purpose']),
    _strings(j['evidence']),
  );
  final String name;
  final String category;
  final bool confirmed;
  final String purpose;
  final List<String> evidence;
}

class Dependency {
  const Dependency(
    this.name,
    this.version,
    this.dev,
    this.ecosystem,
    this.manifest,
  );
  factory Dependency.fromJson(Map<String, dynamic> j) => Dependency(
    _s(j['name']),
    _s(j['version']),
    j['dev'] == true,
    _s(j['ecosystem']),
    _s(j['manifest']),
  );
  final String name;
  final String version;
  final bool dev;
  final String ecosystem;
  final String manifest;
}

class Endpoint {
  const Endpoint(this.method, this.route, this.framework, this.path, this.line);
  factory Endpoint.fromJson(Map<String, dynamic> j) => Endpoint(
    _s(j['method']),
    _s(j['route']),
    _s(j['framework']),
    _s(j['path']),
    _i(j['line']),
  );
  final String method;
  final String route;
  final String framework;
  final String path;
  final int line;
  String get ref => '$path:$line';
}

class Entity {
  const Entity(this.name, this.source, this.columns, this.path, this.line);
  factory Entity.fromJson(Map<String, dynamic> j) => Entity(
    _s(j['name']),
    _s(j['source']),
    _maps(j['columns']).map((c) => (_s(c['name']), _s(c['type']))).toList(),
    _s(j['path']),
    _i(j['line']),
  );
  final String name;
  final String source;
  final List<(String, String)> columns;
  final String path;
  final int line;
}

class Module {
  const Module(
    this.path,
    this.role,
    this.files,
    this.languages,
    this.keyFiles,
    this.imports,
    this.importedBy,
  );
  factory Module.fromJson(Map<String, dynamic> j) => Module(
    _s(j['path']),
    _s(j['role']),
    _i(j['files']),
    _strings(j['languages']),
    _strings(j['keyFiles']),
    _strings(j['imports']),
    _strings(j['importedBy']),
  );
  final String path;
  final String role;
  final int files;
  final List<String> languages;
  final List<String> keyFiles;
  final List<String> imports;
  final List<String> importedBy;
}

class TreeFile {
  const TreeFile(this.path, this.size, this.read);
  final String path;
  final int size;

  /// Whether the analysis read it (and so the app can show it).
  final bool read;
}

class Narrative {
  const Narrative(this.overview, this.howItWorks, this.learnToBuild);
  static Narrative? fromJson(Object? v) {
    if (v is! Map) return null;
    final overview = v['overview'];
    if (overview is! String || overview.isEmpty) return null;
    return Narrative(
      overview,
      _s(v['howItWorks']),
      _strings(v['learnToBuild']),
    );
  }

  final String overview;
  final String howItWorks;
  final List<String> learnToBuild;
}

/// A finished (or failed) analysis with its report.
class RepoAnalysis {
  RepoAnalysis(
    this.summary,
    Map<String, dynamic>? report,
    Object? sections,
    Object? narrative,
  ) : report = report ?? const {},
      sections = _maps(sections).map(ReportSection.fromJson).toList(),
      narrative = Narrative.fromJson(narrative);

  final AnalysisSummary summary;
  final Map<String, dynamic> report;
  final List<ReportSection> sections;
  final Narrative? narrative;

  Map<String, dynamic> get _repo =>
      (report['repo'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get stats =>
      (report['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get quality =>
      (report['quality'] as Map?)?.cast<String, dynamic>() ?? const {};

  String? get description => _repo['description'] as String?;
  int get stars => _i(_repo['stars']);
  String? get license => _repo['license'] as String?;
  String get defaultBranch => _s(_repo['defaultBranch']);

  Map<String, int> get languages => {
    for (final e in ((report['languages'] as Map?) ?? const {}).entries)
      e.key.toString(): _i(e.value),
  };

  late final List<Tech> techs = _maps(
    report['techs'],
  ).map(Tech.fromJson).toList();
  late final List<Dependency> dependencies = _maps(
    report['dependencies'],
  ).map(Dependency.fromJson).toList();
  late final List<Endpoint> endpoints = _maps(
    report['endpoints'],
  ).map(Endpoint.fromJson).toList();
  late final List<Entity> entities = _maps(
    report['entities'],
  ).map(Entity.fromJson).toList();
  late final List<Module> modules = _maps(
    report['modules'],
  ).map(Module.fromJson).toList();
  late final List<ArchGraph> graphs = _maps(
    report['graphs'],
  ).map(ArchGraph.fromJson).toList();
  late final List<Map<String, dynamic>> workflows = _maps(report['workflows']);
  late final List<Map<String, dynamic>> containers = _maps(
    report['containers'],
  );
  late final List<Map<String, dynamic>> deploy = _maps(report['deploy']);
  late final List<Map<String, dynamic>> env = _maps(report['env']);
  late final List<Map<String, dynamic>> secrets = _maps(report['secrets']);
  late final List<TreeFile> tree = _maps(report['tree'])
      .map(
        (t) => TreeFile(_s(t['p']), _i(t['s']), t['r'] == 1 || t['r'] == true),
      )
      .toList();
  bool get treeTruncated => report['treeTruncated'] == true;

  ArchGraph? graph(String id) {
    for (final g in graphs) {
      if (g.id == id) return g;
    }
    return null;
  }

  ReportSection? section(String id) {
    for (final s in sections) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// An answer from ask-repo, with the lines it rests on.
class RepoAnswer {
  const RepoAnswer(this.question, this.answer, this.citations);
  final String question;
  final String answer;
  final List<(String, int)> citations;
}

/// The branches of a repository, for choosing one before analysing.
class RepoBranches {
  const RepoBranches(
    this.fullName,
    this.defaultBranch,
    this.branches,
    this.isPrivate,
  );
  final String fullName;
  final String defaultBranch;
  final List<String> branches;
  final bool isPrivate;
}

/// A failure the page can explain: GitHub's limit, a missing repository, a
/// refused token, our own limit, or the AI being unavailable.
class RepoAnalyzerException implements Exception {
  const RepoAnalyzerException(this.message, {this.code, this.status});
  final String message;
  final String? code;
  final int? status;
  @override
  String toString() => message;
}
