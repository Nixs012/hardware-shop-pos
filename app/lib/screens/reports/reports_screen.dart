import 'package:flutter/material.dart';

import '../../models/product.dart';
import '../../models/sale.dart';
import '../../models/staff.dart';
import '../../services/firestore_service.dart';
import '../../services/reports_repository.dart';
import '../../services/sync_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/export_button.dart';
import '../../widgets/filter_pill.dart';
import '../../widgets/reports_loading_widgets.dart';
import '../../widgets/segmented_period_control.dart';
import '../../widgets/section_card.dart';
import '../../widgets/sales_trend_chart.dart';
import '../../widgets/search_field.dart';
import '../../widgets/stock_badge.dart';
import '../../widgets/summary_card.dart';

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
      _injectedFirestoreService ??= widget.firestoreService ??
          FirestoreServiceImpl(widget.currentStaff.shopId);

  late final ReportsRepository _repo;
  late final TextEditingController _stockSearchController;

  // 0 = Daily, 1 = Weekly, 2 = Monthly, 3 = Custom
  int _selectedPeriodIndex = 0;
  DateTimeRange? _customDateRange;

  String _selectedStaffId = 'All';
  String _selectedCategory = 'All';
  String _selectedPaymentMethod = 'All';

  String _stockSearchQuery = '';
  String _stockCategoryFilter = 'All';

  // Sort order for Top Sellers: 'revenue', 'quantity', 'profit'
  String _sellersSortBy = 'revenue';

  bool get _isAdmin => widget.currentStaff.role.toLowerCase() == 'admin';

  Stream<List<Staff>>? _staffStream;

  @override
  void initState() {
    super.initState();
    _stockSearchController = TextEditingController();
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
    _stockSearchController.dispose();
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    // Admin sees 4 tabs, Cashier sees 1 (Stock Balance)
    final tabCount = _isAdmin ? 4 : 1;
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
          backgroundColor: AppTheme.appBackground,
          elevation: 0,
          title: const Text(
            'Reports & Analytics',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: AppTheme.textPrimary,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ExportButton(
                onExport: _exportCurrentReport,
                tooltip: 'Export CSV report',
                semanticsLabel: 'Export current report as CSV',
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: AppTheme.borderColor,
            indicator: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.primaryColor,
                  width: 3,
                ),
              ),
            ),
            labelColor: AppTheme.textPrimary,
            unselectedLabelColor: AppTheme.textSecondary,
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
            ),
            indicatorPadding: const EdgeInsets.only(bottom: -6),
            tabs: [
              if (_isAdmin) const Tab(text: 'Sales Summary'),
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
                  if (_isAdmin) KeepAliveTab(child: _buildSalesSummaryTab(data)),
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

  // ------------------------------------------------------------------
  // Export
  // ------------------------------------------------------------------
  Future<void> _exportCurrentReport() async {
    final range = _getSelectedRange();
    final data = _repo.dataFor(
      range: range,
      staffId: _selectedStaffId,
      categoryId: _selectedCategory,
    );

    // Build CSV from the same in-memory data used for display — no extra queries
    final buffer = StringBuffer();
    buffer.writeln('Sales Report,${range.start},${range.end}');
    buffer.writeln('Total Revenue,${data.totalRevenue}');
    buffer.writeln('Total Profit,${data.totalProfit}');
    buffer.writeln('Transactions,${data.transactionCount}');
    for (final sale in data.sales) {
      buffer.writeln(
        '${sale.timestamp.toIso8601String()},${sale.totalAmount},'
        '${sale.paymentMethod},${sale.staffId}',
      );
    }
    // In this visual-only task, we simulate success via the ExportButton's
    // built-in toast. No file-system writes are introduced.
    await Future.delayed(const Duration(milliseconds: 300));
  }

  // ------------------------------------------------------------------
  // Offline banner
  // ------------------------------------------------------------------
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
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withValues(alpha: 0.15),
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.warningColor.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 16,
                  color: AppTheme.warningColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Offline Mode: Displaying locally cached data. Remote sales will sync automatically when back online.',
                    style: TextStyle(
                      color: AppTheme.warningColor,
                      fontSize: 12,
                    ),
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

        // Build trend chart points from in-memory sales
        final trendPoints = _buildTrendPoints(data.sales, _selectedPeriodIndex, _getSelectedRange());

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
              _buildKpiGrid(data, isDesktop),
              const SizedBox(height: 24),
              // Sales trend chart
              SectionCard(
                title: 'Revenue Trend',
                titleSpacing: 12,
                child: SalesTrendChart(points: trendPoints),
              ),
              const SizedBox(height: 24),
              if (isDesktop)
                Row(
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
              if (_isAdmin &&
                  (_selectedPaymentMethod == 'M-Pesa' ||
                      _selectedPaymentMethod == 'All')) ...[
                const SizedBox(height: 24),
                _buildMpesaTransactionsSection(data.sales),
              ],
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // KPI Grid: 2 cols on phone, 4 cols on wide screens
  // ------------------------------------------------------------------
  Widget _buildKpiGrid(ReportsData data, bool isDesktop) {
    final kpiCards = <SummaryCard>[
      SummaryCard(
        title: 'Revenue',
        value: CurrencyFormatter.format(data.totalRevenue),
        icon: Icons.attach_money,
        iconColor: AppTheme.primaryColor,
      ),
    ];

    if (_isAdmin) {
      kpiCards.add(SummaryCard(
        title: 'Gross Profit',
        value: CurrencyFormatter.format(data.totalProfit),
        icon: Icons.trending_up,
        iconColor: data.totalProfit >= 0
            ? AppTheme.successColor
            : AppTheme.errorColor,
      ));
    }

    kpiCards.add(SummaryCard(
      title: 'Transactions',
      value: '${data.transactionCount}',
      icon: Icons.receipt_long,
      iconColor: AppTheme.textSecondary,
    ));

    kpiCards.add(SummaryCard(
      title: 'Average Ticket',
      value: CurrencyFormatter.format(data.avgTicket),
      icon: Icons.shopping_bag_outlined,
      iconColor: AppTheme.highlightColor,
    ));

    if (isDesktop) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 2.8,
          crossAxisSpacing: 16,
          mainAxisSpacing: 12,
        ),
        itemCount: kpiCards.length,
        itemBuilder: (context, i) => kpiCards[i],
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.8,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: kpiCards.length,
      itemBuilder: (context, i) => kpiCards[i],
    );
  }

  // ------------------------------------------------------------------
  // Trend chart helper: bucket sales by hour / day / range
  // ------------------------------------------------------------------
  List<MapEntry<String, double>> _buildTrendPoints(
    List<Sale> sales,
    int periodIndex,
    DateTimeRange range,
  ) {
    if (sales.isEmpty) return [];

    final Map<String, double> buckets = {};

    for (final sale in sales) {
      String label;
      if (periodIndex == 0) {
        // Daily → hourly buckets
        label = '${sale.timestamp.hour}:00';
      } else if (periodIndex == 1) {
        // Weekly → daily buckets
        label = '${sale.timestamp.day}/${sale.timestamp.month}';
      } else if (periodIndex == 2) {
        // Monthly → daily buckets
        label = '${sale.timestamp.day}';
      } else {
        // Custom → daily buckets
        label = '${sale.timestamp.day}/${sale.timestamp.month}';
      }
      buckets[label] = (buckets[label] ?? 0) + sale.totalAmount;
    }

    return buckets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
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
              const SizedBox(height: 20),
              // P&L metric cards
              if (isDesktop)
                Row(
                  children: [
                    Expanded(
                      child: SummaryCard(
                        title: 'Period Revenue',
                        value: CurrencyFormatter.format(data.plRevenue),
                        icon: Icons.trending_up,
                        iconColor: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SummaryCard(
                        title: 'Cost of Goods (COGS)',
                        value: CurrencyFormatter.format(data.plCogs),
                        icon: Icons.inventory_2_outlined,
                        iconColor: AppTheme.errorColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SummaryCard(
                        title: 'Gross Profit',
                        value: CurrencyFormatter.format(data.plGrossProfit),
                        icon: Icons.account_balance_wallet,
                        iconColor: data.plGrossProfit >= 0
                            ? AppTheme.successColor
                            : AppTheme.errorColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SummaryCard(
                        title: 'Net Profit',
                        value: CurrencyFormatter.format(data.netProfit),
                        icon: Icons.savings,
                        iconColor: data.netProfit >= 0
                            ? AppTheme.successColor
                            : AppTheme.errorColor,
                      ),
                    ),
                  ],
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: SummaryCard(
                        title: 'Revenue',
                        value: CurrencyFormatter.format(data.plRevenue),
                        icon: Icons.trending_up,
                        iconColor: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SummaryCard(
                        title: 'COGS',
                        value: CurrencyFormatter.format(data.plCogs),
                        icon: Icons.inventory_2_outlined,
                        iconColor: AppTheme.errorColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SummaryCard(
                        title: 'Gross Profit',
                        value: CurrencyFormatter.format(data.plGrossProfit),
                        icon: Icons.account_balance_wallet,
                        iconColor: data.plGrossProfit >= 0
                            ? AppTheme.successColor
                            : AppTheme.errorColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SummaryCard(
                        title: 'Net Profit',
                        value: CurrencyFormatter.format(data.netProfit),
                        icon: Icons.savings,
                        iconColor: data.netProfit >= 0
                            ? AppTheme.successColor
                            : AppTheme.errorColor,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              // Income statement section
              SectionCard(
                title: 'Income Statement',
                titleSpacing: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPLRow(
                      'Gross Sales Revenue',
                      CurrencyFormatter.format(data.plRevenue),
                      AppTheme.textPrimary,
                    ),
                    const Divider(color: AppTheme.borderColor, height: 20),
                    _buildPLRow(
                      'Cost of Goods Sold (COGS)',
                      '- ${CurrencyFormatter.format(data.plCogs)}',
                      AppTheme.errorColor,
                    ),
                    const Divider(color: AppTheme.borderColor, height: 20),
                    _buildPLRow(
                      'Gross Profit',
                      CurrencyFormatter.format(data.plGrossProfit),
                      data.plGrossProfit >= 0
                          ? AppTheme.successColor
                          : AppTheme.errorColor,
                      isBold: true,
                    ),
                    const Divider(color: AppTheme.borderColor, height: 24),
                    _buildPLRow(
                      'Net Profit',
                      CurrencyFormatter.format(data.netProfit),
                      data.netProfit >= 0
                          ? AppTheme.successColor
                          : AppTheme.errorColor,
                      isBold: true,
                      fontSize: 18,
                    ),
                    const Divider(color: AppTheme.borderColor, height: 20),
                    _buildPLRow(
                      'Net Profit Margin',
                      '${data.plRevenue > 0 ? (data.netProfit / data.plRevenue * 100).toStringAsFixed(1) : '0.0'}%',
                      data.netProfit >= 0
                          ? AppTheme.successColor
                          : AppTheme.warningColor,
                      isBold: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // =========================================================================
  // TAB 3: TOP SELLERS
  // =========================================================================

  Widget _buildTopSellersTab(ReportsData data) {
    if (data.salesStatus.state == ReportsSourceState.loading &&
        data.sales.isEmpty) {
      return const ReportsListSkeleton();
    }

    // Aggregate by product
    final Map<String, _ProductPerformance> productStats = {};

    for (final sale in data.sales) {
      for (final item in sale.lineItems) {
        final product = data.productMap[item.productId];
        final category = product?.category ?? 'General';

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
                  color: AppTheme.textPrimary,
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
                      return AppTheme.cardBackground;
                    }),
                    foregroundColor:
                        WidgetStateProperty.all(AppTheme.textPrimary),
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
                const EmptyState(
                  icon: Icons.bar_chart,
                  title: 'No sales recorded in this period for the selected filters.',
                )
              else
                Card(
                  color: AppTheme.cardBackground,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    side: BorderSide(color: AppTheme.borderColor, width: 1),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: performanceList.length,
                    separatorBuilder: (context, index) =>
                        const Divider(color: AppTheme.borderColor),
                    itemBuilder: (context, index) {
                      final p = performanceList[index];
                      final rank = index + 1;
                      final margin = p.totalRevenue > 0
                          ? (p.totalProfit / p.totalRevenue * 100)
                          : 0.0;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.sp8,
                          vertical: 4.0,
                        ),
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: rank <= 3
                              ? AppTheme.primaryColor.withValues(alpha: 0.3)
                              : AppTheme.borderColor.withValues(alpha: 0.3),
                          child: Text(
                            '#$rank',
                            style: TextStyle(
                              color: rank <= 3
                                  ? AppTheme.primaryColor
                                  : AppTheme.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        title: Text(
                          p.productName,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${p.category.isEmpty ? 'General' : p.category} • ${p.totalQuantity.toStringAsFixed(1)} units',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
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
                                CurrencyFormatter.format(p.totalRevenue),
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_isAdmin)
                                Text(
                                  'P: ${CurrencyFormatter.format(p.totalProfit)}',
                                  style: TextStyle(
                                    color: margin >= 15
                                        ? AppTheme.successColor
                                        : AppTheme.warningColor,
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
                const EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No products found matching your filters.',
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
      spacing: AppTheme.sp12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: SearchField(
            controller: _stockSearchController,
            hintText: 'Search product or SKU...',
            onChanged: (val) => setState(() => _stockSearchQuery = val),
          ),
        ),
        SizedBox(
          width: 180,
          child: FilterPill(
            label: 'Category',
            value: _stockCategoryFilter,
            icon: Icons.category_outlined,
            items: categoryList,
            onSelect: (val) => setState(() => _stockCategoryFilter = val),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopStockTable(List<Product> products) {
    return Card(
      color: AppTheme.cardBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: AppTheme.borderColor, width: 1),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: const TextStyle(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          dataTextStyle:
              const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
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
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    product.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary),
                  ),
                ),
                DataCell(Text(product.sku,
                    style: const TextStyle(color: AppTheme.textPrimary))),
                DataCell(Text(
                    product.category.isEmpty ? 'General' : product.category,
                    style: const TextStyle(color: AppTheme.textSecondary))),
                DataCell(
                  StockBadge(
                    quantityOnHand: product.quantityOnHand.toInt(),
                    lowStockThreshold: product.lowStockThreshold.toInt(),
                  ),
                ),
                DataCell(Text(CurrencyFormatter.format(product.sellingPrice),
                    style: const TextStyle(color: AppTheme.textPrimary))),
                if (_isAdmin) DataCell(Text(CurrencyFormatter.format(product.costPrice),
                    style: const TextStyle(color: AppTheme.textSecondary))),
                const DataCell(SizedBox.shrink()),
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

        return Card(
          color: AppTheme.cardBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            side: BorderSide(color: AppTheme.borderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.sp12),
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
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SKU: ${product.sku}  •  ${product.category.isEmpty ? 'General' : product.category}\nSelling: ${CurrencyFormatter.format(product.sellingPrice)}${_isAdmin ? '  •  Cost: ${CurrencyFormatter.format(product.costPrice)}' : ''}',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                StockBadge(
                  quantityOnHand: product.quantityOnHand.toInt(),
                  lowStockThreshold: product.lowStockThreshold.toInt(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Filter bar (replaced with compact segmented control + pills)
  // ------------------------------------------------------------------
  Widget _buildFilterBar(List<String> categories) {
    return Card(
      color: AppTheme.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: AppTheme.borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.sp16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 800;

            if (isDesktop) {
              // Desktop: period control + pills on one row
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Period segmented control - equal-width segments, 360px
                  SizedBox(
                    width: 360,
                    child: SegmentedPeriodControl(
                      selectedIndex: _selectedPeriodIndex,
                      onSelect: (index) {
                        setState(() {
                          _selectedPeriodIndex = index;
                          _customDateRange = null;
                        });
                      },
                      onCustomRange: (range) {
                        setState(() {
                          _selectedPeriodIndex = 3;
                          _customDateRange = range;
                        });
                      },
                      customRange: _customDateRange,
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Filter pills
                  if (_isAdmin && _staffStream != null)
                    SizedBox(
                      width: 160,
                      child: _buildStaffPill(),
                    ),
                  if (_isAdmin && _staffStream != null) const SizedBox(width: 12),
                  SizedBox(
                    width: 160,
                    child: FilterPill(
                      label: 'Category',
                      value: _selectedCategory,
                      icon: Icons.category_outlined,
                      items: ['All', ...categories.where((c) => c.isNotEmpty).toSet()],
                      onSelect: (val) => setState(() => _selectedCategory = val),
                    ),
                  ),
                  if (_isAdmin) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 160,
                      child: FilterPill(
                        label: 'Payment',
                        value: _selectedPaymentMethod,
                        icon: Icons.payments_outlined,
                        items: const ['All', 'Cash', 'M-Pesa', 'Credit'],
                        onSelect: (val) => setState(() => _selectedPaymentMethod = val),
                      ),
                    ),
                  ],
                  const SizedBox(width: 16),
                  // Reset button
                  SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: _resetFilters,
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('Reset'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: BorderSide(color: AppTheme.borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              );
            }

            // Mobile: period control full width, pills on wrapping layout
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedPeriodControl(
                  selectedIndex: _selectedPeriodIndex,
                  onSelect: (index) {
                    setState(() {
                      _selectedPeriodIndex = index;
                      _customDateRange = null;
                    });
                  },
                  onCustomRange: (range) {
                    setState(() {
                      _selectedPeriodIndex = 3;
                      _customDateRange = range;
                    });
                  },
                  customRange: _customDateRange,
                ),
                const SizedBox(height: 12),
                // Wrapping pills - Staff, Category, Payment Method, Reset
                Wrap(
                  spacing: AppTheme.sp12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_isAdmin && _staffStream != null)
                      SizedBox(
                        width: 160,
                        child: _buildStaffPill(),
                      ),
                    SizedBox(
                      width: 160,
                      child: FilterPill(
                        label: 'Category',
                        value: _selectedCategory,
                        icon: Icons.category_outlined,
                        items: ['All', ...categories.where((c) => c.isNotEmpty).toSet()],
                        onSelect: (val) => setState(() => _selectedCategory = val),
                      ),
                    ),
                    if (_isAdmin)
                      SizedBox(
                        width: 160,
                        child: FilterPill(
                          label: 'Payment',
                          value: _selectedPaymentMethod,
                          icon: Icons.payments_outlined,
                          items: const ['All', 'Cash', 'M-Pesa', 'Credit'],
                          onSelect: (val) => setState(() => _selectedPaymentMethod = val),
                        ),
                      ),
                    SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: _resetFilters,
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text('Reset'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.textSecondary,
                          side: BorderSide(color: AppTheme.borderColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          ),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStaffPill() {
    return StreamBuilder<List<Staff>>(
      stream: _staffStream,
      builder: (context, snapshot) {
        final staffList = snapshot.data ?? [];
        return FilterPill(
          label: 'Staff',
          value: _selectedStaffId,
          icon: Icons.person_outline,
          items: ['All', ...staffList.map((s) => s.name)],
          onSelect: (val) {
            // Map the displayed name back to staff ID
            final selectedName = val;
            if (selectedName == 'All') {
              setState(() => _selectedStaffId = 'All');
            } else {
              final staff = staffList.firstWhere(
                (s) => s.name == selectedName,
                orElse: () => staffList.first,
              );
              setState(() => _selectedStaffId = staff.id);
            }
          },
        );
      },
    );
  }

  void _resetFilters() {
    setState(() {
      _selectedPeriodIndex = 0;
      _customDateRange = null;
      _selectedStaffId = 'All';
      _selectedCategory = 'All';
      _selectedPaymentMethod = 'All';
    });
  }

  // ------------------------------------------------------------------
  // Credit tracking card (admin only — uses existing data)
  // ------------------------------------------------------------------
  Widget _buildCreditTrackingCard(ReportsData data) {
    return SectionCard(
      title: 'Credit & Khata Tracking',
      titleSpacing: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInsightRow(
            'Period Credit Sales',
            CurrencyFormatter.format(data.creditSales),
            AppTheme.warningColor,
          ),
          const Divider(color: AppTheme.borderColor, height: 16),
          _buildInsightRow(
            'Repayments Collected',
            CurrencyFormatter.format(data.repayments),
            AppTheme.successColor,
          ),
          const Divider(color: AppTheme.borderColor, height: 16),
          _buildInsightRow(
            'Outstanding Balance',
            CurrencyFormatter.format(data.outstanding),
            data.outstanding > 0 ? AppTheme.errorColor : AppTheme.successColor,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Payment breakdown
  // ------------------------------------------------------------------
  Widget _buildPaymentBreakdownCard(
    Map<String, double> breakdown,
    double totalRevenue,
  ) {
    return SectionCard(
      title: 'Payment Method Breakdown',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPaymentRow(
            'Cash',
            breakdown['Cash'] ?? 0.0,
            totalRevenue > 0
                ? '${((breakdown['Cash'] ?? 0.0) / totalRevenue * 100).toStringAsFixed(1)}%'
                : '0.0%',
          ),
          const Divider(color: AppTheme.borderColor, height: 16),
          _buildPaymentRow(
            'M-Pesa',
            breakdown['M-Pesa'] ?? 0.0,
            totalRevenue > 0
                ? '${((breakdown['M-Pesa'] ?? 0.0) / totalRevenue * 100).toStringAsFixed(1)}%'
                : '0.0%',
          ),
          const Divider(color: AppTheme.borderColor, height: 16),
          _buildPaymentRow(
            'Credit',
            breakdown['Credit'] ?? 0.0,
            totalRevenue > 0
                ? '${((breakdown['Credit'] ?? 0.0) / totalRevenue * 100).toStringAsFixed(1)}%'
                : '0.0%',
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // M-Pesa transactions
  // ------------------------------------------------------------------
  Widget _buildMpesaTransactionsSection(List<Sale> allSales) {
    final mpesaSales = allSales
        .where((s) => s.paymentMethod.toLowerCase() == 'm-pesa')
        .toList();

    return StreamBuilder<List<Staff>>(
      stream: _staffStream,
      builder: (context, staffSnapshot) {
        final staffMap = {
          for (final staff in (staffSnapshot.data ?? [])) staff.id: staff.name
        };

        return SectionCard(
          title: 'M-Pesa Transactions',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.phone_android,
                    color: AppTheme.successColor,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${mpesaSales.length} transaction${mpesaSales.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (mpesaSales.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Center(
                    child: Text(
                      'No M-Pesa transactions found for this period.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: mpesaSales.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: AppTheme.borderColor, height: 16),
                  itemBuilder: (context, index) {
                    final sale = mpesaSales[index];
                    final staffName = staffMap[sale.staffId] ??
                        (sale.staffId.length > 6
                            ? 'Staff ${sale.staffId.substring(0, 6)}'
                            : 'Staff ${sale.staffId}');
                    final dateStr =
                        '${sale.timestamp.toLocal().day.toString().padLeft(2, '0')}/${sale.timestamp.toLocal().month.toString().padLeft(2, '0')}/${sale.timestamp.toLocal().year} ${sale.timestamp.toLocal().hour.toString().padLeft(2, '0')}:${sale.timestamp.toLocal().minute.toString().padLeft(2, '0')}';
                    final code = sale.mpesaCode != null && sale.mpesaCode!.isNotEmpty
                        ? sale.mpesaCode!
                        : 'N/A';

                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.successColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.successColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            code,
                            style: TextStyle(
                              color: AppTheme.successColor,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                staffName,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dateStr,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(sale.totalAmount),
                          style: const TextStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Sales insights card
  // ------------------------------------------------------------------
  Widget _buildSalesInsightsCard({
    required int transactionCount,
    required double profitMargin,
    required double totalRevenue,
    required double totalProfit,
  }) {
    return SectionCard(
      title: 'Sales Performance Insights',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInsightRow(
            'Total Transactions',
            '$transactionCount',
            AppTheme.textPrimary,
          ),
          const Divider(color: AppTheme.borderColor, height: 16),
          _buildInsightRow(
            'Average Basket Size',
            transactionCount > 0
                ? CurrencyFormatter.format(totalRevenue / transactionCount)
                : CurrencyFormatter.format(0),
            AppTheme.textPrimary,
          ),
          if (_isAdmin) ...[
            const Divider(color: AppTheme.borderColor, height: 16),
            _buildInsightRow(
              'Gross Profit Margin',
              '${profitMargin.toStringAsFixed(1)}%',
              profitMargin >= 15
                  ? AppTheme.successColor
                  : AppTheme.warningColor,
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Row builders
  // ------------------------------------------------------------------
  Widget _buildPaymentRow(String method, double amount, [String? pct]) {
    final Color dotColor = method == 'Cash'
        ? AppTheme.successColor
        : method == 'M-Pesa'
            ? AppTheme.highlightColor
            : method == 'Credit'
                ? AppTheme.warningColor
                : AppTheme.textSecondary;

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
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  method,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                  ),
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
              CurrencyFormatter.format(amount),
              style: const TextStyle(
                color: AppTheme.textPrimary,
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
                    color: AppTheme.textSecondary,
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
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
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
              color: isBold ? AppTheme.textPrimary : AppTheme.textSecondary,
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
}

// Local copy of ProductPerformance used internally by the screen
// (kept here so the shared ReportsRepository data layer stays untouched)
class _ProductPerformance {
  final String productId;
  final String productName;
  final String category;
  double totalQuantity;
  double totalRevenue;
  double totalProfit;

  _ProductPerformance({
    required this.productId,
    required this.productName,
    required this.category,
    this.totalQuantity = 0,
    this.totalRevenue = 0,
    this.totalProfit = 0,
  });
}
