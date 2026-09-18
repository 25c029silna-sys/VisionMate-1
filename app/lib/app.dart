import 'dart:async';
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

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final RouteObserver<PageRoute> appRouteObserver = RouteObserver<PageRoute>();

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
              navigatorKey: rootNavigatorKey,
              navigatorObservers: [appRouteObserver],
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
  late VoiceService _voiceService;
  late StorageService _storageService;

  @override
  void initState() {
    super.initState();
    _voiceService = Provider.of<VoiceService>(context, listen: false);
    _storageService = Provider.of<StorageService>(context, listen: false);

    // Gesture-triggered SOS with 8-second voice cancellation window
    _shakeDetector.startListening(() async {
      if (!mounted) return;
      final emergencyService = EmergencyService();
      await emergencyService.executeGlobalSos(
        storageService: _storageService,
        voiceService: _voiceService,
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

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  late final VoiceService voiceService;
  late final CommandRouter router;
  String status = 'Voice ready. Tap microphone or shake for SOS.';
  bool isListening = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    voiceService = Provider.of<VoiceService>(context, listen: false);
    router = Provider.of<CommandRouter>(context, listen: false);

    // Auto-activate voice input at app startup
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await voiceService.speak(
        'Welcome to VisionMate. Listening for your command...',
        awaitCompletion: true,
      );
      if (mounted) {
        await _activateVoiceRecognition();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() {
    // Stop listening when navigating to a child module
    _retryTimer?.cancel();
    if (isListening) {
      voiceService.stopListening();
      if (mounted) {
        setState(() {
          isListening = false;
          status = 'Voice listening paused.';
        });
      }
    }
  }

  @override
  void didPopNext() {
    // Automatically reactivate voice input when returning to the HomeScreen
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await voiceService.speak(
        'Returned to main menu. Listening for your command...',
        awaitCompletion: true,
      );
      if (mounted) {
        await _activateVoiceRecognition();
      }
    });
  }

  Future<void> _navigateToModule(String route) async {
    if (isListening) {
      await voiceService.stopListening();
      if (mounted) {
        setState(() {
          isListening = false;
          status = 'Opening module...';
        });
      }
    }
    if (mounted) {
      await Navigator.pushNamed(context, route);
    }
  }

  Future<void> _activateVoiceRecognition() async {
    _retryTimer?.cancel();
    if (isListening) {
      await voiceService.stopListening();
      if (mounted) {
        setState(() {
          isListening = false;
          status = 'Voice listening paused. Tap microphone button to speak.';
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        isListening = true;
        status = 'Listening for voice command... Speak now.';
      });
    }

    final command = await voiceService.listen();

    if (!mounted) return;

    setState(() {
      isListening = false;
    });

    if (command != null && command.trim().isNotEmpty) {
      final text = command.trim();
      setState(() {
        status = 'Heard: "$text"';
      });

      // Check if user just said the wake word alone
      if (CommandRouter.containsWakeWord(text) &&
          CommandRouter.extractCommandAfterWakeWord(text).isEmpty) {
        await voiceService.speak('I am listening. State a feature name like Braille, OCR, Library, Scene, or SOS.');
        if (mounted) {
          await _activateVoiceRecognition();
        }
        return;
      }

      final route = router.routeForCommand(text);
      if (route != null) {
        if (route == '/guide') {
          VoiceCommandGuideModal.show(context);
          await VoiceGuideService(voiceService).readGuideAloud();
        } else {
          await voiceService.speak('Opening module.');
          if (mounted) {
            await _navigateToModule(route);
          }
        }
      } else {
        await voiceService.speak('Command not recognized. Tap the voice button, say VisionMate, or say Guide for help.');
        if (mounted) {
          setState(() {
            status = 'Command not recognized. Tap microphone button to speak.';
          });
        }
      }
    } else {
      setState(() {
        status = 'No voice input detected. Say "VisionMate" or tap button to speak.';
      });
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
                onTap: () => _navigateToModule('/braille'),
              ),
              const SizedBox(height: 12),

              FeatureCard(
                title: 'Digital Library & RAG',
                description: 'Search saved books, notes, and PDF documents using spoken voice queries.',
                icon: Icons.local_library_rounded,
                primaryColor: Colors.purpleAccent,
                secondaryColor: Colors.deepPurple,
                badgeText: 'OFFLINE RAG',
                onTap: () => _navigateToModule('/library'),
              ),
              const SizedBox(height: 12),

              FeatureCard(
                title: 'OCR Text Reader',
                description: 'Read printed text documents, signboards, and mail aloud.',
                icon: Icons.document_scanner_rounded,
                primaryColor: Colors.lightBlueAccent,
                secondaryColor: Colors.blue,
                badgeText: 'TEXT TO SPEECH',
                onTap: () => _navigateToModule('/ocr'),
              ),
              const SizedBox(height: 12),

              FeatureCard(
                title: 'Scene & Indoor Navigation',
                description: 'Detect obstacles, doors, and surroundings in real time.',
                icon: Icons.explore_rounded,
                primaryColor: Colors.tealAccent,
                secondaryColor: Colors.teal,
                badgeText: 'YOLO REAL-TIME',
                onTap: () => _navigateToModule('/scene'),
              ),
              const SizedBox(height: 12),

              FeatureCard(
                title: 'Emergency SOS',
                description: 'Shake device 3 times to send GPS coordinates to trusted contacts.',
                icon: Icons.warning_rounded,
                primaryColor: Colors.redAccent,
                secondaryColor: Colors.red,
                badgeText: 'SAFETY',
                onTap: () => _navigateToModule('/emergency'),
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

