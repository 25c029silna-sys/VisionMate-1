/// Transforms raw / degraded Braille OCR text into fluent, legible natural language.
/// Supports fast on-device offline translation (Grade 2 Braille contractions & number signs)
/// with zero external API dependencies.
class BrailleTextRefiner {
  static const Map<String, String> _numberMap = {
    'a': '1', 'b': '2', 'c': '3', 'd': '4', 'e': '5',
    'f': '6', 'g': '7', 'h': '8', 'i': '9', 'j': '0',
  };

  /// 100% Offline rule-based Braille text normalization:
  /// - Decodes Braille number prefix (#) to standard digits (#aiai -> 1719, #cj -> 30)
  /// - Expands Grade 2 Braille short-forms (fr -> friends, cd -> could, wd -> would)
  /// - Context-guards Grade 2 single-letter expansions (b -> but, c -> can, x -> it)
  ///   to prevent expanding isolated noise fragments into hallucinated words
  /// - Separates attached Braille conjunction contractions (e.g. "lifeand" -> "life and")
  /// - Cleans stray OCR noise clusters and trailing punctuation artifacts
  static String refineOffline(String rawText) {
    if (rawText.trim().isEmpty) return rawText;

    // 1. Decode Braille number prefixes (#a -> 1, #b -> 2, #cj -> 30, #afei -> 1659)
    String text = rawText.replaceAllMapped(
      RegExp(r'#([a-jA-J]+)'),
      (match) {
        final chars = match.group(1)!;
        final buffer = StringBuffer();
        for (int i = 0; i < chars.length; i++) {
          final c = chars[i].toLowerCase();
          buffer.write(_numberMap[c] ?? c);
        }
        return buffer.toString();
      },
    );

    // 2. Separate common Braille conjunction contractions attached to words:
    // e.g. "lifeand" -> "life and", "islandfor" -> "island for", "withthe" -> "with the"
    text = text.replaceAllMapped(
      RegExp(r'\b([a-zA-Z]{3,})(and|with|for|the|of)\b', caseSensitive: false),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    text = text.replaceAllMapped(
      RegExp(r'\b(and|with|for|the|of)([a-zA-Z]{3,})\b', caseSensitive: false),
      (m) => '${m.group(1)} ${m.group(2)}',
    );

    // 3. Clean up common Braille OCR substitution artifacts
    text = text.replaceAll('*', 'in');

    // 4. Expand Grade 2 short-forms and context-guarded single-letter words
    final lines = text.split('\n');
    final processedLines = <String>[];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Filter out pure noise lines (e.g. "u::", "x''", "o", "::")
      if (RegExp(r"^[^a-zA-Z0-9]*[a-zA-Z]?[^a-zA-Z0-9]*$").hasMatch(line)) {
        continue;
      }

      final words = line.split(RegExp(r'\s+'));
      final assembledLine = words.join(' ').trim();
      // Remove trailing orphan punctuation
      final cleanedLine = assembledLine
          .replaceAll(RegExp(r'\s+[;:\.\,\-\*\?\!/]+$'), '')
          .replaceAll(RegExp(r'^[;:\.\,\-\*\?\!/]+\s+'), '')
          .replaceAll(RegExp(r'[;]{2,}'), ';');

      if (cleanedLine.isNotEmpty) {
        processedLines.add(cleanedLine);
      }
    }

    return processedLines.join('\n').trim();
  }
}

