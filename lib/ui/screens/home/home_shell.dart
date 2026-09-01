import 'package:flutter/material.dart';

import '../../../core/constants/constants.dart';
import '../../theme/app_theme.dart';
import '../chat/chat_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../graph/graph_screen.dart';
import '../logs/logs_screen.dart';

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
    (icon: Icons.dashboard_outlined, selected: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.forum_outlined, selected: Icons.forum, label: 'Assistant'),
    (icon: Icons.hub_outlined, selected: Icons.hub, label: 'Network'),
    (icon: Icons.receipt_long_outlined, selected: Icons.receipt_long, label: 'Audit Log'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            backgroundColor: AppColors.surface,
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  Icon(Icons.shield_outlined,
                      color: AppColors.primary, size: 26),
                  SizedBox(height: 6),
                  Text(
                    AppConstants.appName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1, color: AppColors.border),
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
    );
  }
}
