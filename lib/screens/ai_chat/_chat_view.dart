part of '../ai_chat_drawer.dart';

// ── Chat view ─────────────────────────────────────────────────────────────────

class _ChatView extends StatefulWidget {
  final ScrollController scrollCtrl;
  final TextEditingController inputCtrl;
  final FocusNode focusNode;
  final Future<void> Function() onSend;
  final VoidCallback onScrollToBottom;
  final VoidCallback onAttach;
  final Future<void> Function(FileOperation) onExecuteOp;
  final Future<void> Function(ChatMessage, String, bool) onResend;
  final bool isBuildingCtx;

  const _ChatView({
    super.key,
    required this.scrollCtrl,
    required this.inputCtrl,
    required this.focusNode,
    required this.onSend,
    required this.onScrollToBottom,
    required this.onAttach,
    required this.onExecuteOp,
    required this.onResend,
    required this.isBuildingCtx,
  });

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  int _prevMsgCount = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Select only the fields this widget needs — prevents rebuilds caused by
    // unrelated ChatProvider changes (selectedAgent, snapshots, contextPaths).
    final msgs = context.select<ChatProvider, List<ChatMessage>>(
      (c) => c.activeConversation?.messages ?? const [],
    );
    final isStreaming = context.select<ChatProvider, bool>(
      (c) => c.isStreaming,
    );
    final selectedAgent = context.select<ChatProvider, AiAgent>(
      (c) => c.selectedAgent,
    );

    if (msgs.length != _prevMsgCount || isStreaming) {
      _prevMsgCount = msgs.length;
      widget.onScrollToBottom();
    }

    return Column(
      children: [
        _AgentModelBar(),
        Divider(height: 1, thickness: 1, color: cs.outlineVariant),
        Expanded(
          child: msgs.isEmpty
              ? _EmptyState()
              : ListView.builder(
                  controller: widget.scrollCtrl,
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  itemCount: msgs.length,
                  // addAutomaticKeepAlives: false avoids wrapping every item in
                  // a KeepAlive widget — saves memory when list is long.
                  addAutomaticKeepAlives: false,
                  itemBuilder: (ctx, i) {
                    final msg = msgs[i];
                    return msg.isUser
                        ? _UserMessage(
                            message: msg,
                            onResend: widget.onResend,
                          )
                        : _AiMessage(
                            message: msg,
                            agent: selectedAgent,
                            onExecuteOp: widget.onExecuteOp,
                          );
                  },
                ),
        ),
        _InputArea(
          ctrl: widget.inputCtrl,
          focusNode: widget.focusNode,
          onSend: widget.onSend,
          onAttach: widget.onAttach,
          isBuildingCtx: widget.isBuildingCtx,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final focus = context.select<ChatProvider, String>(
      (c) => c.selectedAgent.focus,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                  color: cs.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.auto_awesome_rounded,
                  size: 30, color: cs.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text('Como posso ajudar?',
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              '$focus\n\nConheço todos os arquivos do projeto automaticamente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
