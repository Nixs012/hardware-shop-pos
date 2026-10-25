import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/customer_payment.dart';
import '../models/failed_sale.dart';
import '../models/product.dart';
import '../models/queued_payment.dart';
import '../models/queued_sale.dart';
import '../models/sale.dart';

class SyncStatus {
  final bool isOnline;
  final int pendingCount;
  final bool isSyncing;

  const SyncStatus({
    required this.isOnline,
    required this.pendingCount,
    this.isSyncing = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncStatus &&
          runtimeType == other.runtimeType &&
          isOnline == other.isOnline &&
          pendingCount == other.pendingCount &&
          isSyncing == other.isSyncing;

  @override
  int get hashCode =>
      isOnline.hashCode ^ pendingCount.hashCode ^ isSyncing.hashCode;
}

abstract class SyncStorage {
  Future<void> init();
  Future<void> savePending(QueuedSale sale);
  Future<void> removePending(String saleId);
  Future<List<QueuedSale>> getPendingSales();
  Future<int> getPendingCount();

  Future<void> saveNeedsReview(QueuedSale sale);
  Future<void> removeNeedsReview(String saleId);
  Future<List<QueuedSale>> getNeedsReviewSales();

  Future<void> cacheProducts(List<Product> products, {bool isAdmin = false});
  Future<List<Product>> getCachedProducts();
  Future<void> updateCachedProductStock(String productId, double delta);
  Future<void> clearCachedCostData();

  // Customer Payment sync
  Future<void> savePendingPayment(QueuedPayment payment);
  Future<void> removePendingPayment(String paymentId);
  Future<List<QueuedPayment>> getPendingPayments();
}

class HiveSyncStorage implements SyncStorage {
  String _shopId = 'default_shop';

  void setShopId(String shopId) {
    _shopId = shopId;
  }

  String get _pendingBoxName => 'pending_sales_$_shopId';
  String get _needsReviewBoxName => 'needs_review_sales_$_shopId';
  String get _productsBoxName => 'cached_products_$_shopId';
  String get _pendingPaymentsBoxName => 'pending_payments_$_shopId';

  late Box<Map> _pendingBox;
  late Box<Map> _needsReviewBox;
  late Box<Map> _productsBox;
  late Box<Map> _pendingPaymentsBox;

  @override
  Future<void> init() async {
    _pendingBox = await Hive.openBox<Map>(_pendingBoxName);
    _needsReviewBox = await Hive.openBox<Map>(_needsReviewBoxName);
    _productsBox = await Hive.openBox<Map>(_productsBoxName);
    _pendingPaymentsBox = await Hive.openBox<Map>(_pendingPaymentsBoxName);
  }

  Future<void> clearLocalCaches() async {
    try {
      if (_pendingBox.isOpen) await _pendingBox.clear();
      if (_needsReviewBox.isOpen) await _needsReviewBox.clear();
      if (_productsBox.isOpen) await _productsBox.clear();
      if (_pendingPaymentsBox.isOpen) await _pendingPaymentsBox.clear();
    } catch (_) {}
  }

  @override
  Future<void> savePending(QueuedSale sale) async {
    await _pendingBox.put(sale.sale.id, sale.toMap());
  }

  @override
  Future<void> removePending(String saleId) async {
    await _pendingBox.delete(saleId);
  }

  @override
  Future<List<QueuedSale>> getPendingSales() async {
    final list = <QueuedSale>[];
    for (final raw in _pendingBox.values) {
      try {
        final map = Map<String, dynamic>.from(raw);
        list.add(QueuedSale.fromMap(map));
      } catch (e) {
        debugPrint('Error parsing pending sale: $e');
      }
    }
    list.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return list;
  }

  @override
  Future<int> getPendingCount() async {
    return _pendingBox.length;
  }

  @override
  Future<void> saveNeedsReview(QueuedSale sale) async {
    await _needsReviewBox.put(sale.sale.id, sale.toMap());
  }

  @override
  Future<void> removeNeedsReview(String saleId) async {
    await _needsReviewBox.delete(saleId);
  }

  @override
  Future<List<QueuedSale>> getNeedsReviewSales() async {
    final list = <QueuedSale>[];
    for (final raw in _needsReviewBox.values) {
      try {
        final map = Map<String, dynamic>.from(raw);
        list.add(QueuedSale.fromMap(map));
      } catch (e) {
        debugPrint('Error parsing needs review sale: $e');
      }
    }
    list.sort((a, b) => (b.lastAttemptAt ?? b.queuedAt).compareTo(a.lastAttemptAt ?? a.queuedAt));
    return list;
  }

  @override
  Future<void> cacheProducts(List<Product> products, {bool isAdmin = false}) async {
    final map = <String, Map<String, dynamic>>{};
    for (final product in products) {
      final entry = <String, dynamic>{...product.toMap()};
      if (isAdmin) {
        entry['cost_price'] = product.costPrice;
        entry['cost_price_estimated'] = product.costPriceEstimated;
      }
      map[product.id] = entry;
    }
    await _productsBox.putAll(map);
  }

  @override
  Future<List<Product>> getCachedProducts() async {
    final list = <Product>[];
    for (final raw in _productsBox.values) {
      try {
        final map = Map<String, dynamic>.from(raw);
        final id = map['id'] as String? ?? '';
        list.add(Product.fromMap(map, id));
      } catch (e) {
        debugPrint('Error parsing cached product: $e');
      }
    }
    return list;
  }

  @override
  Future<void> updateCachedProductStock(String productId, double delta) async {
    final raw = _productsBox.get(productId);
    if (raw == null) return;
    try {
      final map = Map<String, dynamic>.from(raw);
      final currentStock = (map['quantity_on_hand'] as num? ?? 0).toDouble();
      map['quantity_on_hand'] = currentStock + delta;
      await _productsBox.put(productId, map);
    } catch (e) {
      debugPrint('Error updating cached product stock: $e');
    }
  }

  @override
  Future<void> clearCachedCostData() async {
    final keys = _productsBox.keys.toList();
    for (final key in keys) {
      final raw = _productsBox.get(key);
      if (raw != null) {
        final m = Map<String, dynamic>.from(raw);
        m.remove('cost_price');
        m.remove('cost_price_estimated');
        await _productsBox.put(key, m);
      }
    }
  }

  @override
  Future<void> savePendingPayment(QueuedPayment payment) async {
    await _pendingPaymentsBox.put(payment.payment.id, payment.toMap());
  }

  @override
  Future<void> removePendingPayment(String paymentId) async {
    await _pendingPaymentsBox.delete(paymentId);
  }

  @override
  Future<List<QueuedPayment>> getPendingPayments() async {
    final list = <QueuedPayment>[];
    for (final raw in _pendingPaymentsBox.values) {
      try {
        final map = Map<String, dynamic>.from(raw);
        list.add(QueuedPayment.fromMap(map));
      } catch (e) {
        debugPrint('Error parsing pending payment: $e');
      }
    }
    list.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return list;
  }
}

class MemorySyncStorage implements SyncStorage {
  final Map<String, Map<String, dynamic>> _pending = {};
  final Map<String, Map<String, dynamic>> _needsReview = {};
  final Map<String, Map<String, dynamic>> _products = {};
  final Map<String, Map<String, dynamic>> _pendingPayments = {};

  @override
  Future<void> init() async {}

  @override
  Future<void> savePending(QueuedSale sale) async {
    _pending[sale.sale.id] = sale.toMap();
  }

  @override
  Future<void> removePending(String saleId) async {
    _pending.remove(saleId);
  }

  @override
  Future<List<QueuedSale>> getPendingSales() async {
    final list = _pending.values
        .map((m) => QueuedSale.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    list.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return list;
  }

  @override
  Future<int> getPendingCount() async => _pending.length;

  @override
  Future<void> saveNeedsReview(QueuedSale sale) async {
    _needsReview[sale.sale.id] = sale.toMap();
  }

  @override
  Future<void> removeNeedsReview(String saleId) async {
    _needsReview.remove(saleId);
  }

  @override
  Future<List<QueuedSale>> getNeedsReviewSales() async {
    final list = _needsReview.values
        .map((m) => QueuedSale.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    list.sort((a, b) =>
        (b.lastAttemptAt ?? b.queuedAt).compareTo(a.lastAttemptAt ?? a.queuedAt));
    return list;
  }

  @override
  Future<void> cacheProducts(List<Product> products, {bool isAdmin = false}) async {
    for (final p in products) {
      final entry = <String, dynamic>{...p.toMap()};
      if (isAdmin) {
        entry['cost_price'] = p.costPrice;
        entry['cost_price_estimated'] = p.costPriceEstimated;
      }
      _products[p.id] = entry;
    }
  }

  @override
  Future<List<Product>> getCachedProducts() async {
    return _products.values
        .map((m) => Product.fromMap(Map<String, dynamic>.from(m), m['id'] as String))
        .toList();
  }

  @override
  Future<void> updateCachedProductStock(String productId, double delta) async {
    final m = _products[productId];
    if (m == null) return;
    final current = (m['quantity_on_hand'] as num? ?? 0).toDouble();
    m['quantity_on_hand'] = current + delta;
  }

  @override
  Future<void> clearCachedCostData() async {
    for (final m in _products.values) {
      m.remove('cost_price');
      m.remove('cost_price_estimated');
    }
  }

  @override
  Future<void> savePendingPayment(QueuedPayment payment) async {
    _pendingPayments[payment.payment.id] = payment.toMap();
  }

  @override
  Future<void> removePendingPayment(String paymentId) async {
    _pendingPayments.remove(paymentId);
  }

  @override
  Future<List<QueuedPayment>> getPendingPayments() async {
    final list = _pendingPayments.values
        .map((m) => QueuedPayment.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    list.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return list;
  }
}

typedef SyncSaleCallback = Future<void> Function(QueuedSale sale, String shopId);
typedef SyncPaymentCallback = Future<void> Function(QueuedPayment payment, String shopId);

class SyncService {
  static final SyncService _instance = SyncService._internal();
  static SyncService get instance => _instance;

  final SyncStorage _storage;
  final Connectivity? _connectivity;
  final SyncSaleCallback? _customSyncSale;
  final SyncPaymentCallback? _customSyncPayment;

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isOnline = false;
  bool _isSyncing = false;
  int _pendingCount = 0;
  static const int maxRetries = 5;

  SyncService._internal({
    SyncStorage? storage,
    Connectivity? connectivity,
    SyncSaleCallback? syncSale,
    SyncPaymentCallback? syncPayment,
  })  : _storage = storage ?? HiveSyncStorage(),
        _connectivity = connectivity ?? Connectivity(),
        _customSyncSale = syncSale,
        _customSyncPayment = syncPayment;

  factory SyncService.custom({
    required SyncStorage storage,
    Connectivity? connectivity,
    SyncSaleCallback? syncSale,
    SyncPaymentCallback? syncPayment,
    bool initialOnline = false,
  }) {
    final s = SyncService._internal(
      storage: storage,
      connectivity: connectivity,
      syncSale: syncSale,
      syncPayment: syncPayment,
    );
    s._isOnline = initialOnline;
    return s;
  }

  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncStatus get currentStatus => SyncStatus(
        isOnline: _isOnline,
        pendingCount: _pendingCount,
        isSyncing: _isSyncing,
      );

  bool get isOnline => _isOnline;
  int get pendingCount => _pendingCount;
  bool get isSyncing => _isSyncing;
  String _currentShopId = 'default_shop';
  String get currentShopId => _currentShopId;

  Future<void> init([String shopId = 'default_shop']) async {
    _currentShopId = shopId;
    if (_storage is HiveSyncStorage) {
      _storage.setShopId(shopId);
    }
    await _storage.init();
    _pendingCount = await _storage.getPendingCount();

    if (_connectivity != null) {
      try {
        final initial = await _connectivity.checkConnectivity();
        _isOnline = _checkIsOnline(initial);
      } catch (e) {
        _isOnline = false;
      }

      _connectivitySubscription ??=
          _connectivity.onConnectivityChanged.listen((results) {
        final onlineNow = _checkIsOnline(results);
        final changed = onlineNow != _isOnline;
        _isOnline = onlineNow;
        _notifyStatus();
        if (changed && _isOnline) {
          unawaited(drainQueue(_currentShopId));
        }
      });
    }

    _notifyStatus();
  }

  Future<void> switchShop(String shopId) async {
    _currentShopId = shopId;
    if (_storage is HiveSyncStorage) {
      _storage.setShopId(shopId);
      await _storage.init();
    }
    _pendingCount = await _storage.getPendingCount();
    _notifyStatus();
    if (_isOnline && _pendingCount > 0) {
      unawaited(drainQueue(shopId));
    }
  }

  Future<void> clearLocalCaches() async {
    if (_storage is HiveSyncStorage) {
      await _storage.clearLocalCaches();
    }
    _pendingCount = 0;
    _notifyStatus();
  }

  void setOnlineForTesting(bool online) {
    _isOnline = online;
    _notifyStatus();
  }

  static bool _checkIsOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn ||
        r == ConnectivityResult.other ||
        (r != ConnectivityResult.none && r != ConnectivityResult.bluetooth));
  }

  void _notifyStatus() {
    if (!_statusController.isClosed) {
      _statusController.add(currentStatus);
    }
  }

  Duration calculateBackoff(int retryCount) {
    if (retryCount <= 0) return Duration.zero;
    final shift = (1 << retryCount).clamp(2, 120);
    return Duration(seconds: shift);
  }

  Future<void> queueSale(
    Sale sale, {
    String shopId = 'default_shop',
    bool includeCostSnapshot = true,
  }) async {
    final queuedSale = QueuedSale(
      sale: sale,
      includeCostSnapshot: includeCostSnapshot,
      queuedAt: DateTime.now(),
    );
    await _storage.savePending(queuedSale);
    _pendingCount = await _storage.getPendingCount();
    _notifyStatus();

    // Optimistically update local stock
    for (final item in sale.lineItems) {
      await _storage.updateCachedProductStock(item.productId, -item.quantity);
    }

    if (_isOnline) {
      await drainQueue(shopId);
    }
  }

  Future<void> queuePayment(CustomerPayment payment, [String shopId = 'default_shop']) async {
    final queuedPayment = QueuedPayment(
      payment: payment,
      queuedAt: DateTime.now(),
    );
    await _storage.savePendingPayment(queuedPayment);
    if (_isOnline) {
      await drainQueue(shopId);
    }
  }

  Future<List<FailedSaleRecord>> getFailedSales([String? shopId]) async {
    final needsReview = await _storage.getNeedsReviewSales();
    return needsReview.map((q) => q.toFailedSaleRecord()).toList();
  }

  Future<void> retryFailedSale(FailedSaleRecord record, [String? shopId]) async {
    final effectiveShopId = (shopId != null && shopId.isNotEmpty) ? shopId : _currentShopId;
    await _storage.removeNeedsReview(record.sale.id);
    final queued = QueuedSale(
      sale: record.sale,
      includeCostSnapshot: true,
      retryCount: 0,
      queuedAt: DateTime.now(),
      lastError: null,
      lastAttemptAt: null,
    );
    await _storage.savePending(queued);
    _pendingCount = await _storage.getPendingCount();
    _notifyStatus();
    if (_isOnline) {
      await drainQueue(effectiveShopId);
    }
  }

  Future<void> drainQueue([String? shopId]) async {
    final effectiveShopId = (shopId != null && shopId.isNotEmpty) ? shopId : _currentShopId;
    if (_isSyncing || !_isOnline) return;
    _isSyncing = true;
    _notifyStatus();

    try {
      await _drainSales(effectiveShopId);
      await _drainPayments(effectiveShopId);
    } finally {
      _isSyncing = false;
      _pendingCount = await _storage.getPendingCount();
      _notifyStatus();
    }
  }

  Future<void> _drainSales(String shopId) async {
    final pending = await _storage.getPendingSales();
    if (pending.isEmpty) return;

    for (final queued in pending) {
      if (!_isOnline) break;
      try {
        if (_customSyncSale != null) {
          await _customSyncSale(queued, shopId);
        } else {
          final db = FirebaseFirestore.instance;
          final saleId = queued.sale.id;
          final saleRef = db.collection('shops').doc(shopId).collection('sales').doc(saleId);
          final costRef = db.collection('shops').doc(shopId).collection('sales_costs').doc(saleId);

          debugPrint(
              '[SyncService] Draining sale $saleId to shops/$shopId/sales (includeCostSnapshot: ${queued.includeCostSnapshot})...');

          bool exists = false;
          try {
            final existing = await saleRef.get();
            exists = existing.exists;
          } catch (e) {
            debugPrint('[SyncService] saleRef.get check for $saleId caught: $e');
            exists = false;
          }

          if (!exists) {
            final batch = db.batch();
            batch.set(saleRef, queued.sale.toMap());
            if (queued.includeCostSnapshot) {
              batch.set(costRef, queued.sale.toCostMap());
            }

            for (final item in queued.sale.lineItems) {
              final productRef = db.collection('shops').doc(shopId).collection('products').doc(item.productId);
              batch.update(productRef, {
                'quantity_on_hand': FieldValue.increment(-item.quantity),
              });
            }
            await batch.commit();
            debugPrint('[SyncService] Sale $saleId successfully committed to shops/$shopId/sales');
          }
        }

        await _storage.removePending(queued.sale.id);
        debugPrint('[SyncService] Sale ${queued.sale.id} removed from pending queue');
      } catch (e, stack) {
        debugPrint('[SyncService] ERROR draining sale ${queued.sale.id}: $e\n$stack');
        final newRetryCount = queued.retryCount + 1;
        if (newRetryCount >= maxRetries) {
          await _storage.removePending(queued.sale.id);
          final failed = QueuedSale(
            sale: queued.sale,
            includeCostSnapshot: queued.includeCostSnapshot,
            queuedAt: queued.queuedAt,
            retryCount: newRetryCount,
            lastError: e.toString(),
            lastAttemptAt: DateTime.now(),
          );
          await _storage.saveNeedsReview(failed);
        } else {
          final updated = QueuedSale(
            sale: queued.sale,
            includeCostSnapshot: queued.includeCostSnapshot,
            queuedAt: queued.queuedAt,
            retryCount: newRetryCount,
            lastError: e.toString(),
            lastAttemptAt: DateTime.now(),
          );
          await _storage.savePending(updated);
        }
      }
    }
  }

  Future<void> _drainPayments(String shopId) async {
    final pendingPayments = await _storage.getPendingPayments();
    if (pendingPayments.isEmpty) return;

    final db = FirebaseFirestore.instance;

    for (final queued in pendingPayments) {
      if (!_isOnline) break;
      try {
        if (_customSyncPayment != null) {
          await _customSyncPayment(queued, shopId);
        } else {
          await db
              .collection('shops')
              .doc(shopId)
              .collection('customer_payments')
              .doc(queued.payment.id)
              .set(queued.payment.toMap());
        }
        await _storage.removePendingPayment(queued.payment.id);
      } catch (_) {}
    }
  }

  Future<void> cacheProducts(List<Product> products, {bool isAdmin = false}) async {
    await _storage.cacheProducts(products, isAdmin: isAdmin);
  }

  Future<void> clearCachedCostData() async {
    await _storage.clearCachedCostData();
  }

  Future<List<Product>> getCachedProducts() async {
    return _storage.getCachedProducts();
  }
}
