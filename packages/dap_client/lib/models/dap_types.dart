// DAP domain types used across client and provider.

class DapThread {
  final int id;
  final String name;
  const DapThread({required this.id, required this.name});

  factory DapThread.fromJson(Map<String, dynamic> j) =>
      DapThread(id: j['id'] as int, name: j['name'] as String? ?? 'Thread ${j['id']}');
}

class DapStackFrame {
  final int id;
  final String name;
  final String? sourcePath;
  final String? sourceName;
  final int line;
  final int column;

  const DapStackFrame({
    required this.id,
    required this.name,
    this.sourcePath,
    this.sourceName,
    required this.line,
    required this.column,
  });

  factory DapStackFrame.fromJson(Map<String, dynamic> j) {
    final src = j['source'] as Map<String, dynamic>?;
    return DapStackFrame(
      id: j['id'] as int,
      name: j['name'] as String? ?? '<unknown>',
      sourcePath: src?['path'] as String?,
      sourceName: src?['name'] as String?,
      line: j['line'] as int? ?? 0,
      column: j['column'] as int? ?? 0,
    );
  }
}

class DapScope {
  final String name;
  final int variablesReference;
  final bool expensive;

  const DapScope({
    required this.name,
    required this.variablesReference,
    required this.expensive,
  });

  factory DapScope.fromJson(Map<String, dynamic> j) => DapScope(
        name: j['name'] as String? ?? '',
        variablesReference: j['variablesReference'] as int? ?? 0,
        expensive: j['expensive'] as bool? ?? false,
      );
}

class DapVariable {
  final String name;
  final String value;
  final String? type;
  /// > 0 means this variable has children (object/list).
  final int variablesReference;

  const DapVariable({
    required this.name,
    required this.value,
    this.type,
    required this.variablesReference,
  });

  bool get hasChildren => variablesReference > 0;

  factory DapVariable.fromJson(Map<String, dynamic> j) => DapVariable(
        name: j['name'] as String? ?? '',
        value: j['value'] as String? ?? '',
        type: j['type'] as String?,
        variablesReference: j['variablesReference'] as int? ?? 0,
      );
}

class DapBreakpoint {
  final int? id;
  final bool verified;
  final int? line;
  final String? message;

  const DapBreakpoint({
    this.id,
    required this.verified,
    this.line,
    this.message,
  });

  factory DapBreakpoint.fromJson(Map<String, dynamic> j) => DapBreakpoint(
        id: j['id'] as int?,
        verified: j['verified'] as bool? ?? false,
        line: j['line'] as int?,
        message: j['message'] as String?,
      );
}
