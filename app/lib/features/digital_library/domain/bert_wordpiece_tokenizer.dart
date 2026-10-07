/// Pure-Dart WordPiece Tokenizer for BERT and Sentence-Transformers (e.g. all-MiniLM-L6-v2).
///
/// Encodes raw English text into WordPiece token IDs and attention masks conforming
/// to the 30,522-token standard BERT vocabulary (`vocab.txt`).
class TokenizedInput {
  final List<int> inputIds;
  final List<int> attentionMask;

  const TokenizedInput({
    required this.inputIds,
    required this.attentionMask,
  });
}

class BertWordPieceTokenizer {
  final Map<String, int> vocab;
  final int unkId;
  final int clsId;
  final int sepId;
  final int padId;

  BertWordPieceTokenizer(
    this.vocab, {
    this.unkId = 100,
    this.clsId = 101,
    this.sepId = 102,
    this.padId = 0,
  });

  /// Factory creating tokenizer from raw `vocab.txt` file string content.
  factory BertWordPieceTokenizer.fromVocabString(String content) {
    final map = <String, int>{};
    final lines = content.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final token = lines[i].trim();
      if (token.isNotEmpty) {
        map[token] = i;
      }
    }
    return BertWordPieceTokenizer(map);
  }

  /// Factory creating tokenizer from list of vocabulary strings.
  factory BertWordPieceTokenizer.fromLines(List<String> lines) {
    final map = <String, int>{};
    for (int i = 0; i < lines.length; i++) {
      final token = lines[i].trim();
      if (token.isNotEmpty) {
        map[token] = i;
      }
    }
    return BertWordPieceTokenizer(map);
  }

  static bool _isPunctuation(int codeUnit) {
    if ((codeUnit >= 33 && codeUnit <= 47) ||
        (codeUnit >= 58 && codeUnit <= 64) ||
        (codeUnit >= 91 && codeUnit <= 96) ||
        (codeUnit >= 123 && codeUnit <= 126)) {
      return true;
    }
    return false;
  }

  static bool _isWhitespace(int codeUnit) {
    return codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13;
  }

  /// Splits string into basic whitespace and punctuation tokens.
  List<String> _basicTokenize(String text) {
    final clean = text.toLowerCase();
    final tokens = <String>[];
    final buffer = StringBuffer();

    for (int i = 0; i < clean.length; i++) {
      final cu = clean.codeUnitAt(i);
      if (_isWhitespace(cu)) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
      } else if (_isPunctuation(cu)) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        tokens.add(String.fromCharCode(cu));
      } else {
        buffer.writeCharCode(cu);
      }
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }
    return tokens;
  }

  /// Encodes [text] into WordPiece IDs and attention mask with [CLS] and [SEP].
  TokenizedInput encode(
    String text, {
    int maxSeqLength = 128,
    bool padToMax = false,
  }) {
    final basicTokens = _basicTokenize(text);
    final ids = <int>[clsId];

    for (final token in basicTokens) {
      if (ids.length >= maxSeqLength - 1) break;

      if (token.length > 100) {
        ids.add(unkId);
        continue;
      }

      int start = 0;
      final subIds = <int>[];
      bool isBad = false;

      while (start < token.length) {
        int end = token.length;
        String? curSubword;

        while (start < end) {
          String sub = token.substring(start, end);
          if (start > 0) {
            sub = '##$sub';
          }
          if (vocab.containsKey(sub)) {
            curSubword = sub;
            break;
          }
          end--;
        }

        if (curSubword == null) {
          isBad = true;
          break;
        }

        subIds.add(vocab[curSubword]!);
        start = end;
      }

      if (isBad) {
        ids.add(unkId);
      } else {
        for (final id in subIds) {
          if (ids.length < maxSeqLength - 1) {
            ids.add(id);
          }
        }
      }
    }

    ids.add(sepId);

    final mask = List<int>.filled(ids.length, 1);

    if (padToMax && ids.length < maxSeqLength) {
      final padCount = maxSeqLength - ids.length;
      ids.addAll(List<int>.filled(padCount, padId));
      mask.addAll(List<int>.filled(padCount, 0));
    }

    return TokenizedInput(inputIds: ids, attentionMask: mask);
  }
}
