class ParsedContact {
  final String name;
  final String phone;

  const ParsedContact({required this.name, required this.phone});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParsedContact &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          phone == other.phone;

  @override
  int get hashCode => name.hashCode ^ phone.hashCode;

  @override
  String toString() => 'ParsedContact(name: "$name", phone: "$phone")';
}

/// Helper and parser for voice-activated emergency contact management in VisionMate.
/// Provides robust spoken phone number normalization, speech-friendly formatting,
/// one-shot command extraction, and conversational intent classification.
class EmergencyContactVoiceHelper {
  static const Map<String, String> _wordToDigit = {
    'zero': '0',
    'oh': '0',
    'o': '0',
    'one': '1',
    'won': '1',
    'two': '2',
    'to': '2',
    'too': '2',
    'three': '3',
    'four': '4',
    'for': '4',
    'fore': '4',
    'five': '5',
    'six': '6',
    'seven': '7',
    'eight': '8',
    'ate': '8',
    'nine': '9',
    'ten': '10',
    'eleven': '11',
    'twelve': '12',
    'thirteen': '13',
    'fourteen': '14',
    'fifteen': '15',
    'sixteen': '16',
    'seventeen': '17',
    'eighteen': '18',
    'nineteen': '19',
    'twenty': '20',
    'thirty': '30',
    'forty': '40',
    'fourty': '40',
    'fifty': '50',
    'sixty': '60',
    'seventy': '70',
    'eighty': '80',
    'ninety': '90',
  };

  static const Map<String, String> _singleDigitWords = {
    'zero': '0',
    'oh': '0',
    'o': '0',
    'one': '1',
    'two': '2',
    'three': '3',
    'four': '4',
    'five': '5',
    'six': '6',
    'seven': '7',
    'eight': '8',
    'nine': '9',
    '0': '0',
    '1': '1',
    '2': '2',
    '3': '3',
    '4': '4',
    '5': '5',
    '6': '6',
    '7': '7',
    '8': '8',
    '9': '9',
  };

  /// Affirmative confirmation keywords for voice dialogues
  static const List<String> confirmationKeywords = [
    'confirm',
    'yes',
    'save',
    'ok',
    'okay',
    'correct',
    'proceed',
    'done',
    'sure',
    'yeah',
    'yep',
    'affirmative',
    'right',
    'sounds good',
  ];

  /// Cancellation and exit keywords for voice dialogues
  static const List<String> cancellationKeywords = [
    'cancel',
    'stop',
    'abort',
    'wait',
    'no',
    'exit',
    'discard',
    'nevermind',
    'never mind',
    'back',
    'dismiss',
    'close',
  ];

  /// Keep / skip keywords when editing an existing contact field
  static const List<String> keepKeywords = [
    'keep',
    'skip',
    'same',
    'leave',
    'no change',
    'leave it',
    'stay',
    'keep it',
    'keep current',
  ];

