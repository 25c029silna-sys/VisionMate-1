import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/voice/voice_service.dart';
import 'core/voice/command_router.dart';
import 'core/voice/voice_guide_service.dart';
import 'core/storage/storage_service.dart';
import 'core/sensors/shake_detector_service.dart';
import 'features/braille/presentation/braille_screen.dart';
import 'features/digital_library/presentation/library_screen.dart';
import 'features/ocr_reader/presentation/ocr_screen.dart';
import 'features/scene_navigation/presentation/scene_screen.dart';
import 'features/emergency_sos/presentation/emergency_screen.dart';
import 'features/emergency_sos/domain/emergency_service.dart';
import 'widgets/feature_card.dart';
import 'widgets/voice_button.dart';
import 'widgets/voice_command_guide.dart';

class VisionMateApp extends StatelessWidget {
  const VisionMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<VoiceService>(create: (_) => VoiceService()),
        Provider<CommandRouter>(create: (_) => CommandRouter()),
        Provider<StorageService>(create: (_) => StorageService()),
      ],
      child: Builder(
        builder: (context) {
          return GlobalShakeWrapper(
            child: MaterialApp(
              title: 'VisionMate',
              debugShowCheckedModeBanner: false,
              theme: ThemeData.dark().copyWith(
                scaffoldBackgroundColor: const Color(0xFF0D1117),
                appBarTheme: const AppBarTheme(
                  backgroundColor: Color(0xFF161B22),
                  elevation: 0,
                ),
              ),
              initialRoute: '/',
              routes: {
                '/': (_) => const HomeScreen(),
                '/braille': (_) => const BrailleScreen(),
                '/library': (_) => const LibraryScreen(),
                '/ocr': (_) => const OcrScreen(),
                '/scene': (_) => const SceneScreen(),
                '/emergency': (_) => const EmergencyScreen(),
              },
            ),
          );
        },
      ),
    );
  }
}

class GlobalShakeWrapper extends StatefulWidget {
  final Widget child;
  const GlobalShakeWrapper({super.key, required this.child});

  @override
  State<GlobalShakeWrapper> createState() => _GlobalShakeWrapperState();
}

class _GlobalShakeWrapperState extends State<GlobalShakeWrapper> {
  final ShakeDetectorService _shakeDetector = ShakeDetectorService();

  @override
  void initState() {
    super.initState();
    _shakeDetector.startListening(() async {
      if (!mounted) return;
      final voiceService = Provider.of<VoiceService>(context, listen: false);
      final storageService = Provider.of<StorageService>(context, listen: false);
      final emergencyService = EmergencyService();
      await emergencyService.executeGlobalSos(
        storageService: storageService,
        voiceService: voiceService,
      );
    });
  }

