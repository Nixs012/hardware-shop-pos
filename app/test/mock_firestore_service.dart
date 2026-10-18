import 'dart:async';

import 'package:app/models/customer_payment.dart';
import 'package:app/models/expense.dart';
import 'package:app/models/failed_sale.dart';
import 'package:app/models/product.dart';
import 'package:app/models/sale.dart';
import 'package:app/models/staff.dart';
import 'package:app/services/firestore_service.dart';

/// A mock [FirestoreService] that returns empty streams and no-op futures,
/// for use in widget tests where no real Firebase backend is available.
class MockFirestoreService implements FirestoreService {
  final StreamController<List<Product>> _productsController =
      StreamController<List<Product>>.broadcast();
  final StreamController<List<Sale>> _salesController =
      StreamController<List<Sale>>.broadcast();
  final StreamController<List<CustomerPayment>> _paymentsController =
      StreamController<List<CustomerPayment>>.broadcast();
  final StreamController<List<Staff>> _staffController =
      StreamController<List<Staff>>.broadcast();
  final StreamController<List<Expense>> _expensesController =
      StreamController<List<Expense>>.broadcast();

  MockFirestoreService() {
    // Emit empty lists initially so StreamBuilders don't hang
    _productsController.add([]);
    _salesController.add([]);
    _paymentsController.add([]);
    _staffController.add([]);
    _expensesController.add([]);
  }

  @override
  Stream<List<Product>> getProductsStream({bool isAdmin = false}) =>
      _productsController.stream;

  @override
  Stream<List<Sale>> getSalesStream({bool isAdmin = false, String? staffId}) =>
      _salesController.stream;

  @override
  Stream<List<CustomerPayment>> getCustomerPaymentsStream() =>
      _paymentsController.stream;

  @override
  Stream<List<Staff>> getStaffStream() => _staffController.stream;

  @override
  Stream<List<Expense>> getExpensesStream() => _expensesController.stream;

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
    _productsController.close();
    _salesController.close();
    _paymentsController.close();
    _staffController.close();
    _expensesController.close();
  }

  // Helpers to seed data into the mock streams for testing
  void setProducts(List<Product> products) {
    if (!_productsController.isClosed) _productsController.add(products);
  }

  void setSales(List<Sale> sales) {
    if (!_salesController.isClosed) _salesController.add(sales);
  }

  void setStaff(List<Staff> staff) {
    if (!_staffController.isClosed) _staffController.add(staff);
  }

  void setExpenses(List<Expense> expenses) {
    if (!_expensesController.isClosed) _expensesController.add(expenses);
  }

  void setPayments(List<CustomerPayment> payments) {
    if (!_paymentsController.isClosed) _paymentsController.add(payments);
  }
}
