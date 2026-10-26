import 'package:flutter/material.dart';
import '../utils/theme.dart';
import 'sync_status_indicator.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool showSyncIndicator;
  final bool centerTitle;
  final double height;

  const AppHeader({
    super.key,
    required this.title,
    this.actions,
    this.showSyncIndicator = false,
    this.centerTitle = false,
    this.height = kToolbarHeight,
  });

  @override
  Widget build(BuildContext context) {
    final trailing = <Widget>[];
    if (showSyncIndicator) {
      trailing.add(const Padding(
        padding: EdgeInsets.only(right: AppTheme.sp8),
        child: SyncStatusIndicator(compact: true),
      ));
    }
    if (actions != null) {
      trailing.addAll(actions!);
    }

    return AppBar(
      backgroundColor: AppTheme.appBackground,
      foregroundColor: AppTheme.textPrimary,
      elevation: 0,
      centerTitle: centerTitle,
      toolbarHeight: height,
      titleSpacing: 0,
      leading: Navigator.canPop(context)
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: trailing.isEmpty ? null : trailing,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(height);
}



