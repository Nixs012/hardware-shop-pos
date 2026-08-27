import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/product.dart';
import '../../models/sale.dart';
import '../../models/sale_line_item.dart';
import '../../models/staff.dart';
import '../../services/firestore_service.dart';
import '../../utils/theme.dart';

class BillingScreen extends StatefulWidget {
  final Staff currentStaff;

  const BillingScreen({super.key, required this.currentStaff});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _firestoreService = FirestoreService();
  final _searchController = TextEditingController();
  
  String _searchQuery = '';
  List<Product> _allProducts = [];
  
  // Cart state: keyed by product ID
  final Map<String, SaleLineItem> _cart = {};
  
  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double get _cartTotal {
    return _cart.values.fold(0, (sum, item) => sum + (item.unitPriceAtSale * item.quantity));
  }
  
  void _addToCart(Product product) async {
    if (product.quantityOnHand <= 0) {
      final override = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.backgroundColor,
          title: const Text('Out of Stock', style: TextStyle(color: Colors.white)),
          content: Text('${product.name} is out of stock. Add anyway?', style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.secondaryColor)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Override', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (override != true) return;
    }

    setState(() {
      if (_cart.containsKey(product.id)) {
        final existing = _cart[product.id]!;
        _cart[product.id] = SaleLineItem(
          productId: existing.productId,
          quantity: existing.quantity + 1,
          unitPriceAtSale: existing.unitPriceAtSale,
          unitCostAtSale: existing.unitCostAtSale,
        );
      } else {
        _cart[product.id] = SaleLineItem(
          productId: product.id,
          quantity: 1,
          unitPriceAtSale: product.sellingPrice,
          unitCostAtSale: product.costPrice,
        );
      }
    });
  }

  void _updateQuantity(String productId, double delta) {
    setState(() {
      if (!_cart.containsKey(productId)) return;
      final existing = _cart[productId]!;
      final newQuantity = existing.quantity + delta;
      
      if (newQuantity <= 0) {
        _cart.remove(productId);
      } else {
        _cart[productId] = SaleLineItem(
          productId: existing.productId,
          quantity: newQuantity,
          unitPriceAtSale: existing.unitPriceAtSale,
          unitCostAtSale: existing.unitCostAtSale,
        );
      }
    });
  }
  
