import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/customer_payment.dart';
import '../models/expense.dart';
import '../models/failed_sale.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/staff.dart';
import 'sync_service.dart';

/// A helper that wraps a source stream, caches the last emitted value,
/// and replays it to new subscribers immediately (BehaviorSubject pattern).
///
/// This fixes two problems:
/// 1. "Bad state: Stream has already been listened to" — the underlying
///    Firestore `snapshots()` stream is only subscribed once.
/// 2. Late subscribers (e.g. when switching tabs) miss the first event —
///    this replays the last value immediately on subscription.
///
/// The wrapped stream is a broadcast stream, so multiple listeners are OK.
class CachedReplayStream<T> {
  final StreamController<T> _controller =
      StreamController<T>.broadcast();
  late final StreamSubscription<T> _subscription;
  T? _lastValue;
  Object? _lastError;
  StackTrace? _lastErrorStack;
  bool _hasError = false;
  bool _isDisposed = false;

  CachedReplayStream(Stream<T> source) {
    _subscription = source.listen(
      (data) {
        _lastValue = data;
        _hasError = false;
        _lastError = null;
        _lastErrorStack = null;
        if (!_controller.isClosed && !_isDisposed) {
          _controller.add(data);
        }
      },
      onError: (Object err, StackTrace? stack) {
        _hasError = true;
        _lastError = err;
        _lastErrorStack = stack;
        if (!_controller.isClosed && !_isDisposed) {
          _controller.addError(err, stack);
        }
      },
      onDone: () {
        if (!_controller.isClosed && !_isDisposed) {
          _controller.close();
        }
      },
    );
  }

  /// Returns a stream that replays the last value (or error) to every new
  /// subscriber *synchronously on subscription*.
  ///
  /// This uses [Stream.multi] so each listener gets its own private stream
  /// with an immediate replay. The previous implementation replayed via a
  /// microtask into a throw-away broadcast controller: lazily built widgets
  /// (e.g. TabBarView pages, which are only built when their tab is opened)
  /// subscribed AFTER the microtask had fired, the broadcast controller
  /// dropped the value because it had no listener, and the widget waited
  /// forever. It also leaked one forwarder subscription per call.
  Stream<T> get stream {
    if (_isDisposed) {
      return const Stream.empty();
    }
    return Stream<T>.multi((controller) {
      // Synchronous replay for this listener.
      if (_hasError && _lastError != null) {
        controller.addError(_lastError!, _lastErrorStack);
      } else if (_lastValue != null) {
        controller.add(_lastValue as T);
      }
      // Forward subsequent events from the main controller.
      final forwarder = _controller.stream.listen(
        controller.add,
        onError: (Object err, StackTrace? stack) =>
            controller.addError(err, stack),
        onDone: controller.close,
      );
      controller.onCancel = forwarder.cancel;
    });
  }

  void dispose() {
    _isDisposed = true;
    _subscription.cancel();
    _controller.close();
  }
}

/// Abstract interface for Firestore data operations.
/// Screens depend on this interface so they can be tested with a mock.
abstract class FirestoreService {
  /// Streams products. If [isAdmin] is false, cost data is never requested or read.
  /// Seamlessly loads from local cache for offline/airplane mode support.
  /// Each stream is cached so multiple listeners share a single Firestore subscription,
  /// and late subscribers (e.g. tab switches) receive the last value immediately.
  Stream<List<Product>> getProductsStream({bool isAdmin = false});

  /// Streams sales. Cashiers only read sales documents (without cost fields).
  /// For Admins, /sales is merged with /sales_costs so profit reports receive unitCostAtSale.
  /// Each stream is cached so multiple listeners share a single Firestore subscription.
  Stream<List<Sale>> getSalesStream({bool isAdmin = false, String? staffId});

  Stream<List<CustomerPayment>> getCustomerPaymentsStream();

  Stream<List<Staff>> getStaffStream();

  Stream<List<Expense>> getExpensesStream();

