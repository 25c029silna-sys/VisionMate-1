import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../data/ocr_data_source.dart';

enum OcrReaderState {
  idle,
  capturing,
  processing,
  reading,
  error,
}

class OcrService {
  final OcrDataSource dataSource;
  OcrReaderState state = OcrReaderState.idle;

  OcrService({OcrDataSource? dataSource})
      : dataSource = dataSource ?? OcrDataSource();

  /// Sorts [blocks] into natural reading order:
  /// Primary sort: Top-to-bottom by vertical coordinate (top).
  /// Secondary sort: Left-to-right by horizontal coordinate (left) for blocks
  /// within the same horizontal line band (vertical delta <= 20.0 pixels).
  static List<OcrTextBlock> sortTextBlocksInReadingOrder(List<OcrTextBlock> blocks) {
    if (blocks.length <= 1) return List.from(blocks);

    final sorted = List<OcrTextBlock>.from(blocks);
    const bandThreshold = 20.0;

    sorted.sort((a, b) {
      final topDiff = (a.boundingBox.top - b.boundingBox.top).abs();
      if (topDiff <= bandThreshold) {
        // Blocks are in approximately the same horizontal line band: sort left-to-right
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      }
      // Sort top-to-bottom
      return a.boundingBox.top.compareTo(b.boundingBox.top);
    });

    return sorted;
  }

  /// Extracts text from [imagePath], sorts into reading order, and returns assembled text string.
  /// Returns 'NO_TEXT_FOUND' if image contains no readable text.
  /// Returns 'EXTRACTION_ERROR' if ML Kit or file processing fails.
  Future<String> recognizeTextFromImage(String imagePath) async {
    state = OcrReaderState.processing;
    try {
      final blocks = await dataSource.extractTextBlocks(imagePath);
      if (blocks.isEmpty) {
        state = OcrReaderState.idle;
        return 'NO_TEXT_FOUND';
      }

      final orderedBlocks = sortTextBlocksInReadingOrder(blocks);
      final assembledText = orderedBlocks
          .map((b) => b.text.trim())
          .where((t) => t.isNotEmpty)
          .join('\n\n');

      if (assembledText.trim().isEmpty) {
        state = OcrReaderState.idle;
        return 'NO_TEXT_FOUND';
      }

      state = OcrReaderState.reading;
      return assembledText;
    } catch (e, stackTrace) {
      state = OcrReaderState.error;
      debugPrint('OcrService error during text extraction: $e');
      debugPrintStack(stackTrace: stackTrace);
      return 'EXTRACTION_ERROR';
    }
  }

  /// Optional web context expansion lookup for a key term/phrase.
  /// Fully non-blocking & isolated: network failures or offline status return
  /// fallback message without interrupting prior core reading results.
  Future<String> fetchWebContext(String textQuery, {http.Client? client}) async {
    if (textQuery.trim().isEmpty) {
      return 'No additional context available.';
    }

    final httpClient = client ?? http.Client();
    final firstTerm = textQuery.split(RegExp(r'\s+')).take(3).join(' ');

    try {
      final uri = Uri.parse(
        'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(firstTerm)}',
      );
      final response = await httpClient.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final body = response.body;
        if (body.contains('"extract":"')) {
          final extract = body.split('"extract":"').last.split('","').first;
          if (extract.isNotEmpty) {
            return 'Additional context for $firstTerm: $extract';
          }
        }
      }
      return 'No additional context available for $firstTerm.';
    } catch (e) {
      debugPrint('OcrService optional web lookup offline/failed: $e');
      return 'No additional context available.';
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
