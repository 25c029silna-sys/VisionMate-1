import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Represents extracted cell data containing the 28x28 patch, cell position, and 6-dot presence states.
class BrailleCellData {
  final int row;
  final int col;
  final img.Image patch28x28;
  final List<bool> dots; // 6-element list: [dot1, dot2, dot3, dot4, dot5, dot6]
  final bool isEmpty;

  BrailleCellData({
    required this.row,
    required this.col,
    required this.patch28x28,
    required this.dots,
    required this.isEmpty,
  });
}

class BraillePreprocessor {
  /// Loads an image file from path, decodes it, normalizes resolution,
  /// and segments into structured 6-dot Braille cells.
  Future<List<BrailleCellData>> processImageFile(String imagePath) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      debugPrint('BraillePreprocessor: File does not exist at $imagePath');
      return [];
    }

    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      debugPrint('BraillePreprocessor: Could not decode image bytes');
      return [];
    }

    return extractCellData(image);
  }

  /// Extracts cell patches and 6-dot patterns from an in-memory image.
  List<BrailleCellData> extractCellData(img.Image originalImage, {int numRows = 6, int numCols = 10}) {
    final List<BrailleCellData> resultCells = [];

    // 1. Scale down high-resolution camera photos to 800px width
    img.Image scaledImage = originalImage;
    if (originalImage.width > 800) {
      scaledImage = img.copyResize(originalImage, width: 800);
    }

    // 2. Grayscale conversion
    final grayscale = img.grayscale(scaledImage);
    final width = grayscale.width;
    final height = grayscale.height;

    // Margins (5% left/right, 10% top/bottom)
    final startX = (width * 0.05).toInt();
    final startY = (height * 0.10).toInt();
    final gridW = (width * 0.90).toInt();
    final gridH = (height * 0.80).toInt();

    final cellW = gridW ~/ numCols;
    final cellH = gridH ~/ numRows;

    for (int r = 0; r < numRows; r++) {
      for (int c = 0; c < numCols; c++) {
        final cropX = startX + c * cellW;
        final cropY = startY + r * cellH;

        if (cropX + cellW > width || cropY + cellH > height) continue;

        final patch = img.copyCrop(
          grayscale,
          x: cropX,
          y: cropY,
          width: cellW,
          height: cellH,
        );

        final patch28 = img.copyResize(patch, width: 28, height: 28);

        // Analyze luminance min/max
        double minLum = 255.0;
        double maxLum = 0.0;
        double totalLum = 0.0;

        for (int y = 0; y < 28; y++) {
          for (int x = 0; x < 28; x++) {
            final px = patch28.getPixel(x, y);
            final lum = img.getLuminance(px).toDouble();
            if (lum < minLum) minLum = lum;
            if (lum > maxLum) maxLum = lum;
            totalLum += lum;
          }
        }

        final contrast = maxLum - minLum;
        final avgLum = totalLum / (28 * 28);

        // Cell is empty if contrast is too low
        if (contrast < 25.0) {
          resultCells.add(BrailleCellData(
            row: r,
            col: c,
            patch28x28: patch28,
            dots: List.filled(6, false),
            isEmpty: true,
          ));
          continue;
        }

        // Analyze 6-dot positions (2 columns x 3 rows) in 28x28 cell patch
        // Dot 1 (x: 8, y: 5), Dot 2 (x: 8, y: 14), Dot 3 (x: 8, y: 23)
        // Dot 4 (x: 20, y: 5), Dot 5 (x: 20, y: 14), Dot 6 (x: 20, y: 23)
        final dotCoords = [
          [8, 5],   // Dot 1
          [8, 14],  // Dot 2
          [8, 23],  // Dot 3
          [20, 5],  // Dot 4
          [20, 14], // Dot 5
          [20, 23], // Dot 6
        ];

        final dots = <bool>[];
        for (final coord in dotCoords) {
          final x = coord[0];
          final y = coord[1];
          final px = patch28.getPixel(x, y);
          final lum = img.getLuminance(px).toDouble();
          // Dot is detected if local luminance differs significantly from background average
          final isDotPresent = (lum - avgLum).abs() > (contrast * 0.25);
          dots.add(isDotPresent);
        }

        final hasAnyDot = dots.any((d) => d);

        resultCells.add(BrailleCellData(
          row: r,
          col: c,
          patch28x28: patch28,
          dots: dots,
          isEmpty: !hasAnyDot,
        ));
      }
    }

    return resultCells;
  }
}

