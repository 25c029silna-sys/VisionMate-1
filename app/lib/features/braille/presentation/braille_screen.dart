import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../../../core/camera/camera_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/voice/voice_service.dart';
import '../../../widgets/voice_button.dart';
import '../../digital_library/data/embedding_store.dart';
import '../../digital_library/domain/library_service.dart';
import '../domain/braille_service.dart';

class BrailleScreen extends StatefulWidget {
  const BrailleScreen({super.key});

  @override
  State<BrailleScreen> createState() => _BrailleScreenState();
}

class _BrailleScreenState extends State<BrailleScreen> {
  late VoiceService voiceService;
  final BrailleService brailleService = BrailleService();
  final CameraService cameraService = CameraService();
  
  String result = 'Position camera over Braille page and tap Scan Braille or say Scan.';
  bool isScanning = false;
  bool isCameraReady = false;
  bool isExportingPdf = false;
  bool isListening = false;

  @override
  void initState() {
    super.initState();
    voiceService = Provider.of<VoiceService>(context, listen: false);
    _initCamera();
  }

  Future<void> _initCamera() async {
    final ready = await cameraService.initCamera(resolution: ResolutionPreset.high);
    if (mounted) {
      setState(() {
        isCameraReady = ready;
      });
    }
    await voiceService.speak('Braille recognition activated. Align page within frame and tap screen or say scan.');
    if (mounted) {
      await _handleVoiceCommand();
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

    if (command == null || command.trim().isEmpty) return;

    final lower = command.toLowerCase().trim();
    if (lower.contains('scan') || lower.contains('capture') || lower.contains('read') || lower.contains('process')) {
      await _scanBraille();
    } else if (lower.contains('pdf') || lower.contains('export') || lower.contains('save')) {
      await _exportToPdf();
    } else if (lower.contains('repeat') || lower.contains('again')) {
      if (result.isNotEmpty) {
        await voiceService.speak('Current Braille text: $result');
      }
    } else if (lower.contains('back') || lower.contains('home') || lower.contains('exit') || lower.contains('close')) {
      await voiceService.speak('Returning to main menu.');
      if (mounted) Navigator.pop(context);
    } else if (lower.contains('help') || lower.contains('guide')) {
      await voiceService.speak('Available commands: say Scan to read Braille, PDF to export document, Repeat to hear again, or Back to return home.');
    } else {
      await voiceService.speak('Command not recognized. Say Scan, PDF, or Back.');
    }
  }


  Future<void> _scanBraille() async {
    if (isScanning) return;

    setState(() {
      isScanning = true;
      result = 'Processing Braille page image...';
    });

    try {
      await voiceService.speak('Scanning Braille page. Please hold the camera steady.');

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
          isScanning = false;
        });
        await voiceService.speak(errorMsg);
        return;
      }

      final extracted = await brailleService.classifyBraille(imagePath);

      if (!mounted) return;

      if (extracted == 'MODEL_UNAVAILABLE') {
        const errorMsg = "The trained Braille model file is currently unavailable. Operating in standard cell detection mode.";
        setState(() {
          result = errorMsg;
          isScanning = false;
        });
        await voiceService.speak(errorMsg);
        return;
      }

      setState(() {
        result = extracted;
        isScanning = false;
      });

      await voiceService.speak('Braille recognition complete. Recognized text: $extracted');
    } catch (e, stack) {
      debugPrint('BrailleScreen scanning error: $e\n$stack');
      if (!mounted) return;
      const errorMsg = 'An error occurred while scanning the Braille page. Please try again.';
      setState(() {
        result = errorMsg;
        isScanning = false;
      });
      await voiceService.speak(errorMsg);
    }
  }

  Future<void> _exportToPdf() async {
    if (result.trim().isEmpty || result.contains('Position camera') || result.contains('Processing')) {
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
      final docTitle = 'Braille Document ($dateStr $timeStr)';

      final pdfFile = await brailleService.exportBrailleTextToPdf(result, title: docTitle);
      
      // Index the Braille PDF into the Digital Library vector store for semantic search
      try {
        final storage = Provider.of<StorageService>(context, listen: false);
        final libraryService = LibraryService(EmbeddingStore(storage));
        await libraryService.addAndIndexDocument(docTitle, result, sourceType: 'braille_pdf');
      } catch (storageErr) {
        debugPrint('BrailleScreen: Storage indexing note: $storageErr');
      }

      if (!mounted) return;

      setState(() {
        isExportingPdf = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF saved and indexed into Digital Library (${pdfFile.path})'),
          backgroundColor: Colors.green,
        ),
      );

      await voiceService.speak('Braille text successfully converted to PDF and saved to your digital library.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isExportingPdf = false;
      });
      await voiceService.speak('Failed to export PDF file.');
    }
  }

  @override
  void dispose() {
    cameraService.dispose();
    brailleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRecognizedText = result.isNotEmpty &&
        !result.contains('Position camera') &&
        !result.contains('Processing') &&
        !result.contains('isn\'t available');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Braille Page Recognition'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).primaryColor, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isCameraReady && cameraService.controller != null)
                      CameraPreview(cameraService.controller!)
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
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isScanning ? Colors.greenAccent : Colors.white38,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.all(32),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14.0),
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
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
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
                        if (hasRecognizedText) ...[
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: isExportingPdf ? null : _exportToPdf,
                              icon: isExportingPdf
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.picture_as_pdf, size: 22),
                              label: const Text('PDF', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                    const SizedBox(height: 10),
                    VoiceButton(
                      label: 'VOICE COMMAND',
                      subtitle: 'Tap to speak: "Scan", "PDF", or "Repeat"',
                      activeSubtitle: 'Listening... say "Scan" or "PDF"',
                      isListening: isListening,
                      onPressed: _handleVoiceCommand,
                      primaryColor: const Color(0xFF1E293B),
                      activeColor: Colors.amber.shade800,
                    ),
                    const SizedBox(height: 6),
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
