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

  String status = 'Point your camera at the text and say "capture" or tap to scan.';
  String extractedText = '';
  bool isInitializing = true;
  bool isScanning = false;

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
      setState(() {
        isInitializing = false;
      });
      await voiceService.speak(
        'OCR reader activated. Point your camera at the text and say capture or tap to scan.',
      );
    } catch (e) {
      await voiceService.speak('Camera initialization failed. Returning to main menu.');
      if (mounted) Navigator.pop(context);
    }
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
    }
  }

  Future<void> _processScan() async {
    if (isScanning) return;
    setState(() {
      isScanning = true;
      status = 'Scanning text. Please hold camera steady...';
    });

    await voiceService.speak('Scanning text. Please hold the camera steady.');

    const imagePath = 'scanned_doc.jpg'; // Placeholder camera snapshot path
    final result = await ocrService.recognizeTextFromImage(imagePath);

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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR Reader')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              status,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (extractedText.isNotEmpty)
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      extractedText,
                      style: const TextStyle(fontSize: 16, height: 1.5),
                    ),
                  ),
                ),
              )
            else
              const Expanded(
                child: Center(
                  child: Icon(Icons.document_scanner, size: 80, color: Colors.blueAccent),
                ),
              ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: isScanning ? null : _processScan,
              icon: const Icon(Icons.camera_alt),
              label: Text(isScanning ? 'Scanning...' : 'Scan / Capture Document'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _handleVoiceCommand,
              icon: const Icon(Icons.mic),
              label: const Text('Voice Command Prompt'),
            ),
          ],
        ),
      ),
    );
  }
}
