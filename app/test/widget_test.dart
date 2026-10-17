import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/screens/auth/auth_screen.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app with AuthScreen and trigger a frame.
    await tester.pumpWidget(const PosApp(home: AuthScreen()));

    // Verify that the AuthScreen is present
    expect(find.byType(AuthScreen), findsOneWidget);
  });
}
