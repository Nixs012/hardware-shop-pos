class CurrencyFormatter {
  static String format(double amount) {
    return 'KSh ${amount.toStringAsFixed(2)}';
  }
}
