import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/failed_sale.dart';
import '../models/product.dart';
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

  Future<void> cacheProducts(List<Product> products);
  Future<List<Product>> getCachedProducts();
  Future<void> updateCachedProductStock(String productId, double delta);
}

class HiveSyncStorage implements SyncStorage {
  static const String pendingBoxName = 'pending_sales';
  static const String needsReviewBoxName = 'needs_review_sales';
  static const String productsBoxName = 'cached_products';

  late Box<Map> _pendingBox;
  late Box<Map> _needsReviewBox;
  late Box<Map> _productsBox;

  @override
  Future<void> init() async {
    _pendingBox = await Hive.openBox<Map>(pendingBoxName);
    _needsReviewBox = await Hive.openBox<Map>(needsReviewBoxName);
    _productsBox = await Hive.openBox<Map>(productsBoxName);
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
  Future<void> cacheProducts(List<Product> products) async {
    final map = <String, Map<String, dynamic>>{};
    for (final product in products) {
      map[product.id] = {
        ...product.toMap(),
        'cost_price': product.costPrice,
        'cost_price_estimated': product.costPriceEstimated,
      };
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
}

class MemorySyncStorage implements SyncStorage {
  final Map<String, Map<String, dynamic>> _pending = {};
  final Map<String, Map<String, dynamic>> _needsReview = {};
  final Map<String, Map<String, dynamic>> _products = {};

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
  Future<void> cacheProducts(List<Product> products) async {
    for (final p in products) {
      _products[p.id] = {
        ...p.toMap(),
        'cost_price': p.costPrice,
        'cost_price_estimated': p.costPriceEstimated,
      };
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
}

typedef SyncSaleCallback = Future<void> Function(QueuedSale sale);

class SyncService {
  static final SyncService _instance = SyncService._internal();
  static SyncService get instance => _instance;

  final SyncStorage _storage;
  final Connectivity? _connectivity;
  final SyncSaleCallback? _customSyncSale;

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
  })  : _storage = storage ?? HiveSyncStorage(),
        _connectivity = connectivity ?? Connectivity(),
        _customSyncSale = syncSale;

  /// Visible for testing to instantiate isolated pure Dart instances
  factory SyncService.custom({
    required SyncStorage storage,
    Connectivity? connectivity,
    SyncSaleCallback? syncSale,
    bool initialOnline = false,
  }) {
    final s = SyncService._internal(
      storage: storage,
      connectivity: connectivity,
      syncSale: syncSale,
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

  Future<void> init() async {
    await _storage.init();
    _pendingCount = await _storage.getPendingCount();

    if (_connectivity != null) {
      try {
        final initial = await _connectivity.checkConnectivity();
        _isOnline = _checkIsOnline(initial);
      } catch (e) {
        _isOnline = false;
        debugPrint('Connectivity check failed: $e');
      }

      _connectivitySubscription =
          _connectivity.onConnectivityChanged.listen((results) {
        final onlineNow = _checkIsOnline(results);
        final changed = onlineNow != _isOnline;
        _isOnline = onlineNow;
        _notifyStatus();
        if (changed && _isOnline) {
          unawaited(drainQueue());
        }
      });
    }

    _notifyStatus();

    if (_isOnline) {
      unawaited(drainQueue());
    }
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
        r == ConnectivityResult.vpn);
  }

  void _notifyStatus() {
    if (!_statusController.isClosed) {
      _statusController.add(currentStatus);
    }
  }

  Duration calculateBackoff(int retryCount) {
    if (retryCount <= 0) return Duration.zero;
    // 2s, 4s, 8s, 16s, 32s... capped at 120s
    final shift = (1 << retryCount).clamp(2, 120);
    return Duration(seconds: shift);
  }

  Future<void> queueSale(
    Sale sale, {
    bool includeCostSnapshot = true,
  }) async {
    final queuedSale = QueuedSale(
      sale: sale,
      includeCostSnapshot: includeCostSnapshot,
      queuedAt: DateTime.now(),
    );

    await _storage.savePending(queuedSale);

    // Optimistically update local stock in cached products for instant offline UI
    for (final item in sale.lineItems) {
      await _storage.updateCachedProductStock(item.productId, -item.quantity);
    }

    _pendingCount = await _storage.getPendingCount();
    _notifyStatus();

    if (_isOnline) {
      unawaited(drainQueue());
    }
  }

  Future<void>? _syncingFuture;

  Future<void> drainQueue() async {
    if (_syncingFuture != null) {
      return _syncingFuture!;
    }
    _syncingFuture = _performDrain();
    try {
      await _syncingFuture;
    } finally {
      _syncingFuture = null;
    }
  }

  Future<void> _performDrain() async {
    _isSyncing = true;
    _notifyStatus();

    try {
      final pending = await _storage.getPendingSales();
      final now = DateTime.now();

      for (final item in pending) {
        if (!_isOnline) {
          break; // Stop draining when offline
        }

        // Check exponential backoff window
        if (item.retryCount > 0 && item.lastAttemptAt != null) {
          final backoff = calculateBackoff(item.retryCount);
          if (now.difference(item.lastAttemptAt!) < backoff) {
            continue; // Skip until backoff elapsed
          }
        }

        try {
          if (_customSyncSale != null) {
            await _customSyncSale(item);
          } else {
            await _defaultFirestoreSync(item);
          }

          // Successfully synced! Remove from pending
          await _storage.removePending(item.sale.id);
        } catch (error) {
          final nextRetry = item.retryCount + 1;
          final lastError = error.toString();

          if (nextRetry >= maxRetries) {
            // Exceeded retries: Route to Needs Review for admins and NEVER delete
            final reviewItem = item.copyWith(
              retryCount: nextRetry,
              lastAttemptAt: DateTime.now(),
              lastError: lastError,
            );
            await _storage.saveNeedsReview(reviewItem);
            await _storage.removePending(item.sale.id);
            debugPrint(
              'Sale ${item.sale.id} moved to Needs Review after $nextRetry retries.',
            );
          } else {
            // Update retry count and backoff timestamp
            final updated = item.copyWith(
              retryCount: nextRetry,
              lastAttemptAt: DateTime.now(),
              lastError: lastError,
            );
            await _storage.savePending(updated);
          }
        }
      }
    } finally {
      _pendingCount = await _storage.getPendingCount();
      _isSyncing = false;
      _notifyStatus();
    }
  }

  Future<void> _defaultFirestoreSync(QueuedSale queuedSale) async {
    final db = FirebaseFirestore.instance;
    final saleId = queuedSale.sale.id;

    // 1. Idempotency check: Client UUID prevents duplicate sales
    final existing = await db.collection('sales').doc(saleId).get();
    if (existing.exists) {
      // Sale already exists in Firestore!
      // If admin cost document is missing, ensure it's recorded
      if (queuedSale.includeCostSnapshot) {
        final costDoc = await db.collection('sales_costs').doc(saleId).get();
        if (!costDoc.exists) {
          await db
              .collection('sales_costs')
              .doc(saleId)
              .set(queuedSale.sale.toCostMap());
        }
      }
      return; // Never re-decrement stock for an already written sale
    }

    final batch = db.batch();

    // 2. Add public sale document (strictly without unit_cost_at_sale)
    final saleRef = db.collection('sales').doc(saleId);
    batch.set(saleRef, queuedSale.sale.toMap());

    // 3. Add admin-only sales_costs document with unit_cost_at_sale snapshot
    if (queuedSale.includeCostSnapshot) {
      final costRef = db.collection('sales_costs').doc(saleId);
      batch.set(costRef, queuedSale.sale.toCostMap());
    }

    // 4. Atomically decrement stock as FieldValue.increment deltas
    // If two devices sell offline, the server sums both decrements!
    for (final item in queuedSale.sale.lineItems) {
      final productRef = db.collection('products').doc(item.productId);
      batch.update(productRef, {
        'quantity_on_hand': FieldValue.increment(-item.quantity),
      });
    }

    await batch.commit().timeout(const Duration(seconds: 15));
  }

  Future<List<FailedSaleRecord>> getFailedSales() async {
    final list = await _storage.getNeedsReviewSales();
    return list.map((q) => q.toFailedSaleRecord()).toList();
  }

  Future<void> retryFailedSale(FailedSaleRecord record) async {
    final needsReview = await _storage.getNeedsReviewSales();
    final matching =
        needsReview.where((q) => q.sale.id == record.sale.id).toList();

    if (matching.isNotEmpty) {
      final item = matching.first;
      await _storage.removeNeedsReview(item.sale.id);
      // Reset retry count to 0 and re-queue in pending
      await _storage.savePending(item.copyWith(
        retryCount: 0,
        lastAttemptAt: null,
        lastError: null,
      ));
    } else {
      await _storage.savePending(QueuedSale(
        sale: record.sale,
        includeCostSnapshot: true,
        queuedAt: DateTime.now(),
      ));
    }

    _pendingCount = await _storage.getPendingCount();
    _notifyStatus();

    if (_isOnline) {
      await drainQueue();
    }
  }

  Future<void> cacheProducts(List<Product> products) async {
    await _storage.cacheProducts(products);
  }

  Future<List<Product>> getCachedProducts() async {
    return _storage.getCachedProducts();
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _statusController.close();
  }
}
