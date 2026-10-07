import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/features/braille/domain/braille_text_refiner.dart';
import 'package:visionmate/features/braille/domain/page_border_detector.dart';
import 'package:visionmate/features/braille/domain/printed_braille_detector.dart';

void main() {
  test('Test user text refinement', () {
    const rawUserText = '''cc?a
Acellisthebasic
unitoflife.Every
cellhasamembrane,
cytoplasm,and genetic
material.The nucleus
controlsactivities
and storesDNA.
Mitochondriaproduce
energy. Plantcells
also have acell wall
and chloroplasts,
jhich animalcell;
lack.''';

    print('--- RAW INPUT ---');
    print(rawUserText);

    final refined = BrailleTextRefiner.refineOffline(rawUserText);
    print('\n--- REFINED OUTPUT ---');
    print(refined);

    expect(refined, contains('A cell is the basic'));
    expect(refined, contains('unit of life. Every'));
    expect(refined, contains('cell has a membrane,'));
    expect(refined, contains('cytoplasm, and genetic'));
    expect(refined, contains('material. The nucleus'));
    expect(refined, contains('controls activities'));
    expect(refined, contains('and stores DNA.'));
    expect(refined, contains('Mitochondria produce'));
    expect(refined, contains('energy. Plant cells'));
    expect(refined, contains('also have a cell wall'));
    expect(refined, contains('and chloroplasts,'));
    expect(refined, contains('which animal cells'));
    expect(refined, contains('lack.'));
    expect(refined.contains('cc?a'), isFalse);
  });

  test('Test user latest scan refinement', () {
    const latestScan = '''acc '
A cell is the basic
unit of life. /j-ery
material. The nucleus
Mitochondria produce
energy. Plant cells
also have a cell wall
and chloroplasts,
which animal cells
lack.''';

    final refined = BrailleTextRefiner.refineOffline(latestScan);
    print('\n--- LATEST SCAN REFINED ---');
    print(refined);

    expect(refined.contains("acc '"), isFalse);
    expect(refined.contains("acc"), isFalse);
    expect(refined, contains('unit of life. Every'));
    expect(refined, contains('A cell is the basic'));
    expect(refined, contains('material. The nucleus'));
    expect(refined, contains('Mitochondria produce'));
    expect(refined, contains('energy. Plant cells'));
    expect(refined, contains('also have a cell wall'));
    expect(refined, contains('and chloroplasts,'));
    expect(refined, contains('which animal cells'));
    expect(refined, contains('lack.'));
  });
}
