import 'package:flutter_test/flutter_test.dart';
import 'package:visionmate/app.dart';

void main() {
  testWidgets('VisionMateApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VisionMateApp());
    expect(find.byType(VisionMateApp), findsOneWidget);
  });
}
