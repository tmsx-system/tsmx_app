import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/employee_attendance.dart';
import '../../state/dashboard/dashboard_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/erp/erp_empty_state.dart';
import '../../widgets/responsive/responsive_layout.dart';

class EmployeeAttendanceTab extends StatefulWidget {
  const EmployeeAttendanceTab({super.key});

  @override
  State<EmployeeAttendanceTab> createState() => _EmployeeAttendanceTabState();
}

class _EmployeeAttendanceTabState extends State<EmployeeAttendanceTab> {
  bool _didInitialLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialLoad) return;
    _didInitialLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<DashboardState>().refreshAttendance());
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<DashboardState>();
    final attendance = state.attendance;
    final employeeLabel = attendance.employeeName.isNotEmpty
        ? attendance.employeeName
        : attendance.employee;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => state.refreshAttendance(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 110),
        children: [
          Text(
            employeeLabel.isEmpty ? 'Riwayat Absensi' : employeeLabel,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Riwayat Employee Checkin hari ini',
            style: TextStyle(
              color: AppColors.slate,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (state.attendanceLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (state.attendanceError != null)
            Text(
              state.attendanceError!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (state.checkinLogs.isEmpty)
            const ErpEmptyState(
              title: 'Belum ada absensi hari ini',
              message: 'Check In dari Beranda untuk mencatat Employee Checkin.',
              icon: Icons.fingerprint_rounded,
            )
          else
            ...state.checkinLogs.map(_logTile),
        ],
      ),
    );
  }

  Widget _logTile(EmployeeCheckinLog log) {
    final isIn = log.logType == 'IN';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.softGreen,
            foregroundColor: AppColors.primary,
            child: Icon(
              isIn ? Icons.login_rounded : Icons.logout_rounded,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIn ? 'Check In' : 'Check Out',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  log.timeDisplay,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            log.id,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
