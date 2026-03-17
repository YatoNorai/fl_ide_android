enum SdkType {
  flutter,
  androidSdk,
  reactNative,
  nodejs,
  python;

  String get displayName {
    switch (this) {
      case SdkType.flutter:
        return 'Flutter';
      case SdkType.androidSdk:
        return 'Android SDK';
      case SdkType.reactNative:
        return 'React Native';
      case SdkType.nodejs:
        return 'Node.js';
      case SdkType.python:
        return 'Python';
    }
  }

  String get icon {
    switch (this) {
      case SdkType.flutter:
        return '🐦';
      case SdkType.androidSdk:
        return '🤖';
      case SdkType.reactNative:
        return '⚛️';
      case SdkType.nodejs:
        return '🟩';
      case SdkType.python:
        return '🐍';
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
    }
  }
}
