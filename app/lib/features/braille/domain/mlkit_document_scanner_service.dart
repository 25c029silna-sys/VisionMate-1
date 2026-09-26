import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// Service interfacing with Google ML Kit's on-device Document Scanner.
///
/// Employs Google's established production ML model (running on-device via
/// Google Play Services) to perform real-time edge detection, corner snapping,
/// perspective deskewing, and boundary cropping.
class MlKitDocumentScannerService {
  final DocumentScannerOptions? _options;

  MlKitDocumentScannerService({DocumentScannerOptions? options})
      : _options = options;

  /// Launches Google's native Document Scanner UI with live edge snapping.
  ///
  /// Returns the absolute file path of the cropped and rectified JPEG image,
  /// or `null` if the user dismissed or cancelled the scanner.
  Future<String?> scanDocument({
    ScannerMode mode = ScannerMode.base,
    int pageLimit = 1,
    bool isGalleryImport = true,
  }) async {
    final options = _options ??
        DocumentScannerOptions(
          documentFormats: const {DocumentFormat.jpeg},
          pageLimit: pageLimit,
          mode: mode,
          isGalleryImport: isGalleryImport,
        );

    final scanner = DocumentScanner(options: options);
    try {
      final result = await scanner.scanDocument();
      if (result.images != null && result.images!.isNotEmpty) {
        final path = result.images!.first;
        if (await File(path).exists()) {
          return path;
        }
      }
      return null;
    } catch (e) {
      debugPrint('MlKitDocumentScannerService: Error during scanning: $e');
      rethrow;
    } finally {
      await scanner.close();
    }
  }
}
