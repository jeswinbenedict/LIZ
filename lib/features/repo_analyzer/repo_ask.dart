import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../shared/widgets/liz_notice.dart';
import 'repo_code.dart';
import 'repo_models.dart';
import 'repo_service.dart';

class AskEntry {
  AskEntry(this.question, this.focus);
  final String question;
  final String? focus;
  RepoAnswer? answer;
  String? error;
  bool get loading => answer == null && error == null;
}

/// The questions asked about one analysis, shared by the Ask tab and every
/// "Explain" button elsewhere on the page.
class RepoAskController extends ChangeNotifier {
  RepoAskController(this._service, this.analysisId);
  final RepoAnalyzerService _service;
  final String analysisId;
  final entries = <AskEntry>[];

  bool get busy => entries.any((e) => e.loading);

  Future<void> ask(String question, {String? focus}) async {
    final q = question.trim();
    if (q.length < 3 || busy) return;
    final entry = AskEntry(q, focus);
    entries.add(entry);
    notifyListeners();
    try {
      entry.answer = await _service.ask(analysisId, q, focus: focus);
    } on RepoAnalyzerException catch (e) {
      entry.error = e.message;
    } catch (_) {
      entry.error = 'Something went wrong. Try again.';
    }
    notifyListeners();
  }
}

const suggestedQuestions = [
  'How was this application built?',
  'What architecture does this project follow?',
  'How does the frontend communicate with the backend?',
  'Which database is used, and how is it structured?',
  'How does authentication work?',
  'Explain the complete application workflow.',
  'How can I run this project locally?',
  'How can I deploy this project?',
  'What technologies should I learn to build something similar?',
];

class AskPanel extends StatefulWidget {
  const AskPanel({super.key, required this.controller});
  final RepoAskController controller;

  @override
  State<AskPanel> createState() => _AskPanelState();
}

class _AskPanelState extends State<AskPanel> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final q = (text ?? _field.text).trim();
    if (q.length < 3) return;
    _field.clear();
    widget.controller.ask(q);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Answers come from this repository’s own files, with the lines they rest on. '
              'Tap a reference to open the file there.',
              style: LizText.callout.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in suggestedQuestions)
                  ActionChip(
                    label: Text(q),
                    onPressed: c.busy ? null : () => _send(q),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            for (final e in c.entries.reversed) ...[
              _Answer(entry: e, analysisId: c.analysisId),
              const SizedBox(height: 12),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _field,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 600,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      labelText: 'Ask about this repository',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: c.busy ? null : _send,
                    child: const Text('Ask'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.entry, required this.analysisId});
  final AskEntry entry;
  final String analysisId;

  @override
  Widget build(BuildContext context) {
    final p = context.liz;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: p.surface,
        shape: LizRadius.shape(
          LizRadius.md,
          side: BorderSide(color: p.hairline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.question,
              style: LizText.headline.copyWith(color: p.textPrimary),
            ),
            if (entry.focus != null) ...[
              const SizedBox(height: 4),
              Text(
                'About ${entry.focus}',
                style: LizText.label.copyWith(color: p.textSecondary),
              ),
            ],
            const SizedBox(height: 10),
            if (entry.loading)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Reading the repository…',
                    style: LizText.callout.copyWith(color: p.textSecondary),
                  ),
                ],
              )
            else if (entry.error != null)
              LizNotice(
                text: entry.error!,
                color: p.caution,
                icon: Icons.info_outline,
              )
            else ...[
              SelectableText.rich(
                TextSpan(children: _spans(entry.answer!.answer, p)),
                style: LizText.body.copyWith(
                  color: p.textPrimary,
                  height: 1.55,
                ),
              ),
              if (entry.answer!.citations.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Sources',
                  style: LizText.caption.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: 6),
                RefChips(
                  analysisId: analysisId,
                  refs: [
                    for (final (path, line) in entry.answer!.citations)
                      '$path:$line',
                  ],
                  max: 12,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// The answer with **bold** and `code` as the model writes them, and its
  /// [path:line] citations quiet so the prose reads first.
  List<InlineSpan> _spans(String text, LizPalette p) {
    final out = <InlineSpan>[];
    final re = RegExp(r'\*\*([^*]+)\*\*|`([^`]+)`|\[([^\]\s]+:\d+(?:-\d+)?)\]');
    var at = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > at) out.add(TextSpan(text: text.substring(at, m.start)));
      if (m.group(1) != null) {
        out.add(
          TextSpan(
            text: m.group(1),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      } else if (m.group(2) != null) {
        out.add(
          TextSpan(
            text: m.group(2),
            style: LizText.mono.copyWith(fontSize: 13.5, color: p.textPrimary),
          ),
        );
      } else {
        out.add(
          TextSpan(
            text: '[${m.group(3)}]',
            style: LizText.mono.copyWith(
              fontSize: 11.5,
              color: p.textSecondary,
            ),
          ),
        );
      }
      at = m.end;
    }
    if (at < text.length) out.add(TextSpan(text: text.substring(at)));
    return out;
  }
}
