import '../models/customer_payment.dart';
import '../models/sale.dart';

/// The single definition of an outstanding credit balance, shared by the
/// Reports credit card and the Customer Credit (Khata) screen so the two
/// can never disagree.
///
/// Outstanding balance = credit sales − repayments.
double computeOutstandingBalance({
  required double creditSales,
  required double repayments,
}) =>
    creditSales - repayments;

/// Aggregated credit position of a single customer.
class CustomerCreditBalance {
  final String customerName;
  final String customerPhone;
  final double totalCreditSales;
  final double totalRepayments;

  const CustomerCreditBalance({
    required this.customerName,
    required this.customerPhone,
    required this.totalCreditSales,
    required this.totalRepayments,
  });

  double get outstanding => computeOutstandingBalance(
        creditSales: totalCreditSales,
        repayments: totalRepayments,
      );
}

/// Computes per-customer balances from ALL credit sales minus ALL repayments
/// contained in the provided lists.
///
/// Used by the Customer Credit screen; the Reports credit card uses
/// [computeOutstandingBalance] over its period totals.
Map<String, CustomerCreditBalance> computeCustomerBalances(
  List<Sale> sales,
  List<CustomerPayment> payments,
) {
  final totals = <String, ({double creditSales, double repayments})>{};
  final phones = <String, String>{};

  // Add credit sales.
  for (final sale in sales) {
    if (sale.paymentMethod == 'Credit' &&
        sale.customerName != null &&
        sale.customerName!.isNotEmpty) {
      final key = sale.customerName!;
      phones.putIfAbsent(key, () => sale.customerPhone ?? '');
      final current = totals[key] ?? (creditSales: 0.0, repayments: 0.0);
      totals[key] = (
        creditSales: current.creditSales + sale.totalAmount,
        repayments: current.repayments,
      );
    }
  }

  // Add repayments.
  for (final payment in payments) {
    final key = payment.customerName;
    phones.putIfAbsent(key, () => payment.customerPhone);
    final current = totals[key] ?? (creditSales: 0.0, repayments: 0.0);
    totals[key] = (
      creditSales: current.creditSales,
      repayments: current.repayments + payment.amount,
    );
  }

  return {
    for (final entry in totals.entries)
      entry.key: CustomerCreditBalance(
        customerName: entry.key,
        customerPhone: phones[entry.key] ?? '',
        totalCreditSales: entry.value.creditSales,
        totalRepayments: entry.value.repayments,
      ),
  };
}