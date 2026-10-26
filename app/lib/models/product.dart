class Product {
  final String id;
  final String name;
  final String sku;
  final String category;
  final double costPrice; // required for profit calculations, restricted to admin
  final double sellingPrice;
  final double quantityOnHand;
  final double lowStockThreshold;
  final String unit;
  final bool costPriceEstimated;

  Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.category,
    this.costPrice = 0.0,
    required this.sellingPrice,
    required this.quantityOnHand,
    this.lowStockThreshold = 5,
    required this.unit,
    this.costPriceEstimated = false,
  });

  /// Serializes public product fields (without cost data) for /products collection
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'sku': sku,
      'category': category,
      'selling_price': sellingPrice,
      'quantity_on_hand': quantityOnHand,
      'low_stock_threshold': lowStockThreshold,
      'unit': unit,
    };
  }

  /// Serializes cost data for admin-only /product_costs collection
  Map<String, dynamic> toCostMap() {
    return {
      'product_id': id,
      'cost_price': costPrice,
      'cost_price_estimated': costPriceEstimated,
    };
  }

  factory Product.fromMap(
    Map<String, dynamic> map,
    String id, [
    Map<String, dynamic>? costMap,
  ]) {
    final effectiveCost = costMap != null
        ? (costMap['cost_price'] ?? 0.0).toDouble()
        : (map['cost_price'] ?? 0.0).toDouble();
    final effectiveEstimated = costMap != null
        ? (costMap['cost_price_estimated'] ?? false)
        : (map['cost_price_estimated'] ?? false);

    return Product(
      id: id,
      name: map['name'] ?? '',
      sku: map['sku'] ?? '',
      category: map['category'] ?? '',
      costPrice: effectiveCost,
      sellingPrice: (map['selling_price'] ?? 0.0).toDouble(),
      quantityOnHand: (map['quantity_on_hand'] ?? 0).toDouble(),
      lowStockThreshold: (map['low_stock_threshold'] ?? 5).toDouble(),
      unit: map['unit'] ?? 'piece',
      costPriceEstimated: effectiveEstimated,
    );
  }
}



