import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/core/voice/voice_post_process_helper.dart';

void main() {
  group('VoicePostProcessHelper Unit Tests', () {
    test('isRepeatOrAgain accurately identifies repeat and process-again commands', () {
      expect(VoicePostProcessHelper.isRepeatOrAgain('again'), isTrue);
      expect(VoicePostProcessHelper.isRepeatOrAgain('do it again'), isTrue);
      expect(VoicePostProcessHelper.isRepeatOrAgain('repeat'), isTrue);
      expect(VoicePostProcessHelper.isRepeatOrAgain('scan again'), isTrue);
      expect(VoicePostProcessHelper.isRepeatOrAgain('search again'), isTrue);
      expect(VoicePostProcessHelper.isRepeatOrAgain('try again'), isTrue);
      expect(VoicePostProcessHelper.isRepeatOrAgain('one more time'), isTrue);
      expect(VoicePostProcessHelper.isRepeatOrAgain('can you repeat please'), isTrue);
      expect(VoicePostProcessHelper.isRepeatOrAgain('scan another document'), isTrue);
      expect(VoicePostProcessHelper.isRepeatOrAgain('edit contact again'), isTrue);
      expect(VoicePostProcessHelper.isRepeatOrAgain('describe'), isTrue);
      expect(VoicePostProcessHelper.isRepeatOrAgain(''), isFalse);
      expect(VoicePostProcessHelper.isRepeatOrAgain(null), isFalse);
    });

    test('isHomeOrExit accurately identifies home, back, and exit commands', () {
      expect(VoicePostProcessHelper.isHomeOrExit('home'), isTrue);
      expect(VoicePostProcessHelper.isHomeOrExit('go home'), isTrue);
      expect(VoicePostProcessHelper.isHomeOrExit('back'), isTrue);
      expect(VoicePostProcessHelper.isHomeOrExit('go back'), isTrue);
      expect(VoicePostProcessHelper.isHomeOrExit('main menu'), isTrue);
      expect(VoicePostProcessHelper.isHomeOrExit('back to main'), isTrue);
      expect(VoicePostProcessHelper.isHomeOrExit('exit'), isTrue);
      expect(VoicePostProcessHelper.isHomeOrExit('close'), isTrue);
      expect(VoicePostProcessHelper.isHomeOrExit('return'), isTrue);
      expect(VoicePostProcessHelper.isHomeOrExit('take me home'), isTrue);
      expect(VoicePostProcessHelper.isHomeOrExit(''), isFalse);
      expect(VoicePostProcessHelper.isHomeOrExit(null), isFalse);
    });

    test('formatPrompt produces clear spoken instructions', () {
      final prompt = VoicePostProcessHelper.formatPrompt('scan another document');
      expect(prompt, equals('Say again to scan another document, or say home to return to the main menu.'));
    });
  });
}
