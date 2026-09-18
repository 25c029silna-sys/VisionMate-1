import 'dart:async';
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
  Timer? _retryTimer;

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

    if (command == null || command.trim().isEmpty) {
      if (mounted) {
        setState(() {
          result = 'Tap microphone button to speak a command.';
        });
      }
      return;
    }

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
      if (mounted) {
        setState(() {
          result = 'Tap microphone button to speak a command.';
        });
      }
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
    _retryTimer?.cancel();
    if (isFlashOn) {
      cameraService.toggleFlash(false);
    }
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
            // Live Camera Viewfinder (Flex: 2)
            Expanded(
              flex: 2,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.tealAccent.withAlpha((0.6 * 255).round()), width: 2),
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
                            CircularProgressIndicator(color: Colors.tealAccent),
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
                      margin: const EdgeInsets.all(20),
                    ),
                  ],
                ),
              ),
            ),
            // Result Display & Action Controls (Flex: 3 so description box has generous space)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Prominent, High-Contrast Scene Description Box
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isAnalyzing
                                ? Colors.tealAccent
                                : Colors.tealAccent.withAlpha((0.4 * 255).round()),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.tealAccent.withAlpha((0.08 * 255).round()),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Row with Icon and Live Status Badge
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.tealAccent.withAlpha((0.15 * 255).round()),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.visibility_rounded,
                                    color: Colors.tealAccent,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'SCENE DESCRIPTION',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.tealAccent,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isAnalyzing
                                        ? Colors.amber.withAlpha((0.2 * 255).round())
                                        : Colors.green.withAlpha((0.2 * 255).round()),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isAnalyzing ? Colors.amberAccent : Colors.greenAccent,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: isAnalyzing ? Colors.amberAccent : Colors.greenAccent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        isAnalyzing ? 'ANALYZING' : 'READY',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isAnalyzing ? Colors.amberAccent : Colors.greenAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6.0),
                              child: Divider(color: Colors.white12, height: 1),
                            ),
                            // Text Output Area with guaranteed visibility
                            Expanded(
                              child: SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Text(
                                  result,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.45,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Action Buttons Row / Compact Stack
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: isAnalyzing ? null : _describeScene,
                        icon: isAnalyzing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.explore, size: 22),
                        label: Text(
                          isAnalyzing ? 'Analyzing Surroundings...' : 'Describe Surroundings',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    VoiceButton(
                      label: 'VOICE COMMAND',
                      subtitle: 'Tap to speak: "Describe", "Repeat", or "Flash"',
                      activeSubtitle: 'Listening... say "Describe" or "Flash"',
                      isListening: isListening,
                      onPressed: _handleVoiceCommand,
                      height: 52,
                      primaryColor: const Color(0xFF1E293B),
                      activeColor: Colors.teal.shade700,
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
