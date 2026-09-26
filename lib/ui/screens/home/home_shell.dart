import 'package:flutter/material.dart';

import '../../../core/constants/constants.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../graph/graph_screen.dart';
import '../logs/logs_screen.dart';
import '../../widgets/sync_status_badge.dart';

/// Top-level navigation between the four workspaces
/// (`docs/AppFlow.md` §2, §3, §8, §9).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.dashboard_outlined, label: 'Dashboard'),
    (icon: Icons.forum_outlined, label: 'Assistant'),
    (icon: Icons.hub_outlined, label: 'Network'),
    (icon: Icons.receipt_long_outlined, label: 'Audit Log'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WorkspaceColors.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            index: _index,
            destinations: _destinations,
            onSelect: (i) => setState(() => _index = i),
          ),
          Expanded(
            child: Column(
              children: [
                const _TopHeader(),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: const [
                      DashboardScreen(),
                      ChatScreen(),
                      GraphScreen(),
                      LogsScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final int index;
  final List<({IconData icon, String label})> destinations;
  final ValueChanged<int> onSelect;

  const _Sidebar({
    required this.index,
    required this.destinations,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      decoration: const BoxDecoration(
        color: WorkspaceColors.inputBackground,
        border: Border(right: BorderSide(color: WorkspaceColors.border)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Icon(Icons.shield_outlined,
                    color: WorkspaceColors.primary, size: 22),
                SizedBox(height: 4),
                Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: WorkspaceColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _NavTile(
                      icon: destinations[i].icon,
                      label: destinations[i].label,
                      selected: i == index,
                      onTap: () => onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SyncStatusBadge(compact: true),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: _Avatar(),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? WorkspaceColors.primary : WorkspaceColors.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: selected
                ? WorkspaceColors.primary.withValues(alpha: 0.15)
                : null,
            border: selected
                ? Border.all(
                    color: WorkspaceColors.primary.withValues(alpha: 0.4))
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();
  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: WorkspaceColors.primaryLight,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.person,
            size: 16, color: WorkspaceColors.background),
      );
}

class _TopHeader extends StatelessWidget {
  const _TopHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: WorkspaceColors.inputBackground,
        border: Border(bottom: BorderSide(color: WorkspaceColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text('OPERATIONAL FORENSIC TERMINAL',
                    style: AppTheme.mono.copyWith(
                        fontSize: 11,
                        letterSpacing: 0.55,
                        color: WorkspaceColors.textSecondary)),
                Text('// SECURE-NODE-04',
                    style: AppTheme.mono.copyWith(
                        fontSize: 11, color: WorkspaceColors.primary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: WorkspaceColors.surfaceCard,
              border: Border.all(color: WorkspaceColors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      color: WorkspaceColors.accentAmber,
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text('ACTIVE AUDIT',
                    style: AppTheme.mono.copyWith(
                        fontSize: 11, color: WorkspaceColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const _Avatar(),
        ],
      ),
    );
  }
}
