import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Export control with icon, accessible label, loading indicator, and
/// success/error toast feedback.
///
/// The actual CSV generation is left to the parent via [onExport] — this
/// widget only handles UI state (loading / success / error toasts).
///
/// Only formats that already work are offered (currently CSV).
class ExportButton extends StatefulWidget {
  final Future<void> Function() onExport;
  final String? tooltip;
  final String? semanticsLabel;

  const ExportButton({
    super.key,
    required this.onExport,
    this.tooltip = 'Export report',
    this.semanticsLabel = 'Export report',
  });

  @override
  State<ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<ExportButton> {
  bool _isExporting = false;

  Future<void> _handleExport() async {
    setState(() => _isExporting = true);
    try {
      await widget.onExport();
      if (mounted) {
        _showToast('Report exported successfully', AppTheme.successColor);
      }
    } catch (e) {
      if (mounted) {
        _showToast('Export failed: $e', AppTheme.errorColor);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showToast(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: AppTheme.textPrimary)),
        backgroundColor: color.withValues(alpha: 0.2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip ?? 'Export report',
      child: Semantics(
        label: widget.semanticsLabel,
        button: true,
        child: SizedBox(
          width: 44,
          height: 44,
          child: _isExporting
              ? Container(
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                )
              : IconButton(
                  icon: Icon(
                    Icons.file_download_outlined,
                    color: AppTheme.textPrimary,
                    size: 20,
                  ),
                  onPressed: _handleExport,
                  tooltip: widget.tooltip,
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.cardBackground,
                    foregroundColor: AppTheme.textPrimary,
                    minimumSize: const Size(44, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      side: BorderSide(color: AppTheme.borderColor, width: 1),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
