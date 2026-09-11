import 'package:flutter/material.dart';

import '../../models/staff.dart';
import '../../models/product.dart';
import '../../services/firestore_service.dart';
import '../../utils/theme.dart';
import 'product_form_screen.dart';

class ProductsScreen extends StatefulWidget {
  final Staff currentStaff;

  const ProductsScreen({super.key, required this.currentStaff});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _firestoreService = FirestoreService();
  final _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedCategory = 'All';
  bool _onlyLowStock = false;

  bool get _isAdmin => widget.currentStaff.role.toLowerCase() == 'admin';

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
        stream: _firestoreService.getProductsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading products: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
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
                  MaterialPageRoute(builder: (_) => const ProductFormScreen()),
                );
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add Product', style: TextStyle(color: Colors.white)),
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
        color: Colors.white.withValues(alpha: 0.02),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.secondaryColor.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: isDesktop
          ? Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
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
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: categories.contains(_selectedCategory)
                          ? _selectedCategory
                          : 'All',
                      dropdownColor: AppTheme.backgroundColor,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
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
                  selectedColor: Colors.orange.withValues(alpha: 0.25),
                  checkmarkColor: Colors.orange,
                  labelStyle: TextStyle(
                    color: _onlyLowStock ? Colors.orange : Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            )
          : Column(
              children: [
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
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
                    fillColor: Colors.white.withValues(alpha: 0.05),
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
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: categories.contains(_selectedCategory)
                                ? _selectedCategory
                                : 'All',
                            dropdownColor: AppTheme.backgroundColor,
                            style: const TextStyle(
                              color: Colors.white,
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
                      selectedColor: Colors.orange.withValues(alpha: 0.25),
                      checkmarkColor: Colors.orange,
                      labelStyle: TextStyle(
                        color: _onlyLowStock ? Colors.orange : Colors.white70,
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
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.secondaryColor.withValues(alpha: 0.15),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            horizontalMargin: 20,
            columnSpacing: 24,
            headingRowColor: WidgetStateProperty.all(
              Colors.white.withValues(alpha: 0.05),
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
                            color: Colors.white,
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
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${product.quantityOnHand} ${product.unit}',
                          style: TextStyle(
                            color: isOut
                                ? Colors.redAccent
                                : isLow
                                    ? Colors.orange
                                    : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isOut)
                          _buildBadge('OUT OF STOCK', Colors.red)
                        else if (isLow)
                          _buildBadge('LOW STOCK', Colors.orange),
                      ],
                    ),
                  ),
                  DataCell(
                    Text(
                      'KSh ${product.sellingPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_isAdmin)
                    DataCell(
                      Text(
                        'KSh ${product.costPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  if (_isAdmin)
                    DataCell(
                      Text(
                        '$margin%',
                        style: TextStyle(
                          color: double.parse(margin) >= 20
                              ? Colors.green
                              : Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (_isAdmin)
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18, color: Colors.blue),
                        tooltip: 'Edit Product',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProductFormScreen(existingProduct: product),
                            ),
                          );
                        },
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
    color: Colors.white,
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
          color: Colors.white.withValues(alpha: 0.05),
          margin: const EdgeInsets.only(bottom: 12.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isLowStock
                  ? Colors.orange.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (isLowStock)
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 20,
                  ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Category: ${product.category}  •  Stock: ${product.quantityOnHand} ${product.unit}',
                    style: const TextStyle(color: AppTheme.secondaryColor),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Price: KSh ${product.sellingPrice.toStringAsFixed(2)}',
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
                            'Cost: KSh ${product.costPrice.toStringAsFixed(2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
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
                ? const Icon(Icons.edit, color: AppTheme.secondaryColor)
                : null,
            onTap: _isAdmin
                ? () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ProductFormScreen(existingProduct: product),
                      ),
                    );
                  }
                : null,
          ),
        );
      },
    );
  }
}
