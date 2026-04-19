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
  final String cleanupScript;
  final SdkConfig sdkConfig;
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

  String get newProjectCmd          => sdkConfig.newProjectCmd;
  String get defaultEntryFile       => sdkConfig.defaultEntryFile;
  List<String> get projectFileExtensions => sdkConfig.fileExtensions;
  String get syncCommand            => sdkConfig.syncCommand;
  String get syncTriggerFile        => sdkConfig.syncTriggerFile;

  // ── All hardcoded definitions ─────────────────────────────────────────────

  static const List<SdkDefinition> all = [

    // ── Flutter ──────────────────────────────────────────────────────────────
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
      installScript: r'''
pkg update -y && pkg install -y curl git unzip
curl -LO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_arm64.tar.xz
mkdir -p $PREFIX/opt
tar xf flutter_linux_arm64.tar.xz -C $PREFIX/opt
rm flutter_linux_arm64.tar.xz
ln -sf $PREFIX/opt/flutter/bin/flutter $PREFIX/bin/flutter
export PATH="$PREFIX/opt/flutter/bin:$PATH"
echo 'export PATH="$PATH:$PREFIX/opt/flutter/bin"' >> ~/.bashrc
flutter config --android-sdk ${ANDROID_HOME:-$PREFIX/opt/android-sdk}
flutter doctor
''',
      buildCommand: 'flutter build apk --debug',
      sdkConfig: SdkConfig(
        newProjectCmd: r'flutter create $name',
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

    // ── Android SDK ───────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.androidSdk,
      verifyBinary: 'sdkmanager',
      verifyCmd: 'sdkmanager --version',
      cleanupScript: r'''
rm -rf "$ANDROID_HOME/cmdline-tools" "$ANDROID_HOME/platform-tools" \
       "$ANDROID_HOME/platforms" "$ANDROID_HOME/build-tools" 2>/dev/null
rm -rf "$PREFIX/opt/java-language-server" 2>/dev/null
rm -rf "$PREFIX/opt/lemminx" 2>/dev/null
rm -f "$PREFIX/bin/sdkmanager" "$PREFIX/bin/adb" 2>/dev/null
rm -f commandlinetools-linux-*.zip java-language-server.tar.gz 2>/dev/null
pkg uninstall -y openjdk-17 wget unzip 2>/dev/null || true
''',
      installScript: r'''
pkg update -y && pkg install -y openjdk-17 wget unzip
export ANDROID_HOME="${ANDROID_HOME:-$PREFIX/opt/android-sdk}"
mkdir -p "$ANDROID_HOME/cmdline-tools"
wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip -q commandlinetools-linux-*.zip -d "$ANDROID_HOME/cmdline-tools"
mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
rm commandlinetools-linux-*.zip
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
ln -sf "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "$PREFIX/bin/sdkmanager"
ln -sf "$ANDROID_HOME/platform-tools/adb" "$PREFIX/bin/adb" 2>/dev/null || true
echo 'export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"' >> ~/.bashrc
pkg install -y kotlin-language-server 2>/dev/null || true
mkdir -p "$PREFIX/opt/java-language-server"
wget -q https://github.com/georgewfraser/java-language-server/releases/latest/download/java-language-server.tar.gz
tar xzf java-language-server.tar.gz -C "$PREFIX/opt/java-language-server"
rm java-language-server.tar.gz
ls "$PREFIX/opt/java-language-server/dist/lang.jar"
mkdir -p "$PREFIX/opt/lemminx"
wget -q -O "$PREFIX/opt/lemminx/lemminx.jar" \
  https://github.com/eclipse/lemminx/releases/download/0.29.0/org.eclipse.lemminx-0.29.0-uber.jar
ls "$PREFIX/opt/lemminx/lemminx.jar"
''',
      buildCommand: './gradlew assembleDebug',
      sdkConfig: SdkConfig(
        newProjectCmd: r'mkdir -p $name',
        defaultEntryFile: 'app/src/main/java/MainActivity.kt',
        fileExtensions: ['java', 'kotlin', 'kt', 'xml', 'gradle'],
        syncCommand: './gradlew --refresh-dependencies',
        syncTriggerFile: 'app/build.gradle',
      ),
    ),

    // ── React Native ──────────────────────────────────────────────────────────
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

    // ── Node.js ───────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.nodejs,
      verifyBinary: 'node',
      verifyCmd: 'node --version',
      cleanupScript: 'pkg uninstall -y nodejs-lts 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y nodejs-lts
npm install -g @vscode/js-debug 2>/dev/null || true
echo "✓ Node.js instalado: $(node --version)"
''',
      buildCommand: 'npm run build',
      sdkConfig: SdkConfig(
        newProjectCmd: r'mkdir -p $name && cd $name && npm init -y',
        defaultEntryFile: 'index.js',
        fileExtensions: ['js', 'ts', 'mjs', 'cjs', 'json'],
        syncCommand: 'npm install',
        syncTriggerFile: 'package.json',
        runCommand: 'node index.js',
      ),
      dapConfig: DapConfig(
        adapterBinary: 'node',
        adapterArgs: [r'$PREFIX/lib/node_modules/@vscode/js-debug/dist/src/debugAdapter.js'],
        adapterId: 'node2',
        launchProgram: 'index.js',
        buildDoneStrings: ['Debugger attached', 'Listening for connections'],
      ),
    ),

    // ── Python ────────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.python,
      verifyBinary: 'python3',
      verifyCmd: 'python3 --version',
      cleanupScript: 'pkg uninstall -y python 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y python
pip install pylsp debugpy
''',
      buildCommand: 'python3 main.py',
      sdkConfig: SdkConfig(
        newProjectCmd: r'mkdir -p $name',
        defaultEntryFile: 'main.py',
        fileExtensions: ['py', 'txt', 'cfg', 'toml'],
        syncCommand: 'pip install -r requirements.txt',
        syncTriggerFile: 'requirements.txt',
      ),
      dapConfig: DapConfig(
        adapterBinary: r'$PREFIX/bin/python3',
        adapterArgs: ['-m', 'debugpy.adapter'],
        adapterId: 'python',
        launchProgram: 'main.py',
        buildDoneStrings: ['Debugger is ready'],
      ),
    ),

    // ── Swift ─────────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.swift,
      verifyBinary: 'swift',
      verifyCmd: 'swift --version',
      cleanupScript: 'pkg uninstall -y swift 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y swift lldb
