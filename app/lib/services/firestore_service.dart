import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/sale.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> addProduct(Product product) {
    return _db.collection('products').doc(product.id).set(product.toMap());
  }

  Future<void> updateProduct(Product product) {
    return _db.collection('products').doc(product.id).update(product.toMap());
  }

  Stream<List<Product>> getProductsStream() {
    return _db.collection('products').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Product.fromMap(doc.data(), doc.id)).toList();
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

    await batch.commit();
  }

  Stream<List<Sale>> getSalesStream() {
    return _db.collection('sales').orderBy('timestamp', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Sale.fromMap(doc.data(), doc.id)).toList();
    });
  }
}
