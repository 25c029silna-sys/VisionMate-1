import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visionmate/core/voice/voice_service.dart';
import 'package:visionmate/core/camera/camera_service.dart';
import 'package:visionmate/core/permissions/permission_service.dart';
import 'package:visionmate/features/scene_navigation/domain/scene_service.dart';
import 'package:visionmate/features/scene_navigation/presentation/scene_screen.dart';

class MockVoiceService extends Mock implements VoiceService {}
class MockCameraService extends Mock implements CameraService {}
class MockPermissionService extends Mock implements PermissionService {}
class MockSceneService extends Mock implements SceneService {}

void main() {
  late MockVoiceService mockVoiceService;
  late MockCameraService mockCameraService;
  late MockPermissionService mockPermissionService;
  late MockSceneService mockSceneService;

  setUpAll(() {
    registerFallbackValue(ResolutionPreset.high);
  });

  setUp(() {
    mockVoiceService = MockVoiceService();
    mockCameraService = MockCameraService();
    mockPermissionService = MockPermissionService();
    mockSceneService = MockSceneService();

    when(() => mockVoiceService.speak(any())).thenAnswer((_) async {});
    when(() => mockVoiceService.listen()).thenAnswer((_) async => null);
    when(() => mockVoiceService.listen(listenDurationSeconds: any(named: 'listenDurationSeconds'))).thenAnswer((_) async => null);
    when(() => mockPermissionService.requestCameraPermission()).thenAnswer((_) async => true);
    when(() => mockCameraService.initCamera(resolution: any(named: 'resolution'))).thenAnswer((_) async => true);
    when(() => mockCameraService.isInitialized).thenReturn(true);
    when(() => mockCameraService.controller).thenReturn(null);
    when(() => mockCameraService.takePicture()).thenAnswer((_) async => XFile('test_scene.jpg'));
    when(() => mockCameraService.toggleFlash(any())).thenAnswer((_) async {});
    when(() => mockCameraService.dispose()).thenReturn(null);
    when(() => mockSceneService.dispose()).thenReturn(null);
  });

  Widget buildTestableWidget() {
    return MultiProvider(
      providers: [
        ListenableProvider<VoiceService>.value(value: mockVoiceService),
      ],
      child: MaterialApp(
        home: SceneScreen(
          sceneService: mockSceneService,
          cameraService: mockCameraService,
          permissionService: mockPermissionService,
        ),
      ),
    );
  }

  testWidgets('SceneScreen renders title and Describe Surroundings button', (tester) async {
    await tester.pumpWidget(buildTestableWidget());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Scene Navigation'), findsOneWidget);
    expect(find.text('Describe Surroundings'), findsOneWidget);
  });

  testWidgets('SceneScreen handles camera permission denial gracefully', (tester) async {
    when(() => mockPermissionService.requestCameraPermission()).thenAnswer((_) async => false);

    await tester.pumpWidget(buildTestableWidget());
    await tester.pump(const Duration(milliseconds: 200));

    verify(() => mockVoiceService.speak('Camera permission denied. Returning to main menu.')).called(1);
  });

  testWidgets('Tapping Describe Surroundings triggers analysis and speaks detected scene summary', (tester) async {
    when(() => mockSceneService.describeScene(any()))
        .thenAnswer((_) async => 'Warning: chair detected right in front of you.');

    await tester.pumpWidget(buildTestableWidget());
    await tester.pump(const Duration(milliseconds: 200));

    final describeBtn = find.text('Describe Surroundings');
    await tester.tap(describeBtn);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Warning: chair detected right in front of you.'), findsOneWidget);
    verify(() => mockVoiceService.speak('Warning: chair detected right in front of you.')).called(1);
  });

  testWidgets('SceneScreen handles MODEL_UNAVAILABLE gracefully with spoken alert', (tester) async {
    when(() => mockSceneService.describeScene(any()))
        .thenAnswer((_) async => 'MODEL_UNAVAILABLE');

    await tester.pumpWidget(buildTestableWidget());
    await tester.pump(const Duration(milliseconds: 200));

    final describeBtn = find.text('Describe Surroundings');
    await tester.tap(describeBtn);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text("This feature isn't available yet — the recognition model hasn't been installed."), findsOneWidget);
  });
}
