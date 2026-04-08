class SshConfig {
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKeyPath;
  final bool useKeyAuth;
  final String remoteProjectsPath;
  final bool enabled;

  const SshConfig({
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKeyPath,
    this.useKeyAuth = false,
    this.remoteProjectsPath = '~/projects',
    this.enabled = false,
  });

  factory SshConfig.empty() => const SshConfig(
        host: '',
        port: 22,
        username: '',
        password: null,
        privateKeyPath: null,
        useKeyAuth: false,
        remoteProjectsPath: '~/projects',
        enabled: false,
      );

  factory SshConfig.fromJson(Map<String, dynamic> json) => SshConfig(
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 22,
        username: json['username'] as String? ?? '',
        password: json['password'] as String?,
        privateKeyPath: json['privateKeyPath'] as String?,
        useKeyAuth: json['useKeyAuth'] as bool? ?? false,
        remoteProjectsPath:
            json['remoteProjectsPath'] as String? ?? '~/projects',
        enabled: json['enabled'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        if (password != null) 'password': password,
        if (privateKeyPath != null) 'privateKeyPath': privateKeyPath,
        'useKeyAuth': useKeyAuth,
        'remoteProjectsPath': remoteProjectsPath,
        'enabled': enabled,
      };

  SshConfig copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? privateKeyPath,
    bool? useKeyAuth,
    String? remoteProjectsPath,
    bool? enabled,
  }) =>
      SshConfig(
        host: host ?? this.host,
        port: port ?? this.port,
        username: username ?? this.username,
        password: password ?? this.password,
        privateKeyPath: privateKeyPath ?? this.privateKeyPath,
        useKeyAuth: useKeyAuth ?? this.useKeyAuth,
        remoteProjectsPath: remoteProjectsPath ?? this.remoteProjectsPath,
        enabled: enabled ?? this.enabled,
      );
}
