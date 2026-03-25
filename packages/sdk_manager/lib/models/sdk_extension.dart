import 'package:core/core.dart';

class SdkExtPackage {
  final String type;    // 'zip' | 'tar_gz' | 'deb'
  final String url;
  final String filename;
  final String arch;
  final double? sizeMb;

  const SdkExtPackage({
    required this.type,
    required this.url,
    required this.filename,
    required this.arch,
    this.sizeMb,
  });

  factory SdkExtPackage.fromJson(Map<String, dynamic> j) => SdkExtPackage(
        type: j['type'] as String,
        url: j['url'] as String,
        filename: j['filename'] as String,
        arch: j['arch'] as String,
        sizeMb: (j['size_mb'] as num?)?.toDouble(),
      );
}

class SdkExtAuthor {
  final String name;
  final String? github;

  const SdkExtAuthor({required this.name, this.github});

  factory SdkExtAuthor.fromJson(Map<String, dynamic> j) => SdkExtAuthor(
        name: j['name'] as String,
        github: j['github'] as String?,
      );
}

class SdkExtJsonAuthor {
  final String name;
  final String date;

  const SdkExtJsonAuthor({required this.name, required this.date});

  factory SdkExtJsonAuthor.fromJson(Map<String, dynamic> j) =>
      SdkExtJsonAuthor(
        name: j['name'] as String,
        date: j['date'] as String,
      );
}

class SdkExtStep {
  final String type;          // 'shell' | 'extract'
  final String description;
  final String? command;      // for 'shell'
  final String? dest;         // for 'extract' — destination directory

  const SdkExtStep({
    required this.type,
    required this.description,
    this.command,
    this.dest,
  });

  factory SdkExtStep.fromJson(Map<String, dynamic> j) => SdkExtStep(
        type: j['type'] as String,
        description: j['description'] as String,
        command: j['command'] as String?,
        dest: j['dest'] as String?,
      );
}

class SdkExtension {
  final int schemaVersion;
  final String sdk;
  final String sdkVersion;
  final String displayName;
  final String description;
  final SdkExtPackage package;
  final SdkExtAuthor packageAuthor;
  final SdkExtJsonAuthor jsonAuthor;
  final List<SdkExtStep> installSteps;
  final List<SdkExtStep> configSteps;
  final List<SdkExtStep> cleanupSteps;
  final List<SdkExtStep> uninstallSteps;
  final String verifyBinary;
  final String verifyCommand;

  const SdkExtension({
    required this.schemaVersion,
    required this.sdk,
    required this.sdkVersion,
    required this.displayName,
    required this.description,
    required this.package,
    required this.packageAuthor,
    required this.jsonAuthor,
    required this.installSteps,
    required this.configSteps,
    this.cleanupSteps = const [],
    this.uninstallSteps = const [],
    required this.verifyBinary,
    required this.verifyCommand,
  });

  factory SdkExtension.fromJson(Map<String, dynamic> j) => SdkExtension(
        schemaVersion: j['schema_version'] as int,
        sdk: j['sdk'] as String,
        sdkVersion: j['sdk_version'] as String,
        displayName: j['display_name'] as String,
        description: j['description'] as String,
        package: SdkExtPackage.fromJson(j['package'] as Map<String, dynamic>),
        packageAuthor:
            SdkExtAuthor.fromJson(j['package_author'] as Map<String, dynamic>),
        jsonAuthor: SdkExtJsonAuthor.fromJson(
            j['json_author'] as Map<String, dynamic>),
        installSteps: (j['install_steps'] as List)
            .map((s) => SdkExtStep.fromJson(s as Map<String, dynamic>))
            .toList(),
        configSteps: (j['config_steps'] as List)
            .map((s) => SdkExtStep.fromJson(s as Map<String, dynamic>))
            .toList(),
        cleanupSteps: ((j['cleanup_steps'] as List?) ?? [])
            .map((s) => SdkExtStep.fromJson(s as Map<String, dynamic>))
            .toList(),
        uninstallSteps: ((j['uninstall_steps'] as List?) ?? [])
            .map((s) => SdkExtStep.fromJson(s as Map<String, dynamic>))
            .toList(),
        verifyBinary: j['verify_binary'] as String,
        verifyCommand: j['verify_command'] as String,
      );

  bool get isInstalled => RuntimeEnvir.isBinaryAvailable(verifyBinary);
}
