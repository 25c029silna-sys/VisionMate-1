class CommandRouter {
  /// Intent keyword maps ordered by deterministic tie-breaking priority:
  /// Emergency > Guide > Braille > OCR > Scene > Library > Home
  static const Map<String, List<String>> _intentKeywords = {
    '/emergency': ['emergency', 'sos', 'panic', 'help', 'danger', 'distress'],
    '/guide': ['guide', 'voice guide', 'commands', 'list commands', 'what can i say', 'talkback'],
    '/braille': ['braille', 'brail', 'tactile'],
    '/ocr': ['ocr', 'read text', 'read document', 'read page', 'scan text', 'text reader', 'read', 'scan', 'capture'],
    '/scene': ['scene', 'surroundings', 'navigate', 'navigation', 'obstacle', 'environment', 'describe'],
    '/library': ['library', 'smart library', 'digital library', 'semantic search', 'document search', 'search', 'find document'],
    '/': ['home', 'go home', 'main screen', 'back to main'],
  };

  /// Wake-word trigger phrases for global activation
  static const List<String> wakeWordPhrases = [
    'visionmate',
    'vision mate',
    'hey visionmate',
    'hey vision mate',
    'ok visionmate',
    'ok vision mate',
  ];

  /// Cancellation keywords for emergency SOS and active operations
  static const List<String> cancellationKeywords = [
    'cancel',
    'stop',
    'abort',
    'wait',
    'no',
    'nevermind',
    'false alarm',
    'hold',
    'exit',
  ];

  /// Checks if [text] contains any emergency cancellation keyword.
  static bool isCancellationCommand(String text) {
    final lower = text.toLowerCase().trim();
    for (final word in cancellationKeywords) {
      if (word.length <= 2) {
        // Use word boundary for short words (like 'no') to prevent false matches on 'now', 'know', etc.
        if (RegExp(r'\b' + RegExp.escape(word) + r'\b').hasMatch(lower)) {
          return true;
        }
      } else {
        if (lower.contains(word)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Checks if [text] begins with or contains the global wake word "VisionMate".
  static bool containsWakeWord(String text) {
    final lower = text.toLowerCase().trim();
    for (final phrase in wakeWordPhrases) {
      if (lower.contains(phrase)) {
        return true;
      }
    }
    return false;
  }

  /// Strips wake word phrases from the input command to isolate the actual request.
  static String extractCommandAfterWakeWord(String text) {
    String cleaned = text.toLowerCase().trim();
    for (final phrase in wakeWordPhrases) {
      if (cleaned.startsWith(phrase)) {
        cleaned = cleaned.substring(phrase.length).trim();
        break;
      }
    }
    // Also remove any leading connecting words like 'please', 'can you', etc.
    cleaned = cleaned.replaceFirst(RegExp(r'^(please|open|go to|show)\s+'), '').trim();
    return cleaned;
  }

  /// Normalizes input text by lowercasing and stripping special punctuation.
  String _normalize(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
  }

  /// Resolves spoken command to a destination route path or returns null if unmatched.
  String? routeForCommand(String command) {
    final normalized = _normalize(command);
    if (normalized.isEmpty) return null;

    // Check direct intent match first
    for (final entry in _intentKeywords.entries) {
      final route = entry.key;
      final keywords = entry.value;

      for (final keyword in keywords) {
        if (normalized.contains(keyword)) {
          return route;
        }
      }
    }

    // Strip wake word prefix if present and re-evaluate
    final stripped = extractCommandAfterWakeWord(normalized);
    if (stripped.isNotEmpty && stripped != normalized) {
      for (final entry in _intentKeywords.entries) {
        final route = entry.key;
        final keywords = entry.value;

        for (final keyword in keywords) {
          if (stripped.contains(keyword)) {
            return route;
          }
        }
      }
    }

    return null;
  }

  /// Static helper delegating to instance method
  static String? routeCommand(String command) => CommandRouter().routeForCommand(command);
}


