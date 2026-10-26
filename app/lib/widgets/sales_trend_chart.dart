import 'package:flutter/material.dart';
import '../utils/currency_formatter.dart';
import '../utils/theme.dart';

/// Lightweight revenue-over-time chart drawn with [CustomPainter].
///
/// No external chart dependencies — uses only Flutter SDK primitives.
///
/// * [points] is a list of (label, revenue) pairs computed from the same
///   in-memory data the Reports tabs already use (no extra queries).
/// * Period granularity is chosen by the parent: hourly for Daily,
///   daily for Weekly/Monthly, and per-range for Custom.
/// * Blue line with dot markers, subtle gridlines, KSh-formatted axes.
/// * Tappable/hoverable bars/dots show a KSh tooltip with the bucket label.
/// * Friendly empty state when there are no sales.
class SalesTrendChart extends StatefulWidget {
  /// (x-axis label, revenue for that bucket)
  final List<MapEntry<String, double>> points;
  final double height;

  const SalesTrendChart({
    super.key,
    required this.points,
    this.height = 200,
  });

  @override
  State<SalesTrendChart> createState() => _SalesTrendChartState();
}

class _SalesTrendChartState extends State<SalesTrendChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return _EmptyChart(height: widget.height);
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(details.globalPosition);
        final width = box.size.width;
        final index = (local.dx / width * widget.points.length).floor();
        if (index >= 0 && index < widget.points.length) {
          setState(() => _hoveredIndex = index);
        }
      },
      onPanEnd: (_) => setState(() => _hoveredIndex = null),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {},
        onExit: (_) => setState(() => _hoveredIndex = null),
        child: CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _SalesTrendPainter(
            points: widget.points,
            hoveredIndex: _hoveredIndex,
          ),
        ),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final double height;

  const _EmptyChart({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bar_chart,
            size: 40,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            'Sales will appear here after the first sale',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesTrendPainter extends CustomPainter {
  final List<MapEntry<String, double>> points;
  final int? hoveredIndex;

  _SalesTrendPainter({required this.points, this.hoveredIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = AppTheme.primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..isAntiAlias = true;

    final paintGrid = Paint()
      ..color = AppTheme.borderColor.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final paintFill = Paint()
      ..color = AppTheme.primaryColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final paintBar = Paint()
      ..color = AppTheme.primaryColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final textStyleAxis = TextStyle(
      color: AppTheme.textSecondary,
      fontSize: 11,
    );

    final textStyleLabel = TextStyle(
      color: AppTheme.textPrimary,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );

    final maxCount = points.map((p) => p.value).fold<double>(0, (a, b) => a > b ? a : b);
    final maxVal = maxCount > 0 ? maxCount : 1.0;

    // Leave enough room on the left for y-axis labels (12px padding)
    final plotLeft = 52.0;
    final plotRight = 16.0;
    final plotTop = 20.0;
    final plotBottom = 32.0;

    final plotWidth = size.width - plotLeft - plotRight;
    final plotHeight = size.height - plotTop - plotBottom;

    // Draw horizontal gridlines (3 lines)
    for (int i = 0; i <= 3; i++) {
      final y = plotTop + (plotHeight / 3) * i;
      canvas.drawLine(Offset(plotLeft, y), Offset(size.width - plotRight, y), paintGrid);
    }

    // Draw y-axis labels — right-aligned with 8px padding so first/last not clipped
    for (int i = 0; i <= 3; i++) {
      final val = maxVal - (maxVal / 3) * i;
      final y = plotTop + (plotHeight / 3) * i;
      final tp = TextPainter(
        text: TextSpan(text: CurrencyFormatter.format(val), style: textStyleAxis),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
      );
      tp.layout();
      tp.paint(canvas, Offset(plotLeft - tp.width - 8, y - tp.height / 2));
    }

    if (points.length < 2) {
      // Single point — just draw a dot
      final x = plotLeft + plotWidth / 2;
      final y = plotTop + plotHeight - (points.first.value / maxVal) * plotHeight;
      canvas.drawCircle(Offset(x, y), 4, paintLine);
      return;
    }

    // Compute x positions for each point
    final pointsOnPath = points.asMap().entries.map((entry) {
      final i = entry.key;
      final value = entry.value.value;
      final x = plotLeft + (plotWidth / (points.length - 1)) * i;
      final y = plotTop + plotHeight - (value / maxVal) * plotHeight;
      return Offset(x, y);
    }).toList();

    final useBars = points.length <= 7;

    if (useBars) {
      // Bar chart
      final barWidth = plotWidth / points.length * 0.6;
      final barGap = plotWidth / points.length * 0.2;

      for (int i = 0; i < points.length; i++) {
        final barX = plotLeft + barGap / 2 + (plotWidth / points.length) * i;
        final barTop = pointsOnPath[i].dy;
        final barRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, barTop, barWidth, plotTop + plotHeight - barTop),
          const Radius.circular(2),
        );

        // Highlight bar on hover
        if (hoveredIndex == i) {
          paintBar.color = AppTheme.primaryColor;
        } else {
          paintBar.color = AppTheme.primaryColor.withValues(alpha: 0.6);
        }

        canvas.drawRRect(barRect, paintBar);
      }
    } else {
      // Line chart with area fill
      final path = Path();
      path.moveTo(pointsOnPath.first.dx, pointsOnPath.first.dy);
      for (final p in pointsOnPath.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }

      // Area fill (gradient-like)
      final fillPath = Path.from(path)
        ..lineTo(pointsOnPath.last.dx, plotTop + plotHeight)
        ..lineTo(pointsOnPath.first.dx, plotTop + plotHeight)
        ..close();
      canvas.drawPath(fillPath, paintFill);

      // Line
      canvas.drawPath(path, paintLine);
    }

    // Dots + x-axis labels + hover tooltip
    for (int i = 0; i < points.length; i++) {
      final p = pointsOnPath[i];
      final isHovered = hoveredIndex == i;

      // Draw dot marker for line mode, or top of bar for bar mode
      final dotRadius = isHovered ? 5.0 : 3.5;
      canvas.drawCircle(p, dotRadius, paintLine);

      // x-axis label — positioned below the plot area, centered on the point
      final label = points[i].key;
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyleLabel),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tp.layout();

      // Ensure x-label doesn't overlap with markers
      final labelY = plotTop + plotHeight + 4;
      tp.paint(canvas, Offset(p.dx - tp.width / 2, labelY));

      // Hover tooltip — shows bucket label and KSh amount
      if (isHovered) {
        final tooltipText = '${points[i].key}\n${CurrencyFormatter.format(points[i].value)}';
        final ttp = TextPainter(
          text: TextSpan(
            text: tooltipText,
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        ttp.layout();
        final tx = p.dx - ttp.width / 2;
        // Position tooltip above the point, clamped to chart bounds
        final ty = (p.dy - ttp.height - 16).clamp(
          plotTop + 4.0,
          plotTop + plotHeight - ttp.height - 4.0,
        );
        final bgRect = Rect.fromLTWH(
          tx - 6,
          ty - 4,
          ttp.width + 12,
          ttp.height + 8,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
          Paint()..color = AppTheme.cardBackground,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
          paintGrid,
        );
        ttp.paint(canvas, Offset(tx, ty));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SalesTrendPainter old) {
    return old.points != points || old.hoveredIndex != hoveredIndex;
  }
}
