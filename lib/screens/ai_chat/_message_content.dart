part of '../ai_chat_drawer.dart';

// ── Message content (text + operation cards) ──────────────────────────────────

sealed class _Seg {}
class _TextSeg  extends _Seg { final String text; _TextSeg(this.text); }
class _OpSeg    extends _Seg { final FileOperation op; _OpSeg(this.op); }

class _MessageContent extends StatelessWidget {
  final ChatMessage message;
  final Future<void> Function(FileOperation) onExecuteOp;

  const _MessageContent({required this.message, required this.onExecuteOp});

  // Static regex — compiled once for the lifetime of the app.
  static final _opTagRx = RegExp(
    r'<fl_write[^>]*>[\s\S]*?</fl_write>'
    r'|<fl_delete[^>]*/?>|<fl_rename[^>]*/?>|<fl_mkdir[^>]*/?>|<fl_terminal[^>]*/?>',
    multiLine: true,
  );

  // LRU-style segment cache: keyed by (text, ops.length).
  // Bounded to 60 entries so it doesn't grow unbounded during long sessions.
  static final _cache = <String, List<_Seg>>{};

  @override
  Widget build(BuildContext context) {
    final cacheKey = '${message.id}:${message.operations.length}';
    final segments = _cache.putIfAbsent(
      cacheKey,
      () => _splitSegments(message.text, message.operations),
    );
    if (_cache.length > 60) _cache.clear();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final seg in segments)
          if (seg is _OpSeg)
            _FileOpCard(
              op: seg.op,
              msgId: message.id,
              onExecuteOp: onExecuteOp,
            )
          else if (seg is _TextSeg && seg.text.isNotEmpty)
            _RichTextBlock(text: seg.text),
      ],
    );
  }

  static List<_Seg> _splitSegments(String text, List<FileOperation> ops) {
    final result = <_Seg>[];
    int last = 0;
    int opIdx = 0;
    for (final m in _opTagRx.allMatches(text)) {
      if (m.start > last) {
        result.add(_TextSeg(text.substring(last, m.start)));
      }
      if (opIdx < ops.length) {
        result.add(_OpSeg(ops[opIdx++]));
      }
      last = m.end;
    }
    if (last < text.length) result.add(_TextSeg(text.substring(last)));
    if (result.isEmpty) result.add(_TextSeg(text));
    return result;
  }
}