  /// Drops the cached report streams (sales, products, expenses, customer
  /// payments) so the next call returns a fresh Firestore subscription.
  /// Screens holding older streams keep their last emitted data and recover
  /// on their next rebuild. Used by the Reports "Retry" action.
  void resetReportsStreams();

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

  // Cache streams so each Firestore query is only listened to once across
  // the entire app. This prevents "Bad state: Stream has already been
  // listened to" errors. Each CachedReplayStream replays the last value to
  // late subscribers (e.g. when switching tabs).
  final Map<String, CachedReplayStream<List<Product>>> _productStreams = {};
  final Map<String, CachedReplayStream<List<Sale>>> _saleStreams = {};
  CachedReplayStream<List<CustomerPayment>>? _paymentsStream;
  CachedReplayStream<List<Staff>>? _staffStream;
  CachedReplayStream<List<Expense>>? _expensesStream;

  // For cashier mode: sales are queried by staff_id. The Firestore rule
  // requires staff_id == request.auth.uid, so we use the auth UID.
  // The Staff model stores authUid separately from the document id.
  String? _cashierAuthUid;

  /// Call this with the current user's Firebase Auth UID when operating as a
  /// cashier, so that sales queries filter correctly against Firestore rules.
  void setCashierAuthUid(String? uid) {
    _cashierAuthUid = uid;
  }

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
  /// Each stream is cached so multiple listeners share a single Firestore subscription,
  /// and late subscribers (e.g. tab switches) receive the last value immediately.
  @override
  Stream<List<Product>> getProductsStream({bool isAdmin = false}) {
    final key = isAdmin ? 'admin' : 'cashier';

    if (_productStreams.containsKey(key)) {
      return _productStreams[key]!.stream;
    }

    Stream<List<Product>> baseStream;

    if (!isAdmin) {
      debugPrint('[Reports] products stream (cashier): subscribing to /products');
      baseStream = _db.collection('products').snapshots().map((snapshot) {
        debugPrint('[Reports] products stream (cashier): received ${snapshot.docs.length} docs');
        final products = snapshot.docs
            .map((doc) => Product.fromMap(doc.data(), doc.id))
            .toList();
        SyncService.instance.cacheProducts(products, isAdmin: false);
        return products;
      });
    } else {
      debugPrint('[Reports] products stream (admin): subscribing to /products + /product_costs');
      final controller = StreamController<List<Product>>.broadcast();
      List<QueryDocumentSnapshot<Map<String, dynamic>>>? productDocs;
      Map<String, Map<String, dynamic>> costs = {};

      void tryEmit() {
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
        if (productDocs == null) {
          debugPrint('[Reports] products stream (admin): first /products snapshot (${snap.docs.length} docs)');
        }
        productDocs = snap.docs;
        tryEmit();
      }, onError: (Object err, StackTrace stack) {
        debugPrint('[Reports] products stream (admin) ERROR: $err\n$stack');
        if (!controller.isClosed) controller.addError(err, stack);
      });

      final sub2 = _db.collection('product_costs').snapshots().listen((snap) {
        costs = {for (final doc in snap.docs) doc.id: doc.data()};
        tryEmit();
      }, onError: (Object err, StackTrace stack) {
        debugPrint('[Reports] product_costs stream error (non-fatal): $err');
        tryEmit();
      });

      controller.onCancel = () {
        sub1.cancel();
        sub2.cancel();
      };

      baseStream = controller.stream;
    }

    final cached = CachedReplayStream<List<Product>>(baseStream);
    _productStreams[key] = cached;
    return cached.stream;
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
    // For cashiers, use the auth UID (not the document ID) to match Firestore rules
    final effectiveStaffId = isAdmin ? null : (_cashierAuthUid ?? staffId);
    final key = isAdmin ? 'admin:all' : 'cashier:${effectiveStaffId ?? 'unknown'}';

    if (_saleStreams.containsKey(key)) {
      return _saleStreams[key]!.stream;
    }

    Stream<List<Sale>> baseStream;

