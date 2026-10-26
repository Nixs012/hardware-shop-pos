import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/customer_payment.dart';
import '../../models/sale.dart';
import '../../models/staff.dart';
import '../../services/firestore_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/credit_balance.dart';
import '../../utils/theme.dart';
import '../../widgets/error_display_widgets.dart';

class CustomerCreditScreen extends StatefulWidget {
  final Staff currentStaff;
  final FirestoreService? firestoreService;

  const CustomerCreditScreen({super.key, required this.currentStaff, this.firestoreService});

  @override
  State<CustomerCreditScreen> createState() => _CustomerCreditScreenState();
}

class _CustomerCreditScreenState extends State<CustomerCreditScreen> {
  FirestoreService? _injectedFirestoreService;

  FirestoreService get _firestoreService =>
      _injectedFirestoreService ??= widget.firestoreService ??
          FirestoreServiceImpl(widget.currentStaff.shopId);

  String _searchQuery = '';

  String _money(double amount) => CurrencyFormatter.format(amount);

  /// Computes outstanding balance per customer based on ALL credit sales
  /// minus ALL repayments across all time.
  ///
  /// Delegates to the shared [computeCustomerBalances] function so the Credit
  /// screen and the Reports credit card always agree.
  Map<String, CustomerCreditBalance> _computeBalances(
    List<Sale> sales,
    List<CustomerPayment> payments,
  ) =>
      computeCustomerBalances(sales, payments);

  Future<void> _showRecordRepaymentDialog(CustomerCreditBalance customer) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Text(
          'Record Repayment from ${customer.customerName}',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Outstanding Balance: ${_money(customer.outstanding)}',
                style: const TextStyle(
                  color: AppTheme.secondaryColor,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Repayment Amount (KSh)',
                  hintText: 'e.g. 2000',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Note (Optional)',
                  hintText: 'e.g. Partial payment',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: AppTheme.textPrimary,
            ),
            onPressed: () async {
              final amount =
                  double.tryParse(amountController.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid repayment amount.'),
                    backgroundColor: AppTheme.errorColor,
                  ),
                );
                return;
              }

              final payment = CustomerPayment(
                id: const Uuid().v4(),
                customerName: customer.customerName,
                customerPhone: customer.customerPhone,
                amount: amount,
                paymentMethod: 'Repayment',
                timestamp: DateTime.now(),
                staffId: widget.currentStaff.id,
                note: noteController.text.trim().isEmpty
                    ? null
                    : noteController.text.trim(),
              );

