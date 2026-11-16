import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import 'repo_models.dart';

/// The Repository Analyzer's backend: the analyze-repo and ask-repo functions
/// and the person's own rows (row-level security keeps everyone else's out).
abstract class RepoAnalyzerService {
  /// The branches of a repository, so one can be chosen.
  Future<RepoBranches> branches(String url, {String? token});

  /// Starts an analysis and returns its id (or an earlier one of the same
  /// public commit, copied).
  Future<String> start(String url, {String? ref, String? token});

  Future<List<AnalysisSummary>> mine();
  Future<RepoAnalysis> get(String id);
  Future<String?> fileContent(String id, String path);
  Future<RepoAnswer> ask(String id, String question, {String? focus});
  Future<void> delete(String id);
}

class SupabaseRepoAnalyzerService implements RepoAnalyzerService {
  SupabaseRepoAnalyzerService(this._client);
  final SupabaseClient _client;

  Future<Map<String, dynamic>> _invoke(
    String fn,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await _client.functions.invoke(fn, body: body);
      final data = res.data;
      if (data is Map && data['data'] is Map) {
        return (data['data'] as Map).cast<String, dynamic>();
      }
      throw RepoAnalyzerException(
        data is Map && data['error'] is String
            ? data['error'] as String
            : 'Something went wrong.',
      );
    } on FunctionException catch (e) {
      final d = e.details;
      final message = d is Map && d['error'] is String
          ? d['error'] as String
          : switch (e.status) {
              429 => 'Too many requests. Wait a few minutes and try again.',
              401 => 'Sign in again to continue.',
              _ => 'Something went wrong. Try again.',
            };
      throw RepoAnalyzerException(
        message,
        code: d is Map ? d['code'] as String? : null,
        status: e.status,
      );
    }
  }

  @override
  Future<RepoBranches> branches(String url, {String? token}) async {
    final d = await _invoke('analyze-repo', {
      'url': url,
      'action': 'branches',
      if (token != null && token.isNotEmpty) 'token': token,
    });
    return RepoBranches(
      d['fullName'].toString(),
      d['defaultBranch'].toString(),
      (d['branches'] as List? ?? const []).map((e) => e.toString()).toList(),
      d['private'] == true,
    );
  }

  @override
  Future<String> start(String url, {String? ref, String? token}) async {
    final d = await _invoke('analyze-repo', {
      'url': url,
      if (ref != null && ref.isNotEmpty) 'ref': ref,
      if (token != null && token.isNotEmpty) 'token': token,
    });
    return d['id'].toString();
  }

  @override
  Future<List<AnalysisSummary>> mine() async {
    final rows = await _client
        .from('repo_analyses')
        .select(AnalysisSummary.columns)
        .order('created_at', ascending: false)
        .limit(50);
    return rows.map(AnalysisSummary.fromJson).toList();
  }

  @override
  Future<RepoAnalysis> get(String id) async {
    final row = await _client
        .from('repo_analyses')
        .select('${AnalysisSummary.columns}, report, sections, narrative')
        .eq('id', id)
        .maybeSingle();
    if (row == null) {
      throw const RepoAnalyzerException(
        'This analysis does not exist, or it is not yours.',
        status: 404,
      );
    }
    return RepoAnalysis(
      AnalysisSummary.fromJson(row),
      (row['report'] as Map?)?.cast<String, dynamic>(),
      row['sections'],
      row['narrative'],
    );
  }

  @override
  Future<String?> fileContent(String id, String path) async {
    final row = await _client
        .from('repo_analysis_files')
        .select('content')
        .eq('analysis_id', id)
        .eq('path', path)
        .maybeSingle();
    return row?['content'] as String?;
  }

  @override
  Future<RepoAnswer> ask(String id, String question, {String? focus}) async {
    final d = await _invoke('ask-repo', {
      'analysis_id': id,
      'question': question,
      'focus': ?focus,
    });
    return RepoAnswer(question, d['answer'].toString(), [
      for (final c in (d['citations'] as List? ?? const []).whereType<Map>())
        (c['path'].toString(), (c['line'] as num?)?.toInt() ?? 1),
    ]);
  }

  @override
  Future<void> delete(String id) =>
      _client.from('repo_analyses').delete().eq('id', id);
}

/// Null in demo mode: the analyzer reads real repositories and keeps their
/// reports, which needs the live backend. The page says so instead of showing
/// made-up analysis.
final repoAnalyzerServiceProvider = Provider<RepoAnalyzerService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseRepoAnalyzerService(client);
});
