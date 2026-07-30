import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/voice/voice_service.dart';
import 'core/voice/command_router.dart';
import 'core/voice/voice_guide_service.dart';
import 'core/storage/storage_service.dart';
import 'features/braille/presentation/braille_screen.dart';
import 'features/digital_library/presentation/library_screen.dart';
import 'features/ocr_reader/presentation/ocr_screen.dart';
import 'features/scene_navigation/presentation/scene_screen.dart';
import 'features/emergency_sos/presentation/emergency_screen.dart';
import 'widgets/feature_card.dart';
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
  String status = 'Continuous voice activation active...';
  bool isListening = false;

  @override
  void initState() {
    super.initState();
    voiceService = Provider.of<VoiceService>(context, listen: false);
    router = Provider.of<CommandRouter>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await voiceService.speak('Welcome to VisionMate. Continuous voice activation is active.');
      _startVoiceActivation();
    });
  }

  void _startVoiceActivation() {
    setState(() {
      isListening = true;
      status = 'Continuous voice activation active... Speak a command anytime.';
    });
    voiceService.startContinuousListening((command) async {
      if (!mounted) return;
      setState(() {
        status = 'Heard: "$command"';
      });

      final route = router.routeForCommand(command);
      if (route != null) {
        if (route == '/guide') {
          VoiceCommandGuideModal.show(context);
          await VoiceGuideService(voiceService).readGuideAloud();
        } else {
          await voiceService.speak('Opening $route.');
          if (mounted) {
            Navigator.pushNamed(context, route);
          }
        }
      } else {
        await voiceService.speak('Command not recognized. Say Guide or Help for commands.');
      }
    });
  }

  @override
  void dispose() {
    voiceService.stopContinuousListening();
    super.dispose();
  }

  Future<void> _listen() async {
    if (!voiceService.isContinuous) {
      _startVoiceActivation();
    } else {
      voiceService.stopContinuousListening();
      setState(() {
        isListening = false;
        status = 'Voice activation paused. Tap mic to resume.';
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
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Status & Speech Visualizer HUD
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isListening ? Colors.blueAccent : Colors.white12,
                  width: isListening ? 2 : 1,
                ),
                boxShadow: isListening
                    ? [
                        BoxShadow(
                          color: Colors.blueAccent.withAlpha((0.3 * 255).round()),
                          blurRadius: 16,
                          spreadRadius: 2,
                        )
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _listen,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isListening ? Colors.blueAccent : Colors.white10,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isListening ? Icons.mic : Icons.mic_none,
                        color: isListening ? Colors.white : Colors.blueAccent,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              isListening ? 'VOICE LISTENING' : 'VOICE ASSISTANT',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isListening ? Colors.blueAccent : Colors.white38,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isListening ? Colors.greenAccent : Colors.white38,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          status,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Section Label for Sighted / Dual-Use Navigation
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4),
              child: Row(
                children: [
                  const Text(
                    'TOUCH & VOICE MODULES',
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
                      'Voice Commands',
                      style: TextStyle(fontSize: 12, color: Colors.blueAccent),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Feature Cards Grid for Non-Blind / Sighted Users
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
                    badgeText: 'Say "OCR"',
                    onTap: () => Navigator.pushNamed(context, '/ocr'),
                  ),
                  const SizedBox(height: 12),
                  FeatureCard(
                    title: 'Scene & Navigation',
                    description: 'Real-time obstacle detection and surroundings description.',
                    icon: Icons.remove_red_eye_rounded,
                    primaryColor: Colors.tealAccent,
                    secondaryColor: Colors.green,
                    badgeText: 'Say "Scene"',
                    onTap: () => Navigator.pushNamed(context, '/scene'),
                  ),
                  const SizedBox(height: 12),
                  FeatureCard(
                    title: 'Braille Recognition',
                    description: 'Capture Braille dots and translate them to readable text.',
                    icon: Icons.grid_on_rounded,
                    primaryColor: Colors.amberAccent,
                    secondaryColor: Colors.orange,
                    badgeText: 'Say "Braille"',
                    onTap: () => Navigator.pushNamed(context, '/braille'),
                  ),
                  const SizedBox(height: 12),
                  FeatureCard(
                    title: 'Digital Library',
                    description: 'Semantic vector search across indexed documents & texts.',
                    icon: Icons.menu_book_rounded,
                    primaryColor: Colors.purpleAccent,
                    secondaryColor: Colors.deepPurple,
                    badgeText: 'Say "Library"',
                    onTap: () => Navigator.pushNamed(context, '/library'),
                  ),
                  const SizedBox(height: 12),
                  FeatureCard(
                    title: 'Emergency SOS',
                    description: 'Instant danger alert with GPS location to emergency contacts.',
                    icon: Icons.warning_amber_rounded,
                    primaryColor: Colors.redAccent,
                    secondaryColor: Colors.deepOrange,
                    badgeText: 'Say "SOS"',
                    onTap: () => Navigator.pushNamed(context, '/emergency'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Bottom Quick Control Action Bar
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
                      onPressed: _listen,
                      icon: Icon(
                        isListening ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                      ),
                      label: Text(isListening ? 'Listening...' : 'Tap to Speak'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/emergency'),
                    icon: const Icon(Icons.warning_amber_rounded, color: Colors.white),
                    label: const Text('SOS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
