import 'package:core/core.dart';

/// All info needed to install and verify an SDK inside the rootfs
class SdkDefinition {
  final SdkType type;
  final String verifyBinary; // binary to check existence
  final String verifyCmd; // command to run to get version
  final String installScript; // bash one-liner to install
  final String buildCommand; // how to build a project
  final String newProjectCmd; // how to create a new project ($name = project name)
  final List<String> projectFileExtensions; // for syntax highlighting
  final String defaultEntryFile; // file to open on project launch

  const SdkDefinition({
    required this.type,
    required this.verifyBinary,
    required this.verifyCmd,
    required this.installScript,
    required this.buildCommand,
    required this.newProjectCmd,
    required this.projectFileExtensions,
    required this.defaultEntryFile,
  });

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
      newProjectCmd: 'flutter create \$name',
      projectFileExtensions: ['dart', 'yaml', 'json'],
      defaultEntryFile: 'lib/main.dart',
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
      newProjectCmd: '''
mkdir -p \$name && cd \$name
''',
      projectFileExtensions: ['java', 'kotlin', 'kt', 'xml', 'gradle'],
      defaultEntryFile: 'app/src/main/java/MainActivity.kt',
    ),
    SdkDefinition(
      type: SdkType.reactNative,
      verifyBinary: 'node',
      verifyCmd: 'npx react-native --version',
      installScript: '''
pkg update -y && pkg install -y nodejs-lts
npm install -g react-native-cli
''',
      buildCommand: 'npx react-native build-android --mode=debug',
      newProjectCmd: 'npx react-native init \$name',
      projectFileExtensions: ['js', 'jsx', 'ts', 'tsx', 'json'],
      defaultEntryFile: 'App.tsx',
    ),
    SdkDefinition(
      type: SdkType.nodejs,
      verifyBinary: 'node',
      verifyCmd: 'node --version',
      installScript: 'pkg update -y && pkg install -y nodejs-lts',
      buildCommand: 'npm run build',
      newProjectCmd: 'mkdir -p \$name && cd \$name && npm init -y',
      projectFileExtensions: ['js', 'ts', 'mjs', 'cjs', 'json'],
      defaultEntryFile: 'index.js',
    ),
    SdkDefinition(
      type: SdkType.python,
      verifyBinary: 'python3',
      verifyCmd: 'python3 --version',
      installScript: 'pkg update -y && pkg install -y python',
      buildCommand: 'python3 main.py',
      newProjectCmd: 'mkdir -p \$name',
      projectFileExtensions: ['py', 'txt', 'cfg', 'toml'],
      defaultEntryFile: 'main.py',
    ),
  ];

  static SdkDefinition forType(SdkType type) =>
      all.firstWhere((d) => d.type == type);
}
