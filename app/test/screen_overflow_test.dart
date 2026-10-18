import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/staff.dart';
import 'package:app/screens/billing/billing_screen.dart';
import 'package:app/screens/customer_credit/customer_credit_screen.dart';
import 'package:app/screens/products/products_screen.dart';
import 'package:app/screens/reports/reports_screen.dart';
import 'package:app/screens/settings/settings_screen.dart';

import 'mock_firestore_service.dart';

/// Tests that widget screens render without overflow or build exceptions
/// at a 360dp width (Samsung SM-G930F), the target device for this fix.
void main() {
  // 360 x 640 dp — the Samsung SM-G930F screen size
  const testScreenSize = Size(360, 640);
  final adminStaff = Staff(
    id: '1',
    name: 'Admin',
    role: 'admin',
    email: 'admin@test.com',
  );
  final cashierStaff = Staff(
    id: '2',
    name: 'Cashier',
    role: 'cashier',
    email: 'cashier@test.com',
  );

  /// Wraps a screen in MaterialApp + Scaffold so it has the proper widget
  /// ancestor chain (Material, MediaQuery, etc.) just like in production
  /// where screens are embedded in MainLayout's Scaffold.
  Widget wrapScreen(Widget screen) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: testScreenSize),
        child: Scaffold(
          body: screen,
        ),
      ),
    );
  }

  group('Screen overflow tests at 360x640dp', () {
    testWidgets('BillingScreen renders without overflow (cashier)', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();
      await tester.pumpWidget(
        wrapScreen(
          BillingScreen(
            currentStaff: cashierStaff,
            firestoreService: mockFs,
          ),
        ),
      );

      // Let streams settle
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(BillingScreen), findsOneWidget);
      expect(find.text('Exception'), findsNothing);
      expect(find.text('Bad state'), findsNothing);
    });

    testWidgets('ProductsScreen renders without overflow (admin)', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();
      await tester.pumpWidget(
        wrapScreen(
          ProductsScreen(
            currentStaff: adminStaff,
            firestoreService: mockFs,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ProductsScreen), findsOneWidget);
      expect(find.text('Exception'), findsNothing);
      expect(find.text('Bad state'), findsNothing);
    });

    testWidgets('ReportsScreen renders Sales Summary tab without overflow (admin)', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();
      await tester.pumpWidget(
        wrapScreen(
          ReportsScreen(
            currentStaff: adminStaff,
            firestoreService: mockFs,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ReportsScreen), findsOneWidget);
      expect(find.text('Exception'), findsNothing);
      expect(find.text('Bad state'), findsNothing);
      mockFs.dispose();
    });

    testWidgets('ReportsScreen renders Profit & Loss tab without overflow (admin)', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();
      await tester.pumpWidget(
        wrapScreen(
          ReportsScreen(
            currentStaff: adminStaff,
            firestoreService: mockFs,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Switch to P&L tab (tab index 1 for admin)
      await tester.tap(find.text('Profit & Loss'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ReportsScreen), findsOneWidget);
      expect(find.text('Exception'), findsNothing);
      mockFs.dispose();
    });

    testWidgets('ReportsScreen renders Top Sellers tab without overflow (admin)', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();
      await tester.pumpWidget(
        wrapScreen(
          ReportsScreen(
            currentStaff: adminStaff,
            firestoreService: mockFs,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Switch to Top Sellers tab (tab index 2 for admin)
      await tester.tap(find.text('Top Sellers'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ReportsScreen), findsOneWidget);
      expect(find.text('Exception'), findsNothing);
      mockFs.dispose();
    });

    testWidgets('ReportsScreen renders Stock Balance tab without overflow', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();
      await tester.pumpWidget(
        wrapScreen(
          ReportsScreen(
            currentStaff: adminStaff,
            firestoreService: mockFs,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Switch to Stock Balance tab (last tab)
      await tester.tap(find.text('Stock Balance'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ReportsScreen), findsOneWidget);
      expect(find.text('Exception'), findsNothing);
      mockFs.dispose();
    });

    testWidgets('CustomerCreditScreen renders without overflow', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();
      await tester.pumpWidget(
        wrapScreen(
          CustomerCreditScreen(
            currentStaff: cashierStaff,
            firestoreService: mockFs,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(CustomerCreditScreen), findsOneWidget);
      expect(find.text('Exception'), findsNothing);
      expect(find.text('Bad state'), findsNothing);
    });

    testWidgets('SettingsScreen renders without overflow (admin)', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();
      await tester.pumpWidget(
        wrapScreen(
          SettingsScreen(
            currentStaff: adminStaff,
            firestoreService: mockFs,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Exception'), findsNothing);
      expect(find.text('Bad state'), findsNothing);
    });

    testWidgets('ReportsScreen switches tabs repeatedly without stream errors', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();
      await tester.pumpWidget(
        wrapScreen(
          ReportsScreen(
            currentStaff: adminStaff,
            firestoreService: mockFs,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Cycle through all tabs multiple times
      for (int i = 0; i < 3; i++) {
        await tester.tap(find.text('Profit & Loss'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(ReportsScreen), findsOneWidget);

        await tester.tap(find.text('Top Sellers'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(ReportsScreen), findsOneWidget);

        await tester.tap(find.text('Sales Summary'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(ReportsScreen), findsOneWidget);

        await tester.tap(find.text('Stock Balance'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(ReportsScreen), findsOneWidget);
      }

      // Verify no "Bad state: Stream has already been listened to" errors
      expect(find.text('Bad state'), findsNothing);
      expect(find.text('Stream has already been listened to'), findsNothing);

      mockFs.dispose();
    });

    testWidgets('ReportsScreen renders without overflow for cashier (no P&L/Top Sellers tabs)', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();
      await tester.pumpWidget(
        wrapScreen(
          ReportsScreen(
            currentStaff: cashierStaff,
            firestoreService: mockFs,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ReportsScreen), findsOneWidget);
      expect(find.text('Exception'), findsNothing);
      mockFs.dispose();
    });
  });
}
