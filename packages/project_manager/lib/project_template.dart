import 'package:core/core.dart';
import 'package:sdk_manager/sdk_manager.dart';

class ProjectTemplate {
  final SdkType sdk;

  const ProjectTemplate(this.sdk);

  String createCommand(String projectName, String parentDir) {
    final def = SdkDefinition.forType(sdk);
    final cmd = def.newProjectCmd.replaceAll(r'$name', projectName);
    return 'cd "$parentDir" && $cmd';
  }

  static ProjectTemplate forSdk(SdkType sdk) => ProjectTemplate(sdk);
}
