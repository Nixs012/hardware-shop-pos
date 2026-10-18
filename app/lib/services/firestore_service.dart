import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/customer_payment.dart';
import '../models/expense.dart';
import '../models/failed_sale.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/staff.dart';
import 'sync_service.dart';

/// Abstract interface for Firestore data operations.
/// Screens depend on this interface so they can be tested with a mock.
abstract class FirestoreService {
  /// Streams products. If [isAdmin] is false, cost data is never requested or read.
  /// Seamlessly loads from local cache for offline/airplane mode support.
  /// Each stream is cached so multiple listeners share a single Firestore subscription.
  Stream<List<Product>> getProductsStream({bool isAdmin = false});

  /// Streams sales. Cashiers only read sales documents (without cost fields).
  /// For Admins, /sales is merged with /sales_costs so profit reports receive unitCostAtSale.
  /// Each stream is cached so multiple listeners share a single Firestore subscription.
  Stream<List<Sale>> getSalesStream({bool isAdmin = false, String? staffId});

  Stream<List<CustomerPayment>> getCustomerPaymentsStream();

  Stream<List<Staff>> getStaffStream();

  Stream<List<Expense>> getExpensesStream();

  Future<void> addProduct(Product product);
  Future<void> updateProduct(Product product);
  Future<void> deleteProduct(String productId);

  Future<void> processSale(Sale sale, {bool includeCostSnapshot = true});
  Future<Sale?> getLatestSale({String? staffId});

  Future<void> recordCustomerPayment(CustomerPayment payment);

  Future<void> addExpense(Expense expense);
  Future<void> updateExpense(Expense expense);
  Future<void> deleteExpense(String expenseId);

  Future<void> updateStaff(Staff staff);
  Future<List<FailedSaleRecord>> getFailedSales();
  Future<void> retryFailedSale(FailedSaleRecord record);
}

class FirestoreServiceImpl implements FirestoreService {
  final FirebaseFirestore _db;

  FirestoreServiceImpl({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  // Cache single-subscription streams so each Firestore query is only
  // listened to once across the entire app. This prevents "Bad state:
  // Stream has already been listened to" errors when multiple StreamBuilders
  // subscribe to the same stream (e.g., across report tab switches).
  final Map<String, Stream<List<Product>>> _productStreams = {};
  final Map<String, Stream<List<Sale>>> _saleStreams = {};
  Stream<List<CustomerPayment>>? _paymentsStream;
  Stream<List<Staff>>? _staffStream;
  Stream<List<Expense>>? _expensesStream;

  @override
  Future<void> addProduct(Product product) {
    final batch = _db.batch();
    batch.set(_db.collection('products').doc(product.id), product.toMap());
    batch.set(
      _db.collection('product_costs').doc(product.id),
      product.toCostMap(),
    );
    return batch.commit();
  }

  @override
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

  @override
  Future<void> deleteProduct(String productId) {
    final batch = _db.batch();
    batch.delete(_db.collection('products').doc(productId));
    batch.delete(_db.collection('product_costs').doc(productId));
    return batch.commit();
  }

  /// Streams products. If [isAdmin] is false, cost data is never requested or read.
  /// Seamlessly loads from local cache for offline/airplane mode support.
  /// Each stream is cached so multiple listeners share a single Firestore subscription.
  @override
  Stream<List<Product>> getProductsStream({bool isAdmin = false}) {
    final key = isAdmin ? 'admin' : 'cashier';
    if (_productStreams.containsKey(key)) {
      return _productStreams[key]!;
    }

    final controller = StreamController<List<Product>>.broadcast();

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
      _productStreams[key] = controller.stream;
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

    _productStreams[key] = controller.stream;
    return controller.stream;
  }

  @override
  Future<void> processSale(Sale sale, {bool includeCostSnapshot = true}) async {
    await SyncService.instance.queueSale(
      sale,
      includeCostSnapshot: includeCostSnapshot,
    );
  }

  @override
  Future<List<FailedSaleRecord>> getFailedSales() {
    return SyncService.instance.getFailedSales();
  }

  @override
  Future<void> retryFailedSale(FailedSaleRecord record) {
    return SyncService.instance.retryFailedSale(record);
  }

  /// Streams sales. Cashiers only read sales documents (without cost fields).
  /// For Admins, /sales is merged with /sales_costs so profit reports receive unitCostAtSale.
  /// Each stream is cached so multiple listeners share a single Firestore subscription.
  @override
  Stream<List<Sale>> getSalesStream({bool isAdmin = false, String? staffId}) {
    final key = isAdmin ? 'admin:${staffId ?? 'all' }' : 'cashier:$staffId';
    if (_saleStreams.containsKey(key)) {
      return _saleStreams[key]!;
    }

    if (!isAdmin) {
      var query = _db.collection('sales').orderBy('timestamp', descending: true);
      if (staffId != null) {
        query = query.where('staff_id', isEqualTo: staffId);
      }
      final stream = query.snapshots().map((snapshot) {
        final sales = snapshot.docs
            .map((doc) => Sale.fromMap(doc.data(), doc.id))
            .toList();
        sales.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return sales;
      });
      _saleStreams[key] = stream;
      return stream;
    }

    // For Admin: merge /sales with admin-only /sales_costs
    final controller = StreamController<List<Sale>>.broadcast();
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

    _saleStreams[key] = controller.stream;
    return controller.stream;
  }

  @override
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

  @override
  Future<void> recordCustomerPayment(CustomerPayment payment) {
    if (SyncService.instance.isOnline) {
      // Online: write directly to Firestore
      return _db
          .collection('customer_payments')
          .doc(payment.id)
          .set(payment.toMap());
    } else {
      // Offline: queue for sync when connectivity is restored
      return SyncService.instance.queuePayment(payment);
    }
  }

  @override
  Stream<List<CustomerPayment>> getCustomerPaymentsStream() {
    _paymentsStream ??= _db
        .collection('customer_payments')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => CustomerPayment.fromMap(doc.data(), doc.id))
              .toList();
        });
    return _paymentsStream!;
  }

  @override
  Stream<List<Staff>> getStaffStream() {
    _staffStream ??= _db.collection('staff').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Staff.fromMap(doc.data(), doc.id))
          .toList();
    });
    return _staffStream!;
  }

  @override
  Future<void> updateStaff(Staff staff) {
    return _db.collection('staff').doc(staff.id).update(staff.toMap());
  }

  // --- Expenses (Ledger for P&L) ---

  @override
  Future<void> addExpense(Expense expense) {
    return _db.collection('expenses').doc(expense.id).set(expense.toMap());
  }

  @override
  Future<void> updateExpense(Expense expense) {
    return _db
        .collection('expenses')
        .doc(expense.id)
        .update(expense.toMap());
  }

  @override
  Future<void> deleteExpense(String expenseId) {
    return _db.collection('expenses').doc(expenseId).delete();
  }

  @override
  Stream<List<Expense>> getExpensesStream() {
    _expensesStream ??= _db.collection('expenses').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Expense.fromMap(doc.data(), doc.id))
          .toList();
    });
    return _expensesStream!;
  }
}
