import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Compact animated segmented control for the Reports filter period.
///
/// Renders Daily / Weekly / Monthly / Custom as a single rounded container
/// with a blue selected state and muted unselected labels.
///
/// * 44px minimum touch targets.
/// * 150ms implicit animation on selection.
/// * [onCustomRange] is invoked when Custom is tapped, giving the parent
/// * the chance to show the date-range picker.
/// * Does NOT hard-code data -- [selectedIndex] and the four labels are
///   passed by the parent which owns the filter state.
class SegmentedPeriodControl extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final void Function(DateTimeRange) onCustomRange;
  final DateTimeRange? customRange;

  const SegmentedPeriodControl({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.onCustomRange,
    this.customRange,
  });

  static const labels = ['Daily', 'Weekly', 'Monthly', 'Custom'];

  @override
  Widget build(BuildContext context) {
    // Honor reduced-motion: no animation when disabled.
    final useAnimations =
        MediaQuery.of(context).disableAnimations == false;

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.elevatedBackground,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = selectedIndex == index;
          final isCustom = index == 3;

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () async {
                if (isCustom) {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2025, 1, 1),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    initialDateRange: customRange,
                    builder: (context, child) {
                      return Theme(
                        data: ThemeData.dark(useMaterial3: true),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    onCustomRange(picked);
                  }
                } else {
                  onSelect(index);
                }
              },
              child: AnimatedContainer(
                duration: useAnimations ? const Duration(milliseconds: 150) : Duration.zero,
                curve: Curves.easeOut,
                decoration: selected
                    ? BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      )
                    : null,
                alignment: Alignment.center,
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color: selected
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
