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
      installScript: '''
pkg update -y && pkg install -y curl git unzip
curl -LO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_arm64.tar.xz
tar xf flutter_linux_arm64.tar.xz -C \$PREFIX
rm flutter_linux_arm64.tar.xz
echo 'export PATH="\$PATH:\$PREFIX/flutter/bin"' >> ~/.bashrc
flutter config --android-sdk \$ANDROID_HOME
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
      installScript: '''
pkg update -y && pkg install -y openjdk-17 wget unzip
mkdir -p \$ANDROID_HOME/cmdline-tools
wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q commandlinetools-linux-*.zip -d \$ANDROID_HOME/cmdline-tools
mv \$ANDROID_HOME/cmdline-tools/cmdline-tools \$ANDROID_HOME/cmdline-tools/latest
rm commandlinetools-linux-*.zip
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
''',
      buildCommand: './gradlew assembleDebug',
      sdkConfig: SdkConfig(
        newProjectCmd: 'mkdir -p \$name',
        defaultEntryFile: 'app/src/main/java/MainActivity.kt',
        fileExtensions: ['java', 'kotlin', 'kt', 'xml', 'gradle'],
      ),
    ),
    SdkDefinition(
      type: SdkType.reactNative,
      verifyBinary: 'node',
      verifyCmd: 'node --version',
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
    ),
  ];

  static SdkDefinition forType(SdkType type) =>
      all.firstWhere((d) => d.type == type);
}
