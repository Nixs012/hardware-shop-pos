import 'dart:async';

import 'package:app/models/customer_payment.dart';
import 'package:app/models/expense.dart';
import 'package:app/models/failed_sale.dart';
import 'package:app/models/product.dart';
import 'package:app/models/sale.dart';
import 'package:app/models/staff.dart';
import 'package:app/services/firestore_service.dart';

/// A simple replaying stream (BehaviorSubject pattern) used by the mock so
/// subscribers receive the latest value even if they subscribe after it was
/// seeded. Mirrors the production [CachedReplayStream] semantics.
class _ReplayStream<T> {
  final StreamController<T> _controller = StreamController<T>.broadcast();
  T? _last;
  bool _hasValue = false;

  _ReplayStream([T? initial]) {
    if (initial != null) {
      _last = initial;
      _hasValue = true;
    }
  }

  Stream<T> get stream => Stream<T>.multi((controller) {
        if (_hasValue) controller.add(_last as T);
        final forwarder = _controller.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
        controller.onCancel = forwarder.cancel;
      });

  void add(T value) {
    _last = value;
    _hasValue = true;
    if (!_controller.isClosed) _controller.add(value);
  }

  void close() => _controller.close();
}

/// A mock [FirestoreService] that returns replaying streams and no-op futures,
/// for use in widget tests where no real Firebase backend is available.
///
/// Call counters let tests assert that streams are subscribed exactly once
/// (e.g. switching Reports tabs must not reload anything).
class MockFirestoreService implements FirestoreService {
  late final _ReplayStream<List<Product>> _products;
  late final _ReplayStream<List<Sale>> _sales;
  late final _ReplayStream<List<CustomerPayment>> _payments;
  late final _ReplayStream<List<Staff>> _staff;
  late final _ReplayStream<List<Expense>> _expenses;

  MockFirestoreService() {
    // Emit empty lists initially so consumers never hang on first load.
    _products = _ReplayStream<List<Product>>([]);
    _sales = _ReplayStream<List<Sale>>([]);
    _payments = _ReplayStream<List<CustomerPayment>>([]);
    _staff = _ReplayStream<List<Staff>>([]);
    _expenses = _ReplayStream<List<Expense>>([]);
  }

  // Call counters for assertions.
  int getProductsStreamCalls = 0;
  int getSalesStreamCalls = 0;
  int getCustomerPaymentsStreamCalls = 0;
  int getStaffStreamCalls = 0;
  int getExpensesStreamCalls = 0;
  int resetReportsStreamsCalls = 0;

  @override
  Stream<List<Product>> getProductsStream({bool isAdmin = false}) {
    getProductsStreamCalls++;
    return _products.stream;
  }

  @override
  Stream<List<Sale>> getSalesStream({bool isAdmin = false, String? staffId}) {
    getSalesStreamCalls++;
    return _sales.stream;
  }

  @override
  Stream<List<CustomerPayment>> getCustomerPaymentsStream() {
    getCustomerPaymentsStreamCalls++;
    return _payments.stream;
  }

  @override
  Stream<List<Staff>> getStaffStream() {
    getStaffStreamCalls++;
    return _staff.stream;
  }

  @override
  Stream<List<Expense>> getExpensesStream() {
    getExpensesStreamCalls++;
    return _expenses.stream;
  }

  @override
  void resetReportsStreams() {
    resetReportsStreamsCalls++;
  }

  // No-op: the mock doesn't filter by auth UID, so this is intentionally ignored.
  void setCashierAuthUid(String? uid) {}

  @override
  Future<void> addProduct(Product product) async {}

  @override
  Future<void> updateProduct(Product product) async {}

  @override
  Future<void> deleteProduct(String productId) async {}

  @override
  Future<void> processSale(Sale sale, {bool includeCostSnapshot = true}) async {}

  @override
  Future<Sale?> getLatestSale({String? staffId}) async => null;

  @override
  Future<void> recordCustomerPayment(CustomerPayment payment) async {}

  @override
  Future<void> addExpense(Expense expense) async {}

  @override
  Future<void> updateExpense(Expense expense) async {}

  @override
  Future<void> deleteExpense(String expenseId) async {}

  @override
  Future<void> updateStaff(Staff staff) async {}

  @override
  Future<List<FailedSaleRecord>> getFailedSales() async => [];

  @override
  Future<void> retryFailedSale(FailedSaleRecord record) async {}

  void dispose() {
    _products.close();
    _sales.close();
    _payments.close();
    _staff.close();
    _expenses.close();
  }

  // Helpers to seed data into the mock streams for testing
  void setProducts(List<Product> products) => _products.add(products);

  void setSales(List<Sale> sales) => _sales.add(sales);

  void setStaff(List<Staff> staff) => _staff.add(staff);

  void setExpenses(List<Expense> expenses) => _expenses.add(expenses);

  void setPayments(List<CustomerPayment> payments) => _payments.add(payments);
}
