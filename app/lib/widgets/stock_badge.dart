import 'package:flutter/material.dart';
import '../utils/theme.dart';

class StockBadge extends StatelessWidget {
  final int quantityOnHand;
  final int lowStockThreshold;

  const StockBadge({
    super.key,
    required this.quantityOnHand,
    required this.lowStockThreshold,
  });

  bool get isLowStock =>
      quantityOnHand <= lowStockThreshold && quantityOnHand > 0;
  bool get isOutOfStock => quantityOnHand <= 0;
  bool get isAdequate => quantityOnHand > lowStockThreshold;

  Color get _color {
    if (isOutOfStock) return AppTheme.errorColor;
    if (isLowStock) return AppTheme.warningColor;
    return AppTheme.successColor;
  }

  String get _label {
    if (isOutOfStock) return 'Out of Stock';
    if (isLowStock) return 'Low Stock';
    return 'In Stock';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: _color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _color),
          ),
          const SizedBox(width: 4),
          Text(
            _label,
            style: TextStyle(
              color: _color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}



