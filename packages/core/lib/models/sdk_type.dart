enum SdkType {
  flutter,
  androidSdk,
  reactNative,
  nodejs,
  python,
  swift,
  go,
  // ── New SDKs ──────────────────────────────────────────────────────────────
  kotlinMultiplatform,
  cpp,
  rust,
  lua,
  ruby,
  php,
  bash,
  htmlCss,
  csharp,
  scala,
  r,
  zig,
  haskell,
  elixir;

  String get displayName {
    switch (this) {
      case SdkType.flutter:             return 'Flutter';
      case SdkType.androidSdk:          return 'Android SDK';
      case SdkType.reactNative:         return 'React Native';
      case SdkType.nodejs:              return 'Node.js';
      case SdkType.python:              return 'Python';
      case SdkType.swift:               return 'Swift';
      case SdkType.go:                  return 'Go';
      case SdkType.kotlinMultiplatform: return 'Kotlin Multiplatform';
      case SdkType.cpp:                 return 'C / C++';
      case SdkType.rust:                return 'Rust';
      case SdkType.lua:                 return 'Lua';
      case SdkType.ruby:                return 'Ruby';
      case SdkType.php:                 return 'PHP';
      case SdkType.bash:                return 'Bash / Shell';
      case SdkType.htmlCss:             return 'HTML / CSS';
      case SdkType.csharp:              return 'C# (.NET)';
      case SdkType.scala:               return 'Scala';
      case SdkType.r:                   return 'R';
      case SdkType.zig:                 return 'Zig';
      case SdkType.haskell:             return 'Haskell';
      case SdkType.elixir:              return 'Elixir';
    }
  }

  String get icon {
    switch (this) {
      case SdkType.flutter:             return '🐦';
      case SdkType.androidSdk:          return '🤖';
      case SdkType.reactNative:         return '⚛️';
      case SdkType.nodejs:              return '🟩';
      case SdkType.python:              return '🐍';
      case SdkType.swift:               return '🦅';
      case SdkType.go:                  return '🐹';
      case SdkType.kotlinMultiplatform: return '🎯';
      case SdkType.cpp:                 return '⚙️';
      case SdkType.rust:                return '🦀';
      case SdkType.lua:                 return '🌙';
      case SdkType.ruby:                return '💎';
      case SdkType.php:                 return '🐘';
      case SdkType.bash:                return '🖥️';
      case SdkType.htmlCss:             return '🌐';
      case SdkType.csharp:              return '🔷';
      case SdkType.scala:               return '🔴';
      case SdkType.r:                   return '📊';
      case SdkType.zig:                 return '⚡';
      case SdkType.haskell:             return 'λ';
      case SdkType.elixir:              return '💜';
    }
  }

  String get description {
    switch (this) {
      case SdkType.flutter:
        return 'Build cross-platform apps with Flutter ARM64';
      case SdkType.androidSdk:
        return 'Native Android development with Gradle';
      case SdkType.reactNative:
        return 'Cross-platform apps with React Native';
      case SdkType.nodejs:
        return 'JavaScript/TypeScript runtime';
      case SdkType.python:
        return 'Python 3 scripting and apps';
      case SdkType.swift:
        return 'Swift scripting and server-side apps';
      case SdkType.go:
        return 'Go com gopls LSP e Delve debugger';
      case SdkType.kotlinMultiplatform:
        return 'Kotlin Multiplatform — compartilhe código entre Android, iOS e Desktop';
      case SdkType.cpp:
        return 'C e C++ com clangd LSP e lldb-dap debugger';
      case SdkType.rust:
        return 'Rust com rust-analyzer LSP e lldb-dap debugger';
      case SdkType.lua:
        return 'Lua com lua-language-server LSP';
      case SdkType.ruby:
        return 'Ruby com Solargraph LSP';
      case SdkType.php:
        return 'PHP com Intelephense LSP';
      case SdkType.bash:
        return 'Bash/Shell scripting com bash-language-server';
      case SdkType.htmlCss:
        return 'HTML, CSS e SCSS com vscode-langservers LSP';
      case SdkType.csharp:
        return 'C# e .NET com csharp-ls LSP';
      case SdkType.scala:
        return 'Scala com Metals LSP';
      case SdkType.r:
        return 'R para ciência de dados com r-languageserver';
      case SdkType.zig:
        return 'Zig com zls LSP';
      case SdkType.haskell:
        return 'Haskell com HLS (Haskell Language Server)';
      case SdkType.elixir:
        return 'Elixir/Phoenix com ElixirLS LSP';
    }
  }
}
