import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/dashboard/dashboard_state.dart';
import '../../state/todo/todo_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/dashboard/dashboard_module_launcher.dart';
import '../../widgets/erp/erp_workflow_helper.dart';
import '../../widgets/responsive/responsive_layout.dart';
import '../profile/profile_screen.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  bool _didInitialLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialLoad) return;
    _didInitialLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dashboardState = context.read<DashboardState>();
      unawaited(dashboardState.refreshAttendance());
      if (dashboardState.canUseApprovals) {
        unawaited(context.read<TodoState>().fetchApprovalTodos());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<DashboardState>();

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        await appState.refreshAttendance();
        if (!context.mounted) return;
        if (appState.canUseApprovals) {
          await context.read<TodoState>().fetchApprovalTodos(
            forceRefresh: true,
          );
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: TmsxResponsive.pagePadding(context, top: 18, bottom: 110),
        child: TmsxResponsiveBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DashboardGreetingCard(appState: appState),
              const SizedBox(height: 18),
              const DashboardModuleLauncher(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardGreetingCard extends StatelessWidget {
  final DashboardState appState;

  const _DashboardGreetingCard({required this.appState});

  @override
  Widget build(BuildContext context) {
    final rawName = appState.mobileBoot?.fullName.trim();
    final fallback = appState.currentUser?.split('@').first.trim() ?? 'User';
    final name = rawName?.isNotEmpty == true ? rawName! : fallback;
    final site = appState.selectedSiteName.trim().isNotEmpty
        ? appState.selectedSiteName.trim()
        : 'Workspace';
    final attendance = appState.attendance;
    final reminder = _reminderText();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 22, 18, 20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello,',
                      style: TextStyle(
                        color: AppColors.slate.withValues(alpha: 0.95),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          site,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Transform.rotate(
                angle: 0.18,
                child: Container(
                  width: 88,
                  height: 88,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF9FE9E6),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: AppColors.white,
                    size: 42,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pengingat absensi',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                if (appState.attendanceLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(minHeight: 3),
                  )
                else
                  Text(
                    appState.attendanceError ?? reminder,
                    style: TextStyle(
                      color: appState.attendanceError == null
                          ? AppColors.slate
                          : AppColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                if (attendance.hasEmployee &&
                    appState.attendanceError == null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: appState.attendancePunching
                          ? null
                          : () => _punch(
                              context,
                              attendance.needsCheckOut ? 'OUT' : 'IN',
                            ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: Icon(
                        attendance.needsCheckOut
                            ? Icons.logout_rounded
                            : Icons.login_rounded,
                        size: 18,
                      ),
                      label: Text(
                        appState.attendancePunching
                            ? 'Menyimpan...'
                            : (attendance.needsCheckOut
                                  ? 'Check-out'
                                  : 'Check-in'),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _reminderText() {
    final attendance = appState.attendance;
    if (!attendance.hasEmployee) {
      return 'User login belum terhubung ke Employee. Hubungkan User ID di ERPNext untuk absensi.';
    }
    if (attendance.needsCheckOut) {
      final time = attendance.lastInDisplay;
      return time.isEmpty
          ? 'Anda sudah check-in. Jangan lupa check-out.'
          : 'Check-in pukul $time. Pengingat: lakukan check-out saat selesai.';
    }
    if (attendance.lastOutDisplay.isNotEmpty) {
      return 'Check-out pukul ${attendance.lastOutDisplay}. Check-in lagi jika shift berikutnya dimulai.';
    }
    return 'Belum check-in hari ini. Lakukan check-in untuk memulai absensi.';
  }

  Future<void> _punch(BuildContext context, String logType) async {
    if (logType == 'OUT') {
      final ok = await confirmErpAction(
        context,
        title: 'Check-out sekarang?',
        message: 'Absensi Employee Checkin OUT akan dicatat ke ERPNext.',
      );
      if (!ok || !context.mounted) return;
    }
    try {
      await context.read<DashboardState>().punchAttendance(logType);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            logType == 'OUT'
                ? 'Check-out berhasil dicatat.'
                : 'Check-in berhasil dicatat.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      final message = context.read<DashboardState>().attendanceError;
      if (message == null || message.isEmpty) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.danger),
      );
    }
  }
}
