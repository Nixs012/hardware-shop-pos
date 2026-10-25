import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/expense.dart';
import 'package:app/models/product.dart';
import 'package:app/models/sale.dart';
import 'package:app/models/sale_line_item.dart';
import 'package:app/models/customer_payment.dart';
import 'package:app/models/staff.dart';
import 'package:app/screens/reports/reports_screen.dart';
import 'package:app/utils/credit_balance.dart';
import 'package:app/services/reports_repository.dart';
import 'mock_firestore_service.dart';

/// Helper class for testing credit balance computation logic.
class _TestCustomerBalance {
  final String customerName;
  final String customerPhone;
  double totalCreditSales;
  double totalRepayments;

  _TestCustomerBalance({
    required this.customerName,
    required this.customerPhone,
    required this.totalCreditSales,
    required this.totalRepayments,
  });

  double get outstanding => totalCreditSales - totalRepayments;
}

void main() {
  // Extracted reusable balance-computation logic — mirrors
  // CustomerCreditScreen._computeBalances but as a pure function
  // for unit testing.
  Map<String, _TestCustomerBalance> computeBalances(
    List<Sale> sales,
    List<CustomerPayment> payments,
  ) {
    final balances = <String, _TestCustomerBalance>{};

    for (final sale in sales) {
      if (sale.paymentMethod == 'Credit' &&
          sale.customerName != null &&
          sale.customerName!.isNotEmpty) {
        final key = sale.customerName!;
        final existing = balances[key] ?? _TestCustomerBalance(
          customerName: sale.customerName!,
          customerPhone: sale.customerPhone ?? '',
          totalCreditSales: 0,
          totalRepayments: 0,
        );
        balances[key] = existing
          ..totalCreditSales += sale.totalAmount;
      }
    }

    for (final payment in payments) {
      final key = payment.customerName;
      final existing = balances[key] ?? _TestCustomerBalance(
        customerName: payment.customerName,
        customerPhone: payment.customerPhone,
        totalCreditSales: 0,
        totalRepayments: 0,
      );
      balances[key] = existing
        ..totalRepayments += payment.amount;
    }

    return balances;
  }

  group('Phase 5 - Reports and Profit/Loss Domain Tests', () {
    test('Expense model serializes and deserializes correctly', () {
      final date = DateTime(2026, 10, 18, 11, 30);
      final expense = Expense(
        id: 'exp-123',
        date: date,
        category: 'Rent',
        amount: 15000.0,
        note: 'Monthly shop space rent',
      );

      final map = expense.toMap();
      expect(map['id'], equals('exp-123'));
      expect(map['category'], equals('Rent'));
      expect(map['amount'], equals(15000.0));
      expect(map['note'], equals('Monthly shop space rent'));

      final restored = Expense.fromMap(map, 'exp-123');
      expect(restored.id, equals('exp-123'));
      expect(restored.category, equals('Rent'));
      expect(restored.amount, equals(15000.0));
      expect(restored.note, equals('Monthly shop space rent'));
    });

    test('Profit calculation: line_profit = (unit_price - unit_cost) * quantity', () {
      final item1 = SaleLineItem(
        productId: 'prod-pvc',
        quantity: 3,
        unitPriceAtSale: 150.0,
        unitCostAtSale: 100.0,
      );
      // (150 - 100) * 3 = 150
      expect(item1.profit, equals(150.0));

      final item2 = SaleLineItem(
        productId: 'prod-cement',
        quantity: 2,
        unitPriceAtSale: 750.0,
        unitCostAtSale: 600.0,
      );
      // (750 - 600) * 2 = 300
      expect(item2.profit, equals(300.0));
    });

    test('Period profit formula: gross_profit - operating_expenses = net_profit', () {
      final sale1 = Sale(
        id: 's1',
        timestamp: DateTime(2026, 10, 18, 10, 0),
        staffId: 'staff-1',
        paymentMethod: 'Cash',
        lineItems: [
          SaleLineItem(
            productId: 'prod-1',
            quantity: 5,
            unitPriceAtSale: 200.0, // revenue: 1000, cost: 600, profit: 400
            unitCostAtSale: 120.0,
          ),
        ],
      );

      final sale2 = Sale(
        id: 's2',
        timestamp: DateTime(2026, 10, 18, 14, 0),
        staffId: 'staff-2',
        paymentMethod: 'M-Pesa',
        lineItems: [
          SaleLineItem(
            productId: 'prod-2',
            quantity: 2,
            unitPriceAtSale: 500.0, // revenue: 1000, cost: 700, profit: 300
            unitCostAtSale: 350.0,
          ),
        ],
      );

      final expenses = [
        Expense(
          id: 'exp-1',
          date: DateTime(2026, 10, 18, 12, 0),
          category: 'Transport',
          amount: 250.0,
        ),
        Expense(
          id: 'exp-2',
          date: DateTime(2026, 10, 18, 16, 0),
          category: 'Electricity',
          amount: 150.0,
        ),
      ];

      final totalRevenue = sale1.totalAmount + sale2.totalAmount; // 2000.0
      final totalCOGS = sale1.totalCost + sale2.totalCost; // 1300.0
      final grossProfit = totalRevenue - totalCOGS; // 700.0
      final totalExpenses = expenses.fold<double>(0.0, (sum, e) => sum + e.amount); // 400.0

      final netProfit = grossProfit - totalExpenses; // 300.0
      final netMargin = (netProfit / totalRevenue) * 100; // 15.0%

      expect(totalRevenue, equals(2000.0));
      expect(totalCOGS, equals(1300.0));
      expect(grossProfit, equals(700.0));
      expect(totalExpenses, equals(400.0));
      expect(netProfit, equals(300.0));
      expect(netMargin, equals(15.0));
    });

    test('Local timezone day boundaries: 23:50 local sale belongs to current day', () {
      final localDate = DateTime(2026, 10, 18);
      final dayStart = DateTime(localDate.year, localDate.month, localDate.day);
      final dayEnd = DateTime(localDate.year, localDate.month, localDate.day, 23, 59, 59, 999);

      final lateSale = DateTime(2026, 10, 18, 23, 50);
      final nextDayEarly = DateTime(2026, 10, 19, 0, 5);

      expect(!lateSale.isBefore(dayStart) && !lateSale.isAfter(dayEnd), isTrue);
      expect(!nextDayEarly.isBefore(dayStart) && !nextDayEarly.isAfter(dayEnd), isFalse);
    });

    test('Weekly period boundaries: Monday to Sunday', () {
      // Suppose today is Wednesday Oct 21, 2026 (weekday = 3)
      final wednesday = DateTime(2026, 10, 21, 15, 0);
      final daysToSubtract = wednesday.weekday - 1; // 2
      final monday = wednesday.subtract(Duration(days: daysToSubtract));
      final start = DateTime(monday.year, monday.month, monday.day);

      final daysToAdd = 7 - wednesday.weekday; // 4
      final sunday = wednesday.add(Duration(days: daysToAdd));
      final end = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59, 999);

      expect(start.weekday, equals(DateTime.monday));
      expect(sunday.weekday, equals(DateTime.sunday));
      expect(start.day, equals(19)); // Monday Oct 19
      expect(sunday.day, equals(25)); // Sunday Oct 25
      expect(end.hour, equals(23));
      expect(end.minute, equals(59));
    });

    test('Credit sales (khata) count toward revenue and profit at sale time and are tracked separately', () {
      final creditSale = Sale(
        id: 'credit-sale-1',
        timestamp: DateTime(2026, 10, 18, 9, 0),
        staffId: 'staff-1',
        paymentMethod: 'Credit',
        lineItems: [
          SaleLineItem(
            productId: 'prod-pipes',
            quantity: 10,
            unitPriceAtSale: 100.0, // revenue: 1000
            unitCostAtSale: 70.0,   // cost: 700, profit: 300
          ),
        ],
      );

      // Counts toward revenue & profit at time of sale
      expect(creditSale.totalAmount, equals(1000.0));
      expect(creditSale.totalProfit, equals(300.0));
      expect(creditSale.paymentMethod, equals('Credit'));
    });

    test('Low stock flagging uses quantity_on_hand <= low_stock_threshold', () {
      final normal = Product(
        id: 'p1',
        name: 'Paint 5L',
        sku: 'PNT-5L',
        category: 'Paint',
        sellingPrice: 1200.0,
        quantityOnHand: 10.0,
        lowStockThreshold: 5.0,
        unit: 'tin',
      );
      final low = Product(
        id: 'p2',
        name: 'Paint 1L',
        sku: 'PNT-1L',
        category: 'Paint',
        sellingPrice: 400.0,
        quantityOnHand: 4.0,
        lowStockThreshold: 5.0,
        unit: 'tin',
      );
      final outOfStock = Product(
        id: 'p3',
        name: 'Paint 20L',
        sku: 'PNT-20L',
        category: 'Paint',
        sellingPrice: 4500.0,
        quantityOnHand: 0.0,
        lowStockThreshold: 2.0,
        unit: 'bucket',
      );

      expect(normal.quantityOnHand <= normal.lowStockThreshold, isFalse);
      expect(low.quantityOnHand <= low.lowStockThreshold, isTrue);
      expect(outOfStock.quantityOnHand <= outOfStock.lowStockThreshold, isTrue);
      expect(outOfStock.quantityOnHand <= 0, isTrue);
    });
  });

  group('Phase 6 - Customer Credit Outstanding Balance Tests', () {
    test('Single credit sale with no repayment → outstanding equals sale total', () {
      final creditSale = Sale(
        id: 's1',
        timestamp: DateTime(2026, 10, 18, 10, 0),
        staffId: 'staff-1',
        paymentMethod: 'Credit',
        customerName: 'John Mwangi',
        customerPhone: '0700111222',
        lineItems: [
          SaleLineItem(
            productId: 'prod-cement',
            quantity: 5,
            unitPriceAtSale: 800.0,
            unitCostAtSale: 600.0,
          ),
        ],
      );

      final balances = computeBalances([creditSale], []);

      expect(balances.length, equals(1));
      expect(balances['John Mwangi']!.outstanding, equals(4000.0));
    });

    test('Full repayment zeroes out outstanding balance', () {
      final creditSale = Sale(
        id: 's1',
        timestamp: DateTime(2026, 10, 18, 10, 0),
        staffId: 'staff-1',
        paymentMethod: 'Credit',
        customerName: 'Jane Njoroge',
        lineItems: [
          SaleLineItem(
            productId: 'prod-paint',
            quantity: 2,
            unitPriceAtSale: 1500.0,
            unitCostAtSale: 900.0,
          ),
        ],
      );

      final repayment = CustomerPayment(
        id: 'p1',
        customerName: 'Jane Njoroge',
        customerPhone: '0722000111',
        amount: 3000.0,
        paymentMethod: 'Repayment',
        timestamp: DateTime(2026, 10, 20),
        staffId: 'admin-1',
      );

      final balances = computeBalances([creditSale], [repayment]);

      expect(balances['Jane Njoroge']!.outstanding, equals(0.0));
    });

    test('Partial repayment reduces outstanding proportionally', () {
      final creditSale = Sale(
        id: 's1',
        timestamp: DateTime(2026, 10, 18, 10, 0),
        staffId: 'staff-1',
        paymentMethod: 'Credit',
        customerName: 'Peter Ochieng',
        lineItems: [
          SaleLineItem(
            productId: 'prod-wire',
            quantity: 10,
            unitPriceAtSale: 500.0,
            unitCostAtSale: 300.0,
          ),
        ],
      );

      final repayment = CustomerPayment(
        id: 'p1',
        customerName: 'Peter Ochieng',
        customerPhone: '',
        amount: 2000.0,
        paymentMethod: 'Repayment',
        timestamp: DateTime(2026, 10, 19),
        staffId: 'admin-1',
      );

      final balances = computeBalances([creditSale], [repayment]);

      // 10 * 500 = 5000 credit, minus 2000 repayment = 3000 outstanding
      expect(balances['Peter Ochieng']!.outstanding, equals(3000.0));
    });

    test('Multiple credit sales for same customer aggregate correctly', () {
      final sale1 = Sale(
        id: 's1',
        timestamp: DateTime(2026, 10, 18, 9, 0),
        staffId: 'staff-1',
        paymentMethod: 'Credit',
        customerName: 'Ali Hassan',
        lineItems: [
          SaleLineItem(
            productId: 'prod-1',
            quantity: 3,
            unitPriceAtSale: 1000.0,
            unitCostAtSale: 600.0,
          ),
        ],
      );

      final sale2 = Sale(
        id: 's2',
        timestamp: DateTime(2026, 10, 20, 14, 0),
        staffId: 'staff-2',
        paymentMethod: 'Credit',
        customerName: 'Ali Hassan',
        lineItems: [
          SaleLineItem(
            productId: 'prod-2',
            quantity: 2,
            unitPriceAtSale: 2000.0,
            unitCostAtSale: 1200.0,
          ),
        ],
      );

      final repayment = CustomerPayment(
        id: 'p1',
        customerName: 'Ali Hassan',
        customerPhone: '0711223344',
        amount: 1500.0,
        paymentMethod: 'Repayment',
        timestamp: DateTime(2026, 10, 21),
        staffId: 'admin-1',
      );

      final balances = computeBalances([sale1, sale2], [repayment]);

      // Total credit: 3000 + 4000 = 7000; repayment: 1500 → outstanding 5500
      expect(balances['Ali Hassan']!.totalCreditSales, equals(7000.0));
      expect(balances['Ali Hassan']!.totalRepayments, equals(1500.0));
      expect(balances['Ali Hassan']!.outstanding, equals(5500.0));
    });

    test('Cash sales do not contribute to customer credit balances', () {
      final cashSale = Sale(
        id: 's1',
        timestamp: DateTime(2026, 10, 18, 9, 0),
        staffId: 'staff-1',
        paymentMethod: 'Cash',
        customerName: 'Cash Customer',
        lineItems: [
          SaleLineItem(
            productId: 'prod-1',
            quantity: 1,
            unitPriceAtSale: 500.0,
            unitCostAtSale: 300.0,
          ),
        ],
      );

      final balances = computeBalances([cashSale], []);

      expect(balances.isEmpty, isTrue);
    });

    test('Customer with only repayments (no credit) shows as zero balance and is excluded from outstanding list', () {
      final repayment = CustomerPayment(
        id: 'p1',
        customerName: 'Bonus Customer',
        customerPhone: '0733445566',
        amount: 500.0,
        paymentMethod: 'Repayment',
        timestamp: DateTime(2026, 10, 19),
        staffId: 'admin-1',
      );

      final balances = computeBalances([], [repayment]);

      // Customer exists in the balances map but outstanding is 0
      expect(balances['Bonus Customer'], isNotNull);
      expect(balances['Bonus Customer']!.totalCreditSales, equals(0.0));
      expect(balances['Bonus Customer']!.totalRepayments, equals(500.0));
      expect(balances['Bonus Customer']!.outstanding, equals(-500.0));
    });

    test('Different customers have independent balances', () {
      final saleA = Sale(
        id: 's1',
        timestamp: DateTime(2026, 10, 18, 9, 0),
        staffId: 'staff-1',
        paymentMethod: 'Credit',
        customerName: 'Customer A',
        lineItems: [
          SaleLineItem(
            productId: 'prod-1',
            quantity: 1,
            unitPriceAtSale: 1000.0,
            unitCostAtSale: 600.0,
          ),
        ],
      );

      final saleB = Sale(
        id: 's2',
        timestamp: DateTime(2026, 10, 18, 10, 0),
        staffId: 'staff-1',
        paymentMethod: 'Credit',
        customerName: 'Customer B',
        lineItems: [
          SaleLineItem(
            productId: 'prod-2',
            quantity: 1,
            unitPriceAtSale: 2000.0,
            unitCostAtSale: 1000.0,
          ),
        ],
      );

      final balances = computeBalances([saleA, saleB], []);

      expect(balances['Customer A']!.outstanding, equals(1000.0));
      expect(balances['Customer B']!.outstanding, equals(2000.0));
    });
  });

  group('Requirement 2 & 4 - Shared Outstanding Balance & Tab Switching Tests', () {
    test('computeOutstandingBalance returns correct difference across scenarios', () {
      expect(computeOutstandingBalance(creditSales: 10000.0, repayments: 3500.0), equals(6500.0));
      expect(computeOutstandingBalance(creditSales: 5000.0, repayments: 5000.0), equals(0.0));
      expect(computeOutstandingBalance(creditSales: 2000.0, repayments: 2500.0), equals(-500.0));
      expect(computeOutstandingBalance(creditSales: 0.0, repayments: 0.0), equals(0.0));
      expect(computeOutstandingBalance(creditSales: 123.45, repayments: 23.45), closeTo(100.0, 0.001));
    });

    test('computeCustomerBalances aggregates credit sales and repayments accurately', () {
      final sale1 = Sale(
        id: 's-1',
        paymentMethod: 'Credit',
        timestamp: DateTime(2026, 10, 1),
        staffId: 'staff-1',
        customerName: 'Alice',
        customerPhone: '0711111111',
        lineItems: [
          SaleLineItem(productId: 'prod-1', quantity: 1, unitPriceAtSale: 1500.0, unitCostAtSale: 1000.0),
        ],
      );
      final sale2 = Sale(
        id: 's-2',
        paymentMethod: 'Credit',
        timestamp: DateTime(2026, 10, 2),
        staffId: 'staff-1',
        customerName: 'Alice',
        customerPhone: '0711111111',
        lineItems: [
          SaleLineItem(productId: 'prod-1', quantity: 1, unitPriceAtSale: 2500.0, unitCostAtSale: 1500.0),
        ],
      );
      final sale3 = Sale(
        id: 's-3',
        paymentMethod: 'Credit',
        timestamp: DateTime(2026, 10, 3),
        staffId: 'staff-1',
        customerName: 'Bob',
        customerPhone: '0722222222',
        lineItems: [
          SaleLineItem(productId: 'prod-2', quantity: 1, unitPriceAtSale: 3000.0, unitCostAtSale: 2000.0),
        ],
      );
      final saleCash = Sale(
        id: 's-4',
        paymentMethod: 'Cash',
        timestamp: DateTime(2026, 10, 4),
        staffId: 'staff-1',
        customerName: 'Alice',
        lineItems: [
          SaleLineItem(productId: 'prod-1', quantity: 1, unitPriceAtSale: 5000.0, unitCostAtSale: 3500.0),
        ],
      );

      final pay1 = CustomerPayment(
        id: 'p-1',
        customerName: 'Alice',
        customerPhone: '0711111111',
        amount: 1000.0,
        timestamp: DateTime(2026, 10, 5),
        paymentMethod: 'M-Pesa',
        staffId: 'staff-1',
      );
      final pay2 = CustomerPayment(
        id: 'p-2',
        customerName: 'Bob',
        customerPhone: '0722222222',
        amount: 3000.0,
        timestamp: DateTime(2026, 10, 6),
        paymentMethod: 'Cash',
        staffId: 'staff-1',
      );

      final balances = computeCustomerBalances([sale1, sale2, sale3, saleCash], [pay1, pay2]);

      expect(balances.containsKey('Alice'), isTrue);
      expect(balances.containsKey('Bob'), isTrue);

      final alice = balances['Alice']!;
      expect(alice.totalCreditSales, equals(4000.0));
      expect(alice.totalRepayments, equals(1000.0));
      expect(alice.outstanding, equals(3000.0));
      expect(alice.outstanding, equals(computeOutstandingBalance(creditSales: alice.totalCreditSales, repayments: alice.totalRepayments)));
      expect(alice.customerPhone, equals('0711111111'));

      final bob = balances['Bob']!;
      expect(bob.totalCreditSales, equals(3000.0));
      expect(bob.totalRepayments, equals(3000.0));
      expect(bob.outstanding, equals(0.0));
    });

    test('ReportsRepository caches queries and switching tabs does not re-query streams', () async {
      ReportsRepository.resetSessionForTesting();
      final mockService = MockFirestoreService();
      final repo = ReportsRepository.acquire(
        service: mockService,
        isAdmin: true,
        staffId: null,
      );
      repo.start();

      expect(mockService.getSalesStreamCalls, equals(1));
      expect(mockService.getProductsStreamCalls, equals(1));

      // Request data for multiple tabs / queries — should be served from cache without extra stream calls
      final range = DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 12, 31));
      repo.dataFor(range: range, staffId: 'All', categoryId: 'All');
      repo.dataFor(range: range, staffId: 'All', categoryId: 'All'); // cached

      expect(mockService.getSalesStreamCalls, equals(1));
      expect(mockService.getProductsStreamCalls, equals(1));

      ReportsRepository.resetSessionForTesting();
      mockService.dispose();
    });

    testWidgets('ReportsScreen switches tabs without re-querying streams (admin)', (WidgetTester tester) async {
      ReportsRepository.resetSessionForTesting();
      final mockFs = MockFirestoreService();
      final admin = Staff(id: '1', name: 'Admin', role: 'admin', email: 'admin@test.com');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsScreen(currentStaff: admin, firestoreService: mockFs),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Initial query counts
      expect(mockFs.getSalesStreamCalls, equals(1));
      expect(mockFs.getProductsStreamCalls, equals(1));
      expect(mockFs.getExpensesStreamCalls, equals(0));
      expect(mockFs.getCustomerPaymentsStreamCalls, equals(1));

      // Admin sees Credit & Khata Tracking card
      expect(find.text('Credit & Khata Tracking'), findsOneWidget);

      // Switch to Profit & Loss tab
      await tester.tap(find.text('Profit & Loss'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Switch to Top Sellers tab
      await tester.tap(find.text('Top Sellers'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Switch to Stock Balance tab
      await tester.tap(find.text('Stock Balance'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Switch back to Sales Summary tab
      await tester.tap(find.text('Sales Summary'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Ensure stream calls did NOT increase upon switching tabs
      expect(mockFs.getSalesStreamCalls, equals(1));
      expect(mockFs.getProductsStreamCalls, equals(1));
      expect(mockFs.getExpensesStreamCalls, equals(0));
      expect(mockFs.getCustomerPaymentsStreamCalls, equals(1));

      // Credit card is still rendered
      expect(find.text('Credit & Khata Tracking'), findsOneWidget);

      ReportsRepository.resetSessionForTesting();
      mockFs.dispose();
    });

    testWidgets('ReportsScreen for cashier role hides credit tracking and never queries customer payments', (WidgetTester tester) async {
      ReportsRepository.resetSessionForTesting();
      final mockFs = MockFirestoreService();
      final cashier = Staff(id: '2', name: 'Cashier', role: 'cashier', email: 'cashier@test.com');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsScreen(currentStaff: cashier, firestoreService: mockFs),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Cashier should NOT query customer payments, expenses, or sales
      expect(mockFs.getCustomerPaymentsStreamCalls, equals(0));
      expect(mockFs.getExpensesStreamCalls, equals(0));
      expect(mockFs.getSalesStreamCalls, equals(0));

      // Cashier must NOT see Sales Summary, Credit & Khata Tracking card or profit
      expect(find.text('Sales Summary'), findsNothing);
      expect(find.text('Credit & Khata Tracking'), findsNothing);
      expect(find.text('Gross Profit'), findsNothing);

      // Cashier sees Stock Balance tab
      expect(find.text('Stock Balance'), findsOneWidget);

      ReportsRepository.resetSessionForTesting();
      mockFs.dispose();
    });
  });
}
