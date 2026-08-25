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
    expect(find.text('Scan Braille'), findsOneWidget);
  });

  testWidgets('Library screen loads', (tester) async {
    await tester.pumpWidget(_wrap(const LibraryScreen()));
    expect(find.text('Search Library'), findsOneWidget);
  });

  testWidgets('OCR screen loads', (tester) async {
    await tester.pumpWidget(_wrap(const OcrScreen()));
    expect(find.text('Read Document'), findsOneWidget);
  });

  testWidgets('Scene screen loads', (tester) async {
    await tester.pumpWidget(_wrap(const SceneScreen()));
    expect(find.text('Describe Surroundings'), findsOneWidget);
  });

  testWidgets('Emergency screen loads', (tester) async {
    await tester.pumpWidget(_wrap(const EmergencyScreen()));
    expect(find.text('Send Emergency SOS'), findsOneWidget);
  });
}
