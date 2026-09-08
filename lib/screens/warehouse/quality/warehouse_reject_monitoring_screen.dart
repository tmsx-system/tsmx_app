import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/quality_inspection_record.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../shared/warehouse_widgets.dart';

class WarehouseRejectMonitoringScreen extends StatefulWidget {
  const WarehouseRejectMonitoringScreen({super.key});

  @override
  State<WarehouseRejectMonitoringScreen> createState() =>
      _WarehouseRejectMonitoringScreenState();
}

class _WarehouseRejectMonitoringScreenState
    extends State<WarehouseRejectMonitoringScreen> {
  final _search = TextEditingController();
  List<QualityInspectionRecord> _rows = const [];
  String? _inspectionType;
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
          .fetchRejectedQualityInspections(
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
    final types =
        _rows
            .map((row) => row.inspectionType)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final affectedItems = _rows
        .map((row) => row.itemCode)
        .where((value) => value.isNotEmpty)
        .toSet()
        .length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Reject Monitoring',
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
              title: 'Quality Reject',
              subtitle: 'Hasil inspeksi yang membutuhkan tindak lanjut',
              icon: Icons.report_problem_outlined,
            ),
            warehouseSectionGap,
            Row(
              children: [
                Expanded(child: _metric('Total reject', '${_rows.length}')),
                const SizedBox(width: 10),
                Expanded(child: _metric('Item terdampak', '$affectedItems')),
              ],
            ),
            const SizedBox(height: 10),
            const WarehouseInfoPanel(
              icon: Icons.info_outline_rounded,
              color: AppColors.warning,
              message:
                  'Daftar ini berisi hasil inspeksi yang ditolak dan perlu ditindaklanjuti.',
            ),
            warehouseSectionGap,
            WarehouseSearchField(
              controller: _search,
              hintText: 'Cari item, inspeksi, atau referensi',
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _inspectionType,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tipe inspeksi',
                prefixIcon: Icon(Icons.fact_check_outlined),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('Semua tipe')),
                ...types.map(
                  (type) => DropdownMenuItem(value: type, child: Text(type)),
                ),
              ],
              onChanged: (value) => setState(
                () => _inspectionType = value?.isEmpty == true ? null : value,
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
              title: 'Daftar Reject',
              subtitle: '${rows.length} hasil inspeksi ditampilkan',
              icon: Icons.list_alt_rounded,
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty && !_loading)
              const ErpEmptyState(
                title: 'Tidak ada reject ditemukan',
                message:
                    'Ubah periode/filter atau tarik ke bawah untuk refresh.',
              )
            else
              ...rows.map(_rejectCard),
          ],
        ),
      ),
    );
  }

  List<QualityInspectionRecord> _filteredRows() {
    final query = _search.text.trim().toLowerCase();
    return _rows.where((row) {
      return (_inspectionType == null ||
              row.inspectionType == _inspectionType) &&
          (query.isEmpty ||
              row.name.toLowerCase().contains(query) ||
              row.itemCode.toLowerCase().contains(query) ||
              row.itemName.toLowerCase().contains(query) ||
              row.referenceName.toLowerCase().contains(query));
    }).toList();
  }

  Widget _rejectCard(QualityInspectionRecord row) => Padding(
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
          const CircleAvatar(
            backgroundColor: Color(0xFFFFEBEE),
            foregroundColor: AppColors.danger,
            child: Icon(Icons.close_rounded),
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
                    if (row.inspectionType.isNotEmpty) row.inspectionType,
                  ].join(' | '),
                  style: const TextStyle(color: AppColors.slate, fontSize: 11),
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
                if (row.remarks.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    row.remarks,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (row.reportDate != null)
            Text(
              DateFormat('dd MMM').format(row.reportDate!),
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    ),
  );

  Widget _metric(String label, String value) => Container(
    padding: const EdgeInsets.all(14),
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
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.slate, fontSize: 11),
        ),
      ],
    ),
  );

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
