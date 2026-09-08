import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/sales_workspace.dart';
import '../../../state/spg/spg_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../../visits/attendance_tab.dart';

class SpgOverviewTab extends StatefulWidget {
  final ValueChanged<int> onMenuSelected;

  const SpgOverviewTab({super.key, required this.onMenuSelected});

  @override
  State<SpgOverviewTab> createState() => _SpgOverviewTabState();
}

class _SpgOverviewTabState extends State<SpgOverviewTab> {
  SalesVisit? _activeVisit;
  String? _profileImageUrl;
  String? _visitError;
  bool _visitLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadVisitSnapshot();
      _loadProfileImage();
    });
  }

  Future<void> _loadVisitSnapshot({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _visitLoading = true;
      _visitError = null;
    });
    try {
      final state = context.read<SpgState>();
      await state.fetchSpgVisits(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _activeVisit = state.activeSpgVisit;
        _visitError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _activeVisit = null;
        _visitError = 'Gagal memuat status absensi.';
      });
    } finally {
      if (mounted) setState(() => _visitLoading = false);
    }
  }

  Future<void> _loadProfileImage() async {
    final state = context.read<SpgState>();
    try {
      final profile = await state.fetchCurrentUserProfile();
      final image = profile['user_image']?.toString().trim() ?? '';
      if (!mounted || image.isEmpty) return;
      final imageUrl =
          image.startsWith('http://') || image.startsWith('https://')
          ? image
          : Uri.parse(state.frappeService.baseUrl).resolve(image).toString();
      setState(() => _profileImageUrl = imageUrl);
    } catch (_) {
      if (mounted) setState(() => _profileImageUrl = null);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadVisitSnapshot(forceRefresh: true),
      _loadProfileImage(),
    ]);
  }

  Future<void> _openCheckIn() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AttendanceCheckInScreen(spgMode: true),
      ),
    );
    if (!mounted) return;
    await _loadVisitSnapshot(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 104),
        children: [
          _SpgVisitActionCard(
            active: _activeVisit,
            profileImageUrl: _profileImageUrl,
            loading: _visitLoading,
            error: _visitError,
            onAction: _openCheckIn,
            onOpenHistory: () => widget.onMenuSelected(1),
          ),

          GridView.count(
            crossAxisCount: TmsxResponsive.columnsFor(
              context,
              phone: 3,
              tablet: 4,
              desktop: 5,
            ),
            mainAxisSpacing: 14,
            crossAxisSpacing: 12,
            childAspectRatio: 0.78,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _SpgShortcutTile(
                icon: Icons.location_on_rounded,
                label: 'Absensi',
                color: AppColors.primary,
                onTap: () => widget.onMenuSelected(1),
              ),
              _SpgShortcutTile(
                icon: Icons.photo_camera_rounded,
                label: 'Foto',
                color: const Color(0xFF2563EB),
                onTap: () => widget.onMenuSelected(2),
              ),
              _SpgShortcutTile(
                icon: Icons.bar_chart_rounded,
                label: 'Selling',
                color: const Color(0xFF0891B2),
                onTap: () => widget.onMenuSelected(3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpgVisitActionCard extends StatelessWidget {
  const _SpgVisitActionCard({
    required this.active,
    required this.profileImageUrl,
    required this.loading,
    required this.error,
    required this.onAction,
    required this.onOpenHistory,
  });

  final SalesVisit? active;
  final String? profileImageUrl;
  final bool loading;
  final String? error;
  final VoidCallback onAction;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final activeVisit = active;
    final now = DateTime.now();
    final greeting = now.hour < 11
        ? 'Good Morning,'
        : now.hour < 15
        ? 'Good Afternoon,'
        : 'Good Evening,';
    final title = activeVisit?.customerName.trim().isNotEmpty == true
        ? activeVisit!.customerName
        : activeVisit?.customer.trim().isNotEmpty == true
        ? activeVisit!.customer
        : 'SPG Team!';
    final statusText = activeVisit == null
        ? 'You are not Check-in yet Today.'
        : 'You are checked in today.';
    final timeText = activeVisit == null || activeVisit.checkInTime.isEmpty
        ? ''
        : activeVisit.checkInTime;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          error ?? statusText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: error == null
                                ? AppColors.slate
                                : Colors.red.shade600,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (timeText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            timeText,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onOpenHistory,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: AppColors.softGreen,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.white,
                              width: 2,
                            ),
                          ),
                          child: profileImageUrl == null
                              ? const Icon(
                                  Icons.person_rounded,
                                  color: AppColors.primary,
                                  size: 24,
                                )
                              : Image.network(
                                  profileImageUrl!,
                                  cacheWidth: 96,
                                  cacheHeight: 96,
                                  filterQuality: FilterQuality.medium,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.person_rounded,
                                    color: AppColors.primary,
                                    size: 24,
                                  ),
                                ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: AppColors.softGreen,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.white,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              activeVisit == null
                                  ? Icons.location_on_outlined
                                  : Icons.near_me_rounded,
                              color: AppColors.primary,
                              size: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (loading)
                const Positioned(
                  right: 0,
                  top: 0,
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: loading ? null : onAction,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.45),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              icon: Icon(
                activeVisit == null
                    ? Icons.login_rounded
                    : Icons.logout_rounded,
                size: 17,
              ),
              label: Text(
                activeVisit == null ? 'Check In' : 'Check Out',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpgShortcutTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SpgShortcutTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.32),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(icon, color: AppColors.white, size: 28),
              ),
              const SizedBox(height: 9),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 12,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
