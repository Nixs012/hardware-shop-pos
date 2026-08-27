import 'sale_line_item.dart';

class Sale {
  final String id; // client UUID
  final DateTime timestamp;
  final String staffId;
  final String paymentMethod;
  final List<SaleLineItem> lineItems;

  Sale({
    required this.id,
    required this.timestamp,
    required this.staffId,
    required this.paymentMethod,
    required this.lineItems,
  });

  double get totalAmount => lineItems.fold(0, (sum, item) => sum + (item.unitPriceAtSale * item.quantity));

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'staff_id': staffId,
      'payment_method': paymentMethod,
      'line_items': lineItems.map((x) => x.toMap()).toList(),
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map, String id) {
    return Sale(
      id: id,
      timestamp: map['timestamp'] != null ? DateTime.parse(map['timestamp']) : DateTime.now(),
      staffId: map['staff_id'] ?? '',
      paymentMethod: map['payment_method'] ?? '',
      lineItems: List<SaleLineItem>.from(
        (map['line_items'] as List? ?? []).map((x) => SaleLineItem.fromMap(x)),
      ),
    );
  }
}
