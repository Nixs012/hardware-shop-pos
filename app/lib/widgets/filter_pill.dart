import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Compact dropdown "pill" filter used on the Reports filter bar.
///
/// Renders a rounded container with:
///   * a short leading label (e.g. "Staff")
///   * the currently selected value text
///   * a chevron icon
///
/// When tapped, shows a [PopupMenuButton] listing [items]. The selected item
/// is highlighted in the menu. Long names wrap/ellipsis so it never overflows.
///
/// All values come from real data passed by the parent — nothing is hard-coded.
class FilterPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final List<String> items;
  final ValueChanged<String> onSelect;
  final double width;

  const FilterPill({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.items,
    required this.onSelect,
    this.width = 160,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value.isEmpty ? label : value;

    return Container(
      height: 40,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(
          maxHeight: 240,
          minWidth: width,
        ),
        position: PopupMenuPosition.under,
        tooltip: '$label — $displayValue',
        menuPadding: EdgeInsets.zero,
        itemBuilder: (context) {
          return items.map((item) {
            final isSelected = item == value || (value.isEmpty && item == 'All');
            return PopupMenuItem<String>(
              value: item,
              height: 40,
              textStyle: isSelected
                  ? TextStyle(
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600,
                    )
                  : null,
              child: Row(
                children: [
                  if (isSelected)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList();
        },
        onSelected: onSelect,
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textSecondary, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$label: $displayValue',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              color: AppTheme.textSecondary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
