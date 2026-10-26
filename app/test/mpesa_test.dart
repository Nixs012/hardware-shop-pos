import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/product.dart';
import 'package:app/models/sale.dart';
import 'package:app/models/sale_line_item.dart';
import 'package:app/models/shop.dart';
import 'package:app/models/staff.dart';
import 'package:app/screens/billing/billing_screen.dart';
import 'package:app/screens/settings/settings_screen.dart';
import 'package:app/services/sync_service.dart';
import 'package:app/utils/mpesa_utils.dart';

import 'mock_firestore_service.dart';

void main() {
  const testScreenSize = Size(360, 640);

  final adminStaff = Staff(
    id: 'admin_1',
    name: 'Admin User',
    role: 'admin',
    email: 'admin@test.com',
  );

  final cashierStaff = Staff(
    id: 'cashier_1',
    name: 'Cashier User',
    role: 'cashier',
    email: 'cashier@test.com',
  );

  final testProduct = Product(
    id: 'prod_1',
    name: 'Test Hammer',
    sku: 'TH01',
    category: 'Tools',
    costPrice: 300,
    sellingPrice: 500,
    quantityOnHand: 20,
    unit: 'pcs',
  );

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

  group('M-Pesa Code Validation Unit Tests', () {
    test('Valid 10-char alphanumeric codes are accepted', () {
      expect(MpesaUtils.isValidCode('QAB12CD34E'), isTrue);
      expect(MpesaUtils.isValidCode('1234567890'), isTrue);
      expect(MpesaUtils.isValidCode('ABCDEFGHIJ'), isTrue);
      expect(MpesaUtils.isValidCode('  QAB12CD34E  '), isTrue);
      expect(MpesaUtils.isValidCode('qab12cd34e'), isTrue);
    });

    test('Codes with invalid lengths or characters are rejected', () {
      expect(MpesaUtils.isValidCode(''), isFalse);
      expect(MpesaUtils.isValidCode('QAB12'), isFalse); // too short
      expect(MpesaUtils.isValidCode('QAB12CD34E1'), isFalse); // too long
      expect(MpesaUtils.isValidCode('QAB12-D34E'), isFalse); // contains hyphen
      expect(MpesaUtils.isValidCode('QAB12.D34E'), isFalse); // contains period
      expect(MpesaUtils.isValidCode('QAB12 CD34'), isFalse); // space inside
    });

    test('Sanitizing code auto-uppercases and trims', () {
      expect(MpesaUtils.sanitizeCode('  qab12cd34e  '), equals('QAB12CD34E'));
      expect(MpesaUtils.sanitizeCode('abc123xyz0'), equals('ABC123XYZ0'));
    });

    test('getValidationError returns accurate inline error messages', () {
      expect(MpesaUtils.getValidationError(''), equals('M-Pesa transaction code is required'));
      expect(MpesaUtils.getValidationError('ABC'), contains('must be exactly 10 characters'));
      expect(MpesaUtils.getValidationError('ABC12345678'), contains('must be exactly 10 characters'));
      expect(MpesaUtils.getValidationError('ABC123456!'), contains('letters and digits only'));
      expect(MpesaUtils.getValidationError('QAB12CD34E'), isNull);
    });
  });

  group('M-Pesa Duplicate Detection Unit Tests', () {
    test('MemorySyncStorage finds cached and pending sales by M-Pesa code', () async {
      final storage = MemorySyncStorage();
      final sale = Sale(
        id: 'sale_101',
        timestamp: DateTime.now(),
        staffId: 'cashier_1',
        paymentMethod: 'M-Pesa',
        mpesaCode: 'QAB12CD34E',
        lineItems: [
          SaleLineItem(
            productId: 'p1',
            quantity: 1,
            unitPriceAtSale: 500,
            unitCostAtSale: 300,
          ),
        ],
      );

      await storage.cacheSales([sale]);

      final found = await storage.findSaleByMpesaCode('QAB12CD34E');
      expect(found, isNotNull);
      expect(found!.id, equals('sale_101'));

      // Case-insensitive check
      final foundLower = await storage.findSaleByMpesaCode('qab12cd34e');
      expect(foundLower, isNotNull);
      expect(foundLower!.id, equals('sale_101'));

      // Non-matching code returns null
      final notFound = await storage.findSaleByMpesaCode('DIFF123456');
      expect(notFound, isNull);
    });

    test('Shop model produces correct M-Pesa instruction line', () {
      final tillShop = Shop(
        id: 's1',
        name: 'Hardware',
        address: '',
        phone: '',
        footer: 'Thanks',
        paperSize: '58mm',
        ownerUid: 'owner_1',
        joinCode: 'CODE1',
        createdAt: DateTime.now(),
        mpesaType: 'Till',
        mpesaNumber: '123456',
      );
      expect(tillShop.mpesaInstruction, equals('Pay via M-Pesa: Till 123456'));

      final paybillShop = Shop(
        id: 's2',
        name: 'Hardware',
        address: '',
        phone: '',
        footer: 'Thanks',
        paperSize: '58mm',
        ownerUid: 'owner_1',
        joinCode: 'CODE1',
        createdAt: DateTime.now(),
        mpesaType: 'Paybill',
        mpesaNumber: '522522',
        mpesaAccountNumber: '987654',
      );
      expect(paybillShop.mpesaInstruction, equals('Pay via M-Pesa: Paybill 522522, Acc 987654'));

      final noneShop = Shop(
        id: 's3',
        name: 'Hardware',
        address: '',
        phone: '',
        footer: 'Thanks',
        paperSize: '58mm',
        ownerUid: 'owner_1',
        joinCode: 'CODE1',
        createdAt: DateTime.now(),
      );
      expect(noneShop.mpesaInstruction, isNull);
    });
  });

  group('M-Pesa Widget Tests at 360x640', () {
    testWidgets('M-Pesa field displays, validates inline, and completes sale', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();
      mockFs.setProducts([testProduct]);

      await tester.pumpWidget(
        wrapScreen(
          BillingScreen(
            currentStaff: cashierStaff,
            firestoreService: mockFs,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on product to add to cart
      await tester.tap(find.text('Test Hammer'));
      await tester.pumpAndSettle();

      // Click "Complete Sale" button on collapsed cart
      await tester.tap(find.widgetWithText(ElevatedButton, 'Complete Sale').first);
      await tester.pumpAndSettle();

      // Payment method dialog should appear with Cash, M-Pesa, Credit
      expect(find.text('Select Payment Method'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('M-Pesa'), findsOneWidget);
      expect(find.text('Credit'), findsOneWidget);

      // Select M-Pesa
      await tester.tap(find.text('M-Pesa'));
      await tester.pumpAndSettle();

      // M-Pesa dialog appears with required field
      expect(find.text('M-Pesa Payment'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'M-Pesa transaction code'), findsOneWidget);

      // "Complete Sale" in dialog is disabled initially
      final completeButtonFinder = find.widgetWithText(ElevatedButton, 'Complete Sale');
      expect(completeButtonFinder, findsOneWidget);
      ElevatedButton button = tester.widget<ElevatedButton>(completeButtonFinder);
      expect(button.onPressed, isNull);

      // Enter short code
      await tester.enterText(find.byType(TextField), 'QAB12');
      await tester.pumpAndSettle();
      expect(find.textContaining('must be exactly 10 characters'), findsOneWidget);
      button = tester.widget<ElevatedButton>(completeButtonFinder);
      expect(button.onPressed, isNull);

      // Enter valid 10-char code
      await tester.enterText(find.byType(TextField), 'qab12cd34e');
      await tester.pumpAndSettle();

      // Text is auto-uppercased and valid
      button = tester.widget<ElevatedButton>(completeButtonFinder);
      expect(button.onPressed, isNotNull);

      // Complete the sale
      await tester.tap(completeButtonFinder);
      await tester.pumpAndSettle();

      // Dialog closed and sale recorded with mpesaCode
      expect(find.text('M-Pesa Payment'), findsNothing);
      expect(mockFs.getLatestSale(), completion(isNotNull));
      final recordedSale = await mockFs.getLatestSale();
      expect(recordedSale?.mpesaCode, equals('QAB12CD34E'));
      expect(recordedSale?.paymentMethod, equals('M-Pesa'));
    });

    testWidgets('Duplicate M-Pesa code blocks cashier but allows admin override', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();
      mockFs.setProducts([testProduct]);
      mockFs.mockSaleByMpesaCode = Sale(
        id: 'earlier_sale_12345',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        staffId: 'staff_9',
        paymentMethod: 'M-Pesa',
        mpesaCode: 'DUP1234567',
        lineItems: [
          SaleLineItem(
            productId: 'prod_1',
            quantity: 1,
            unitPriceAtSale: 500,
            unitCostAtSale: 300,
          ),
        ],
      );

      // 1. Test as Cashier: blocked
      await tester.pumpWidget(
        wrapScreen(
          BillingScreen(
            currentStaff: cashierStaff,
            firestoreService: mockFs,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Hammer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Complete Sale').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('M-Pesa'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'DUP1234567');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Complete Sale'));
      await tester.pumpAndSettle();

      // Duplicate warning dialog shows
      expect(find.text('Duplicate M-Pesa Code'), findsOneWidget);
      expect(find.textContaining('Cashiers cannot proceed'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Override & Complete'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Close'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Close'));
      await tester.pumpAndSettle();

      // 2. Test as Admin: can override
      await tester.pumpWidget(
        wrapScreen(
          BillingScreen(
            currentStaff: adminStaff,
            firestoreService: mockFs,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test Hammer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Complete Sale').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('M-Pesa'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'DUP1234567');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Complete Sale'));
      await tester.pumpAndSettle();

      // Admin duplicate warning shows override button
      expect(find.text('Duplicate M-Pesa Code'), findsOneWidget);
      expect(find.textContaining('As an admin, you can override'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Override & Complete'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Override & Complete'));
      await tester.pumpAndSettle();

      // Sale succeeds
      expect(find.text('Duplicate M-Pesa Code'), findsNothing);
      expect(find.text('M-Pesa Payment'), findsNothing);
    });

    testWidgets('SettingsScreen displays Shop Details & M-Pesa for Admin only', (WidgetTester tester) async {
      final mockFs = MockFirestoreService();

      // Admin test
      await tester.pumpWidget(
        wrapScreen(
          SettingsScreen(
            currentStaff: adminStaff,
            firestoreService: mockFs,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shop Details & M-Pesa'), findsOneWidget);
      expect(find.text('Save Shop Details'), findsOneWidget);

      // Cashier test
      await tester.pumpWidget(
        wrapScreen(
          SettingsScreen(
            currentStaff: cashierStaff,
            firestoreService: mockFs,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shop Details & M-Pesa'), findsNothing);
      expect(find.text('Save Shop Details'), findsNothing);
    });
  });
}



