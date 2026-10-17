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

  double get totalAmount => lineItems.fold(
        0.0,
        (sum, item) => sum + (item.unitPriceAtSale * item.quantity),
      );

  double get totalCost => lineItems.fold(
        0.0,
        (sum, item) => sum + (item.unitCostAtSale * item.quantity),
      );

  double get totalProfit => totalAmount - totalCost;

  /// Public sale format for /sales collection (no cost data)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'staff_id': staffId,
      'payment_method': paymentMethod,
      'line_items': lineItems.map((x) => x.toMap()).toList(),
    };
  }

  /// Admin-only cost format for /sales_costs collection
  Map<String, dynamic> toCostMap() {
    return {
      'sale_id': id,
      'timestamp': timestamp.toIso8601String(),
      'staff_id': staffId,
      'payment_method': paymentMethod,
      'line_items': lineItems.map((x) => x.toCostMap()).toList(),
      'total_cost': totalCost,
      'total_amount': totalAmount,
    };
  }

  factory Sale.fromMap(
    Map<String, dynamic> map,
    String id, [
    Map<String, dynamic>? costMap,
  ]) {
    final rawLineItems = (map['line_items'] as List? ?? []);
    final costLineItems = (costMap?['line_items'] as List? ?? []);

    final items = <SaleLineItem>[];
    for (int i = 0; i < rawLineItems.length; i++) {
      final rawItem = Map<String, dynamic>.from(rawLineItems[i] as Map);
      Map<String, dynamic>? matchedCost;

      if (i < costLineItems.length) {
        matchedCost = Map<String, dynamic>.from(costLineItems[i] as Map);
      } else {
        final found = costLineItems.where(
          (c) => (c as Map)['product_id'] == rawItem['product_id'],
        );
        if (found.isNotEmpty) {
          matchedCost = Map<String, dynamic>.from(found.first as Map);
        }
      }

      items.add(SaleLineItem.fromMap(rawItem, matchedCost));
    }

    return Sale(
      id: id,
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : DateTime.now(),
      staffId: map['staff_id'] ?? '',
      paymentMethod: map['payment_method'] ?? '',
      lineItems: items,
    );
  }
}
