/// Metadata for a downloadable theme extension (from index.json).
class ExtensionThemeMeta {
  final String id;
  final String name;
  final String file;
  final bool dark;
  final String preview; // hex background color
  final String accent;  // hex accent/cursor color

  const ExtensionThemeMeta({
    required this.id,
    required this.name,
    required this.file,
    required this.dark,
    required this.preview,
    required this.accent,
  });

  factory ExtensionThemeMeta.fromJson(Map<String, dynamic> j) =>
      ExtensionThemeMeta(
        id: j['id'] as String,
        name: j['name'] as String,
        file: j['file'] as String,
        dark: j['dark'] as bool? ?? true,
        preview: j['preview'] as String? ?? '#1E1E2E',
        accent: j['accent'] as String? ?? '#89B4FA',
      );

  int get previewArgb => _parseHex(preview, 0xFF1E1E2E);
  int get accentArgb  => _parseHex(accent,  0xFF89B4FA);

  static int _parseHex(String hex, int fallback) {
    final s = hex.replaceFirst('#', '');
    final full = s.length == 6 ? 'FF$s' : s;
    return int.tryParse(full, radix: 16) ?? fallback;
  }
}
