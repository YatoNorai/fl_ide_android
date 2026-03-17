/// Metadata for a downloadable theme extension (from index.json).
class ExtensionThemeMeta {
  final String id;
  final String name;
  final String file;
  final bool dark;
  final String preview; // hex color for the preview swatch

  const ExtensionThemeMeta({
    required this.id,
    required this.name,
    required this.file,
    required this.dark,
    required this.preview,
  });

  factory ExtensionThemeMeta.fromJson(Map<String, dynamic> j) =>
      ExtensionThemeMeta(
        id: j['id'] as String,
        name: j['name'] as String,
        file: j['file'] as String,
        dark: j['dark'] as bool? ?? true,
        preview: j['preview'] as String? ?? '#1E1E2E',
      );

  /// Parse hex preview into a Color value (ARGB int).
  int get previewArgb {
    final s = preview.replaceFirst('#', '');
    final hex = s.length == 6 ? 'FF$s' : s;
    return int.tryParse(hex, radix: 16) ?? 0xFF1E1E2E;
  }
}
