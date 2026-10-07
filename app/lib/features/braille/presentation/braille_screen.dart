import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../../../core/camera/camera_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/voice/voice_service.dart';
import '../../../core/voice/voice_post_process_helper.dart';
import '../../../widgets/voice_button.dart';
import '../../digital_library/data/embedding_store.dart';
import '../../digital_library/domain/library_service.dart';
import '../domain/braille_service.dart';
import 'widgets/voice_pdf_naming_dialog.dart';

class BrailleScreen extends StatefulWidget {
  final CameraService? cameraService;
  final BrailleService? brailleService;
  const BrailleScreen({super.key, this.cameraService, this.brailleService});

  @override
  State<BrailleScreen> createState() => _BrailleScreenState();
}

class _BrailleScreenState extends State<BrailleScreen> {
  late VoiceService voiceService;
  late final BrailleService brailleService;
  late final CameraService cameraService;
  
  String result = 'Position camera over Braille page and tap Scan Braille or say Scan.';
  String _extractedText = '';
  bool _hasRecognizedText = false;
  bool isScanning = false;
  bool isCameraReady = false;
  bool isFlashOn = false;
  bool isMaximizedCamera = false;
  bool isExportingPdf = false;
  bool isListening = false;

  @override
  void initState() {
    super.initState();
    voiceService = Provider.of<VoiceService>(context, listen: false);
    cameraService = widget.cameraService ?? CameraService();
    brailleService = widget.brailleService ?? BrailleService();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final ready = await cameraService.initCamera(resolution: ResolutionPreset.high);
    if (mounted) {
      setState(() {
        isCameraReady = ready;
      });
    }
    await voiceService.speak('Braille recognition activated. Align page within frame and tap screen or say scan.', awaitCompletion: true);
    if (mounted) {
      await _handleVoiceCommand();
    }
  }

  Future<void> _toggleFlash() async {
    if (!cameraService.isInitialized) return;
    final nextState = !isFlashOn;
    await cameraService.toggleFlash(nextState);
    if (mounted) {
      setState(() {
        isFlashOn = nextState;
      });
    }
    await voiceService.speak(nextState ? 'Flashlight turned on.' : 'Flashlight turned off.');
  }

  Future<void> _toggleMaximizeCamera({bool autoScan = true}) async {
    final nextState = !isMaximizedCamera;
    setState(() {
      isMaximizedCamera = nextState;
    });
    if (nextState) {
      await voiceService.speak('Camera area enlarged for reading large Braille pages.', awaitCompletion: true);
      if (autoScan && mounted) {
        await _scanBraille();
      }
    } else {
      await voiceService.speak('Camera area restored to standard view.');
    }
  }

