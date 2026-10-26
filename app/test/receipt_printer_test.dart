import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' show PaperSize;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/models/sale.dart';
import 'package:app/services/printer_service.dart';

void main() {
  group('Phase 4 - Thermal Receipt Printing & Formatting Tests', () {
    test('formatReceiptDate formats timestamp as DD/MM/YYYY  HH:mm', () {
      final dt = DateTime(2026, 8, 26, 14, 32);
      final formatted = PrinterService.formatReceiptDate(dt);
      expect(formatted, equals('26/08/2026  14:32'));

      final singleDigits = DateTime(2026, 5, 4, 9, 7);
      final formattedSingle = PrinterService.formatReceiptDate(singleDigits);
      expect(formattedSingle, equals('04/05/2026  09:07'));
    });

    test('formatMoney adds thousands comma separation and keeps 2 decimals', () {
      expect(PrinterService.formatMoney(450.0), equals('450.00'));
      expect(PrinterService.formatMoney(1200.0), equals('1,200.00'));
      expect(PrinterService.formatMoney(1234567.89), equals('1,234,567.89'));
      expect(PrinterService.formatMoney(0.0), equals('0.00'));
    });

    test('formatQuantity formats integers cleanly and decimals with 2 decimal places', () {
      expect(PrinterService.formatQuantity(3.0), equals('3'));
      expect(PrinterService.formatQuantity(1.0), equals('1'));
      expect(PrinterService.formatQuantity(2.5), equals('2.50'));
      expect(PrinterService.formatQuantity(0.75), equals('0.75'));
    });

    test('truncateItemName protects 58mm layout from wide product names', () {
      const shortName = 'PVC Pipe 2"';
      expect(
        PrinterService.truncateItemName(shortName, PaperSize.mm58),
        equals('PVC Pipe 2"'),
      );

      const longName = 'Galvanized Hex Head Bolt M10x50';
      // For 58mm: max 16 chars (15 chars + ellipsis)
      final truncated58 = PrinterService.truncateItemName(longName, PaperSize.mm58);
      expect(truncated58.length, lessThanOrEqualTo(16));
      expect(truncated58.endsWith('…'), isTrue);

      // For 80mm: allows wider up to 24 chars
      final truncated80 = PrinterService.truncateItemName(longName, PaperSize.mm80);
      expect(truncated80.length, lessThanOrEqualTo(24));
      expect(truncated80.length, greaterThan(truncated58.length));
    });

    test('ReceiptItem correctly models name, quantity, and total', () {
      const item = ReceiptItem(
        name: 'Cement 50kg',
        quantity: 2,
        total: 1500.0,
      );
      expect(item.name, equals('Cement 50kg'));
      expect(item.quantity, equals(2));
      expect(item.total, equals(1500.0));
    });

    test('PaperSize and receipt customization persist via SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final service = PrinterService();

      // Default paper size is 58mm
      expect(await service.getPaperSize(), equals(PaperSize.mm58));

      // Switch to 80mm
      await service.setPaperSize(PaperSize.mm80);
      expect(await service.getPaperSize(), equals(PaperSize.mm80));

      // Default shop name
      expect(await service.getShopName(), equals('Shamamo Hardware Shop'));

      // Save custom details
      await service.saveReceiptSettings(
        shopName: 'Super Hardware Ltd',
        addressPhone: 'Plot 4, Main Street / 0712345678',
        footerMessage: 'Goods once sold are not returnable. Thank you!',
      );

      expect(await service.getShopName(), equals('Super Hardware Ltd'));
      expect(await service.getAddressPhone(), equals('Plot 4, Main Street / 0712345678'));
      expect(await service.getFooterMessage(), equals('Goods once sold are not returnable. Thank you!'));
    });

    test('printSale throws PrinterConnectionException when printer is disconnected', () async {
      SharedPreferences.setMockInitialValues({});
      final service = PrinterService();

      final sale = Sale(
        id: 'sale-test-999',
        timestamp: DateTime.now(),
        staffId: 'staff-1',
        paymentMethod: 'Cash',
        lineItems: [],
      );

      // On disconnected environment without live Bluetooth printer, printSale must throw
      // PrinterConnectionException without crashing the app, enabling caller retry handling
      expect(
        () async => await service.printSale(
          sale: sale,
          staffName: 'Alice',
          items: [],
        ),
        throwsA(isA<PrinterConnectionException>()),
      );
    });
  });
}