  @override
  void dispose() {
    _shakeDetector.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final VoiceService voiceService;
  late final CommandRouter router;
  String status = 'Tap the Voice Button below to give a command, or shake 3 times for SOS.';
  bool isListening = false;

  @override
  void initState() {
    super.initState();
    voiceService = Provider.of<VoiceService>(context, listen: false);
    router = Provider.of<CommandRouter>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await voiceService.speak(
        'Welcome to VisionMate. Tap the voice button to give a command, or shake device 3 times for Emergency SOS.',
      );
    });
  }

  Future<void> _activateVoiceRecognition() async {
    if (isListening) {
      await voiceService.stopListening();
      setState(() {
        isListening = false;
        status = 'Voice listening canceled.';
      });
      return;
    }

    setState(() {
      isListening = true;
      status = 'Listening for voice command... Speak now.';
    });

    await voiceService.speak('Listening. State your command.');
    final command = await voiceService.listen(listenDurationSeconds: 5);

    if (!mounted) return;

    setState(() {
      isListening = false;
    });

    if (command != null && command.trim().isNotEmpty) {
      final text = command.trim();
      setState(() {
        status = 'Heard: "$text"';
      });

      final route = router.routeForCommand(text);
      if (route != null) {
        if (route == '/guide') {
          VoiceCommandGuideModal.show(context);
          await VoiceGuideService(voiceService).readGuideAloud();
        } else {
          await voiceService.speak('Opening module.');
          if (mounted) {
            Navigator.pushNamed(context, route);
          }
        }
      } else {
        await voiceService.speak('Command not recognized. Tap the voice button to try again or say Guide for commands.');
      }
    } else {
      setState(() {
        status = 'No voice input detected. Tap button to try again.';
      });
      await voiceService.speak('No command heard. Tap the button to speak again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withAlpha((0.2 * 255).round()),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.remove_red_eye_rounded, color: Colors.blueAccent, size: 24),
            ),
            const SizedBox(width: 10),
            const Text(
              'VisionMate',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Colors.blueAccent),
            tooltip: 'Voice Commands Guide',
            onPressed: () => VoiceCommandGuideModal.show(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Status & Main Push-To-Talk Button Container
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  VoiceButton(
                    label: 'TAP TO ACTIVATE VOICE',
                    isListening: isListening,
                    onPressed: _activateVoiceRecognition,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isListening ? Icons.graphic_eq_rounded : Icons.info_outline_rounded,
                          size: 18,
                          color: isListening ? Colors.blueAccent : Colors.white54,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 13,
                              color: isListening ? Colors.white : Colors.white70,
                              fontWeight: isListening ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Section Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4),
              child: Row(
                children: [
                  const Text(
                    'MODULES & EMERGENCY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white38,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => VoiceCommandGuideModal.show(context),
                    icon: const Icon(Icons.info_outline, size: 14, color: Colors.blueAccent),
                    label: const Text(
                      'Voice Guide',
                      style: TextStyle(fontSize: 12, color: Colors.blueAccent),
                    ),
                  ),
                ],
              ),
            ),

            // Feature Cards Grid
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  FeatureCard(
                    title: 'OCR Text Reader',
                    description: 'Scan and hear books, labels, signs, & printed documents.',
                    icon: Icons.document_scanner_rounded,
                    primaryColor: Colors.blueAccent,
                    secondaryColor: Colors.cyan,
                    badgeText: 'Tap or Voice',
                    onTap: () => Navigator.pushNamed(context, '/ocr'),
                  ),
                  const SizedBox(height: 12),
                  FeatureCard(
                    title: 'Scene & Navigation',
                    description: 'Real-time obstacle detection and surroundings description.',
                    icon: Icons.remove_red_eye_rounded,
                    primaryColor: Colors.tealAccent,
                    secondaryColor: Colors.green,
                    badgeText: 'Tap or Voice',
                    onTap: () => Navigator.pushNamed(context, '/scene'),
                  ),
                  const SizedBox(height: 12),
                  FeatureCard(
                    title: 'Braille Recognition',
                    description: 'Capture Braille dots and translate them to readable text.',
                    icon: Icons.grid_on_rounded,
                    primaryColor: Colors.amberAccent,
                    secondaryColor: Colors.orange,
                    badgeText: 'Tap or Voice',
                    onTap: () => Navigator.pushNamed(context, '/braille'),
                  ),
                  const SizedBox(height: 12),
                  FeatureCard(
                    title: 'Digital Library',
                    description: 'Semantic vector search across indexed documents & texts.',
                    icon: Icons.menu_book_rounded,
                    primaryColor: Colors.purpleAccent,
                    secondaryColor: Colors.deepPurple,
                    badgeText: 'Tap or Voice',
                    onTap: () => Navigator.pushNamed(context, '/library'),
                  ),
                  const SizedBox(height: 12),
                  FeatureCard(
                    title: 'Emergency SOS',
                    description: 'Instant danger alert with GPS location to emergency contacts (or Shake 3 Times).',
                    icon: Icons.warning_amber_rounded,
                    primaryColor: Colors.redAccent,
                    secondaryColor: Colors.deepOrange,
                    badgeText: 'Shake 3x or Tap',
                    onTap: () => Navigator.pushNamed(context, '/emergency'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Bottom Emergency SOS Quick Access Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF161B22),
                border: Border(
                  top: BorderSide(color: Colors.white12, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pushNamed(context, '/emergency'),
                      icon: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                      label: const Text(
                        'EMERGENCY SOS (OR SHAKE DEVICE 3x)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
