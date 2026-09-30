import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visionmate/core/voice/voice_service.dart';
import 'package:visionmate/core/voice/command_router.dart';
import 'package:visionmate/core/voice/voice_post_process_helper.dart';
import 'package:visionmate/core/storage/storage_service.dart';
import 'package:visionmate/core/camera/camera_service.dart';
import 'package:visionmate/core/permissions/permission_service.dart';
import 'package:visionmate/features/ocr_reader/domain/ocr_service.dart';
import 'package:visionmate/features/ocr_reader/presentation/ocr_screen.dart';
import 'package:visionmate/features/scene_navigation/domain/scene_service.dart';
import 'package:visionmate/features/scene_navigation/presentation/scene_screen.dart';
import 'package:visionmate/features/braille/domain/braille_service.dart';
import 'package:visionmate/features/braille/presentation/braille_screen.dart';
import 'package:visionmate/features/digital_library/presentation/library_screen.dart';
import 'package:visionmate/features/emergency_sos/presentation/emergency_screen.dart';

class MockVoiceService extends Mock implements VoiceService {}
class MockStorageService extends Mock implements StorageService {}
class MockCameraService extends Mock implements CameraService {}
class MockPermissionService extends Mock implements PermissionService {}
class MockOcrService extends Mock implements OcrService {}
class MockBrailleService extends Mock implements BrailleService {}
class MockSceneService extends Mock implements SceneService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(ResolutionPreset.high);
    registerFallbackValue(const Duration(seconds: 8));
  });

  late MockVoiceService mockVoiceService;
  late MockStorageService mockStorageService;
  late MockCameraService mockCameraService;
  late MockPermissionService mockPermissionService;
  late MockOcrService mockOcrService;
  late MockBrailleService mockBrailleService;
  late MockSceneService mockSceneService;
  late CommandRouter commandRouter;

  setUp(() {
    mockVoiceService = MockVoiceService();
    mockStorageService = MockStorageService();
    mockCameraService = MockCameraService();
    mockPermissionService = MockPermissionService();
    mockOcrService = MockOcrService();
    mockBrailleService = MockBrailleService();
    mockSceneService = MockSceneService();
    commandRouter = CommandRouter();

    when(() => mockVoiceService.speak(any(), awaitCompletion: any(named: 'awaitCompletion')))
        .thenAnswer((_) async {});
    when(() => mockVoiceService.speak(any()))
        .thenAnswer((_) async {});
    when(() => mockVoiceService.listen(
          listenDurationSeconds: any(named: 'listenDurationSeconds'),
          pauseDurationSeconds: any(named: 'pauseDurationSeconds'),
        )).thenAnswer((_) async => null);
    when(() => mockVoiceService.listen(
          listenDurationSeconds: any(named: 'listenDurationSeconds'),
        )).thenAnswer((_) async => null);
    when(() => mockVoiceService.listen()).thenAnswer((_) async => null);
    when(() => mockVoiceService.stopListening()).thenAnswer((_) async {});
    when(() => mockVoiceService.stopSpeaking()).thenAnswer((_) async {});

    when(() => mockStorageService.fetchDocuments()).thenAnswer((_) async => [
      {
        'id': 1,
        'title': 'Test Document',
        'text': 'This is a sample document for testing post process voice loop.',
        'source_type': 'test',
        'created_at': '2026-01-01',
      }
    ]);
    when(() => mockStorageService.getTrustedContact()).thenAnswer((_) async => {
      'name': 'Mom',
      'phone': '9876543210',
    });
    when(() => mockStorageService.saveTrustedContact(name: any(named: 'name'), phone: any(named: 'phone')))
        .thenAnswer((_) async {});

    when(() => mockPermissionService.requestCameraPermission()).thenAnswer((_) async => true);
    when(() => mockCameraService.initCamera(resolution: any(named: 'resolution'))).thenAnswer((_) async => true);
    when(() => mockCameraService.isInitialized).thenReturn(true);
    when(() => mockCameraService.controller).thenReturn(null);
    when(() => mockCameraService.dispose()).thenAnswer((_) async {});
    when(() => mockSceneService.dispose()).thenAnswer((_) async {});
  });

  Widget wrapWithProviders(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<VoiceService>.value(value: mockVoiceService),
        Provider<CommandRouter>.value(value: commandRouter),
        Provider<StorageService>.value(value: mockStorageService),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('Post-Process Voice Loop & Auto-Activation Test Suite', () {
    testWidgets('LibraryScreen automatically announces and activates voice search on screen load', (tester) async {
      await tester.pumpWidget(wrapWithProviders(const LibraryScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify that Digital Library speaks readiness and starts listening immediately
      verify(() => mockVoiceService.speak(
        any(that: contains('Digital library ready')),
        awaitCompletion: true,
      )).called(1);

      verify(() => mockVoiceService.listen(
        listenDurationSeconds: any(named: 'listenDurationSeconds'),
        pauseDurationSeconds: any(named: 'pauseDurationSeconds'),
      )).called(1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('OcrScreen offers post-process voice options after text extraction', (tester) async {
      when(() => mockOcrService.recognizeTextFromImage(any())).thenAnswer((_) async => 'Sample Scanned Text');

      await tester.pumpWidget(wrapWithProviders(OcrScreen(
        ocrService: mockOcrService,
        cameraService: mockCameraService,
        permissionService: mockPermissionService,
      )));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify camera and prompt was announced
      verify(() => mockVoiceService.speak(any(that: contains('OCR reader activated')))).called(1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('BrailleScreen offers post-process voice options with save PDF prompt', (tester) async {
      await tester.pumpWidget(wrapWithProviders(BrailleScreen(
        cameraService: mockCameraService,
        brailleService: mockBrailleService,
      )));
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => mockVoiceService.speak(any(that: contains('Braille recognition activated')))).called(1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('SceneScreen initializes and speaks surroundings prompt', (tester) async {
      await tester.pumpWidget(wrapWithProviders(SceneScreen(
        sceneService: mockSceneService,
        cameraService: mockCameraService,
        permissionService: mockPermissionService,
      )));
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => mockVoiceService.speak(any(that: contains('Scene description activated')))).called(1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('EmergencyScreen uses extended 35s listening and 7s pause for phone number input', (tester) async {
      await tester.pumpWidget(wrapWithProviders(const EmergencyScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      // Trigger voice contact setup
      final state = tester.state(find.byType(EmergencyScreen));
      (state as dynamic).startVoiceContactSetup();

      // Turn 1: Name input
      when(() => mockVoiceService.listen(listenDurationSeconds: 25, pauseDurationSeconds: 6))
          .thenAnswer((_) async => 'Dr Smith');

      // Turn 2: Phone input - verify generous 35s and 7s timing
      when(() => mockVoiceService.listen(listenDurationSeconds: 35, pauseDurationSeconds: 7))
          .thenAnswer((_) async => '9876543210');

      // Turn 3: Confirmation
      when(() => mockVoiceService.listen(listenDurationSeconds: 20, pauseDurationSeconds: 6))
          .thenAnswer((_) async => 'confirm');

      // Turn 4: Post-contact options
      when(() => mockVoiceService.listen(listenDurationSeconds: 15, pauseDurationSeconds: 4))
          .thenAnswer((_) async => 'home');

      await tester.pump(const Duration(milliseconds: 100));

      verify(() => mockVoiceService.listen(listenDurationSeconds: 25, pauseDurationSeconds: 6)).called(1);
      verify(() => mockVoiceService.listen(listenDurationSeconds: 35, pauseDurationSeconds: 7)).called(1);
      verify(() => mockVoiceService.listen(listenDurationSeconds: 20, pauseDurationSeconds: 6)).called(1);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
