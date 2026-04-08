import 'package:core/core.dart';
import 'package:sdk_manager/sdk_manager.dart';

class ProjectTemplate {
  final SdkType sdk;

  const ProjectTemplate(this.sdk);

  /// [overrideNewProjectCmd] — when provided (e.g. from an installed JSON
  /// extension) it replaces the hardcoded [SdkDefinition.newProjectCmd].
  /// [remoteIsWindows] — when true, generates cmd.exe-compatible commands.
  String createCommand(String projectName, String parentDir,
      {String? overrideNewProjectCmd, bool remoteIsWindows = false}) {
    final def = SdkDefinition.forType(sdk);
    final raw = overrideNewProjectCmd ?? def.newProjectCmd;

    // Replace $name and fix mkdir for Windows (no -p flag in cmd.exe).
    final cmd = raw
        .replaceAll(r'$name', projectName)
        .replaceAll('mkdir -p ', remoteIsWindows ? 'mkdir ' : 'mkdir -p ');

    final projectPath = '$parentDir/$projectName';

    // PowerShell (Windows SSH default) uses ';' as separator and its built-in
    // 'cd' handles drive changes natively — no '/d' flag or '&&' needed.
    final base = remoteIsWindows
        ? 'cd "$parentDir"; $cmd'
        : 'cd "$parentDir" && $cmd';

    // Termux/Android-specific gradle fixes are only needed on Linux.
    if (sdk == SdkType.flutter && !remoteIsWindows) {
      return '$base && ${_flutterAndroidFixes(projectPath)}';
    }
    return base;
  }

  /// Bash commands to fix a newly-created Flutter project so it builds
  /// correctly with termux-android-sdk (mumumusuc).
  ///
  /// Fixes applied:
  ///  1. Pin `ndkVersion` to a concrete version (flutter.ndkVersion resolves
  ///     to an empty string inside Termux and breaks the build).
  ///  2. Write `local.properties` with the correct `sdk.dir` pointing at the
  ///     termux-android-sdk installation path.
  static String _flutterAndroidFixes(String projectPath) {
    const ndkVersion = '27.0.12077973';
    // Termux android-sdk lives at $PREFIX/opt/android-sdk
    const androidSdkDir = r'$PREFIX/opt/android-sdk';
    return '''
(
  GRADLE="$projectPath/android/app/build.gradle.kts"
  if [ -f "\$GRADLE" ]; then
    sed -i 's/ndkVersion = flutter\\.ndkVersion/ndkVersion = "$ndkVersion"/g' "\$GRADLE"
    echo "✓ Pinned ndkVersion to $ndkVersion"
  fi
  PROPS="$projectPath/android/local.properties"
  printf 'sdk.dir=$androidSdkDir\\nndk.dir=$androidSdkDir/ndk/$ndkVersion\\n' > "\$PROPS"
  echo "✓ Wrote local.properties"
) 2>&1''';
  }

  static ProjectTemplate forSdk(SdkType sdk) => ProjectTemplate(sdk);
}
