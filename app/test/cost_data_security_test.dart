import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/product.dart';
import 'package:app/models/sale.dart';
import 'package:app/models/sale_line_item.dart';
import 'package:app/models/customer_payment.dart';

void main() {
  group('Cost Data Security & Separation Tests', () {
    test('Product.toMap() excludes cost data for cashier-accessible collection', () {
      final product = Product(
        id: 'prod-123',
        name: 'Cement 50kg',
        sku: 'CEM-01',
        category: 'Building',
        costPrice: 650.0,
        sellingPrice: 750.0,
        quantityOnHand: 40.0,
        lowStockThreshold: 10.0,
        unit: 'bag',
        costPriceEstimated: false,
      );

      final publicMap = product.toMap();
      expect(publicMap.containsKey('cost_price'), isFalse);
      expect(publicMap.containsKey('cost_price_estimated'), isFalse);
      expect(publicMap['selling_price'], 750.0);
      expect(publicMap['name'], 'Cement 50kg');

      final costMap = product.toCostMap();
      expect(costMap['cost_price'], 650.0);
      expect(costMap['cost_price_estimated'], isFalse);
    });

    test('Product.fromMap() behaves safely when cost document is omitted (Cashier view)', () {
      final publicDocData = {
        'id': 'prod-123',
        'name': 'PVC Pipe 2"',
        'sku': 'PVC-02',
        'category': 'Plumbing',
        'selling_price': 450.0,
        'quantity_on_hand': 25.0,
        'low_stock_threshold': 5.0,
        'unit': 'piece',
      };

      final cashierProduct = Product.fromMap(publicDocData, 'prod-123');
      expect(cashierProduct.costPrice, 0.0);
      expect(cashierProduct.costPriceEstimated, isFalse);
      expect(cashierProduct.sellingPrice, 450.0);

      final adminCostData = {
        'cost_price': 320.0,
        'cost_price_estimated': true,
      };

      final adminProduct = Product.fromMap(publicDocData, 'prod-123', adminCostData);
      expect(adminProduct.costPrice, 320.0);
      expect(adminProduct.costPriceEstimated, isTrue);
      expect(adminProduct.sellingPrice, 450.0);
    });

    test('SaleLineItem.toMap() excludes unit_cost_at_sale for cashier sales stream', () {
      final lineItem = SaleLineItem(
        productId: 'prod-123',
        quantity: 2.0,
        unitPriceAtSale: 450.0,
        unitCostAtSale: 320.0,
      );

      final publicMap = lineItem.toMap();
      expect(publicMap.containsKey('unit_cost_at_sale'), isFalse);
      expect(publicMap['unit_price_at_sale'], 450.0);
      expect(publicMap['quantity'], 2.0);

      final costMap = lineItem.toCostMap();
      expect(costMap['unit_cost_at_sale'], 320.0);
      expect(costMap['unit_price_at_sale'], 450.0);
    });

    test('Sale.toMap() produces public sale record while toCostMap() captures cost snapshot', () {
      final sale = Sale(
        id: 'sale-uuid-001',
        timestamp: DateTime(2026, 10, 18, 14, 30),
        staffId: 'staff-cashier-1',
        paymentMethod: 'Cash',
        lineItems: [
          SaleLineItem(
            productId: 'prod-1',
            quantity: 3.0,
            unitPriceAtSale: 100.0,
            unitCostAtSale: 70.0,
          ),
        ],
      );

      final publicSaleMap = sale.toMap();
      expect(publicSaleMap['id'], 'sale-uuid-001');
      final publicItems = publicSaleMap['line_items'] as List;
      expect((publicItems.first as Map).containsKey('unit_cost_at_sale'), isFalse);

      final costSaleMap = sale.toCostMap();
      expect(costSaleMap['total_cost'], 210.0);
      expect(costSaleMap['total_amount'], 300.0);
      final costItems = costSaleMap['line_items'] as List;
      expect((costItems.first as Map)['unit_cost_at_sale'], 70.0);
    });

    test('CustomerPayment serializes and deserializes independently of sales collection', () {
      final payment = CustomerPayment(
        id: 'pay-uuid-789',
        customerName: 'John Contractor',
        customerPhone: '+254712345678',
        amount: 5000.0,
        paymentMethod: 'M-Pesa',
        timestamp: DateTime(2026, 10, 18, 16, 0),
        staffId: 'staff-cashier-1',
        saleId: 'sale-uuid-001',
        note: 'Partial repayment for site materials',
      );

      final map = payment.toMap();
      expect(map['customer_name'], 'John Contractor');
      expect(map['amount'], 5000.0);
      expect(map['payment_method'], 'M-Pesa');
      expect(map['sale_id'], 'sale-uuid-001');

      final reconstructed = CustomerPayment.fromMap(map, 'pay-uuid-789');
      expect(reconstructed.id, 'pay-uuid-789');
      expect(reconstructed.customerName, 'John Contractor');
      expect(reconstructed.amount, 5000.0);
      expect(reconstructed.note, 'Partial repayment for site materials');
    });
  });
}
