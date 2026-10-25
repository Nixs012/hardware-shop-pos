import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/customer_payment.dart';
import '../models/expense.dart';
import '../models/failed_sale.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/staff.dart';
import '../models/shop.dart';
import 'sync_service.dart';

/// A helper that wraps a source stream, caches the last emitted value,
/// and replays it to new subscribers immediately (BehaviorSubject pattern).
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

  Stream<T> get stream {
    if (_isDisposed) {
      return const Stream.empty();
    }
    return Stream<T>.multi((controller) {
      if (_hasError && _lastError != null) {
        controller.addError(_lastError!, _lastErrorStack);
      } else if (_lastValue != null) {
        controller.add(_lastValue as T);
      }
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
abstract class FirestoreService {
  String get shopId;

  Stream<List<Product>> getProductsStream({bool isAdmin = false});
  Stream<List<Sale>> getSalesStream({bool isAdmin = false, String? staffId});
  Stream<List<CustomerPayment>> getCustomerPaymentsStream();
  Stream<List<Staff>> getStaffStream();
  Stream<List<Expense>> getExpensesStream();

  void resetReportsStreams();

  Future<Shop?> getShop();
  Future<void> updateShop(Shop shop);
  Future<String> regenerateJoinCode([String? oldCode]);

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
  @override
  final String shopId;

  FirestoreServiceImpl([String? shopId, FirebaseFirestore? firestore])
      : shopId = shopId ?? 'default_shop',
        _db = firestore ?? FirebaseFirestore.instance;

  final Map<String, CachedReplayStream<List<Product>>> _productStreams = {};
  final Map<String, CachedReplayStream<List<Sale>>> _saleStreams = {};
  CachedReplayStream<List<CustomerPayment>>? _paymentsStream;
  CachedReplayStream<List<Staff>>? _staffStream;
  CachedReplayStream<List<Expense>>? _expensesStream;

  String? _cashierAuthUid;

  void setCashierAuthUid(String? uid) {
    _cashierAuthUid = uid;
  }

  DocumentReference<Map<String, dynamic>> get _shopRef =>
      _db.collection('shops').doc(shopId);

  @override
  Future<Shop?> getShop() async {
    final doc = await _shopRef.get();
    if (doc.exists && doc.data() != null) {
      return Shop.fromMap(doc.data()!, doc.id);
    }
    return null;
  }

  @override
  Future<void> updateShop(Shop shop) async {
    await _shopRef.update(shop.toMap());
  }

  @override
  Future<String> regenerateJoinCode([String? oldCode]) async {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    final newCode =
        List.generate(6, (index) => chars[rand.nextInt(chars.length)]).join();

    String? codeToDelete = oldCode;
    if (codeToDelete == null || codeToDelete.isEmpty) {
      final doc = await _shopRef.get();
      if (doc.exists && doc.data() != null) {
        codeToDelete = doc.data()!['join_code'] as String?;
      }
    }

    final batch = _db.batch();
    batch.update(_shopRef, {'join_code': newCode});
    if (codeToDelete != null && codeToDelete.isNotEmpty) {
      batch.delete(_db.collection('joinCodes').doc(codeToDelete));
    }
    batch.set(_db.collection('joinCodes').doc(newCode), {
      'shopId': shopId,
    });
    await batch.commit();

    return newCode;
  }

  @override
  Future<void> addProduct(Product product) {
    final batch = _db.batch();
    final productsColl = _db.collection('shops').doc(shopId).collection('products');
    final costsColl = _db.collection('shops').doc(shopId).collection('product_costs');

    batch.set(productsColl.doc(product.id), product.toMap());
    batch.set(costsColl.doc(product.id), product.toCostMap());
    return batch.commit();
  }

  @override
  Future<void> updateProduct(Product product) {
    final batch = _db.batch();
    final productsColl = _db.collection('shops').doc(shopId).collection('products');
    final costsColl = _db.collection('shops').doc(shopId).collection('product_costs');

    batch.update(productsColl.doc(product.id), product.toMap());
    batch.set(costsColl.doc(product.id), product.toCostMap(), SetOptions(merge: true));
    return batch.commit();
  }

  @override
  Future<void> deleteProduct(String productId) {
    final batch = _db.batch();
    final productsColl = _db.collection('shops').doc(shopId).collection('products');
    final costsColl = _db.collection('shops').doc(shopId).collection('product_costs');

    batch.delete(productsColl.doc(productId));
    batch.delete(costsColl.doc(productId));
    return batch.commit();
  }

  @override
  Stream<List<Product>> getProductsStream({bool isAdmin = false}) {
    final key = '$shopId:${isAdmin ? 'admin' : 'cashier'}';

    if (_productStreams.containsKey(key)) {
      return _productStreams[key]!.stream;
    }

    Stream<List<Product>> baseStream;
    final productsColl = _db.collection('shops').doc(shopId).collection('products');
    final costsColl = _db.collection('shops').doc(shopId).collection('product_costs');

    if (!isAdmin) {
      baseStream = productsColl.snapshots().map((snapshot) {
        final products = snapshot.docs
            .map((doc) => Product.fromMap(doc.data(), doc.id))
            .toList();
        SyncService.instance.cacheProducts(products, isAdmin: false);
        return products;
      });
    } else {
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

      final sub1 = productsColl.snapshots().listen((snap) {
        productDocs = snap.docs;
        tryEmit();
      }, onError: (Object err, StackTrace stack) {
        if (!controller.isClosed) controller.addError(err, stack);
      });

      final sub2 = costsColl.snapshots().listen((snap) {
        costs = {for (final doc in snap.docs) doc.id: doc.data()};
        tryEmit();
      }, onError: (Object err, StackTrace stack) {
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
      shopId: shopId,
      includeCostSnapshot: includeCostSnapshot,
    );
  }

  @override
  Future<List<FailedSaleRecord>> getFailedSales() {
    return SyncService.instance.getFailedSales(shopId);
  }

  @override
  Future<void> retryFailedSale(FailedSaleRecord record) {
    return SyncService.instance.retryFailedSale(record, shopId);
  }

  @override
  Stream<List<Sale>> getSalesStream({bool isAdmin = false, String? staffId}) {
    final effectiveStaffId = isAdmin ? null : (_cashierAuthUid ?? staffId);
    final key = '$shopId:${isAdmin ? 'admin:all' : 'cashier:${effectiveStaffId ?? 'unknown'}'}';

    if (_saleStreams.containsKey(key)) {
      return _saleStreams[key]!.stream;
    }

    Stream<List<Sale>> baseStream;
    final salesColl = _db.collection('shops').doc(shopId).collection('sales');
    final costsColl = _db.collection('shops').doc(shopId).collection('sales_costs');

    if (!isAdmin) {
      var query = salesColl.orderBy('timestamp', descending: true);
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

      final sub1 = salesColl
          .orderBy('timestamp', descending: true)
          .snapshots()
          .listen((snap) {
        saleDocs = snap.docs;
        emitMerged();
      }, onError: (Object err, StackTrace stack) {
        if (!controller.isClosed) controller.addError(err, stack);
      });

      final sub2 = costsColl.snapshots().listen((snap) {
        costs = {for (final doc in snap.docs) doc.id: doc.data()};
        emitMerged();
      }, onError: (Object err, StackTrace stack) {
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
        .collection('shops')
        .doc(shopId)
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

  @override
  Future<void> recordCustomerPayment(CustomerPayment payment) {
    final paymentsColl = _db.collection('shops').doc(shopId).collection('customer_payments');
    if (SyncService.instance.isOnline) {
      return paymentsColl.doc(payment.id).set(payment.toMap());
    } else {
      return SyncService.instance.queuePayment(payment, shopId);
    }
  }

  @override
  Stream<List<CustomerPayment>> getCustomerPaymentsStream() {
    final paymentsColl = _db.collection('shops').doc(shopId).collection('customer_payments');
    _paymentsStream ??= CachedReplayStream<List<CustomerPayment>>(
      paymentsColl
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((snapshot) {
            return snapshot.docs
                .map((doc) => CustomerPayment.fromMap(doc.data(), doc.id))
                .toList();
          }),
    );
    return _paymentsStream!.stream;
  }

  @override
  Stream<List<Staff>> getStaffStream() {
    final staffColl = _db.collection('shops').doc(shopId).collection('staff');
    _staffStream ??= CachedReplayStream<List<Staff>>(
      staffColl.snapshots().map((snapshot) {
        return snapshot.docs
            .map((doc) => Staff.fromMap(doc.data(), doc.id))
            .toList();
      }),
    );
    return _staffStream!.stream;
  }

  @override
  Future<void> updateStaff(Staff staff) {
    return _db
        .collection('shops')
        .doc(shopId)
        .collection('staff')
        .doc(staff.id)
        .update(staff.toMap());
  }

  @override
  Future<void> addExpense(Expense expense) {
    return _db
        .collection('shops')
        .doc(shopId)
        .collection('expenses')
        .doc(expense.id)
        .set(expense.toMap());
  }

  @override
  Future<void> updateExpense(Expense expense) {
    return _db
        .collection('shops')
        .doc(shopId)
        .collection('expenses')
        .doc(expense.id)
        .update(expense.toMap());
  }

  @override
  Future<void> deleteExpense(String expenseId) {
    return _db
        .collection('shops')
        .doc(shopId)
        .collection('expenses')
        .doc(expenseId)
        .delete();
  }

  @override
  Stream<List<Expense>> getExpensesStream() {
    final expensesColl = _db.collection('shops').doc(shopId).collection('expenses');
    _expensesStream ??= CachedReplayStream<List<Expense>>(
      expensesColl.snapshots().map((snapshot) {
        return snapshot.docs
            .map((doc) => Expense.fromMap(doc.data(), doc.id))
            .toList();
      }),
    );
    return _expensesStream!.stream;
  }

  @override
  void resetReportsStreams() {
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
