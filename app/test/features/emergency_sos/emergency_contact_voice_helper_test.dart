import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/features/emergency_sos/domain/emergency_contact_voice_helper.dart';

void main() {
  group('EmergencyContactVoiceHelper Unit Tests', () {
    // -------------------------------------------------------------------------
    // 1. Spoken Phone Number Parsing
    // -------------------------------------------------------------------------
    group('parseSpokenPhoneNumber', () {
      test('parses standard digit strings and strips non-digits', () {
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('555-1234'), equals('5551234'));
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('(800) 555-0199'), equals('8005550199'));
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('+1 (415) 555-2671'), equals('+14155552671'));
      });

      test('parses spoken English digit words', () {
        final spoken = 'nine eight seven six five four three two one zero';
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber(spoken), equals('9876543210'));
      });

      test('handles "oh" and "o" as zero', () {
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('eight oh zero five five five zero one zero zero'), equals('8005550100'));
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('nine o eight'), equals('908'));
      });

      test('handles double and triple digit multipliers', () {
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('double nine double eight double seven'), equals('998877'));
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('triple five double zero one'), equals('555001'));
      });

      test('preserves leading plus indicator for international numbers', () {
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('plus one five five five zero one two three'), equals('+15550123'));
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('+91 nine eight seven six five four three two one zero'), equals('+919876543210'));
      });

      test('ignores conversational speech fillers like "the phone number is"', () {
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('the phone number is 9876543210'), equals('9876543210'));
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('my mobile is plus one 800 555 0199 thanks'), equals('+18005550199'));
      });

      test('returns empty string on empty or whitespace-only input', () {
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber(''), equals(''));
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('   '), equals(''));
        expect(EmergencyContactVoiceHelper.parseSpokenPhoneNumber('hello world please'), equals(''));
      });
    });

    // -------------------------------------------------------------------------
    // 2. Phone Number Formatting for TTS Speech Readback
    // -------------------------------------------------------------------------
    group('formatPhoneNumberForSpeech', () {
      test('formats digits with individual spaces for distinct speech', () {
        expect(EmergencyContactVoiceHelper.formatPhoneNumberForSpeech('9876543210'), equals('9 8 7 6 5 4 3 2 1 0'));
      });

      test('pronounces leading plus as "plus"', () {
        expect(EmergencyContactVoiceHelper.formatPhoneNumberForSpeech('+15551234'), equals('plus 1 5 5 5 1 2 3 4'));
      });

      test('handles empty or blank phone number gracefully', () {
        expect(EmergencyContactVoiceHelper.formatPhoneNumberForSpeech(''), equals('none'));
        expect(EmergencyContactVoiceHelper.formatPhoneNumberForSpeech('  '), equals('none'));
      });
    });

    // -------------------------------------------------------------------------
    // 3. Spoken Name Cleaning
    // -------------------------------------------------------------------------
    group('cleanSpokenName', () {
      test('cleans conversational filler words and title-cases', () {
        expect(EmergencyContactVoiceHelper.cleanSpokenName('mom'), equals('Mom'));
        expect(EmergencyContactVoiceHelper.cleanSpokenName('my contact name is doctor john smith'), equals('Doctor John Smith'));
        expect(EmergencyContactVoiceHelper.cleanSpokenName('call them jane doe'), equals('Jane Doe'));
        expect(EmergencyContactVoiceHelper.cleanSpokenName('it is sarah connor'), equals('Sarah Connor'));
      });

      test('strips punctuation and returns empty string on empty input', () {
        expect(EmergencyContactVoiceHelper.cleanSpokenName(''), equals(''));
        expect(EmergencyContactVoiceHelper.cleanSpokenName('  ...  '), equals(''));
      });
    });

    // -------------------------------------------------------------------------
    // 4. Intent Classification Helpers (Confirmation, Cancellation, Keep)
    // -------------------------------------------------------------------------
    group('Intent Classification Helpers', () {
      test('isConfirmation identifies affirmative responses', () {
        expect(EmergencyContactVoiceHelper.isConfirmation('confirm'), isTrue);
        expect(EmergencyContactVoiceHelper.isConfirmation('yes please'), isTrue);
        expect(EmergencyContactVoiceHelper.isConfirmation('save'), isTrue);
        expect(EmergencyContactVoiceHelper.isConfirmation('ok'), isTrue);
        expect(EmergencyContactVoiceHelper.isConfirmation('okay'), isTrue);
        expect(EmergencyContactVoiceHelper.isConfirmation('correct'), isTrue);
        expect(EmergencyContactVoiceHelper.isConfirmation('sounds good'), isTrue);
        expect(EmergencyContactVoiceHelper.isConfirmation('no'), isFalse);
      });

      test('isCancellation identifies abort and exit responses', () {
        expect(EmergencyContactVoiceHelper.isCancellation('cancel'), isTrue);
        expect(EmergencyContactVoiceHelper.isCancellation('no discard'), isTrue);
        expect(EmergencyContactVoiceHelper.isCancellation('stop'), isTrue);
        expect(EmergencyContactVoiceHelper.isCancellation('abort'), isTrue);
        expect(EmergencyContactVoiceHelper.isCancellation('nevermind'), isTrue);
        expect(EmergencyContactVoiceHelper.isCancellation('yes confirm'), isFalse);
      });

      test('isKeepOrSkip identifies intent to retain existing value', () {
        expect(EmergencyContactVoiceHelper.isKeepOrSkip('keep'), isTrue);
        expect(EmergencyContactVoiceHelper.isKeepOrSkip('keep it'), isTrue);
        expect(EmergencyContactVoiceHelper.isKeepOrSkip('skip'), isTrue);
        expect(EmergencyContactVoiceHelper.isKeepOrSkip('leave it'), isTrue);
        expect(EmergencyContactVoiceHelper.isKeepOrSkip('no change'), isTrue);
        expect(EmergencyContactVoiceHelper.isKeepOrSkip('change it'), isFalse);
      });

      test('isContactCommand identifies contact configuration utterances', () {
        expect(EmergencyContactVoiceHelper.isContactCommand('contact'), isTrue);
        expect(EmergencyContactVoiceHelper.isContactCommand('add contact'), isTrue);
        expect(EmergencyContactVoiceHelper.isContactCommand('edit emergency contact'), isTrue);
        expect(EmergencyContactVoiceHelper.isContactCommand('configure contact'), isTrue);
        expect(EmergencyContactVoiceHelper.isContactCommand('change contact'), isTrue);
        expect(EmergencyContactVoiceHelper.isContactCommand('trigger emergency sos'), isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // 5. One-Shot Direct Command Parsing
    // -------------------------------------------------------------------------
    group('parseDirectCommand', () {
      test('parses one-shot "add contact [Name] [Phone]"', () {
        final result = EmergencyContactVoiceHelper.parseDirectCommand('add contact Mom 1234567890');
        expect(result, isNotNull);
        expect(result!.name, equals('Mom'));
        expect(result.phone, equals('1234567890'));
      });

      test('parses one-shot with explicit separator "phone" / "at"', () {
        final r1 = EmergencyContactVoiceHelper.parseDirectCommand('set contact Doctor Smith at 555-1234');
        expect(r1, isNotNull);
        expect(r1!.name, equals('Doctor Smith'));
        expect(r1.phone, equals('5551234'));

        final r2 = EmergencyContactVoiceHelper.parseDirectCommand('edit emergency contact Jane phone number is +15550192834');
        expect(r2, isNotNull);
        expect(r2!.name, equals('Jane'));
        expect(r2.phone, equals('+15550192834'));
      });

      test('parses one-shot with spoken word digits', () {
        final result = EmergencyContactVoiceHelper.parseDirectCommand('add emergency contact Dad nine eight seven six five four three two one zero');
        expect(result, isNotNull);
        expect(result!.name, equals('Dad'));
        expect(result.phone, equals('9876543210'));
      });

      test('returns null when utterance only requests contact flow without arguments', () {
        expect(EmergencyContactVoiceHelper.parseDirectCommand('contact'), isNull);
        expect(EmergencyContactVoiceHelper.parseDirectCommand('add contact'), isNull);
        expect(EmergencyContactVoiceHelper.parseDirectCommand('edit emergency contact'), isNull);
        expect(EmergencyContactVoiceHelper.parseDirectCommand('trigger sos alert'), isNull);
      });
    });
  });
}
