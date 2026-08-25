import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:visionmate/core/voice/voice_service.dart';
import 'package:visionmate/core/voice/command_router.dart';
import 'package:visionmate/core/storage/storage_service.dart';
import 'package:visionmate/features/braille/presentation/braille_screen.dart';
import 'package:visionmate/features/digital_library/presentation/library_screen.dart';
import 'package:visionmate/features/ocr_reader/presentation/ocr_screen.dart';
import 'package:visionmate/features/scene_navigation/presentation/scene_screen.dart';
import 'package:visionmate/features/emergency_sos/presentation/emergency_screen.dart';

Widget _wrap(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VoiceService>(create: (_) => VoiceService()),
      Provider<CommandRouter>(create: (_) => CommandRouter()),
      Provider<StorageService>(create: (_) => StorageService()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('Braille screen loads', (tester) async {
    await tester.pumpWidget(_wrap(const BrailleScreen()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Scan Braille'), findsOneWidget);
  });

  testWidgets('Library screen loads', (tester) async {
    await tester.pumpWidget(_wrap(const LibraryScreen()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Voice Search Library'), findsOneWidget);
  });

  testWidgets('OCR screen loads', (tester) async {
    await tester.pumpWidget(_wrap(const OcrScreen()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Scan Document'), findsOneWidget);
  });

  testWidgets('Scene screen loads', (tester) async {
    await tester.pumpWidget(_wrap(const SceneScreen()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Describe Surroundings'), findsOneWidget);
  });

  testWidgets('Emergency screen loads', (tester) async {
    await tester.pumpWidget(_wrap(const EmergencyScreen()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('TRIGGER EMERGENCY SOS'), findsOneWidget);
  });
}
