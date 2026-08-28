import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/voice/voice_service.dart';
import '../../../core/camera/camera_service.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../widgets/voice_button.dart';
import '../domain/scene_service.dart';

class SceneScreen extends StatefulWidget {
  final SceneService? sceneService;
  final CameraService? cameraService;
  final PermissionService? permissionService;

  const SceneScreen({
    super.key,
    this.sceneService,
    this.cameraService,
    this.permissionService,
  });

  @override
  State<SceneScreen> createState() => _SceneScreenState();
}

class _SceneScreenState extends State<SceneScreen> {
  late VoiceService voiceService;
  late final SceneService sceneService;
  late final CameraService cameraService;
  late final PermissionService permissionService;

  String result = 'Point camera at your surroundings and tap Describe Surroundings or say Describe.';
  bool isCameraReady = false;
  bool isAnalyzing = false;
  bool isFlashOn = false;
  bool isListening = false;

  @override
  void initState() {
    super.initState();
    sceneService = widget.sceneService ?? SceneService();
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
        'Scene description activated. Point camera at surroundings and tap Describe Surroundings or say describe surroundings.',
      );
      if (mounted) {
        await _handleVoiceCommand();
      }
    } catch (e) {
      debugPrint('SceneScreen camera init failed: $e');
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
    if (lower.contains('stop')) {
      await voiceService.speak('Stopping playback.');
    } else if (lower.contains('describe') || lower.contains('surroundings') || lower.contains('scan') || lower.contains('navigate') || lower.contains('explore')) {
      await _describeScene();
    } else if (lower.contains('repeat') || lower.contains('again')) {
      if (result.isNotEmpty) {
        await voiceService.speak(result);
      }
    } else if (lower.contains('flash') || lower.contains('light')) {
      await _toggleFlash();
    } else if (lower.contains('back') || lower.contains('home') || lower.contains('exit') || lower.contains('close')) {
      await voiceService.speak('Returning to main menu.');
      if (mounted) Navigator.pop(context);
    } else if (lower.contains('help') || lower.contains('guide')) {
      await voiceService.speak('Available commands: say Describe to analyze surroundings, Repeat to hear again, Flash to toggle flashlight, or Back to exit.');
    } else {
      await voiceService.speak('Command not recognized. Say Describe, Repeat, Flash, or Back.');
    }
  }


  Future<void> _describeScene() async {
    if (isAnalyzing) return;

    setState(() {
      isAnalyzing = true;
      result = 'Analyzing surroundings...';
    });

    await voiceService.speak('Analyzing surroundings. Please hold the camera steady.');

    String? imagePath;
    if (cameraService.isInitialized) {
      final photo = await cameraService.takePicture();
      if (photo != null) {
        imagePath = photo.path;
      }
    }

    final text = await sceneService.describeScene(imagePath);

    if (!mounted) return;
    setState(() {
      isAnalyzing = false;
    });

    if (text == 'MODEL_UNAVAILABLE') {
      const errorMsg = "This feature isn't available yet — the recognition model hasn't been installed.";
      setState(() {
        result = errorMsg;
      });
      await voiceService.speak(errorMsg);
      return;
    }

    setState(() {
      result = text;
    });
    await voiceService.speak(text);
  }

  @override
  void dispose() {
    cameraService.dispose();
    sceneService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scene Navigation'),
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
                    // Obstacle framing guideline
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isAnalyzing ? Colors.greenAccent : Colors.white38,
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
            // Result Display & Action Controls
            Expanded(
              flex: 2,
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
                              height: 1.5,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: isAnalyzing ? null : _describeScene,
                        icon: isAnalyzing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.explore, size: 24),
                        label: Text(
                          isAnalyzing ? 'Analyzing Surroundings...' : 'Describe Surroundings',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    VoiceButton(
                      label: 'VOICE COMMAND',
                      subtitle: 'Tap to speak: "Describe", "Repeat", or "Flash"',
                      activeSubtitle: 'Listening... say "Describe" or "Flash"',
                      isListening: isListening,
                      onPressed: _handleVoiceCommand,
                      primaryColor: const Color(0xFF1E293B),
                      activeColor: Colors.teal.shade700,
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
