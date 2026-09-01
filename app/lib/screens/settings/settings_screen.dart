import 'package:flutter/material.dart';

import '../../models/failed_sale.dart';
import '../../models/staff.dart';
import '../../services/firestore_service.dart';
import '../../utils/theme.dart';

class SettingsScreen extends StatefulWidget {
  final Staff currentStaff;

  const SettingsScreen({super.key, required this.currentStaff});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _firestoreService = FirestoreService();
  late Future<List<FailedSaleRecord>> _failedSalesFuture;

  bool get _isAdmin => widget.currentStaff.role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    _failedSalesFuture = _loadFailedSales();
  }

  Future<List<FailedSaleRecord>> _loadFailedSales() {
    return _isAdmin ? _firestoreService.getFailedSales() : Future.value([]);
  }

  void _refreshFailedSales() {
    setState(() {
      _failedSalesFuture = _loadFailedSales();
    });
  }

  Future<void> _retry(FailedSaleRecord record) async {
    try {
      await _firestoreService.retryFailedSale(record);
      if (!mounted) return;
      _refreshFailedSales();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale sync retry completed.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _refreshFailedSales();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Retry failed and remains in Needs Review: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const Center(child: Text('Settings Screen'));
    }

    return RefreshIndicator(
      onRefresh: () async => _refreshFailedSales(),
      child: FutureBuilder<List<FailedSaleRecord>>(
        future: _failedSalesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final failedSales = snapshot.data ?? [];
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Needs Review',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sales that failed to sync are stored on this device until an Admin retries them.',
                style: TextStyle(
                  color: AppTheme.secondaryColor.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 16),
              if (failedSales.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: Text('No failed sales need review.')),
                )
              else
                ...failedSales.map(_buildFailedSale),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFailedSale(FailedSaleRecord record) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'KSh ${record.sale.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.sync, color: AppTheme.primaryColor),
                  tooltip: 'Retry sync',
                  onPressed: () => _retry(record),
                ),
              ],
            ),
            Text(
              'Sale: ${record.sale.id}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              'Failed: ${record.failedAt.toLocal()}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              'Error: ${record.errorMessage}',
              style: const TextStyle(color: Colors.redAccent),
            ),
            const SizedBox(height: 8),
            Text(
              '${record.sale.lineItems.length} line item(s), paid via ${record.sale.paymentMethod}',
              style: TextStyle(
                color: AppTheme.secondaryColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
