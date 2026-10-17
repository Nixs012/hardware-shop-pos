import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
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

  bool get isConnected => kIsWeb ? false : _manager.isConnected;

  Future<List<BluetoothPrinterDevice>> scanBluetoothPrinters() async {
    if (kIsWeb) return [];
    final devices = await _manager.scanPrinters(
      types: {PrinterConnectionType.bluetooth},
      timeout: const Duration(seconds: 5),
    );
    return devices.whereType<BluetoothPrinterDevice>().toList();
  }

  Future<void> connectToPrinter(BluetoothPrinterDevice device) async {
    if (kIsWeb) return;
    await _manager.connect(device);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_printerAddressKey, device.address);
  }

  Future<bool> autoReconnect() async {
    if (kIsWeb) return false;
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
    if (kIsWeb) return;
    if (!isConnected) {
      await autoReconnect();
    }
    if (!isConnected) {
      throw const PrinterConnectionException('Printer not connected');
    }

    final paperSize = await getPaperSize();
    final ticket = await Ticket.create(paperSize);
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
    ticket.text('Date: ${formatReceiptDate(sale.timestamp)}');
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
        PrintColumn(
          text: truncateItemName(item.name, paperSize),
          flex: 5,
        ),
        PrintColumn(
          text: formatQuantity(item.quantity),
          flex: 2,
          align: PrintAlign.center,
        ),
        PrintColumn(text: formatMoney(item.total), flex: 3, align: PrintAlign.right),
      ]);
    }
    ticket.separator();
    ticket.text(
      'Subtotal: ${formatMoney(sale.totalAmount)}',
      align: PrintAlign.right,
    );
    ticket.text('Discount: ${formatMoney(0)}', align: PrintAlign.right);
    ticket.text(
      'TOTAL: ${formatMoney(sale.totalAmount)}',
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
      paperSize: paperSize,
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

  Future<void> dispose() async {
    if (kIsWeb) return;
    await _manager.dispose();
  }

  static String formatReceiptDate(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year  $hour:$minute';
  }

  static String truncateItemName(String name, PaperSize paperSize) {
    final maxLen = paperSize == PaperSize.mm80 ? 24 : 16;
    if (name.length <= maxLen) return name;
    return '${name.substring(0, maxLen - 1)}…';
  }

  static String formatMoney(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final integerPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$integerPart.${parts[1]}';
  }

  static String formatQuantity(double quantity) {
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
      'Date: ${formatReceiptDate(sale.timestamp)}',
      'Cashier: $staffName',
      '-' * 32,
      'Item                 Qty      Total',
      '-' * 32,
      ...items.map(
        (item) =>
            '${truncateItemName(item.name, paperSize)}  ${formatQuantity(item.quantity)}  ${formatMoney(item.total)}',
      ),
      '-' * 32,
      'Subtotal: ${formatMoney(sale.totalAmount)}',
      'Discount: ${formatMoney(0)}',
      'TOTAL: ${formatMoney(sale.totalAmount)}',
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
