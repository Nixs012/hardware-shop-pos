import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import '../models/sale.dart';

class ReceiptItem {
  final String name;
  final double quantity;
  final double total;

  const ReceiptItem({
    required this.name,
    required this.quantity,
    required this.total,
  });
}

class PrinterService {
  static const _printerAddressKey = 'printer_bluetooth_address';
  static const _paperSizeKey = 'printer_paper_size';
  static const _shopNameKey = 'printer_shop_name';
  static const _addressPhoneKey = 'printer_address_phone';
  static const _footerKey = 'printer_footer';

  final PrinterManager _manager = PrinterManager();

  bool get isConnected => _manager.isConnected;

  Future<List<BluetoothPrinterDevice>> scanBluetoothPrinters() async {
    final devices = await _manager.scanPrinters(
      types: {PrinterConnectionType.bluetooth},
      timeout: const Duration(seconds: 5),
    );
    return devices.whereType<BluetoothPrinterDevice>().toList();
  }

  Future<void> connectToPrinter(BluetoothPrinterDevice device) async {
    await _manager.connect(device);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_printerAddressKey, device.address);
  }

  Future<bool> autoReconnect() async {
    final preferences = await SharedPreferences.getInstance();
    final address = preferences.getString(_printerAddressKey);
    if (address == null || address.isEmpty) return false;

    try {
      await connectToPrinter(
        BluetoothPrinterDevice(name: address, address: address),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<PaperSize> getPaperSize() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_paperSizeKey) == '80'
        ? PaperSize.mm80
        : PaperSize.mm58;
  }

  Future<void> setPaperSize(PaperSize size) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _paperSizeKey,
      size == PaperSize.mm80 ? '80' : '58',
    );
  }

  Future<String> getShopName() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_shopNameKey) ?? 'Shamamo Hardware Shop';
  }

  Future<String> getAddressPhone() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_addressPhoneKey) ?? '';
  }

  Future<String> getFooterMessage() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_footerKey) ?? 'Thank you!';
  }

  Future<void> saveReceiptSettings({
    required String shopName,
    required String addressPhone,
    required String footerMessage,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_shopNameKey, shopName);
    await preferences.setString(_addressPhoneKey, addressPhone);
    await preferences.setString(_footerKey, footerMessage);
  }

  Future<void> printSale({
    required Sale sale,
    required String staffName,
    required List<ReceiptItem> items,
  }) async {
    if (!isConnected) {
      await autoReconnect();
    }
    if (!isConnected) {
      throw const PrinterConnectionException('Printer not connected');
    }

    final ticket = await Ticket.create(await getPaperSize());
    final shopName = await getShopName();
    final addressPhone = await getAddressPhone();
    final footerMessage = await getFooterMessage();

    ticket.text(
      shopName,
      align: PrintAlign.center,
      style: const PrintTextStyle(
        bold: true,
        height: TextSize.size2,
        width: TextSize.size2,
      ),
    );
    if (addressPhone.isNotEmpty) {
      ticket.text(addressPhone, align: PrintAlign.center);
    }
    ticket.separator();
    ticket.text('Receipt #: ${sale.id}');
    ticket.text('Date: ${sale.timestamp.toLocal()}');
    ticket.text('Cashier: $staffName');
    ticket.separator();
    ticket.row([
      PrintColumn(
        text: 'Item',
        flex: 5,
        style: const PrintTextStyle(bold: true),
      ),
      PrintColumn(
        text: 'Qty',
        flex: 2,
        align: PrintAlign.center,
        style: const PrintTextStyle(bold: true),
      ),
      PrintColumn(
        text: 'Total',
        flex: 3,
        align: PrintAlign.right,
        style: const PrintTextStyle(bold: true),
      ),
    ]);
    ticket.separator();
    for (final item in items) {
      ticket.row([
        PrintColumn(text: item.name, flex: 5),
        PrintColumn(
          text: _formatQuantity(item.quantity),
          flex: 2,
          align: PrintAlign.center,
        ),
        PrintColumn(text: _money(item.total), flex: 3, align: PrintAlign.right),
      ]);
    }
    ticket.separator();
    ticket.text(
      'Subtotal: ${_money(sale.totalAmount)}',
      align: PrintAlign.right,
    );
    ticket.text('Discount: ${_money(0)}', align: PrintAlign.right);
    ticket.text(
      'TOTAL: ${_money(sale.totalAmount)}',
      align: PrintAlign.right,
      style: const PrintTextStyle(
        bold: true,
        height: TextSize.size2,
        width: TextSize.size2,
      ),
    );
    ticket.separator();
    ticket.text('Paid via: ${sale.paymentMethod}');
    ticket.separator();
    ticket.text(footerMessage, align: PrintAlign.center);
    ticket.cut();

    _debugPrintTicket(
      paperSize: await getPaperSize(),
      shopName: shopName,
      addressPhone: addressPhone,
      sale: sale,
      staffName: staffName,
      items: items,
      footerMessage: footerMessage,
      bytes: ticket.bytes,
    );
    await _manager.printTicket(ticket);
  }

  Future<void> dispose() => _manager.dispose();

  String _money(double amount) => 'KSh ${amount.toStringAsFixed(2)}';

  String _formatQuantity(double quantity) {
    return quantity == quantity.roundToDouble()
        ? quantity.toInt().toString()
        : quantity.toStringAsFixed(2);
  }

  void _debugPrintTicket({
    required PaperSize paperSize,
    required String shopName,
    required String addressPhone,
    required Sale sale,
    required String staffName,
    required List<ReceiptItem> items,
    required String footerMessage,
    required List<int> bytes,
  }) {
    if (!kDebugMode) return;

    final lines = <String>[
      shopName,
      if (addressPhone.isNotEmpty) addressPhone,
      '-' * 32,
      'Receipt #: ${sale.id}',
      'Date: ${sale.timestamp.toLocal()}',
      'Cashier: $staffName',
      '-' * 32,
      'Item                 Qty      Total',
      '-' * 32,
      ...items.map(
        (item) =>
            '${item.name}  ${_formatQuantity(item.quantity)}  ${_money(item.total)}',
      ),
      '-' * 32,
      'Subtotal: ${_money(sale.totalAmount)}',
      'Discount: ${_money(0)}',
      'TOTAL: ${_money(sale.totalAmount)}',
      '-' * 32,
      'Paid via: ${sale.paymentMethod}',
      '-' * 32,
      footerMessage,
      '[CUT]',
    ];
    final hexBytes = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');

    debugPrint(
      '[Printer][DEBUG] Receipt preview (${paperSize.widthMM}mm):\n${lines.join('\n')}',
    );
    debugPrint('[Printer][DEBUG] ESC/POS bytes (${bytes.length}): $hexBytes');
  }
}
