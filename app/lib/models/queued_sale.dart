import 'failed_sale.dart';
import 'sale.dart';

class QueuedSale {
  final Sale sale;
  final bool includeCostSnapshot;
  final int retryCount;
  final DateTime queuedAt;
  final DateTime? lastAttemptAt;
  final String? lastError;

  QueuedSale({
    required this.sale,
    this.includeCostSnapshot = false,
    this.retryCount = 0,
    required this.queuedAt,
    this.lastAttemptAt,
    this.lastError,
  });

  QueuedSale copyWith({
    int? retryCount,
    DateTime? lastAttemptAt,
    String? lastError,
  }) {
    return QueuedSale(
      sale: sale,
      includeCostSnapshot: includeCostSnapshot,
      retryCount: retryCount ?? this.retryCount,
      queuedAt: queuedAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sale': sale.toMap(),
      'include_cost_snapshot': includeCostSnapshot,
      'cost_map': includeCostSnapshot ? sale.toCostMap() : null,
      'retry_count': retryCount,
      'queued_at': queuedAt.toIso8601String(),
      'last_attempt_at': lastAttemptAt?.toIso8601String(),
      'last_error': lastError,
    };
  }

  factory QueuedSale.fromMap(Map<String, dynamic> map) {
    final saleMap = Map<String, dynamic>.from(map['sale'] as Map);
    final costMap = map['cost_map'] != null
        ? Map<String, dynamic>.from(map['cost_map'] as Map)
        : null;
    return QueuedSale(
      sale: Sale.fromMap(saleMap, saleMap['id'] as String, costMap),
      includeCostSnapshot: map['include_cost_snapshot'] as bool? ?? false,
      retryCount: (map['retry_count'] as num? ?? 0).toInt(),
      queuedAt: map['queued_at'] != null
          ? DateTime.parse(map['queued_at'] as String)
          : DateTime.now(),
      lastAttemptAt: map['last_attempt_at'] != null
          ? DateTime.parse(map['last_attempt_at'] as String)
          : null,
      lastError: map['last_error'] as String?,
    );
  }

  FailedSaleRecord toFailedSaleRecord() {
    return FailedSaleRecord(
      sale: sale,
      errorMessage: lastError ?? 'Pending retry sync',
      failedAt: lastAttemptAt ?? queuedAt,
    );
  }
}
