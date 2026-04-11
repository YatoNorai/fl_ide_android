import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/ai_agent.dart';
import 'ai_provider.dart';

part 'chat_models.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

class ChatProvider extends ChangeNotifier {
  final List<ChatConversation> _conversations = [];
  ChatConversation? _activeConversation;
  AiAgent _selectedAgent = kDefaultAgents.first;
  bool _isStreaming = false;
  int _userMessageCount = 0;
  bool _autoAccept = false;

  final Set<String> _contextPaths = {};
  final List<ProjectSnapshot> _snapshots = [];

  // Commands the user has chosen to always accept without confirmation.
  // Stored as the exact command string (trimmed).
  final Set<String> _alwaysAcceptCmds = {};

  List<ChatConversation> get conversations => List.unmodifiable(_conversations);
  ChatConversation? get activeConversation => _activeConversation;
  AiAgent get selectedAgent => _selectedAgent;
  bool get isStreaming => _isStreaming;
  Set<String> get contextPaths => Set.unmodifiable(_contextPaths);
  List<ProjectSnapshot> get snapshots => List.unmodifiable(_snapshots);
  int get userMessageCount => _userMessageCount;
  bool get autoAccept => _autoAccept;
  Set<String> get alwaysAcceptCmds => Set.unmodifiable(_alwaysAcceptCmds);

  /// True when the last AI message has terminal operations still pending approval.
  bool get hasPendingTerminalOps {
    final conv = _activeConversation;
    if (conv == null || conv.messages.isEmpty) return false;
    final lastAi = conv.messages.lastWhere(
      (m) => !m.isUser,
      orElse: () => const ChatMessage(id: '', isUser: true, text: ''),
    );
    if (lastAi.id.isEmpty) return false;
    return lastAi.operations.any(
      (op) => op.type == FileOpType.terminal && op.status == FileOpStatus.pending,
    );
  }

  // ── Context ────────────────────────────────────────────────────────────────

  void toggleContextPath(String path) {
    if (_contextPaths.contains(path)) {
      _contextPaths.remove(path);
    } else {
      _contextPaths.add(path);
    }
    notifyListeners();
  }

  void clearContext() {
    _contextPaths.clear();
    notifyListeners();
  }

  // ── Auto-accept ────────────────────────────────────────────────────────────

  void setAutoAccept(bool value) {
    _autoAccept = value;
    notifyListeners();
  }

  // ── Always-accept commands ─────────────────────────────────────────────────

  bool isAlwaysAccepted(String cmd) => _alwaysAcceptCmds.contains(cmd.trim());

  void addAlwaysAcceptCmd(String cmd) {
    _alwaysAcceptCmds.add(cmd.trim());
    notifyListeners();
    saveProject();
  }

