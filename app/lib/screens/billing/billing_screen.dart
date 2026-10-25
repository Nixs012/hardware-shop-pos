import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'dart:async';
import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../models/product.dart';
import '../../models/sale.dart';
import '../../models/sale_line_item.dart';
import '../../models/staff.dart';
import '../../services/firestore_service.dart';
import '../../services/printer_service.dart';
import '../../services/sync_service.dart';
import '../../utils/theme.dart';
import '../../widgets/error_display_widgets.dart';

class BillingScreen extends StatefulWidget {
  final Staff currentStaff;
  final FirestoreService? firestoreService;

  const BillingScreen({super.key, required this.currentStaff, this.firestoreService});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen>
    with SingleTickerProviderStateMixin {
  late final FirestoreService _firestoreService;
  final _printerService = PrinterService();
  final _searchController = TextEditingController();

  String _searchQuery = '';
  List<Product> _allProducts = [];

  // Cart state: keyed by product ID
  final Map<String, SaleLineItem> _cart = {};
  Sale? _lastCompletedSale;

  // Cart expansion state (mobile only)
  bool _isCartExpanded = false;
  static const double _cartCollapsedHeight = 88.0;
  static const double _maxCartExpandRatio = 0.55; // max 55% of screen height

  @override
  void initState() {
    super.initState();
    _firestoreService = widget.firestoreService ??
        FirestoreServiceImpl(widget.currentStaff.shopId);
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
    return _cart.values.fold(
      0,
      (sum, item) => sum + (item.unitPriceAtSale * item.quantity),
    );
  }

  int get _cartItemCount {
    return _cart.values.fold(0, (sum, item) => sum + item.quantity.toInt());
  }

  void _addToCart(Product product) async {
    if (product.quantityOnHand <= 0) {
      final override = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.backgroundColor,
          title: const Text(
            'Out of Stock',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            '${product.name} is out of stock. Add anyway?',
            style: const TextStyle(color: Colors.white70),
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
                backgroundColor: AppTheme.primaryColor,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Override',
                style: TextStyle(color: Colors.white),
              ),
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
      _ensureCartCollapsed();
    });
  }