[ ! -f "$PREFIX/bin/lldb-vscode" ] && [ -f "$PREFIX/bin/lldb-dap" ] && \
  ln -sf "$PREFIX/bin/lldb-dap" "$PREFIX/bin/lldb-vscode" 2>/dev/null || true
echo "✓ Swift instalado: $(swift --version 2>&1 | head -1)"
''',
      buildCommand: 'swift build',
      sdkConfig: SdkConfig(
        newProjectCmd: r'mkdir -p $name && cd $name && swift package init --type executable',
        defaultEntryFile: 'Sources/main.swift',
        fileExtensions: ['swift', 'json', 'md'],
        runCommand: 'swift run',
      ),
      dapConfig: DapConfig(
        adapterBinary: r'$PREFIX/bin/lldb-vscode',
        adapterArgs: [],
        adapterId: 'lldb',
        launchProgram: r'.build/debug/$name',
        buildDoneStrings: ['stop reason', 'Loaded symbols'],
      ),
    ),

    // ── Go ────────────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.go,
      verifyBinary: 'go',
      verifyCmd: 'go version',
      cleanupScript: 'pkg uninstall -y golang 2>/dev/null || true',
      installScript: 'pkg update -y && pkg install -y golang',
      buildCommand: 'go build -o app .',
      sdkConfig: SdkConfig(
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

    // ── Kotlin Multiplatform ──────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.kotlinMultiplatform,
      verifyBinary: 'java',
      verifyCmd: 'java -version',
      cleanupScript: 'pkg uninstall -y openjdk-17 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y openjdk-17
pkg install -y kotlin-language-server 2>/dev/null || true
mkdir -p "$HOME/.local/kotlin-debug-adapter"
wget -q -O /tmp/kda.zip https://github.com/fwcd/kotlin-debug-adapter/releases/latest/download/adapter.zip 2>/dev/null \
  && unzip -qo /tmp/kda.zip -d "$HOME/.local/kotlin-debug-adapter" && rm /tmp/kda.zip || true
echo "✓ Kotlin Multiplatform pronto"
''',
      buildCommand: './gradlew assembleDebug',
      sdkConfig: SdkConfig(
        newProjectCmd: r'mkdir -p $name',
        defaultEntryFile: 'androidApp/src/main/kotlin/MainActivity.kt',
        fileExtensions: ['kt', 'kts', 'xml', 'gradle', 'json'],
        syncCommand: './gradlew --refresh-dependencies',
        syncTriggerFile: 'settings.gradle.kts',
        runCommand: './gradlew :androidApp:assembleDebug',
      ),
      dapConfig: DapConfig(
        adapterBinary: r'$PREFIX/bin/java',
        adapterArgs: ['-jar', r'$HOME/.local/kotlin-debug-adapter/adapter.jar'],
        adapterId: 'kotlin',
        launchProgram: '.',
        buildDoneStrings: ['Adapter started', 'Listening'],
      ),
    ),

    // ── C / C++ ───────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.cpp,
      verifyBinary: 'clang',
      verifyCmd: 'clang --version',
      cleanupScript: 'pkg uninstall -y clang cmake make 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y clang clang-tools-extra lldb cmake make
