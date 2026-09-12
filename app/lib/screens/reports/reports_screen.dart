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
  String _stockSearchQuery = '';
  String _stockCategoryFilter = 'All';

  bool get _isAdmin => widget.currentStaff.role.toLowerCase() == 'admin';

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

        final avgTicket =
            transactionCount > 0 ? (totalRevenue / transactionCount) : 0.0;
        final profitMargin =
            totalRevenue > 0 ? (totalProfit / totalRevenue * 100) : 0.0;

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 800;

            return SingleChildScrollView(
              padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPeriodSelector(),
                  const SizedBox(height: 24),
                  if (isDesktop)
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            title: 'Total Revenue',
                            value: 'KSh ${totalRevenue.toStringAsFixed(2)}',
                            icon: Icons.attach_money,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        if (_isAdmin) const SizedBox(width: 16),
                        if (_isAdmin)
                          Expanded(
                            child: _buildMetricCard(
                              title: 'Total Profit',
                              value: 'KSh ${totalProfit.toStringAsFixed(2)}',
                              icon: Icons.trending_up,
                              color: Colors.green,
                            ),
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'Transactions',
                            value: '$transactionCount',
                            icon: Icons.receipt_long,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'Average Ticket',
                            value: 'KSh ${avgTicket.toStringAsFixed(2)}',
                            icon: Icons.shopping_bag_outlined,
                            color: Colors.purpleAccent,
                          ),
                        ),
                      ],
                    )
                  else ...[
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
                  ],
                  const SizedBox(height: 24),
                  if (isDesktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _buildPaymentBreakdownCard(
                            paymentBreakdown,
                            totalRevenue,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 4,
                          child: _buildSalesInsightsCard(
                            transactionCount: transactionCount,
                            profitMargin: profitMargin,
                            totalRevenue: totalRevenue,
                            totalProfit: totalProfit,
                          ),
                        ),
                      ],
                    )
                  else
                    _buildPaymentBreakdownCard(paymentBreakdown, totalRevenue),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPaymentBreakdownCard(
    Map<String, double> paymentBreakdown,
    double totalRevenue,
  ) {
    return Card(
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment Method Breakdown',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...paymentBreakdown.entries.map((entry) {
              final pct = totalRevenue > 0
                  ? (entry.value / totalRevenue * 100).toStringAsFixed(1)
                  : '0.0';
              return _buildPaymentRow(entry.key, entry.value, pct);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesInsightsCard({
    required int transactionCount,
    required double profitMargin,
    required double totalRevenue,
    required double totalProfit,
  }) {
    return Card(
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sales Performance Overview',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (_isAdmin)
              _buildInsightRow(
                'Profit Margin',
                '${profitMargin.toStringAsFixed(1)}%',
                profitMargin >= 15 ? Colors.green : Colors.orange,
              ),
            if (_isAdmin) const Divider(color: Colors.white12, height: 20),
            _buildInsightRow(
              'Avg Ticket Value',
              transactionCount > 0
                  ? 'KSh ${(totalRevenue / transactionCount).toStringAsFixed(2)}'
                  : 'KSh 0.00',
              Colors.white,
            ),
            const Divider(color: Colors.white12, height: 20),
            _buildInsightRow(
              'Total Volume',
              '$transactionCount orders',
              AppTheme.secondaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ),
      ],
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
        double margin = revenue > 0 ? (netProfit / revenue * 100) : 0.0;

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 800;

            return SingleChildScrollView(
              padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPeriodSelector(),
                  const SizedBox(height: 24),
                  if (isDesktop)
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            title: 'Gross Revenue',
                            value: 'KSh ${revenue.toStringAsFixed(2)}',
                            icon: Icons.trending_up,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'Cost of Goods (COGS)',
                            value: 'KSh ${costOfGoodsSold.toStringAsFixed(2)}',
                            icon: Icons.shopping_basket_outlined,
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildMetricCard(
                            title: 'Net Profit',
                            value: 'KSh ${netProfit.toStringAsFixed(2)}',
                            icon: Icons.account_balance_wallet,
                            color: netProfit >= 0 ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 24),
                  Card(
                    color: Colors.white.withValues(alpha: 0.03),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          _buildPLRow(
                            'Gross Revenue',
                            'KSh ${revenue.toStringAsFixed(2)}',
                            Colors.white,
                          ),
                          const Divider(color: Colors.white12, height: 24),
                          _buildPLRow(
                            'Cost of Goods Sold (COGS)',
                            '-KSh ${costOfGoodsSold.toStringAsFixed(2)}',
                            Colors.redAccent,
                          ),
                          const Divider(color: Colors.white12, height: 24),
                          _buildPLRow(
                            'Net Profit',
                            'KSh ${netProfit.toStringAsFixed(2)}',
                            netProfit >= 0 ? Colors.green : Colors.red,
                            isBold: true,
                            fontSize: 20,
                          ),
                          const Divider(color: Colors.white12, height: 24),
                          _buildPLRow(
                            'Profit Margin',
                            '${margin.toStringAsFixed(1)}%',
                            margin >= 15 ? Colors.green : Colors.orange,
                            isBold: true,
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

        final categories = <String>{'All'};
        for (final p in products) {
          if (p.category.isNotEmpty) categories.add(p.category);
        }

        final filtered = products.where((p) {
          final matchesQuery = _stockSearchQuery.isEmpty ||
              p.name.toLowerCase().contains(_stockSearchQuery) ||
              p.sku.toLowerCase().contains(_stockSearchQuery);
          final matchesCat = _stockCategoryFilter == 'All' ||
              p.category.toLowerCase() == _stockCategoryFilter.toLowerCase();
          return matchesQuery && matchesCat;
        }).toList();

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 800;

            return Column(
              children: [
                _buildStockToolbar(categories.toList(), isDesktop),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No inventory records found.',
                            style: TextStyle(color: AppTheme.secondaryColor),
                          ),
                        )
                      : isDesktop
                          ? _buildDesktopStockTable(filtered)
                          : _buildMobileStockList(filtered),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStockToolbar(List<String> categories, bool isDesktop) {
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
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              onChanged: (val) =>
                  setState(() => _stockSearchQuery = val.trim().toLowerCase()),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search stock by name or SKU...',
                hintStyle: const TextStyle(color: AppTheme.secondaryColor),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppTheme.secondaryColor,
                  size: 18,
                ),
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
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
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: categories.contains(_stockCategoryFilter)
                    ? _stockCategoryFilter
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
                  if (val != null) setState(() => _stockCategoryFilter = val);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopStockTable(List<Product> products) {
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
            columns: const [
              DataColumn(
                label: Text('Product & SKU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              DataColumn(
                label: Text('Category', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              DataColumn(
                label: Text('Current Stock', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              DataColumn(
                label: Text('Threshold', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              DataColumn(
                label: Text('Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
            rows: products.map((product) {
              final isLow = product.quantityOnHand <= product.lowStockThreshold;
              final isOut = product.quantityOnHand <= 0;

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
                  ),
                  DataCell(
                    Text(
                      '${product.lowStockThreshold} ${product.unit}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isOut
                            ? Colors.red.withValues(alpha: 0.2)
                            : isLow
                                ? Colors.orange.withValues(alpha: 0.2)
                                : Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isOut
                              ? Colors.red
                              : isLow
                                  ? Colors.orange
                                  : Colors.green,
                        ),
                      ),
                      child: Text(
                        isOut
                            ? 'Out of Stock'
                            : isLow
                                ? 'Low Stock'
                                : 'In Stock',
                        style: TextStyle(
                          color: isOut
                              ? Colors.red
                              : isLow
                                  ? Colors.orange
                                  : Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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

  Widget _buildMobileStockList(List<Product> products) {
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
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.secondaryColor,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow(String method, double amount, [String? pct]) {
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
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    method,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (pct != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '($pct%)',
                    style: const TextStyle(
                      color: AppTheme.secondaryColor,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Flexible(
            child: Text(
              'KSh ${amount.toStringAsFixed(2)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
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
    Color valueColor, {
    bool isBold = false,
    double fontSize = 16,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: isBold ? Colors.white : Colors.white70,
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
              color: valueColor,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
