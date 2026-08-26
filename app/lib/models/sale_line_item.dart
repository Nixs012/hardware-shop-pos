class SaleLineItem {
  final String productId;
  final double quantity;
  final double unitPriceAtSale;
  final double unitCostAtSale;

  SaleLineItem({
    required this.productId,
    required this.quantity,
    required this.unitPriceAtSale,
    required this.unitCostAtSale,
  });

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'quantity': quantity,
      'unit_price_at_sale': unitPriceAtSale,
      'unit_cost_at_sale': unitCostAtSale,
    };
  }

  factory SaleLineItem.fromMap(Map<String, dynamic> map) {
    return SaleLineItem(
      productId: map['product_id'] ?? '',
      quantity: (map['quantity'] ?? 0).toDouble(),
      unitPriceAtSale: (map['unit_price_at_sale'] ?? 0.0).toDouble(),
      unitCostAtSale: (map['unit_cost_at_sale'] ?? 0.0).toDouble(),
    );
  }
  
  double get profit => (unitPriceAtSale - unitCostAtSale) * quantity;
}