[ ! -f "$PREFIX/bin/lldb-vscode" ] && [ -f "$PREFIX/bin/lldb-dap" ] && \
  ln -sf "$PREFIX/bin/lldb-dap" "$PREFIX/bin/lldb-vscode" 2>/dev/null || true
echo "✓ C/C++ toolchain instalado"
''',
      buildCommand: 'cmake --build build',
      sdkConfig: SdkConfig(
        newProjectCmd: r'''mkdir -p $name && cd $name && printf '#include <stdio.h>\nint main() { printf("Hello, World!\\n"); return 0; }\n' > main.c && printf 'cmake_minimum_required(VERSION 3.20)\nproject($name)\nadd_executable($name main.c)\n' > CMakeLists.txt && cmake -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON 2>/dev/null | tail -3''',
        defaultEntryFile: 'main.c',
        fileExtensions: ['c', 'cpp', 'cc', 'cxx', 'h', 'hpp'],
        formatCommand: 'clang-format -i .',
      ),
      dapConfig: DapConfig(
        adapterBinary: r'$PREFIX/bin/lldb-vscode',
        adapterArgs: [],
        adapterId: 'lldb',
        launchProgram: './build/main',
        buildDoneStrings: ['Built target'],
      ),
    ),

    // ── Rust ──────────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.rust,
      verifyBinary: 'rustc',
      verifyCmd: 'rustc --version',
      cleanupScript: r'pkg uninstall -y rust 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y rust lldb
cargo install rust-analyzer 2>&1 || pkg install -y rust-analyzer 2>/dev/null || true
[ ! -f "$PREFIX/bin/lldb-vscode" ] && [ -f "$PREFIX/bin/lldb-dap" ] && \
  ln -sf "$PREFIX/bin/lldb-dap" "$PREFIX/bin/lldb-vscode" 2>/dev/null || true
echo "✓ Rust instalado: $(rustc --version)"
''',
      buildCommand: 'cargo build',
      sdkConfig: SdkConfig(
        newProjectCmd: r'cargo new $name',
        defaultEntryFile: 'src/main.rs',
        fileExtensions: ['rs', 'toml'],
        syncCommand: 'cargo fetch',
        syncTriggerFile: 'Cargo.toml',
        formatCommand: 'cargo fmt',
      ),
      dapConfig: DapConfig(
        adapterBinary: r'$PREFIX/bin/lldb-vscode',
        adapterArgs: [],
        adapterId: 'lldb',
        launchProgram: r'target/debug/$name',
        buildDoneStrings: ['Finished'],
      ),
    ),

    // ── Lua ───────────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.lua,
      verifyBinary: 'lua',
      verifyCmd: 'lua -v',
      cleanupScript: 'pkg uninstall -y lua54 lua-language-server 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y lua54 lua-language-server
echo "✓ Lua instalado: $(lua -v)"
''',
      buildCommand: 'lua main.lua',
      sdkConfig: SdkConfig(
        newProjectCmd: r'''mkdir -p $name && printf 'print("Hello, World!")\n' > $name/main.lua''',
        defaultEntryFile: 'main.lua',
        fileExtensions: ['lua'],
        runCommand: 'lua main.lua',
      ),
    ),

    // ── Ruby ──────────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.ruby,
      verifyBinary: 'ruby',
      verifyCmd: 'ruby --version',
      cleanupScript: 'pkg uninstall -y ruby 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y ruby
gem install solargraph bundler
echo "✓ Ruby instalado: $(ruby --version)"
''',
      buildCommand: 'ruby main.rb',
      sdkConfig: SdkConfig(
        newProjectCmd: r'''mkdir -p $name && printf 'puts "Hello, World!"\n' > $name/main.rb''',
        defaultEntryFile: 'main.rb',
        fileExtensions: ['rb', 'gemspec'],
        syncCommand: 'bundle install',
        syncTriggerFile: 'Gemfile',
        formatCommand: 'rubocop -A .',
        runCommand: 'ruby main.rb',
      ),
    ),

    // ── PHP ───────────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.php,
      verifyBinary: 'php',
      verifyCmd: 'php --version',
      cleanupScript: 'pkg uninstall -y php 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y php nodejs-lts
