import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visionmate/core/voice/voice_service.dart';
import 'package:visionmate/core/camera/camera_service.dart';
import 'package:visionmate/core/permissions/permission_service.dart';
import 'package:visionmate/features/ocr_reader/domain/ocr_service.dart';
import 'package:visionmate/features/ocr_reader/presentation/ocr_screen.dart';

class MockVoiceService extends Mock implements VoiceService {}
class MockCameraService extends Mock implements CameraService {}
class MockPermissionService extends Mock implements PermissionService {}
class MockOcrService extends Mock implements OcrService {}

void main() {
  late MockVoiceService mockVoiceService;
  late MockCameraService mockCameraService;
  late MockPermissionService mockPermissionService;
  late MockOcrService mockOcrService;

  setUpAll(() {
    registerFallbackValue(ResolutionPreset.high);
  });

  setUp(() {
    mockVoiceService = MockVoiceService();
    mockCameraService = MockCameraService();
    mockPermissionService = MockPermissionService();
    mockOcrService = MockOcrService();

    when(() => mockVoiceService.speak(any())).thenAnswer((_) async {});
    when(() => mockVoiceService.listen()).thenAnswer((_) async => null);
    when(() => mockVoiceService.listen(listenDurationSeconds: any(named: 'listenDurationSeconds'))).thenAnswer((_) async => null);
    when(() => mockPermissionService.requestCameraPermission()).thenAnswer((_) async => true);
    when(() => mockCameraService.initCamera(resolution: any(named: 'resolution'))).thenAnswer((_) async => true);
    when(() => mockCameraService.isInitialized).thenReturn(true);
    when(() => mockCameraService.controller).thenReturn(null);
    when(() => mockCameraService.takePicture()).thenAnswer((_) async => XFile('test_doc.jpg'));
    when(() => mockCameraService.toggleFlash(any())).thenAnswer((_) async {});
    when(() => mockCameraService.dispose()).thenReturn(null);
  });

  Widget buildTestableWidget() {
    return MultiProvider(
      providers: [
        ListenableProvider<VoiceService>.value(value: mockVoiceService),
      ],
      child: MaterialApp(
        home: OcrScreen(
          ocrService: mockOcrService,
          cameraService: mockCameraService,
          permissionService: mockPermissionService,
        ),
      ),
    );
  }

  testWidgets('OcrScreen renders title and scan button successfully', (widgetTester) async {
    await widgetTester.pumpWidget(buildTestableWidget());
    await widgetTester.pump(const Duration(milliseconds: 200));

    expect(find.text('OCR Reader'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Scan Document'), findsOneWidget);
  });

  testWidgets('OcrScreen handles camera permission denial gracefully without crash', (widgetTester) async {
    when(() => mockPermissionService.requestCameraPermission()).thenAnswer((_) async => false);

    await widgetTester.pumpWidget(buildTestableWidget());
    await widgetTester.pump(const Duration(milliseconds: 200));

    verify(() => mockVoiceService.speak('Camera permission denied. Returning to main menu.')).called(1);
  });

  testWidgets('OcrScreen handles extraction failure gracefully with TTS error alert', (widgetTester) async {
    when(() => mockOcrService.recognizeTextFromImage(any()))
        .thenAnswer((_) async => 'EXTRACTION_ERROR');

    await widgetTester.pumpWidget(buildTestableWidget());
    await widgetTester.pump(const Duration(milliseconds: 200));

    final scanButton = find.widgetWithText(ElevatedButton, 'Scan Document');
    await widgetTester.tap(scanButton);
    await widgetTester.pump(const Duration(milliseconds: 500));

    expect(find.text('Something went wrong reading that text, please try again.'), findsOneWidget);
    verify(() => mockVoiceService.speak('Something went wrong reading that text, please try again.')).called(1);
  });

  testWidgets('OcrScreen successfully extracts and displays recognized text', (widgetTester) async {
    when(() => mockOcrService.recognizeTextFromImage(any()))
        .thenAnswer((_) async => 'Chapter 1: The Beginning');

    await widgetTester.pumpWidget(buildTestableWidget());
    await widgetTester.pump(const Duration(milliseconds: 200));

    final scanButton = find.widgetWithText(ElevatedButton, 'Scan Document');
    await widgetTester.tap(scanButton);
    await widgetTester.pump(const Duration(milliseconds: 500));

    expect(find.text('Chapter 1: The Beginning'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    verify(() => mockVoiceService.speak('Recognized text is: Chapter 1: The Beginning')).called(1);
  });
}
