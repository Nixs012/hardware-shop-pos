import 'customer_payment.dart';

class QueuedPayment {
  final CustomerPayment payment;
  final int retryCount;
  final DateTime queuedAt;
  final DateTime? lastAttemptAt;
  final String? lastError;

  QueuedPayment({
    required this.payment,
    this.retryCount = 0,
    required this.queuedAt,
    this.lastAttemptAt,
    this.lastError,
  });

  QueuedPayment copyWith({
    int? retryCount,
    DateTime? lastAttemptAt,
    String? lastError,
  }) {
    return QueuedPayment(
      payment: payment,
      retryCount: retryCount ?? this.retryCount,
      queuedAt: queuedAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'payment': payment.toMap(),
      'retry_count': retryCount,
      'queued_at': queuedAt.toIso8601String(),
      'last_attempt_at': lastAttemptAt?.toIso8601String(),
      'last_error': lastError,
    };
  }

  factory QueuedPayment.fromMap(Map<String, dynamic> map) {
    final paymentMap = Map<String, dynamic>.from(map['payment'] as Map);
    return QueuedPayment(
      payment: CustomerPayment.fromMap(paymentMap, paymentMap['id'] as String),
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
}



