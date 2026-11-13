import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_alarm/main.dart';

void main() {
  testWidgets('App loads correctly smoke test', (WidgetTester tester) async {
    // Build our app using the correct class name.
    await tester.pumpWidget(const QuizAlarmApp());

    // Wait for the UI to settle
    await tester.pumpAndSettle();

    // Verify that the app launches and displays the main title
    expect(find.text('BrainWake Quiz Alarm'), findsOneWidget);
  });
}
