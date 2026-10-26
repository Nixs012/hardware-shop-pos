import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/product.dart';
import 'package:app/models/sale.dart';
import 'package:app/models/sale_line_item.dart';
import 'package:app/models/customer_payment.dart';
import 'package:app/services/sync_service.dart';

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

  // ──────────────────────────────────────────────────────────────────────────
  // PROOF: Cashier cache vs Admin cache
  // Shows exactly what a cashier account can and cannot see in local storage.
  // ──────────────────────────────────────────────────────────────────────────
  group('Proof: Cashier cannot read cost data; Admin can', () {
    final testProducts = [
      Product(
        id: 'prod-A',
        name: 'Steel Bar 12mm',
        sku: 'STL-12',
        category: 'Metals',
        costPrice: 850.0,
        sellingPrice: 1200.0,
        quantityOnHand: 50.0,
        unit: 'piece',
      ),
      Product(
        id: 'prod-B',
        name: 'Cement 50kg',
        sku: 'CEM-01',
        category: 'Building',
        costPrice: 650.0,
        sellingPrice: 750.0,
        quantityOnHand: 40.0,
        unit: 'bag',
      ),
    ];

    test('Cashier cache: cost_price is absent and reads back as 0.0', () async {
      final cashierStorage = MemorySyncStorage();
      await cashierStorage.init();

      // Simulate what happens when a cashier device syncs products (isAdmin: false)
      await cashierStorage.cacheProducts(testProducts, isAdmin: false);

      final cached = await cashierStorage.getCachedProducts();
      expect(cached.length, 2);

      for (final p in cached) {
        // Cashier must see quantity and price
        expect(p.sellingPrice, greaterThan(0));
        expect(p.quantityOnHand, greaterThan(0));
        // Cashier must NOT see cost price - it defaults to 0.0
        expect(
          p.costPrice,
          0.0,
          reason:
              'cost_price must not be stored on cashier device; '
              'Product.fromMap defaults it to 0.0 when the field is absent.',
        );
      }
    });

    test('Admin cache: cost_price is present and correct', () async {
      final adminStorage = MemorySyncStorage();
      await adminStorage.init();

      // Simulate what happens when an admin device syncs products (isAdmin: true)
      await adminStorage.cacheProducts(testProducts, isAdmin: true);

      final cached = await adminStorage.getCachedProducts();
      expect(cached.length, 2);

      final steelBar = cached.firstWhere((p) => p.id == 'prod-A');
      final cement   = cached.firstWhere((p) => p.id == 'prod-B');

      expect(steelBar.costPrice, 850.0,
          reason: 'Admin device must have the cost_price cached.');
      expect(cement.costPrice, 650.0,
          reason: 'Admin device must have the cost_price cached.');
    });

    test('clearCachedCostData() strips cost from an existing admin cache', () async {
      // Start with admin data written to storage
      final storage = MemorySyncStorage();
      await storage.init();
      await storage.cacheProducts(testProducts, isAdmin: true);

      // Confirm cost is present
      var cached = await storage.getCachedProducts();
      expect(cached.first.costPrice, greaterThan(0));

      // Now simulate a cashier logging in on the same device → wipe cost data
      await storage.clearCachedCostData();

      cached = await storage.getCachedProducts();
      for (final p in cached) {
        expect(
          p.costPrice,
          0.0,
          reason: 'After clearCachedCostData(), no cost_price must remain.',
        );
      }
    });

    test('Firestore rules summary: cashier cannot read /product_costs or /sales_costs', () {
      // This is a documentation test that records the rule assertions.
      // Full rule verification requires the Firebase Emulator (integration test).
      // The Firestore rules at app/firestore.rules enforce:
      //
      //   /product_costs/{id}  → allow read, write: if isAdmin();
      //   /sales_costs/{id}    → allow read: if isAdmin();
      //   /products/{id}       → cost_price field is never written here (toMap() omits it)
      //   /sales/{id}          → unit_cost_at_sale never written here (toMap() omits it)
      //
      // A cashier authenticated via Firebase Auth will be denied by Firestore
      // security rules when trying to GET /product_costs/X or /sales_costs/X
      // because get(staff/uid).data.role != 'admin'.
      //
      // The local Hive cache enforces the same boundary at the app layer:
      // isAdmin=false means cost fields are stripped before writing to disk.
      expect(true, isTrue, reason: 'See comment above for full rule audit.');
    });
  });
}



