import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sale.dart';

// ---------------------------------------------------------------------------
// Exception type callers already catch
// ---------------------------------------------------------------------------
class PrinterConnectionException implements Exception {
  final String message;
  const PrinterConnectionException(this.message);
  @override
  String toString() => 'PrinterConnectionException: $message';
}

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
  static const _mpesaInstructionKey = 'printer_mpesa_instruction';

  static const _firstRunKey = 'first_run_completed';
  static const _lastBackupReminderKey = 'last_backup_reminder_date';

  bool _connected = false;

  bool get isConnected => kIsWeb ? false : _connected;

  Future<List<BluetoothInfo>> scanBluetoothPrinters() async {
    if (kIsWeb) return [];
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<void> connectToPrinter(BluetoothInfo device) async {
    if (kIsWeb) return;
    final ok = await PrintBluetoothThermal.connect(
      macPrinterAddress: device.macAdress,
    );
    if (ok) {
      _connected = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_printerAddressKey, device.macAdress);
    } else {
      _connected = false;
      throw const PrinterConnectionException('Could not connect to printer');
    }
  }

  Future<bool> autoReconnect() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString(_printerAddressKey);
    if (address == null || address.isEmpty) return false;

    // Check if still connected
    if (await PrintBluetoothThermal.connectionStatus) {
      _connected = true;
      return true;
    }

    // Try reconnect with stored MAC
    try {
      final ok = await PrintBluetoothThermal.connect(
        macPrinterAddress: address,
      );
      _connected = ok;
      return ok;
    } catch (_) {
      _connected = false;
      return false;
    }
  }

  Future<PaperSize> getPaperSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_paperSizeKey) == '80'
        ? PaperSize.mm80
        : PaperSize.mm58;
  }

  Future<void> setPaperSize(PaperSize size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paperSizeKey, size == PaperSize.mm80 ? '80' : '58');
  }

  /// ---------------------------------------------------------------------------
  /// First-run setup
  /// ---------------------------------------------------------------------------
  Future<bool> isFirstRunCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_firstRunKey) ?? false;
  }

  Future<void> setFirstRunCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstRunKey, true);
  }

  /// Convenience: true when the app has NOT been set up yet.
  Future<bool> isFirstRun() => isFirstRunCompleted().then((v) => !v);

  /// ---------------------------------------------------------------------------
  /// Backup-reminder scheduling (weekly)
  /// ---------------------------------------------------------------------------
  /// Returns true when the monthly backup reminder should fire.
  static const _backupInterval = Duration(days: 30);

  Future<bool> shouldShowBackupReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final lastStr = prefs.getString(_lastBackupReminderKey);
    if (lastStr == null) {
      // First run — seed today so the reminder won't fire for 30 days.
      await prefs.setString(
        _lastBackupReminderKey,
        DateTime.now().toIso8601String(),
      );
      return false;
    }
    final last = DateTime.tryParse(lastStr);
    if (last == null) return false;
    return DateTime.now().difference(last) >= _backupInterval;
  }

  Future<void> markBackupReminderShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastBackupReminderKey,
      DateTime.now().toIso8601String(),
    );
  }

  Future<String> getShopName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_shopNameKey) ?? 'Shamamo Hardware Shop';
  }

  Future<String> getAddressPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_addressPhoneKey) ?? '';
  }

  Future<String> getFooterMessage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_footerKey) ?? 'Thank you!';
  }

  Future<String?> getMpesaInstruction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_mpesaInstructionKey);
  }

  Future<void> setMpesaInstruction(String? instruction) async {
    final prefs = await SharedPreferences.getInstance();
    if (instruction != null && instruction.trim().isNotEmpty) {
      await prefs.setString(_mpesaInstructionKey, instruction.trim());
    } else {
      await prefs.remove(_mpesaInstructionKey);
    }
  }

  Future<void> saveReceiptSettings({
    required String shopName,
    required String addressPhone,
    required String footerMessage,
    String? mpesaInstruction,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shopNameKey, shopName);
    await prefs.setString(_addressPhoneKey, addressPhone);
    await prefs.setString(_footerKey, footerMessage);
    if (mpesaInstruction != null) {
      await setMpesaInstruction(mpesaInstruction);
    }
  }

  Future<void> printSale({
    required Sale sale,
    required String staffName,
    required List<ReceiptItem> items,
    String? mpesaInstruction,
  }) async {
    if (kIsWeb) return;

    if (!_connected) {
      await autoReconnect();
    }
    if (!_connected) {
      throw const PrinterConnectionException('Printer not connected');
    }

    final paperSize = await getPaperSize();
    final shopName = await getShopName();
    final addressPhone = await getAddressPhone();
    final footerMessage = await getFooterMessage();
    final effectiveInstruction = mpesaInstruction ?? await getMpesaInstruction();
    if (mpesaInstruction != null) {
      await setMpesaInstruction(mpesaInstruction);
    }

    final bytes = await _buildTicketBytes(
      paperSize: paperSize,
      shopName: shopName,
      addressPhone: addressPhone,
      sale: sale,
      staffName: staffName,
      items: items,
      footerMessage: footerMessage,
      mpesaInstruction: effectiveInstruction,
    );

    _debugDump(
      paperSize: paperSize,
      shopName: shopName,
      addressPhone: addressPhone,
      sale: sale,
      staffName: staffName,
      items: items,
      footerMessage: footerMessage,
      mpesaInstruction: effectiveInstruction,
      bytes: bytes,
    );

    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) {
      _connected = false;
      throw const PrinterConnectionException('Print write failed');
    }
  }

  /// Public helper for testing and receipt generation
  Future<List<int>> generateReceiptBytes({
    required PaperSize paperSize,
    required String shopName,
    required String addressPhone,
    required Sale sale,
    required String staffName,
    required List<ReceiptItem> items,
    required String footerMessage,
    String? mpesaInstruction,
  }) {
    return _buildTicketBytes(
      paperSize: paperSize,
      shopName: shopName,
      addressPhone: addressPhone,
      sale: sale,
      staffName: staffName,
      items: items,
      footerMessage: footerMessage,
      mpesaInstruction: mpesaInstruction,
    );
  }

  // ---------------------------------------------------------------------------
  // Ticket builder using esc_pos_utils_plus
  // ---------------------------------------------------------------------------
  Future<List<int>> _buildTicketBytes({
    required PaperSize paperSize,
    required String shopName,
    required String addressPhone,
    required Sale sale,
    required String staffName,
    required List<ReceiptItem> items,
    required String footerMessage,
    String? mpesaInstruction,
  }) async {
    final profile = await CapabilityProfile.load();
    final ticket = Generator(paperSize, profile);
    final bytes = <int>[];
    bytes.addAll(
      ticket.text(
        shopName,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    );
    if (addressPhone.isNotEmpty) {
      bytes.addAll(
        ticket.text(
          addressPhone,
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
    }
    bytes.addAll(ticket.hr());
    bytes.addAll(ticket.text('Receipt #: ${sale.id}'));
    bytes.addAll(ticket.text('Date: ${formatReceiptDate(sale.timestamp)}'));
    bytes.addAll(ticket.text('Cashier: $staffName'));
    bytes.addAll(ticket.hr());

    // Header row
    final colWidths = _colWidths(paperSize);
    bytes.addAll(
      ticket.row([
        PosColumn(
          text: 'Item',
          width: colWidths[0],
          styles: const PosStyles(bold: true),
        ),
        PosColumn(
          text: 'Qty',
          width: colWidths[1],
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
        PosColumn(
          text: 'Total',
          width: colWidths[2],
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]),
    );
    bytes.addAll(ticket.hr());

    for (final item in items) {
      bytes.addAll(
        ticket.row([
          PosColumn(
            text: truncateItemName(item.name, paperSize),
            width: colWidths[0],
          ),
          PosColumn(
            text: formatQuantity(item.quantity),
            width: colWidths[1],
            styles: const PosStyles(align: PosAlign.center),
          ),
          PosColumn(
            text: formatMoney(item.total),
            width: colWidths[2],
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }

    bytes.addAll(ticket.hr());
    bytes.addAll(
      ticket.text(
        'Subtotal: ${formatMoney(sale.totalAmount)}',
        styles: const PosStyles(align: PosAlign.right),
      ),
    );
    bytes.addAll(
      ticket.text(
        'Discount: ${formatMoney(0)}',
        styles: const PosStyles(align: PosAlign.right),
      ),
    );
    bytes.addAll(
      ticket.text(
        'TOTAL: ${formatMoney(sale.totalAmount)}',
        styles: const PosStyles(
          align: PosAlign.right,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    );
    bytes.addAll(ticket.hr());
    bytes.addAll(ticket.text('Paid via: ${sale.paymentMethod}'));
    if (sale.paymentMethod == 'M-Pesa' && sale.mpesaCode != null && sale.mpesaCode!.isNotEmpty) {
      bytes.addAll(ticket.text('M-Pesa Code: ${sale.mpesaCode}'));
    }
    bytes.addAll(ticket.hr());
    if (mpesaInstruction != null && mpesaInstruction.trim().isNotEmpty) {
      bytes.addAll(
        ticket.text(
          mpesaInstruction.trim(),
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      );
      bytes.addAll(ticket.feed(1));
    }
    bytes.addAll(
      ticket.text(
        footerMessage,
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(ticket.cut());

    return bytes;
  }

  // 12 columns total (esc_pos_utils_plus uses 12-column grid)
  List<int> _colWidths(PaperSize size) {
    // [item, qty, total] in 12-column fractions
    return size == PaperSize.mm80 ? [6, 3, 3] : [5, 3, 4];
  }

  Future<void> dispose() async {
    if (kIsWeb) return;
    await PrintBluetoothThermal.disconnect;
    _connected = false;
  }

  // ---------------------------------------------------------------------------
  // Static helpers (unchanged API – callers and tests use these directly)
  // ---------------------------------------------------------------------------
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

  void _debugDump({
    required PaperSize paperSize,
    required String shopName,
    required String addressPhone,
    required Sale sale,
    required String staffName,
    required List<ReceiptItem> items,
    required String footerMessage,
    String? mpesaInstruction,
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
      if (sale.paymentMethod == 'M-Pesa' && sale.mpesaCode != null && sale.mpesaCode!.isNotEmpty)
        'M-Pesa Code: ${sale.mpesaCode}',
      '-' * 32,
      if (mpesaInstruction != null && mpesaInstruction.trim().isNotEmpty) ...[
        mpesaInstruction.trim(),
        '',
      ],
      footerMessage,
      '[CUT]',
    ];
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    debugPrint(
      '[Printer][DEBUG] Receipt (${paperSize == PaperSize.mm80 ? 80 : 58}mm):\n${lines.join('\n')}',
    );
    debugPrint('[Printer][DEBUG] ESC/POS bytes (${bytes.length}): $hex');
  }
}
