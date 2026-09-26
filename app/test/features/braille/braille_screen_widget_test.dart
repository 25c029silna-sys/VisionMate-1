import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visionmate/core/storage/storage_service.dart';
import 'package:visionmate/core/voice/voice_service.dart';
import 'package:visionmate/core/camera/camera_service.dart';
import 'package:visionmate/features/braille/presentation/braille_screen.dart';

import 'package:visionmate/features/braille/domain/braille_service.dart';
import 'package:visionmate/features/braille/domain/page_border_detector.dart';

class MockVoiceService extends Mock implements VoiceService {}
class MockCameraService extends Mock implements CameraService {}
class MockStorageService extends Mock implements StorageService {}
class MockBrailleService extends Mock implements BrailleService {}

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

    Widget createTestableWidget({
      CameraService? cameraService,
      BrailleService? brailleService,
      StorageService? storageService,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<VoiceService>.value(value: mockVoiceService),
          Provider<StorageService>.value(value: storageService ?? mockStorageService),
        ],
        child: MaterialApp(
          home: BrailleScreen(
            cameraService: cameraService ?? mockCameraService,
            brailleService: brailleService,
          ),
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
      // Gemini API key and Demo buttons are removed
      expect(find.byIcon(Icons.vpn_key_rounded), findsNothing);
      expect(find.text('ML Kit'), findsNothing);
      expect(find.text('Border Demo'), findsNothing);
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

    testWidgets('Does not render border crop HUD or demo buttons', (tester) async {
      await tester.pumpWidget(createTestableWidget());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('BORDER CROP: ON'), findsNothing);
      expect(find.text('BORDER CROP: OFF'), findsNothing);
      expect(find.text('ML Kit'), findsNothing);
      expect(find.text('Border Demo'), findsNothing);
    });

    testWidgets('Voice command "save pdf as biology notes" warns when no text has been scanned', (tester) async {
      when(() => mockVoiceService.listen()).thenAnswer((_) async => 'save pdf as biology notes');
      await tester.pumpWidget(createTestableWidget());
      await tester.pump(const Duration(milliseconds: 300));

      verify(() => mockVoiceService.speak('No recognized Braille text available to export.')).called(1);
    });

    testWidgets('Starts voice capture instance after all recognized braille text is spoken by TTS', (tester) async {
      final mockBrailleService = MockBrailleService();
      when(() => mockCameraService.takePicture()).thenAnswer((_) async => XFile('mock/test.jpg'));
      when(() => mockBrailleService.scanBrailleWithBorderCrop(any(), enableBorderCrop: any(named: 'enableBorderCrop')))
          .thenAnswer((_) async => BrailleScanResult(
            text: 'Recognized Braille Text Sample',
            pageBorder: PageBorderDetector.createFallbackBorder(100, 100),
            isBorderDetected: false,
            originalWidth: 100,
            originalHeight: 100,
            croppedWidth: 100,
            croppedHeight: 100,
            elapsed: Duration.zero,
          ));

      await tester.pumpWidget(createTestableWidget(brailleService: mockBrailleService));
      await tester.pump(const Duration(milliseconds: 100));

      final scanButton = find.text('Scan Braille');
      await tester.tap(scanButton);
      await tester.pump(const Duration(milliseconds: 500));

      verifyInOrder([
        () => mockVoiceService.speak('Braille recognition complete. Recognized text: Recognized Braille Text Sample'),
        () => mockVoiceService.listen(),
      ]);
    });

    testWidgets('Returns to home page after saving a PDF via voice command', (tester) async {
      final mockBrailleService = MockBrailleService();
      when(() => mockCameraService.takePicture()).thenAnswer((_) async => XFile('mock/test.jpg'));
      when(() => mockBrailleService.scanBrailleWithBorderCrop(any(), enableBorderCrop: any(named: 'enableBorderCrop')))
          .thenAnswer((_) async => BrailleScanResult(
            text: 'Biology Notes',
            pageBorder: PageBorderDetector.createFallbackBorder(100, 100),
            isBorderDetected: false,
            originalWidth: 100,
            originalHeight: 100,
            croppedWidth: 100,
            croppedHeight: 100,
            elapsed: Duration.zero,
          ));

      final testPdf = File('${Directory.systemTemp.path}/test_biology_notes.pdf');
      await testPdf.writeAsString('%PDF mock');
      when(() => mockBrailleService.exportBrailleTextToPdf(any(), title: any(named: 'title')))
          .thenAnswer((_) async => testPdf);

      int listenCount = 0;
      when(() => mockVoiceService.listen()).thenAnswer((_) async {
        listenCount++;
        if (listenCount >= 2) {
          return 'save pdf as biology notes';
        }
        return null;
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<VoiceService>.value(value: mockVoiceService),
            Provider<StorageService>.value(value: mockStorageService),
          ],
          child: MaterialApp(
            initialRoute: '/',
            routes: {
              '/': (context) => const Scaffold(body: Text('Home Page Screen')),
              '/braille': (context) => BrailleScreen(
                cameraService: mockCameraService,
                brailleService: mockBrailleService,
              ),
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final navState = tester.state<NavigatorState>(find.byType(Navigator));
      navState.pushNamed('/braille');
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Braille Page Recognition'), findsOneWidget);

      final scanButton = find.text('Scan Braille');
      await tester.tap(scanButton);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Home Page Screen'), findsOneWidget);
      expect(find.text('Braille Page Recognition'), findsNothing);

      if (await testPdf.exists()) {
        await testPdf.delete();
      }
    });
  });
}
