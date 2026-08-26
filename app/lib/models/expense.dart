class Expense {
  final String id;
  final DateTime date;
  final String category;
  final double amount;
  final String? note;

  Expense({
    required this.id,
    required this.date,
    required this.category,
    required this.amount,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'category': category,
      'amount': amount,
      'note': note,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map, String id) {
    return Expense(
      id: id,
      date: map['date'] != null ? DateTime.parse(map['date']) : DateTime.now(),
      category: map['category'] ?? '',
      amount: (map['amount'] ?? 0.0).toDouble(),
      note: map['note'],
    );
  }
}
