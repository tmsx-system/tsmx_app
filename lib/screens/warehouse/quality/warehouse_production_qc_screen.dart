import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/quality_inspection_record.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../shared/warehouse_widgets.dart';

class WarehouseProductionQcScreen extends StatefulWidget {
  const WarehouseProductionQcScreen({super.key});

  @override
  State<WarehouseProductionQcScreen> createState() =>
      _WarehouseProductionQcScreenState();
}

class _WarehouseProductionQcScreenState
    extends State<WarehouseProductionQcScreen> {
  final _search = TextEditingController();
  List<QualityInspectionRecord> _rows = const [];
  String? _status;
  int _periodDays = 30;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _rows = await context
          .read<WarehouseStockState>()
          .fetchProductionQualityInspections(
            periodDays: _periodDays,
            forceRefresh: forceRefresh,
          );
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows();
    final accepted = _countStatus('accepted');
    final rejected = _countStatus('rejected');
    final pending = _rows.length - accepted - rejected;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'QC Hasil Produksi',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: warehousePagePaddingOf(context),
          children: [
            const WarehouseSectionHeader(
              title: 'QC Dalam Proses',
              subtitle: 'Pantau kualitas item selama proses produksi',
              icon: Icons.precision_manufacturing_outlined,
            ),
            warehouseSectionGap,
            Row(
              children: [
                Expanded(
                  child: _metric(
                    label: 'Diterima',
                    value: '$accepted',
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metric(
                    label: 'Menunggu',
                    value: '$pending',
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _metric(
                    label: 'Ditolak',
                    value: '$rejected',
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const WarehouseInfoPanel(
              icon: Icons.info_outline_rounded,
              message:
                  'Data berasal dari Quality Inspection dengan tipe In Process.',
            ),
            warehouseSectionGap,
            WarehouseSearchField(
              controller: _search,
              hintText: 'Cari item, inspeksi, atau referensi',
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Filter status',
                prefixIcon: Icon(Icons.fact_check_outlined),
              ),
              items: const [
                DropdownMenuItem(value: '', child: Text('Semua status')),
                DropdownMenuItem(value: 'Accepted', child: Text('Diterima')),
                DropdownMenuItem(value: 'Pending', child: Text('Menunggu')),
                DropdownMenuItem(value: 'Rejected', child: Text('Ditolak')),
              ],
              onChanged: (value) => setState(
                () => _status = value?.isEmpty == true ? null : value,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _periodDays,
              decoration: const InputDecoration(
                labelText: 'Periode monitoring',
                prefixIcon: Icon(Icons.date_range_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 30, child: Text('30 hari terakhir')),
                DropdownMenuItem(value: 90, child: Text('90 hari terakhir')),
              ],
              onChanged: (value) {
                if (value == null || value == _periodDays) return;
                setState(() => _periodDays = value);
                _load();
              },
            ),
            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              WarehouseInfoPanel(
                icon: Icons.error_outline_rounded,
                color: AppColors.danger,
                message: _error!,
              ),
            ],
            warehouseSectionGap,
            WarehouseSectionHeader(
              title: 'Daftar QC Produksi',
              subtitle: '${rows.length} inspeksi ditampilkan',
              icon: Icons.list_alt_rounded,
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty && !_loading)
              const ErpEmptyState(
                title: 'QC hasil produksi tidak ditemukan',
                message:
                    'Pastikan Quality Inspection menggunakan tipe In Process.',
              )
            else
              ...rows.map(_inspectionCard),
          ],
        ),
      ),
    );
  }

  int _countStatus(String status) =>
      _rows.where((row) => row.status.trim().toLowerCase() == status).length;

  List<QualityInspectionRecord> _filteredRows() {
    final query = _search.text.trim().toLowerCase();
    return _rows.where((row) {
      final matchesStatus = _status == null
          ? true
          : _status == 'Pending'
          ? row.status.toLowerCase() != 'accepted' &&
                row.status.toLowerCase() != 'rejected'
          : row.status.toLowerCase() == _status!.toLowerCase();
      return matchesStatus &&
          (query.isEmpty ||
              row.name.toLowerCase().contains(query) ||
              row.itemCode.toLowerCase().contains(query) ||
              row.itemName.toLowerCase().contains(query) ||
              row.referenceName.toLowerCase().contains(query));
    }).toList();
  }

  Widget _inspectionCard(QualityInspectionRecord row) {
    final color = _statusColor(row.status);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              foregroundColor: color,
              child: Icon(_statusIcon(row.status)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.itemName.isEmpty ? row.itemCode : row.itemName,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      row.name,
                      if (row.itemCode.isNotEmpty) row.itemCode,
                      if (row.inspectedBy.isNotEmpty) row.inspectedBy,
                    ].join(' | '),
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11,
                    ),
                  ),
                  if (row.referenceName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${row.referenceType}: ${row.referenceName}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  row.status.isEmpty ? 'Menunggu' : row.status,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (row.reportDate != null)
                  Text(
                    DateFormat('dd MMM').format(row.reportDate!),
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric({
    required String label,
    required String value,
    required Color color,
  }) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
      boxShadow: AppColors.cardShadow,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.slate, fontSize: 10),
        ),
      ],
    ),
  );

  Color _statusColor(String status) {
    final normalized = status.toLowerCase();
    if (normalized == 'accepted') return AppColors.success;
    if (normalized == 'rejected') return AppColors.danger;
    return AppColors.warning;
  }

  IconData _statusIcon(String status) {
    final normalized = status.toLowerCase();
    if (normalized == 'accepted') return Icons.check_rounded;
    if (normalized == 'rejected') return Icons.close_rounded;
    return Icons.hourglass_empty_rounded;
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
