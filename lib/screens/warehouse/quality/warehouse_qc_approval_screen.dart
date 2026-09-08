import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/quality_inspection_record.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../shared/warehouse_widgets.dart';

class WarehouseQcApprovalScreen extends StatefulWidget {
  const WarehouseQcApprovalScreen({super.key});

  @override
  State<WarehouseQcApprovalScreen> createState() =>
      _WarehouseQcApprovalScreenState();
}

class _WarehouseQcApprovalScreenState extends State<WarehouseQcApprovalScreen> {
  final _search = TextEditingController();
  List<QualityInspectionRecord> _rows = const [];
  String? _submittingName;
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _rows = await context
          .read<WarehouseStockState>()
          .fetchQualityInspectionsForApproval(periodDays: _periodDays);
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(QualityInspectionRecord inspection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Quality Inspection?'),
        content: Text(
          '${inspection.name}\n\n'
          'Hasil QC: ${inspection.status.isEmpty ? 'Belum ditentukan' : inspection.status}\n\n'
          'Setelah submit, dokumen tidak dapat diedit tanpa proses cancel/amend.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: inspection.status.isEmpty
                ? null
                : () => Navigator.pop(context, true),
            icon: const Icon(Icons.approval_outlined),
            label: const Text('Setujui & Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _submittingName = inspection.name;
      _error = null;
    });
    try {
      await context.read<WarehouseStockState>().submitDocument(
        'Quality Inspection',
        inspection.name,
      );
      if (!mounted) return;
      setState(() => _rows.removeWhere((row) => row.name == inspection.name));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${inspection.name} berhasil disubmit.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _submittingName = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows();
    final accepted = _rows
        .where((row) => row.status.toLowerCase() == 'accepted')
        .length;
    final rejected = _rows
        .where((row) => row.status.toLowerCase() == 'rejected')
        .length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Approval QC',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: warehousePagePaddingOf(context),
          children: [
            const WarehouseSectionHeader(
              title: 'QC Menunggu Approval',
              subtitle: 'Review hasil QC sebelum submit dokumen',
              icon: Icons.approval_outlined,
            ),
            warehouseSectionGap,
            Row(
              children: [
                Expanded(
                  child: _metric(
                    'Siap diterima',
                    '$accepted',
                    AppColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric('Siap ditolak', '$rejected', AppColors.danger),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const WarehouseInfoPanel(
              icon: Icons.warning_amber_rounded,
              color: AppColors.warning,
              message:
                  'Approval akan submit Quality Inspection sesuai hasil Accepted atau Rejected yang sudah ditentukan.',
            ),
            warehouseSectionGap,
            WarehouseSearchField(
              controller: _search,
              hintText: 'Cari inspeksi, item, atau referensi',
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(
                labelText: 'Filter hasil QC',
                prefixIcon: Icon(Icons.fact_check_outlined),
              ),
              items: const [
                DropdownMenuItem(value: '', child: Text('Semua hasil')),
                DropdownMenuItem(value: 'Accepted', child: Text('Accepted')),
                DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
              ],
              onChanged: (value) => setState(
                () => _status = value?.isEmpty == true ? null : value,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _periodDays,
              decoration: const InputDecoration(
                labelText: 'Periode inspeksi',
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
              title: 'Daftar Approval',
              subtitle: '${rows.length} draft ditampilkan',
              icon: Icons.list_alt_rounded,
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty && !_loading)
              const ErpEmptyState(
                title: 'Tidak ada QC menunggu approval',
                message: 'Semua Quality Inspection draft sudah ditangani.',
              )
            else
              ...rows.map(_approvalCard),
          ],
        ),
      ),
    );
  }

  List<QualityInspectionRecord> _filteredRows() {
    final query = _search.text.trim().toLowerCase();
    return _rows.where((row) {
      return (_status == null ||
              row.status.toLowerCase() == _status!.toLowerCase()) &&
          (query.isEmpty ||
              row.name.toLowerCase().contains(query) ||
              row.itemCode.toLowerCase().contains(query) ||
              row.itemName.toLowerCase().contains(query) ||
              row.referenceName.toLowerCase().contains(query));
    }).toList();
  }

  Widget _approvalCard(QualityInspectionRecord row) {
    final accepted = row.status.toLowerCase() == 'accepted';
    final rejected = row.status.toLowerCase() == 'rejected';
    final ready = accepted || rejected;
    final color = accepted
        ? AppColors.success
        : rejected
        ? AppColors.danger
        : AppColors.warning;
    final submitting = _submittingName == row.name;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.1),
                  foregroundColor: color,
                  child: Icon(
                    accepted
                        ? Icons.check_rounded
                        : rejected
                        ? Icons.close_rounded
                        : Icons.hourglass_empty_rounded,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.itemName.isEmpty ? row.itemCode : row.itemName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        [
                          row.name,
                          if (row.inspectionType.isNotEmpty) row.inspectionType,
                          if (row.reportDate != null)
                            DateFormat('dd MMM yyyy').format(row.reportDate!),
                        ].join(' | '),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  row.status.isEmpty ? 'Belum siap' : row.status,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            if (row.referenceName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${row.referenceType}: ${row.referenceName}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: !ready || submitting ? null : () => _approve(row),
              icon: submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.approval_outlined),
              label: Text(ready ? 'Review & Submit' : 'Hasil QC belum siap'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color color) => Container(
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
          style: TextStyle(
            color: color,
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
