import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint, visibleForTesting;
import 'package:flutter/material.dart' show DateTimeRange;

import '../models/customer_payment.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../utils/credit_balance.dart';
import 'firestore_service.dart';

/// Which Firestore-backed source feeds a part of the reports.
enum ReportsSource { sales, products, expenses, customerPayments }

/// Lifecycle of a single report source.
enum ReportsSourceState {
  /// Source is not used for the current role (e.g. expenses for a cashier).
  notUsed,

  /// Source is subscribed and waiting for its first snapshot.
  loading,

  /// Source delivered at least one snapshot.
  ready,

  /// Source produced no snapshot within the timeout.
  timedOut,

  /// Source failed with an error.
  error,
}

/// Status + human readable message for one report source.
class ReportsSourceStatus {
  final ReportsSourceState state;
  final String? message;

  const ReportsSourceStatus(this.state, [this.message]);

  bool get isFailed =>
      state == ReportsSourceState.timedOut || state == ReportsSourceState.error;
}

/// Cache key: date range + staff filter + category filter.
class ReportsQuery {
  final DateTimeRange range;
  final String staffId;
  final String categoryId;

  const ReportsQuery({
    required this.range,
    required this.staffId,
    required this.categoryId,
  });

  String get cacheKey =>
      '${range.start.millisecondsSinceEpoch}|'
      '${range.end.millisecondsSinceEpoch}|$staffId|$categoryId';
}

/// Aggregated performance of one product across the filtered sales set.
class ProductPerformance {
  final String productId;
  final String productName;
  final String category;
  double totalQuantity;
  double totalRevenue;
  double totalProfit;

  ProductPerformance({
    required this.productId,
    required this.productName,
    required this.category,
    this.totalQuantity = 0,
    this.totalRevenue = 0,
    this.totalProfit = 0,
  });
}

/// Everything the Reports tabs need for one (range, staff, category) query,
/// computed from the in-memory data loaded once by [ReportsRepository].
class ReportsData {
  final ReportsQuery query;

  final ReportsSourceStatus salesStatus;
  final ReportsSourceStatus productsStatus;
  final ReportsSourceStatus expensesStatus;
  final ReportsSourceStatus paymentsStatus;

  /// Sales within range, staff filter and (when set) the sale-level category
  /// match — the exact set the Sales Summary and P&L tabs have always used.
  final List<Sale> sales;

  /// Repayments recorded within the selected range.
  final List<CustomerPayment> periodPayments;

  /// Expenses recorded within the selected range.
  final List<Expense> periodExpenses;

  final List<Product> products;
  final Map<String, Product> productMap;

  /// Distinct product categories, for the category filter.
  final List<String> categories;

  // ---- Sales Summary aggregates ----
  final double totalRevenue;
  final double totalProfit;
  final double avgTicket;
  final double profitMargin;
  final int transactionCount;

  final Map<String, double> paymentBreakdown;

  final double creditSales;
  final double repayments;

  /// Shared definition with the Credit screen: credit sales − repayments.
  final double outstanding;

  // ---- Profit & Loss aggregates ----
  final double plRevenue;
  final double plCogs;
  final double plGrossProfit;
  final double totalExpenses;
  final double netProfit;

  const ReportsData({
    required this.query,
    required this.salesStatus,
    required this.productsStatus,
    required this.expensesStatus,
    required this.paymentsStatus,
    required this.sales,
    required this.periodPayments,
    required this.periodExpenses,
    required this.products,
    required this.productMap,
    required this.categories,
    required this.totalRevenue,
    required this.totalProfit,
    required this.avgTicket,
    required this.profitMargin,
    required this.transactionCount,
    required this.paymentBreakdown,
    required this.creditSales,
    required this.repayments,
    required this.outstanding,
    required this.plRevenue,
    required this.plCogs,
    required this.plGrossProfit,
    required this.totalExpenses,
    required this.netProfit,
  });

  /// Show a skeleton (not a spinner) while sales have never arrived.
  bool get showSalesSkeleton => salesStatus.state == ReportsSourceState.loading;

