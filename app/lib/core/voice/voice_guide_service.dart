import 'voice_service.dart';

class VoiceGuideService {
  final VoiceService voiceService;

  VoiceGuideService(this.voiceService);

  /// Comprehensive spoken list of all supported voice commands across VisionMate.
  static const List<Map<String, String>> commandGuide = [
    {
      'title': 'Emergency SOS',
      'command': 'Say Emergency, SOS, or Help me',
      'description': 'Triggers emergency alert with GPS location and calls your trusted contact.',
    },
    {
      'title': 'OCR Text Reader',
      'command': 'Say OCR, Read text, or Scan document',
      'description': 'Scans and reads printed pages, signs, and labels aloud.',
    },
    {
      'title': 'Scene & Obstacles',
      'command': 'Say Scene, Describe, or Obstacles',
      'description': 'Describes your surroundings and detects immediate navigation obstacles.',
    },
    {
      'title': 'Braille Recognition',
      'command': 'Say Braille or Tactile',
      'description': 'Scans Braille dots via camera and translates them into text.',
    },
    {
      'title': 'Smart Digital Library',
      'command': 'Say Library or Search',
      'description': 'Performs semantic vector search across your saved notes and books.',
    },
    {
      'title': 'Voice Commands Guide',
      'command': 'Say Guide, Commands, or Help',
      'description': 'Repeats this interactive spoken guide of all available commands.',
    },
  ];

  /// Reads out the comprehensive list of commands sequentially via TTS speech talkback.
  Future<void> readGuideAloud() async {
    await voiceService.speak('Starting VisionMate Voice Commands Guide.');
    await voiceService.speak('Here is the comprehensive list of voice commands you can use anytime.');

    for (final item in commandGuide) {
      final text = '${item['title']}. ${item['command']}. ${item['description']}';
      await voiceService.speak(text);
    }

    await voiceService.speak('End of Voice Commands Guide. Simply speak any of these commands now.');
  }
}
