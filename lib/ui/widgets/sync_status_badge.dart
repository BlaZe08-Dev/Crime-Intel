import 'package:flutter/material.dart';

import '../../core/di/app_services.dart';
import '../../main.dart';
import '../../sync/models/sync_models.dart';
import '../theme/app_theme.dart';

/// Interactive sync status indicator displayed in the primary navigation rail.
///
/// Clicking the badge displays detailed synchronization diagnostics and a manual
/// "Sync Now" affordance.
class SyncStatusBadge extends StatefulWidget {
  final bool compact;

  const SyncStatusBadge({super.key, this.compact = true});

  @override
  State<SyncStatusBadge> createState() => _SyncStatusBadgeState();
}

class _SyncStatusBadgeState extends State<SyncStatusBadge> {
  bool _manualSyncing = false;

  @override
  Widget build(BuildContext context) {
    final services = ServicesScope.of(context);

    return ValueListenableBuilder<SyncStatus>(
      valueListenable: services.syncManager.statusNotifier,
      builder: (context, status, _) {
        final icon = _statusIcon(status);
        final color = _statusColor(status);

        if (widget.compact) {
          return Tooltip(
            message: '${status.label}\nClick for sync details & manual sync',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showSyncDetails(context, services, status),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 16, color: color),
                    if (status.pendingCount > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${status.pendingCount}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showSyncDetails(context, services, status),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _statusIcon(SyncStatus status) {
    if (status.isSyncing) return Icons.sync;
    if (!status.isConfigured) return Icons.cloud_off_outlined;
    if (!status.isOnline) return Icons.cloud_off;
    if (status.pendingCount > 0) return Icons.cloud_upload_outlined;
    return Icons.cloud_done_outlined;
  }

  Color _statusColor(SyncStatus status) {
    if (status.isSyncing) return AppColors.primary;
    if (!status.isConfigured) return AppColors.textMuted;
    if (!status.isOnline) return AppColors.accentAmber;
    if (status.pendingCount > 0) return AppColors.accentAmber;
    return AppColors.accentEmerald;
  }

  void _showSyncDetails(
    BuildContext context,
    AppServices services,
    SyncStatus status,
  ) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.border),
              ),
              title: const Row(
                children: [
                  Icon(Icons.cloud_sync, color: AppColors.primary, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Neon Cloud Synchronization',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRow(
                      'Connection Status',
                      status.isOnline ? 'Online (Connected)' : 'Offline (Local-only)',
                      status.isOnline ? AppColors.accentEmerald : AppColors.accentAmber,
                    ),
                    _buildRow(
                      'Central Store',
                      status.isConfigured ? 'Neon (PostgreSQL)' : 'Not Configured (set NEON_DATABASE_URL)',
                      status.isConfigured ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                    _buildRow(
                      'Pending Queue',
                      '${status.pendingCount} item(s) waiting for sync',
                      status.pendingCount > 0 ? AppColors.accentAmber : AppColors.accentEmerald,
                    ),
                    _buildRow(
                      'Local Device ID',
                      services.deviceId,
                      AppColors.textSecondary,
                    ),
                    _buildRow(
                      'Last Synchronized',
                      status.lastSyncTime != null
                          ? '${status.lastSyncTime!.toLocal()}'.split('.').first
                          : 'Never synced this session',
                      AppColors.textSecondary,
                    ),
                    if (status.lastError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.accentRose.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.accentRose.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.accentRose, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                status.lastError!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.accentRose,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: 8),
                    const Text(
                      'Audit & Attribution Architecture:\n'
                      '• Actions while offline remain tamper-evident on your local hash chain.\n'
                      '• Synced entries append into Neon in order of arrival, creating the authoritative central chain.\n'
                      '• Search/RAG results from other investigators never disclose their personal identity.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('Close'),
                ),
                ElevatedButton.icon(
                  icon: _manualSyncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.refresh, size: 16),
                  label: Text(_manualSyncing ? 'Syncing...' : 'Sync Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: (!status.isConfigured || _manualSyncing)
                      ? null
                      : () async {
                          setDialogState(() => _manualSyncing = true);
                          await services.syncManager.syncNow();
                          if (context.mounted) {
                            setDialogState(() => _manualSyncing = false);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: valueColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
