class CommandRouter {
  /// Intent keyword maps ordered by deterministic tie-breaking priority:
  /// Emergency > Guide > Braille > OCR > Scene > Library > Home
  static const Map<String, List<String>> _intentKeywords = {
    '/emergency': ['emergency', 'sos', 'panic', 'help me', 'danger', 'distress'],
    '/guide': ['guide', 'help', 'commands', 'list commands', 'what can i say', 'voice guide', 'talkback'],
    '/braille': ['braille', 'brail', 'tactile'],
    '/ocr': ['ocr', 'read text', 'read document', 'read page', 'scan text', 'text reader', 'read', 'scan', 'capture'],
    '/scene': ['scene', 'surroundings', 'navigate', 'navigation', 'obstacle', 'environment', 'describe'],
    '/library': ['library', 'smart library', 'digital library', 'semantic search', 'document search', 'search', 'find document'],
    '/': ['home', 'go home', 'main screen', 'back to main'],
  };

  /// Normalizes input text by lowercasing and stripping special punctuation.
  String _normalize(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
  }

  /// Resolves spoken command to a destination route path or returns null if unmatched.
  String? routeForCommand(String command) {
    final normalized = _normalize(command);
    if (normalized.isEmpty) return null;

    for (final entry in _intentKeywords.entries) {
      final route = entry.key;
      final keywords = entry.value;

      for (final keyword in keywords) {
        if (normalized.contains(keyword)) {
          return route;
        }
      }
    }
    return null;
  }

  /// Static helper delegating to instance method
  static String? routeCommand(String command) => CommandRouter().routeForCommand(command);
}


