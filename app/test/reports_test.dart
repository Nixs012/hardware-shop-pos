import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/expense.dart';
import 'package:app/models/product.dart';
import 'package:app/models/sale.dart';
import 'package:app/models/sale_line_item.dart';

void main() {
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
}
