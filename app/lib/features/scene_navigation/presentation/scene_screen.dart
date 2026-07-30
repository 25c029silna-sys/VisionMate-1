import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/voice/voice_service.dart';
import '../domain/scene_service.dart';

class SceneScreen extends StatefulWidget {
  const SceneScreen({super.key});

  @override
  State<SceneScreen> createState() => _SceneScreenState();
}

class _SceneScreenState extends State<SceneScreen> {
  late VoiceService voiceService;
  final SceneService sceneService = SceneService();
  String result = 'Awaiting scene description command.';

  @override
  void initState() {
    super.initState();
    voiceService = Provider.of<VoiceService>(context, listen: false);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await voiceService.speak('Scene description activated. Say describe surroundings to begin.');
    });
  }

  Future<void> _describeScene() async {
    await voiceService.speak('Analyzing surroundings.');
    final text = await sceneService.describeScene();
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scene Navigation')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(result),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _describeScene,
              child: const Text('Describe Surroundings'),
            ),
          ],
        ),
      ),
    );
  }
}
