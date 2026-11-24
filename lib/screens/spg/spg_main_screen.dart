import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth/auth_state.dart';
import '../../theme/app_colors.dart';
import '../selling/tukar_guling/tukar_guling_tab.dart';
import '../shared/role_main_screen.dart';
import 'daily_activity/spg_daily_activity_tab.dart';
import 'daily_report/spg_daily_report_tab.dart';
import 'overview/spg_overview_tab.dart';

class SpgMainScreen extends StatefulWidget {
  const SpgMainScreen({super.key});

  @override
  State<SpgMainScreen> createState() => _SpgMainScreenState();
}

class _SpgMainScreenState extends State<SpgMainScreen> {
  Future<bool>? _tukarGulingFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tukarGulingFuture ??= _canOpenTukarGuling();
  }

  Future<bool> _canOpenTukarGuling() async {
    final auth = context.read<AuthState>();
    final results = await Future.wait([
      auth.canReadDoctype('Tukar Guling'),
      auth.canCreateDoctype('Tukar Guling'),
    ]);
    return results.any((allowed) => allowed);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _tukarGulingFuture,
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        final showTukarGuling = snapshot.data == true;
        return RoleMainScreen(
          title: 'SPG & SPM',
          fallbackUsername: 'SPG & SPM',
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Beranda',
            ),
            const NavigationDestination(
              icon: Icon(Icons.photo_camera_outlined),
              selectedIcon: Icon(Icons.photo_camera_rounded),
              label: 'Activity',
            ),
            const NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart_rounded),
              label: 'Report',
            ),
            if (showTukarGuling)
              const NavigationDestination(
                icon: Icon(Icons.swap_horiz_outlined),
                selectedIcon: Icon(Icons.swap_horiz_rounded),
                label: 'Tukar Guling',
              ),
          ],
          screensBuilder: (onMenuSelected) => [
            SpgOverviewTab(onMenuSelected: onMenuSelected),
            const SpgDailyActivityTab(),
            const SpgDailyReportTab(),
            if (showTukarGuling) const TukarGulingTab(),
          ],
        );
      },
    );
  }
}
