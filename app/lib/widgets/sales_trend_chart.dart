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
/// * Tappable/hoverable dots show a KSh tooltip.
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

    final textStyleAxis = TextStyle(
      color: AppTheme.textSecondary,
      fontSize: 10,
    );

    final textStyleLabel = TextStyle(
      color: AppTheme.textPrimary,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );

    final maxCount = points.map((p) => p.value).fold<double>(0, (a, b) => a > b ? a : b);
    final maxVal = maxCount > 0 ? maxCount : 1.0;

    final plotLeft = 40.0;
    final plotRight = 16.0;
    final plotTop = 16.0;
    final plotBottom = 28.0;

    final plotWidth = size.width - plotLeft - plotRight;
    final plotHeight = size.height - plotTop - plotBottom;

    // Draw horizontal gridlines (3 lines)
    for (int i = 0; i <= 3; i++) {
      final y = plotTop + (plotHeight / 3) * i;
      canvas.drawLine(Offset(plotLeft, y), Offset(size.width - plotRight, y), paintGrid);
    }

    // Draw y-axis labels
    for (int i = 0; i <= 3; i++) {
      final val = maxVal - (maxVal / 3) * i;
      final y = plotTop + (plotHeight / 3) * i;
      final tp = TextPainter(
        text: TextSpan(text: CurrencyFormatter.format(val), style: textStyleAxis),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(4, y - tp.height / 2));
    }

    if (points.length < 2) {
      // Single point — just draw a dot
      final x = plotLeft;
      final y = plotTop + plotHeight - (points.first.value / maxVal) * plotHeight;
      canvas.drawCircle(Offset(x, y), 4, paintLine);
      return;
    }

    // Compute path
    final path = Path();
    final pointsOnPath = points.asMap().entries.map((entry) {
      final i = entry.key;
      final value = entry.value.value;
      final x = plotLeft + (plotWidth / (points.length - 1)) * i;
      final y = plotTop + plotHeight - (value / maxVal) * plotHeight;
      return Offset(x, y);
    }).toList();

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

    // Dots + x-axis labels + hover tooltip
    for (int i = 0; i < points.length; i++) {
      final p = pointsOnPath[i];
      final isHovered = hoveredIndex == i;
      final dotRadius = isHovered ? 5.0 : 3.5;

      canvas.drawCircle(p, dotRadius, paintLine);

      // x-axis label
      final label = points[i].key;
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyleLabel),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      tp.layout();
      tp.paint(canvas, Offset(p.dx - tp.width / 2, size.height - plotBottom + 4));

      // Hover tooltip
      if (isHovered) {
        final tooltipText = CurrencyFormatter.format(points[i].value);
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
        );
        ttp.layout();
        final tx = p.dx - ttp.width / 2;
        final ty = p.dy - 24;
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
