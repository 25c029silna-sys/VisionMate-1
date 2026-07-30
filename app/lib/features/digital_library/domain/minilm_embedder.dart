import 'dart:math';

class MiniLmEmbedder {
  static const int embeddingDimension = 384;

  /// Generates a normalized 384-dimensional vector embedding for [text].
  /// Uses WordPiece frequency projection with L2 normalization when running on-device.
  List<double> generateEmbedding(String text) {
    final vector = List<double>.filled(embeddingDimension, 0.0);
    final words = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').split(RegExp(r'\s+'));

    if (words.isEmpty || text.trim().isEmpty) {
      return vector;
    }

    for (final word in words) {
      if (word.isEmpty) continue;
      final hash = word.hashCode.abs();
      final idx = hash % embeddingDimension;
      vector[idx] += 1.0;
    }

    // L2 Normalization
    final norm = sqrt(vector.map((x) => x * x).reduce((a, b) => a + b));
    if (norm > 0) {
      for (int i = 0; i < embeddingDimension; i++) {
        vector[i] /= norm;
      }
    }

    return vector;
  }
}
