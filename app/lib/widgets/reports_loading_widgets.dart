import 'package:flutter/material.dart';

/// Static grey placeholder blocks shown while report data is loading.
///
/// Deliberately animation-free so widget tests using `pumpAndSettle` cannot
/// hang, while still making it obvious that content is loading.
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton for the Sales Summary tab: a grid of metric cards.
class ReportsSummarySkeleton extends StatelessWidget {
  const ReportsSummarySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: double.infinity, height: 44),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: SkeletonBox(width: double.infinity, height: 88)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(width: double.infinity, height: 88)),
            ],
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(child: SkeletonBox(width: double.infinity, height: 88)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(width: double.infinity, height: 88)),
            ],
          ),
          const SizedBox(height: 20),
          const SkeletonBox(width: double.infinity, height: 220),
          const SizedBox(height: 16),
          const SkeletonBox(width: double.infinity, height: 140),
          const SizedBox(height: 16),
          const SkeletonBox(width: double.infinity, height: 140),
        ],
      ),
    );
  }
}

/// Skeleton for the P&L / Top Sellers / Stock Balance tabs: rows of blocks.
class ReportsListSkeleton extends StatelessWidget {
  final int rows;

  const ReportsListSkeleton({super.key, this.rows = 6});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: double.infinity, height: 44),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: SkeletonBox(width: double.infinity, height: 72)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(width: double.infinity, height: 72)),
            ],
          ),
          const SizedBox(height: 20),
          const SkeletonBox(width: 180, height: 22),
          const SizedBox(height: 12),
          for (int i = 0; i < rows; i++) ...[
            const SkeletonBox(width: double.infinity, height: 56),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Inline red banner naming the data source that failed, with a Retry
/// button. Rendered ABOVE content so the data that did load stays visible.
class SourceErrorBanner extends StatelessWidget {
  final String title;
  final String? message;
  final VoidCallback onRetry;

  const SourceErrorBanner({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MaterialBanner(
        backgroundColor: Colors.red.withValues(alpha: 0.15),
        leading: const Icon(Icons.warning, color: Colors.red),
        content: Text(
          message == null ? title : '$title\n$message',
          style: const TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: onRetry,
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }
}