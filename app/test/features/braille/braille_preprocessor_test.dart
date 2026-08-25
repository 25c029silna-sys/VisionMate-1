import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visionmate/features/braille/data/braille_preprocessor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BraillePreprocessor Unit Tests', () {
    late BraillePreprocessor preprocessor;

    setUp(() {
      preprocessor = BraillePreprocessor();
    });

    test('extractCellData extracts expected grid dimensions (6 rows x 10 cols)', () {
      final sampleImage = img.Image(width: 400, height: 300);
      img.fill(sampleImage, color: img.ColorRgb8(255, 255, 255));

      final cells = preprocessor.extractCellData(sampleImage, numRows: 6, numCols: 10);
      expect(cells.length, equals(60));
      expect(cells.first.row, equals(0));
      expect(cells.first.col, equals(0));
      expect(cells.last.row, equals(5));
      expect(cells.last.col, equals(9));
    });

    test('extractCellData identifies empty uniform background cells', () {
      final sampleImage = img.Image(width: 200, height: 200);
      img.fill(sampleImage, color: img.ColorRgb8(200, 200, 200));

      final cells = preprocessor.extractCellData(sampleImage);
      expect(cells.every((c) => c.isEmpty), isTrue);
    });

    test('processImageFile handles non-existent image path gracefully', () async {
      final cells = await preprocessor.processImageFile('non_existent_braille_path.jpg');
      expect(cells, isEmpty);
    });
  });
}
