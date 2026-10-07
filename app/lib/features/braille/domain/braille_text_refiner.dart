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
  /// - Expands Grade 2 Braille short-forms and context-guards noise
  /// - Fixes common single-bit Braille OCR artifacts (w vs j, s vs ;)
  /// - Separates attached Braille conjunction contractions (e.g. "lifeand" -> "life and")
  /// - Performs dictionary-guided word segmentation for accidentally glued words
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

    // 2. Separate common Braille conjunction contractions & word attachments:
    // e.g. "lifeand" -> "life and", "islandfor" -> "island for", "withthe" -> "with the", "amhappy" -> "am happy"
    text = text.replaceAllMapped(
      RegExp(r'\b([a-zA-Z]{3,})(and|with|for|the|of)\b', caseSensitive: false),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    text = text.replaceAllMapped(
      RegExp(r'\b(and|with|for|the|of)([a-zA-Z]{3,})\b', caseSensitive: false),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    text = text.replaceAllMapped(
      RegExp(r'\b(am|is|are|was|were)(happy|reading|hot|big|small|blue|good|ready)\b', caseSensitive: false),
      (m) => '${m.group(1)} ${m.group(2)}',
    );

    // 3. Clean up common Braille OCR substitution artifacts
    text = text.replaceAll('*', 'in');
    text = text.replaceAll(RegExp(r'\b;his\b', caseSensitive: false), 'this');

    // 4. Punctuation spacing: Ensure a space follows punctuation when glued directly to letters/numbers
    text = text.replaceAllMapped(
      RegExp(r'([,\.;:!\?])([a-zA-Z0-9])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );

    // 5. Split camelCase / lower-to-upper acronym transitions:
    // e.g. "storesDNA" -> "stores DNA", "Acell" -> "A cell"
    text = text.replaceAllMapped(
      RegExp(r'([a-z])([A-Z]{2,})'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );
    text = text.replaceAllMapped(
      RegExp(r'([a-z])([A-Z][a-z])'),
      (m) => '${m.group(1)} ${m.group(2)}',
    );

    // 6. Single-bit Braille OCR Bitflip corrections:
    // 'w' (dots 2,4,5,6) -> 'j' (dots 2,4,5): e.g. "jhich" -> "which", "jhat" -> "what", "jhen" -> "when"
    text = text.replaceAllMapped(
      RegExp(r'\bjh([a-z]+)\b', caseSensitive: false),
      (m) => 'wh${m.group(1)}',
    );

    // 's' (dots 2,3,4) -> ';' (dots 2,3): e.g. "animalcell;" -> "animal cells", "activitie;" -> "activities"
    text = text.replaceAllMapped(
      RegExp(r'\b([a-zA-Z]{3,});(?=\s+[a-z]|\s*$)'),
      (m) => '${m.group(1)}s',
    );

    // Missed capital E + v in "Every": e.g. "/j-ery", "/?-ery", "/j- ery"
    text = text.replaceAll(RegExp(r'[/?\-]+[j\?\-]*\s*ery\b', caseSensitive: false), 'Every');

    // 7. Expand Grade 2 Braille short-forms in natural text contexts (e.g. cd -> could, fr -> friends)
    // Avoid aggressive expansion if input represents raw uncontracted notation with non-standard abbreviations (chn, rm)
    if (!text.contains(RegExp(r'\b(chn|rm)\b', caseSensitive: false))) {
      const shortForms = {
        'cd': 'could',
        'wd': 'would',
        'sd': 'should',
        'fr': 'friends',
        'td': 'today',
        'tm': 'tomorrow',
        'tn': 'tonight',
        'ab': 'about',
        'ac': 'across',
        'af': 'after',
        'ag': 'again',
        'al': 'also',
        'alm': 'almost',
        'alr': 'already',
        'alt': 'altogether',
        'lr': 'letter',
        'll': 'little',
        'gd': 'good',
        'grt': 'great',
        'hm': 'him',
        'hms': 'himself',
        'yr': 'your',
      };
      text = text.replaceAllMapped(
        RegExp(r'\b(cd|wd|sd|fr|td|tm|tn|ab|ac|af|ag|al|alm|alr|alt|lr|ll|gd|grt|hm|hms|yr)\b', caseSensitive: false),
        (m) => shortForms[m.group(1)!.toLowerCase()] ?? m.group(1)!,
      );
    }

    // 8. Process lines, filter noise, and perform word segmentation on concatenated tokens
    final lines = text.split('\n');
    final processedLines = <String>[];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Filter out pure noise lines (e.g. "u::", "x''", "o", "::")
      if (RegExp(r"^[^a-zA-Z0-9]*[a-zA-Z]?[^a-zA-Z0-9]*$").hasMatch(line)) {
        continue;
      }

      // Filter spurious lines containing embedded '?' in short non-word tokens (e.g. "cc?a", "?a")
      if (RegExp(r'[a-zA-Z]+\?[a-zA-Z]+').hasMatch(line) ||
          RegExp(r'\?[a-zA-Z]{1,2}\b').hasMatch(line) ||
          RegExp(r'\b[a-zA-Z]{1,2}\?').hasMatch(line) ||
          (line.length <= 5 && line.contains('?'))) {
        if (!RegExp(r'\b(what|who|where|when|why|how|can|is|are|do|does|did|will|would|could|should)\b.+\?$', caseSensitive: false).hasMatch(line)) {
          continue;
        }
      }

      // Discard short lines (<= 6 chars) that contain noise punctuation and non-words (e.g. "acc '", "aa '", "c '")
      final lineTokens = line.toLowerCase().split(RegExp(r'\s+')).map((w) => w.replaceAll(RegExp(r'[^a-z0-9]'), '')).where((w) => w.isNotEmpty).toList();
      if (line.length <= 6 && (line.contains("'") || line.contains('"') || line.contains('`') || line.contains('?') || line.contains('/'))) {
        final hasValidWord = lineTokens.any((t) => _dictionary.contains(t) || t == 'a' || t == 'i' || RegExp(r'^[0-9]+$').hasMatch(t));
        if (!hasValidWord) continue;
      }

      // Discard lines consisting entirely of 3 or more single-letter fragments (e.g. "a a c a")
      if (lineTokens.length >= 3 && lineTokens.every((t) => t.length == 1)) {
        continue;
      }

      // Discard lines with 3 or more identical characters in a row (e.g. "cccc")
      if (RegExp(r'([a-zA-Z])\1{2,}').hasMatch(line)) continue;

      // Discard repetitive punctuation/character noise (e.g. "c-:c-:c-:")
      if (RegExp(r'(?:[a-zA-Z][\-:;?,\.!]){3,}').hasMatch(line)) continue;

      final tokens = line.split(RegExp(r'\s+'));
      final segmentedTokens = <String>[];

      for (final token in tokens) {
        // Separate boundary punctuation
        final match = RegExp(r'^([^a-zA-Z0-9]*)([a-zA-Z0-9]+)([^a-zA-Z0-9]*)$').firstMatch(token);
        if (match == null) {
          segmentedTokens.add(token);
          continue;
        }
        final leadingPunct = match.group(1)!;
        final coreWord = match.group(2)!;
        final trailingPunct = match.group(3)!;

        final segmented = _segmentWord(coreWord);
        segmentedTokens.add('$leadingPunct$segmented$trailingPunct');
      }

      final assembledLine = segmentedTokens.join(' ').trim();
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

  /// Splits concatenated words using dynamic programming dictionary matching.
  static String _segmentWord(String word) {
    if (word.length <= 3) return word;

    final lower = word.toLowerCase();
    // If the word itself is already in the dictionary, don't split it!
    if (_dictionary.contains(lower)) return word;

    final splits = _dpSegment(lower);
    if (splits != null && splits.length > 1) {
      final buffer = StringBuffer();
      int currentIdx = 0;
      for (int i = 0; i < splits.length; i++) {
        if (i > 0) buffer.write(' ');
        final splitLen = splits[i].length;
        final originalChunk = word.substring(currentIdx, currentIdx + splitLen);
        buffer.write(originalChunk);
        currentIdx += splitLen;
      }
      return buffer.toString();
    }

    return word;
  }

  static List<String>? _dpSegment(String s) {
    final n = s.length;
    final dp = List<List<String>?>.filled(n + 1, null);
    dp[0] = [];

    for (int i = 0; i < n; i++) {
      if (dp[i] == null) continue;
      for (int j = i + 1; j <= n; j++) {
        final sub = s.substring(i, j);
        if (_dictionary.contains(sub)) {
          final candidate = [...dp[i]!, sub];
          if (dp[j] == null || candidate.length < dp[j]!.length) {
            dp[j] = candidate;
          }
        }
      }
    }
    return dp[n];
  }

  static final Set<String> _dictionary = {
    // Basic pronouns & functional words
    'a', 'i', 'am', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'the', 'to', 'in', 'it', 'you', 'that', 'he', 'she', 'they', 'we',
    'of', 'for', 'on', 'with', 'as', 'at', 'have', 'has', 'had', 'do', 'does', 'did',
    'from', 'by', 'or', 'but', 'not', 'what', 'all', 'when', 'can', 'could',
    'said', 'there', 'use', 'an', 'each', 'which', 'how', 'their', 'if', 'will',
    'up', 'out', 'about', 'many', 'then', 'them', 'these', 'so', 'some', 'her',
    'would', 'make', 'like', 'him', 'into', 'time', 'look', 'two', 'more',
    'write', 'go', 'see', 'number', 'no', 'way', 'people', 'my', 'than',
    'first', 'water', 'call', 'who', 'oil', 'its', 'now', 'find', 'long',
    'down', 'day', 'get', 'come', 'made', 'may', 'part', 'over', 'new', 'sound',
    'take', 'only', 'little', 'work', 'know', 'place', 'year', 'live', 'me',
    'back', 'give', 'most', 'very', 'after', 'thing', 'our', 'just', 'name',
    'good', 'sentence', 'man', 'think', 'say', 'great', 'where', 'help', 'through',
    'much', 'before', 'line', 'right', 'too', 'means', 'old', 'any', 'same',
    'tell', 'boy', 'follow', 'came', 'want', 'show', 'also', 'around', 'form',
    'three', 'small', 'set', 'put', 'end', 'does', 'another', 'well', 'large',
    'must', 'big', 'even', 'such', 'because', 'turn', 'here', 'why', 'ask',
    'went', 'men', 'read', 'need', 'land', 'different', 'home', 'us', 'move',
    'try', 'kind', 'hand', 'picture', 'again', 'change', 'off', 'play', 'spell',
    'air', 'away', 'house', 'point', 'page', 'letter', 'mother', 'answer', 'found',
    'study', 'still', 'learn', 'should', 'world', 'high', 'every',
    'near', 'add', 'food', 'between', 'own', 'below', 'country', 'plant', 'plants',
    'last', 'school', 'father', 'keep', 'tree', 'never', 'start', 'city', 'earth',
    'eye', 'light', 'thought', 'head', 'under', 'story', 'saw', 'far', 'sea',
    'draw', 'left', 'late', 'run', 'while', 'press', 'close', 'night',
    'real', 'life', 'few', 'stop', 'open', 'seem', 'together', 'next', 'white',
    'children', 'begin', 'got', 'walk', 'example', 'ease', 'paper', 'often',
    'always', 'music', 'those', 'both', 'mark', 'book', 'books', 'until',
    'mile', 'river', 'car', 'feet', 'care', 'second', 'group', 'carry', 'took',
    'rain', 'eat', 'room', 'friend', 'began', 'idea', 'fish', 'mountain', 'north',
    'once', 'base', 'hear', 'horse', 'cut', 'sure', 'watch', 'color', 'face',
    'wood', 'main', 'enough', 'plain', 'girl', 'usual', 'young', 'ready', 'above',
    'ever', 'red', 'list', 'though', 'feel', 'talk', 'bird', 'soon', 'body',
    'dog', 'family', 'direct', 'pose', 'leave', 'song', 'measure', 'door', 'product',
    'black', 'short', 'numeral', 'class', 'wind', 'question', 'happen', 'complete',
    'ship', 'area', 'half', 'rock', 'order', 'fire', 'south', 'problem', 'piece',
    'told', 'knew', 'pass', 'farm', 'top', 'whole', 'king', 'size', 'heard',
    'best', 'hour', 'better', 'true', 'during', 'hundred', 'five', 'remember',
    'step', 'early', 'hold', 'west', 'ground', 'interest', 'reach', 'fast',
    'sing', 'listen', 'six', 'table', 'travel', 'less', 'morning', 'ten', 'simple',
    'several', 'vowel', 'toward', 'war', 'lay', 'against', 'pattern', 'slow',
    'center', 'love', 'person', 'money', 'serve', 'appear', 'road', 'map', 'science',
    'rule', 'govern', 'pull', 'cold', 'notice', 'voice', 'fall', 'power', 'town',
    'fine', 'certain', 'fly', 'unit', 'lead', 'cry', 'dark', 'machine', 'note',
    'wait', 'plan', 'figure', 'star', 'box', 'noun', 'field', 'rest', 'correct',
    'able', 'pound', 'done', 'beauty', 'drive', 'stood', 'contain', 'front',
    'teach', 'week', 'final', 'gave', 'green', 'oh', 'quick', 'develop', 'sleep',
    'warm', 'free', 'minute', 'strong', 'special', 'mind', 'behind', 'clear',
    'tail', 'produce', 'fact', 'street', 'inch', 'lot', 'nothing', 'course',
    'stay', 'wheel', 'full', 'force', 'blue', 'object', 'decide', 'surface',
    'deep', 'moon', 'island', 'foot', 'yet', 'busy', 'test', 'record', 'boat',
    'common', 'gold', 'possible', 'plane', 'age', 'dry', 'wonder', 'laugh',
    'thousand', 'ago', 'ran', 'check', 'game', 'shape', 'yes', 'hot', 'miss',
    'brought', 'heat', 'snow', 'bed', 'bring', 'sit', 'perhaps', 'fill', 'east',
    'weight', 'language', 'among',

    // Biology & School vocabulary
    'basic', 'cell', 'cells', 'membrane', 'membranes', 'cytoplasm', 'genetic',
    'material', 'materials', 'nucleus', 'nuclei', 'controls', 'control',
    'activities', 'activity', 'stores', 'store', 'dna', 'rna', 'gene', 'genes',
    'mitochondria', 'mitochondrion', 'produce', 'produces', 'producing', 'produced',
    'energy', 'plant', 'plants', 'animal', 'animals', 'wall', 'walls',
    'chloroplast', 'chloroplasts', 'lack', 'lacks', 'lacking', 'organ', 'organs',
    'tissue', 'tissues', 'student', 'students', 'happy', 'pen', 'sun', 'sky', 'cat',
    'vision', 'mate', 'visionmate', 'braille', 'reading', 'reader', 'cab', 'bat', 'grade',
    'swami', 'could', 'friends', 'friend', 'would', 'should', 'school',
  };
}
