import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/sale.dart';
import 'sync_service.dart';

/// Service that handles CSV import and export of products and sales.
///
/// Uses `file_picker` on mobile/desktop to read and write files. On the web,
/// it falls back to a text area copy-paste mechanism (the user pastes CSV
/// text and receives exported CSV text back).
class CsvExportService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _uuid = Uuid();
  static final CsvEncoder _encoder = CsvEncoder();
  static final CsvDecoder _decoder = CsvDecoder();

  // ---------------------------------------------------------------------------
  // Product Import
  // ---------------------------------------------------------------------------

  /// Picks a CSV file and imports products from it.
  ///
  /// Expected CSV header:
  /// name,sku,category,selling_price,quantity_on_hand,low_stock_threshold,unit,cost_price
  ///
  /// Returns the number of products successfully imported and a list of error
  /// messages for rows that failed.
  Future<ImportResult> importProductsFromCsv() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (picked.isEmpty) {
      return ImportResult(0, []);
    }

    final file = picked.first;
    final bytes = await file.readAsBytes();

    final csvString = utf8.decode(bytes);
    return _parseAndImportProducts(csvString);
  }

  /// Parses CSV text and imports products.
  ///
  /// This is also usable when the user pastes CSV text on the web.
  Future<ImportResult> importProductsFromText(String csvText) async {
    return _parseAndImportProducts(csvText);
  }

  Future<ImportResult> _parseAndImportProducts(String csvText) async {
    final rows = _decoder.convert(csvText);

    if (rows.isEmpty) {
      return ImportResult(0, ['The CSV file is empty.']);
    }

    // First row is the header
    final header = rows.first
        .map((c) => c.toString().toLowerCase().trim())
        .toList();
    final hasRequiredColumns =
        header.contains('name') &&
        header.contains('sku') &&
        header.contains('selling_price');
    if (!hasRequiredColumns) {
      return ImportResult(0, [
        'CSV must have at least these columns: Name, SKU, Selling Price.',
      ]);
    }

    // Build a column-index map for flexible column ordering
    final colMap = <String, int>{};
    for (int i = 0; i < header.length; i++) {
      colMap[header[i]] = i;
    }

    final products = <Product>[];
    final errors = <String>[];
    var imported = 0;

    for (int rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.length < 3) continue; // skip blank or too-short rows

      try {
        final name = _getCell(row, colMap, 'name');
        final sku = _getCell(row, colMap, 'sku');
        final category = _getCell(row, colMap, 'category');
        final sellingPriceStr = _getCell(row, colMap, 'selling_price');
        final costPriceStr = _getCell(row, colMap, 'cost_price');
        final quantityStr = _getCell(row, colMap, 'quantity_on_hand');
        final lowStockStr = _getCell(row, colMap, 'low_stock_threshold');
        final unit = _getCell(row, colMap, 'unit');

        if (name.isEmpty || sku.isEmpty || sellingPriceStr.isEmpty) {
          errors.add(
            'Row ${rowIndex + 1}: Missing required fields (name, sku, or selling_price).',
          );
          continue;
        }

        final product = Product(
          id: _uuid.v4(),
          name: name,
          sku: sku,
          category: category.isNotEmpty ? category : 'Uncategorized',
          sellingPrice: double.tryParse(sellingPriceStr) ?? 0.0,
          quantityOnHand: double.tryParse(quantityStr) ?? 0.0,
          lowStockThreshold: double.tryParse(lowStockStr) ?? 5.0,
          unit: unit.isNotEmpty ? unit : 'piece',
          costPrice: double.tryParse(costPriceStr) ?? 0.0,
        );

        products.add(product);
        imported++;
      } catch (e) {
        errors.add('Row ${rowIndex + 1}: ${e.toString()}');
      }
    }

    // Batch-write all products using FirestoreService's addProduct
    final writeBatch = _db.batch();
    for (final p in products) {
      final docRef = _db.collection('products').doc(p.id);
      writeBatch.set(docRef, p.toMap());
      writeBatch.set(
        _db.collection('product_costs').doc(p.id),
        p.toCostMap(),
        SetOptions(merge: true),
      );
    }
    await writeBatch.commit();

    // Also cache locally so offline devices see the imported products
    await SyncService.instance.cacheProducts(products, isAdmin: true);

    return ImportResult(imported, errors);
  }

  String _getCell(List<dynamic> row, Map<String, int> colMap, String column) {
    final idx = colMap[column];
    if (idx == null || idx >= row.length) return '';
    return row[idx].toString().trim();
  }

  // ---------------------------------------------------------------------------
  // Sales Export
  // ---------------------------------------------------------------------------

  /// Exports all sales to a CSV file. On mobile/desktop the file is saved to
  /// the device's Downloads / Documents folder. On the web the CSV text is
  /// returned so the caller can display it to the user.
  ///
  /// Returns the CSV content as a string (useful for web copy-paste).
  Future<String> exportSalesToCsv({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final sales = await _fetchSales(startDate: startDate, endDate: endDate);
    final productMap = await _fetchProductMap();
    final rows = _salesToRows(sales, productMap);
    final csv = _encoder.convert(rows);

    if (kIsWeb) {
      // On web, the caller handles the CSV text
      return csv;
    } else {
      // On mobile/desktop, write to a file
      final result = await FilePicker.saveFile(
        dialogTitle: 'Export Sales',
        fileName: 'sales_export_${_timestamp()}.csv',
        bytes: utf8.encode(csv),
        mimeType: 'text/csv',
      );

      if (result == null) {
        return '';
      }
    }

    return csv;
  }

  Future<Map<String, Product>> _fetchProductMap() async {
    final snap = await _db.collection('products').get();
    final map = <String, Product>{};
    for (final doc in snap.docs) {
      map[doc.id] = Product.fromMap(doc.data(), doc.id);
    }
    return map;
  }

  Future<List<Sale>> _fetchSales({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('sales')
        .orderBy('timestamp');

    if (startDate != null) {
      query = query.where('timestamp', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('timestamp', isLessThanOrEqualTo: endDate);
    }

    final snap = await query.get();
    return snap.docs.map((doc) => Sale.fromMap(doc.data(), doc.id)).toList();
  }

  List<List<dynamic>> _salesToRows(
    List<Sale> sales,
    Map<String, Product> productMap,
  ) {
    final rows = <List<dynamic>>[];

    // Header
    rows.add([
      'Receipt ID',
      'Date',
      'Staff',
      'Payment Method',
      'Customer Name',
      'Customer Phone',
      'Item Name',
      'SKU',
      'Category',
      'Unit Price',
      'Quantity',
      'Line Total',
      'Subtotal',
      'Discount',
      'Total Amount',
      'Total Cost',
      'Total Profit',
    ]);

    for (final sale in sales) {
      final dateStr = _formatExportDate(sale.timestamp);
      final subtotalStr = sale.totalAmount.toStringAsFixed(2);
      final discountStr = '0.00';
      if (sale.lineItems.isEmpty) {
        rows.add([
          sale.id,
          dateStr,
          sale.staffId,
          sale.paymentMethod,
          sale.customerName ?? '',
          sale.customerPhone ?? '',
          '',
          '',
          '',
          '',
          '',
          '',
          subtotalStr,
          discountStr,
          subtotalStr,
          sale.totalCost.toStringAsFixed(2),
          sale.totalProfit.toStringAsFixed(2),
        ]);
      } else {
        var firstItem = true;
        for (final item in sale.lineItems) {
          final product = productMap[item.productId];
          rows.add([
            sale.id,
            dateStr,
            sale.staffId,
            sale.paymentMethod,
            sale.customerName ?? '',
            sale.customerPhone ?? '',
            product?.name ?? item.productId,
            product?.sku ?? '',
            product?.category ?? '',
            item.unitPriceAtSale.toStringAsFixed(2),
            item.quantity.toString(),
            (item.unitPriceAtSale * item.quantity).toStringAsFixed(2),
            // Subtotal/Discount/Total only on first line
            firstItem ? subtotalStr : '',
            firstItem ? discountStr : '',
            firstItem ? subtotalStr : '',
            firstItem ? sale.totalCost.toStringAsFixed(2) : '',
            firstItem ? sale.totalProfit.toStringAsFixed(2) : '',
          ]);
          firstItem = false;
        }
      }
    }

    return rows;
  }

  String _formatExportDate(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year  $hour:$minute';
  }

  String _timestamp() {
    final now = DateTime.now().toLocal();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
  }
}

/// Result of a CSV import operation.
class ImportResult {
  final int imported;
  final List<String> errors;

  ImportResult(this.imported, this.errors);

  bool get hasErrors => errors.isNotEmpty;
}