  Future<void> _handleVoiceCommand() async {
    if (isListening) {
      await voiceService.stopListening();
      if (mounted) {
        setState(() {
          isListening = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        isListening = true;
      });
    }

    final command = await voiceService.listen();

    if (!mounted) return;
    setState(() {
      isListening = false;
    });

    if (command == null || command.trim().isEmpty) {
      return;
    }

    await _handleVoiceCommandWithUtterance(command);
  }

  Future<void> _handleVoiceCommandWithUtterance(String command) async {
    final lower = command.toLowerCase().trim();
    if (lower.contains('scan') || lower.contains('capture') || lower.contains('read') || lower.contains('process') || VoicePostProcessHelper.isRepeatOrAgain(lower)) {
      await _scanBraille();
    } else if (lower.contains('flash') || lower.contains('light')) {
      await _toggleFlash();
    } else if (lower.contains('expand') || lower.contains('maximize') || lower.contains('fullscreen') || lower.contains('large')) {
      await _toggleMaximizeCamera();
    } else if (lower.contains('minimize') || lower.contains('shrink') || lower.contains('restore') || lower.contains('normal')) {
      if (isMaximizedCamera) await _toggleMaximizeCamera(autoScan: false);
    } else if (lower.contains('pdf') || lower.contains('export') || lower.contains('save')) {
      final customName = BrailleService.extractPdfNameFromCommand(command);
      if (customName != null && customName.isNotEmpty) {
        await _exportToPdf(customName: customName);
      } else {
        await _promptAndExportPdf();
      }
    } else if (lower.contains('repeat') || lower.contains('again')) {
      if (_hasRecognizedText && _extractedText.isNotEmpty) {
        await voiceService.speak('Current Braille text: $_extractedText', awaitCompletion: true);
      } else {
        await voiceService.speak('No Braille text scanned yet.');
      }
    } else if (VoicePostProcessHelper.isHomeOrExit(lower)) {
      await voiceService.speak('Returning to main menu.');
      if (mounted) Navigator.pop(context);
    } else if (lower.contains('help') || lower.contains('guide')) {
      await voiceService.speak('Available commands: say Scan to read Braille, Flash to toggle flashlight, Expand to enlarge camera area, Save PDF as with your chosen document name, Repeat to hear again, or Back to return home.');
    } else {
      await voiceService.speak(
        'Command not recognized. Say Scan, Flash, Expand, Save PDF, or Back.',
        awaitCompletion: true,
      );
    }
  }

  Future<void> _scanBraille() async {
    if (isScanning) return;
    if (isListening) {
      await voiceService.stopListening();
      if (mounted) setState(() => isListening = false);
    }

    setState(() {
      isScanning = true;
      result = 'Scanning Braille page...';
    });

    try {
      await voiceService.speak('Scanning Braille page.');

      String? imagePath;
      if (cameraService.isInitialized) {
        final photo = await cameraService.takePicture();
        if (photo != null) {
          imagePath = photo.path;
        }
      }

      if (imagePath == null) {
        const errorMsg = 'Could not capture photo from camera. Please ensure camera permission is granted.';
        if (!mounted) return;
        setState(() {
          result = errorMsg;
          _extractedText = '';
          _hasRecognizedText = false;
          isScanning = false;
        });
        await voiceService.speak(errorMsg);
        return;
      }

      final scanResult = await brailleService.scanBrailleWithBorderCrop(
        imagePath,
        enableBorderCrop: false,
      );

      if (!mounted) return;

      final extracted = scanResult.text;

      if (extracted == 'MODEL_UNAVAILABLE') {
        const errorMsg = "The trained Braille model file is currently unavailable. Operating in standard cell detection mode.";
        setState(() {
          result = errorMsg;
          _extractedText = '';
          _hasRecognizedText = false;
          isScanning = false;
        });
        await voiceService.speak(errorMsg);
        return;
      }

      if (!scanResult.hasContent ||
          extracted.contains('No Braille text detected') ||
          extracted.contains('Position camera') ||
          extracted.trim().isEmpty) {
        setState(() {
          result = 'No Braille text detected. Please align camera over a Braille page.';
          _extractedText = '';
          _hasRecognizedText = false;
          isScanning = false;
        });
        await voiceService.speak('No Braille text detected. Please align camera over a Braille page and tap scan.');
        return;
      }

      setState(() {
        result = extracted;
        _extractedText = extracted;
        _hasRecognizedText = true;
        isScanning = false;
        if (isMaximizedCamera) {
          isMaximizedCamera = false;
        }
      });

      await voiceService.speak('Braille recognition complete. Recognized text: $extracted', awaitCompletion: true);
      if (mounted) {
        await _promptAndExportPdf();
      }
    } catch (e, stack) {
      debugPrint('BrailleScreen scanning error: $e\n$stack');
      if (!mounted) return;
      const errorMsg = 'An error occurred while scanning the Braille page. Please try again.';
      setState(() {
        result = errorMsg;
        _extractedText = '';
        _hasRecognizedText = false;
        isScanning = false;
      });
      await voiceService.speak(errorMsg);
    }
  }

  Future<void> _promptAndExportPdf() async {
    if (!_hasRecognizedText || _extractedText.trim().isEmpty) {
      await voiceService.speak('No recognized Braille text available to export.');
      return;
    }

    final chosenName = await VoicePdfNamingDialog.show(
      context,
      voiceService: voiceService,
    );

    if (!mounted || chosenName == null) return;

    await _exportToPdf(customName: chosenName.trim().isNotEmpty ? chosenName.trim() : null);
  }

  Future<void> _exportToPdf({String? customName}) async {
    if (!_hasRecognizedText || _extractedText.trim().isEmpty) {
      await voiceService.speak('No recognized Braille text available to export.');
      return;
    }

    setState(() {
      isExportingPdf = true;
    });

    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      
      final cleanTitle = customName != null ? BrailleService.cleanPdfName(customName) : '';
      final docTitle = cleanTitle.isNotEmpty ? cleanTitle : 'Braille Document ($dateStr $timeStr)';

      await voiceService.speak('Saving PDF as $docTitle.');

      final pdfFile = await brailleService.exportBrailleTextToPdf(_extractedText, title: docTitle);
      
      if (!mounted) return;

      // Index the Braille PDF into the Digital Library vector store for semantic search
      try {
        final storage = Provider.of<StorageService>(context, listen: false);
        final libraryService = LibraryService(EmbeddingStore(storage));
        // Index asynchronously in background so screen dismissal is immediate
        libraryService.addAndIndexDocument(docTitle, _extractedText, sourceType: 'braille_pdf').catchError((storageErr) {
          debugPrint('BrailleScreen: Storage indexing note: $storageErr');
          return 0;
        });
      } catch (storageErr) {
        debugPrint('BrailleScreen: Storage indexing note: $storageErr');
      }

      if (!mounted) return;

      setState(() {
        isExportingPdf = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF saved as "$docTitle.pdf" (${pdfFile.path}) and added to Digital Library'),
          backgroundColor: Colors.green,
        ),
      );

      await voiceService.speak('Braille text successfully converted to PDF and saved to your digital library as $docTitle.');
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } catch (e, stack) {
      debugPrint('BrailleScreen export error: $e\n$stack');
      if (!mounted) return;
      setState(() {
        isExportingPdf = false;
      });
      await voiceService.speak('Failed to export PDF file.');
    }
  }

