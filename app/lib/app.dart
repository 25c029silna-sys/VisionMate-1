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
        ChangeNotifierProvider<VoiceService>(create: (_) => VoiceService()),
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
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Voice Status Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isListening ? Colors.greenAccent : Colors.blueAccent.withAlpha((0.4 * 255).round()),
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isListening ? Icons.mic_rounded : Icons.info_outline_rounded,
                      color: isListening ? Colors.greenAccent : Colors.blueAccent,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        status,
                        style: const TextStyle(fontSize: 15, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'ASSISTIVE MODULES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white54,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),

              FeatureCard(
                title: 'Braille Recognition',
                description: 'Scan tactile Braille on paper and hear translated text.',
                icon: Icons.grid_on_rounded,
                primaryColor: Colors.amberAccent,
                secondaryColor: Colors.amber,
                badgeText: 'TACTILE',
                onTap: () => Navigator.pushNamed(context, '/braille'),
              ),
              const SizedBox(height: 12),

              FeatureCard(
                title: 'Digital Library & RAG',
                description: 'Search saved books, notes, and PDF documents using spoken voice queries.',
                icon: Icons.local_library_rounded,
                primaryColor: Colors.purpleAccent,
                secondaryColor: Colors.deepPurple,
                badgeText: 'OFFLINE RAG',
                onTap: () => Navigator.pushNamed(context, '/library'),
              ),
              const SizedBox(height: 12),

              FeatureCard(
                title: 'OCR Text Reader',
                description: 'Read printed text documents, signboards, and mail aloud.',
                icon: Icons.document_scanner_rounded,
                primaryColor: Colors.lightBlueAccent,
                secondaryColor: Colors.blue,
                badgeText: 'TEXT TO SPEECH',
                onTap: () => Navigator.pushNamed(context, '/ocr'),
              ),
              const SizedBox(height: 12),

              FeatureCard(
                title: 'Scene & Indoor Navigation',
                description: 'Detect obstacles, doors, and surroundings in real time.',
                icon: Icons.explore_rounded,
                primaryColor: Colors.tealAccent,
                secondaryColor: Colors.teal,
                badgeText: 'YOLO REAL-TIME',
                onTap: () => Navigator.pushNamed(context, '/scene'),
              ),
              const SizedBox(height: 12),

              FeatureCard(
                title: 'Emergency SOS',
                description: 'Shake device 3 times to send GPS coordinates to trusted contacts.',
                icon: Icons.warning_rounded,
                primaryColor: Colors.redAccent,
                secondaryColor: Colors.red,
                badgeText: 'SAFETY',
                onTap: () => Navigator.pushNamed(context, '/emergency'),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: VoiceButton(
          label: 'TAP TO SPEAK COMMAND',
          subtitle: 'Say "Braille", "OCR", "Library", "Scene", or "SOS"',
          activeSubtitle: 'Listening... speak feature name or command',
          isListening: isListening,
          onPressed: _activateVoiceRecognition,
          primaryColor: const Color(0xFF1E293B),
          activeColor: const Color(0xFF2563EB),
        ),
      ),
    );
  }
}