  void _checkout() async {
    if (_cart.isEmpty) return;

    final paymentMethod = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.backgroundColor,
        title: const Text('Select Payment Method', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _paymentButton(ctx, 'Cash'),
            const SizedBox(height: 8),
            _paymentButton(ctx, 'M-Pesa'),
            const SizedBox(height: 8),
            _paymentButton(ctx, 'Card'),
            const SizedBox(height: 8),
            _paymentButton(ctx, 'Credit'),
          ],
        ),
      ),
    );

    if (paymentMethod == null) return;
    
    // Evaluate if any products are oversold before clearing cart
    bool hasOversold = false;
    for (final item in _cart.values) {
      try {
        final product = _allProducts.firstWhere((p) => p.id == item.productId);
        if (product.quantityOnHand - item.quantity < 0) {
          hasOversold = true;
        }
      } catch (e) {
        // Product not found in local cache, ignore oversold check
      }
    }

    final sale = Sale(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      staffId: widget.currentStaff.id,
      paymentMethod: paymentMethod,
      lineItems: _cart.values.toList(),
    );

    try {
      await _firestoreService.processSale(sale);
      
      if (mounted) {
        setState(() {
          _cart.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text(
              hasOversold 
                ? 'Sale Complete! Warning: Some items were oversold.' 
                : 'Sale Complete!',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: hasOversold ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 4),
          )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _paymentButton(BuildContext context, String method) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.secondaryColor.withValues(alpha: 0.1),
          foregroundColor: Colors.white,
          side: BorderSide(color: AppTheme.secondaryColor.withValues(alpha: 0.3)),
        ),
        onPressed: () => Navigator.pop(context, method),
        child: Text(method, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        
        final catalogWidget = _buildCatalog();
        final cartWidget = _buildCart();

        if (isWide) {
          return Row(
            children: [
              Expanded(flex: 5, child: catalogWidget),
              Container(width: 1, color: AppTheme.secondaryColor.withValues(alpha: 0.3)),
              Expanded(flex: 3, child: cartWidget),
            ],
          );
        } else {
          return Stack(
            children: [
              catalogWidget,
              if (_cart.isNotEmpty)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: 380, // High enough for mobile touch targets
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5), 
                          blurRadius: 10, 
                          offset: const Offset(0, -5)
                        )
                      ],
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      border: Border(top: BorderSide(color: AppTheme.secondaryColor.withValues(alpha: 0.3))),
                    ),
                    child: cartWidget,
                  ),
                ),
            ],
          );
        }
      },
    );
  }

  Widget _buildCatalog() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search products...',
              hintStyle: const TextStyle(color: AppTheme.secondaryColor),
              prefixIcon: const Icon(Icons.search, color: AppTheme.secondaryColor),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Product>>(
            stream: _firestoreService.getProductsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(child: Text('Error loading products', style: TextStyle(color: Colors.red)));
              }

              _allProducts = snapshot.data ?? [];
              
              final filtered = _allProducts.where((p) {
                if (_searchQuery.isEmpty) return true;
                return p.name.toLowerCase().contains(_searchQuery) || p.sku.toLowerCase().contains(_searchQuery);
              }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text('No products found.', style: TextStyle(color: AppTheme.secondaryColor)),
                );
              }

              return GridView.builder(
                padding: EdgeInsets.only(
                  left: 16.0, right: 16.0, top: 0, 
                  bottom: _cart.isNotEmpty ? 400 : 16.0, // extra padding on mobile if cart is visible
                ),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final product = filtered[index];
                  final isLowStock = product.quantityOnHand <= product.lowStockThreshold;
                  final outOfStock = product.quantityOnHand <= 0;

                  return InkWell(
                    onTap: () => _addToCart(product),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: outOfStock 
                            ? Colors.red.withValues(alpha: 0.1) 
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: outOfStock 
                              ? Colors.red.withValues(alpha: 0.3)
                              : isLowStock 
                                  ? Colors.orange.withValues(alpha: 0.5) 
                                  : AppTheme.secondaryColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Text(
                            '\$${product.sellingPrice.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Stock: ${product.quantityOnHand} ${product.unit}',
                            style: TextStyle(
                              color: outOfStock 
                                  ? Colors.red 
                                  : isLowStock 
                                      ? Colors.orange 
                                      : AppTheme.secondaryColor, 
                              fontSize: 12,
                              fontWeight: outOfStock ? FontWeight.bold : FontWeight.normal
                            ),
                          )
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCart() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_cart, color: Colors.white),
              const SizedBox(width: 8),
              const Text('Current Sale', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_cart.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                  onPressed: () => setState(() => _cart.clear()),
                  tooltip: 'Clear Cart',
                )
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: _cart.isEmpty
            ? const Center(child: Text('Cart is empty', style: TextStyle(color: AppTheme.secondaryColor)))
            : ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: _cart.length,
                separatorBuilder: (context, index) => const Divider(color: Colors.white12),
                itemBuilder: (context, index) {
                  final key = _cart.keys.elementAt(index);
                  final item = _cart[key]!;
                  final product = _allProducts.firstWhere(
                    (p) => p.id == item.productId, 
                    orElse: () => Product(
                      id: '', name: 'Unknown', sku: '', category: '', 
                      costPrice: 0, sellingPrice: item.unitPriceAtSale, quantityOnHand: 0, unit: ''
                    )
                  );

                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name, 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text('\$${item.unitPriceAtSale.toStringAsFixed(2)} each', style: const TextStyle(color: AppTheme.secondaryColor, fontSize: 12)),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: AppTheme.secondaryColor),
                            onPressed: () => _updateQuantity(key, -1),
                          ),
                          SizedBox(
                            width: 30,
                            child: Text(
                              '${item.quantity}', 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: AppTheme.secondaryColor),
                            onPressed: () => _updateQuantity(key, 1),
                          ),
                        ],
                      ),
                      SizedBox(
                        width: 70,
                        child: Text(
                          '\$${(item.unitPriceAtSale * item.quantity).toStringAsFixed(2)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  );
                },
              ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white.withValues(alpha: 0.05),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('\$${_cartTotal.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.primaryColor, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _cart.isEmpty ? null : _checkout,
                  child: const Text('Complete Sale', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
