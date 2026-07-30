import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Data model representing a structured block of recognized text with bounding box coordinates.
class OcrTextBlock {
  final String text;
  final Rect boundingBox;
  final List<String> lines;

  OcrTextBlock({
    required this.text,
    required this.boundingBox,
    this.lines = const [],
  });

  factory OcrTextBlock.fromMlKitBlock(TextBlock block) {
    return OcrTextBlock(
      text: block.text,
      boundingBox: block.boundingBox,
      lines: block.lines.map((l) => l.text).toList(),
    );
  }
}

class OcrDataSource {
  /// Processes an image from [imagePath] via Google ML Kit Text Recognition
  /// and returns a list of extracted [OcrTextBlock] items.
  Future<List<OcrTextBlock>> extractTextBlocks(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await recognizer.processImage(inputImage);

      final blocks = recognizedText.blocks
          .map((b) => OcrTextBlock.fromMlKitBlock(b))
          .toList();

      return blocks;
    } catch (e, stackTrace) {
      debugPrint('OcrDataSource error: Failed to process image at "$imagePath": $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    } finally {
      // Resource cleanup: dispose TextRecognizer to avoid memory/native leaks
      await recognizer.close();
    }
  }
}
