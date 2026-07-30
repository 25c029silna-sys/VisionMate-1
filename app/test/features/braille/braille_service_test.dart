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
      expect(brailleService.mapIndexToCharacter(0), 'a');
      expect(brailleService.mapIndexToCharacter(1), 'b');
      expect(brailleService.mapIndexToCharacter(25), 'z');
      expect(brailleService.mapIndexToCharacter(63), ' ');
      expect(brailleService.mapIndexToCharacter(100), '?');
    });

    test('assembleBrailleText reconstructs raw character sequence', () {
      // Cell indices for 'a', 'b', 'c' -> 0, 1, 2
      final text = brailleService.assembleBrailleText([0, 1, 2]);
      expect(text, 'abc');
    });

    test('assembleBrailleText converts number sign (#) prefix correctly', () {
      // Cell index for '#' is 49. 'a', 'b' -> 0, 1 become '1', '2'
      final text = brailleService.assembleBrailleText([49, 0, 1]);
      expect(text, '12');
    });

    test('assembleBrailleText handles capital modifier (,) prefix correctly', () {
      // Cell index for ',' is 37. 'h', 'e', 'l', 'l', 'o' -> 7, 4, 11, 11, 14
      final text = brailleService.assembleBrailleText([37, 7, 4, 11, 11, 14]);
      expect(text, 'Hello');
    });
  });
}
