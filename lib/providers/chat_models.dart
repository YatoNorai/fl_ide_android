part of 'chat_provider.dart';

// ── File operation models ──────────────────────────────────────────────────────

enum FileOpType { write, delete, rename, mkdir, terminal }
enum FileOpStatus { pending, accepted, rejected }

class FileOperation {
  final String id;
  final FileOpType type;
  final String path;
  final String? newPath;
  final String? content;
  final String? language;
  final FileOpStatus status;
  /// For [FileOpType.terminal]: the shell command to run.
  final String? command;
  /// For [FileOpType.terminal]: stdout+stderr output after execution.
  final String? commandOutput;

  const FileOperation({
    required this.id,
    required this.type,
    required this.path,
    this.newPath,
    this.content,
    this.language,
    this.status = FileOpStatus.pending,
    this.command,
    this.commandOutput,
  });

  FileOperation copyWith({
    FileOpStatus? status,
    String? commandOutput,
  }) => FileOperation(
        id: id,
        type: type,
        path: path,
        newPath: newPath,
        content: content,
        language: language,
        status: status ?? this.status,
        command: command,
        commandOutput: commandOutput ?? this.commandOutput,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'path': path,
        if (newPath != null) 'newPath': newPath,
        if (content != null) 'content': content,
        if (language != null) 'language': language,
        'status': status.name,
        if (command != null) 'command': command,
        if (commandOutput != null) 'commandOutput': commandOutput,
      };

  factory FileOperation.fromJson(Map<String, dynamic> j) => FileOperation(
        id: j['id'] as String,
        type: FileOpType.values.byName(j['type'] as String),
        path: j['path'] as String,
        newPath: j['newPath'] as String?,
        content: j['content'] as String?,
        language: j['language'] as String?,
        status: FileOpStatus.values.byName(
            (j['status'] as String?) ?? 'pending'),
        command: j['command'] as String?,
        commandOutput: j['commandOutput'] as String?,
      );

  String get opLabel {
    switch (type) {
      case FileOpType.write:    return 'Criar / editar arquivo';
      case FileOpType.delete:   return 'Excluir';
      case FileOpType.rename:   return 'Renomear / mover';
      case FileOpType.mkdir:    return 'Criar pasta';
      case FileOpType.terminal: return 'Executar comando';
    }
  }
}

// ── Snapshot model ─────────────────────────────────────────────────────────────

class ProjectSnapshot {
  final String id;
  final int userMessageIndex;
  final String messagePreview;
  final DateTime timestamp;
  /// path → content before this snapshot (null = file didn't exist before)
  final Map<String, String?> fileBackups;

  const ProjectSnapshot({
    required this.id,
    required this.userMessageIndex,
    required this.messagePreview,
    required this.timestamp,
    required this.fileBackups,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userMessageIndex': userMessageIndex,
        'messagePreview': messagePreview,
        'timestamp': timestamp.toIso8601String(),
        'fileBackups': fileBackups,
      };

  factory ProjectSnapshot.fromJson(Map<String, dynamic> j) => ProjectSnapshot(
        id: j['id'] as String,
        userMessageIndex: j['userMessageIndex'] as int,
        messagePreview: j['messagePreview'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        fileBackups: Map<String, String?>.from(
            (j['fileBackups'] as Map).map((k, v) => MapEntry(k as String, v as String?))),
      );
}

// ── Chat message ───────────────────────────────────────────────────────────────

class ChatMessage {
  final String id;
  final bool isUser;
  final String text;
  final bool isThinking;
  final List<FileOperation> operations;
  /// For orchestrator messages: id of the sub-agent that produced this message.
  /// Empty string = the conversation's primary agent.
  final String subAgentId;
  /// Human-readable label shown above orchestrator sub-agent messages.
  final String subAgentLabel;
  final int subAgentColor;

  const ChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    this.isThinking = false,
    this.operations = const [],
    this.subAgentId = '',
    this.subAgentLabel = '',
    this.subAgentColor = 0,
  });

  ChatMessage copyWith({
    String? text,
    bool? isThinking,
    List<FileOperation>? operations,
    String? subAgentId,
    String? subAgentLabel,
    int? subAgentColor,
  }) =>
      ChatMessage(
        id: id,
        isUser: isUser,
        text: text ?? this.text,
        isThinking: isThinking ?? this.isThinking,
        operations: operations ?? this.operations,
        subAgentId: subAgentId ?? this.subAgentId,
        subAgentLabel: subAgentLabel ?? this.subAgentLabel,
        subAgentColor: subAgentColor ?? this.subAgentColor,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'isUser': isUser,
        'text': text,
        'operations': operations.map((o) => o.toJson()).toList(),
        if (subAgentId.isNotEmpty) 'subAgentId': subAgentId,
        if (subAgentLabel.isNotEmpty) 'subAgentLabel': subAgentLabel,
        if (subAgentColor != 0) 'subAgentColor': subAgentColor,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        isUser: j['isUser'] as bool,
        text: j['text'] as String,
        operations: ((j['operations'] as List?) ?? [])
            .map((o) => FileOperation.fromJson(o as Map<String, dynamic>))
            .toList(),
        subAgentId: j['subAgentId'] as String? ?? '',
        subAgentLabel: j['subAgentLabel'] as String? ?? '',
        subAgentColor: j['subAgentColor'] as int? ?? 0,
      );
}

// ── Chat conversation ──────────────────────────────────────────────────────────

class ChatConversation {
  final String id;
  final AiAgent agent;
  final List<ChatMessage> messages;

  const ChatConversation({
    required this.id,
    required this.agent,
    this.messages = const [],
  });

  String get title {
    final first = messages.where((m) => m.isUser).firstOrNull;
    if (first == null) return 'Nova conversa';
    final t = first.text;
    return t.length > 46 ? '${t.substring(0, 46)}…' : t;
  }

  ChatConversation copyWith({List<ChatMessage>? messages}) => ChatConversation(
        id: id,
        agent: agent,
        messages: messages ?? this.messages,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'agentId': agent.id,
        'agentName': agent.name,
        'agentFocus': agent.focus,
        'agentColor': agent.colorValue,
        'agentInstructions': agent.instructions,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatConversation.fromJson(Map<String, dynamic> j) => ChatConversation(
        id: j['id'] as String,
        agent: AiAgent(
          id: j['agentId'] as String,
          name: j['agentName'] as String,
          focus: j['agentFocus'] as String,
          instructions: j['agentInstructions'] as String,
          colorValue: j['agentColor'] as int,
        ),
        messages: ((j['messages'] as List?) ?? [])
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}
