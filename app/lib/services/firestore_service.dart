import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';
import 'dart:convert';

import '../models/customer_payment.dart';
import '../models/failed_sale.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/staff.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _failedSalesKey = 'failed_sales_needs_review';

  Future<void> addProduct(Product product) {
    final batch = _db.batch();
    batch.set(_db.collection('products').doc(product.id), product.toMap());
    batch.set(
      _db.collection('product_costs').doc(product.id),
      product.toCostMap(),
    );
    return batch.commit();
  }

  Future<void> updateProduct(Product product) {
    final batch = _db.batch();
    batch.update(_db.collection('products').doc(product.id), product.toMap());
    batch.set(
      _db.collection('product_costs').doc(product.id),
      product.toCostMap(),
      SetOptions(merge: true),
    );
    return batch.commit();
  }

  Future<void> deleteProduct(String productId) {
    final batch = _db.batch();
    batch.delete(_db.collection('products').doc(productId));
    batch.delete(_db.collection('product_costs').doc(productId));
    return batch.commit();
  }

  /// Streams products. If [isAdmin] is false, cost data is never requested or read.
  Stream<List<Product>> getProductsStream({bool isAdmin = false}) {
    if (!isAdmin) {
      return _db.collection('products').snapshots().map((snapshot) {
        return snapshot.docs
            .map((doc) => Product.fromMap(doc.data(), doc.id))
            .toList();
      });
    }

    // For Admin: merge /products with admin-only /product_costs
    final controller = StreamController<List<Product>>();
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? productDocs;
    Map<String, Map<String, dynamic>> costs = {};

    void emitMerged() {
      if (productDocs == null) return;
      final products = productDocs!.map((doc) {
        final costData = costs[doc.id];
        return Product.fromMap(doc.data(), doc.id, costData);
      }).toList();
      if (!controller.isClosed) {
        controller.add(products);
      }
    }

    final sub1 = _db.collection('products').snapshots().listen((snap) {
      productDocs = snap.docs;
      emitMerged();
    }, onError: controller.addError);

    final sub2 = _db.collection('product_costs').snapshots().listen((snap) {
      costs = {for (final doc in snap.docs) doc.id: doc.data()};
      emitMerged();
    }, onError: (Object _) {
      // If error or permissions, still emit products
      emitMerged();
    });

    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
    };

    return controller.stream;
  }

  Future<void> processSale(Sale sale, {bool includeCostSnapshot = true}) async {
    final batch = _db.batch();

    // 1. Add public sale document (strictly without unit_cost_at_sale)
    final saleRef = _db.collection('sales').doc(sale.id);
    batch.set(saleRef, sale.toMap());

    // 2. Add admin-only sales_costs document with unit_cost_at_sale snapshot
    if (includeCostSnapshot) {
      final costRef = _db.collection('sales_costs').doc(sale.id);
      batch.set(costRef, sale.toCostMap());
    }

    // 3. Atomically decrement stock for each line item
    for (final item in sale.lineItems) {
      final productRef = _db.collection('products').doc(item.productId);
      batch.update(productRef, {
        'quantity_on_hand': FieldValue.increment(-item.quantity),
      });
    }

    unawaited(
      batch.commit().catchError((Object error) {
        unawaited(_saveFailedSale(sale, error.toString()));
      }),
    );
  }

  Future<List<FailedSaleRecord>> getFailedSales() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_failedSalesKey);
    if (encoded == null || encoded.isEmpty) return [];

    try {
      final stored = jsonDecode(encoded) as Map<String, dynamic>;
      final records = <FailedSaleRecord>[];
      for (final value in stored.values) {
        try {
          records.add(
            FailedSaleRecord.fromMap(Map<String, dynamic>.from(value as Map)),
          );
        } catch (_) {}
      }
      records.sort((a, b) => b.failedAt.compareTo(a.failedAt));
      return records;
    } catch (_) {
      return [];
    }
  }

  Future<void> retryFailedSale(FailedSaleRecord record) async {
    final batch = _db.batch();
    batch.set(_db.collection('sales').doc(record.sale.id), record.sale.toMap());
    batch.set(
      _db.collection('sales_costs').doc(record.sale.id),
      record.sale.toCostMap(),
    );
    for (final item in record.sale.lineItems) {
      batch.update(_db.collection('products').doc(item.productId), {
        'quantity_on_hand': FieldValue.increment(-item.quantity),
      });
    }

    try {
      await batch.commit().timeout(const Duration(seconds: 10));
      await _removeFailedSale(record.sale.id);
    } catch (error) {
      await _saveFailedSale(record.sale, error.toString());
      rethrow;
    }
  }

  Future<void> _saveFailedSale(Sale sale, String errorMessage) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = _readFailedSaleMap(preferences);
      stored[sale.id] = FailedSaleRecord(
        sale: sale,
        errorMessage: errorMessage,
        failedAt: DateTime.now(),
      ).toMap();
      await preferences.setString(_failedSalesKey, jsonEncode(stored));
    } catch (_) {}
  }

  Future<void> _removeFailedSale(String saleId) async {
    final preferences = await SharedPreferences.getInstance();
    final stored = _readFailedSaleMap(preferences);
    stored.remove(saleId);
    await preferences.setString(_failedSalesKey, jsonEncode(stored));
  }

  Map<String, dynamic> _readFailedSaleMap(SharedPreferences preferences) {
    final encoded = preferences.getString(_failedSalesKey);
    if (encoded == null || encoded.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    } catch (_) {
      return {};
    }
  }

  /// Streams sales. Cashiers only read sales documents (without cost fields).
  /// For Admins, /sales is merged with /sales_costs so profit reports receive unitCostAtSale.
  Stream<List<Sale>> getSalesStream({bool isAdmin = false, String? staffId}) {
    if (!isAdmin) {
      var query = _db.collection('sales').orderBy('timestamp', descending: true);
      if (staffId != null) {
        return _db
            .collection('sales')
            .where('staff_id', isEqualTo: staffId)
            .snapshots()
            .map((snapshot) {
              final sales = snapshot.docs
                  .map((doc) => Sale.fromMap(doc.data(), doc.id))
                  .toList();
              sales.sort((a, b) => b.timestamp.compareTo(a.timestamp));
              return sales;
            });
      }
      return query.snapshots().map((snapshot) {
        return snapshot.docs
            .map((doc) => Sale.fromMap(doc.data(), doc.id))
            .toList();
      });
    }

    // For Admin: merge /sales with admin-only /sales_costs
    final controller = StreamController<List<Sale>>();
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? saleDocs;
    Map<String, Map<String, dynamic>> costs = {};

    void emitMerged() {
      if (saleDocs == null) return;
      final sales = saleDocs!.map((doc) {
        final costData = costs[doc.id];
        return Sale.fromMap(doc.data(), doc.id, costData);
      }).toList();
      sales.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (!controller.isClosed) {
        controller.add(sales);
      }
    }

    final sub1 = _db
        .collection('sales')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snap) {
          saleDocs = snap.docs;
          emitMerged();
        }, onError: controller.addError);

    final sub2 = _db.collection('sales_costs').snapshots().listen((snap) {
      costs = {for (final doc in snap.docs) doc.id: doc.data()};
      emitMerged();
    }, onError: (Object _) {
      emitMerged();
    });

    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
    };

    return controller.stream;
  }

  Future<Sale?> getLatestSale({String? staffId}) async {
    Query<Map<String, dynamic>> query = _db
        .collection('sales')
        .orderBy('timestamp', descending: true);
    if (staffId != null) {
      query = query.where('staff_id', isEqualTo: staffId);
    }

    final snapshot = await query
        .limit(1)
        .get(const GetOptions(source: Source.cache));
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return Sale.fromMap(doc.data(), doc.id);
  }

  // --- Customer Payments (Credit Repayments) ---
  // Sales are strictly immutable. Credit repayments are recorded in customer_payments.

  Future<void> recordCustomerPayment(CustomerPayment payment) {
    return _db
        .collection('customer_payments')
        .doc(payment.id)
        .set(payment.toMap());
  }

  Stream<List<CustomerPayment>> getCustomerPaymentsStream() {
    return _db
        .collection('customer_payments')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => CustomerPayment.fromMap(doc.data(), doc.id))
              .toList();
        });
  }

  Stream<List<Staff>> getStaffStream() {
    return _db.collection('staff').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Staff.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> updateStaff(Staff staff) {
    return _db.collection('staff').doc(staff.id).update(staff.toMap());
  }
}
