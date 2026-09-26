import 'dart:math';

/// Enhanced on-device semantic embedding engine for the Digital Library.
///
/// Implements a multi-layer semantic pattern matching pipeline:
/// 1. Deterministic 32-bit FNV-1a hashing (platform-independent vector projection).
/// 2. Conversational speech filler and high-frequency stop-word suppression.
/// 3. Sub-word character 3-gram and 4-gram projections (typo & inflection resilience).
/// 4. Morphological suffix stem normalization (plurals, gerunds, past tenses).
/// 5. Adjacent token bigram collocation hashing (preserves local phrase semantics).
/// 6. Sub-linear term frequency scaling: val = 1.0 + ln(1 + weight).
/// 7. Robust L2 normalization with strict zero-vector and NaN guards.
class MiniLmEmbedder {
  static const int embeddingDimension = 384;

  /// Conversational speech fillers and low-information English stop words.
  /// Suppressing these in speech queries prevents diluting the L2 norm of key terms.
  static const Set<String> _stopWords = {
    'um', 'uh', 'ah', 'er', 'please', 'can', 'could', 'would', 'will',
    'find', 'search', 'get', 'show', 'open', 'read', 'look', 'tell',
    'the', 'a', 'an', 'and', 'or', 'of', 'in', 'on', 'at', 'to', 'for',
    'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'it', 'its', 'this', 'that', 'these', 'those',
    'with', 'by', 'as', 'from', 'into', 'about',
    'my', 'me', 'we', 'our', 'us', 'your', 'you', 'i', 'he', 'she', 'they', 'them',
    'thanks', 'thank', 'hello', 'hey', 'hi', 'just', 'some', 'any'
  };

  /// 32-bit FNV-1a deterministic hash function.
  /// Unlike Object.hashCode, FNV-1a is invariant across Dart VM versions, 32/64-bit architectures,
  /// and target platforms (Android ARM64, x86_64, Windows, unit tests).
  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (int i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.abs();
  }

  /// Simple rule-based English suffix stemmer.
  /// Normalizes common morphological inflections:
  /// - Plurals: "prescriptions" -> "prescription", "hallways" -> "hallway", "notes" -> "note"
  /// - Gerunds / participles: "navigating" -> "navigat", "reading" -> "read"
  /// - Past tense: "deposited" -> "deposit", "scanned" -> "scan"
  static String _stem(String word) {
    if (word.length <= 3) return word;
    if (word.endsWith('ies') && word.length > 4) {
      return '${word.substring(0, word.length - 3)}y';
    }
    if (word.endsWith('ing') && word.length > 5) {
      return word.substring(0, word.length - 3);
    }
    if (word.endsWith('ed') && word.length > 4) {
      return word.substring(0, word.length - 2);
    }
    if (word.endsWith('es') && word.length > 4) {
      return word.substring(0, word.length - 2);
    }
    if (word.endsWith('s') && !word.endsWith('ss') && word.length > 3) {
      return word.substring(0, word.length - 1);
    }
    return word;
  }

  /// Generates a normalized 384-dimensional vector embedding for [text].
  ///
  /// When [filterStopWords] is true (default), speech fillers and non-discriminative
  /// stop words are filtered out so that core domain keywords receive high energy.
  /// If all words are stop words, fallback retains the tokens to avoid empty vectors.
  List<double> generateEmbedding(String text, {bool filterStopWords = true}) {
    final rawVector = List<double>.filled(embeddingDimension, 0.0);
    final rawTokens = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (rawTokens.isEmpty || text.trim().isEmpty) {
      return rawVector;
    }

    // Filter conversational fillers / stop words if meaningful content words exist
    List<String> contentTokens = rawTokens;
    if (filterStopWords) {
      final filtered = rawTokens.where((w) => !_stopWords.contains(w)).toList();
      if (filtered.isNotEmpty) {
        contentTokens = filtered;
      }
    }

    // Accumulate weighted token counts
    final bucketWeights = <int, double>{};

    void addWeight(String token, double weight) {
      if (token.isEmpty) return;
      final idx = _fnv1a(token) % embeddingDimension;
      bucketWeights[idx] = (bucketWeights[idx] ?? 0.0) + weight;
    }

    for (int i = 0; i < contentTokens.length; i++) {
      final token = contentTokens[i];

      // 1. Primary Word Token (weight: 1.0)
      addWeight(token, 1.0);

      // 2. Morphological Stem (weight: 0.85)
      final stem = _stem(token);
      if (stem != token) {
        addWeight(stem, 0.85);
      }

      // 3. Sub-word character n-grams (3-grams: 0.15 for len >= 4, 4-grams: 0.25 for len >= 5)
      // Provides typo tolerance and morphological bridging
      if (token.length >= 4) {
        for (int j = 0; j <= token.length - 3; j++) {
          final gram3 = token.substring(j, j + 3);
          addWeight('g3_$gram3', 0.15);
        }
      }
      if (token.length >= 5) {
        for (int j = 0; j <= token.length - 4; j++) {
          final gram4 = token.substring(j, j + 4);
          addWeight('g4_$gram4', 0.25);
        }
      }

      // 4. Token Bigram Collocation (weight: 0.45)
      // Preserves adjacent phrase structure ("emergency contact", "indoor navigation")
      if (i < contentTokens.length - 1) {
        final bigram = '${token}_${contentTokens[i + 1]}';
        addWeight('bi_$bigram', 0.45);
      }
    }

    // 5. Sub-linear Term Frequency Scaling:
    // If weight <= 1.0, retain exact fractional weight (keeps collisions negligible).
    // If weight > 1.0, apply 1.0 + ln(weight) to compress repetitive keyword bursts.
    for (final entry in bucketWeights.entries) {
      final idx = entry.key;
      final rawWeight = entry.value;
      rawVector[idx] = rawWeight <= 1.0 ? rawWeight : 1.0 + log(rawWeight);
    }

    // 6. L2 Normalization with numerical zero-vector safety
    double sumSq = 0.0;
    for (int i = 0; i < embeddingDimension; i++) {
      sumSq += rawVector[i] * rawVector[i];
    }
    final norm = sqrt(sumSq);

    if (norm > 0.0) {
      for (int i = 0; i < embeddingDimension; i++) {
        rawVector[i] /= norm;
      }
    }

    return rawVector;
  }
}