npm install -g intelephense
echo "✓ PHP instalado: $(php --version | head -1)"
''',
      buildCommand: 'php index.php',
      sdkConfig: SdkConfig(
        newProjectCmd: r'''mkdir -p $name && printf '<?php\necho "Hello, World!\n";\n' > $name/index.php''',
        defaultEntryFile: 'index.php',
        fileExtensions: ['php', 'phtml', 'html'],
        syncCommand: 'composer install',
        syncTriggerFile: 'composer.json',
        runCommand: 'php index.php',
      ),
    ),

    // ── Bash / Shell ──────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.bash,
      verifyBinary: 'bash',
      verifyCmd: 'bash --version',
      cleanupScript: 'npm uninstall -g bash-language-server 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y nodejs-lts
npm install -g bash-language-server
echo "✓ bash-language-server instalado"
''',
      buildCommand: 'bash main.sh',
      sdkConfig: SdkConfig(
        newProjectCmd: r'''mkdir -p $name && printf '#!/usr/bin/env bash\necho "Hello, World!"\n' > $name/main.sh && chmod +x $name/main.sh''',
        defaultEntryFile: 'main.sh',
        fileExtensions: ['sh', 'bash'],
        runCommand: 'bash main.sh',
      ),
    ),

    // ── HTML / CSS ────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.htmlCss,
      verifyBinary: 'node',
      verifyCmd: 'node --version',
      cleanupScript: 'npm uninstall -g vscode-langservers-extracted 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y nodejs-lts
npm install -g vscode-langservers-extracted
echo "✓ HTML/CSS LSP instalado"
''',
      buildCommand: 'echo "Abra index.html em um navegador"',
      sdkConfig: SdkConfig(
        newProjectCmd: r'''mkdir -p $name && cat > $name/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>$name</title><link rel="stylesheet" href="style.css"></head>
<body><h1>Hello, World!</h1><script src="script.js"></script></body>
</html>
HTMLEOF
printf 'body { font-family: sans-serif; margin: 2rem; }\n' > $name/style.css
printf 'console.log("Hello!");\n' > $name/script.js''',
        defaultEntryFile: 'index.html',
        fileExtensions: ['html', 'css', 'scss', 'less', 'js'],
      ),
    ),

    // ── C# (.NET) ────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.csharp,
      verifyBinary: 'dotnet',
      verifyCmd: 'dotnet --version',
      cleanupScript: r'rm -rf "$HOME/.dotnet" 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y dotnet-sdk
dotnet tool install -g csharp-ls 2>&1 || true
echo "✓ .NET instalado: $(dotnet --version)"
''',
      buildCommand: 'dotnet build',
      sdkConfig: SdkConfig(
        newProjectCmd: r'dotnet new console -n $name',
        defaultEntryFile: 'Program.cs',
        fileExtensions: ['cs', 'csproj', 'json'],
        syncCommand: 'dotnet restore',
        syncTriggerFile: '*.csproj',
        formatCommand: 'dotnet format',
        runCommand: 'dotnet run',
      ),
    ),

    // ── Scala ────────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.scala,
      verifyBinary: 'scala',
      verifyCmd: 'scala --version',
      cleanupScript: 'pkg uninstall -y scala 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y openjdk-17 scala
