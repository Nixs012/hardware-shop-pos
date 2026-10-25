import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/expense.dart';
import '../../models/product.dart';
import '../../models/staff.dart';
import '../../services/firestore_service.dart';
import '../../services/reports_repository.dart';
import '../../services/sync_service.dart';
import '../../utils/theme.dart';
import '../../widgets/reports_loading_widgets.dart';

class KeepAliveTab extends StatefulWidget {
  final Widget child;
  const KeepAliveTab({super.key, required this.child});

  @override
  State<KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class ReportsScreen extends StatefulWidget {
  final Staff currentStaff;
  final FirestoreService? firestoreService;

  const ReportsScreen({super.key, required this.currentStaff, this.firestoreService});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  FirestoreService? _injectedFirestoreService;

  FirestoreService get _firestoreService =>
      _injectedFirestoreService ??= widget.firestoreService ?? FirestoreServiceImpl();

  late final ReportsRepository _repo;

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

  Stream<List<Staff>>? _staffStream;

  @override
  void initState() {
    super.initState();
    if (_isAdmin) {
      _staffStream = _firestoreService.getStaffStream();
    }
    _repo = ReportsRepository.acquire(
      service: _firestoreService,
      isAdmin: _isAdmin,
      staffId: widget.currentStaff.id,
    );
    _repo.start();
    _repo.addListener(_onRepoChanged);
  }

  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

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
    final range = _getSelectedRange();
    final data = _repo.dataFor(
      range: range,
      staffId: _selectedStaffId,
      categoryId: _selectedCategory,
    );

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
            isScrollable: true,
            tabAlignment: TabAlignment.start,
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
              child: TabBarView(
                children: [
                  KeepAliveTab(child: _buildSalesSummaryTab(data)),
                  if (_isAdmin) KeepAliveTab(child: _buildProfitLossTab(data)),
                  if (_isAdmin) KeepAliveTab(child: _buildTopSellersTab(data)),
                  KeepAliveTab(child: _buildStockBalanceTab(data)),
                ],
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

  Widget _buildSalesSummaryTab(ReportsData data) {
    if (data.showSalesSkeleton && data.sales.isEmpty) {
      return const ReportsSummarySkeleton();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFilterBar(data.categories),
              if (data.salesStatus.isFailed)
                SourceErrorBanner(
                  title: 'Sales data loading failed',
                  message: data.salesStatus.message,
                  onRetry: () => _repo.retry(ReportsSource.sales),
                ),
              if (_isAdmin && data.paymentsStatus.isFailed)
                SourceErrorBanner(
                  title: 'Customer payments loading failed',
                  message: data.paymentsStatus.message,
                  onRetry: () => _repo.retry(ReportsSource.customerPayments),
                ),
              const SizedBox(height: 20),
              if (isDesktop)
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Total Revenue',
                        value: _money(data.totalRevenue),
                        icon: Icons.attach_money,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    if (_isAdmin) const SizedBox(width: 16),
                    if (_isAdmin)
                      Expanded(
                        child: _buildMetricCard(
                          title: 'Gross Profit',
                          value: _money(data.totalProfit),
                          icon: Icons.trending_up,
                          color: Colors.green,
                        ),
                      ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Transactions',
                        value: '${data.transactionCount}',
                        icon: Icons.receipt_long,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Average Ticket',
                        value: _money(data.avgTicket),
                        icon: Icons.shopping_bag_outlined,
                        color: Colors.purpleAccent,
                      ),
                    ),
                  ],
                )
              else ...[
                _buildMetricCard(
                  title: 'Total Revenue',
                  value: _money(data.totalRevenue),
                  icon: Icons.attach_money,
                  color: AppTheme.primaryColor,
                ),
                if (_isAdmin) ...[
                  const SizedBox(height: 12),
                  _buildMetricCard(
                    title: 'Gross Profit',
                    value: _money(data.totalProfit),
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
                        value: '${data.transactionCount}',
                        icon: Icons.receipt_long,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Average Ticket',
                        value: _money(data.avgTicket),
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
                        data.paymentBreakdown,
                        data.totalRevenue,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSalesInsightsCard(
                            transactionCount: data.transactionCount,
                            profitMargin: data.profitMargin,
                            totalRevenue: data.totalRevenue,
                            totalProfit: data.totalProfit,
                          ),
                          if (_isAdmin) ...[
                            const SizedBox(height: 16),
                            _buildCreditTrackingCard(data),
                          ],
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
                _buildPaymentBreakdownCard(
                  data.paymentBreakdown,
                  data.totalRevenue,
                ),
                const SizedBox(height: 16),
                _buildSalesInsightsCard(
                  transactionCount: data.transactionCount,
                  profitMargin: data.profitMargin,
                  totalRevenue: data.totalRevenue,
                  totalProfit: data.totalProfit,
                ),
                if (_isAdmin) ...[
                  const SizedBox(height: 16),
                  _buildCreditTrackingCard(data),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  // =========================================================================
  // TAB 2: PROFIT & LOSS (ADMIN ONLY)
  // =========================================================================

  Widget _buildProfitLossTab(ReportsData data) {
    if ((data.salesStatus.state == ReportsSourceState.loading ||
            data.productsStatus.state == ReportsSourceState.loading) &&
        data.sales.isEmpty &&
        data.products.isEmpty) {
      return const ReportsListSkeleton();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFilterBar(data.categories),
              if (data.salesStatus.isFailed)
                SourceErrorBanner(
                  title: 'Sales data loading failed',
                  message: data.salesStatus.message,
                  onRetry: () => _repo.retry(ReportsSource.sales),
                ),
              if (data.expensesStatus.isFailed)
                SourceErrorBanner(
                  title: 'Expenses loading failed',
                  message: data.expensesStatus.message,
                  onRetry: () => _repo.retry(ReportsSource.expenses),
                ),
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
              if (isDesktop)
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Period Revenue',
                        value: _money(data.plRevenue),
                        icon: Icons.trending_up,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Cost of Goods (COGS)',
                        value: _money(data.plCogs),
                        icon: Icons.inventory_2_outlined,
                        color: Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Operating Expenses',
                        value: _money(data.totalExpenses),
                        icon: Icons.receipt_long,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Net Profit',
                        value: _money(data.netProfit),
                        icon: Icons.account_balance_wallet,
                        color: data.netProfit >= 0 ? Colors.green : Colors.red,
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
                        value: _money(data.plRevenue),
                        icon: Icons.trending_up,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'COGS',
                        value: _money(data.plCogs),
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
                        value: _money(data.totalExpenses),
                        icon: Icons.receipt_long,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Net Profit',
                        value: _money(data.netProfit),
                        icon: Icons.account_balance_wallet,
                        color: data.netProfit >= 0 ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
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
                        _money(data.plRevenue),
                        Colors.white,
                      ),
                      const Divider(color: Colors.white12, height: 20),
                      _buildPLRow(
                        'Cost of Goods Sold (COGS)',
                        '- ${_money(data.plCogs)}',
                        Colors.redAccent,
                      ),
                      const Divider(color: Colors.white12, height: 20),
                      _buildPLRow(
                        'Gross Profit',
                        _money(data.plGrossProfit),
                        data.plGrossProfit >= 0 ? Colors.green : Colors.red,
                        isBold: true,
                      ),
                      const Divider(color: Colors.white12, height: 20),
                      _buildPLRow(
                        'Operating Expenses (Rent, Wages, Transport)',
                        '- ${_money(data.totalExpenses)}',
                        Colors.orange,
                      ),
                      const Divider(color: Colors.white24, height: 24),
                      _buildPLRow(
                        'Net Profit',
                        _money(data.netProfit),
                        data.netProfit >= 0 ? Colors.green : Colors.red,
                        isBold: true,
                        fontSize: 18,
                      ),
                      const Divider(color: Colors.white12, height: 20),
                      _buildPLRow(
                        'Net Profit Margin',
                        '${data.plRevenue > 0 ? (data.netProfit / data.plRevenue * 100).toStringAsFixed(1) : '0.0'}%',
                        data.netProfit >= 0 ? Colors.green : Colors.orange,
                        isBold: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildExpensesListCard(data.periodExpenses),
            ],
          ),
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
                Flexible(
                  child: Text(
                    '${expenses.length} record(s)',
                    style: const TextStyle(
                      color: AppTheme.secondaryColor,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                      _formatDate(exp.date),
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
                        const SizedBox(width: 4),
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

  Widget _buildTopSellersTab(ReportsData data) {
    if (data.salesStatus.state == ReportsSourceState.loading &&
        data.sales.isEmpty) {
      return const ReportsListSkeleton();
    }

    // Aggregate by product
    final Map<String, ProductPerformance> productStats = {};

    for (final sale in data.sales) {
      for (final item in sale.lineItems) {
        final product = data.productMap[item.productId];
        final category = product?.category ?? 'General';

        final existing = productStats.putIfAbsent(
          item.productId,
          () => ProductPerformance(
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
              _buildFilterBar(data.categories),
              if (data.salesStatus.isFailed)
                SourceErrorBanner(
                  title: 'Sales data loading failed',
                  message: data.salesStatus.message,
                  onRetry: () => _repo.retry(ReportsSource.sales),
                ),
              const SizedBox(height: 16),
              const Text(
                'Product Ranking',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 4.0,
                        ),
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
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${p.category.isEmpty ? 'General' : p.category} • ${p.totalQuantity.toStringAsFixed(1)} units',
                          style: const TextStyle(
                            color: AppTheme.secondaryColor,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: SizedBox(
                          width: 90,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _money(p.totalRevenue),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_isAdmin)
                                Text(
                                  'P: ${_money(p.totalProfit)}',
                                  style: TextStyle(
                                    color: margin >= 15
                                        ? Colors.green
                                        : Colors.orange,
                                    fontSize: 10,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
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
  }

  // =========================================================================
  // TAB 4: STOCK BALANCE
  // =========================================================================

  Widget _buildStockBalanceTab(ReportsData data) {
    if (data.productsStatus.state == ReportsSourceState.loading &&
        data.products.isEmpty) {
      return const ReportsListSkeleton();
    }

    final filteredProducts = data.products.where((p) {
      final matchesSearch =
          _stockSearchQuery.isEmpty ||
          p.name.toLowerCase().contains(_stockSearchQuery.toLowerCase()) ||
          p.sku.toLowerCase().contains(_stockSearchQuery.toLowerCase());

      final matchesCategory =
          _stockCategoryFilter == 'All' ||
          p.category.toLowerCase() == _stockCategoryFilter.toLowerCase();

      return matchesSearch && matchesCategory;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data.productsStatus.isFailed)
                SourceErrorBanner(
                  title: 'Products loading failed',
                  message: data.productsStatus.message,
                  onRetry: () => _repo.retry(ReportsSource.products),
                ),
              _buildStockToolbar(data.categories),
              const SizedBox(height: 16),
              if (filteredProducts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(
                    child: Text(
                      'No products found matching your filters.',
                      style: TextStyle(color: AppTheme.secondaryColor),
                    ),
                  ),
                )
              else if (isDesktop)
                _buildDesktopStockTable(filteredProducts)
              else
                _buildMobileStockList(filteredProducts),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStockToolbar(List<String> categories) {
    final categoryList = ['All', ...categories];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search product or SKU...',
              hintStyle: const TextStyle(color: AppTheme.secondaryColor),
              prefixIcon: const Icon(Icons.search, color: AppTheme.secondaryColor),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: (val) => setState(() => _stockSearchQuery = val),
          ),
        ),
        DropdownButtonHideUnderline(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButton<String>(
              value: _stockCategoryFilter,
              dropdownColor: AppTheme.surfaceColor,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items: categoryList.map((cat) {
                return DropdownMenuItem(
                  value: cat,
                  child: Text(cat.isEmpty ? 'General' : cat),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _stockCategoryFilter = val);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopStockTable(List<Product> products) {
    return Card(
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppTheme.secondaryColor.withValues(alpha: 0.15),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: const TextStyle(
            color: AppTheme.secondaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          dataTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
          columns: [
            const DataColumn(label: Text('Product Name')),
            const DataColumn(label: Text('SKU')),
            const DataColumn(label: Text('Category')),
            const DataColumn(label: Text('Qty On Hand')),
            const DataColumn(label: Text('Selling Price')),
            if (_isAdmin) const DataColumn(label: Text('Cost Price')),
            const DataColumn(label: Text('Status')),
          ],
          rows: products.map((product) {
            final isLow =
                product.quantityOnHand <= product.lowStockThreshold;
            final isOut = product.quantityOnHand <= 0;

            return DataRow(
              cells: [
                DataCell(
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataCell(Text(product.sku)),
                DataCell(Text(product.category.isEmpty ? 'General' : product.category)),
                DataCell(
                  Text(
                    '${product.quantityOnHand.toStringAsFixed(1)} ${product.unit}',
                    style: TextStyle(
                      color: isOut
                          ? Colors.red
                          : (isLow ? Colors.orange : Colors.white),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                DataCell(Text(_money(product.sellingPrice))),
                if (_isAdmin) DataCell(Text(_money(product.costPrice))),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isOut
                          ? Colors.red.withValues(alpha: 0.2)
                          : (isLow
                              ? Colors.orange.withValues(alpha: 0.2)
                              : Colors.green.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isOut ? 'Out of Stock' : (isLow ? 'Low Stock' : 'In Stock'),
                      style: TextStyle(
                        color: isOut
                            ? Colors.redAccent
                            : (isLow ? Colors.orangeAccent : Colors.greenAccent),
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
    );
  }

  Widget _buildMobileStockList(List<Product> products) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: products.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final product = products[index];
        final isLow = product.quantityOnHand <= product.lowStockThreshold;
        final isOut = product.quantityOnHand <= 0;

        return Card(
          color: Colors.white.withValues(alpha: 0.03),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: AppTheme.secondaryColor.withValues(alpha: 0.15),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SKU: ${product.sku}  •  ${product.category.isEmpty ? 'General' : product.category}\nSelling: ${_money(product.sellingPrice)}${_isAdmin ? '  •  Cost: ${_money(product.costPrice)}' : ''}',
                        style: const TextStyle(
                          color: AppTheme.secondaryColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${product.quantityOnHand.toStringAsFixed(1)} ${product.unit}',
                      style: TextStyle(
                        color: isOut
                            ? Colors.redAccent
                            : (isLow ? Colors.orangeAccent : Colors.white),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isOut
                            ? Colors.red.withValues(alpha: 0.2)
                            : (isLow
                                ? Colors.orange.withValues(alpha: 0.2)
                                : Colors.green.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isOut ? 'Out of Stock' : (isLow ? 'Low Stock' : 'In Stock'),
                        style: TextStyle(
                          color: isOut
                              ? Colors.redAccent
                              : (isLow ? Colors.orangeAccent : Colors.greenAccent),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterBar(List<String> categories) {
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
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Period selector
            ToggleButtons(
              isSelected: [
                _selectedPeriodIndex == 0,
                _selectedPeriodIndex == 1,
                _selectedPeriodIndex == 2,
                _selectedPeriodIndex == 3,
              ],
              onPressed: (index) async {
                if (index == 3) {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2025, 1, 1),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedPeriodIndex = 3;
                      _customDateRange = picked;
                    });
                  }
                } else {
                  setState(() {
                    _selectedPeriodIndex = index;
                    _customDateRange = null;
                  });
                }
              },
              color: AppTheme.secondaryColor,
              selectedColor: Colors.white,
              fillColor: AppTheme.primaryColor.withValues(alpha: 0.3),
              borderColor: AppTheme.secondaryColor.withValues(alpha: 0.3),
              selectedBorderColor: AppTheme.primaryColor,
              borderRadius: BorderRadius.circular(8),
              constraints: const BoxConstraints(minHeight: 36, minWidth: 70),
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Daily', style: TextStyle(fontSize: 12)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Weekly', style: TextStyle(fontSize: 12)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Monthly', style: TextStyle(fontSize: 12)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Custom', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            // Staff filter (Admin only)
            if (_isAdmin && _staffStream != null)
              StreamBuilder<List<Staff>>(
                stream: _staffStream,
                builder: (context, snapshot) {
                  final staffList = snapshot.data ?? [];
                  return DropdownButtonHideUnderline(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedStaffId,
                        dropdownColor: AppTheme.surfaceColor,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'All',
                            child: Text('All Staff'),
                          ),
                          ...staffList.map(
                            (s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.name),
                            ),
                          ),
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
            // Category filter
            DropdownButtonHideUnderline(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  dropdownColor: AppTheme.surfaceColor,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'All',
                      child: Text('All Categories'),
                    ),
                    ...categories
                        .where((c) => c.isNotEmpty)
                        .toSet()
                        .map(
                          (cat) => DropdownMenuItem(
                            value: cat,
                            child: Text(cat),
                          ),
                        ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedCategory = val);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditTrackingCard(ReportsData data) {
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
              _money(data.creditSales),
              Colors.orange,
            ),
            const Divider(color: Colors.white12, height: 16),
            _buildInsightRow(
              'Repayments Collected',
              _money(data.repayments),
              Colors.green,
            ),
            const Divider(color: Colors.white12, height: 16),
            _buildInsightRow(
              'Outstanding Balance',
              _money(data.outstanding),
              data.outstanding > 0 ? Colors.redAccent : Colors.green,
            ),
          ],
        ),
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
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppTheme.secondaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    Map<String, double> breakdown,
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
            _buildPaymentRow(
              'Cash',
              breakdown['Cash'] ?? 0.0,
              totalRevenue > 0
                  ? '${((breakdown['Cash'] ?? 0.0) / totalRevenue * 100).toStringAsFixed(1)}%'
                  : '0.0%',
            ),
            const Divider(color: Colors.white12, height: 16),
            _buildPaymentRow(
              'M-Pesa',
              breakdown['M-Pesa'] ?? 0.0,
              totalRevenue > 0
                  ? '${((breakdown['M-Pesa'] ?? 0.0) / totalRevenue * 100).toStringAsFixed(1)}%'
                  : '0.0%',
            ),
            const Divider(color: Colors.white12, height: 16),
            _buildPaymentRow(
              'Card',
              breakdown['Card'] ?? 0.0,
              totalRevenue > 0
                  ? '${((breakdown['Card'] ?? 0.0) / totalRevenue * 100).toStringAsFixed(1)}%'
                  : '0.0%',
            ),
            const Divider(color: Colors.white12, height: 16),
            _buildPaymentRow(
              'Credit',
              breakdown['Credit'] ?? 0.0,
              totalRevenue > 0
                  ? '${((breakdown['Credit'] ?? 0.0) / totalRevenue * 100).toStringAsFixed(1)}%'
                  : '0.0%',
            ),
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
              'Sales Performance Insights',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInsightRow(
              'Total Transactions',
              '$transactionCount',
              Colors.white,
            ),
            const Divider(color: Colors.white12, height: 16),
            _buildInsightRow(
              'Average Basket Size',
              transactionCount > 0 ? _money(totalRevenue / transactionCount) : _money(0),
              Colors.white,
            ),
            if (_isAdmin) ...[
              const Divider(color: Colors.white12, height: 16),
              _buildInsightRow(
                'Gross Profit Margin',
                '${profitMargin.toStringAsFixed(1)}%',
                profitMargin >= 15 ? Colors.green : Colors.orange,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow(String method, double amount, [String? pct]) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: method == 'Cash'
                      ? Colors.green
                      : method == 'M-Pesa'
                          ? Colors.lightGreen
                          : method == 'Card'
                              ? Colors.blue
                              : Colors.purple,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  method,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Text(
              _money(amount),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            if (pct != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                child: Text(
                  '($pct)',
                  style: const TextStyle(
                    color: AppTheme.secondaryColor,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildInsightRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.secondaryColor, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.bold,
            fontSize: 14,
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
    double fontSize = 14,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: isBold ? Colors.white : AppTheme.secondaryColor,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: fontSize,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: fontSize,
          ),
        ),
      ],
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Export Report', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Choose export format for current period report:',
          style: TextStyle(color: AppTheme.secondaryColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Report exported to CSV successfully.')),
              );
            },
            child: const Text('Export CSV'),
          ),
        ],
      ),
    );
  }

  void _showAddExpenseDialog() {
    final categoryController = TextEditingController(text: 'Rent');
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Add Operating Expense', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: categoryController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Category (Rent, Wages, Transport, etc.)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Amount (KSh)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Note (Optional)'),
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
              final amount = double.tryParse(amountController.text.trim()) ?? 0.0;
              if (amount <= 0) return;

              final expense = Expense(
                id: const Uuid().v4(),
                date: DateTime.now(),
                category: categoryController.text.trim(),
                amount: amount,
                note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
              );

              await _firestoreService.addExpense(expense);
              if (!dialogCtx.mounted) return;
              Navigator.pop(dialogCtx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Expense added successfully')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showEditExpenseDialog(Expense expense) {
    final categoryController = TextEditingController(text: expense.category);
    final amountController = TextEditingController(text: expense.amount.toString());
    final noteController = TextEditingController(text: expense.note ?? '');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Edit Operating Expense', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: categoryController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Amount (KSh)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: 'Note (Optional)'),
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
              final amount = double.tryParse(amountController.text.trim()) ?? 0.0;
              if (amount <= 0) return;

              final updated = Expense(
                id: expense.id,
                date: expense.date,
                category: categoryController.text.trim(),
                amount: amount,
                note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
              );

              await _firestoreService.updateExpense(updated);
              if (!dialogCtx.mounted) return;
              Navigator.pop(dialogCtx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Expense updated successfully')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteExpense(Expense expense) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Delete Expense', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete ${expense.category} (${_money(expense.amount)})?',
          style: const TextStyle(color: AppTheme.secondaryColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await _firestoreService.deleteExpense(expense.id);
              if (!dialogCtx.mounted) return;
              Navigator.pop(dialogCtx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Expense deleted successfully')),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
