import 'package:core/core.dart';

/// Hardcoded fallback SDK definitions.
/// When a JSON extension is installed its [SdkConfig] / [DapConfig] take
/// priority. These values are used when no matching extension is available.
class SdkDefinition {
  final SdkType type;
  final String verifyBinary;
  final String verifyCmd;
  final String installScript;
  final String buildCommand;

  /// Shell commands run automatically when [installScript] exits with a
  /// non-zero status (via `trap … ERR`).  Should forcefully undo everything
  /// the install script may have created so the user can retry cleanly.
  final String cleanupScript;

  /// Project-level config (new project cmd, entry file, sync, etc.)
  final SdkConfig sdkConfig;

  /// DAP adapter config. Empty (no DAP) for non-Flutter SDKs by default.
  final DapConfig dapConfig;

  const SdkDefinition({
    required this.type,
    required this.verifyBinary,
    required this.verifyCmd,
    required this.installScript,
    required this.buildCommand,
    required this.sdkConfig,
    this.cleanupScript = '',
    this.dapConfig = DapConfig.empty,
  });

  // ── Convenience pass-throughs ─────────────────────────────────────────────

  String get newProjectCmd       => sdkConfig.newProjectCmd;
  String get defaultEntryFile    => sdkConfig.defaultEntryFile;
  List<String> get projectFileExtensions => sdkConfig.fileExtensions;
  String get syncCommand         => sdkConfig.syncCommand;
  String get syncTriggerFile     => sdkConfig.syncTriggerFile;

  // ── Hardcoded definitions ─────────────────────────────────────────────────

