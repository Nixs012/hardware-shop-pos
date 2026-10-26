import 'package:flutter/material.dart';
import '../models/product.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';
import 'stock_badge.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback? onTap;
  final bool showCategory;
  final bool showCostPrice;
  final bool compact;

  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.showCategory = true,
    this.showCostPrice = false,
    this.compact = false,
  });

  bool get isOutOfStock => product.quantityOnHand <= 0;
  bool get isLowStock =>
      product.quantityOnHand <= product.lowStockThreshold &&
      product.quantityOnHand > 0;

  Color get _borderColor {
    if (isOutOfStock) return AppTheme.errorColor;
    if (isLowStock) return AppTheme.warningColor;
    return AppTheme.borderColor;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.cardBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: _borderColor, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : AppTheme.sp12),
          child: compact ? _buildCompact() : _buildRegular(),
        ),
      ),
    );
  }

  Widget _buildRegular() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: category chip + stock badge
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (showCategory && product.category.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.elevatedBackground,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  border: Border.all(color: AppTheme.borderColor, width: 1),
                ),
                child: Text(
                  product.category,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            StockBadge(
              quantityOnHand: product.quantityOnHand.toInt(),
              lowStockThreshold: product.lowStockThreshold.toInt(),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.sp8),
        // Product name
        Text(
          product.name,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (product.sku.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            'SKU: ${product.sku}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const Spacer(),
        // Price row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              CurrencyFormatter.format(product.sellingPrice),
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (showCostPrice && product.costPrice > 0)
              Text(
                'Cost: ${CurrencyFormatter.format(product.costPrice)}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        // Stock level
        Text(
          '${product.quantityOnHand.toInt()} ${product.unit} on hand',
          style: TextStyle(
            color: isOutOfStock
                ? AppTheme.errorColor
                : isLowStock
                    ? AppTheme.warningColor
                    : AppTheme.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildCompact() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name
        Text(
          product.name,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Price
        Text(
          CurrencyFormatter.format(product.sellingPrice),
          style: const TextStyle(
            color: AppTheme.primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        // Stock
        Text(
          '${product.quantityOnHand.toInt()} ${product.unit}',
          style: TextStyle(
            color: isOutOfStock
                ? AppTheme.errorColor
                : isLowStock
                    ? AppTheme.warningColor
                    : AppTheme.textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}



