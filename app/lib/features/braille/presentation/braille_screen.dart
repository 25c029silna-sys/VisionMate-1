import 'dart:async';
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
import '../domain/braille_text_refiner.dart';

class BrailleScreen extends StatefulWidget {
  final CameraService? cameraService;
  const BrailleScreen({super.key, this.cameraService});

  @override
  State<BrailleScreen> createState() => _BrailleScreenState();
}

class _BrailleScreenState extends State<BrailleScreen> {
  late VoiceService voiceService;
  final BrailleService brailleService = BrailleService();
  late final CameraService cameraService;
  
  String result = 'Position camera over Braille page and tap Scan Braille or say Scan.';
  bool isScanning = false;
  bool isCameraReady = false;
  bool isFlashOn = false;
  bool isMaximizedCamera = false;
  bool isExportingPdf = false;
  bool isEnhancing = false;
  bool isListening = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    voiceService = Provider.of<VoiceService>(context, listen: false);
    cameraService = widget.cameraService ?? CameraService();
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

  void _toggleMaximizeCamera() {
    final nextState = !isMaximizedCamera;
    setState(() {
      isMaximizedCamera = nextState;
    });
    voiceService.speak(nextState
        ? 'Camera area enlarged for reading large Braille pages.'
        : 'Camera area restored to standard view.');
  }

  Future<void> _handleVoiceCommand() async {
    _retryTimer?.cancel();
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
    } else if (lower.contains('flash') || lower.contains('light')) {
      await _toggleFlash();
    } else if (lower.contains('expand') || lower.contains('maximize') || lower.contains('fullscreen') || lower.contains('large')) {
      _toggleMaximizeCamera();
    } else if (lower.contains('minimize') || lower.contains('shrink') || lower.contains('restore') || lower.contains('normal')) {
      if (isMaximizedCamera) _toggleMaximizeCamera();
    } else if (lower.contains('enhance') || lower.contains('polish') || lower.contains('fix') || lower.contains('correct')) {
      await _enhanceText();
    } else if (lower.contains('api') || lower.contains('key')) {
      await _showApiKeyDialog();
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
      await voiceService.speak('Available commands: say Scan to read Braille, Flash to toggle flashlight, Expand to enlarge camera area, Enhance to restore text, Key to configure API key, PDF to export document, Repeat to hear again, or Back to return home.');
    } else {
      await voiceService.speak('Command not recognized. Say Scan, Flash, Expand, Enhance, Key, PDF, or Back.');
      if (mounted) {
        setState(() {
          result = 'Tap microphone button to speak a command.';
        });
      }
    }
  }

  Future<String?> _getGeminiApiKey() async {
    // 1. Check SQLite storage first (user-entered key takes precedence)
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final key = await storage.getSetting('gemini_api_key');
      if (key != null && key.trim().isNotEmpty && !key.toUpperCase().contains('YOUR_GEMINI_API_KEY')) {
        return key.trim();
      }
    } catch (e) {
      debugPrint('BrailleScreen: Key lookup note: $e');
    }

    // 2. Check environment variable, but ignore dummy placeholders
    const envKey = String.fromEnvironment('GEMINI_API_KEY');
    if (envKey.isNotEmpty && !envKey.toUpperCase().contains('YOUR_GEMINI_API_KEY')) {
      return envKey.trim();
    }

    return null;
  }

  Future<void> _showApiKeyDialog() async {
    final currentKey = await _getGeminiApiKey() ?? '';
    final controller = TextEditingController(text: currentKey);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Colors.amberAccent),
            SizedBox(width: 8),
            Text('Gemini API Key'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your Google Gemini API key to enable AI text enhancement and restoration for degraded Braille pages.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Google Gemini API Key',
                hintText: 'AIzaSy...',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newKey = controller.text.trim();
              try {
                final storage = Provider.of<StorageService>(context, listen: false);
                await storage.setSetting('gemini_api_key', newKey);
              } catch (_) {}
              if (ctx.mounted) Navigator.pop(ctx);
              voiceService.speak(newKey.isNotEmpty
                  ? 'Gemini API key saved. You can now use AI text enhancement.'
                  : 'API key cleared.');
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _enhanceText() async {
    if (result.trim().isEmpty || result.contains('Position camera') || result.contains('Processing')) {
      await voiceService.speak('No recognized Braille text available to enhance.');
      return;
    }

    final apiKey = await _getGeminiApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      await voiceService.speak('To enhance Braille text with AI, please configure your Gemini API key.');
      if (mounted) {
        await _showApiKeyDialog();
      }
      return;
    }

    setState(() {
      isEnhancing = true;
    });
    await voiceService.speak('Refining Braille text with language model...');

    try {
      final enhanced = await BrailleTextRefiner.refineWithAi(result, apiKey: apiKey);
      if (!mounted) return;

      setState(() {
        result = enhanced;
        isEnhancing = false;
      });

      await voiceService.speak('Text enhanced: $enhanced');
    } on InvalidApiKeyException {
      if (!mounted) return;
      setState(() {
        isEnhancing = false;
      });
      await voiceService.speak('The Gemini API key is invalid or not configured. Please enter a valid key from Google AI Studio.');
      await _showApiKeyDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isEnhancing = false;
      });
      await voiceService.speak('Could not complete text enhancement.');
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
        if (isMaximizedCamera && !extracted.contains('No Braille text detected')) {
          isMaximizedCamera = false;
        }
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
      
      if (!mounted) return;

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
    _retryTimer?.cancel();
    if (isFlashOn) {
      cameraService.toggleFlash(false);
    }
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
        actions: [
          IconButton(
            icon: const Icon(Icons.vpn_key_rounded),
            tooltip: 'Configure Gemini API Key',
            onPressed: _showApiKeyDialog,
          ),
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
              flex: isMaximizedCamera ? 7 : 5,
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
                    // Large Page Framing Alignment Guide
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isScanning
                              ? Colors.greenAccent
                              : (isMaximizedCamera ? Colors.amberAccent.withAlpha(160) : Colors.white54),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    const SizedBox(width: 10),
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
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: isEnhancing ? null : _enhanceText,
                                icon: isEnhancing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.auto_fix_high, size: 20),
                                label: const Text('Enhance', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal.shade700,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              height: 52,
                              child: ElevatedButton.icon(
                                onPressed: isExportingPdf ? null : _exportToPdf,
                                icon: isExportingPdf
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.picture_as_pdf, size: 22),
                                label: const Text('PDF', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
                        subtitle: 'Tap to speak: "Scan", "Expand", or "PDF"',
                        activeSubtitle: 'Listening... say "Scan" or "Expand"',
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