  void _ensureCartCollapsed() {
    // If not expanded, keep collapsed; if expanded, keep expanded
    if (!mounted || _isCartExpanded) return;
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
    try {
      if (_cart.isEmpty) {
        return;
      }

      final paymentMethod = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.backgroundColor,
          title: const Text(
            'Select Payment Method',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _paymentButton(ctx, 'Cash'),
              const SizedBox(height: 8),
              _paymentButton(ctx, 'M-Pesa'),
              const SizedBox(height: 8),
              _paymentButton(ctx, 'Credit'),
            ],
          ),
        ),
      );

      if (paymentMethod == null) {
        return;
      }

      String? customerName;
      String? customerPhone;

      if (paymentMethod == 'Credit') {
        final customerInfo = await _showCustomerCreditDialog();
        if (customerInfo == null) return;
        customerName = customerInfo['name'];
        customerPhone = customerInfo['phone'];
      }

      bool hasOversold = false;
      for (final item in _cart.values) {
        try {
          final product = _allProducts.firstWhere(
            (p) => p.id == item.productId,
          );
          if (product.quantityOnHand - item.quantity < 0) {
            hasOversold = true;
          }
        } catch (_) {}
      }

      final sale = Sale(
        id: const Uuid().v4(),
        timestamp: DateTime.now(),
        staffId: widget.currentStaff.id,
        paymentMethod: paymentMethod,
        lineItems: _cart.values.toList(),
        customerName: customerName,
        customerPhone: customerPhone,
      );

      final bool isAdmin = widget.currentStaff.role.toLowerCase() == 'admin';
      await _firestoreService.processSale(
        sale,
        includeCostSnapshot: isAdmin,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _cart.clear();
        _isCartExpanded = false;
      });

      final isOnline = SyncService.instance.isOnline;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasOversold
                ? 'Sale Complete! Warning: Some items were oversold.'
                : (isOnline
                    ? 'Sale Successful'
                    : 'Sale saved offline (queued for auto-sync)'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: hasOversold
              ? Colors.orange
              : (isOnline ? Colors.green : Colors.amber.shade800),
          duration: const Duration(seconds: 4),
        ),
      );
      _lastCompletedSale = sale;
      if (!kIsWeb) {
        unawaited(_printSale(sale));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _printSale(Sale sale) async {
    final items = sale.lineItems.map((item) {
      final matchingProducts = _allProducts.where(
        (p) => p.id == item.productId,
      );
      final product = matchingProducts.isEmpty ? null : matchingProducts.first;
      return ReceiptItem(
        name: product?.name ?? item.productId,
        quantity: item.quantity,
        total: item.unitPriceAtSale * item.quantity,
      );
    }).toList();

    try {
      await _printerService.printSale(
        sale: sale,
        staffName: widget.currentStaff.name,
        items: items,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().contains('not connected')
                ? 'Printer not connected'
                : error.toString().contains('PrinterWriteException') ||
                    error.toString().contains('PrinterConnectionException')
                ? 'Printer disconnected or out of paper'
                : 'Printer error: $error',
          ),
          backgroundColor: Colors.orange,
          action: SnackBarAction(
            label: 'Reconnect',
            onPressed: () => unawaited(_reconnectAndPrint(sale)),
          ),
        ),
      );
    }
  }

  Future<void> _reconnectAndPrint(Sale sale) async {
    final connected = await _printerService.autoReconnect();
    if (!mounted) return;
    if (!connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Printer not connected. Pair it from Settings first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    await _printSale(sale);
  }

  Future<void> _reprintLastReceipt() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Receipt printing is only available on the Android app.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    try {
      final sale =
          _lastCompletedSale ??
          await _firestoreService.getLatestSale(
            staffId: _cashierQueryId,
          );
      if (sale == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No completed sale is available to reprint.'),
            ),
          );
        }
        return;
      }
      await _printSale(sale);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load the last sale: $error')),
        );
      }
    }
  }

  String? get _cashierQueryId {
    final isAdmin = widget.currentStaff.role.toLowerCase() == 'admin';
    return isAdmin ? null : widget.currentStaff.id;
  }

  Future<Map<String, String>?> _showCustomerCreditDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppTheme.backgroundColor,
          title: const Text(
            'Enter Customer Details (Credit)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Customer Name',
                    hintText: 'e.g. John Kamau',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Phone Number (Optional)',
                    hintText: 'e.g. 0712345678',
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  dialogCtx,
                  {
                    'name': name,
                    'phone': phoneController.text.trim(),
                  },
                );
              },
              child: const Text('Confirm Credit Sale'),
            ),
          ],
        );
      },
    );
  }

  Widget _paymentButton(BuildContext context, String method) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.secondaryColor.withValues(alpha: 0.1),
          foregroundColor: Colors.white,
          side: BorderSide(
            color: AppTheme.secondaryColor.withValues(alpha: 0.3),
          ),
        ),
        onPressed: () => Navigator.pop(context, method),
        child: Text(method, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxCartHeight = screenHeight * _maxCartExpandRatio;

    if (isWide) {
      // Desktop: sidebar layout with fixed cart
      return Row(
        children: [
          Expanded(flex: 5, child: _buildCatalog(isCartVisible: _cart.isNotEmpty)),
          Container(
            width: 1,
            color: AppTheme.secondaryColor.withValues(alpha: 0.3),
          ),
          Expanded(
            flex: 3,
            child: _buildCartExpanded(context, isDesktop: true),
          ),
        ],
      );
    }

    // Mobile: catalog + draggable cart bar
    return Scaffold(
      body: Stack(
        children: [
          _buildCatalog(isCartVisible: _cart.isNotEmpty),
          if (_cart.isNotEmpty) _buildDraggableCart(context, maxCartHeight),
          if (_cart.isNotEmpty && !_isCartExpanded)
            _buildCollapsedCartBar(),
        ],
      ),
    );
  }

  Widget _buildCatalog({required bool isCartVisible}) {
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
              prefixIcon: const Icon(
                Icons.search,
                color: AppTheme.secondaryColor,
              ),
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
            stream: _firestoreService.getProductsStream(
              isAdmin: widget.currentStaff.role.toLowerCase() == 'admin',
            ),
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

              _allProducts = snapshot.data ?? [];

              final filtered = _allProducts.where((p) {
                if (_searchQuery.isEmpty) return true;
                return p.name.toLowerCase().contains(_searchQuery) ||
                    p.sku.toLowerCase().contains(_searchQuery);
              }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text(
                    'No products found.',
                    style: TextStyle(color: AppTheme.secondaryColor),
                  ),
                );
              }

              return GridView.builder(
                padding: EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  top: 0,
                  bottom: isCartVisible
                      ? (_isCartExpanded ? 200.0 : 90.0)
                      : 16.0,
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
                  final isLowStock =
                      product.quantityOnHand <= product.lowStockThreshold;
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Text(
                            'KSh ${product.sellingPrice.toStringAsFixed(2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
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
                              fontWeight: outOfStock
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
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

  /// The collapsed cart bar at the bottom of the screen (mobile).
  /// Shows item count, total, and a "Complete Sale" button.
  /// Height: 88 dp. Tapping it expands the full cart.
  Widget _buildCollapsedCartBar() {
    final itemCount = _cartItemCount;
    final itemLabel = itemCount == 1 ? 'item' : 'items';

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: () => setState(() => _isCartExpanded = true),
        child: Container(
          height: _cartCollapsedHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
            border: Border(
              top: BorderSide(
                color: AppTheme.secondaryColor.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_cart, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Text(
                '$itemCount $itemLabel',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(width: 8),
              const VerticalDivider(
                color: Colors.white12,
                width: 1,
                indent: 8,
                endIndent: 8,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'KSh ${_cartTotal.toStringAsFixed(2)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _cart.isEmpty ? null : _checkout,
                  child: const Text(
                    'Complete Sale',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A draggable cart panel for mobile that slides up from the collapsed
  /// bar to the fully expanded state. Uses a drag gesture detector.
  Widget _buildDraggableCart(BuildContext context, double maxCartHeight) {
    final cartHeight = _isCartExpanded ? maxCartHeight : _cartCollapsedHeight;
    final screenHeight = MediaQuery.of(context).size.height;
    final effectiveHeight = math.min(cartHeight, screenHeight * _maxCartExpandRatio);

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: GestureDetector(
        onTap: _isCartExpanded
            ? () => setState(() => _isCartExpanded = false)
            : null,
        onPanUpdate: (details) {
          final delta = details.delta.dy;
          if (delta < 0 && !_isCartExpanded) {
            // Swiping up -> expand
            setState(() {
              _isCartExpanded = true;
            });
          } else if (delta > 0 && _isCartExpanded) {
            // Swiping down -> collapse
            setState(() {
              _isCartExpanded = false;
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          height: effectiveHeight,
          decoration: BoxDecoration(
            color: AppTheme.backgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(_isCartExpanded ? 0 : 16),
            ),
            border: Border(
              top: BorderSide(
                color: AppTheme.secondaryColor.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: _buildCartExpanded(context),
        ),
      ),
    );
  }

  /// The full cart widget used for desktop (always expanded) and mobile
  /// (when dragged up). Shows cart items list, total, and Complete Sale button.
  Widget _buildCartExpanded(BuildContext context, {bool isDesktop = false}) {
    return Column(
      children: [
        // Drag handle (mobile only)
        if (!isDesktop)
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        if (!isDesktop && _isCartExpanded && _cart.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Current Sale',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$_cartItemCount ${_cartItemCount == 1 ? 'item' : 'items'}',
                  style: const TextStyle(
                    color: AppTheme.secondaryColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        else if (isDesktop)
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Current Sale',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_cart.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep,
                        color: Colors.redAccent),
                    onPressed: () => setState(() => _cart.clear()),
                    tooltip: 'Clear Cart',
                  ),
              ],
            ),
          ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: _cart.isEmpty
              ? const Center(
                  child: Text(
                    'Cart is empty',
                    style: TextStyle(color: AppTheme.secondaryColor),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: _cart.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Colors.white12),
                  itemBuilder: (context, index) {
                    final key = _cart.keys.elementAt(index);
                    final item = _cart[key]!;
                    final product = _allProducts.firstWhere(
                      (p) => p.id == item.productId,
                      orElse: () => Product(
                        id: '',
                        name: 'Unknown',
                        sku: '',
                        category: '',
                        costPrice: 0,
                        sellingPrice: item.unitPriceAtSale,
                        quantityOnHand: 0,
                        unit: '',
                      ),
                    );

                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'KSh ${item.unitPriceAtSale.toStringAsFixed(2)} each',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.secondaryColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: AppTheme.secondaryColor,
                              ),
                              onPressed: () => _updateQuantity(key, -1),
                            ),
                            SizedBox(
                              width: 30,
                              child: Text(
                                '${item.quantity}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle_outline,
                                color: AppTheme.secondaryColor,
                              ),
                              onPressed: () => _updateQuantity(key, 1),
                            ),
                          ],
                        ),
                        SizedBox(
                          width: 96,
                          child: Text(
                            'KSh ${(item.unitPriceAtSale * item.quantity).toStringAsFixed(2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
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
              if (!kIsWeb)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _reprintLastReceipt,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Reprint last receipt'),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Total',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'KSh ${_cartTotal.toStringAsFixed(2)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _cart.isEmpty ? null : _checkout,
                  child: const Text(
                    'Complete Sale',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
