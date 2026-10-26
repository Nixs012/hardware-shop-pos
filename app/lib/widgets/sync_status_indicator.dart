import 'dart:async';
import 'package:flutter/material.dart';

import '../services/sync_service.dart';

class SyncStatusIndicator extends StatelessWidget {
  final bool compact;

  const SyncStatusIndicator({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: SyncService.instance.statusStream,
      initialData: SyncService.instance.currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncService.instance.currentStatus;

        Color color;
        IconData icon;
        String label;

        if (status.isSyncing) {
          color = Colors.blue;
          icon = Icons.sync;
          label = status.pendingCount > 0
              ? 'Syncing (${status.pendingCount})'
              : 'Syncing...';
        } else if (status.pendingCount > 0) {
          color = Colors.amber;
          icon = Icons.cloud_upload_outlined;
          label = '${status.pendingCount} pending';
        } else if (status.isOnline) {
          color = Colors.green;
          icon = Icons.cloud_done_outlined;
          label = 'Online';
        } else {
          color = Colors.redAccent;
          icon = Icons.cloud_off_outlined;
          label = 'Offline';
        }

        return Tooltip(
          message: status.isOnline
              ? (status.pendingCount > 0
                  ? '${status.pendingCount} sales queued for sync. Tap to sync now.'
                  : 'System online. Real-time sync active.')
              : 'System offline (airplane mode or no connection). Local sales will queue and sync automatically when online.',
          child: InkWell(
            onTap: () {
              if (status.isOnline && status.pendingCount > 0) {
                unawaited(SyncService.instance.drainQueue());
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Triggering sync for queued sales...'),
                    duration: Duration(seconds: 2),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      status.isOnline
                          ? (status.pendingCount > 0
                              ? '${status.pendingCount} sales waiting to sync.'
                              : 'All sales are synced.')
                          : 'Offline mode: billing, inventory, and receipt printing function locally.',
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status.isSyncing)
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    )
                  else
                    Icon(
                      compact ? Icons.circle : icon,
                      color: color,
                      size: compact ? 8 : 14,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}



