import 'sale.dart';

class FailedSaleRecord {
  final Sale sale;
  final String errorMessage;
  final DateTime failedAt;

  FailedSaleRecord({
    required this.sale,
    required this.errorMessage,
    required this.failedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'sale': sale.toMap(),
      'error_message': errorMessage,
      'failed_at': failedAt.toIso8601String(),
    };
  }

  factory FailedSaleRecord.fromMap(Map<String, dynamic> map) {
    final saleMap = Map<String, dynamic>.from(map['sale'] as Map);
    return FailedSaleRecord(
      sale: Sale.fromMap(saleMap, saleMap['id'] as String),
      errorMessage: map['error_message'] as String? ?? 'Unknown sync error',
      failedAt: DateTime.parse(map['failed_at'] as String),
    );
  }
}
