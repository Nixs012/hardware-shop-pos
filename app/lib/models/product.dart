class Product {
  final String id;
  final String name;
  final String sku;
  final String category;
  final double costPrice; // required
  final double sellingPrice;
  final int quantityOnHand;
  final int lowStockThreshold;
  final String unit;
  final bool costPriceEstimated;

  Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.category,
    required this.costPrice,
    required this.sellingPrice,
    required this.quantityOnHand,
    this.lowStockThreshold = 5,
    required this.unit,
    this.costPriceEstimated = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'sku': sku,
      'category': category,
      'cost_price': costPrice,
      'selling_price': sellingPrice,
      'quantity_on_hand': quantityOnHand,
      'low_stock_threshold': lowStockThreshold,
      'unit': unit,
      'cost_price_estimated': costPriceEstimated,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map, String id) {
    return Product(
      id: id,
      name: map['name'] ?? '',
      sku: map['sku'] ?? '',
      category: map['category'] ?? '',
      costPrice: (map['cost_price'] ?? 0.0).toDouble(),
      sellingPrice: (map['selling_price'] ?? 0.0).toDouble(),
      quantityOnHand: map['quantity_on_hand']?.toInt() ?? 0,
      lowStockThreshold: map['low_stock_threshold']?.toInt() ?? 5,
      unit: map['unit'] ?? 'piece',
      costPriceEstimated: map['cost_price_estimated'] ?? false,
    );
  }
}