              await _firestoreService.recordCustomerPayment(payment);
              if (!dialogCtx.mounted) return;
              Navigator.pop(dialogCtx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Repayment of ${_money(amount)} recorded for ${customer.customerName}.',
                    ),
                    backgroundColor: AppTheme.successColor,
                  ),
                );
              }
            },
            icon: const Icon(Icons.payment, size: 16),
            label: const Text('Save Repayment'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceColor,
        elevation: 0,
        title: const Text(
          'Customer Credit (Khata)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: StreamBuilder<List<Sale>>(
        stream: _firestoreService.getSalesStream(isAdmin: true),
        builder: (context, salesSnapshot) {
          return StreamBuilder<List<CustomerPayment>>(
            stream: _firestoreService.getCustomerPaymentsStream(),
            builder: (context, paymentsSnapshot) {
              final sales = salesSnapshot.data ?? [];
              final payments = paymentsSnapshot.data ?? [];

              final balancesMap =
                  _computeBalances(sales, payments);
              var balances = balancesMap.values.toList();

              // Filter by search query
              if (_searchQuery.isNotEmpty) {
                balances = balances
                    .where((b) =>
                        b.customerName
                            .toLowerCase()
                            .contains(_searchQuery.toLowerCase()) ||
                        (b.customerPhone.contains(_searchQuery)))
                    .toList();
              }

              // Only show customers with outstanding balance > 0
              balances = balances
                  .where((b) => b.outstanding > 0)
                  .toList()
                  ..sort((a, b) => b.outstanding.compareTo(a.outstanding));

              if (salesSnapshot.connectionState == ConnectionState.waiting &&
                  paymentsSnapshot.connectionState == ConnectionState.waiting &&
                  salesSnapshot.data == null &&
                  paymentsSnapshot.data == null) {
                return const Center(child: CircularProgressIndicator());
              }

              if (salesSnapshot.hasError || paymentsSnapshot.hasError) {
                final error = salesSnapshot.hasError
                    ? salesSnapshot.error
                    : paymentsSnapshot.error;
                final stack = salesSnapshot.hasError
                    ? salesSnapshot.stackTrace
                    : paymentsSnapshot.stackTrace;
                return ErrorDisplayWidget(
                  error: error,
                  stackTrace: stack,
                  onRetry: () => setState(() {}),
                  fallbackMessage: 'Error loading customer credit data.',
                );
              }

              return Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      onChanged: (val) =>
                          setState(() => _searchQuery = val),
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search customer name or phone...',
                        hintStyle:
                            TextStyle(color: AppTheme.textSecondary),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: AppTheme.cardBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  // Summary card
                  if (balances.isNotEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16.0),
                      child: _buildSummaryCard(balances),
                    ),
                  const SizedBox(height: 16),
                  // Customer list
                  Expanded(
                    child: balances.isEmpty
                        ? const Center(
                            child: Text(
                              'No customers with outstanding credit.',
                              style: TextStyle(
                                color: AppTheme.secondaryColor,
                                fontSize: 14,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16.0),
                            itemCount: balances.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final customer = balances[index];
                              return Card(
                                color: AppTheme.cardBackground,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                                  side: BorderSide(
                                    color: AppTheme.borderColor,
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppTheme.sp16,
                                    vertical: AppTheme.sp8,
                                  ),
                                  leading: CircleAvatar(
                                    radius: 22,
                                    backgroundColor:
                                        AppTheme.warningColor.withValues(alpha: 0.2),
                                    child: const Icon(
                                      Icons.person,
                                      color: AppTheme.highlightColor,
                                      size: 22,
                                    ),
                                  ),
                                  title: Text(
                                    customer.customerName,
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (customer.customerPhone.isNotEmpty)
                                        Text(
                                          customer.customerPhone,
                                          style: const TextStyle(
                                            color: AppTheme.secondaryColor,
                                            fontSize: 12,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Credit Sales: ${_money(customer.totalCreditSales)} • Repayments: ${_money(customer.totalRepayments)}',
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _money(customer.outstanding),
                                        style: TextStyle(
                                          color: customer.outstanding > 0
                                              ? AppTheme.errorColor
                                              : AppTheme.successColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Outstanding',
                                        style: TextStyle(
                                          color: customer.outstanding > 0
                                              ? AppTheme.errorColor
                                              : AppTheme.successColor,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _showCustomerDetailDialog(
                                      context, customer, payments,
                                      sales: sales),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(List<CustomerCreditBalance> balances) {
    final totalOutstanding = balances.fold<double>(
        0, (sum, b) => sum + b.outstanding);

    return Card(
      color: AppTheme.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: AppTheme.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildSummaryMetric(
              'Customers in Debt',
              '${balances.length}',
              AppTheme.errorColor,
            ),
            Container(
              width: 1,
              color: AppTheme.secondaryColor.withValues(alpha: 0.2),
            ),
            _buildSummaryMetric(
              'Total Outstanding',
              _money(totalOutstanding),
              AppTheme.warningColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.secondaryColor,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  void _showCustomerDetailDialog(
    BuildContext ctx,
    CustomerCreditBalance customer,
    List<CustomerPayment> allPayments, {
    required List<Sale> sales,
  }) async {
    final customerPayments = allPayments
        .where((p) => p.customerName == customer.customerName)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final customerSales = sales
        .where((s) => s.customerName == customer.customerName)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              customer.customerName,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (customer.customerPhone.isNotEmpty)
              Text(
                customer.customerPhone,
                style: const TextStyle(
                  color: AppTheme.secondaryColor,
                  fontSize: 13,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Outstanding: ${_money(customer.outstanding)}',
              style: const TextStyle(
                color: AppTheme.errorColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _showRecordRepaymentDialog(customer);
                },
                icon: const Icon(Icons.payment, size: 16),
                label: const Text('Record Repayment'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Credit Sales',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              if (customerSales.isEmpty)
                const Text(
                  'No credit sales found.',
                  style: TextStyle(color: AppTheme.secondaryColor, fontSize: 11),
                )
              else
                ...customerSales.take(5).map((sale) {
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                    title: Text(
                      '${sale.lineItems.length} item(s) • ${_money(sale.totalAmount)}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                    subtitle: Text(
                      '${sale.timestamp.toLocal()}'.split('.').first,
                      style: const TextStyle(
                        color: AppTheme.secondaryColor,
                        fontSize: 10,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.receipt_long,
                      color: AppTheme.secondaryColor,
                      size: 14,
                    ),
                  );
                }),
              const SizedBox(height: 8),
              const Text(
                'Repayments',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              if (customerPayments.isEmpty)
                const Text(
                  'No repayments recorded.',
                  style: TextStyle(color: AppTheme.secondaryColor, fontSize: 11),
                )
              else
                ...customerPayments.take(5).map((payment) {
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                    leading: const Icon(
                      Icons.arrow_downward,
                      color: AppTheme.successColor,
                      size: 14,
                    ),
                    title: Text(
                      _money(payment.amount),
                      style: const TextStyle(
                        color: AppTheme.successColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${payment.timestamp.toLocal()}'.split('.').first,
                      style: const TextStyle(
                        color: AppTheme.secondaryColor,
                        fontSize: 10,
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}




