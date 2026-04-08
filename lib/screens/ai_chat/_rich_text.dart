part of '../ai_chat_drawer.dart';

// ── Rich text block ───────────────────────────────────────────────────────────

class _RichTextBlock extends StatelessWidget {
  final String text;
  const _RichTextBlock({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final base = TextStyle(color: cs.onSurface, fontSize: 13, height: 1.5);
    final bold = base.copyWith(fontWeight: FontWeight.bold);
    final italic = base.copyWith(fontStyle: FontStyle.italic);
    final code = base.copyWith(
      fontFamily: 'monospace',
      fontSize: 12,
      color: cs.primary,
      backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
    );
    // Also render ``` code blocks inside plain text segments
    final segments = _parseCodeBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in segments)
          if (s.isCode)
            _CodeBlockWidget(code: s.text, language: s.lang)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text.rich(_buildSpans(s.text, base, bold, italic, code)),
            ),
      ],
    );
  }

  static List<_RawSeg> _parseCodeBlocks(String raw) {
    final result = <_RawSeg>[];
    final rx = RegExp(r'```(\w*)\n?([\s\S]*?)```', multiLine: true);
    int last = 0;
    for (final m in rx.allMatches(raw)) {
      if (m.start > last) result.add(_RawSeg(raw.substring(last, m.start)));
      result.add(_RawSeg((m.group(2) ?? '').trimRight(),
          isCode: true, lang: m.group(1) ?? ''));
      last = m.end;
    }
    if (last < raw.length) result.add(_RawSeg(raw.substring(last)));
    if (result.isEmpty) result.add(_RawSeg(raw));
    return result;
  }

  static TextSpan _buildSpans(String text, TextStyle base, TextStyle bold,
      TextStyle italic, TextStyle code) {
    final spans = <InlineSpan>[];
    final rx = RegExp(r'\*\*([\s\S]*?)\*\*|\*([\s\S]*?)\*|`([^`]+)`');
    int last = 0;
    for (final m in rx.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      if (m.group(1) != null) spans.add(TextSpan(text: m.group(1), style: bold));
      else if (m.group(2) != null) spans.add(TextSpan(text: m.group(2), style: italic));
      else if (m.group(3) != null) spans.add(TextSpan(text: m.group(3), style: code));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: base, children: spans);
  }
}

class _RawSeg {
  final String text;
  final bool isCode;
  final String lang;
  const _RawSeg(this.text, {this.isCode = false, this.lang = ''});
}

// ── Code block (inside rich text) ────────────────────────────────────────────

class _CodeBlockWidget extends StatelessWidget {
  final String code;
  final String language;
  const _CodeBlockWidget({required this.code, required this.language});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final bg     = isDark ? const Color(0xFF1E1E1E) : cs.surfaceContainerHighest;
    final header = isDark ? const Color(0xFF2D2D2D) : cs.surfaceContainerHigh;
    final fg     = isDark ? const Color(0xFFD4D4D4) : cs.onSurface;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
            decoration: BoxDecoration(
              color: header,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                if (language.isNotEmpty)
                  Text(language,
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                const Spacer(),
                _CopyButton(code: code),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SelectableText(
              code,
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12, color: fg, height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Copy button ───────────────────────────────────────────────────────────────

class _CopyButton extends StatefulWidget {
  final String code;
  const _CopyButton({required this.code});
  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.copy_outlined,
        size: 14,
        color: _copied ? cs.primary : cs.onSurfaceVariant,
      ),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.code));
        if (!mounted) return;
        setState(() => _copied = true);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _copied = false);
      },
      tooltip: _copied ? 'Copiado!' : 'Copiar',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }
}