  @override
  void dispose() {
    if (isFlashOn) {
      cameraService.toggleFlash(false);
    }
    cameraService.dispose();
    if (widget.brailleService == null) {
      brailleService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRecognizedText = _hasRecognizedText;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Braille Page Recognition'),
        actions: [
          IconButton(
            icon: Icon(isMaximizedCamera ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
            tooltip: isMaximizedCamera ? 'Restore Camera View' : 'Enlarge Camera View for Large Page',
            onPressed: _toggleMaximizeCamera,
          ),
          IconButton(
            icon: Icon(isFlashOn ? Icons.flash_on : Icons.flash_off),
            tooltip: isFlashOn ? 'Turn Flash Off' : 'Turn Flash On',
            onPressed: isCameraReady ? _toggleFlash : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Enlarged Live Camera Viewfinder
            Expanded(
              flex: isMaximizedCamera ? 7 : 4,
              child: Container(
                margin: const EdgeInsets.fromLTRB(10.0, 6.0, 10.0, 4.0),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isMaximizedCamera ? Colors.amberAccent : Theme.of(context).primaryColor,
                    width: isMaximizedCamera ? 2.5 : 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isCameraReady && cameraService.controller != null)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final controller = cameraService.controller!;
                          final previewSize = controller.value.previewSize;
                          return ClipRect(
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              child: FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: previewSize != null ? previewSize.height : constraints.maxWidth,
                                  height: previewSize != null ? previewSize.width : constraints.maxHeight,
                                  child: CameraPreview(controller),
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    else
                      const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text(
                              'Initializing camera view...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    // Quick-Toggle Floating Expand/Compact Badge
                    Positioned(
                      top: 10,
                      right: 10,
                      child: InkWell(
                        onTap: _toggleMaximizeCamera,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.amberAccent.withAlpha(140)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isMaximizedCamera ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                color: Colors.amberAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isMaximizedCamera ? 'Compact' : 'Expand Area',
                                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom Controls and Results Area
            if (isMaximizedCamera)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                color: const Color(0xFF161B22),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: isScanning ? null : _scanBraille,
                          icon: isScanning
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.camera_alt, size: 24),
                          label: Text(
                            isScanning ? 'Processing...' : 'Scan Braille',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 50,
                      width: 50,
                      child: IconButton.filled(
                        onPressed: _handleVoiceCommand,
                        icon: Icon(isListening ? Icons.mic : Icons.mic_none, color: Colors.white, size: 24),
                        tooltip: 'Voice Command',
                        style: IconButton.styleFrom(
                          backgroundColor: isListening ? Colors.green : const Color(0xFF1E293B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                  child: Column(
                    children: [
                      // Result Display Box
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12.0),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade900,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: SingleChildScrollView(
                            child: SelectableText(
                              result,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Action Buttons Row
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: isScanning ? null : _scanBraille,
                                icon: isScanning
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.camera_alt, size: 20),
                                label: Text(
                                  isScanning ? 'Processing...' : 'Scan Braille',
                                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (hasRecognizedText) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: isExportingPdf ? null : _promptAndExportPdf,
                                icon: isExportingPdf
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.picture_as_pdf, size: 20),
                                label: const Text('PDF', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepOrangeAccent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      VoiceButton(
                        label: 'VOICE COMMAND',
                        subtitle: 'Tap to speak: "Scan" or "Save PDF as [name]"',
                        activeSubtitle: 'Listening... say "Scan" or "Save PDF as [name]"',
                        isListening: isListening,
                        onPressed: _handleVoiceCommand,
                        primaryColor: const Color(0xFF1E293B),
                        activeColor: Colors.amber.shade800,
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
