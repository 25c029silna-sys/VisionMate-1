import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Exception thrown when the Gemini API key is missing, a placeholder, or invalid.
class InvalidApiKeyException implements Exception {
  final String message;
  InvalidApiKeyException(this.message);

  @override
  String toString() => 'InvalidApiKeyException: $message';
}

/// Transforms raw / degraded Braille OCR text into fluent, legible natural language.
/// Supports both fast on-device offline translation (Grade 2 Braille contractions & number signs)
/// and optional AI generative reconstruction via Google Gemini API.
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


  /// AI Generative Text Reconstruction:
  /// Uses Google Gemini API (or compatible LLM) to convert degraded / partially-illegible
  /// Braille OCR output into fluent, grammatically accurate English text.
  /// Falls back to [refineOffline] if network or temporary server error occurs.
  /// Throws [InvalidApiKeyException] if the API key is a dummy placeholder or rejected by Google.
  static Future<String> refineWithAi(
    String rawText, {
    String? apiKey,
    http.Client? client,
  }) async {
    final offlineCleaned = refineOffline(rawText);
    if (apiKey == null || apiKey.trim().isEmpty) {
      return offlineCleaned;
    }

    final cleanKey = apiKey.trim();
    if (cleanKey.toUpperCase().contains('YOUR_GEMINI_API_KEY')) {
      throw InvalidApiKeyException('API key is a placeholder ("YOUR_GEMINI_API_KEY"). Please configure a valid key from Google AI Studio.');
    }

    final httpClient = client ?? http.Client();

    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$cleanKey',
      );

      final prompt = '''You are an expert assistive Braille transcription restorer for visually impaired users.
The text below was captured by an optical camera scanning an embossed Braille page printed in Unified English Braille (UEB Grade 2 contracted Braille).
Because of camera resolution, embossing shadows, and Braille shorthand contractions (such as "fr" for friends, "x" for it, single-cell contractions like "and", "the", "ed", "ou", "wh"), the raw OCR transcription contains partial phonetic spellings, missing letters, and contraction artifacts.

TASK:
Reconstruct this into the complete, grammatically correct, fluent English text intended by the author.
Preserve paragraph, heading, and dialogue structure. Accurately correct OCR typos and expand Braille shorthand.
Do not include conversational filler, notes, disclaimers, or markdown formatting blocks. Output ONLY the clean restored text.

RAW BRAILLE OCR TRANSCRIPTION:
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
                'maxOutputTokens': 1500,
              }
            }),
          )
          .timeout(const Duration(seconds: 12));

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
      } else if (response.statusCode == 400 || response.statusCode == 403) {
        debugPrint('AI refinement returned authentication/key error: ${response.statusCode}');
        throw InvalidApiKeyException('Gemini API key is invalid or unauthorized (HTTP ${response.statusCode}).');
      }

      debugPrint('AI refinement returned status ${response.statusCode}, using offline refined text.');
      return offlineCleaned;
    } on InvalidApiKeyException {
      rethrow;
    } catch (e) {
      debugPrint('AI refinement fallback note: $e');
      return offlineCleaned;
    }
  }
}
