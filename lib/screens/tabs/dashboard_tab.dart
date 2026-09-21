import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:image_picker/image_picker.dart';

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

class _DashboardGreetingCard extends StatefulWidget {
  final DashboardState appState;

  const _DashboardGreetingCard({required this.appState});

  @override
  State<_DashboardGreetingCard> createState() => _DashboardGreetingCardState();
}

class _DashboardGreetingCardState extends State<_DashboardGreetingCard> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  DashboardState get appState => widget.appState;

  @override
  Widget build(BuildContext context) {
    final fullName = appState.userFullName.trim();
    final attendance = appState.attendance;
    final checkedIn = attendance.needsCheckOut;
    final timeLabel = checkedIn
        ? _toAmPm(attendance.lastInDisplay)
        : _nowAmPm();
    final imageUrl = appState.userImageUrl;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greetingWord(),
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (fullName.isNotEmpty)
                      Text(
                        '$fullName!',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (appState.attendanceLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 3),
                      )
                    else if (appState.attendanceError != null)
                      Text(
                        appState.attendanceError!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      )
                    else ...[
                      Text(
                        checkedIn
                            ? 'You started your day at.'
                            : 'Ready to start your day?',
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                  if (!mounted) return;
                  await appState.refreshAttendance();
                },
                customBorder: const CircleBorder(),
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: AppColors.softGreen,
                  child: imageUrl == null
                      ? Text(
                          fullName.isEmpty ? '?' : fullName[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : ClipOval(
                          child: Image.network(
                            imageUrl,
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Text(
                              fullName.isEmpty
                                  ? '?'
                                  : fullName[0].toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
          if (attendance.hasEmployee && appState.attendanceError == null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: checkedIn
                  ? OutlinedButton(
                      onPressed: appState.attendancePunching
                          ? null
                          : () => _punch(context, 'OUT'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(
                          color: AppColors.primary,
                          width: 1.4,
                        ),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            appState.attendancePunching
                                ? 'Saving...'
                                : 'Check Out',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.sentiment_satisfied_alt_rounded,
                            size: 20,
                          ),
                        ],
                      ),
                    )
                  : FilledButton(
                      onPressed: appState.attendancePunching
                          ? null
                          : () => _punch(context, 'IN'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            appState.attendancePunching
                                ? 'Saving...'
                                : 'Check In',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.sentiment_satisfied_alt_rounded,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  String _greetingWord() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  String _nowAmPm() => _formatAmPm(DateTime.now());

  String _toAmPm(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return _nowAmPm();
    final parts = value.split(':');
    if (parts.length < 2) return value;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return value;
    return _formatAmPm(DateTime(2000, 1, 1, hour, minute));
  }

  String _formatAmPm(DateTime value) {
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $suffix';
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

    final state = context.read<DashboardState>();
    try {
      await state.ensureAttendanceLocation();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    if (!context.mounted) return;

    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 75,
      maxWidth: 1280,
    );
    if (!context.mounted) return;
    if (photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto kamera depan wajib sebelum Check In/Out.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    try {
      await state.punchAttendance(logType, photoPath: photo.path);
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
