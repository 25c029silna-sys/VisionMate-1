import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/features/braille/domain/braille_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BrailleService Tests', () {
    late BrailleService brailleService;

    setUp(() {
      brailleService = BrailleService();
    });

    tearDown(() {
      brailleService.dispose();
    });

    test('mapIndexToCharacter returns correct default character mapping', () {
      expect(brailleService.mapIndexToCharacter(0), ' ');
      expect(brailleService.mapIndexToCharacter(32), 'a');
      expect(brailleService.mapIndexToCharacter(48), 'b');
      expect(brailleService.mapIndexToCharacter(43), 'z');
      expect(brailleService.mapIndexToCharacter(100), '?');
    });

    test('assembleBrailleText reconstructs raw character sequence', () {
      // Cell indices for 'a', 'b', 'c' -> 32, 48, 36
      final text = brailleService.assembleBrailleText([32, 48, 36]);
      expect(text, 'abc');
    });

    test('assembleBrailleText converts number sign (#) prefix correctly', () {
      // Cell index for '#' is 15. 'a', 'b' -> 32, 48 become '1', '2'
      final text = brailleService.assembleBrailleText([15, 32, 48]);
      expect(text, '12');
    });

    test('assembleBrailleText handles capital modifier (,) prefix correctly', () {
      // Cell index for ',' is 1. 'h', 'e', 'l', 'l', 'o' -> 50, 34, 56, 56, 42
      final text = brailleService.assembleBrailleText([1, 50, 34, 56, 56, 42]);
      expect(text, 'Hello');
    });
  });
}
