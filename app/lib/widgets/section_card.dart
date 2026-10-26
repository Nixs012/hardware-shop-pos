import 'package:flutter/material.dart';
import '../utils/theme.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? titleSpacing;

  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.padding,
    this.titleSpacing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.cardBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(color: AppTheme.borderColor, width: 1),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: titleSpacing ?? 16),
            child,
          ],
        ),
      ),
    );
  }
}



