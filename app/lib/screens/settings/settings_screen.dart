import 'package:flutter/material.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import '../../models/failed_sale.dart';
import '../../models/staff.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/printer_service.dart';
import '../../utils/theme.dart';

class SettingsScreen extends StatefulWidget {
  final Staff currentStaff;

  const SettingsScreen({super.key, required this.currentStaff});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _firestoreService = FirestoreService();
  final _printerService = PrinterService();
  final _shopNameController = TextEditingController();
  final _addressPhoneController = TextEditingController();
  final _footerController = TextEditingController();
  late Future<List<FailedSaleRecord>> _failedSalesFuture;
  PaperSize _paperSize = PaperSize.mm58;
  bool _printerConnected = false;
  bool _scanning = false;

  bool get _isAdmin => widget.currentStaff.role.toLowerCase() == 'admin';

  @override
  void initState() {
    super.initState();
    _failedSalesFuture = _loadFailedSales();
    _loadPrinterSettings();
  }

  Future<void> _loadPrinterSettings() async {
    _shopNameController.text = await _printerService.getShopName();
    _addressPhoneController.text = await _printerService.getAddressPhone();
    _footerController.text = await _printerService.getFooterMessage();
    _paperSize = await _printerService.getPaperSize();
    _printerConnected = await _printerService.autoReconnect();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _addressPhoneController.dispose();
    _footerController.dispose();
    _printerService.dispose();
    super.dispose();
  }

  Future<void> _scanPrinters() async {
    setState(() => _scanning = true);
    try {
      final printers = await _printerService.scanBluetoothPrinters();
      if (!mounted) return;
      if (printers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No Bluetooth printers found.')),
        );
        return;
      }
      final selected = await showDialog<BluetoothPrinterDevice>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Select Bluetooth Printer'),
          children: printers
              .map(
                (printer) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, printer),
                  child: Text('${printer.name}\n${printer.address}'),
                ),
              )
              .toList(),
        ),
      );
      if (selected == null) return;
      await _printerService.connectToPrinter(selected);
      if (mounted) {
        setState(() => _printerConnected = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printer connected and saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Printer scan/connect failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _savePrinterSettings() async {
    await _printerService.setPaperSize(_paperSize);
    await _printerService.saveReceiptSettings(
      shopName: _shopNameController.text.trim(),
      addressPhone: _addressPhoneController.text.trim(),
      footerMessage: _footerController.text.trim().isEmpty
          ? 'Thank you!'
          : _footerController.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Printer settings saved.')));
    }
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
              if (_isAdmin) ...[
                _buildPrinterSection(),
                const SizedBox(height: 24),
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
                const Divider(height: 48, color: Colors.white24),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () async {
                    await AuthService().logout();
                  },
                  icon: const Icon(Icons.logout, color: Colors.white),
                  label: const Text(
                    'Log Out',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPrinterSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Printer',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_printerConnected ? 'Connected' : 'Not connected'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _scanning ? null : _scanPrinters,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(
                _scanning ? 'Scanning...' : 'Scan Bluetooth Printers',
              ),
            ),
            TextField(
              controller: _shopNameController,
              decoration: const InputDecoration(labelText: 'Shop name'),
            ),
            TextField(
              controller: _addressPhoneController,
              decoration: const InputDecoration(labelText: 'Address / phone'),
            ),
            TextField(
              controller: _footerController,
              decoration: const InputDecoration(labelText: 'Footer message'),
            ),
            DropdownButton<PaperSize>(
              value: _paperSize,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: PaperSize.mm58,
                  child: Text('Paper width: 58mm'),
                ),
                DropdownMenuItem(
                  value: PaperSize.mm80,
                  child: Text('Paper width: 80mm'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _paperSize = value ?? PaperSize.mm58),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _savePrinterSettings,
                icon: const Icon(Icons.save),
                label: const Text('Save printer settings'),
              ),
            ),
          ],
        ),
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
