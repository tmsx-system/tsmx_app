import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/spg/spg_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../utils/erp_error_message.dart';
import '../../../widgets/erp/erp_section_widgets.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import 'create_spg_daily_report_screen.dart';

class SpgDailyReportTab extends StatefulWidget {
  const SpgDailyReportTab({super.key});

  @override
  State<SpgDailyReportTab> createState() => _SpgDailyReportTabState();
}

class _SpgDailyReportTabState extends State<SpgDailyReportTab> {
  List<Map<String, dynamic>> _records = const [];
  bool _loading = true;
  bool _canWrite = false;
  bool _canSubmit = false;
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
      final state = context.read<SpgState>();
      final records = await state.fetchSpgDailyReports();
      final draftName = _firstDraftName(records);
      final permissions = await Future.wait<bool>([
        state.canWriteSpgDailyReport(docname: draftName),
        state.canSubmitSpgDailyReport(docname: draftName),
      ]);
      if (!mounted) return;
      setState(() {
        _records = records;
        _canWrite = permissions[0];
        _canSubmit = permissions[1];
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreateSpgDailyReportScreen()),
    );
    if (created == true && mounted) await _load();
  }

  Future<void> _openEdit(String name) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateSpgDailyReportScreen(existingName: name),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _submit(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Report Selling'),
        content: Text('Submit $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<SpgState>().submitSpgDailyReport(name);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    }
  }

  int _docStatus(Map<String, dynamic> row) =>
      int.tryParse(row['docstatus']?.toString() ?? '') ?? 0;

  String _firstDraftName(List<Map<String, dynamic>> records) {
    for (final row in records) {
      if (_docStatus(row) != 0) continue;
      final name = row['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
    }
    return '';
  }

  String _statusLabel(int docstatus) {
    if (docstatus == 1) return 'Submitted';
    if (docstatus == 2) return 'Cancelled';
    return 'Draft';
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
                title: 'SPG Daily Report',
                subtitle: 'Riwayat stock awal, stock akhir, dan sell out',
                icon: Icons.bar_chart_outlined,
                color: Color(0xFF0891B2),
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
                const ErpEmptyState(title: 'Belum ada report selling SPG')
              else
                ..._records.map(_recordTile),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'create-spg-daily-report',
            backgroundColor: const Color(0xFF0891B2),
            foregroundColor: AppColors.white,
            onPressed: _openCreate,
            icon: const Icon(Icons.add_chart_rounded),
            label: const Text('Report Selling'),
          ),
        ),
      ],
    );
  }

  Widget _recordTile(Map<String, dynamic> row) {
    final name = row['name']?.toString() ?? '';
    final customer = row['customer_name']?.toString().trim().isNotEmpty == true
        ? row['customer_name'].toString()
        : row['customer']?.toString() ?? '-';
    final employee = row['employee']?.toString() ?? '-';
    final date =
        row['report_date']?.toString() ?? row['modified']?.toString() ?? '-';
    final docstatus = _docStatus(row);
    final isDraft = docstatus == 0;
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
                color: const Color(0xFF0891B2).withValues(alpha: 0.08),
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
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.bar_chart_outlined,
                  color: Color(0xFF0891B2),
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
                          color: const Color(0xFF0891B2),
                        ),
                        _MetaPill(
                          icon: Icons.inventory_2_outlined,
                          label: 'Selling',
                          color: AppColors.primary,
                        ),
                        _MetaPill(
                          icon: Icons.flag_outlined,
                          label: _statusLabel(docstatus),
                          color: isDraft
                              ? const Color(0xFF0891B2)
                              : AppColors.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Aksi',
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.slate),
                onSelected: (value) {
                  if (value == 'detail') _showDetail(name);
                  if (value == 'edit') _openEdit(name);
                  if (value == 'submit') _submit(name);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'detail',
                    child: _ReportMenuLabel(
                      icon: Icons.visibility_outlined,
                      label: 'Lihat Detail',
                    ),
                  ),
                  if (isDraft && _canWrite)
                    const PopupMenuItem(
                      value: 'edit',
                      child: _ReportMenuLabel(
                        icon: Icons.edit_outlined,
                        label: 'Edit',
                      ),
                    ),
                  if (isDraft && _canSubmit)
                    const PopupMenuItem(
                      value: 'submit',
                      child: _ReportMenuLabel(
                        icon: Icons.verified_outlined,
                        label: 'Submit',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetail(String name) async {
    try {
      final state = context.read<SpgState>();
      final detail = await state.fetchSpgDailyReportDetail(name);
      if (!mounted) return;
      final isDraft = _docStatus(detail) == 0;
      final canEdit = isDraft &&
          (_canWrite || await state.canWriteSpgDailyReport(docname: name));
      final canSubmit = isDraft &&
          (_canSubmit || await state.canSubmitSpgDailyReport(docname: name));
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => _SpgDailyReportDetailSheet(
          detail: detail,
          canEdit: canEdit,
          canSubmit: canSubmit,
          onEdit: () {
            Navigator.pop(sheetContext);
            _openEdit(name);
          },
          onSubmit: () async {
            Navigator.pop(sheetContext);
            await _submit(name);
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    }
  }
}

class _ReportMenuLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ReportMenuLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
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

class _SpgDailyReportDetailSheet extends StatelessWidget {
  final Map<String, dynamic> detail;
  final bool canEdit;
  final bool canSubmit;
  final VoidCallback onEdit;
  final VoidCallback onSubmit;

  const _SpgDailyReportDetailSheet({
    required this.detail,
    required this.canEdit,
    required this.canSubmit,
    required this.onEdit,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final rows = _childRows(detail['selling_items']);
    return DraggableScrollableSheet(
      initialChildSize: 0.68,
      minChildSize: 0.4,
      maxChildSize: 0.9,
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
                title:
                    detail['customer_name']?.toString().trim().isNotEmpty ==
                        true
                    ? detail['customer_name'].toString()
                    : detail['customer']?.toString() ?? 'SPG Daily Report',
                subtitle: detail['name']?.toString() ?? '',
                icon: Icons.bar_chart_outlined,
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
                        'Report Date',
                        detail['report_date']?.toString() ?? '',
                      ),
                      _detailRow('Notes', detail['notes']?.toString() ?? ''),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (canEdit || canSubmit) ...[
                Row(
                  children: [
                    if (canEdit)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                      ),
                    if (canEdit && canSubmit) const SizedBox(width: 10),
                    if (canSubmit)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onSubmit,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('Submit'),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (rows.isEmpty)
                const ErpEmptyState(title: 'Belum ada item selling')
              else
                ...rows.map(_itemCard),
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

  Widget _itemCard(Map<String, dynamic> row) {
    final item = row['item']?.toString() ?? '';
    final uom = row['uom']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.softGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.primary,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.trim().isEmpty ? 'Item' : item,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (uom.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          uom,
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _quantityTile(
                    label: 'Stock Awal',
                    value:
                        row['opening_stock']?.toString() ??
                        row['stock_awal']?.toString() ??
                        '',
                    icon: Icons.login_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _quantityTile(
                    label: 'Stock Akhir',
                    value:
                        row['closing_stock']?.toString() ??
                        row['stock_akhir']?.toString() ??
                        '',
                    icon: Icons.logout_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _quantityTile(
              label: 'Sell Out',
              value: row['sell_out']?.toString() ?? '',
              icon: Icons.point_of_sale_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quantityTile({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.trim().isEmpty ? '-' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
