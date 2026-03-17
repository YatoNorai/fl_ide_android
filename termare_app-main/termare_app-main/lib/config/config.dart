import 'package:global_repository/global_repository.dart';

class Config {
  Config._();
  static String bashPath = '${RuntimeEnvir.binPath}/bash';
  static String packageName = 'com.flutteride.android';
  // flutter package名，因为这个会影响assets的路径
  static String flutterPackage = '';
}
