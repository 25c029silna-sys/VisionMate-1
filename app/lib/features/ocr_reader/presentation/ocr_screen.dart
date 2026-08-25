import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/voice/voice_service.dart';
import '../../../core/camera/camera_service.dart';
import '../../../core/permissions/permission_service.dart';
import '../domain/ocr_service.dart';

class OcrScreen extends StatefulWidget {
  final OcrService? ocrService;
  final CameraService? cameraService;
  final PermissionService? permissionService;

  const OcrScreen({
    super.key,
    this.ocrService,
    this.cameraService,
    this.permissionService,
  });

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  late VoiceService voiceService;
  late final OcrService ocrService;
  late final CameraService cameraService;
  late final PermissionService permissionService;

  String status = 'Point camera at printed text to begin scanning.';
  String extractedText = '';
  bool isCameraReady = false;
  bool isScanning = false;
  bool isFlashOn = false;

  @override
  void initState() {
    super.initState();
    ocrService = widget.ocrService ?? OcrService();
    cameraService = widget.cameraService ?? CameraService();
    permissionService = widget.permissionService ?? PermissionService();

    voiceService = Provider.of<VoiceService>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initCameraAndPrompt();
    });
  }

  Future<void> _initCameraAndPrompt() async {
    try {
      final hasPermission = await permissionService.requestCameraPermission();
      if (!hasPermission) {
        await voiceService.speak('Camera permission denied. Returning to main menu.');
        if (mounted) Navigator.pop(context);
        return;
      }

      final ready = await cameraService.initCamera(resolution: ResolutionPreset.high);
      if (mounted) {
        setState(() {
          isCameraReady = ready;
        });
      }

      await voiceService.speak(
        'OCR reader activated. Point your camera at the text and say capture or tap to scan.',
      );
    } catch (e) {
      debugPrint('OCR Screen camera init failed: $e');
      await voiceService.speak('Camera initialization failed. Returning to main menu.');
      if (mounted) Navigator.pop(context);
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

  Future<void> _handleVoiceCommand() async {
    final command = await voiceService.listen();
    if (command == null || command.isEmpty) return;

    final lower = command.toLowerCase();
    if (lower.contains('stop')) {
      await voiceService.speak('Stopping playback.');
    } else if (lower.contains('capture') || lower.contains('scan') || lower.contains('read')) {
      await _processScan();
    } else if (lower.contains('scan again') || lower.contains('rescan')) {
      await _processScan();
    } else if (lower.contains('tell me more') || lower.contains('more context') || lower.contains('context')) {
      await _fetchContext();
    } else if (lower.contains('repeat') || lower.contains('again')) {
      if (extractedText.isNotEmpty) {
        await voiceService.speak('Recognized text: $extractedText');
      } else {
        await voiceService.speak('No text has been scanned yet.');
      }
    } else if (lower.contains('flash') || lower.contains('light')) {
      await _toggleFlash();
    }
  }

  Future<void> _processScan() async {
    if (isScanning) return;
    setState(() {
      isScanning = true;
      status = 'Scanning text. Please hold camera steady...';
    });

    await voiceService.speak('Scanning text. Please hold the camera steady.');

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
        status = errorMsg;
        isScanning = false;
      });
      await voiceService.speak(errorMsg);
      return;
    }

    final result = await ocrService.recognizeTextFromImage(imagePath);

    if (!mounted) return;
    setState(() {
      isScanning = false;
    });

    if (result == 'NO_TEXT_FOUND') {
      const msg = "I couldn't find any readable text. Try moving closer or improving the lighting.";
      setState(() {
        status = msg;
      });
      await voiceService.speak(msg);
      return;
    }

    if (result == 'EXTRACTION_ERROR') {
      const msg = 'Something went wrong reading that text, please try again.';
      setState(() {
        status = msg;
      });
      await voiceService.speak(msg);
      return;
    }

    setState(() {
      extractedText = result;
      status = 'Text extracted successfully.';
    });

    await voiceService.speak('Recognized text is: $result');
  }

  Future<void> _fetchContext() async {
    if (extractedText.isEmpty) {
      await voiceService.speak('No text has been read yet to get context for.');
      return;
    }
    await voiceService.speak('Fetching additional context.');
    final contextMsg = await ocrService.fetchWebContext(extractedText);
    await voiceService.speak(contextMsg);
  }

  @override
  void dispose() {
    cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR Reader'),
        actions: [
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
            // Live Camera Viewfinder
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
                    // Document scanning overlay frame
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isScanning ? Colors.greenAccent : Colors.white38,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.all(24),
                    ),
                  ],
                ),
              ),
            ),
            // Extracted Text / Status & Action Buttons
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
                            extractedText.isNotEmpty ? extractedText : status,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.5,
                              color: extractedText.isNotEmpty ? Colors.white : Colors.white70,
                              fontWeight: extractedText.isNotEmpty ? FontWeight.w500 : FontWeight.normal,
                            ),
                            textAlign: extractedText.isNotEmpty ? TextAlign.left : TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Action controls
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: isScanning ? null : _processScan,
                              icon: isScanning
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.document_scanner, size: 24),
                              label: Text(
                                isScanning ? 'Scanning...' : 'Scan Document',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (extractedText.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: () => voiceService.speak('Recognized text is: $extractedText'),
                              icon: const Icon(Icons.volume_up, size: 22),
                              label: const Text('Read', style: TextStyle(fontSize: 15)),
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
                            child: OutlinedButton.icon(
                              onPressed: _fetchContext,
                              icon: const Icon(Icons.info_outline, size: 22),
                              label: const Text('Context', style: TextStyle(fontSize: 15)),
                              style: OutlinedButton.styleFrom(
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
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _handleVoiceCommand,
                        icon: const Icon(Icons.mic, size: 20),
                        label: const Text('Voice Command Prompt'),
                      ),
                    ),
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
