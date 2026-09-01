import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';
import 'dart:convert';

import '../models/failed_sale.dart';
import '../models/product.dart';
import '../models/sale.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _failedSalesKey = 'failed_sales_needs_review';

  Future<void> addProduct(Product product) {
    return _db.collection('products').doc(product.id).set(product.toMap());
  }

  Future<void> updateProduct(Product product) {
    return _db.collection('products').doc(product.id).update(product.toMap());
  }

  Stream<List<Product>> getProductsStream() {
    return _db.collection('products').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Product.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> processSale(Sale sale) async {
    final batch = _db.batch();

    // Add sale document
    final saleRef = _db.collection('sales').doc(sale.id);
    batch.set(saleRef, sale.toMap());

    // Atomically decrement stock for each line item
    for (final item in sale.lineItems) {
      final productRef = _db.collection('products').doc(item.productId);
      batch.update(productRef, {
        'quantity_on_hand': FieldValue.increment(-item.quantity),
      });
    }

    debugPrint('[Firestore] Queueing sale batch for local commit: ${sale.id}');
    unawaited(
      batch
          .commit()
          .then((_) {
            debugPrint('[Firestore] Sale batch commit completed: ${sale.id}');
          })
          .catchError((Object error, StackTrace stackTrace) {
            debugPrint('[Firestore] Sale batch sync failed: $error');
            debugPrint('[Firestore] Sale batch sync stack trace: $stackTrace');
            unawaited(_saveFailedSale(sale, error.toString()));
          }),
    );
    debugPrint('[Firestore] Sale batch queued locally: ${sale.id}');
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
        } catch (error, stackTrace) {
          debugPrint(
            '[Firestore] Ignoring corrupted failed-sale record: $error',
          );
          debugPrint('[Firestore] Corrupted record stack trace: $stackTrace');
        }
      }
      records.sort((a, b) => b.failedAt.compareTo(a.failedAt));
      return records;
    } catch (error, stackTrace) {
      debugPrint('[Firestore] Failed-sale storage is corrupted: $error');
      debugPrint('[Firestore] Failed-sale storage stack trace: $stackTrace');
      return [];
    }
  }

  Future<void> retryFailedSale(FailedSaleRecord record) async {
    final batch = _db.batch();
    batch.set(_db.collection('sales').doc(record.sale.id), record.sale.toMap());
    for (final item in record.sale.lineItems) {
      batch.update(_db.collection('products').doc(item.productId), {
        'quantity_on_hand': FieldValue.increment(-item.quantity),
      });
    }

    try {
      await batch.commit().timeout(const Duration(seconds: 10));
      await _removeFailedSale(record.sale.id);
      debugPrint('[Firestore] Failed sale retry succeeded: ${record.sale.id}');
    } catch (error, stackTrace) {
      await _saveFailedSale(record.sale, error.toString());
      debugPrint('[Firestore] Failed sale retry failed: $error');
      debugPrint('[Firestore] Failed sale retry stack trace: $stackTrace');
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
      debugPrint('[Firestore] Failed sale saved for Needs Review: ${sale.id}');
    } catch (error, stackTrace) {
      debugPrint(
        '[Firestore] Could not persist failed sale ${sale.id}: $error',
      );
      debugPrint(
        '[Firestore] Failed-sale persistence stack trace: $stackTrace',
      );
    }
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
    } catch (error, stackTrace) {
      debugPrint('[Firestore] Resetting corrupted failed-sale map: $error');
      debugPrint('[Firestore] Failed-sale map stack trace: $stackTrace');
      return {};
    }
  }

  Stream<List<Sale>> getSalesStream() {
    return _db
        .collection('sales')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => Sale.fromMap(doc.data(), doc.id))
              .toList();
        });
  }
}