    if (!isAdmin) {
      // Cashier: query /sales filtered by staff_id
      // Firestore rule requires staff_id == request.auth.uid
      var query = _db.collection('sales').orderBy('timestamp', descending: true);
      if (effectiveStaffId != null) {
        query = query.where('staff_id', isEqualTo: effectiveStaffId);
      }
      baseStream = query.snapshots().map((snapshot) {
        final sales = snapshot.docs
            .map((doc) => Sale.fromMap(doc.data(), doc.id))
            .toList();
        sales.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return sales;
      });
    } else {
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

      debugPrint('[Reports] admin sales: subscribing to /sales (orderBy timestamp DESC)');
      final sub1 = _db
          .collection('sales')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen((snap) {
        if (saleDocs == null) {
          debugPrint('[Reports] admin sales: first snapshot received (${snap.docs.length} docs)');
        }
        saleDocs = snap.docs;
        emitMerged();
      }, onError: (Object err, StackTrace stack) {
        debugPrint('[Reports] admin sales ERROR: $err\n$stack');
        if (!controller.isClosed) controller.addError(err, stack);
      });

      final sub2 = _db.collection('sales_costs').snapshots().listen((snap) {
        costs = {for (final doc in snap.docs) doc.id: doc.data()};
        emitMerged();
      }, onError: (Object err, StackTrace stack) {
        // sales_costs errors should not block the merged stream;
        // sales without cost data can still emit
        debugPrint('[Reports] sales_costs stream error (non-fatal): $err');
        emitMerged();
      });

      controller.onCancel = () {
        sub1.cancel();
        sub2.cancel();
      };

      baseStream = controller.stream;
    }

    final cached = CachedReplayStream<List<Sale>>(baseStream);
    _saleStreams[key] = cached;
    return cached.stream;
  }

  @override
  Future<Sale?> getLatestSale({String? staffId}) async {
    Query<Map<String, dynamic>> query = _db
        .collection('sales')
        .orderBy('timestamp', descending: true);
    if (staffId != null) {
      query = query.where('staff_id', isEqualTo: staffId);
    }
    debugPrint('[Reports] getLatestSale: querying /sales (staffId: $staffId)');

    final snapshot = await query
        .limit(1)
        .get(const GetOptions(source: Source.cache));
    debugPrint('[Reports] getLatestSale: ${snapshot.docs.isEmpty ? 'no' : 'found'} result');
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
    debugPrint('[Reports] customer_payments: subscribing');
    _paymentsStream ??= CachedReplayStream<List<CustomerPayment>>(
      _db
          .collection('customer_payments')
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((snapshot) {
            debugPrint('[Reports] customer_payments stream: received ${snapshot.docs.length} docs');
            return snapshot.docs
                .map((doc) => CustomerPayment.fromMap(doc.data(), doc.id))
                .toList();
          }),
    );
    return _paymentsStream!.stream;
  }

  @override
  Stream<List<Staff>> getStaffStream() {
    debugPrint('[Reports] staff stream: subscribing');
    _staffStream ??= CachedReplayStream<List<Staff>>(
      _db.collection('staff').snapshots().map((snapshot) {
        debugPrint('[Reports] staff stream: received ${snapshot.docs.length} docs');
        return snapshot.docs
            .map((doc) => Staff.fromMap(doc.data(), doc.id))
            .toList();
      }),
    );
    return _staffStream!.stream;
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
    _expensesStream ??= CachedReplayStream<List<Expense>>(
      _db.collection('expenses').snapshots().map((snapshot) {
        debugPrint('[Reports] expenses stream: received ${snapshot.docs.length} docs');
        return snapshot.docs
            .map((doc) => Expense.fromMap(doc.data(), doc.id))
            .toList();
      }),
    );
    return _expensesStream!.stream;
  }

  @override
  void resetReportsStreams() {
    debugPrint(
      '[FirestoreService] resetReportsStreams: dropping cached report streams',
    );
    for (final cached in _saleStreams.values) {
      cached.dispose();
    }
    _saleStreams.clear();
    for (final cached in _productStreams.values) {
      cached.dispose();
    }
    _productStreams.clear();
    _paymentsStream?.dispose();
    _paymentsStream = null;
    _expensesStream?.dispose();
    _expensesStream = null;
  }
}