mkdir -p "$HOME/.local/bin"
curl -fL https://github.com/coursier/launchers/raw/master/cs-aarch64-pc-linux.gz | gzip -d > "$HOME/.local/bin/cs"
chmod +x "$HOME/.local/bin/cs"
"$HOME/.local/bin/cs" install metals 2>&1 || true
echo "✓ Scala e Metals LSP instalados"
''',
      buildCommand: 'scala main.scala',
      sdkConfig: SdkConfig(
        newProjectCmd: r'''mkdir -p $name && printf 'object Main extends App {\n  println("Hello, World!")\n}\n' > $name/main.scala''',
        defaultEntryFile: 'main.scala',
        fileExtensions: ['scala', 'sc', 'sbt'],
        syncCommand: 'sbt update',
        syncTriggerFile: 'build.sbt',
        runCommand: 'scala main.scala',
      ),
    ),

    // ── R ────────────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.r,
      verifyBinary: 'Rscript',
      verifyCmd: 'Rscript --version',
      cleanupScript: 'pkg uninstall -y r-base 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y r-base
Rscript -e 'install.packages("languageserver", repos="https://cloud.r-project.org")' 2>&1
echo "✓ R instalado: $(Rscript --version)"
''',
      buildCommand: 'Rscript main.R',
      sdkConfig: SdkConfig(
        newProjectCmd: r'''mkdir -p $name && printf '# Hello World\ncat("Hello, World!\n")\n' > $name/main.R''',
        defaultEntryFile: 'main.R',
        fileExtensions: ['r', 'R', 'Rmd'],
        runCommand: 'Rscript main.R',
      ),
    ),

    // ── Zig ──────────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.zig,
      verifyBinary: 'zig',
      verifyCmd: 'zig version',
      cleanupScript: 'pkg uninstall -y zig zls 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y zig zls lldb
[ ! -f "$PREFIX/bin/lldb-vscode" ] && [ -f "$PREFIX/bin/lldb-dap" ] && \
  ln -sf "$PREFIX/bin/lldb-dap" "$PREFIX/bin/lldb-vscode" 2>/dev/null || true
echo "✓ Zig instalado: $(zig version)"
''',
      buildCommand: 'zig build run',
      sdkConfig: SdkConfig(
        newProjectCmd: r'mkdir -p $name && cd $name && zig init',
        defaultEntryFile: 'src/main.zig',
        fileExtensions: ['zig'],
        formatCommand: 'zig fmt .',
        runCommand: 'zig run src/main.zig',
      ),
      dapConfig: DapConfig(
        adapterBinary: r'$PREFIX/bin/lldb-vscode',
        adapterArgs: [],
        adapterId: 'lldb',
        launchProgram: 'zig-out/bin/main',
        buildDoneStrings: ['stop reason', 'Loaded symbols'],
      ),
    ),

    // ── Haskell ───────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.haskell,
      verifyBinary: 'ghc',
      verifyCmd: 'ghc --version',
      cleanupScript: r'pkg uninstall -y ghc cabal-install 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y ghc cabal-install
cabal update
cabal install haskell-language-server 2>&1 || true
echo "✓ Haskell instalado: $(ghc --version)"
''',
      buildCommand: 'runghc main.hs',
      sdkConfig: SdkConfig(
        newProjectCmd: r'''mkdir -p $name && printf 'main :: IO ()\nmain = putStrLn "Hello, World!"\n' > $name/main.hs''',
        defaultEntryFile: 'main.hs',
        fileExtensions: ['hs', 'lhs', 'cabal'],
        syncCommand: 'cabal update',
        syncTriggerFile: '*.cabal',
        runCommand: 'runghc main.hs',
      ),
    ),

    // ── Elixir ────────────────────────────────────────────────────────────────
    SdkDefinition(
      type: SdkType.elixir,
      verifyBinary: 'elixir',
      verifyCmd: 'elixir --version',
      cleanupScript: 'pkg uninstall -y elixir 2>/dev/null || true',
      installScript: r'''
pkg update -y && pkg install -y elixir
mkdir -p "$HOME/.elixir-ls"
curl -fL https://github.com/elixir-lsp/elixir-ls/releases/latest/download/elixir-ls.zip \
  -o /tmp/elixir-ls.zip 2>&1
unzip -q /tmp/elixir-ls.zip -d "$HOME/.elixir-ls" && rm /tmp/elixir-ls.zip
chmod +x "$HOME/.elixir-ls/language_server.sh"
echo "✓ Elixir instalado: $(elixir --version | head -1)"
''',
      buildCommand: 'mix run',
      sdkConfig: SdkConfig(
        newProjectCmd: r'mix new $name',
        defaultEntryFile: r'lib/$name.ex',
        fileExtensions: ['ex', 'exs'],
        syncCommand: 'mix deps.get',
        syncTriggerFile: 'mix.exs',
        formatCommand: 'mix format',
        runCommand: 'mix run',
      ),
    ),

  ];

  static SdkDefinition forType(SdkType type) =>
      all.firstWhere((d) => d.type == type);
}
