import 'sdk_type.dart';

class Project {
  final String id;
  final String name;
  final SdkType sdk;
  final String path;
  final DateTime createdAt;
  DateTime lastOpenedAt;

  Project({
    required this.id,
    required this.name,
    required this.sdk,
    required this.path,
    required this.createdAt,
    required this.lastOpenedAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String,
        name: json['name'] as String,
        sdk: SdkType.values.firstWhere((e) => e.name == json['sdk']),
        path: json['path'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastOpenedAt: DateTime.parse(json['lastOpenedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sdk': sdk.name,
        'path': path,
        'createdAt': createdAt.toIso8601String(),
        'lastOpenedAt': lastOpenedAt.toIso8601String(),
      };

  Project copyWith({DateTime? lastOpenedAt}) => Project(
        id: id,
        name: name,
        sdk: sdk,
        path: path,
        createdAt: createdAt,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      );
}
