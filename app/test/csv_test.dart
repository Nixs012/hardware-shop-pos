import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for CSV parsing and encoding logic used by CsvExportService.
/// These tests validate the CSV package usage (csv v8 API: CsvEncoder, CsvDecoder)
/// and ensure the import/export CSV format is correct.
void main() {
  final CsvEncoder encoder = CsvEncoder();
  final CsvDecoder decoder = CsvDecoder();

  group('CsvDecoder (csv v8 API)', () {
    test('parses CSV with standard headers', () {
      final csv = 'name,sku,category,selling_price,cost_price,quantity_on_hand,low_stock_threshold,unit\n'
          'Hammer,HM001,Tools,15.50,8.00,100,10,piece\n'
          'Nails,P100,Hardware,0.10,0.05,1000,50,box';
      final rows = decoder.convert(csv);

      expect(rows.length, 3);

      // Header row
      expect(rows[0], [
        'name', 'sku', 'category', 'selling_price',
        'cost_price', 'quantity_on_hand', 'low_stock_threshold', 'unit'
      ]);

      // Data rows
      expect(rows[1], ['Hammer', 'HM001', 'Tools', '15.50', '8.00', '100', '10', 'piece']);
      expect(rows[2], ['Nails', 'P100', 'Hardware', '0.10', '0.05', '1000', '50', 'box']);
    });

    test('parses CSV with empty rows (skipped)', () {
      final csv = 'name,sku,selling_price\nProduct,A1,10.00\n';
      final rows = decoder.convert(csv);
      // Trailing newline should not create an extra empty row
      expect(rows.length, 2);
    });

    test('handles CSV with quoted fields', () {
      final csv = 'name,description\n"Widget, Special","A ""quoted"" widget"';
      final rows = decoder.convert(csv);

      expect(rows[1][0], 'Widget, Special');
      expect(rows[1][1], 'A "quoted" widget');
    });

    test('parses CSV with numeric values as strings', () {
      final csv = 'selling_price\n15.50\n0.10';
      final rows = decoder.convert(csv);

      expect(rows[1][0], '15.50');
      expect(rows[2][0], '0.10');
    });
  });

  group('CsvEncoder (csv v8 API)', () {
    test('encodes rows to CSV string', () {
      final rows = [
        ['name', 'sku', 'price'],
        ['Hammer', 'HM001', '15.50'],
      ];
      final csv = encoder.convert(rows);

      expect(csv, contains('name,sku,price'));
      expect(csv, contains('Hammer,HM001,15.50'));
    });

    test('encodes empty rows list', () {
      final csv = encoder.convert([]);
      expect(csv, '');
    });

    test('handles special characters in CSV by quoting', () {
      final rows = [
        ['name', 'note'],
        ['Widget, Inc', 'Has "quotes"'],
      ];
      final csv = encoder.convert(rows);

      expect(csv, contains('"Widget, Inc"'));
      expect(csv, contains('"Has ""quotes""'));
    });
  });

  group('CSV round-trip (import/export)', () {
    test('encode then decode preserves data', () {
      final originalRows = [
        ['name', 'sku', 'category', 'selling_price'],
        ['Hammer', 'HM001', 'Tools', '15.50'],
        ['Nails', 'P100', 'Hardware', '0.10'],
      ];

      final csv = encoder.convert(originalRows);
      final decoded = decoder.convert(csv);

      expect(decoded, equals(originalRows));
    });
  });

  group('CSV import column mapping logic', () {
    test('required columns: name, sku, selling_price', () {
      final csv = 'name,sku,selling_price,cost_price,quantity_on_hand,low_stock_threshold,unit,category\n'
          'Hammer,HM001,15.50,8.00,100,10,piece,Tools';

      final rows = decoder.convert(csv);
      final header = rows.first.map((c) => c.toString().toLowerCase().trim()).toList();

      final colMap = <String, int>{};
      for (int i = 0; i < header.length; i++) {
        colMap[header[i]] = i;
      }

      expect(colMap['name'], 0);
      expect(colMap['sku'], 1);
      expect(colMap['selling_price'], 2);
      expect(colMap['cost_price'], 3);
      expect(colMap['quantity_on_hand'], 4);
      expect(colMap['low_stock_threshold'], 5);
      expect(colMap['unit'], 6);
      expect(colMap['category'], 7);
    });

    test('missing required columns produces error', () {
      // CSV without 'name' column
      final csv = 'sku,selling_price\nHM001,15.50';
      final rows = decoder.convert(csv);
      final header = rows.first.map((c) => c.toString().toLowerCase().trim()).toList();

      final hasRequiredColumns = header.contains('name') &&
          header.contains('sku') &&
          header.contains('selling_price');

      expect(hasRequiredColumns, isFalse);
    });

    test('column order is flexible', () {
      final csv = 'selling_price,name,category,sku,unit,cost_price,quantity_on_hand,low_stock_threshold\n'
          '15.50,Hammer,Tools,HM001,piece,8.00,100,10';

      final rows = decoder.convert(csv);
      final header = rows.first.map((c) => c.toString().toLowerCase().trim()).toList();

      final colMap = <String, int>{};
      for (int i = 0; i < header.length; i++) {
        colMap[header[i]] = i;
      }

      // Name should now be at index 1, selling_price at 0
      expect(colMap['selling_price'], 0);
      expect(colMap['name'], 1);
      expect(colMap['category'], 2);
      expect(colMap['sku'], 3);
    });

    test('parsing double values from CSV cells', () {
      final csv = 'name,selling_price,cost_price,quantity_on_hand,low_stock_threshold\n'
          'Hammer,15.50,8.00,100,10';

      final rows = decoder.convert(csv);
      final header = rows.first.map((c) => c.toString().toLowerCase().trim()).toList();
      final colMap = <String, int>{};
      for (int i = 0; i < header.length; i++) {
        colMap[header[i]] = i;
      }

      final row = rows[1];

      // Simulate _getCell + double.tryParse
      final sellingPrice = double.tryParse(row[colMap['selling_price'] as int].toString().trim()) ?? 0.0;
      final costPrice = double.tryParse(row[colMap['cost_price'] as int].toString().trim()) ?? 0.0;
      final quantity = double.tryParse(row[colMap['quantity_on_hand'] as int].toString().trim()) ?? 0.0;
      final lowStock = double.tryParse(row[colMap['low_stock_threshold'] as int].toString().trim()) ?? 0.0;

      expect(sellingPrice, 15.50);
      expect(costPrice, 8.00);
      expect(quantity, 100.0);
      expect(lowStock, 10.0);
    });

    test('invalid number defaults to 0.0', () {
      final csv = 'name,selling_price\nBadProduct,N/A';
      final rows = decoder.convert(csv);
      final header = rows.first.map((c) => c.toString().toLowerCase().trim()).toList();
      final colMap = <String, int>{};
      for (int i = 0; i < header.length; i++) {
        colMap[header[i]] = i;
      }

      final row = rows[1];
      final sellingPrice = double.tryParse(row[colMap['selling_price'] as int].toString().trim()) ?? 0.0;

      expect(sellingPrice, 0.0);
    });

    test('skip rows with fewer than 3 columns (blank rows)', () {
      final csv = 'name,sku,selling_price\nHammer,HM001,15.50\n\n';
      final rows = decoder.convert(csv);

      expect(rows.length, 2); // Header + 1 data row, trailing empty line ignored
    });
  });
}



