import 'package:flutter_test/flutter_test.dart';
import 'package:app/models/product.dart';
import 'package:app/models/queued_sale.dart';
import 'package:app/models/sale.dart';
import 'package:app/models/sale_line_item.dart';
import 'package:app/services/sync_service.dart';

void main() {
  group('Phase 3 - Offline-First Sync Queue & Duplicate Handling Tests', () {
    late MemorySyncStorage storage;

    setUp(() {
      storage = MemorySyncStorage();
    });

    Sale createTestSale({
      required String id,
      DateTime? timestamp,
      String staffId = 'staff-01',
      String paymentMethod = 'Cash',
      List<SaleLineItem>? lineItems,
    }) {
      return Sale(
        id: id,
        timestamp: timestamp ?? DateTime(2026, 10, 18, 10, 0),
        staffId: staffId,
        paymentMethod: paymentMethod,
        lineItems: lineItems ??
            [
              SaleLineItem(
                productId: 'prod-cement',
                quantity: 2.0,
                unitPriceAtSale: 750.0,
                unitCostAtSale: 650.0,
              ),
            ],
      );
    }

    test('QueuedSale preserves client UUID and cost snapshots across serialization', () {
      final sale = createTestSale(id: 'client-uuid-999');
      final queuedSale = QueuedSale(
        sale: sale,
        includeCostSnapshot: true,
        retryCount: 2,
        queuedAt: DateTime(2026, 10, 18, 10, 5),
        lastAttemptAt: DateTime(2026, 10, 18, 10, 6),
        lastError: 'Network unreachable',
      );

      final map = queuedSale.toMap();
      final restored = QueuedSale.fromMap(map);

      expect(restored.sale.id, equals('client-uuid-999'));
      expect(restored.includeCostSnapshot, isTrue);
      expect(restored.retryCount, equals(2));
      expect(restored.lastError, equals('Network unreachable'));
      expect(restored.sale.lineItems.first.unitCostAtSale, equals(650.0));
      expect(restored.sale.totalAmount, equals(1500.0));
    });

    test('Queueing a sale stores it in pending with client UUID and decrements cached stock', () async {
      final product = Product(
        id: 'prod-cement',
        name: 'Cement 50kg',
        sku: 'CEM-01',
        category: 'Building',
        sellingPrice: 750.0,
        quantityOnHand: 20.0,
        unit: 'bag',
      );
      await storage.cacheProducts([product]);

      final syncService = SyncService.custom(
        storage: storage,
        initialOnline: false,
      );

      final sale = createTestSale(id: 'client-uuid-101');
      await syncService.queueSale(sale, includeCostSnapshot: true);

      // Verify pending queue has exactly 1 sale with matching UUID
      final pending = await storage.getPendingSales();
      expect(pending.length, equals(1));
      expect(pending.first.sale.id, equals('client-uuid-101'));
      expect(syncService.pendingCount, equals(1));

      // Verify local product stock was optimistically decremented from 20 to 18
      final cachedProducts = await storage.getCachedProducts();
      final updatedProduct =
          cachedProducts.firstWhere((p) => p.id == 'prod-cement');
      expect(updatedProduct.quantityOnHand, equals(18.0));
    });

    test('Online draining executes sync callback and removes sale from pending queue', () async {
      final syncedSales = <String>[];
      final syncService = SyncService.custom(
        storage: storage,
        initialOnline: true,
        syncSale: (queuedSale, [String shopId = '']) async {
          syncedSales.add(queuedSale.sale.id);
        },
      );

      final sale = createTestSale(id: 'client-uuid-202');
      await syncService.queueSale(sale);
      await syncService.drainQueue();

      expect(syncedSales, contains('client-uuid-202'));
      expect(await storage.getPendingCount(), equals(0));
      expect(syncService.pendingCount, equals(0));
    });

    test('Idempotency & Duplicate Prevention: Retried sale with same UUID is not duplicated', () async {
      final serverDatabase = <String, Sale>{};
      int serverWriteAttempts = 0;

      Future<void> mockServerSync(QueuedSale queuedSale, [String? shopId]) async {
        serverWriteAttempts++;
        final saleId = queuedSale.sale.id;

        // Idempotency check matching FirestoreService implementation
        if (serverDatabase.containsKey(saleId)) {
          // Already recorded on server: Return without re-inserting or double-decrementing
          return;
        }

        serverDatabase[saleId] = queuedSale.sale;
      }

      final syncService = SyncService.custom(
        storage: storage,
        initialOnline: false,
        syncSale: mockServerSync,
      );

      final sale = createTestSale(id: 'unique-sale-uuid-777');

      // First queue and manual drain
      await syncService.queueSale(sale);
      syncService.setOnlineForTesting(true);
      await syncService.drainQueue();

      expect(serverDatabase.containsKey('unique-sale-uuid-777'), isTrue);
      expect(serverWriteAttempts, equals(1));

      // Simulate a network timeout scenario where client re-submits the same queued sale
      await storage.savePending(QueuedSale(
        sale: sale,
        queuedAt: DateTime.now(),
      ));
      await syncService.drainQueue();

      // Ensure server still only has 1 record and duplicate was avoided
      expect(serverDatabase.length, equals(1));
      expect(serverWriteAttempts, equals(2));
      expect(await storage.getPendingCount(), equals(0));
    });

    test('Exponential backoff calculation produces exponential delays capped at 120s', () {
      final syncService = SyncService.custom(storage: storage);

      expect(syncService.calculateBackoff(0), equals(Duration.zero));
      expect(syncService.calculateBackoff(1), equals(const Duration(seconds: 2)));
      expect(syncService.calculateBackoff(2), equals(const Duration(seconds: 4)));
      expect(syncService.calculateBackoff(3), equals(const Duration(seconds: 8)));
      expect(syncService.calculateBackoff(4), equals(const Duration(seconds: 16)));
      expect(syncService.calculateBackoff(5), equals(const Duration(seconds: 32)));
      expect(syncService.calculateBackoff(6), equals(const Duration(seconds: 64)));
      expect(syncService.calculateBackoff(7), equals(const Duration(seconds: 120))); // capped
    });

    test('Unrecoverable failure moves sale to Needs Review after max retries and never deletes it', () async {
      int syncAttempts = 0;
      final syncService = SyncService.custom(
        storage: storage,
        initialOnline: true,
        syncSale: (queuedSale, [String shopId = '']) async {
          syncAttempts++;
          throw Exception('Simulated permanent sync error');
        },
      );

      final sale = createTestSale(id: 'failing-sale-555');

      // First attempt during queueSale
      await syncService.queueSale(sale);
      expect(syncAttempts, equals(1));

      // Attempt retries until reaching maxRetries (5)
      for (int i = 0; i < 4; i++) {
        // Fast-forward backoff timestamp to allow retry
        final pending = await storage.getPendingSales();
        if (pending.isNotEmpty) {
          await storage.savePending(pending.first.copyWith(
            lastAttemptAt: DateTime.now().subtract(const Duration(minutes: 5)),
          ));
        }
        await syncService.drainQueue();
      }

      // After 5 attempts, sale must be removed from pending and moved to Needs Review
      expect(syncAttempts, equals(5));
      expect(await storage.getPendingCount(), equals(0));

      final needsReview = await storage.getNeedsReviewSales();
      expect(needsReview.length, equals(1));
      expect(needsReview.first.sale.id, equals('failing-sale-555'));
      expect(needsReview.first.retryCount, equals(5));
      expect(needsReview.first.lastError, contains('Simulated permanent sync error'));

      // Verify getFailedSales exposes this for admin UI
      final failedRecords = await syncService.getFailedSales();
      expect(failedRecords.length, equals(1));
      expect(failedRecords.first.sale.id, equals('failing-sale-555'));
    });

    test('Admin retry of Needs Review sale moves it back to pending and allows sync', () async {
      bool shouldSucceed = false;
      final syncService = SyncService.custom(
        storage: storage,
        initialOnline: true,
        syncSale: (queuedSale, [String shopId = '']) async {
          if (!shouldSucceed) {
            throw Exception('Initial failure');
          }
        },
      );

      final sale = createTestSale(id: 'review-sale-333');
      await storage.saveNeedsReview(QueuedSale(
        sale: sale,
        retryCount: 5,
        queuedAt: DateTime.now(),
        lastError: 'Simulated failure',
      ));

      expect((await storage.getNeedsReviewSales()).length, equals(1));

      // Admin triggers retry after fixing the issue
      shouldSucceed = true;
      final failedRecords = await syncService.getFailedSales();
      await syncService.retryFailedSale(failedRecords.first);

      // Verify sale was successfully removed from Needs Review and synced
      expect(await storage.getNeedsReviewSales(), isEmpty);
      expect(await storage.getPendingCount(), equals(0));
    });

    test('Pending sales are drained in FIFO order', () async {
      final processedOrder = <String>[];
      final syncService = SyncService.custom(
        storage: storage,
        initialOnline: false,
        syncSale: (queuedSale, [String shopId = '']) async {
          processedOrder.add(queuedSale.sale.id);
        },
      );

      final sale1 = createTestSale(
        id: 'sale-first',
        timestamp: DateTime(2026, 10, 18, 9, 0),
      );
      final sale2 = createTestSale(
        id: 'sale-second',
        timestamp: DateTime(2026, 10, 18, 9, 5),
      );
      final sale3 = createTestSale(
        id: 'sale-third',
        timestamp: DateTime(2026, 10, 18, 9, 10),
      );

      await syncService.queueSale(sale1);
      await syncService.queueSale(sale2);
      await syncService.queueSale(sale3);

      syncService.setOnlineForTesting(true);
      await syncService.drainQueue();

      expect(processedOrder, equals(['sale-first', 'sale-second', 'sale-third']));
    });
  });
}
