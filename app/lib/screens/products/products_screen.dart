import 'package:flutter/material.dart';

import '../../models/staff.dart';
import '../../models/product.dart';
import '../../services/firestore_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/theme.dart';
import '../../widgets/error_display_widgets.dart';
import 'product_form_screen.dart';

class ProductsScreen extends StatefulWidget {
  final Staff currentStaff;
  final FirestoreService? firestoreService;

  const ProductsScreen({super.key, required this.currentStaff, this.firestoreService});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  FirestoreService? _injectedFirestoreService;
  final _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedCategory = 'All';
  bool _onlyLowStock = false;

  bool get _isAdmin => widget.currentStaff.role.toLowerCase() == 'admin';

  FirestoreService get _firestoreService =>
      _injectedFirestoreService ??= widget.firestoreService ??
          FirestoreServiceImpl(widget.currentStaff.shopId);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: StreamBuilder<List<Product>>(
        stream: _firestoreService.getProductsStream(isAdmin: _isAdmin),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorDisplayWidget(
              error: snapshot.error,
              stackTrace: snapshot.stackTrace,
              onRetry: () => setState(() {}),
              fallbackMessage: 'Error loading products',
            );
          }

          final allProducts = snapshot.data ?? [];

          // Extract unique categories
          final categories = <String>{'All'};
          for (final p in allProducts) {
            if (p.category.isNotEmpty) {
              categories.add(p.category);
            }
          }

          // Filter products
          final filtered = allProducts.where((p) {
            final matchesQuery = _searchQuery.isEmpty ||
                p.name.toLowerCase().contains(_searchQuery) ||
                p.sku.toLowerCase().contains(_searchQuery);
            final matchesCategory = _selectedCategory == 'All' ||
                p.category.toLowerCase() == _selectedCategory.toLowerCase();
            final matchesLowStock =
                !_onlyLowStock || (p.quantityOnHand <= p.lowStockThreshold);

            return matchesQuery && matchesCategory && matchesLowStock;
          }).toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 800;