  static const List<SdkDefinition> all = [
    SdkDefinition(
      type: SdkType.flutter,
      verifyBinary: 'flutter',
      verifyCmd: 'flutter --version',
      cleanupScript: r'''
rm -rf "$PREFIX/opt/flutter" 2>/dev/null
rm -f "$PREFIX/bin/flutter" 2>/dev/null
rm -f flutter_linux_arm64.tar.xz 2>/dev/null
pkg uninstall -y curl git unzip 2>/dev/null || true
''',
      installScript: '''
pkg update -y && pkg install -y curl git unzip
curl -LO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_arm64.tar.xz
mkdir -p \$PREFIX/opt
tar xf flutter_linux_arm64.tar.xz -C \$PREFIX/opt
rm flutter_linux_arm64.tar.xz
# Symlink into \$PREFIX/bin so it is on PATH for the IDE process
ln -sf \$PREFIX/opt/flutter/bin/flutter \$PREFIX/bin/flutter
# Make flutter available in the current terminal session
export PATH="\$PREFIX/opt/flutter/bin:\$PATH"
echo 'export PATH="\$PATH:\$PREFIX/opt/flutter/bin"' >> ~/.bashrc
flutter config --android-sdk \${ANDROID_HOME:-\$PREFIX/opt/android-sdk}
flutter doctor
''',
      buildCommand: 'flutter build apk --debug',
      sdkConfig: SdkConfig(
        newProjectCmd: 'flutter create \$name',
        defaultEntryFile: 'lib/main.dart',
        fileExtensions: ['dart', 'yaml', 'json'],
        syncCommand: 'flutter pub get',
        syncTriggerFile: 'pubspec.yaml',
        formatCommand: 'dart format',
      ),
      dapConfig: DapConfig(
        adapterBinary: r'$FLUTTER_ROOT/bin/flutter',
        adapterArgs: ['debug_adapter'],
        adapterId: 'dart',
        launchProgram: 'lib/main.dart',
        devicesCommand: r'$FLUTTER_ROOT/bin/flutter devices --machine',
        buildDoneStrings: [
          'Syncing files to device',
          'flutter run key commands',
          'Running with soundNullSafety',
          'To hot reload',
        ],
        platformDeviceMap: {
          'android': 'android',
          'web': 'web-server',
          'linux': 'linux',
        },
        webPlatform: 'web',
        webServerArgs: [
          '-d', 'web-server',
          '--web-port', '5050',
          '--web-hostname', 'localhost',
          '--no-start-paused',
        ],
      ),
    ),
    SdkDefinition(
      type: SdkType.androidSdk,
      verifyBinary: 'sdkmanager',
      verifyCmd: 'sdkmanager --version',
      cleanupScript: r'''
rm -rf "$ANDROID_HOME/cmdline-tools" "$ANDROID_HOME/platform-tools" \
       "$ANDROID_HOME/platforms" "$ANDROID_HOME/build-tools" 2>/dev/null
rm -rf "$PREFIX/opt/java-language-server" 2>/dev/null
rm -f "$PREFIX/bin/sdkmanager" "$PREFIX/bin/adb" 2>/dev/null
rm -f commandlinetools-linux-*.zip java-language-server.tar.gz 2>/dev/null
pkg uninstall -y openjdk-17 wget unzip 2>/dev/null || true
''',
      installScript: '''
pkg update -y && pkg install -y openjdk-17 wget unzip
# Use fallback if ANDROID_HOME is not set in this shell session
export ANDROID_HOME="\${ANDROID_HOME:-\$PREFIX/opt/android-sdk}"
mkdir -p "\$ANDROID_HOME/cmdline-tools"
wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q commandlinetools-linux-*.zip -d "\$ANDROID_HOME/cmdline-tools"
mv "\$ANDROID_HOME/cmdline-tools/cmdline-tools" "\$ANDROID_HOME/cmdline-tools/latest"
rm commandlinetools-linux-*.zip
# Add tools to PATH for this session
export PATH="\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH"
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
# Symlink into \$PREFIX/bin so the IDE process can find them
ln -sf "\$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "\$PREFIX/bin/sdkmanager"
ln -sf "\$ANDROID_HOME/platform-tools/adb" "\$PREFIX/bin/adb" 2>/dev/null || true
echo 'export PATH="\$PATH:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools"' >> ~/.bashrc
# ── java-language-server (Java/Kotlin LSP) ─────────────────────────────────
# Lightweight single-jar LSP by georgewfraser.  Much more reliable on Android
# than jdtls or kotlin-language-server: no OSGi, starts in under 10 s.
mkdir -p "\$PREFIX/opt/java-language-server"
wget -q https://github.com/georgewfraser/java-language-server/releases/latest/download/java-language-server.tar.gz
tar xzf java-language-server.tar.gz -C "\$PREFIX/opt/java-language-server"
rm java-language-server.tar.gz
# Verify the jar landed where the IDE expects it
ls "\$PREFIX/opt/java-language-server/dist/lang.jar"
''',
      buildCommand: './gradlew assembleDebug',
      sdkConfig: SdkConfig(
        newProjectCmd: 'mkdir -p \$name',
        defaultEntryFile: 'app/src/main/java/MainActivity.kt',
        fileExtensions: ['java', 'kotlin', 'kt', 'xml', 'gradle'],
        syncCommand: './gradlew --refresh-dependencies',
        syncTriggerFile: 'app/build.gradle',
      ),
    ),
    SdkDefinition(
      type: SdkType.reactNative,
      verifyBinary: 'node',
      verifyCmd: 'node --version',
      cleanupScript: 'pkg uninstall -y nodejs-lts 2>/dev/null || true',
      installScript: 'apt-get update -y && apt-get install -y nodejs-lts',
      buildCommand: 'npx expo export',
      sdkConfig: SdkConfig(
        newProjectCmd: r'npx --yes create-expo-app $name',
        defaultEntryFile: 'App.tsx',
        fileExtensions: ['js', 'jsx', 'ts', 'tsx', 'json'],
        syncCommand: 'npm install',
        syncTriggerFile: 'package.json',
      ),
    ),
    SdkDefinition(
      type: SdkType.nodejs,
      verifyBinary: 'node',
      verifyCmd: 'node --version',
      cleanupScript: 'pkg uninstall -y nodejs-lts 2>/dev/null || true',
      installScript: 'pkg update -y && pkg install -y nodejs-lts',
      buildCommand: 'npm run build',
      sdkConfig: SdkConfig(
        newProjectCmd: 'mkdir -p \$name && cd \$name && npm init -y',
        defaultEntryFile: 'index.js',
        fileExtensions: ['js', 'ts', 'mjs', 'cjs', 'json'],
        syncCommand: 'npm install',
        syncTriggerFile: 'package.json',
      ),
    ),
    SdkDefinition(
      type: SdkType.python,
      verifyBinary: 'python3',
      verifyCmd: 'python3 --version',
      cleanupScript: 'pkg uninstall -y python 2>/dev/null || true',
      installScript: 'pkg update -y && pkg install -y python',
      buildCommand: 'python3 main.py',
      sdkConfig: SdkConfig(
        newProjectCmd: 'mkdir -p \$name',
        defaultEntryFile: 'main.py',
        fileExtensions: ['py', 'txt', 'cfg', 'toml'],
        syncCommand: 'pip install -r requirements.txt',
        syncTriggerFile: 'requirements.txt',
      ),
    ),
    SdkDefinition(
      type: SdkType.swift,
      verifyBinary: 'swift',
      verifyCmd: 'swift --version',
      cleanupScript: 'pkg uninstall -y swift 2>/dev/null || true',
      installScript: 'pkg update -y && pkg install -y swift',
      buildCommand: 'swift build',
      sdkConfig: SdkConfig(
        newProjectCmd: 'mkdir -p \$name && cd \$name && swift package init --type executable',
        defaultEntryFile: 'Sources/main.swift',
        fileExtensions: ['swift', 'json', 'md'],
      ),
    ),
    SdkDefinition(
      type: SdkType.go,
      verifyBinary: 'go',
      verifyCmd: 'go version',
      cleanupScript: 'pkg uninstall -y golang 2>/dev/null || true',
      installScript: 'pkg update -y && pkg install -y golang',
      buildCommand: 'go build -o app .',
      sdkConfig: SdkConfig(
        // printf interprets \n as newline; "fmt" must stay unescaped for shell
        newProjectCmd: r'''mkdir -p $name && cd $name && go mod init $name && printf 'package main\n\nimport "fmt"\n\nfunc main() {\n\tfmt.Println("Hello, World!")\n}\n' > main.go''',
        defaultEntryFile: 'main.go',
        fileExtensions: ['go', 'mod', 'sum'],
        syncCommand: 'go mod tidy',
        syncTriggerFile: 'go.mod',
        formatCommand: 'gofmt -w .',
      ),
      dapConfig: DapConfig(
        adapterBinary: r'$HOME/go/bin/dlv',
        adapterArgs: ['dap', '--check-go-version=false'],
        adapterId: 'go',
        launchProgram: '.',
        buildDoneStrings: ['loaded'],
      ),
    ),
  ];

  static SdkDefinition forType(SdkType type) =>
      all.firstWhere((d) => d.type == type);
}
