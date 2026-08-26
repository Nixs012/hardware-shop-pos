import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/sale.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> addProduct(Product product) {
    return _db.collection('products').doc(product.id).set(product.toMap());
  }

  Future<void> addSale(Sale sale) {
    return _db.collection('sales').doc(sale.id).set(sale.toMap());
  }
}
