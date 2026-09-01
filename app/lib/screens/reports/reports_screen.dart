import 'package:flutter/material.dart';

import '../../models/staff.dart';
import '../../models/sale.dart';
import '../../models/product.dart';
import '../../services/firestore_service.dart';
import '../../utils/theme.dart';

class ReportsScreen extends StatefulWidget {
  final Staff currentStaff;

  const ReportsScreen({super.key, required this.currentStaff});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _firestoreService = FirestoreService();

  // Segmented control value: 0 = Daily, 1 = Weekly, 2 = Monthly
  int _selectedPeriodIndex = 0;

  bool get _isAdmin => widget.currentStaff.role == 'admin';

  DateTimeRange _getSelectedRange() {
    final now = DateTime.now();
    switch (_selectedPeriodIndex) {
      case 0: // Daily
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case 1: // Weekly
        final daysToSubtract = now.weekday - 1;
        final monday = now.subtract(Duration(days: daysToSubtract));
        final start = DateTime(monday.year, monday.month, monday.day);

        final daysToAdd = 7 - now.weekday;
        final sunday = now.add(Duration(days: daysToAdd));
        final end = DateTime(
          sunday.year,
          sunday.month,
          sunday.day,
          23,
          59,
          59,
          999,
        );
        return DateTimeRange(start: start, end: end);
      case 2: // Monthly
      default:
        final start = DateTime(now.year, now.month, 1);
        final lastDay = DateTime(now.year, now.month + 1, 0);
        final end = DateTime(now.year, now.month, lastDay.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 2 tabs if cashier (Sales Summary, Stock Balance), 3 if admin (+ Profit & Loss)
    final tabCount = _isAdmin ? 3 : 2;

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: TabBar(
          indicatorColor: AppTheme.primaryColor,
          labelColor: Colors.white,
          unselectedLabelColor: AppTheme.secondaryColor,
          tabs: [
            const Tab(text: 'Sales Summary'),
            if (_isAdmin) const Tab(text: 'Profit & Loss'),
            const Tab(text: 'Stock Balance'),
          ],
        ),
        body: TabBarView(
          children: [
            _buildSalesSummaryTab(),
            if (_isAdmin) _buildProfitLossTab(),
            _buildStockBalanceTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesSummaryTab() {
    final range = _getSelectedRange();

    return StreamBuilder<List<Sale>>(
      stream: _firestoreService.getSalesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Error loading sales data',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        final sales = snapshot.data ?? [];

        // Filter sales by the local timezone range
        final filteredSales = sales.where((sale) {
          return sale.timestamp.isAfter(range.start) &&
              sale.timestamp.isBefore(range.end);
        }).toList();

        double totalRevenue = 0;
        double totalProfit = 0;
        int transactionCount = filteredSales.length;
        Map<String, double> paymentBreakdown = {
          'Cash': 0.0,
          'M-Pesa': 0.0,
          'Card': 0.0,
          'Credit': 0.0,
        };

        for (final sale in filteredSales) {
          totalRevenue += sale.totalAmount;
          paymentBreakdown[sale.paymentMethod] =
              (paymentBreakdown[sale.paymentMethod] ?? 0.0) + sale.totalAmount;

          for (final item in sale.lineItems) {
            totalProfit += item.profit;
          }
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPeriodSelector(),
              const SizedBox(height: 20),
              _buildMetricCard(
                title: 'Total Revenue',
                value: 'KSh ${totalRevenue.toStringAsFixed(2)}',
                icon: Icons.attach_money,
                color: AppTheme.primaryColor,
              ),
              if (_isAdmin) ...[
                const SizedBox(height: 12),
                _buildMetricCard(
                  title: 'Total Profit',
                  value: 'KSh ${totalProfit.toStringAsFixed(2)}',
                  icon: Icons.trending_up,
                  color: Colors.green,
                ),
              ],
              const SizedBox(height: 12),
              _buildMetricCard(
                title: 'Transactions',
                value: '$transactionCount',
                icon: Icons.receipt_long,
                color: AppTheme.secondaryColor,
              ),
              const SizedBox(height: 24),
              const Text(
                'Payment Method Breakdown',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...paymentBreakdown.entries.map(
                (entry) => _buildPaymentRow(entry.key, entry.value),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfitLossTab() {
    final range = _getSelectedRange();

    return StreamBuilder<List<Sale>>(
      stream: _firestoreService.getSalesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Error loading P&L data',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        final sales = snapshot.data ?? [];

        final filteredSales = sales.where((sale) {
          return sale.timestamp.isAfter(range.start) &&
              sale.timestamp.isBefore(range.end);
        }).toList();

        double revenue = 0;
        double costOfGoodsSold = 0;

        for (final sale in filteredSales) {
          revenue += sale.totalAmount;
          for (final item in sale.lineItems) {
            costOfGoodsSold += item.unitCostAtSale * item.quantity;
          }
        }

        double netProfit = revenue - costOfGoodsSold;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPeriodSelector(),
              const SizedBox(height: 20),
              Card(
                color: Colors.white.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      _buildPLRow(
                        'Gross Revenue',
                        'KSh ${revenue.toStringAsFixed(2)}',
                        Colors.white,
                      ),
                      const Divider(color: Colors.white24, height: 24),
                      _buildPLRow(
                        'Cost of Goods Sold (COGS)',
                        '-KSh ${costOfGoodsSold.toStringAsFixed(2)}',
                        Colors.redAccent,
                      ),
                      const Divider(color: Colors.white24, height: 24),
                      _buildPLRow(
                        'Net Profit',
                        'KSh ${netProfit.toStringAsFixed(2)}',
                        netProfit >= 0 ? Colors.green : Colors.red,
                        isBold: true,
                        fontSize: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStockBalanceTab() {
    return StreamBuilder<List<Product>>(
      stream: _firestoreService.getProductsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
            child: Text(
              'Error loading stock inventory',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        final products = snapshot.data ?? [];

        if (products.isEmpty) {
          return const Center(
            child: Text(
              'No inventory records found.',
              style: TextStyle(color: AppTheme.secondaryColor),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            final isLowStock =
                product.quantityOnHand <= product.lowStockThreshold;

            return Card(
              color: Colors.white.withValues(alpha: 0.05),
              margin: const EdgeInsets.only(bottom: 12.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isLowStock
                      ? Colors.orange.withValues(alpha: 0.5)
                      : Colors.transparent,
                ),
              ),
              child: ListTile(
                title: Text(
                  product.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'SKU: ${product.sku}  •  Category: ${product.category}',
                  style: const TextStyle(
                    color: AppTheme.secondaryColor,
                    fontSize: 12,
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${product.quantityOnHand} ${product.unit}',
                      style: TextStyle(
                        color: isLowStock ? Colors.orange : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (isLowStock)
                      const Text(
                        'Low Stock',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPeriodSelector() {
    return Center(
      child: SegmentedButton<int>(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return AppTheme.primaryColor;
            }
            return Colors.white.withValues(alpha: 0.05);
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
        ),
        segments: const [
          ButtonSegment<int>(value: 0, label: Text('Daily')),
          ButtonSegment<int>(value: 1, label: Text('Weekly')),
          ButtonSegment<int>(value: 2, label: Text('Monthly')),
        ],
        selected: {_selectedPeriodIndex},
        onSelectionChanged: (Set<int> newSelection) {
          setState(() {
            _selectedPeriodIndex = newSelection.first;
          });
        },
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(color: AppTheme.secondaryColor, fontSize: 14),
        ),
        trailing: SizedBox(
          width: 170,
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentRow(String method, double amount) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      margin: const EdgeInsets.only(bottom: 8.0),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              method,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Flexible(
            child: Text(
              'KSh ${amount.toStringAsFixed(2)}',
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
      ),
    );
  }

  Widget _buildPLRow(
    String label,
    String value,
    Color valColor, {
    bool isBold = false,
    double fontSize = 16,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valColor,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
