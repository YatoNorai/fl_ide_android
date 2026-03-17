enum BuildStatus { idle, running, success, error }

class BuildResult {
  final BuildStatus status;
  final String output;
  final String? apkPath;
  final DateTime? finishedAt;

  const BuildResult({
    this.status = BuildStatus.idle,
    this.output = '',
    this.apkPath,
    this.finishedAt,
  });

  BuildResult copyWith({
    BuildStatus? status,
    String? output,
    String? apkPath,
    DateTime? finishedAt,
  }) =>
      BuildResult(
        status: status ?? this.status,
        output: output ?? this.output,
        apkPath: apkPath ?? this.apkPath,
        finishedAt: finishedAt ?? this.finishedAt,
      );

  bool get isRunning => status == BuildStatus.running;
  bool get isSuccess => status == BuildStatus.success;
  bool get isError => status == BuildStatus.error;
}
