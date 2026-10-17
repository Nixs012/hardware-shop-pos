class CustomerPayment {
  final String id;
  final String customerName;
  final String customerPhone;
  final double amount;
  final String paymentMethod;
  final DateTime timestamp;
  final String staffId;
  final String? saleId;
  final String? note;

  CustomerPayment({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.amount,
    required this.paymentMethod,
    required this.timestamp,
    required this.staffId,
    this.saleId,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'amount': amount,
      'payment_method': paymentMethod,
      'timestamp': timestamp.toIso8601String(),
      'staff_id': staffId,
      'sale_id': saleId,
      'note': note,
    };
  }

  factory CustomerPayment.fromMap(Map<String, dynamic> map, String id) {
    return CustomerPayment(
      id: id,
      customerName: map['customer_name'] ?? '',
      customerPhone: map['customer_phone'] ?? '',
      amount: (map['amount'] ?? 0.0).toDouble(),
      paymentMethod: map['payment_method'] ?? 'Cash',
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : DateTime.now(),
      staffId: map['staff_id'] ?? '',
      saleId: map['sale_id'],
      note: map['note'],
    );
  }
}
