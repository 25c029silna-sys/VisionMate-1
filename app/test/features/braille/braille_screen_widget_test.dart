import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visionmate/core/storage/storage_service.dart';
import 'package:visionmate/core/voice/voice_service.dart';
import 'package:visionmate/core/camera/camera_service.dart';
import 'package:visionmate/features/braille/presentation/braille_screen.dart';

class MockVoiceService extends Mock implements VoiceService {}
class MockCameraService extends Mock implements CameraService {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(ResolutionPreset.high);
  });

  group('BrailleScreen Widget Tests', () {
    late MockVoiceService mockVoiceService;
    late MockCameraService mockCameraService;
    late MockStorageService mockStorageService;

    setUp(() {
      mockVoiceService = MockVoiceService();
      mockCameraService = MockCameraService();
      mockStorageService = MockStorageService();
      when(() => mockVoiceService.speak(any())).thenAnswer((_) async {});
      when(() => mockVoiceService.listen()).thenAnswer((_) async => null);
      when(() => mockVoiceService.listen(listenDurationSeconds: any(named: 'listenDurationSeconds'))).thenAnswer((_) async => null);
      when(() => mockCameraService.initCamera(resolution: any(named: 'resolution'))).thenAnswer((_) async => true);
      when(() => mockCameraService.isInitialized).thenReturn(true);
      when(() => mockCameraService.takePicture()).thenAnswer((_) async => null);
      when(() => mockCameraService.toggleFlash(any())).thenAnswer((_) async {});
      when(() => mockCameraService.dispose()).thenReturn(null);
      when(() => mockStorageService.getSetting(any())).thenAnswer((_) async => null);
      when(() => mockStorageService.setSetting(any(), any())).thenAnswer((_) async {});
    });

    Widget createTestableWidget({CameraService? cameraService, StorageService? storageService}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<VoiceService>.value(value: mockVoiceService),
          Provider<StorageService>.value(value: storageService ?? mockStorageService),
        ],
        child: MaterialApp(
          home: BrailleScreen(cameraService: cameraService ?? mockCameraService),
        ),
      );
    }

    testWidgets('Renders BrailleScreen title, camera view area, and scan button', (tester) async {
      await tester.pumpWidget(createTestableWidget());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Braille Page Recognition'), findsOneWidget);
      expect(find.text('Scan Braille'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
      expect(find.byIcon(Icons.flash_off), findsOneWidget);
      expect(find.byIcon(Icons.vpn_key_rounded), findsOneWidget);
    });

    testWidgets('Tapping flash button toggles flashlight and provides voice feedback', (tester) async {
      await tester.pumpWidget(createTestableWidget());
      await tester.pump(const Duration(milliseconds: 100));

      final flashBtn = find.byTooltip('Turn Flash On');
      expect(flashBtn, findsOneWidget);

      await tester.tap(flashBtn);
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => mockCameraService.toggleFlash(true)).called(1);
      verify(() => mockVoiceService.speak('Flashlight turned on.')).called(1);
      expect(find.byIcon(Icons.flash_on), findsOneWidget);
    });

    testWidgets('Tapping Scan Braille triggers scan sequence and voice feedback', (tester) async {
      await tester.pumpWidget(createTestableWidget());
      await tester.pump(const Duration(milliseconds: 100));

      final scanButton = find.text('Scan Braille');
      expect(scanButton, findsOneWidget);

      await tester.tap(scanButton);
      await tester.pump(const Duration(milliseconds: 500));

      verify(() => mockVoiceService.speak(any())).called(greaterThanOrEqualTo(1));
    });

    testWidgets('Tapping maximize button enlarges camera area and provides voice feedback', (tester) async {
      await tester.pumpWidget(createTestableWidget());
      await tester.pump(const Duration(milliseconds: 100));

      final expandBtn = find.byTooltip('Enlarge Camera View for Large Page');
      expect(expandBtn, findsOneWidget);

      await tester.tap(expandBtn);
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => mockVoiceService.speak('Camera area enlarged for reading large Braille pages.')).called(1);
      expect(find.byTooltip('Restore Camera View'), findsOneWidget);
    });

    testWidgets('Tapping Gemini API key button opens configuration dialog and saves key', (tester) async {
      await tester.pumpWidget(createTestableWidget());
      await tester.pump(const Duration(milliseconds: 100));

      final keyBtn = find.byTooltip('Configure Gemini API Key');
      expect(keyBtn, findsOneWidget);

      await tester.tap(keyBtn);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Gemini API Key'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'AIzaSyTestMockKey123');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(milliseconds: 200));

      verify(() => mockStorageService.setSetting('gemini_api_key', 'AIzaSyTestMockKey123')).called(1);
      verify(() => mockVoiceService.speak(any(that: contains('Gemini API key saved')))).called(1);
    });
  });
}
