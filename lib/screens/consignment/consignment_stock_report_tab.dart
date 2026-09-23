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
            .map(
              (column) => _ReportColumn(
                field: column['fieldname']?.toString() ??
                    column['field']?.toString() ??
                    column['label']?.toString() ??
                    '',
                label: column['label']?.toString() ??
                    column['fieldname']?.toString() ??
                    '',
              ),
            )
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
    final displayColumns = _columns.take(5).toList(growable: false);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadReport,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 104),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Consignment Stock by Customer',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sumber: Query Report ERPNext',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _DateChip(
                        label: 'Dari',
                        value: dateFmt.format(_fromDate),
                        onTap: () => _pickDate(isFrom: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DateChip(
                        label: 'Sampai',
                        value: dateFmt.format(_toDate),
                        onTap: () => _pickDate(isFrom: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Parent Warehouse',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value:
                          _parentWarehouse != null &&
                              _parentWarehouses.contains(_parentWarehouse)
                          ? _parentWarehouse
                          : null,
                      hint: Text(
                        _warehousesLoading
                            ? 'Memuat warehouse...'
                            : 'Pilih warehouse',
                      ),
                      items: [
                        for (final warehouse in _parentWarehouses)
                          DropdownMenuItem(
                            value: warehouse,
                            child: Text(warehouse, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _warehousesLoading
                          ? null
                          : (value) => setState(() => _parentWarehouse = value),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _loadReport,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(_loading ? 'Memuat...' : 'Jalankan Report'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErpErrorBox(message: _error!),
          ],
          if (!_loading && _error == null && _rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: ErpEmptyState(
                title: 'Tidak ada data stock consignment',
                message: 'Coba ubah filter tanggal atau parent warehouse.',
              ),
            ),
          if (_rows.isNotEmpty) ...[
            Text(
              '${_rows.length} baris',
              style: const TextStyle(
                color: AppColors.slate,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
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

class _ReportColumn {
  final String field;
  final String label;

  const _ReportColumn({required this.field, required this.label});
}

class _DateChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          color: AppColors.background,
        ),
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
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
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
      'item_code',
      'item_name',
      'warehouse',
    ]);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w900,
              ),
            ),
          if (title.isNotEmpty) const SizedBox(height: 8),
          for (final column in columns)
            if (_cellValue(column.field).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        column.label,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _cellValue(column.field),
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
      ),
    );
  }

  String _firstText(List<String> keys) {
    for (final key in keys) {
      for (final entry in row.entries) {
        if (entry.key.toLowerCase() == key) {
          final value = entry.value?.toString().trim() ?? '';
          if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
        }
      }
    }
    return '';
  }

  String _cellValue(String field) {
    final raw = row[field];
    if (raw == null) return '';
    if (raw is num) return formatErpCurrency(raw.toDouble());
    final text = raw.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return '';
    final asNumber = double.tryParse(text.replaceAll(',', ''));
    if (asNumber != null && RegExp(r'^-?\d+(\.\d+)?$').hasMatch(text.replaceAll(',', ''))) {
      return formatErpCurrency(asNumber);
    }
    return text;
  }
}
