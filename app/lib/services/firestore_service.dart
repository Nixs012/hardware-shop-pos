import 'package:cloud_firestore/cloud_firestore.dart';
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