              return Column(
                children: [
                  _buildToolbar(categories.toList(), isDesktop),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No products match your search/filter.',
                              style: TextStyle(
                                color: AppTheme.secondaryColor,
                                fontSize: 16,
                              ),
                            ),
                          )
                        : isDesktop
                            ? _buildDesktopTable(filtered)
                            : _buildMobileList(filtered),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.primaryColor,
               onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ProductFormScreen(firestoreService: _firestoreService)),
                );
              },
              icon: const Icon(Icons.add, color: AppTheme.textPrimary),
              label: const Text('Add Product', style: TextStyle(color: AppTheme.textPrimary)),
            )
          : null,
    );
  }

  Widget _buildToolbar(List<String> categories, bool isDesktop) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 24 : 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderColor),
        ),
      ),
      child: isDesktop
          ? Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search products by name or SKU...',
                      hintStyle:
                          const TextStyle(color: AppTheme.secondaryColor),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppTheme.secondaryColor,
                        size: 20,
                      ),
                      isDense: true,
                      filled: true,
                       fillColor: AppTheme.cardBackground,
                       border: OutlineInputBorder(
                         borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                         borderSide: BorderSide.none,
                       ),
                     ),
                   ),
                 ),
                 const SizedBox(width: 16),
                 Container(
                   padding: const EdgeInsets.symmetric(horizontal: AppTheme.sp12),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: categories.contains(_selectedCategory)
                          ? _selectedCategory
                          : 'All',
                      dropdownColor: AppTheme.backgroundColor,
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      items: categories.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Text(cat == 'All' ? 'All Categories' : cat),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCategory = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                FilterChip(
                  label: const Text('Low Stock Only'),
                  selected: _onlyLowStock,
                  onSelected: (val) => setState(() => _onlyLowStock = val),
                  selectedColor: AppTheme.warningColor.withValues(alpha: 0.25),
                  checkmarkColor: AppTheme.warningColor,
                  labelStyle: TextStyle(
                    color: _onlyLowStock ? AppTheme.warningColor : AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                TextField(
                  controller: _searchController,
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    hintStyle:
                        const TextStyle(color: AppTheme.secondaryColor),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppTheme.secondaryColor,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.cardBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBackground,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: categories.contains(_selectedCategory)
                                ? _selectedCategory
                                : 'All',
                            dropdownColor: AppTheme.backgroundColor,
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                            ),
                            items: categories.map((cat) {
                              return DropdownMenuItem(
                                value: cat,
                                child: Text(cat == 'All' ? 'All Categories' : cat),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedCategory = val);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilterChip(
                      label: const Text('Low Stock'),
                      selected: _onlyLowStock,
                      onSelected: (val) => setState(() => _onlyLowStock = val),
                      selectedColor: AppTheme.warningColor.withValues(alpha: 0.25),
                      checkmarkColor: AppTheme.warningColor,
                      labelStyle: TextStyle(
                        color: _onlyLowStock ? AppTheme.warningColor : AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildDesktopTable(List<Product> products) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            horizontalMargin: 20,
            columnSpacing: 24,
            headingRowColor: WidgetStateProperty.all(
              AppTheme.elevatedBackground,
            ),
            columns: [
              const DataColumn(label: Text('Product & SKU', style: _headerStyle)),
              const DataColumn(label: Text('Category', style: _headerStyle)),
              const DataColumn(label: Text('Stock Level', style: _headerStyle)),
              const DataColumn(label: Text('Selling Price', style: _headerStyle)),
              if (_isAdmin)
                const DataColumn(label: Text('Cost Price', style: _headerStyle)),
              if (_isAdmin)
                const DataColumn(label: Text('Margin', style: _headerStyle)),
              if (_isAdmin)
                const DataColumn(label: Text('Action', style: _headerStyle)),
            ],
            rows: products.map((product) {
              final isLow = product.quantityOnHand <= product.lowStockThreshold;
              final isOut = product.quantityOnHand <= 0;
              final margin = product.sellingPrice > 0
                  ? ((product.sellingPrice - product.costPrice) /
                          product.sellingPrice *
                          100)
                      .toStringAsFixed(1)
                  : '0.0';

              return DataRow(
                cells: [
                  DataCell(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (product.sku.isNotEmpty)
                          Text(
                            'SKU: ${product.sku}',
                            style: const TextStyle(
                              color: AppTheme.secondaryColor,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      product.category.isEmpty ? '-' : product.category,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '${product.quantityOnHand} ${product.unit}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isOut
                                  ? AppTheme.errorColor
                                  : isLow
                                      ? AppTheme.warningColor
                                      : AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isOut)
                          _buildBadge('OUT OF STOCK', AppTheme.errorColor)
                        else if (isLow)
                          _buildBadge('LOW STOCK', AppTheme.warningColor),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      CurrencyFormatter.format(product.sellingPrice),
                      style: const TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                   if (_isAdmin)
                    DataCell(
                      Text(
                        CurrencyFormatter.format(product.costPrice),
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                   if (_isAdmin)
                    DataCell(
                      Text(
                        '$margin%',
                        style: TextStyle(
                          color: double.parse(margin) >= 20
                              ? AppTheme.successColor
                              : AppTheme.warningColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (_isAdmin)
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           IconButton(
                             icon: const Icon(
                               Icons.edit,
                               size: 18,
                               color: AppTheme.highlightColor,
                             ),
                             tooltip: 'Edit Product',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ProductFormScreen(existingProduct: product, firestoreService: _firestoreService),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.redAccent,
                            ),
                            tooltip: 'Delete Product',
                            onPressed: () => _confirmDeleteProduct(product),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  static const _headerStyle = TextStyle(
    color: AppTheme.textPrimary,
    fontWeight: FontWeight.bold,
    fontSize: 13,
  );

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMobileList(List<Product> products) {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        final isLowStock = product.quantityOnHand <= product.lowStockThreshold;

        return Card(
          color: AppTheme.cardBackground,
          margin: const EdgeInsets.only(bottom: 12.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            side: BorderSide(
              color: isLowStock
                  ? AppTheme.warningColor.withValues(alpha: 0.5)
                  : AppTheme.borderColor,
              width: 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTheme.sp16,
              vertical: AppTheme.sp8,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (isLowStock) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.warningColor,
                    size: 20,
                  ),
                ],
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Category: ${product.category}  •  Stock: ${product.quantityOnHand} ${product.unit}',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Price: ${CurrencyFormatter.format(product.sellingPrice)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_isAdmin) ...[
                        const SizedBox(width: 16),
                        Flexible(
                          child: Text(
                            'Cost: ${CurrencyFormatter.format(product.costPrice)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            trailing: _isAdmin
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          color: AppTheme.highlightColor,
                          size: 20,
                        ),
                        tooltip: 'Edit Product',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProductFormScreen(
                                  existingProduct: product, firestoreService: _firestoreService),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppTheme.errorColor,
                          size: 20,
                        ),
                        tooltip: 'Delete Product',
                        onPressed: () => _confirmDeleteProduct(product),
                      ),
                    ],
                  )
                : null,
            onTap: _isAdmin
                ? () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ProductFormScreen(existingProduct: product, firestoreService: _firestoreService),
                      ),
                    );
                  }
                : null,
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          side: BorderSide(
            color: AppTheme.secondaryColor.withValues(alpha: 0.2),
          ),
        ),
        title: const Text(
          'Delete Product',
          style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Delete ${product.name}? This cannot be undone.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.secondaryColor),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: AppTheme.textPrimary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _firestoreService.deleteProduct(product.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${product.name} deleted.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete product: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}



