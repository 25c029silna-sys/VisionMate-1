import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Transforms raw / degraded Braille OCR text into fluent, legible natural language.
/// Supports both fast on-device offline translation (Grade 2 Braille contractions & number signs)
/// and optional AI generative reconstruction via Google Gemini API.
class BrailleTextRefiner {
  static const Map<String, String> _numberMap = {
    'a': '1', 'b': '2', 'c': '3', 'd': '4', 'e': '5',
    'f': '6', 'g': '7', 'h': '8', 'i': '9', 'j': '0',
  };

  static const Map<String, String> _grade2WordSigns = {
    'b': 'but',
    'c': 'can',
    'd': 'do',
    'e': 'every',
    'f': 'from',
    'g': 'go',
    'h': 'have',
    'j': 'just',
    'k': 'knowledge',
    'l': 'like',
    'm': 'more',
    'n': 'not',
    'p': 'people',
    'q': 'quite',
    'r': 'rather',
    's': 'so',
    't': 'that',
    'u': 'us',
    'v': 'very',
    'w': 'will',
    'x': 'it',
    'y': 'you',
    'z': 'as',
  };

  /// 100% Offline rule-based Braille text normalization:
  /// - Decodes Braille number prefix (#) to standard digits (#aiai -> 1719, #cj -> 30)
  /// - Expands Grade 2 Braille single-letter words (b -> but, c -> can, x -> it)
  /// - Separates attached Braille conjunction contractions (e.g. "lifeand" -> "life and")
  /// - Cleans stray OCR artifacts while maintaining original reading structure
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

    // 3. Expand Grade 2 single-letter words
    final lines = text.split('\n');
    final processedLines = <String>[];

    for (final line in lines) {
      final words = line.split(RegExp(r'\s+'));
      final expandedWords = <String>[];

      for (final w in words) {
        final lower = w.toLowerCase();
        if (_grade2WordSigns.containsKey(lower)) {
          // Preserve capitalization if first letter was uppercase
          final expanded = _grade2WordSigns[lower]!;
          if (w.isNotEmpty && w[0] == w[0].toUpperCase() && w[0] != w[0].toLowerCase()) {
            expandedWords.add('${expanded[0].toUpperCase()}${expanded.substring(1)}');
          } else {
            expandedWords.add(expanded);
          }
        } else {
          expandedWords.add(w);
        }
      }
      processedLines.add(expandedWords.join(' '));
    }

    String result = processedLines.join('\n');

    // 4. Clean up common Braille OCR substitution artifacts (e.g. * often represents "in")
    result = result.replaceAll('*', 'in');

    return result.trim();
  }

  /// AI Generative Text Reconstruction:
  /// Uses Google Gemini API (or compatible LLM) to convert degraded / partially-illegible
  /// Braille OCR output into fluent, grammatically accurate English text.
  /// Falls back to [refineOffline] if network or API key is unavailable.
  static Future<String> refineWithAi(
    String rawText, {
    String? apiKey,
    http.Client? client,
  }) async {
    final offlineCleaned = refineOffline(rawText);
    if (apiKey == null || apiKey.trim().isEmpty) {
      return offlineCleaned;
    }

    final httpClient = client ?? http.Client();

    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey',
      );

      final prompt = '''You are an expert assistive OCR post-processor for blind users. 
The following text was extracted by a computer vision model from an embossed Braille page. 
It contains minor OCR typos, missing letters, and Braille contraction artifacts. 

Reconstruct the text into fluent, legible, grammatically correct English matching the intended meaning. 
Do not add unsolicited commentary, explanations, or formatting markers. Output only the restored text.

RAW BRAILLE OCR TEXT:
$offlineCleaned''';

      final response = await httpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [{'text': prompt}]
                }
              ],
              'generationConfig': {
                'temperature': 0.2,
                'maxOutputTokens': 1024,
              }
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final refined = parts[0]['text'] as String?;
            if (refined != null && refined.trim().isNotEmpty) {
              return refined.trim();
            }
          }
        }
      }
      debugPrint('AI refinement returned status ${response.statusCode}, using offline refined text.');
      return offlineCleaned;
    } catch (e) {
      debugPrint('AI refinement fallback note: $e');
      return offlineCleaned;
    }
  }
}
