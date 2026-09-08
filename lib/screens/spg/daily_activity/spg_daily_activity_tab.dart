import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/spg/spg_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/erp/erp_section_widgets.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import 'create_spg_daily_activity_screen.dart';

class SpgDailyActivityTab extends StatefulWidget {
  const SpgDailyActivityTab({super.key});

  @override
  State<SpgDailyActivityTab> createState() => _SpgDailyActivityTabState();
}

class _SpgDailyActivityTabState extends State<SpgDailyActivityTab> {
  List<Map<String, dynamic>> _records = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await context.read<SpgState>().fetchSpgDailyActivities();
      if (!mounted) return;
      setState(() => _records = records);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateSpgDailyActivityScreen()),
    );
    if (created == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 104),
            children: [
              const _SpgListHeader(
                title: 'SPG Daily Activity',
                subtitle: 'Riwayat foto aktivitas customer harian',
                icon: Icons.photo_camera_outlined,
                color: Color(0xFF2563EB),
              ),
              if (_loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                ErpErrorBox(message: _error!),
              ],
              const SizedBox(height: 12),
              if (_records.isEmpty && !_loading)
                const ErpEmptyState(title: 'Belum ada report foto SPG')
              else
                ..._records.map(_recordTile),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'create-spg-daily-activity',
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: AppColors.white,
            onPressed: _openCreate,
            icon: const Icon(Icons.add_a_photo_rounded),
            label: const Text('Report Foto'),
          ),
        ),
      ],
    );
  }

  Widget _recordTile(Map<String, dynamic> row) {
    final name = row['name']?.toString() ?? '';
    final customer = row['customer']?.toString() ?? '-';
    final employee = row['employee']?.toString() ?? '-';
    final date =
        row['activity_date']?.toString() ?? row['modified']?.toString() ?? '-';
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: name.isEmpty ? null : () => _showDetail(name),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.photo_library_outlined,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      employee,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetaPill(
                          icon: Icons.calendar_today_outlined,
                          label: date,
                          color: const Color(0xFF2563EB),
                        ),
                        _MetaPill(
                          icon: Icons.image_outlined,
                          label: 'Foto',
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppColors.slate),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetail(String name) async {
    try {
      final detail = await context.read<SpgState>().fetchSpgDailyActivityDetail(
        name,
      );
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _SpgDailyActivityDetailSheet(detail: detail),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaPill({
    required this.icon,
    required this.label,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label.trim().isEmpty ? '-' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpgListHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _SpgListHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
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

class _SpgDailyActivityDetailSheet extends StatelessWidget {
  final Map<String, dynamic> detail;

  const _SpgDailyActivityDetailSheet({required this.detail});

  @override
  Widget build(BuildContext context) {
    final state = context.read<SpgState>();
    final rows = _childRows(detail['activity_photos']);
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              CollectionSectionHeader(
                title: detail['customer']?.toString() ?? 'SPG Daily Activity',
                subtitle: detail['name']?.toString() ?? '',
                icon: Icons.photo_camera_outlined,
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _detailRow(
                        'Employee',
                        detail['employee']?.toString() ?? '',
                      ),
                      _detailRow(
                        'Activity Date',
                        detail['activity_date']?.toString() ?? '',
                      ),
                      _detailRow('Notes', detail['notes']?.toString() ?? ''),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const ErpEmptyState(title: 'Belum ada foto')
              else
                ...rows.map((row) => _photoCard(state, row)),
            ],
          ),
        );
      },
    );
  }

  static List<Map<String, dynamic>> _childRows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Widget _photoCard(SpgState state, Map<String, dynamic> row) {
    final photo = row['photo']?.toString() ?? '';
    final url = _absoluteFileUrl(state.selectedSiteBaseUrl, photo);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (url.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  height: 220,
                  cacheWidth: 900,
                  filterQuality: FilterQuality.medium,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ErpEmptyState(title: 'Foto tidak bisa dimuat'),
                ),
              ),
            const SizedBox(height: 8),
            _detailRow('Waktu', row['photo_time']?.toString() ?? ''),
            _detailRow('Deskripsi', row['description']?.toString() ?? ''),
          ],
        ),
      ),
    );
  }

  String _absoluteFileUrl(String baseUrl, String fileUrl) {
    final value = fileUrl.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return '${baseUrl.replaceAll(RegExp(r'/+$'), '')}$value';
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
