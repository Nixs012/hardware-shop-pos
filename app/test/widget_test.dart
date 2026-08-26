import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/screens/billing/billing_screen.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const PosApp());

    // Verify that the BillingScreen is present
    expect(find.byType(BillingScreen), findsOneWidget);
  });
}
