class SaleLineItem {
  final String productId;
  final double quantity;
  final double unitPriceAtSale;
  final double unitCostAtSale;

  SaleLineItem({
    required this.productId,
    required this.quantity,
    required this.unitPriceAtSale,
    this.unitCostAtSale = 0.0,
  });

  /// Public line item format for /sales collection (no cost data)
  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'quantity': quantity,
      'unit_price_at_sale': unitPriceAtSale,
    };
  }

  /// Admin-only line item format for /sales_costs collection (includes cost snapshot)
  Map<String, dynamic> toCostMap() {
    return {
      'product_id': productId,
      'quantity': quantity,
      'unit_price_at_sale': unitPriceAtSale,
      'unit_cost_at_sale': unitCostAtSale,
    };
  }

  factory SaleLineItem.fromMap(
    Map<String, dynamic> map, [
    Map<String, dynamic>? costMap,
  ]) {
    final effectiveCost = costMap != null
        ? (costMap['unit_cost_at_sale'] ?? 0.0).toDouble()
        : (map['unit_cost_at_sale'] ?? 0.0).toDouble();

    return SaleLineItem(
      productId: map['product_id'] ?? '',
      quantity: (map['quantity'] ?? 0).toDouble(),
      unitPriceAtSale: (map['unit_price_at_sale'] ?? 0.0).toDouble(),
      unitCostAtSale: effectiveCost,
    );
  }

  double get profit => (unitPriceAtSale - unitCostAtSale) * quantity;
}