  /// Show a skeleton while products have never arrived.
  bool get showProductsSkeleton =>
      productsStatus.state == ReportsSourceState.loading;
}

/// Session-scoped repository that subscribes to the Firestore-backed streams
/// exactly ONCE and computes every Reports tab's figures from that in-memory
/// data.
///
/// * Sales (and for admins: sales_costs via the merged stream, expenses and
///   customer payments) are loaded once per session.
/// * Results are cached by (date range, staff filter, category filter) and
///   recomputed in the background when new data arrives.
/// * Each source has a 10 second timeout and surfaces a specific error so the
///   UI can show "data that did load" plus a Retry action — never an endless
///   spinner.
class ReportsRepository extends ChangeNotifier {
  ReportsRepository._(
    this._service,
    this._isAdmin,
    this._staffId,
  ) {
    _status[ReportsSource.sales] =
        const ReportsSourceStatus(ReportsSourceState.loading);
    _status[ReportsSource.products] =
        const ReportsSourceStatus(ReportsSourceState.loading);
    _status[ReportsSource.expenses] = _isAdmin
        ? const ReportsSourceStatus(ReportsSourceState.loading)
        : const ReportsSourceStatus(ReportsSourceState.notUsed);
    _status[ReportsSource.customerPayments] = _isAdmin
        ? const ReportsSourceStatus(ReportsSourceState.loading)
        : const ReportsSourceStatus(ReportsSourceState.notUsed);
  }

  static const Duration sourceTimeout = Duration(seconds: 10);

  static ReportsRepository? _session;

  /// Returns the session repository for this service/role, creating it on
  /// first use. A different service instance or role replaces the session.
  static ReportsRepository acquire({
    required FirestoreService service,
    required bool isAdmin,
    required String? staffId,
  }) {
    final existing = _session;
    if (existing != null &&
        !existing._disposed &&
        identical(existing._service, service) &&
        existing._isAdmin == isAdmin) {
      return existing;
    }
    existing?.dispose();
    final repo = ReportsRepository._(service, isAdmin, staffId);
    _session = repo;
    return repo;
  }

  /// Drops the session repository (used by tests to avoid cross-test state).
  @visibleForTesting
  static void resetSessionForTesting() {
    _session?.dispose();
    _session = null;
  }

  final FirestoreService _service;
  final bool _isAdmin;
  final String? _staffId;

  bool _started = false;
  bool _disposed = false;
  int _watchers = 0;

  StreamSubscription<List<Sale>>? _salesSub;
  StreamSubscription<List<Product>>? _productsSub;
  StreamSubscription<List<Expense>>? _expensesSub;
  StreamSubscription<List<CustomerPayment>>? _paymentsSub;

  final Map<ReportsSource, Timer> _timers = {};
  final Map<ReportsSource, ReportsSourceStatus> _status = {};

  List<Sale> _sales = const [];
  List<CustomerPayment> _payments = const [];
  List<Expense> _expenses = const [];
  List<Product> _products = const [];

  final Map<String, ReportsData> _cache = {};

  bool get started => _started;