  void removeAlwaysAcceptCmd(String cmd) {
    _alwaysAcceptCmds.remove(cmd.trim());
    notifyListeners();
    saveProject();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  String? _projectPath;

  Future<void> loadProject(String projectPath) async {
    _projectPath = projectPath;
    try {
      final file = File('$projectPath/.fl_ide/chat.json');
      if (!file.existsSync()) return;
      final raw  = await file.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _conversations.clear();
      _snapshots.clear();
      for (final c in (data['conversations'] as List? ?? [])) {
        _conversations.add(
            ChatConversation.fromJson(c as Map<String, dynamic>));
      }
      for (final s in (data['snapshots'] as List? ?? [])) {
        _snapshots.add(ProjectSnapshot.fromJson(s as Map<String, dynamic>));
      }
      _userMessageCount = (data['userMessageCount'] as int?) ?? 0;
      _alwaysAcceptCmds
        ..clear()
        ..addAll(((data['alwaysAcceptCmds'] as List?) ?? []).cast<String>());
      // Re-open the most recent conversation
      if (_conversations.isNotEmpty) {
        _activeConversation = _conversations.first;
        _selectedAgent = _activeConversation!.agent;
      }
    } catch (e) {
      debugPrint('[ChatProvider] load error: $e');
    }
    notifyListeners();
  }

  Future<void> saveProject() async {
    if (_projectPath == null) return;
    try {
      final dir = Directory('$_projectPath/.fl_ide');
      if (!dir.existsSync()) await dir.create(recursive: true);
      final file = File('${dir.path}/chat.json');
      final data = {
        'userMessageCount': _userMessageCount,
        'conversations': _conversations.map((c) => c.toJson()).toList(),
        'snapshots': _snapshots.map((s) => s.toJson()).toList(),
        'alwaysAcceptCmds': _alwaysAcceptCmds.toList(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('[ChatProvider] save error: $e');
    }
  }

  // ── Snapshots ──────────────────────────────────────────────────────────────

  void addSnapshot(ProjectSnapshot snapshot) {
    _snapshots.insert(0, snapshot);
    saveProject();
    notifyListeners();
  }

  // ── Agent ──────────────────────────────────────────────────────────────────

  void selectAgent(AiAgent agent) {
    _selectedAgent = agent;
    notifyListeners();
  }

  void newConversation() {
    _activeConversation = null;
    notifyListeners();
  }

  void openConversation(ChatConversation conv) {
    _activeConversation = conv;
    _selectedAgent = conv.agent;
    notifyListeners();
  }

  // ── Operation approval ─────────────────────────────────────────────────────

  void setOperationStatus(String msgId, String opId, FileOpStatus status) {
    if (_activeConversation == null) return;
    final msgs = List<ChatMessage>.from(_activeConversation!.messages);
    final mi = msgs.indexWhere((m) => m.id == msgId);
    if (mi < 0) return;
    final ops = List<FileOperation>.from(msgs[mi].operations);
    final oi = ops.indexWhere((o) => o.id == opId);
    if (oi < 0) return;
    ops[oi] = ops[oi].copyWith(status: status);
    msgs[mi] = msgs[mi].copyWith(operations: ops);
    _setMessages(msgs);
    notifyListeners();
    saveProject();
  }

  void setOperationOutput(String msgId, String opId, String output) {
    if (_activeConversation == null) return;
    final msgs = List<ChatMessage>.from(_activeConversation!.messages);
    final mi = msgs.indexWhere((m) => m.id == msgId);
    if (mi < 0) return;
    final ops = List<FileOperation>.from(msgs[mi].operations);
    final oi = ops.indexWhere((o) => o.id == opId);
    if (oi < 0) return;
    ops[oi] = ops[oi].copyWith(
      status: FileOpStatus.accepted,
      commandOutput: output,
    );
    msgs[mi] = msgs[mi].copyWith(operations: ops);
    _setMessages(msgs);
    notifyListeners();
    saveProject();
  }

  void acceptAllOperations(String msgId) {
    if (_activeConversation == null) return;
    final msgs = List<ChatMessage>.from(_activeConversation!.messages);
    final mi = msgs.indexWhere((m) => m.id == msgId);
    if (mi < 0) return;
    final ops = msgs[mi]
        .operations
        .map((o) => o.status == FileOpStatus.pending
            ? o.copyWith(status: FileOpStatus.accepted)
            : o)
        .toList();
    msgs[mi] = msgs[mi].copyWith(operations: ops);
    _setMessages(msgs);
    notifyListeners();
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> sendMessage(
    String text,
    AiProvider ai, {
    AiAgent? agentOverride,
  }) async {
    if (text.trim().isEmpty || _isStreaming) return;

    _userMessageCount++;

    if (_activeConversation == null) {
      final conv = ChatConversation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        agent: _selectedAgent,
      );
      _conversations.insert(0, conv);
      _activeConversation = conv;
    }

    _addMessage(ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_u',
      isUser: true,
      text: text.trim(),
    ));

    final aiId = '${DateTime.now().millisecondsSinceEpoch}_a';
    _addMessage(ChatMessage(id: aiId, isUser: false, text: '', isThinking: true));
    _isStreaming = true;
    notifyListeners();

    final history = _activeConversation!.messages
        .where((m) => !m.isThinking && m.id != aiId)
        .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text})
        .toList();

    final effectiveAgent = agentOverride ?? _selectedAgent;

    if (!ai.geminiKey.isNotEmpty && !ai.claudeKey.isNotEmpty &&
        !ai.gptKey.isNotEmpty && !ai.deepSeekKey.isNotEmpty) {
      _replaceMessage(
          aiId,
          'Nenhuma chave de API configurada.\nAcesse Configurações → IA para adicionar uma chave.',
          false);
      _isStreaming = false;
      notifyListeners();
      return;
    }

    try {
      final stream = _buildStream(ai, effectiveAgent, history);
      final buffer = StringBuffer();
      var _chunk = 0;
      await for (final chunk in stream) {
        if (chunk.isNotEmpty) {
          buffer.write(chunk);
          // Notify every 6 chunks to avoid rebuilding the UI on every token.
          // The final notify below always flushes the last partial batch.
          if (++_chunk % 6 == 0) {
            _replaceMessage(aiId, buffer.toString(), true);
            notifyListeners();
          }
        }
      }

      final finalText = buffer.isEmpty ? '(resposta vazia)' : buffer.toString();
      final ops = _parseOperations(finalText);
      _replaceMessageWithOps(aiId, finalText, false, ops);
    } catch (e) {
      _replaceMessage(aiId, 'Erro ao contatar a IA: $e', false);
    }

    _isStreaming = false;
    notifyListeners();
    saveProject();
  }

