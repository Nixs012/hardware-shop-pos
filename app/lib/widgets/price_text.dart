import 'package:flutter/material.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';

class PriceText extends StatelessWidget {
  final double amount;
  final TextStyle? style;
  final TextAlign textAlign;
  final int maxLines;

  const PriceText(
    this.amount, {
    super.key,
    this.style,
    this.textAlign = TextAlign.left,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = TextStyle(
      color: AppTheme.textPrimary,
      fontWeight: FontWeight.bold,
      fontSize: 14,
    );
    return Text(
      CurrencyFormatter.format(amount),
      style: style ?? defaultStyle,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}