  /// Subscribes to every source the current role is allowed to read.
  /// Safe to call multiple times; only the first call does anything.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _subscribeSales();
    _subscribeProducts();
    if (_isAdmin) {
      _subscribeExpenses();
      _subscribePayments();
    }
  }

  // ---------------------------------------------------------------------
  // ChangeNotifier lifecycle: arm the 10s timeouts only while a screen is
  // actually watching, so no timers leak when nobody is looking.
  // ---------------------------------------------------------------------
  @override
  void addListener(void Function() listener) {
    super.addListener(listener);
    _watchers++;
    if (_watchers == 1 && _started) _armLoadingTimeouts();
  }

  @override
  void removeListener(void Function() listener) {
    super.removeListener(listener);
    _watchers--;
    if (_watchers <= 0) _cancelAllTimers();
  }

  bool get _isWatched => _watchers > 0;

  // ---------------------------------------------------------------------
  // Sources
  // ---------------------------------------------------------------------
  void _subscribeSales() {
    final stopwatch = Stopwatch()..start();
    debugPrint(
      '[ReportsRepo] sales: query start (isAdmin=$_isAdmin, staffId=${_isAdmin ? 'null' : _staffId})',
    );
    _armTimeout(ReportsSource.sales, 'sales');
    _salesSub = _service
        .getSalesStream(isAdmin: _isAdmin, staffId: _isAdmin ? null : _staffId)
        .listen(
      (sales) {
        if (_status[ReportsSource.sales]!.state != ReportsSourceState.ready) {
          debugPrint(
            '[ReportsRepo] sales: first result after ${stopwatch.elapsedMilliseconds}ms '
            '(${sales.length} docs)',
          );
        }
        _cancelTimer(ReportsSource.sales);
        _sales = sales;
        _setStatus(ReportsSource.sales, ReportsSourceState.ready);
      },
      onError: (Object err, StackTrace stack) {
        debugPrint('[ReportsRepo] sales: ERROR $err');
        _cancelTimer(ReportsSource.sales);
        _setStatus(ReportsSource.sales, ReportsSourceState.error, '$err');
      },
      onDone: () {
        debugPrint('[ReportsRepo] sales: source stream closed');
      },
    );
  }

  void _subscribeProducts() {
    final stopwatch = Stopwatch()..start();
    debugPrint('[ReportsRepo] products: query start (isAdmin=$_isAdmin)');
    _armTimeout(ReportsSource.products, 'products');
    _productsSub = _service.getProductsStream(isAdmin: _isAdmin).listen(
      (products) {
        if (_status[ReportsSource.products]!.state !=
            ReportsSourceState.ready) {
          debugPrint(
            '[ReportsRepo] products: first result after ${stopwatch.elapsedMilliseconds}ms '
            '(${products.length} docs)',
          );
        }
        _cancelTimer(ReportsSource.products);
        _products = products;
        _setStatus(ReportsSource.products, ReportsSourceState.ready);
      },
      onError: (Object err, StackTrace stack) {
        debugPrint('[ReportsRepo] products: ERROR $err');
        _cancelTimer(ReportsSource.products);
        _setStatus(ReportsSource.products, ReportsSourceState.error, '$err');
      },
      onDone: () {
        debugPrint('[ReportsRepo] products: source stream closed');
      },
    );
  }

  void _subscribeExpenses() {
    final stopwatch = Stopwatch()..start();
    debugPrint('[ReportsRepo] expenses: query start (admin only)');
    _armTimeout(ReportsSource.expenses, 'expenses');
    _expensesSub = _service.getExpensesStream().listen(
      (expenses) {
        if (_status[ReportsSource.expenses]!.state !=
            ReportsSourceState.ready) {
          debugPrint(
            '[ReportsRepo] expenses: first result after ${stopwatch.elapsedMilliseconds}ms '
            '(${expenses.length} docs)',
          );
        }
        _cancelTimer(ReportsSource.expenses);
        _expenses = expenses;
        _setStatus(ReportsSource.expenses, ReportsSourceState.ready);
      },
      onError: (Object err, StackTrace stack) {
        debugPrint('[ReportsRepo] expenses: ERROR $err');
        _cancelTimer(ReportsSource.expenses);
        _setStatus(ReportsSource.expenses, ReportsSourceState.error, '$err');
      },
      onDone: () {
        debugPrint('[ReportsRepo] expenses: source stream closed');
      },
    );
  }

  void _subscribePayments() {
    final stopwatch = Stopwatch()..start();
    debugPrint('[ReportsRepo] customer_payments: query start (admin only)');
    _armTimeout(ReportsSource.customerPayments, 'customer_payments');
    _paymentsSub = _service.getCustomerPaymentsStream().listen(
      (payments) {
        if (_status[ReportsSource.customerPayments]!.state !=
            ReportsSourceState.ready) {
          debugPrint(
            '[ReportsRepo] customer_payments: first result after ${stopwatch.elapsedMilliseconds}ms '
            '(${payments.length} docs)',
          );
        }
        _cancelTimer(ReportsSource.customerPayments);
        _payments = payments;
        _setStatus(ReportsSource.customerPayments, ReportsSourceState.ready);
      },
      onError: (Object err, StackTrace stack) {
        debugPrint('[ReportsRepo] customer_payments: ERROR $err');
        _cancelTimer(ReportsSource.customerPayments);
        _setStatus(
          ReportsSource.customerPayments,
          ReportsSourceState.error,
          '$err',
        );
      },
      onDone: () {
        debugPrint('[ReportsRepo] customer_payments: source stream closed');
      },
    );
  }

  // ---------------------------------------------------------------------
  // Timeouts — a source that never delivers must not spin forever.
  // ---------------------------------------------------------------------
  void _armTimeout(ReportsSource source, String label) {
    if (!_isWatched) return; // armed when the first listener attaches
    _cancelTimer(source);
    _timers[source] = Timer(sourceTimeout, () {
      final status = _status[source];
      if (status != null && status.state == ReportsSourceState.loading) {
        debugPrint(
          '[ReportsRepo] $label: TIMEOUT after ${sourceTimeout.inSeconds}s — no snapshot received',
        );
        _setStatus(
          source,
          ReportsSourceState.timedOut,
          'Timed out after ${sourceTimeout.inSeconds} seconds. '
              'Check your connection and tap Retry.',
        );
      }
    });
  }

  void _armLoadingTimeouts() {
    if (_status[ReportsSource.sales]?.state == ReportsSourceState.loading) {
      _armTimeout(ReportsSource.sales, 'sales');
    }
    if (_status[ReportsSource.products]?.state == ReportsSourceState.loading) {
      _armTimeout(ReportsSource.products, 'products');
    }
    if (_status[ReportsSource.expenses]?.state == ReportsSourceState.loading) {
      _armTimeout(ReportsSource.expenses, 'expenses');
    }
    if (_status[ReportsSource.customerPayments]?.state ==
        ReportsSourceState.loading) {
      _armTimeout(ReportsSource.customerPayments, 'customer_payments');
    }
  }

  void _cancelTimer(ReportsSource source) {
    _timers.remove(source)?.cancel();
  }

  void _cancelAllTimers() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  void _setStatus(
    ReportsSource source,
    ReportsSourceState state, [
    String? message,
  ]) {
    _status[source] = ReportsSourceStatus(state, message);
    // New data or a new state invalidates every cached query result.
    _cache.clear();
    if (!_disposed) notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Retry — drops the cached Firestore subscriptions and re-subscribes so a
  // hung or errored source gets a genuinely fresh listener.
  // ---------------------------------------------------------------------
  Future<void> retry(ReportsSource source) async {
    if (_disposed) return;
    debugPrint('[ReportsRepo] retry: $source');
    _cancelAllTimers();
    _service.resetReportsStreams();

    await _salesSub?.cancel();
    await _productsSub?.cancel();
    await _expensesSub?.cancel();
    await _paymentsSub?.cancel();
    _salesSub = null;
    _productsSub = null;
    _expensesSub = null;
    _paymentsSub = null;

    for (final s in [
      ReportsSource.sales,
      ReportsSource.products,
      if (_isAdmin) ReportsSource.expenses,
      if (_isAdmin) ReportsSource.customerPayments,
    ]) {
      _status[s] = const ReportsSourceStatus(ReportsSourceState.loading);
    }
    _cache.clear();
    if (!_disposed) notifyListeners();

    _subscribeSales();
    _subscribeProducts();
    if (_isAdmin) {
      _subscribeExpenses();
      _subscribePayments();
    }
    _armLoadingTimeouts();
  }

  // ---------------------------------------------------------------------
  // Query API — synchronous, in-memory, cached by (range, staff, category).
  // ---------------------------------------------------------------------
  ReportsData dataFor({
    required DateTimeRange range,
    required String staffId,
    required String categoryId,
  }) {
    final query = ReportsQuery(
      range: range,
      staffId: staffId,
      categoryId: categoryId,
    );
    final cached = _cache[query.cacheKey];
    if (cached != null) return cached;

    final data = _compute(query);
    if (_cache.length > 24) _cache.clear();
    _cache[query.cacheKey] = data;
    return data;
  }

  ReportsData _compute(ReportsQuery query) {
    final range = query.range;
    final productMap = {for (final p in _products) p.id: p};

    final filteredSales = _sales.where((sale) {
      final inRange = !sale.timestamp.isBefore(range.start) &&
          !sale.timestamp.isAfter(range.end);
      final matchesStaff =
          query.staffId == 'All' || sale.staffId == query.staffId;
      final matchesCategory = query.categoryId == 'All' ||
          sale.lineItems.any((item) {
            final cat = productMap[item.productId]?.category ?? '';
            return cat.toLowerCase() == query.categoryId.toLowerCase();
          });
      return inRange && matchesStaff && matchesCategory;
    }).toList();

    final periodPayments = _payments.where((payment) {
      return !payment.timestamp.isBefore(range.start) &&
          !payment.timestamp.isAfter(range.end);
    }).toList();

    final periodExpenses = _expenses.where((expense) {
      return !expense.date.isBefore(range.start) &&
          !expense.date.isAfter(range.end);
    }).toList();

    // ---- Sales Summary aggregates ----
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
          (paymentBreakdown[sale.paymentMethod] ?? 0.0) + sale.totalAmount;

      for (final item in sale.lineItems) {
        totalProfit += item.profit;
      }
    }

    final totalCreditSales = paymentBreakdown['Credit'] ?? 0.0;
    final totalRepayments = periodPayments.fold<double>(
      0.0,
      (sum, p) => sum + p.amount,
    );

    final avgTicket = transactionCount > 0
        ? (totalRevenue / transactionCount)
        : 0.0;
    final profitMargin = totalRevenue > 0
        ? (totalProfit / totalRevenue * 100)
        : 0.0;

    // ---- Profit & Loss aggregates ----
    double plRevenue = 0;
    double plCogs = 0;

    for (final sale in filteredSales) {
      plRevenue += sale.totalAmount;
      for (final item in sale.lineItems) {
        plCogs += item.unitCostAtSale * item.quantity;
      }
    }

    final totalExpenses = periodExpenses.fold<double>(
      0.0,
      (sum, e) => sum + e.amount,
    );

    // Canonical formula from pos-domain-rules:
    // period_profit = sum(line_profit) - sum(recorded expenses)
    final plGrossProfit = plRevenue - plCogs;
    final netProfit = plGrossProfit - totalExpenses;

    // Single shared definition of outstanding with the Credit screen.
    final outstanding = computeOutstandingBalance(
      creditSales: totalCreditSales,
      repayments: totalRepayments,
    );

    return ReportsData(
      query: query,
      salesStatus: _status[ReportsSource.sales]!,
      productsStatus: _status[ReportsSource.products]!,
      expensesStatus: _status[ReportsSource.expenses]!,
      paymentsStatus: _status[ReportsSource.customerPayments]!,
      sales: filteredSales,
      periodPayments: periodPayments,
      periodExpenses: periodExpenses,
      products: _products,
      productMap: productMap,
      categories: _products.map((p) => p.category).toSet().toList(),
      totalRevenue: totalRevenue,
      totalProfit: totalProfit,
      avgTicket: avgTicket,
      profitMargin: profitMargin,
      transactionCount: transactionCount,
      paymentBreakdown: paymentBreakdown,
      creditSales: totalCreditSales,
      repayments: totalRepayments,
      outstanding: outstanding,
      plRevenue: plRevenue,
      plCogs: plCogs,
      plGrossProfit: plGrossProfit,
      totalExpenses: totalExpenses,
      netProfit: netProfit,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelAllTimers();
    _salesSub?.cancel();
    _productsSub?.cancel();
    _expensesSub?.cancel();
    _paymentsSub?.cancel();
    _salesSub = null;
    _productsSub = null;
    _expensesSub = null;
    _paymentsSub = null;
    _cache.clear();
    super.dispose();
  }
}

