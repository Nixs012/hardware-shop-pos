import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/customer_payment.dart';
import '../models/expense.dart';
import '../models/failed_sale.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/staff.dart';
import 'sync_service.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
  /// Seamlessly loads from local cache for offline/airplane mode support.
  Stream<List<Product>> getProductsStream({bool isAdmin = false}) {
    final controller = StreamController<List<Product>>();

    // Immediately emit cached products so offline users don't see empty screens
    SyncService.instance.getCachedProducts().then((cached) {
      if (cached.isNotEmpty && !controller.isClosed) {
        controller.add(cached);
      }
    });

    if (!isAdmin) {
      final sub = _db.collection('products').snapshots().listen((snapshot) {
        final products = snapshot.docs
            .map((doc) => Product.fromMap(doc.data(), doc.id))
            .toList();
        SyncService.instance.cacheProducts(products, isAdmin: false);
        if (!controller.isClosed) {
          controller.add(products);
        }
      }, onError: (Object err) {
        if (!controller.isClosed) {
          controller.addError(err);
        }
      });

      controller.onCancel = () => sub.cancel();
      return controller.stream;
    }

    // For Admin: merge /products with admin-only /product_costs
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? productDocs;
    Map<String, Map<String, dynamic>> costs = {};

    void emitMerged() {
      if (productDocs == null) return;
      final products = productDocs!.map((doc) {
        final costData = costs[doc.id];
        return Product.fromMap(doc.data(), doc.id, costData);
      }).toList();
      SyncService.instance.cacheProducts(products, isAdmin: true);
      if (!controller.isClosed) {
        controller.add(products);
      }
    }

    final sub1 = _db.collection('products').snapshots().listen((snap) {
      productDocs = snap.docs;
      emitMerged();
    }, onError: (Object err) {
      if (!controller.isClosed) controller.addError(err);
    });

    final sub2 = _db.collection('product_costs').snapshots().listen((snap) {
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

  Future<void> processSale(Sale sale, {bool includeCostSnapshot = true}) async {
    await SyncService.instance.queueSale(
      sale,
      includeCostSnapshot: includeCostSnapshot,
    );
  }

  Future<List<FailedSaleRecord>> getFailedSales() {
    return SyncService.instance.getFailedSales();
  }

  Future<void> retryFailedSale(FailedSaleRecord record) {
    return SyncService.instance.retryFailedSale(record);
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

  // --- Expenses (Ledger for P&L) ---

  Future<void> addExpense(Expense expense) {
    return _db.collection('expenses').doc(expense.id).set(expense.toMap());
  }

  Future<void> deleteExpense(String expenseId) {
    return _db.collection('expenses').doc(expenseId).delete();
  }

  Stream<List<Expense>> getExpensesStream() {
    return _db.collection('expenses').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Expense.fromMap(doc.data(), doc.id))
          .toList();
    });
  }
}