  // ── Orchestrated send (Architect → Engineer) ──────────────────────────────

  /// Two-phase orchestrated send:
  /// 1. Streams with [planAgent] system prompt → produces a plan message.
  /// 2. Streams with [implAgent] system prompt + the plan as context → produces
  ///    implementation message with file operations.
  Future<void> sendOrchestratedMessage(
    String text,
    AiProvider ai,
    AiAgent planAgent,
    AiAgent implAgent,
  ) async {
    if (text.trim().isEmpty || _isStreaming) return;

    _userMessageCount++;

    if (_activeConversation == null) {
      final conv = ChatConversation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        agent: _selectedAgent,
      );
      _conversations.insert(0, conv);
      _activeConversation = conv;
    }

    _addMessage(ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}_u',
      isUser: true,
      text: text.trim(),
    ));

    // ── Phase 1: Planning (Architect) ────────────────────────────────────────
    final planId = '${DateTime.now().millisecondsSinceEpoch}_plan';
    _addMessage(ChatMessage(
      id: planId,
      isUser: false,
      text: '',
      isThinking: true,
      subAgentId: planAgent.id,
      subAgentLabel: planAgent.name,
      subAgentColor: planAgent.colorValue,
    ));
    _isStreaming = true;
    notifyListeners();

    String planText = '';
    final historyForPlan = _activeConversation!.messages
        .where((m) => !m.isThinking && m.id != planId)
        .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text})
        .toList();

    try {
      final planStream = _buildStream(ai, planAgent, historyForPlan);
      final planBuf = StringBuffer();
      var _planChunk = 0;
      await for (final chunk in planStream) {
        if (chunk.isNotEmpty) {
          planBuf.write(chunk);
          if (++_planChunk % 6 == 0) {
            _replaceMessageSub(planId, planBuf.toString(), true,
                planAgent.id, planAgent.name, planAgent.colorValue);
            notifyListeners();
          }
        }
      }
      planText = planBuf.isEmpty ? '(sem plano)' : planBuf.toString();
      _replaceMessageSub(planId, planText, false,
          planAgent.id, planAgent.name, planAgent.colorValue);
    } catch (e) {
      _replaceMessage(planId, 'Erro na fase de planejamento: $e', false);
      _isStreaming = false;
      notifyListeners();
      saveProject();
      return;
    }

    notifyListeners();

    // ── Phase 2: Implementation (Engineer) ──────────────────────────────────
    final implId = '${DateTime.now().millisecondsSinceEpoch}_impl';

    // Build engineer agent with the plan injected into its instructions
    final implWithPlan = implAgent.copyWith(
      instructions:
          '${implAgent.instructions}\n\n'
          '## Plano recebido do Arquiteto\n$planText\n\n'
          'Implemente o plano acima agora. Use as tags de operação de arquivo.',
    );

    _addMessage(ChatMessage(
      id: implId,
      isUser: false,
      text: '',
      isThinking: true,
      subAgentId: implAgent.id,
      subAgentLabel: implAgent.name,
      subAgentColor: implAgent.colorValue,
    ));
    notifyListeners();

    final historyForImpl = _activeConversation!.messages
        .where((m) => !m.isThinking && m.id != implId)
        .map((m) => {
              'role': m.isUser ? 'user' : 'assistant',
              'content': m.text,
            })
        .toList();

    try {
      final implStream = _buildStream(ai, implWithPlan, historyForImpl);
      final implBuf = StringBuffer();
      var _implChunk = 0;
      await for (final chunk in implStream) {
        if (chunk.isNotEmpty) {
          implBuf.write(chunk);
          if (++_implChunk % 6 == 0) {
            _replaceMessageSub(implId, implBuf.toString(), true,
                implAgent.id, implAgent.name, implAgent.colorValue);
            notifyListeners();
          }
        }
      }
      final finalImpl = implBuf.isEmpty ? '(sem implementação)' : implBuf.toString();
      final ops = _parseOperations(finalImpl);
      _replaceMessageSubWithOps(implId, finalImpl, false, ops,
          implAgent.id, implAgent.name, implAgent.colorValue);
    } catch (e) {
      _replaceMessage(implId, 'Erro na fase de implementação: $e', false);
    }

    _isStreaming = false;
    notifyListeners();
    saveProject();
  }

  /// Picks the correct streaming function based on the user's active provider
  /// selection, falling back to the first configured key.
  Stream<String> _buildStream(
    AiProvider ai,
    AiAgent agent,
    List<Map<String, String>> history,
  ) {
    switch (ai.effectiveProvider) {
      case 'gemini':
        if (ai.geminiKey.isNotEmpty)
          return _streamGemini(ai.geminiKey, ai.geminiModel, agent, history);
      case 'claude':
        if (ai.claudeKey.isNotEmpty)
          return _streamClaude(ai.claudeKey, ai.claudeModel, agent, history);
      case 'gpt':
        if (ai.gptKey.isNotEmpty)
          return _streamGpt(ai.gptKey, ai.gptModel, agent, history);
      case 'deepseek':
        if (ai.deepSeekKey.isNotEmpty)
          return _streamDeepSeek(ai.deepSeekKey, ai.deepSeekModel, agent, history);
    }
    return Stream.value('Nenhuma chave de API configurada.');
  }

  // ── Edit & resend ─────────────────────────────────────────────────────────

  Future<void> editAndResend(
    String msgId,
    String newText,
    AiProvider ai, {
    AiAgent? agentOverride,
  }) async {
    if (_isStreaming) return;

    // Update the message text and delete everything after it
    final msgs = List<ChatMessage>.from(_activeConversation!.messages);
    final idx  = msgs.indexWhere((m) => m.id == msgId);
    if (idx < 0) return;
    msgs[idx] = msgs[idx].copyWith(text: newText);
    if (idx + 1 < msgs.length) msgs.removeRange(idx + 1, msgs.length);
    _setMessages(msgs);
    notifyListeners();

    // Add AI thinking placeholder and stream
    final aiId = '${DateTime.now().millisecondsSinceEpoch}_a';
    _addMessage(ChatMessage(id: aiId, isUser: false, text: '', isThinking: true));
    _isStreaming = true;
    notifyListeners();

    final history = _activeConversation!.messages
        .where((m) => !m.isThinking && m.id != aiId)
        .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text})
        .toList();

    final effectiveAgent = agentOverride ?? _selectedAgent;

    try {
      final stream = _buildStream(ai, effectiveAgent, history);
      final buffer = StringBuffer();
      var _chunk = 0;
      await for (final chunk in stream) {
        if (chunk.isNotEmpty) {
          buffer.write(chunk);
          if (++_chunk % 6 == 0) {
            _replaceMessage(aiId, buffer.toString(), true);
            notifyListeners();
          }
        }
      }
      final finalText = buffer.isEmpty ? '(resposta vazia)' : buffer.toString();
      final ops = _parseOperations(finalText);
      _replaceMessageWithOps(aiId, finalText, false, ops);
    } catch (e) {
      _replaceMessage(aiId, 'Erro ao contatar a IA: $e', false);
    }

    _isStreaming = false;
    notifyListeners();
    saveProject();
  }

  // ── Operation parsing ──────────────────────────────────────────────────────

  // Static regex — compiled once at class load, not on every AI response.
  static final _writeRx  = RegExp(
    r'<fl_write\s+path="([^"]+)"(?:\s+lang="([^"]*)")?>([\s\S]*?)</fl_write>',
    multiLine: true,
  );
  static final _deleteRx = RegExp(r'<fl_delete\s+path="([^"]+)"\s*/?>');
  static final _renameRx = RegExp(r'<fl_rename\s+from="([^"]+)"\s+to="([^"]+)"\s*/?>');
  static final _mkdirRx  = RegExp(r'<fl_mkdir\s+path="([^"]+)"\s*/?>');
  static final _termRx   = RegExp(r'<fl_terminal\s+cmd="([^"]+)"\s*/?>');

  static List<FileOperation> _parseOperations(String text) {
    final ops = <FileOperation>[];
    int idx = 0;
    final ts  = DateTime.now().millisecondsSinceEpoch;

    for (final m in _writeRx.allMatches(text)) {
      ops.add(FileOperation(
        id: '${ts}_${idx++}',
        type: FileOpType.write,
        path: m.group(1)!.trim(),
        language: (m.group(2) ?? '').trim(),
        content: (m.group(3) ?? '').trim(),
      ));
    }
    for (final m in _deleteRx.allMatches(text)) {
      ops.add(FileOperation(
        id: '${ts}_${idx++}',
        type: FileOpType.delete,
        path: m.group(1)!.trim(),
      ));
    }
    for (final m in _renameRx.allMatches(text)) {
      ops.add(FileOperation(
        id: '${ts}_${idx++}',
        type: FileOpType.rename,
        path: m.group(1)!.trim(),
        newPath: m.group(2)!.trim(),
      ));
    }
    for (final m in _mkdirRx.allMatches(text)) {
      ops.add(FileOperation(
        id: '${ts}_${idx++}',
        type: FileOpType.mkdir,
        path: m.group(1)!.trim(),
      ));
    }
    for (final m in _termRx.allMatches(text)) {
      ops.add(FileOperation(
        id: '${ts}_${idx++}',
        type: FileOpType.terminal,
        path: '',
        command: m.group(1)!.trim(),
      ));
    }
    return ops;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _extractApiError(int status, String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final msg = (json['error'] as Map?)?['message'] as String?;
      if (msg != null && msg.isNotEmpty) return 'Erro $status: $msg';
    } catch (_) {}
    final preview = body.length > 300 ? '${body.substring(0, 300)}…' : body;
    return 'Erro $status: $preview';
  }

  void _addMessage(ChatMessage msg) {
    final msgs = List<ChatMessage>.from(_activeConversation!.messages)..add(msg);
    _setMessages(msgs);
  }

  void _replaceMessage(String id, String text, bool isThinking) {
    final msgs = List<ChatMessage>.from(_activeConversation!.messages);
    final idx = msgs.indexWhere((m) => m.id == id);
    if (idx >= 0) msgs[idx] = msgs[idx].copyWith(text: text, isThinking: isThinking);
    _setMessages(msgs);
  }

  void _replaceMessageWithOps(
      String id, String text, bool isThinking, List<FileOperation> operations) {
    final msgs = List<ChatMessage>.from(_activeConversation!.messages);
    final idx = msgs.indexWhere((m) => m.id == id);
    if (idx >= 0) {
      msgs[idx] = msgs[idx].copyWith(
          text: text, isThinking: isThinking, operations: operations);
    }
    _setMessages(msgs);
  }

  void _replaceMessageSub(
      String id, String text, bool isThinking,
      String subAgentId, String subAgentLabel, int subAgentColor) {
    final msgs = List<ChatMessage>.from(_activeConversation!.messages);
    final idx = msgs.indexWhere((m) => m.id == id);
    if (idx >= 0) {
      msgs[idx] = msgs[idx].copyWith(
        text: text,
        isThinking: isThinking,
        subAgentId: subAgentId,
        subAgentLabel: subAgentLabel,
        subAgentColor: subAgentColor,
      );
    }
    _setMessages(msgs);
  }

  void _replaceMessageSubWithOps(
      String id, String text, bool isThinking, List<FileOperation> operations,
      String subAgentId, String subAgentLabel, int subAgentColor) {
    final msgs = List<ChatMessage>.from(_activeConversation!.messages);
    final idx = msgs.indexWhere((m) => m.id == id);
    if (idx >= 0) {
      msgs[idx] = msgs[idx].copyWith(
        text: text,
        isThinking: isThinking,
        operations: operations,
        subAgentId: subAgentId,
        subAgentLabel: subAgentLabel,
        subAgentColor: subAgentColor,
      );
    }
    _setMessages(msgs);
  }

  void _setMessages(List<ChatMessage> msgs) {
    final updated = _activeConversation!.copyWith(messages: msgs);
    _activeConversation = updated;
    final idx = _conversations.indexWhere((c) => c.id == updated.id);
    if (idx >= 0) _conversations[idx] = updated;
  }

  // ── Gemini ─────────────────────────────────────────────────────────────────

  Stream<String> _streamGemini(
    String key,
    String model,
    AiAgent agent,
    List<Map<String, String>> history,
  ) async* {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent?alt=sse&key=$key',
    );
    final contents = history
        .map((m) => {
              'role': m['role'] == 'assistant' ? 'model' : 'user',
              'parts': [
                {'text': m['content']}
              ],
            })
        .toList();
    final body = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': agent.instructions}
        ]
      },
      'contents': contents,
      'generationConfig': {'temperature': 0.7},
    });
    final client = http.Client();
    try {
      final req = http.Request('POST', url)
        ..headers['Content-Type'] = 'application/json'
        ..body = body;
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        final body = await resp.stream.bytesToString();
        yield _extractApiError(resp.statusCode, body);
        return;
      }
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') break;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final candidates = json['candidates'] as List?;
            if (candidates != null && candidates.isNotEmpty) {
              final parts =
                  (candidates[0] as Map?)?['content']?['parts'] as List?;
              if (parts != null && parts.isNotEmpty) {
                yield (parts[0] as Map?)?['text'] as String? ?? '';
              }
            }
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  // ── Claude ─────────────────────────────────────────────────────────────────

  Stream<String> _streamClaude(
    String key,
    String model,
    AiAgent agent,
    List<Map<String, String>> history,
  ) async* {
    final url = Uri.parse('https://api.anthropic.com/v1/messages');
    final body = jsonEncode({
      'model': model,
      'max_tokens': 8096,
      'system': agent.instructions,
      'messages':
          history.map((m) => {'role': m['role'], 'content': m['content']}).toList(),
      'stream': true,
    });
    final client = http.Client();
    try {
      final req = http.Request('POST', url)
        ..headers['x-api-key'] = key
        ..headers['anthropic-version'] = '2023-06-01'
        ..headers['Content-Type'] = 'application/json'
        ..body = body;
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        final body = await resp.stream.bytesToString();
        yield _extractApiError(resp.statusCode, body);
        return;
      }
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            if (json['type'] == 'content_block_delta') {
              yield (json['delta'] as Map?)?['text'] as String? ?? '';
            }
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }

  // ── OpenAI / DeepSeek (compatible) ────────────────────────────────────────

  Stream<String> _streamGpt(
          String key, String model, AiAgent agent, List<Map<String, String>> history) =>
      _streamOpenAiCompat(
        key: key,
        model: model,
        agent: agent,
        history: history,
        baseUrl: 'https://api.openai.com/v1/chat/completions',
      );

  Stream<String> _streamDeepSeek(
          String key, String model, AiAgent agent, List<Map<String, String>> history) =>
      _streamOpenAiCompat(
        key: key,
        model: model,
        agent: agent,
        history: history,
        baseUrl: 'https://api.deepseek.com/v1/chat/completions',
      );

  Stream<String> _streamOpenAiCompat({
    required String key,
    required String model,
    required AiAgent agent,
    required List<Map<String, String>> history,
    required String baseUrl,
  }) async* {
    final url = Uri.parse(baseUrl);
    final messages = [
      {'role': 'system', 'content': agent.instructions},
      ...history.map((m) => {'role': m['role']!, 'content': m['content']!}),
    ];
    final body = jsonEncode({'model': model, 'messages': messages, 'stream': true});
    final client = http.Client();
    try {
      final req = http.Request('POST', url)
        ..headers['Authorization'] = 'Bearer $key'
        ..headers['Content-Type'] = 'application/json'
        ..body = body;
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        final body = await resp.stream.bytesToString();
        yield _extractApiError(resp.statusCode, body);
        return;
      }
      await for (final line in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data == '[DONE]') break;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              yield (choices[0] as Map?)?['delta']?['content'] as String? ?? '';
            }
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }
}

