import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../../../core/camera/camera_service.dart';
import '../../../core/voice/voice_service.dart';
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
  
  String result = 'Position camera over Braille page and tap Scan Braille.';
  bool isScanning = false;
  bool isCameraReady = false;

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
    await voiceService.speak('Braille recognition activated. Align page within frame and tap screen to scan.');
  }

  Future<void> _scanBraille() async {
    if (isScanning) return;

    setState(() {
      isScanning = true;
      result = 'Processing Braille page image...';
    });

    await voiceService.speak('Scanning Braille page. Please hold the camera steady.');

    String imagePath = 'captured_braille.jpg';
    if (cameraService.isInitialized) {
      final photo = await cameraService.takePicture();
      if (photo != null) {
        imagePath = photo.path;
      }
    }

    final extracted = await brailleService.classifyBraille(imagePath);

    if (!mounted) return;

    if (extracted == 'MODEL_UNAVAILABLE') {
      const errorMsg = "This feature isn't available yet — the recognition model hasn't been installed.";
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
  }

  @override
  void dispose() {
    cameraService.dispose();
    brailleService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        result,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: isScanning ? null : _scanBraille,
                        icon: isScanning
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt, size: 28),
                        label: Text(
                          isScanning ? 'Processing...' : 'Scan Braille Page',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
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