  /// Checks if an utterance expresses confirmation (e.g. "confirm", "yes", "save")
  static bool isConfirmation(String text) {
    final lower = text.toLowerCase().trim();
    for (final word in confirmationKeywords) {
      if (word.length <= 3) {
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

  /// Checks if an utterance expresses cancellation or abort
  static bool isCancellation(String text) {
    final lower = text.toLowerCase().trim();
    for (final word in cancellationKeywords) {
      if (word.length <= 2) {
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

  /// Checks if an utterance indicates keeping the current value unchanged
  static bool isKeepOrSkip(String text) {
    final lower = text.toLowerCase().trim();
    for (final word in keepKeywords) {
      if (RegExp(r'\b' + RegExp.escape(word) + r'\b').hasMatch(lower)) {
        return true;
      }
    }
    return false;
  }

  /// Checks if an utterance triggers emergency contact configuration
  static bool isContactCommand(String text) {
    final lower = text.toLowerCase().trim();
    final patterns = [
      'contact',
      'add contact',
      'edit contact',
      'change contact',
      'update contact',
      'configure contact',
      'new contact',
      'set contact',
      'save contact',
      'trusted contact',
      'emergency contact',
    ];
    for (final p in patterns) {
      if (lower.contains(p)) {
        return true;
      }
    }
    return false;
  }

  /// Normalizes spoken speech or transcribed text into a clean phone number.
  /// Handles word numbers ("nine eight seven six"), double/triple multipliers ("double five"),
  /// international prefix indicators ("plus"), dashes, spaces, and punctuation.
  static String parseSpokenPhoneNumber(String input) {
    if (input.trim().isEmpty) return '';

    String cleaned = input.toLowerCase().trim();

    // Check for leading plus indicator
    bool hasLeadingPlus = cleaned.startsWith('+') ||
        cleaned.startsWith('plus') ||
        cleaned.contains(RegExp(r'^\s*plus\b'));

    // Replace filler words
    cleaned = cleaned.replaceAll(RegExp(r'\b(my|the|phone|number|is|at|call|mobile|cell|to|please)\b'), ' ');

    // Normalize double / triple digit words:
    // e.g. "double five" -> "55", "triple zero" -> "000"
    for (final entry in _singleDigitWords.entries) {
      final word = entry.key;
      final digit = entry.value;
      cleaned = cleaned.replaceAll(RegExp(r'\bdouble\s+' + word + r'\b'), '$digit$digit');
      cleaned = cleaned.replaceAll(RegExp(r'\btriple\s+' + word + r'\b'), '$digit$digit$digit');
    }

    // Replace number words with digits
    final tokens = cleaned.split(RegExp(r'[\s,\-]+'));
    final buffer = StringBuffer();

    for (final token in tokens) {
      final t = token.trim();
      if (t.isEmpty) continue;

      if (t == 'plus' || t == '+') {
        if (buffer.isEmpty) {
          hasLeadingPlus = true;
        }
        continue;
      }

      if (_wordToDigit.containsKey(t)) {
        buffer.write(_wordToDigit[t]);
      } else if (RegExp(r'^\d+$').hasMatch(t)) {
        buffer.write(t);
      } else {
        // Remove non-digit characters if token contains embedded numbers
        final digits = t.replaceAll(RegExp(r'[^\d]'), '');
        if (digits.isNotEmpty) {
          buffer.write(digits);
        }
      }
    }

    String resultDigits = buffer.toString();
    if (resultDigits.isEmpty) return '';

    return hasLeadingPlus ? '+$resultDigits' : resultDigits;
  }

  /// Formats a phone number for clear, distinct TTS speech output.
  /// Instead of reading 1234567890 as "one billion two hundred...",
  /// formats digits with spaces: "1 2 3 4 5 6 7 8 9 0", and "+" as "plus ".
  static String formatPhoneNumberForSpeech(String phone) {
    if (phone.trim().isEmpty) return 'none';

    final buffer = StringBuffer();
    final trimmed = phone.trim();

    for (int i = 0; i < trimmed.length; i++) {
      final char = trimmed[i];
      if (char == '+') {
        buffer.write('plus ');
      } else if (RegExp(r'\d').hasMatch(char)) {
        buffer.write('$char ');
      }
    }

    return buffer.toString().trim();
  }

  /// Cleans spoken name utterance, removing common conversational filler phrases.
  /// Capitalizes each word for clean UI presentation.
  static String cleanSpokenName(String raw) {
    if (raw.trim().isEmpty) return '';

    String cleaned = raw.trim();
    // Strip common filler prefixes
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(my\s+)?(contact(\s+name)?|name)(\s+is)?\s+', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceFirst(
      RegExp(r"^(it\s+is|it\'s|it’s|call\s+them|set\s+it\s+to|please\s+use|use)\s+", caseSensitive: false),
      '',
    );
    // Strip trailing punctuation
    cleaned = cleaned.replaceAll(RegExp(r'[^\w\s]'), '').trim();

    if (cleaned.isEmpty) return '';

    // Title case words
    return cleaned.split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + (w.length > 1 ? w.substring(1).toLowerCase() : '');
    }).join(' ');
  }

  /// Parses a one-shot voice command containing both contact name and phone number.
  /// Examples:
  /// - "add contact Mom 1234567890"
  /// - "set contact John Doe 9876543210"
  /// - "edit contact Doctor at 555-1234"
  /// - "emergency contact Jane +15551234567"
  /// Returns [ParsedContact] if both fields could be extracted, or null if interactive
  /// flow should be used instead.
  static ParsedContact? parseDirectCommand(String utterance) {
    final lower = utterance.toLowerCase().trim();

    // Check for contact command triggers
    final triggerPrefixes = [
      'add emergency contact',
      'set emergency contact',
      'edit emergency contact',
      'update emergency contact',
      'change emergency contact',
      'configure emergency contact',
      'save emergency contact',
      'emergency contact',
      'add contact',
      'set contact',
      'edit contact',
      'update contact',
      'change contact',
      'configure contact',
      'save contact',
      'new contact',
    ];

    String? payload;
    for (final prefix in triggerPrefixes) {
      final index = lower.indexOf(prefix);
      if (index != -1) {
        payload = utterance.substring(index + prefix.length).trim();
        break;
      }
    }

    if (payload == null || payload.isEmpty) {
      return null;
    }

    // Remove leading connectors like "to", "named", "as"
    payload = payload.replaceFirst(RegExp(r'^(to|named|as)\s+', caseSensitive: false), '').trim();

    // Look for phone number separator keywords like "phone", "number", "at", "with number"
    final phoneSeparators = [
      RegExp(r'\s+(phone\s+number\s+is|phone\s+number|phone\s+is|phone|number\s+is|number|mobile\s+is|mobile|at)\s+', caseSensitive: false),
    ];

    for (final sep in phoneSeparators) {
      final match = sep.firstMatch(payload);
      if (match != null) {
        final namePart = payload.substring(0, match.start).trim();
        final phonePart = payload.substring(match.end).trim();

        final cleanName = cleanSpokenName(namePart);
        final parsedPhone = parseSpokenPhoneNumber(phonePart);

        if (cleanName.isNotEmpty && parsedPhone.length >= 3) {
          return ParsedContact(name: cleanName, phone: parsedPhone);
        }
      }
    }

    // If no explicit separator word, check if trailing words are digits / number words
    final words = payload.split(RegExp(r'\s+'));
    int splitIndex = -1;

    for (int i = 0; i < words.length; i++) {
      final w = words[i].toLowerCase().replaceAll(RegExp(r'[^\w+]'), '');
      if (RegExp(r'^\+?\d+$').hasMatch(w) ||
          _wordToDigit.containsKey(w) ||
          w == 'double' ||
          w == 'triple' ||
          w == 'plus') {
        splitIndex = i;
        break;
      }
    }

    if (splitIndex > 0) {
      final namePart = words.sublist(0, splitIndex).join(' ');
      final phonePart = words.sublist(splitIndex).join(' ');

      final cleanName = cleanSpokenName(namePart);
      final parsedPhone = parseSpokenPhoneNumber(phonePart);

      if (cleanName.isNotEmpty && parsedPhone.length >= 3) {
        return ParsedContact(name: cleanName, phone: parsedPhone);
      }
    }

    return null;
  }
}
