import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/spg_workspace.dart';
import '../../../state/spg/spg_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_error_message.dart';
import '../../../utils/num_parse.dart';
import '../../../widgets/responsive/responsive_layout.dart';

class SpgOverviewTab extends StatefulWidget {
  final ValueChanged<int> onMenuSelected;

  const SpgOverviewTab({super.key, required this.onMenuSelected});

  @override
  State<SpgOverviewTab> createState() => _SpgOverviewTabState();
}

class _SpgOverviewTabState extends State<SpgOverviewTab> {
  bool _loading = true;
  String? _error;
  _DaySummary _summary = const _DaySummary();
  SpgAssignmentScope _scope = const SpgAssignmentScope.unrestricted();
  late DateTime _from;
  late DateTime _to;
  String? _employeeId;
  String? _customerId;
  int? _docstatus;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _to = today;
    _from = today.subtract(const Duration(days: 6));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<SpgState>();
      final scope = await state.fetchSpgAssignmentScope(from: _from, to: _to);
      if (!mounted) return;
      var employee = _employeeId;
      var customer = _customerId;
      if (scope.lockEmployee) employee = scope.lockedEmployee;
      final employees = scope.employees;
      if (employee != null &&
          employee.isNotEmpty &&
          !employees.any((option) => option.id == employee)) {
        employee = scope.lockEmployee ? scope.lockedEmployee : null;
      }
      final stores = scope.storesFor(employee);
      if (customer != null &&
          customer.isNotEmpty &&
          !stores.any((option) => option.id == customer)) {
        customer = null;
      }
      final reports = await state.fetchSpgDailyReports(
        from: _from,
        to: _to,
        employee: employee,
        customer: customer,
        docstatus: _docstatus,
      );
      final details = await Future.wait(
        reports.take(30).map((row) async {
          final name = row['name']?.toString().trim() ?? '';
          if (name.isEmpty) return row;
          try {
            return await state.fetchSpgDailyReportDetail(name);
          } catch (_) {
            return row;
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        _scope = scope;
        _employeeId = employee;
        _customerId = customer;
        _summary = _DaySummary.fromReports(details);
        if (scope.error.isNotEmpty) _error = scope.error;
      });
    } catch (error) {
      if (mounted) setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openFilter() async {
    final result = await showModalBottomSheet<_SpgFilterValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _SpgFilterSheet(
        from: _from,
        to: _to,
        employeeId: _employeeId,
        customerId: _customerId,
        docstatus: _docstatus,
        scope: _scope,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _from = result.from;
      _to = result.to;
      _employeeId = _scope.lockEmployee ? _scope.lockedEmployee : result.employeeId;
      _customerId = result.customerId;
      _docstatus = result.docstatus;
    });
    await _load();
  }

  String _storeLabel() {
    final id = _customerId?.trim() ?? '';
    if (id.isEmpty) return 'Semua Toko';
    for (final option in _scope.storesFor(_employeeId)) {
      if (option.id == id) return option.label;
    }
    return id;
  }

  String _spgLabel() {
    if (_scope.lockEmployee) {
      final name = _scope.lockedEmployeeName.trim();
      return name.isEmpty ? 'SPG login' : name;
    }
    final id = _employeeId?.trim() ?? '';
    if (id.isEmpty) return 'Semua SPG';
    for (final option in _scope.employees) {
      if (option.id == id) return option.label;
    }
    return id;
  }

  String _statusLabel() {
    if (_docstatus == 0) return 'Draft';
    if (_docstatus == 1) return 'Submitted';
    if (_docstatus == 2) return 'Cancelled';
    return 'Semua Status';
  }

  String _rangeText() {
    if (_from.year == _to.year && _from.month == _to.month) {
      return '${_from.day}–${_to.day} ${_monthName(_to.month)} ${_to.year}';
    }
    if (_from.year == _to.year) {
      return '${_from.day} ${_monthName(_from.month)} – ${_to.day} ${_monthName(_to.month)} ${_to.year}';
    }
    return '${_longDate(_from)} – ${_longDate(_to)}';
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<SpgState>().appState.currentEmployeeProfile;
    final employeeName = profile['employee_name']?.toString().trim() ?? '';
    final user = context.watch<SpgState>().appState.currentUser?.trim() ?? '';
    final name = employeeName.isNotEmpty
        ? employeeName
        : (user.isNotEmpty ? user : 'SPG');
    final site = context.watch<SpgState>().appState.selectedSiteName.trim();
    final place = _summary.place.isNotEmpty ? _summary.place : site;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 104),
        children: [
          _greeting(name, place),
          const SizedBox(height: 14),
          _filterBar(),
          const SizedBox(height: 14),
          _summaryCard(),
          const SizedBox(height: 14),
          _productsCard(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_month_rounded,
            color: AppColors.slate,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_rangeText()}  |  ${_storeLabel()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_spgLabel()} · ${_statusLabel()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _loading ? null : _openFilter,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.softGreen,
              foregroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.filter_alt_outlined, size: 15),
            label: const Text(
              'Filter',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _greeting(String name, String place) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E8A4C), Color(0xFF146B3A), Color(0xFF0E4F2C)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0E4F2C).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -8,
            bottom: -18,
            child: Icon(
              Icons.eco_rounded,
              size: 92,
              color: AppColors.white.withValues(alpha: 0.1),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Selamat datang,',
                style: TextStyle(
                  color: Color(0xFFD7F5E4),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (place.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 14,
                      color: Color(0xFFD7F5E4),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFD7F5E4),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final status = _summary.statusLabel;
    return Container(
      padding: const EdgeInsets.all(16),
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ringkasan',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _rangeText(),
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (status.isNotEmpty)
                _statusChip(status),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'Stock Awal',
                  _qty(_summary.opening),
                  Icons.inventory_2_rounded,
                  const Color(0xFFE7F6EC),
                  const Color(0xFF1B8A4A),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metric(
                  'Stock Akhir',
                  _qty(_summary.closing),
                  Icons.widgets_rounded,
                  const Color(0xFFE8F1FB),
                  const Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'Sell Out',
                  _qty(_summary.sellOut),
                  Icons.trending_up_rounded,
                  const Color(0xFFFFF6E4),
                  const Color(0xFFE09A12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _metric(
                  'Total Produk',
                  '${_summary.products.length} SKU',
                  Icons.layers_rounded,
                  const Color(0xFFF3EEFF),
                  const Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _productsCard() {
    final products = _summary.products;
    final maxValue = products.fold<double>(
      0,
      (max, item) => item.sellOut > max ? item.sellOut : max,
    );
    return Container(
      padding: const EdgeInsets.all(16),
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
            children: [
              const Expanded(
                child: Text(
                  'Sell Out per Produk',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => widget.onMenuSelected(2),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
                label: const Text('Lihat Semua'),
              ),
            ],
          ),
          if (products.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                'Belum ada laporan pada rentang ini.',
                style: TextStyle(
                  color: AppColors.slate,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            for (var index = 0; index < products.take(5).length; index++) ...[
              if (index > 0) const SizedBox(height: 12),
              _productRow(products[index], maxValue, index),
            ],
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final submitted = status == 'Submitted';
    final color = submitted ? AppColors.primary : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: submitted ? AppColors.softGreen : const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            submitted ? Icons.check_circle_rounded : Icons.edit_note_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _productRow(_ProductTotal product, double maxValue, int index) {
    final tone = _productTone(product.name, index);
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tone.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(tone.emoji, style: const TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Text(
            product.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: maxValue <= 0 ? 0 : product.sellOut / maxValue,
              backgroundColor: const Color(0xFFE7F6EC),
              color: const Color(0xFF1B8A4A),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 58,
          child: Text(
            _qty(product.sellOut),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _metric(
    String label,
    String value,
    IconData icon,
    Color background,
    Color foreground,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 18),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  String _qty(double value) {
    final unit = _summary.uom.isEmpty ? '' : ' ${_summary.uom}';
    if (value == value.roundToDouble()) return '${value.toInt()}$unit';
    return '${value.toStringAsFixed(1)}$unit';
  }
}

class _ProductTone {
  final String emoji;
  final Color background;

  const _ProductTone(this.emoji, this.background);
}

_ProductTone _productTone(String name, int index) {
  final key = name.toLowerCase();
  if (key.contains('pepaya') || key.contains('papaya') || key.contains('avocado')) {
    return const _ProductTone('🥑', Color(0xFFE7F6EC));
  }
  if (key.contains('jeruk') || key.contains('orange') || key.contains('mangga')) {
    return const _ProductTone('🍊', Color(0xFFFFF6E4));
  }
  if (key.contains('apel') || key.contains('apple')) {
    return const _ProductTone('🍎', Color(0xFFFFEEEE));
  }
  if (key.contains('anggur') || key.contains('grape')) {
    return const _ProductTone('🍇', Color(0xFFF3EEFF));
  }
  if (key.contains('pisang') ||
      key.contains('banana') ||
      key.contains('cavendish') ||
      key.contains('lakatan') ||
      key.contains('barangan')) {
    return const _ProductTone('🍌', Color(0xFFFFF8D8));
  }
  const fallback = [
    _ProductTone('🍌', Color(0xFFFFF8D8)),
    _ProductTone('🥑', Color(0xFFE7F6EC)),
    _ProductTone('🍊', Color(0xFFFFF6E4)),
    _ProductTone('🍇', Color(0xFFF3EEFF)),
  ];
  return fallback[index % fallback.length];
}

class _ProductTotal {
  final String name;
  final double sellOut;

  const _ProductTotal(this.name, this.sellOut);
}

class _DaySummary {
  final double opening;
  final double closing;
  final double sellOut;
  final String uom;
  final String place;
  final String statusLabel;
  final List<_ProductTotal> products;

  const _DaySummary({
    this.opening = 0,
    this.closing = 0,
    this.sellOut = 0,
    this.uom = '',
    this.place = '',
    this.statusLabel = '',
    this.products = const [],
  });

  factory _DaySummary.fromReports(List<Map<String, dynamic>> reports) {
    if (reports.isEmpty) return const _DaySummary();
    var opening = 0.0;
    var closing = 0.0;
    var sellOut = 0.0;
    var submitted = 0;
    var draft = 0;
    final places = <String>{};
    final byItem = <String, double>{};
    var uom = '';
    for (final report in reports) {
      final customer = report['customer_name']?.toString().trim().isNotEmpty ==
              true
          ? report['customer_name'].toString().trim()
          : report['customer']?.toString().trim() ?? '';
      if (customer.isNotEmpty) places.add(customer);
      final status = int.tryParse(report['docstatus']?.toString() ?? '') ?? 0;
      if (status == 1) {
        submitted++;
      } else if (status == 0) {
        draft++;
      }
      final rows = report['selling_items'];
      if (rows is! List) continue;
      for (final raw in rows.whereType<Map>()) {
        final name = raw['item']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final rowUom = raw['uom']?.toString().trim() ?? '';
        if (uom.isEmpty && rowUom.isNotEmpty) uom = rowUom;
        opening += NumParse.asDouble(raw['opening_stock']);
        closing += NumParse.asDouble(raw['closing_stock']);
        final sold = NumParse.asDouble(raw['sell_out']);
        sellOut += sold;
        byItem[name] = (byItem[name] ?? 0) + sold;
      }
    }
    final products = byItem.entries
        .map((entry) => _ProductTotal(entry.key, entry.value))
        .toList()
      ..sort((a, b) => b.sellOut.compareTo(a.sellOut));
    final statusLabel = draft > 0
        ? 'Draft'
        : submitted > 0
        ? 'Submitted'
        : '';
    return _DaySummary(
      opening: opening,
      closing: closing,
      sellOut: sellOut,
      uom: uom,
      place: places.join(', '),
      statusLabel: statusLabel,
      products: products,
    );
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _monthName(int month) {
  const months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  return months[month - 1];
}

String _longDate(DateTime date) {
  return '${date.day} ${_monthName(date.month)} ${date.year}';
}

class _SpgFilterValue {
  final DateTime from;
  final DateTime to;
  final String? employeeId;
  final String? customerId;
  final int? docstatus;

  const _SpgFilterValue({
    required this.from,
    required this.to,
    required this.employeeId,
    required this.customerId,
    required this.docstatus,
  });
}

class _SpgFilterSheet extends StatefulWidget {
  final DateTime from;
  final DateTime to;
  final String? employeeId;
  final String? customerId;
  final int? docstatus;
  final SpgAssignmentScope scope;

  const _SpgFilterSheet({
    required this.from,
    required this.to,
    required this.employeeId,
    required this.customerId,
    required this.docstatus,
    required this.scope,
  });

  @override
  State<_SpgFilterSheet> createState() => _SpgFilterSheetState();
}

class _SpgFilterSheetState extends State<_SpgFilterSheet> {
  late DateTime _from;
  late DateTime _to;
  String? _employeeId;
  String? _customerId;
  int? _docstatus;

  @override
  void initState() {
    super.initState();
    _from = widget.from;
    _to = widget.to;
    _employeeId = widget.scope.lockEmployee
        ? widget.scope.lockedEmployee
        : widget.employeeId;
    _customerId = widget.customerId;
    _docstatus = widget.docstatus;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final day = _dateOnly(picked);
      if (isStart) {
        _from = day;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = day;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
  }

  void _reset() {
    final today = _dateOnly(DateTime.now());
    setState(() {
      _to = today;
      _from = today.subtract(const Duration(days: 6));
      _employeeId = widget.scope.lockEmployee ? widget.scope.lockedEmployee : null;
      _customerId = null;
      _docstatus = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.scope.lockEmployee;
    final stores = widget.scope.storesFor(_employeeId);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 14),
              const Text(
                'Filter',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _sheetDate('Dari Tanggal', _from, () => _pickDate(isStart: true)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _sheetDate('Sampai Tanggal', _to, () => _pickDate(isStart: false)),
                  ),
                ],
              ),
              if (!locked) ...[
                const SizedBox(height: 10),
                _sheetChoice(
                  label: 'Nama SPG',
                  icon: Icons.badge_outlined,
                  value: _employeeId,
                  options: widget.scope.employees,
                  allLabel: 'Semua SPG',
                  onChanged: (value) {
                    setState(() {
                      _employeeId = value;
                      if (_customerId != null &&
                          !widget.scope
                              .storesFor(value)
                              .any((option) => option.id == _customerId)) {
                        _customerId = null;
                      }
                    });
                  },
                ),
              ],
              const SizedBox(height: 10),
              _sheetChoice(
                label: 'Toko',
                icon: Icons.storefront_outlined,
                value: _customerId,
                options: stores,
                allLabel: 'Semua Toko',
                onChanged: (value) => setState(() => _customerId = value),
              ),
              const SizedBox(height: 10),
              _sheetChoice(
                label: 'Status',
                icon: Icons.flag_outlined,
                value: _docstatus?.toString(),
                options: const [
                  SpgNamedOption('0', 'Draft'),
                  SpgNamedOption('1', 'Submitted'),
                  SpgNamedOption('2', 'Cancelled'),
                ],
                allLabel: 'Semua Status',
                onChanged: (value) {
                  setState(() => _docstatus = int.tryParse(value ?? ''));
                },
              ),
              if (locked) ...[
                const SizedBox(height: 10),
                const Text(
                  'SPG hanya melihat dokumen yang dibuat sendiri, dan toko dari assignment.',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reset,
                      child: const Text('Atur ulang'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(
                          context,
                          _SpgFilterValue(
                            from: _from,
                            to: _to,
                            employeeId: _employeeId,
                            customerId: _customerId,
                            docstatus: _docstatus,
                          ),
                        );
                      },
                      child: const Text('Terapkan'),
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

  Widget _sheetDate(String label, DateTime value, VoidCallback onTap) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          prefixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          '$day/$month/${value.year}',
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _sheetChoice({
    required String label,
    required IconData icon,
    required String? value,
    required List<SpgNamedOption> options,
    required String allLabel,
    required ValueChanged<String?> onChanged,
  }) {
    final ids = options.map((option) => option.id).where((id) => id.isNotEmpty).toSet();
    final selected = value != null && ids.contains(value) ? value : null;
    return DropdownButtonFormField<String?>(
      key: ValueKey('$label-${selected ?? 'all'}-${ids.join(',')}'),
      initialValue: selected,
      isExpanded: true,
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(allLabel)),
        for (final id in ids)
          DropdownMenuItem<String?>(
            value: id,
            child: Text(
              options.firstWhere((option) => option.id == id).label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        prefixIcon: Icon(icon, size: 18),
      ),
    );
  }
}
