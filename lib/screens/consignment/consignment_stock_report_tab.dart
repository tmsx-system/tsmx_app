import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/erp_format.dart';
import '../../widgets/erp/erp_empty_state.dart';
import '../../widgets/erp/erp_error_box.dart';

/// Mobile view for ERPNext Query Report:
/// [Consignment Stock by Customer](https://jakarta.willshine.id/app/query-report/Consignment%20Stock%20by%20Customer)
class ConsignmentStockReportTab extends StatefulWidget {
  const ConsignmentStockReportTab({super.key});

  @override
  State<ConsignmentStockReportTab> createState() =>
      _ConsignmentStockReportTabState();
}

class _ConsignmentStockReportTabState extends State<ConsignmentStockReportTab>
    with AutomaticKeepAliveClientMixin {
  static const _reportName = 'Consignment Stock by Customer';
  static const _defaultParentWarehouse = 'Consignment - Jakarta';

  DateTime _fromDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _toDate = DateTime.now();
  _ReportDatePreset _datePreset = _ReportDatePreset.yearToDate;
  String? _parentWarehouse;

  bool _loading = false;
  bool _warehousesLoading = true;
  String? _error;
  List<String> _parentWarehouses = const [];
  List<_ReportColumn> _columns = const [];
  List<Map<String, dynamic>> _rows = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _loadWarehouses() async {
    setState(() {
      _warehousesLoading = true;
      _error = null;
    });
    try {
      final appState = context.read<AppState>();
      await appState.frappeService.ensureLoggedIn();

      // Parent warehouse for this report is usually a group warehouse
      // (e.g. "Consignment - Jakarta"). WarehouseStockState only keeps
      // non-group warehouses, so fetch groups separately here.
      List<Map<String, dynamic>> rows;
      try {
        rows = await appState.frappeService.fetchResource(
          'Warehouse',
          fields: const [
            'name',
            'warehouse_name',
            'parent_warehouse',
            'is_group',
            'disabled',
          ],
          filters: const [
            ['disabled', '=', 0],
          ],
          orderBy: 'name asc',
          limit: 500,
        );
      } catch (_) {
        rows = await appState.frappeService.fetchResource(
          'Warehouse',
          fields: const ['name', 'warehouse_name', 'is_group'],
          orderBy: 'name asc',
          limit: 500,
        );
      }

      if (!mounted) return;

      final allNames = rows
          .map((row) => row['name']?.toString().trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toSet();

      final groupOrRoot = rows
          .where((row) {
            final isGroup =
                row['is_group'] == 1 || row['is_group'] == true;
            final parent =
                row['parent_warehouse']?.toString().trim() ?? '';
            return isGroup || parent.isEmpty;
          })
          .map((row) => row['name']?.toString().trim() ?? '')
          .where((name) => name.isNotEmpty)
          .toSet();

      final consignmentNames = allNames
          .where((name) => name.toLowerCase().contains('consignment'))
          .toSet();

      final options = <String>{
        ...groupOrRoot,
        ...consignmentNames,
        _defaultParentWarehouse,
      }.toList()
        ..sort();

      var selected = _parentWarehouse;
      if (selected == null || !options.contains(selected)) {
        if (options.contains(_defaultParentWarehouse)) {
          selected = _defaultParentWarehouse;
        } else {
          final consignmentMatch = options.where(
            (name) => name.toLowerCase().contains('consignment'),
          );
          selected = consignmentMatch.isNotEmpty
              ? consignmentMatch.first
              : (options.isNotEmpty ? options.first : null);
        }
      }

      setState(() {
        _parentWarehouses = options;
        _parentWarehouse = selected;
        _warehousesLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _parentWarehouses = const [_defaultParentWarehouse];
        _parentWarehouse = _defaultParentWarehouse;
        _warehousesLoading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _bootstrap() async {
    await _loadWarehouses();
    if (!mounted) return;
    if ((_parentWarehouse ?? '').trim().isEmpty) return;
    await _loadReport();
  }

  Future<void> _loadReport() async {
    final warehouse = (_parentWarehouse ?? '').trim();
    if (warehouse.isEmpty) {
      setState(() => _error = 'Pilih Parent Warehouse terlebih dahulu.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final appState = context.read<AppState>();
      final diagnose = await _diagnoseReportAccess(appState);
      if (diagnose != null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = diagnose;
          _rows = const [];
        });
        return;
      }

      final response = await appState.frappeService.callMethod(
        'frappe.desk.query_report.run',
        args: {
          'report_name': _reportName,
          'filters': {
            'from_date': DateRangePresets.toFrappeDate(_fromDate),
            'to_date': DateRangePresets.toFrappeDate(_toDate),
            'parent_warehouse': warehouse,
          },
          'ignore_prepared_report': true,
          'are_default_filters': false,
        },
      );

      final report = _queryReportPayload(response);
      final columns = _queryReportColumns(report?['columns']);
      final rawRows = _queryReportRows(report?['result'] ?? report?['data']);
      final rows = <Map<String, dynamic>>[];
      for (final raw in rawRows) {
        final mapped = _queryReportRowMap(raw, columns);
        if (_isTotalRow(mapped)) continue;
        if (mapped.isEmpty) continue;
        rows.add(mapped);
      }

      if (!mounted) return;
      setState(() {
        _columns = columns
            .map(_ReportColumn.fromQueryColumn)
            .where((column) => column.field.isNotEmpty)
            .toList(growable: false);
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      final appState = context.read<AppState>();
      final diagnosed = await _friendlyReportErrorAsync(appState, error);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = diagnosed;
        _rows = const [];
      });
    }
  }

  /// ERPNext `query_report.run` requires BOTH:
  /// 1) Report roles (Custom Role / Has Role) via Role Permission for Page and Report
  /// 2) Ref DocType "Report" permission via Role Permission Manager
  Future<String?> _diagnoseReportAccess(AppState appState) async {
    String refDoctype = '';
    try {
      final reportDoc =
          await appState.frappeService.fetchDocument('Report', _reportName);
      refDoctype = reportDoc['ref_doctype']?.toString().trim() ?? '';
    } catch (error) {
      final lower = error.toString().toLowerCase();
      if (lower.contains('permission') ||
          lower.contains('tidak diizinkan') ||
          lower.contains('403')) {
        return _buildReportRoleError(
          detail:
              'Gagal baca DocType Report "$_reportName". '
              'Pastikan role user ada di Role Permission for Page and Report.',
        );
      }
      // Non-permission: continue and let query_report.run surface the error.
      return null;
    }

    if (refDoctype.isEmpty) return null;

    final canReport = await appState.canReportDoctype(refDoctype);
    if (!canReport) {
      return _buildRefDoctypeReportError(refDoctype);
    }
    return null;
  }

  Future<String> _friendlyReportErrorAsync(
    AppState appState,
    Object error,
  ) async {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    final refMatch = RegExp(
      r'permission to get a report on:\s*(.+)$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(raw);
    if (refMatch != null) {
      final refDoctype = (refMatch.group(1) ?? '').trim();
      if (refDoctype.isNotEmpty) {
        return _buildRefDoctypeReportError(refDoctype, serverDetail: raw);
      }
    }

    if (lower.contains("don't have access to report") ||
        lower.contains('dont have access to report') ||
        lower.contains('tidak punya akses query report')) {
      return _buildReportRoleError(serverDetail: raw);
    }

    final isPermission = lower.contains('permission') ||
        lower.contains('not permitted') ||
        lower.contains('tidak diizinkan') ||
        lower.contains('403');
    if (!isPermission) return raw;

    // Generic permission: try to pinpoint Ref DocType Report vs report roles.
    try {
      final reportDoc =
          await appState.frappeService.fetchDocument('Report', _reportName);
      final refDoctype = reportDoc['ref_doctype']?.toString().trim() ?? '';
      if (refDoctype.isNotEmpty) {
        final canReport = await appState.canReportDoctype(refDoctype);
        if (!canReport) {
          return _buildRefDoctypeReportError(refDoctype, serverDetail: raw);
        }
      }
    } catch (_) {
      // Ignore — fall through to dual checklist.
    }

    return _buildDualPermissionError(serverDetail: raw);
  }

  String _buildReportRoleError({String? detail, String? serverDetail}) {
    final buffer = StringBuffer()
      ..writeln('Tidak punya akses Query Report "$_reportName".')
      ..writeln()
      ..writeln('Cek 1 — Role Permission for Page and Report:')
      ..writeln('1. Set Role For = Report, pilih "$_reportName".')
      ..writeln('2. Centang role yang dipakai user login, lalu Update.')
      ..writeln('3. Clear Cache / logout-login ulang.');
    if (detail != null && detail.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(detail.trim());
    }
    if (serverDetail != null && serverDetail.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Detail server: $serverDetail');
    }
    return buffer.toString().trim();
  }

  String _buildRefDoctypeReportError(
    String refDoctype, {
    String? serverDetail,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        'Tidak punya permission "Report" pada Ref DocType "$refDoctype".',
      )
      ..writeln()
      ..writeln(
        'Ini beda dari Role Permission for Page and Report. '
        'Query Report butuh keduanya.',
      )
      ..writeln()
      ..writeln('Cek 2 — Role Permission Manager:')
      ..writeln('1. Buka Role Permission Manager.')
      ..writeln('2. Pilih DocType = "$refDoctype".')
      ..writeln(
        '3. Untuk role user login, centang kolom Report '
        '(biasanya juga perlu Read).',
      )
      ..writeln('4. Simpan, lalu Clear Cache / logout-login ulang.');
    if (serverDetail != null && serverDetail.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Detail server: $serverDetail');
    }
    return buffer.toString().trim();
  }

  String _buildDualPermissionError({String? serverDetail}) {
    final buffer = StringBuffer()
      ..writeln('Tidak punya akses Query Report "$_reportName".')
      ..writeln()
      ..writeln('ERPNext memeriksa 2 hal:')
      ..writeln()
      ..writeln('A) Role Permission for Page and Report')
      ..writeln('   — role user harus dicentang untuk report ini.')
      ..writeln()
      ..writeln('B) Role Permission Manager (Ref DocType)')
      ..writeln(
        '   — role user harus punya kolom Report '
        '(+ biasanya Read) pada Ref DocType report.',
      )
      ..writeln()
      ..writeln('Setelah ubah permission: Update/Save, Clear Cache, login ulang.');
    if (serverDetail != null && serverDetail.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Detail server: $serverDetail');
    }
    return buffer.toString().trim();
  }

  void _applyDatePreset(_ReportDatePreset preset) {
    final today = DateTime.now();
    late final DateTime from;
    late final DateTime to;
    switch (preset) {
      case _ReportDatePreset.yearToDate:
        from = DateTime(today.year, 1, 1);
        to = today;
      case _ReportDatePreset.monthToDate:
        final range = DateRangePresets.monthToDateRange();
        from = range.from;
        to = range.to;
      case _ReportDatePreset.last7Days:
        final range = DateRangePresets.last7DaysRange();
        from = range.from;
        to = range.to;
      case _ReportDatePreset.last30Days:
        final range = DateRangePresets.last30DaysRange();
        from = range.from;
        to = range.to;
      case _ReportDatePreset.custom:
        return;
    }
    setState(() {
      _datePreset = preset;
      _fromDate = from;
      _toDate = to;
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _datePreset = _ReportDatePreset.custom;
      if (isFrom) {
        _fromDate = picked;
        if (_fromDate.isAfter(_toDate)) _toDate = _fromDate;
      } else {
        _toDate = picked;
        if (_toDate.isBefore(_fromDate)) _fromDate = _toDate;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final dateFmt = DateFormat('dd/MM/yyyy');
    final displayColumns = _columns.take(6).toList(growable: false);
    final warehouseValue =
        _parentWarehouse != null && _parentWarehouses.contains(_parentWarehouse)
            ? _parentWarehouse
            : null;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadReport,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 104),
        children: [
          _FilterCard(
            loading: _loading,
            warehousesLoading: _warehousesLoading,
            fromLabel: dateFmt.format(_fromDate),
            toLabel: dateFmt.format(_toDate),
            datePreset: _datePreset,
            warehouseValue: warehouseValue,
            warehouses: _parentWarehouses,
            onPreset: _applyDatePreset,
            onPickFrom: () => _pickDate(isFrom: true),
            onPickTo: () => _pickDate(isFrom: false),
            onWarehouseChanged: (value) =>
                setState(() => _parentWarehouse = value),
            onRun: _loadReport,
          ),
          if (_loading) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: const LinearProgressIndicator(
                minHeight: 3,
                color: AppColors.primary,
                backgroundColor: AppColors.softGreen,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            ErpErrorBox(message: _error!, onRetry: _loading ? null : _loadReport),
          ],
          if (!_loading && _error == null && _rows.isEmpty) ...[
            const SizedBox(height: 18),
            const ErpEmptyState(
              title: 'Tidak ada data stock consignment',
              message:
                  'Ubah periode atau parent warehouse, lalu jalankan report lagi.',
              icon: Icons.inventory_2_outlined,
            ),
          ],
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ResultsHeader(
              count: _rows.length,
              warehouse: warehouseValue ?? '-',
              rangeLabel:
                  '${dateFmt.format(_fromDate)} – ${dateFmt.format(_toDate)}',
            ),
            const SizedBox(height: 12),
            for (final row in _rows)
              _ReportRowCard(row: row, columns: displayColumns),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic>? _queryReportPayload(dynamic response) {
    if (response is! Map) return null;
    final message = response['message'];
    if (message is Map) return Map<String, dynamic>.from(message);
    return Map<String, dynamic>.from(response);
  }

  List<Map<String, dynamic>> _queryReportColumns(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((column) {
      if (column is String) return {'fieldname': column, 'label': column};
      if (column is Map) return Map<String, dynamic>.from(column);
      return <String, dynamic>{};
    }).toList();
  }

  List<dynamic> _queryReportRows(dynamic raw) => raw is List ? raw : const [];

  Map<String, dynamic> _queryReportRowMap(
    dynamic row,
    List<Map<String, dynamic>> columns,
  ) {
    if (row is Map) return Map<String, dynamic>.from(row);
    if (row is! List) return const {};
    final mapped = <String, dynamic>{};
    for (var i = 0; i < row.length && i < columns.length; i++) {
      final key =
          columns[i]['fieldname']?.toString() ??
          columns[i]['field']?.toString() ??
          columns[i]['label']?.toString() ??
          '';
      if (key.isNotEmpty) mapped[key] = row[i];
    }
    return mapped;
  }

  bool _isTotalRow(Map<String, dynamic> row) {
    final values = row.values.map((value) => value?.toString().toLowerCase() ?? '');
    return values.any(
      (value) =>
          value == 'total' ||
          value.startsWith('total ') ||
          value.contains('grand total'),
    );
  }
}

class _ReportDatePreset {
  static const yearToDate = _ReportDatePreset._('year');
  static const monthToDate = _ReportDatePreset._('month');
  static const last7Days = _ReportDatePreset._('7d');
  static const last30Days = _ReportDatePreset._('30d');
  static const custom = _ReportDatePreset._('custom');

  final String id;
  const _ReportDatePreset._(this.id);
}

class _ReportColumn {
  final String field;
  final String label;
  final String fieldtype;

  const _ReportColumn({
    required this.field,
    required this.label,
    this.fieldtype = '',
  });

  factory _ReportColumn.fromQueryColumn(Map<String, dynamic> column) {
    final field = column['fieldname']?.toString() ??
        column['field']?.toString() ??
        column['label']?.toString() ??
        '';
    final label = column['label']?.toString() ??
        column['fieldname']?.toString() ??
        field;
    final fieldtype = column['fieldtype']?.toString() ??
        column['type']?.toString() ??
        '';
    return _ReportColumn(field: field, label: label, fieldtype: fieldtype);
  }

  bool get isNumeric {
    final type = fieldtype.toLowerCase();
    if (type.contains('float') ||
        type.contains('currency') ||
        type.contains('int') ||
        type.contains('percent')) {
      return true;
    }
    final key = '$field $label'.toLowerCase();
    return key.contains('qty') ||
        key.contains('quantity') ||
        key.contains('amount') ||
        key.contains('value') ||
        key.contains('balance') ||
        key.contains('stock');
  }

  bool get isCurrencyLike {
    final type = fieldtype.toLowerCase();
    if (type.contains('currency')) return true;
    final key = '$field $label'.toLowerCase();
    return key.contains('amount') ||
        key.contains('value') ||
        key.contains('valuation');
  }
}

class _FilterCard extends StatelessWidget {
  final bool loading;
  final bool warehousesLoading;
  final String fromLabel;
  final String toLabel;
  final _ReportDatePreset datePreset;
  final String? warehouseValue;
  final List<String> warehouses;
  final ValueChanged<_ReportDatePreset> onPreset;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final ValueChanged<String?> onWarehouseChanged;
  final VoidCallback onRun;

  const _FilterCard({
    required this.loading,
    required this.warehousesLoading,
    required this.fromLabel,
    required this.toLabel,
    required this.datePreset,
    required this.warehouseValue,
    required this.warehouses,
    required this.onPreset,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onWarehouseChanged,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.assessment_outlined,
                  color: AppColors.primary,
                  size: 23,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Consignment Stock by Customer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Query Report ERPNext · filter & jalankan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.slate,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Periode',
            style: TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PresetChip(
                label: 'Tahun ini',
                selected: datePreset == _ReportDatePreset.yearToDate,
                onTap: loading
                    ? null
                    : () => onPreset(_ReportDatePreset.yearToDate),
              ),
              _PresetChip(
                label: 'Bulan ini',
                selected: datePreset == _ReportDatePreset.monthToDate,
                onTap: loading
                    ? null
                    : () => onPreset(_ReportDatePreset.monthToDate),
              ),
              _PresetChip(
                label: '7 hari',
                selected: datePreset == _ReportDatePreset.last7Days,
                onTap: loading
                    ? null
                    : () => onPreset(_ReportDatePreset.last7Days),
              ),
              _PresetChip(
                label: '30 hari',
                selected: datePreset == _ReportDatePreset.last30Days,
                onTap: loading
                    ? null
                    : () => onPreset(_ReportDatePreset.last30Days),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DateChip(
                  label: 'Dari',
                  value: fromLabel,
                  onTap: loading ? null : onPickFrom,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateChip(
                  label: 'Sampai',
                  value: toLabel,
                  onTap: loading ? null : onPickTo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Parent Warehouse',
            style: TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: warehouseValue,
                borderRadius: BorderRadius.circular(14),
                icon: warehousesLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.slate,
                      ),
                hint: Text(
                  warehousesLoading ? 'Memuat warehouse...' : 'Pilih warehouse',
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                items: [
                  for (final warehouse in warehouses)
                    DropdownMenuItem(
                      value: warehouse,
                      child: Text(
                        warehouse,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (warehousesLoading || loading)
                    ? null
                    : onWarehouseChanged,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: loading ? null : onRun,
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(loading ? 'Memuat report...' : 'Jalankan Report'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.45),
                elevation: 0,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.softGreen : AppColors.background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _DateChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.calendar_today_rounded,
                size: 15,
                color: AppColors.primary.withValues(alpha: 0.75),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  final int count;
  final String warehouse;
  final String rangeLabel;

  const _ResultsHeader({
    required this.count,
    required this.warehouse,
    required this.rangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count baris',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  warehouse,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  rangeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
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

class _ReportRowCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final List<_ReportColumn> columns;

  const _ReportRowCard({required this.row, required this.columns});

  @override
  Widget build(BuildContext context) {
    final title = _firstText(const [
      'customer',
      'customer_name',
      'party',
      'item_name',
      'item_code',
      'warehouse',
    ]);
    final subtitle = _firstText(const [
      'warehouse',
      'item_code',
      'item_name',
      'customer',
      'customer_name',
    ], exclude: title);

    final titleKeys = {
      for (final key in const [
        'customer',
        'customer_name',
        'party',
        'item_code',
        'item_name',
        'warehouse',
      ])
        key,
    };

    final detailColumns = columns.where((column) {
      final value = _cellValue(column);
      if (value.isEmpty) return false;
      if (title.isNotEmpty &&
          titleKeys.contains(column.field.toLowerCase()) &&
          value == title) {
        return false;
      }
      if (subtitle.isNotEmpty && value == subtitle) return false;
      return true;
    }).toList(growable: false);

    final metricColumns =
        detailColumns.where((c) => c.isNumeric).take(3).toList();
    final otherColumns =
        detailColumns.where((c) => !metricColumns.contains(c)).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(18),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (metricColumns.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          for (var i = 0; i < metricColumns.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Expanded(
                              child: _MetricTile(
                                label: metricColumns[i].label,
                                value: _cellValue(metricColumns[i]),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    if (otherColumns.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (final column in otherColumns)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 108,
                                child: Text(
                                  column.label,
                                  style: const TextStyle(
                                    color: AppColors.slate,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _cellValue(column),
                                  textAlign: column.isNumeric
                                      ? TextAlign.right
                                      : TextAlign.left,
                                  style: const TextStyle(
                                    color: AppColors.navy,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _firstText(List<String> keys, {String exclude = ''}) {
    for (final key in keys) {
      for (final entry in row.entries) {
        if (entry.key.toLowerCase() != key) continue;
        final value = entry.value?.toString().trim() ?? '';
        if (value.isEmpty || value.toLowerCase() == 'null') continue;
        if (exclude.isNotEmpty && value == exclude) continue;
        return value;
      }
    }
    return '';
  }

  String _cellValue(_ReportColumn column) {
    final raw = row[column.field];
    if (raw == null) return '';
    if (raw is num) {
      return column.isCurrencyLike
          ? formatErpCurrency(raw.toDouble())
          : _formatNumber(raw.toDouble());
    }
    final text = raw.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return '';
    final normalized = text.replaceAll(',', '');
    final asNumber = double.tryParse(normalized);
    if (asNumber != null &&
        RegExp(r'^-?\d+(\.\d+)?$').hasMatch(normalized) &&
        column.isNumeric) {
      return column.isCurrencyLike
          ? formatErpCurrency(asNumber)
          : _formatNumber(asNumber);
    }
    return text;
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return formatErpCurrency(value);
    }
    final parts = value.toStringAsFixed(2).split('.');
    final whole = double.tryParse(parts[0]) ?? value.truncateToDouble();
    return '${formatErpCurrency(whole)},${parts[1]}';
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
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
            value,
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
    );
  }
}
