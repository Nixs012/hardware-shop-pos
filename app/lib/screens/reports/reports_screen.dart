import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../models/customer_payment.dart';
import '../../models/expense.dart';
import '../../models/product.dart';
import '../../models/sale.dart';
import '../../models/staff.dart';
import '../../services/firestore_service.dart';
import '../../services/sync_service.dart';
import '../../utils/theme.dart';

class ReportsScreen extends StatefulWidget {
  final Staff currentStaff;

  const ReportsScreen({super.key, required this.currentStaff});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _firestoreService = FirestoreService();

  // 0 = Daily, 1 = Weekly, 2 = Monthly, 3 = Custom
  int _selectedPeriodIndex = 0;
  DateTimeRange? _customDateRange;

  String _selectedStaffId = 'All';
  String _selectedCategory = 'All';

  String _stockSearchQuery = '';
  String _stockCategoryFilter = 'All';

  // Sort order for Top Sellers: 'revenue', 'quantity', 'profit'
  String _sellersSortBy = 'revenue';

  bool get _isAdmin => widget.currentStaff.role.toLowerCase() == 'admin';

  DateTimeRange _getSelectedRange() {
    final now = DateTime.now();
    switch (_selectedPeriodIndex) {
      case 0: // Daily: shop local calendar day (00:00 to 23:59:59.999)
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case 1: // Weekly: Monday to Sunday
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
      case 2: // Monthly: 1st of month to last calendar day
        final start = DateTime(now.year, now.month, 1);
        final lastDay = DateTime(now.year, now.month + 1, 0);
        final end = DateTime(now.year, now.month, lastDay.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
      case 3: // Custom
      default:
        if (_customDateRange != null) {
          final s = _customDateRange!.start;
          final e = _customDateRange!.end;
          return DateTimeRange(
            start: DateTime(s.year, s.month, s.day),
            end: DateTime(e.year, e.month, e.day, 23, 59, 59, 999),
          );
        }
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        return DateTimeRange(start: start, end: end);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _money(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final integerPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return 'KSh $integerPart.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    // Admin sees 4 tabs, Cashier sees 2 (Sales Summary, Stock Balance)
    final tabCount = _isAdmin ? 4 : 2;

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: AppTheme.surfaceColor,
          elevation: 0,
          title: const Text(
            'Reports & Analytics',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: 'Export CSV Report',
              onPressed: _showExportDialog,
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppTheme.primaryColor,
            labelColor: Colors.white,
            unselectedLabelColor: AppTheme.secondaryColor,
            isScrollable: !_isAdmin,
            tabs: [
              const Tab(text: 'Sales Summary'),
              if (_isAdmin) const Tab(text: 'Profit & Loss'),
              if (_isAdmin) const Tab(text: 'Top Sellers'),
              const Tab(text: 'Stock Balance'),
            ],
          ),
        ),
        body: Column(
          children: [
            _buildOfflineBanner(),
            Expanded(
              child: StreamBuilder<List<Product>>(
                stream: _firestoreService.getProductsStream(isAdmin: _isAdmin),
                builder: (context, productsSnapshot) {
                  final products = productsSnapshot.data ?? [];
                  final productMap = {for (final p in products) p.id: p};

                  return TabBarView(
                    children: [
                      _buildSalesSummaryTab(productMap),
                      if (_isAdmin) _buildProfitLossTab(productMap),
                      if (_isAdmin) _buildTopSellersTab(productMap),
                      _buildStockBalanceTab(products),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return StreamBuilder<SyncStatus>(
      stream: SyncService.instance.statusStream,
      initialData: SyncService.instance.currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status != null && !status.isOnline) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.amber.shade900.withValues(alpha: 0.85),
            child: const Row(
              children: [
                Icon(Icons.cloud_off, size: 16, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Offline Mode: Displaying locally cached data. Remote sales will sync automatically when back online.',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  // =========================================================================
  // TAB 1: SALES SUMMARY
  // =========================================================================

  Widget _buildSalesSummaryTab(Map<String, Product> productMap) {
    final range = _getSelectedRange();

    return StreamBuilder<List<Sale>>(
      stream: _firestoreService.getSalesStream(
        isAdmin: _isAdmin,
        staffId: _isAdmin ? null : widget.currentStaff.id,
      ),
      builder: (context, salesSnapshot) {
        if (salesSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (salesSnapshot.hasError) {
          return const Center(
            child: Text(
              'Error loading sales data',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        return StreamBuilder<List<CustomerPayment>>(
          stream: _firestoreService.getCustomerPaymentsStream(),
          builder: (context, paymentsSnapshot) {
            final allSales = salesSnapshot.data ?? [];
            final allPayments = paymentsSnapshot.data ?? [];

            // Filter sales by date range & secondary filters
            final filteredSales = allSales.where((sale) {
              final inRange =
                  !sale.timestamp.isBefore(range.start) &&
                  !sale.timestamp.isAfter(range.end);
              final matchesStaff =
                  _selectedStaffId == 'All' || sale.staffId == _selectedStaffId;
              final matchesCategory =
                  _selectedCategory == 'All' ||
                  sale.lineItems.any((item) {
                    final cat = productMap[item.productId]?.category ?? '';
                    return cat.toLowerCase() == _selectedCategory.toLowerCase();
                  });
              return inRange && matchesStaff && matchesCategory;
            }).toList();

            // Filter customer payments by date range
            final periodPayments = allPayments.where((payment) {
              return !payment.timestamp.isBefore(range.start) &&
                  !payment.timestamp.isAfter(range.end);
            }).toList();

            double totalRevenue = 0;
            double totalProfit = 0;
            int transactionCount = filteredSales.length;

            final Map<String, double> paymentBreakdown = {
              'Cash': 0.0,
              'M-Pesa': 0.0,
              'Card': 0.0,
              'Credit': 0.0,
            };

            for (final sale in filteredSales) {
              totalRevenue += sale.totalAmount;
              paymentBreakdown[sale.paymentMethod] =
                  (paymentBreakdown[sale.paymentMethod] ?? 0.0) +
                  sale.totalAmount;

              for (final item in sale.lineItems) {
                totalProfit += item.profit;
              }
            }

            final totalCreditSales = paymentBreakdown['Credit'] ?? 0.0;
            final totalRepayments = periodPayments.fold<double>(
              0.0,
              (sum, p) => sum + p.amount,
            );
            final outstandingPeriodCredit = totalCreditSales - totalRepayments;

            final avgTicket = transactionCount > 0
                ? (totalRevenue / transactionCount)
                : 0.0;
            final profitMargin = totalRevenue > 0
                ? (totalProfit / totalRevenue * 100)
                : 0.0;

            return LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 800;

                return SingleChildScrollView(
                  padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFilterBar(),
                      const SizedBox(height: 20),
                      if (isDesktop)
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Total Revenue',
                                value: _money(totalRevenue),
                                icon: Icons.attach_money,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            if (_isAdmin) const SizedBox(width: 16),
                            if (_isAdmin)
                              Expanded(
                                child: _buildMetricCard(
                                  title: 'Gross Profit',
                                  value: _money(totalProfit),
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
                                value: _money(avgTicket),
                                icon: Icons.shopping_bag_outlined,
                                color: Colors.purpleAccent,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _buildMetricCard(
                          title: 'Total Revenue',
                          value: _money(totalRevenue),
                          icon: Icons.attach_money,
                          color: AppTheme.primaryColor,
                        ),
                        if (_isAdmin) ...[
                          const SizedBox(height: 12),
                          _buildMetricCard(
                            title: 'Gross Profit',
                            value: _money(totalProfit),
                            icon: Icons.trending_up,
                            color: Colors.green,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Transactions',
                                value: '$transactionCount',
                                icon: Icons.receipt_long,
                                color: AppTheme.secondaryColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Average Ticket',
                                value: _money(avgTicket),
                                icon: Icons.shopping_bag_outlined,
                                color: Colors.purpleAccent,
                              ),
                            ),
                          ],
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
                              child: Column(
                                children: [
                                  _buildSalesInsightsCard(
                                    transactionCount: transactionCount,
                                    profitMargin: profitMargin,
                                    totalRevenue: totalRevenue,
                                    totalProfit: totalProfit,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildCreditCard(
                                    creditSales: totalCreditSales,
                                    repayments: totalRepayments,
                                    outstanding: outstandingPeriodCredit,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _buildPaymentBreakdownCard(
                          paymentBreakdown,
                          totalRevenue,
                        ),
                        const SizedBox(height: 16),
                        _buildSalesInsightsCard(
                          transactionCount: transactionCount,
                          profitMargin: profitMargin,
                          totalRevenue: totalRevenue,
                          totalProfit: totalProfit,
                        ),
                        const SizedBox(height: 16),
                        _buildCreditCard(
                          creditSales: totalCreditSales,
                          repayments: totalRepayments,
                          outstanding: outstandingPeriodCredit,
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // =========================================================================
  // TAB 2: PROFIT & LOSS (ADMIN ONLY)
  // =========================================================================

  Widget _buildProfitLossTab(Map<String, Product> productMap) {
    final range = _getSelectedRange();

    return StreamBuilder<List<Sale>>(
      stream: _firestoreService.getSalesStream(isAdmin: true),
      builder: (context, salesSnapshot) {
        if (salesSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (salesSnapshot.hasError) {
          return const Center(
            child: Text(
              'Error loading sales data',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        return StreamBuilder<List<Expense>>(
          stream: _firestoreService.getExpensesStream(),
          builder: (context, expensesSnapshot) {
            final sales = salesSnapshot.data ?? [];
            final expenses = expensesSnapshot.data ?? [];

            final filteredSales = sales.where((sale) {
              final inRange =
                  !sale.timestamp.isBefore(range.start) &&
                  !sale.timestamp.isAfter(range.end);
              final matchesStaff =
                  _selectedStaffId == 'All' || sale.staffId == _selectedStaffId;
              final matchesCategory =
                  _selectedCategory == 'All' ||
                  sale.lineItems.any((item) {
                    final cat = productMap[item.productId]?.category ?? '';
                    return cat.toLowerCase() == _selectedCategory.toLowerCase();
                  });
              return inRange && matchesStaff && matchesCategory;
            }).toList();

            final filteredExpenses = expenses.where((exp) {
              return !exp.date.isBefore(range.start) &&
                  !exp.date.isAfter(range.end);
            }).toList();

            double revenue = 0;
            double costOfGoodsSold = 0;

            for (final sale in filteredSales) {
              revenue += sale.totalAmount;
              for (final item in sale.lineItems) {
                costOfGoodsSold += item.unitCostAtSale * item.quantity;
              }
            }

            final totalExpenses = filteredExpenses.fold<double>(
              0.0,
              (sum, e) => sum + e.amount,
            );

            // Canonical formula from pos-domain-rules:
            // period_profit = sum(line_profit) - sum(recorded expenses)
            final grossProfit = revenue - costOfGoodsSold;
            final netProfit = grossProfit - totalExpenses;
            final netMargin = revenue > 0 ? (netProfit / revenue * 100) : 0.0;

            return LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 800;

                return SingleChildScrollView(
                  padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFilterBar(),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Period Financials',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Expense'),
                            onPressed: _showAddExpenseDialog,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // The 4 essential numbers shown together:
                      if (isDesktop)
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Period Revenue',
                                value: _money(revenue),
                                icon: Icons.trending_up,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Cost of Goods (COGS)',
                                value: _money(costOfGoodsSold),
                                icon: Icons.inventory_2_outlined,
                                color: Colors.redAccent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Operating Expenses',
                                value: _money(totalExpenses),
                                icon: Icons.receipt_long,
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Net Profit',
                                value: _money(netProfit),
                                icon: Icons.account_balance_wallet,
                                color: netProfit >= 0
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Revenue',
                                value: _money(revenue),
                                icon: Icons.trending_up,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: 'COGS',
                                value: _money(costOfGoodsSold),
                                icon: Icons.inventory_2_outlined,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Expenses',
                                value: _money(totalExpenses),
                                icon: Icons.receipt_long,
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                title: 'Net Profit',
                                value: _money(netProfit),
                                icon: Icons.account_balance_wallet,
                                color: netProfit >= 0
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Detailed breakdown card
                      Card(
                        color: Colors.white.withValues(alpha: 0.03),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: AppTheme.secondaryColor.withValues(
                              alpha: 0.15,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Income Statement Summary',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildPLRow(
                                'Gross Sales Revenue',
                                _money(revenue),
                                Colors.white,
                              ),
                              const Divider(color: Colors.white12, height: 20),
                              _buildPLRow(
                                'Cost of Goods Sold (COGS)',
                                '- ${_money(costOfGoodsSold)}',
                                Colors.redAccent,
                              ),
                              const Divider(color: Colors.white12, height: 20),
                              _buildPLRow(
                                'Gross Profit',
                                _money(grossProfit),
                                grossProfit >= 0 ? Colors.green : Colors.red,
                                isBold: true,
                              ),
                              const Divider(color: Colors.white12, height: 20),
                              _buildPLRow(
                                'Operating Expenses (Rent, Wages, Transport)',
                                '- ${_money(totalExpenses)}',
                                Colors.orange,
                              ),
                              const Divider(color: Colors.white24, height: 24),
                              _buildPLRow(
                                'Net Profit',
                                _money(netProfit),
                                netProfit >= 0 ? Colors.green : Colors.red,
                                isBold: true,
                                fontSize: 18,
                              ),
                              const Divider(color: Colors.white12, height: 20),
                              _buildPLRow(
                                'Net Profit Margin',
                                '${netMargin.toStringAsFixed(1)}%',
                                netMargin >= 15 ? Colors.green : Colors.orange,
                                isBold: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Expenses list in period
                      _buildExpensesListCard(filteredExpenses),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildExpensesListCard(List<Expense> expenses) {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recorded Expenses Ledger',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${expenses.length} record(s)',
                  style: const TextStyle(
                    color: AppTheme.secondaryColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (expenses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  'No operating expenses recorded for this period. Use "Add Expense" to log rent, transport, wages, etc.',
                  style: TextStyle(
                    color: AppTheme.secondaryColor,
                    fontSize: 13,
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: expenses.length,
                separatorBuilder: (context, index) =>
                    const Divider(color: Colors.white12),
                itemBuilder: (context, index) {
                  final exp = expenses[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.orange.withValues(alpha: 0.15),
                      child: const Icon(
                        Icons.receipt_long,
                        color: Colors.orange,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      exp.category,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${_formatDate(exp.date)}${exp.note != null && exp.note!.isNotEmpty ? ' • ${exp.note}' : ''}',
                      style: const TextStyle(
                        color: AppTheme.secondaryColor,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _money(exp.amount),
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: Colors.blueAccent,
                          ),
                          tooltip: 'Edit Expense',
                          onPressed: () => _showEditExpenseDialog(exp),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 18,
                            color: Colors.redAccent,
                          ),
                          tooltip: 'Delete Expense',
                          onPressed: () => _confirmDeleteExpense(exp),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 3: TOP & BOTTOM SELLERS (ADMIN ONLY)
  // =========================================================================

  Widget _buildTopSellersTab(Map<String, Product> productMap) {
    final range = _getSelectedRange();

    return StreamBuilder<List<Sale>>(
      stream: _firestoreService.getSalesStream(isAdmin: true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final sales = snapshot.data ?? [];

        final filteredSales = sales.where((sale) {
          final inRange =
              !sale.timestamp.isBefore(range.start) &&
              !sale.timestamp.isAfter(range.end);
          final matchesStaff =
              _selectedStaffId == 'All' || sale.staffId == _selectedStaffId;
          return inRange && matchesStaff;
        }).toList();

        // Aggregate by product
        final Map<String, _ProductPerformance> productStats = {};

        for (final sale in filteredSales) {
          for (final item in sale.lineItems) {
            final product = productMap[item.productId];
            final category = product?.category ?? 'General';

            if (_selectedCategory != 'All' &&
                category.toLowerCase() != _selectedCategory.toLowerCase()) {
              continue;
            }

            final existing = productStats.putIfAbsent(
              item.productId,
              () => _ProductPerformance(
                productId: item.productId,
                productName: product?.name ?? item.productId,
                category: category,
              ),
            );

            existing.totalQuantity += item.quantity;
            existing.totalRevenue += (item.unitPriceAtSale * item.quantity);
            existing.totalProfit += item.profit;
          }
        }

        final performanceList = productStats.values.toList();

        // Sort based on selection
        if (_sellersSortBy == 'revenue') {
          performanceList.sort(
            (a, b) => b.totalRevenue.compareTo(a.totalRevenue),
          );
        } else if (_sellersSortBy == 'quantity') {
          performanceList.sort(
            (a, b) => b.totalQuantity.compareTo(a.totalQuantity),
          );
        } else {
          // profit
          performanceList.sort(
            (a, b) => b.totalProfit.compareTo(a.totalProfit),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 800;

            return SingleChildScrollView(
              padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFilterBar(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Product Ranking',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SegmentedButton<String>(
                        style: ButtonStyle(
                          backgroundColor:
                              WidgetStateProperty.resolveWith<Color?>((states) {
                                if (states.contains(WidgetState.selected)) {
                                  return AppTheme.primaryColor;
                                }
                                return Colors.white.withValues(alpha: 0.05);
                              }),
                          foregroundColor: WidgetStateProperty.all(
                            Colors.white,
                          ),
                        ),
                        segments: const [
                          ButtonSegment<String>(
                            value: 'revenue',
                            label: Text('By Revenue'),
                          ),
                          ButtonSegment<String>(
                            value: 'quantity',
                            label: Text('By Volume'),
                          ),
                          ButtonSegment<String>(
                            value: 'profit',
                            label: Text('By Profit'),
                          ),
                        ],
                        selected: {_sellersSortBy},
                        onSelectionChanged: (set) {
                          setState(() => _sellersSortBy = set.first);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (performanceList.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(
                        child: Text(
                          'No sales recorded in this period for the selected filters.',
                          style: TextStyle(color: AppTheme.secondaryColor),
                        ),
                      ),
                    )
                  else
                    Card(
                      color: Colors.white.withValues(alpha: 0.03),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: AppTheme.secondaryColor.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: performanceList.length,
                        separatorBuilder: (context, index) =>
                            const Divider(color: Colors.white12),
                        itemBuilder: (context, index) {
                          final p = performanceList[index];
                          final rank = index + 1;
                          final margin = p.totalRevenue > 0
                              ? (p.totalProfit / p.totalRevenue * 100)
                              : 0.0;

                          return ListTile(
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: rank <= 3
                                  ? AppTheme.primaryColor.withValues(alpha: 0.3)
                                  : Colors.white10,
                              child: Text(
                                '#$rank',
                                style: TextStyle(
                                  color: rank <= 3
                                      ? AppTheme.primaryColor
                                      : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            title: Text(
                              p.productName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${p.category.isEmpty ? 'General' : p.category} • ${p.totalQuantity.toStringAsFixed(1)} units sold',
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
                                  _money(p.totalRevenue),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                if (_isAdmin)
                                  Text(
                                    'Profit: ${_money(p.totalProfit)} (${margin.toStringAsFixed(1)}%)',
                                    style: TextStyle(
                                      color: margin >= 15
                                          ? Colors.green
                                          : Colors.orange,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
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

  // =========================================================================
  // TAB 4: STOCK BALANCE
  // =========================================================================

  Widget _buildStockBalanceTab(List<Product> products) {
    final categories = <String>{'All'};
    for (final p in products) {
      if (p.category.isNotEmpty) categories.add(p.category);
    }

    final filtered = products.where((p) {
      final matchesQuery =
          _stockSearchQuery.isEmpty ||
          p.name.toLowerCase().contains(_stockSearchQuery) ||
          p.sku.toLowerCase().contains(_stockSearchQuery);
      final matchesCat =
          _stockCategoryFilter == 'All' ||
          p.category.toLowerCase() == _stockCategoryFilter.toLowerCase();
      return matchesQuery && matchesCat;
    }).toList();

    final lowStockCount = products
        .where((p) => p.quantityOnHand <= p.lowStockThreshold)
        .length;

    double totalValuation = 0.0;
    if (_isAdmin) {
      for (final p in products) {
        totalValuation += (p.quantityOnHand * p.costPrice);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        return Column(
          children: [
            _buildStockToolbar(
              categories.toList(),
              isDesktop,
              lowStockCount,
              totalValuation,
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No inventory records match the search filter.',
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
  }

  Widget _buildStockToolbar(
    List<String> categories,
    bool isDesktop,
    int lowStockCount,
    double totalValuation,
  ) {
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
      child: Column(
        children: [
          if (_isAdmin || lowStockCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  if (lowStockCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber,
                            color: Colors.orange,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$lowStockCount item(s) low on stock',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_isAdmin) ...[
                    const Spacer(),
                    Text(
                      'Total Inventory Valuation: ${_money(totalValuation)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  onChanged: (val) => setState(
                    () => _stockSearchQuery = val.trim().toLowerCase(),
                  ),
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
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _stockCategoryFilter,
                      dropdownColor: AppTheme.surfaceColor,
                      isExpanded: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: categories.map((cat) {
                        return DropdownMenuItem<String>(
                          value: cat,
                          child: Text(cat),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _stockCategoryFilter = val);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopStockTable(List<Product> products) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Card(
        color: Colors.white.withValues(alpha: 0.03),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: AppTheme.secondaryColor.withValues(alpha: 0.15),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          child: DataTable(
            columnSpacing: 24,
            headingTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            columns: [
              const DataColumn(label: Text('Product Name / SKU')),
              const DataColumn(label: Text('Category')),
              const DataColumn(label: Text('Quantity on Hand')),
              const DataColumn(label: Text('Threshold')),
              if (_isAdmin) const DataColumn(label: Text('Cost Price')),
              const DataColumn(label: Text('Selling Price')),
              const DataColumn(label: Text('Status')),
            ],
            rows: products.map((product) {
              final isLow =
                  product.quantityOnHand <= product.lowStockThreshold &&
                  product.quantityOnHand > 0;
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
                        Text(
                          product.sku,
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
                  if (_isAdmin)
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _money(product.costPrice),
                            style: const TextStyle(color: Colors.white70),
                          ),
                          if (product.costPriceEstimated)
                            const Tooltip(
                              message: 'Estimated Cost Price',
                              child: Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  DataCell(
                    Text(
                      _money(product.sellingPrice),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
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
        final isLowStock =
            product.quantityOnHand <= product.lowStockThreshold &&
            product.quantityOnHand > 0;
        final isOut = product.quantityOnHand <= 0;

        return Card(
          color: Colors.white.withValues(alpha: 0.05),
          margin: const EdgeInsets.only(bottom: 12.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isOut
                  ? Colors.red.withValues(alpha: 0.5)
                  : isLowStock
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
              'SKU: ${product.sku}  •  ${product.category.isEmpty ? 'General' : product.category}\nSelling: ${_money(product.sellingPrice)}${_isAdmin ? ' • Cost: ${_money(product.costPrice)}' : ''}',
              style: const TextStyle(
                color: AppTheme.secondaryColor,
                fontSize: 12,
              ),
            ),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${product.quantityOnHand} ${product.unit}',
                  style: TextStyle(
                    color: isOut
                        ? Colors.redAccent
                        : isLowStock
                        ? Colors.orange
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  isOut
                      ? 'Out of Stock'
                      : isLowStock
                      ? 'Low Stock'
                      : 'In Stock',
                  style: TextStyle(
                    color: isOut
                        ? Colors.redAccent
                        : isLowStock
                        ? Colors.orange
                        : Colors.green,
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

  // =========================================================================
  // SHARED FILTER BAR & COMPONENTS
  // =========================================================================

  Widget _buildFilterBar() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<int>(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith<Color?>((
                      states,
                    ) {
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
                    ButtonSegment<int>(value: 3, label: Text('Custom Range')),
                  ],
                  selected: {_selectedPeriodIndex},
                  onSelectionChanged: (Set<int> newSelection) async {
                    final selected = newSelection.first;
                    if (selected == 3) {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                        initialDateRange:
                            _customDateRange ??
                            DateTimeRange(
                              start: DateTime.now().subtract(
                                const Duration(days: 7),
                              ),
                              end: DateTime.now(),
                            ),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedPeriodIndex = 3;
                          _customDateRange = picked;
                        });
                      }
                    } else {
                      setState(() {
                        _selectedPeriodIndex = selected;
                      });
                    }
                  },
                ),
              ),
            ),
            if (_selectedPeriodIndex == 3 && _customDateRange != null) ...[
              const SizedBox(width: 8),
              ActionChip(
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                label: Text(
                  '${_formatDate(_customDateRange!.start)} - ${_formatDate(_customDateRange!.end)}',
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 12,
                  ),
                ),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                    initialDateRange: _customDateRange,
                  );
                  if (picked != null) {
                    setState(() => _customDateRange = picked);
                  }
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // Secondary dimension filters: Staff & Category
        Row(
          children: [
            if (_isAdmin)
              Expanded(
                child: StreamBuilder<List<Staff>>(
                  stream: _firestoreService.getStaffStream(),
                  builder: (context, snapshot) {
                    final staffList = snapshot.data ?? [];
                    return Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedStaffId,
                          isExpanded: true,
                          dropdownColor: AppTheme.surfaceColor,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'All',
                              child: Text('Staff: All Cashiers'),
                            ),
                            ...staffList.map((s) {
                              return DropdownMenuItem(
                                value: s.id,
                                child: Text('Staff: ${s.name}'),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedStaffId = val);
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_isAdmin) const SizedBox(width: 12),
            Expanded(
              child: StreamBuilder<List<Product>>(
                stream: _firestoreService.getProductsStream(),
                builder: (context, snapshot) {
                  final products = snapshot.data ?? [];
                  final categories = <String>{'All'};
                  for (final p in products) {
                    if (p.category.isNotEmpty) categories.add(p.category);
                  }

                  return Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedCategory,
                        isExpanded: true,
                        dropdownColor: AppTheme.surfaceColor,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        items: categories.map((cat) {
                          return DropdownMenuItem(
                            value: cat,
                            child: Text(
                              cat == 'All' ? 'Category: All' : 'Cat: $cat',
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedCategory = val);
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
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
              radius: 20,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
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
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
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
              'Performance Overview',
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
              _money(
                transactionCount > 0 ? totalRevenue / transactionCount : 0.0,
              ),
              Colors.purpleAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditCard({
    required double creditSales,
    required double repayments,
    required double outstanding,
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
              'Credit & Khata Tracking',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            _buildInsightRow(
              'Period Credit Sales',
              _money(creditSales),
              Colors.orange,
            ),
            const Divider(color: Colors.white12, height: 16),
            _buildInsightRow(
              'Repayments Collected',
              _money(repayments),
              Colors.green,
            ),
            const Divider(color: Colors.white12, height: 16),
            _buildInsightRow(
              'Outstanding Balance',
              _money(outstanding),
              outstanding > 0 ? Colors.redAccent : Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow(String method, double amount, [String? pct]) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
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
              _money(amount),
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
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPLRow(
    String label,
    String value,
    Color valueColor, {
    bool isBold = false,
    double fontSize = 15,
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

  // =========================================================================
  // DIALOGS: ADD EXPENSE & EXPORT CSV
  // =========================================================================

  Future<void> _showAddExpenseDialog() async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String category = 'Rent';
    DateTime expenseDate = DateTime.now();

    final categories = [
      'Rent',
      'Transport / Delivery',
      'Wages / Salaries',
      'Electricity / Water',
      'Repairs & Maintenance',
      'Licenses & Permits',
      'Miscellaneous',
    ];

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor,
            title: const Text(
              'Record Operating Expense',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Category',
                    style: TextStyle(
                      color: AppTheme.secondaryColor,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: category,
                        isExpanded: true,
                        dropdownColor: AppTheme.surfaceColor,
                        style: const TextStyle(color: Colors.white),
                        items: categories.map((cat) {
                          return DropdownMenuItem(value: cat, child: Text(cat));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => category = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Amount (KSh)',
                      hintText: 'e.g. 5000',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Description / Note (Optional)',
                      hintText: 'e.g. Warehouse monthly rent',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Date: ${_formatDate(expenseDate)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: const Text('Change'),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: expenseDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setDialogState(() => expenseDate = picked);
                          }
                        },
                      ),
                    ],
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
                onPressed: () async {
                  final amount = double.tryParse(amountController.text.trim());
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid expense amount.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  final expense = Expense(
                    id: const Uuid().v4(),
                    date: expenseDate,
                    category: category,
                    amount: amount,
                    note: noteController.text.trim().isEmpty
                        ? null
                        : noteController.text.trim(),
                  );

                  await _firestoreService.addExpense(expense);
                  if (!dialogCtx.mounted) return;
                  Navigator.pop(dialogCtx);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Expense logged successfully.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                child: const Text('Save Expense'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteExpense(Expense expense) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Delete Expense?'),
        content: Text(
          'Are you sure you want to delete ${expense.category} (${_money(expense.amount)})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firestoreService.deleteExpense(expense.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Expense deleted.')));
      }
    }
  }

  Future<void> _showEditExpenseDialog(Expense expense) async {
    final amountController = TextEditingController(
      text: expense.amount.toStringAsFixed(2),
    );
    final noteController = TextEditingController(text: expense.note ?? '');
    String category = expense.category;
    DateTime expenseDate = expense.date;

    final categories = [
      'Rent',
      'Transport / Delivery',
      'Wages / Salaries',
      'Electricity / Water',
      'Repairs & Maintenance',
      'Licenses & Permits',
      'Miscellaneous',
    ];

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.surfaceColor,
            title: const Text(
              'Edit Expense',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Category',
                    style: TextStyle(
                      color: AppTheme.secondaryColor,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: category,
                        isExpanded: true,
                        dropdownColor: AppTheme.surfaceColor,
                        style: const TextStyle(color: Colors.white),
                        items: categories.map((cat) {
                          return DropdownMenuItem(value: cat, child: Text(cat));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => category = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Amount (KSh)',
                      hintText: 'e.g. 5000',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Description / Note (Optional)',
                      hintText: 'e.g. Warehouse monthly rent',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Date: ${_formatDate(expenseDate)}',
                        style: const TextStyle(
                          color: AppTheme.secondaryColor,
                          fontSize: 13,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: expenseDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setDialogState(() => expenseDate = picked);
                          }
                        },
                        icon: const Icon(
                          Icons.calendar_today,
                          size: 16,
                          color: AppTheme.primaryColor,
                        ),
                        label: const Text(
                          'Change',
                          style: TextStyle(color: AppTheme.primaryColor),
                        ),
                      ),
                    ],
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
                onPressed: () async {
                  final amount = double.tryParse(amountController.text.trim());
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid expense amount.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  final updated = Expense(
                    id: expense.id,
                    date: expenseDate,
                    category: category,
                    amount: amount,
                    note: noteController.text.trim().isEmpty
                        ? null
                        : noteController.text.trim(),
                  );

                  await _firestoreService.updateExpense(updated);
                  if (!dialogCtx.mounted) return;
                  Navigator.pop(dialogCtx);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Expense updated successfully.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                child: const Text('Save Expense'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showExportDialog() async {
    final range = _getSelectedRange();
    final periodName = _selectedPeriodIndex == 0
        ? 'Daily'
        : _selectedPeriodIndex == 1
        ? 'Weekly'
        : _selectedPeriodIndex == 2
        ? 'Monthly'
        : 'Custom';

    final csvBuffer = StringBuffer();
    csvBuffer.writeln('SHAMAMO HARDWARE POS - REPORT EXPORT');
    csvBuffer.writeln(
      'Period: $periodName (${_formatDate(range.start)} to ${_formatDate(range.end)})',
    );
    csvBuffer.writeln('Generated: ${DateTime.now().toLocal()}');
    csvBuffer.writeln('');

    // Fetch latest sales and products for export
    final sales = await _firestoreService
        .getSalesStream(isAdmin: _isAdmin)
        .first;
    final filteredSales = sales.where((sale) {
      return !sale.timestamp.isBefore(range.start) &&
          !sale.timestamp.isAfter(range.end);
    }).toList();

    double revenue = 0;
    double cogs = 0;
    for (final s in filteredSales) {
      revenue += s.totalAmount;
      for (final it in s.lineItems) {
        cogs += (it.unitCostAtSale * it.quantity);
      }
    }

    csvBuffer.writeln('--- FINANCIAL SUMMARY ---');
    csvBuffer.writeln('Metric,Amount (KSh)');
    csvBuffer.writeln('Total Sales Revenue,${revenue.toStringAsFixed(2)}');
    if (_isAdmin) {
      csvBuffer.writeln('Cost of Goods Sold (COGS),${cogs.toStringAsFixed(2)}');
      csvBuffer.writeln('Gross Profit,${(revenue - cogs).toStringAsFixed(2)}');
    }
    csvBuffer.writeln('Total Transactions,${filteredSales.length}');
    csvBuffer.writeln('');

    csvBuffer.writeln('--- SALES TRANSACTIONS ---');
    csvBuffer.writeln(
      'Sale ID,Date,Staff ID,Payment Method,Items Count,Total Amount',
    );
    for (final s in filteredSales) {
      csvBuffer.writeln(
        '${s.id},${s.timestamp.toIso8601String()},${s.staffId},${s.paymentMethod},${s.lineItems.length},${s.totalAmount.toStringAsFixed(2)}',
      );
    }

    final csvText = csvBuffer.toString();

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Export Report (CSV)'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Report data has been formatted as standard CSV for accountants and spreadsheets:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                height: 180,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    csvText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy CSV to Clipboard'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvText));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('CSV report copied to clipboard!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProductPerformance {
  final String productId;
  final String productName;
  final String category;
  double totalQuantity = 0;
  double totalRevenue = 0;
  double totalProfit = 0;

  _ProductPerformance({
    required this.productId,
    required this.productName,
    required this.category,
  });
}
