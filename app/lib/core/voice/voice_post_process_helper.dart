/// Helper for handling voice-activated post-process options across VisionMate modules.
/// When a module completes its primary process (e.g. OCR text extraction, Braille scan,
/// Scene navigation description, Digital Library search, or Emergency contact setup),
/// this helper classifies the user's spoken intent to either repeat the action ("again")
/// or return to the main screen ("home").
class VoicePostProcessHelper {
  /// Keywords and phrases indicating the user wants to perform the process again.
  static const List<String> repeatKeywords = [
    'again',
    'repeat',
    'retry',
    'redo',
    'more',
    'another',
    'scan',
    'capture',
    'search',
    'describe',
    'edit',
    'reread',
    'continue',
  ];

  /// Multi-word phrases indicating repeat intent.
  static const List<String> repeatPhrases = [
    'one more',
    'do it again',
    'try again',
    'scan again',
    'search again',
    'read again',
    'describe again',
    'once more',
    'edit again',
  ];

  /// Keywords and phrases indicating the user wants to return home or exit.
  static const List<String> homeKeywords = [
    'home',
    'back',
    'exit',
    'close',
    'main',
    'menu',
    'leave',
    'quit',
    'return',
  ];

  /// Multi-word phrases indicating home / exit intent.
  static const List<String> homePhrases = [
    'go home',
    'back home',
    'main menu',
    'go back',
    'back to main',
    'return home',
    'take me home',
    'exit module',
  ];

  /// Evaluates whether the spoken input indicates an intent to repeat or perform the process again.
  static bool isRepeatOrAgain(String? input) {
    if (input == null || input.trim().isEmpty) return false;
    final lower = input.toLowerCase().trim();

    for (final phrase in repeatPhrases) {
      if (lower.contains(phrase)) return true;
    }

    final tokens = lower.replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ').split(RegExp(r'\s+'));
    return tokens.any((t) => repeatKeywords.contains(t));
  }

  /// Evaluates whether the spoken input indicates an intent to return home or exit.
  static bool isHomeOrExit(String? input) {
    if (input == null || input.trim().isEmpty) return false;
    final lower = input.toLowerCase().trim();

    for (final phrase in homePhrases) {
      if (lower.contains(phrase)) return true;
    }

    final tokens = lower.replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ').split(RegExp(r'\s+'));
    return tokens.any((t) => homeKeywords.contains(t));
  }

  /// Generates an accessible auditory prompt for post-process options.
  static String formatPrompt(String actionDescription) {
    return 'Say again to $actionDescription, or say home to return to the main menu.';
  }
}
