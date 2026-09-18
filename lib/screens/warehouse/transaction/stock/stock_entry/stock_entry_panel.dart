import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../models/stock_entry.dart';
import '../../../../../models/warehouse_info.dart';
import '../../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../../theme/app_colors.dart';
import '../../../../../widgets/erp/erp_empty_state.dart';
import '../../../../../widgets/erp/erp_status_badge.dart';
import '../../../shared/warehouse_widgets.dart';
import 'create_stock_entry_screen.dart';
import 'stock_entry_kind.dart';

class StockEntryPanel extends StatefulWidget {
  final StockEntryKind kind;

  const StockEntryPanel({super.key, required this.kind});

  @override
  State<StockEntryPanel> createState() => _StockEntryPanelState();
}

class _StockEntryPanelState extends State<StockEntryPanel> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  bool _canCreate = false;
  String? _error;
  late String _stockEntryType;
  String? _company;
  String? _fromWarehouse;
  String? _toWarehouse;

  @override
  void initState() {
    super.initState();
    _stockEntryType = widget.kind.name;
    _search.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _bootstrap() async {
    final state = context.read<WarehouseStockState>();
    if (state.warehouses.isEmpty) {
      await state.refreshWarehouses();
    }
    if (!mounted) return;
    _company ??= state.preferredCompany(
      state.stockCompanies.map((entry) => entry.key),
    );
    await _load(includeCreatePermission: true);
  }

  Future<void> _load({bool includeCreatePermission = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<WarehouseStockState>();
      if (includeCreatePermission) {
        _canCreate = await state.canCreateDoctype('Stock Entry');
      }
      await state.refreshStockEntries(
        stockEntryType: _stockEntryType,
        company: _company,
        fromWarehouse: _fromWarehouse,
        toWarehouse: _toWarehouse,
        name: _search.text,
      );
      if (!mounted) return;
      if (state.stockEntriesError != null) {
        _error = _friendlyError(state.stockEntriesError!);
      }
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasExtraFilters =>
      (_company ?? '').isNotEmpty ||
      (_fromWarehouse ?? '').isNotEmpty ||
      (_toWarehouse ?? '').isNotEmpty ||
      _stockEntryType != widget.kind.name;

  Future<void> _openFilters() async {
    final state = context.read<WarehouseStockState>();
    if (state.stockEntryTypes.isEmpty) {
      await state.fetchStockEntryTypes();
    }
    if (state.warehouses.isEmpty) {
      await state.refreshWarehouses();
    }
    if (!mounted) return;
    final result = await showModalBottomSheet<_StockEntryListFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return ChangeNotifierProvider.value(
          value: state,
          child: _StockEntryFilterSheet(
            initial: _StockEntryListFilters(
              stockEntryType: _stockEntryType,
              company: _company,
              fromWarehouse: _fromWarehouse,
              toWarehouse: _toWarehouse,
            ),
            defaultType: widget.kind.name,
          ),
        );
      },
    );
    if (result == null || !mounted) return;
    setState(() {
      _stockEntryType = result.stockEntryType;
      _company = result.company;
      _fromWarehouse = result.fromWarehouse;
      _toWarehouse = result.toWarehouse;
    });
    await _load();
  }

  Future<void> _create() async {
    final state = context.read<WarehouseStockState>();
    final matched = state.stockEntryTypes.where(
      (type) => type.name == _stockEntryType,
    );
    final purpose = matched.isEmpty ? widget.kind.purpose : matched.first.purpose;
    final kind = StockEntryKind(name: _stockEntryType, purpose: purpose);
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CreateStockEntryScreen(kind: kind)),
    );
    if (created == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WarehouseStockState>();
    final entries = state.stockEntries;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _stockEntryType,
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: _create,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text('Create $_stockEntryType'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: warehousePagePaddingOf(context),
          children: [
            WarehouseSectionHeader(
              title: 'Stock Entry',
              subtitle: [
                _stockEntryType,
                if ((_company ?? '').isNotEmpty) _company!,
              ].join(' · '),
              icon: widget.kind.icon,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: WarehouseSearchField(
                    controller: _search,
                    hintText: 'Cari ID Stock Entry',
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Filter',
                  onPressed: _openFilters,
                  style: IconButton.styleFrom(
                    backgroundColor: _hasExtraFilters
                        ? AppColors.primary
                        : AppColors.white,
                    foregroundColor: _hasExtraFilters
                        ? AppColors.white
                        : AppColors.navy,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size(48, 48),
                  ),
                  icon: Icon(
                    _hasExtraFilters
                        ? Icons.filter_alt_rounded
                        : Icons.filter_alt_outlined,
                  ),
                ),
              ],
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
            if (entries.isEmpty && !_loading)
              ErpEmptyState(
                title: 'Belum ada $_stockEntryType',
                message:
                    'Tidak ada dokumen untuk filter ini. Ubah company/gudang atau buat Stock Entry baru.',
              )
            else
              ...entries.map(_stockEntryCard),
          ],
        ),
      ),
    );
  }

  Widget _stockEntryCard(StockEntry row) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: WarehouseModernCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: widget.kind.color.withValues(alpha: 0.12),
            foregroundColor: widget.kind.color,
            child: Icon(widget.kind.icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.id,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    row.stockEntryType,
                    if (row.company.isNotEmpty) row.company,
                    row.date,
                    _warehouseRoute(row),
                  ].where((part) => part.trim().isNotEmpty).join('\n'),
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ErpStatusBadge(statusText: row.statusText),
        ],
      ),
    ),
  );

  String _warehouseRoute(StockEntry row) {
    if (row.fromWarehouse.isNotEmpty && row.toWarehouse.isNotEmpty) {
      return '${row.fromWarehouse} → ${row.toWarehouse}';
    }
    if (row.fromWarehouse.isNotEmpty) return 'Dari ${row.fromWarehouse}';
    if (row.toWarehouse.isNotEmpty) return 'Ke ${row.toWarehouse}';
    return '';
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _StockEntryListFilters {
  final String stockEntryType;
  final String? company;
  final String? fromWarehouse;
  final String? toWarehouse;

  const _StockEntryListFilters({
    required this.stockEntryType,
    this.company,
    this.fromWarehouse,
    this.toWarehouse,
  });
}

class _StockEntryFilterSheet extends StatefulWidget {
  final _StockEntryListFilters initial;
  final String defaultType;

  const _StockEntryFilterSheet({
    required this.initial,
    required this.defaultType,
  });

  @override
  State<_StockEntryFilterSheet> createState() => _StockEntryFilterSheetState();
}

class _StockEntryFilterSheetState extends State<_StockEntryFilterSheet> {
  late String _stockEntryType;
  String? _company;
  String? _fromWarehouse;
  String? _toWarehouse;

  @override
  void initState() {
    super.initState();
    _stockEntryType = widget.initial.stockEntryType;
    _company = widget.initial.company;
    _fromWarehouse = widget.initial.fromWarehouse;
    _toWarehouse = widget.initial.toWarehouse;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WarehouseStockState>();
    final types = state.stockEntryTypes;
    final companies = state.stockCompanies.map((entry) => entry.key).toList();
    final warehouses = _warehousesForCompany(state.warehouses, _company);

    return SafeArea(
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
                'Filter Stock Entry',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sama seperti filter list ERPNext: type, company, gudang.',
                style: TextStyle(
                  color: AppColors.slate,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              _dropdown<String>(
                label: 'Stock Entry Type',
                value: types.any((type) => type.name == _stockEntryType)
                    ? _stockEntryType
                    : (types.isEmpty ? _stockEntryType : types.first.name),
                items: [
                  for (final type in types)
                    DropdownMenuItem(value: type.name, child: Text(type.name)),
                  if (_stockEntryType.isNotEmpty &&
                      types.every((type) => type.name != _stockEntryType))
                    DropdownMenuItem(
                      value: _stockEntryType,
                      child: Text(_stockEntryType),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _stockEntryType = value);
                },
              ),
              const SizedBox(height: 12),
              _dropdown<String?>(
                label: 'Company',
                value: (_company ?? '').isEmpty
                    ? null
                    : (companies.contains(_company) ? _company : _company),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua company akses'),
                  ),
                  for (final company in companies)
                    DropdownMenuItem<String?>(
                      value: company,
                      child: Text(company),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _company = value;
                  _fromWarehouse = null;
                  _toWarehouse = null;
                }),
              ),
              const SizedBox(height: 12),
              _dropdown<String?>(
                label: 'Default Source Warehouse',
                value: _fromWarehouse,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua gudang asal'),
                  ),
                  for (final warehouse in warehouses)
                    DropdownMenuItem<String?>(
                      value: warehouse.name,
                      child: Text(warehouse.displayName),
                    ),
                ],
                onChanged: (value) => setState(() => _fromWarehouse = value),
              ),
              const SizedBox(height: 12),
              _dropdown<String?>(
                label: 'Default Target Warehouse',
                value: _toWarehouse,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua gudang tujuan'),
                  ),
                  for (final warehouse in warehouses)
                    DropdownMenuItem<String?>(
                      value: warehouse.name,
                      child: Text(warehouse.displayName),
                    ),
                ],
                onChanged: (value) => setState(() => _toWarehouse = value),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        final preferred = state.preferredCompany(companies);
                        setState(() {
                          _stockEntryType = widget.defaultType;
                          _company = preferred;
                          _fromWarehouse = null;
                          _toWarehouse = null;
                        });
                      },
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        _StockEntryListFilters(
                          stockEntryType: _stockEntryType,
                          company: _company,
                          fromWarehouse: _fromWarehouse,
                          toWarehouse: _toWarehouse,
                        ),
                      ),
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

  List<WarehouseInfo> _warehousesForCompany(
    List<WarehouseInfo> warehouses,
    String? company,
  ) {
    final selected = company?.trim() ?? '';
    return warehouses
        .where((row) => !row.isGroup && row.isDisabled != true)
        .where((row) => selected.isEmpty || row.company == selected)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: items.any((item) => item.value == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}
