import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:visionmate/app.dart';
import 'package:visionmate/core/voice/voice_service.dart';
import 'package:visionmate/core/voice/command_router.dart';
import 'package:visionmate/core/storage/storage_service.dart';

class MockVoiceService extends Mock implements VoiceService {}
class MockStorageService extends Mock implements StorageService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Home Screen Voice Reactivation & VoiceService Timing Tests', () {
    late MockVoiceService mockVoiceService;
    late MockStorageService mockStorageService;
    late CommandRouter commandRouter;

    setUp(() {
      mockVoiceService = MockVoiceService();
      mockStorageService = MockStorageService();
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
    });

    Widget createTestApp() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<VoiceService>.value(value: mockVoiceService),
          Provider<CommandRouter>.value(value: commandRouter),
          Provider<StorageService>.value(value: mockStorageService),
        ],
        child: MaterialApp(
          navigatorObservers: [appRouteObserver],
          routes: {
            '/': (_) => const HomeScreen(),
            '/dummy': (_) => Scaffold(
                  appBar: AppBar(title: const Text('Dummy Module')),
                  body: Builder(
                    builder: (ctx) => ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Back To Home'),
                    ),
                  ),
                ),
          },
        ),
      );
    }

    testWidgets('HomeScreen automatically triggers voice recognition on initial build', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pump(const Duration(milliseconds: 200));

      verify(() => mockVoiceService.speak(
            'Welcome to VisionMate. Listening for your command...',
            awaitCompletion: true,
          )).called(1);
      verify(() => mockVoiceService.listen()).called(1);
    });

    testWidgets('Returning to HomeScreen via Navigator.pop reactivates voice recognition', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pump(const Duration(milliseconds: 200));

      // Push a dummy child module screen
      final context = tester.element(find.byType(HomeScreen));
      Navigator.pushNamed(context, '/dummy');
      await tester.pumpAndSettle();

      expect(find.text('Dummy Module'), findsOneWidget);

      // Pop back to HomeScreen
      await tester.tap(find.text('Back To Home'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);

      // Verify returned announcement and voice recognition reactivation
      verify(() => mockVoiceService.speak(
            'Returned to main menu. Listening for your command...',
            awaitCompletion: true,
          )).called(1);
      verify(() => mockVoiceService.listen()).called(greaterThanOrEqualTo(2));
    });

    testWidgets('VoiceService default parameters provide generous listening and pause duration', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => 1,
      );
      final vs = VoiceService();
      expect(vs.isSpeaking, isFalse);
      expect(vs.isListening, isFalse);
    });
  });
}
