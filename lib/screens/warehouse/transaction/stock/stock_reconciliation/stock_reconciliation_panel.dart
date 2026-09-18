import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../models/stock_entry.dart';
import '../../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../../theme/app_colors.dart';
import '../../../../../utils/erp_format.dart';
import '../../../../../widgets/erp/erp_empty_state.dart';
import '../../../../../widgets/erp/erp_status_badge.dart';
import '../../../shared/warehouse_widgets.dart';
import 'create_stock_reconciliation_screen.dart';

class StockReconciliationPanel extends StatefulWidget {
  const StockReconciliationPanel({super.key});

  @override
  State<StockReconciliationPanel> createState() =>
      _StockReconciliationPanelState();
}

class _StockReconciliationPanelState extends State<StockReconciliationPanel> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  bool _canCreate = false;
  String? _error;
  String? _company;
  String? _expenseAccount;
  String? _costCenter;

  @override
  void initState() {
    super.initState();
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
        _canCreate = await state.canCreateDoctype('Stock Reconciliation');
      }
      await state.refreshStockReconciliations(
        company: _company,
        expenseAccount: _expenseAccount,
        costCenter: _costCenter,
        name: _search.text,
      );
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasExtraFilters =>
      (_company ?? '').isNotEmpty ||
      (_expenseAccount ?? '').isNotEmpty ||
      (_costCenter ?? '').isNotEmpty;

  Future<void> _openFilters() async {
    final state = context.read<WarehouseStockState>();
    final companies = state.stockCompanies.map((entry) => entry.key).toList();
    final result = await showModalBottomSheet<_RecoFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecoFilterSheet(
        initial: _RecoFilters(
          company: _company,
          expenseAccount: _expenseAccount,
          costCenter: _costCenter,
        ),
        companies: companies,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _company = result.company;
      _expenseAccount = result.expenseAccount;
      _costCenter = result.costCenter;
    });
    await _load();
  }

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateStockReconciliationScreen(company: _company),
      ),
    );
    if (created == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rows = context.watch<WarehouseStockState>().stockReconciliations;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Stock Reconciliation',
          style: TextStyle(
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
              label: const Text('Create'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: warehousePagePaddingOf(context),
          children: [
            WarehouseSectionHeader(
              title: 'Stock Reconciliation',
              subtitle: [
                if ((_company ?? '').isNotEmpty) _company!,
                'ERPNext 15',
              ].join(' · '),
              icon: Icons.fact_check_outlined,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: WarehouseSearchField(
                    controller: _search,
                    hintText: 'Cari ID Stock Reconciliation',
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
            if (rows.isEmpty && !_loading)
              const ErpEmptyState(
                title: 'Belum ada Stock Reconciliation',
                message: 'Ubah filter company atau buat dokumen baru.',
              )
            else
              ...rows.map(_card),
          ],
        ),
      ),
    );
  }

  Widget _card(StockReconciliationSummary row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WarehouseModernCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFF3E8FF),
              foregroundColor: warehousePurple,
              child: Icon(Icons.fact_check_outlined),
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
                      if (row.company.isNotEmpty) row.company,
                      if (row.date.isNotEmpty) row.date,
                      if (row.postingTime.isNotEmpty) row.postingTime,
                      'Diff Rp ${formatErpCurrency(row.differenceAmount)}',
                    ].join(' · '),
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            ErpStatusBadge(statusText: row.statusText),
          ],
        ),
      ),
    );
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _RecoFilters {
  final String? company;
  final String? expenseAccount;
  final String? costCenter;

  const _RecoFilters({this.company, this.expenseAccount, this.costCenter});
}

class _RecoFilterSheet extends StatefulWidget {
  final _RecoFilters initial;
  final List<String> companies;

  const _RecoFilterSheet({required this.initial, required this.companies});

  @override
  State<_RecoFilterSheet> createState() => _RecoFilterSheetState();
}

class _RecoFilterSheetState extends State<_RecoFilterSheet> {
  late String? _company;
  late final TextEditingController _account;
  late final TextEditingController _costCenter;

  @override
  void initState() {
    super.initState();
    _company = widget.initial.company;
    _account = TextEditingController(text: widget.initial.expenseAccount ?? '');
    _costCenter = TextEditingController(text: widget.initial.costCenter ?? '');
  }

  @override
  void dispose() {
    _account.dispose();
    _costCenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Filter Stock Reconciliation',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: widget.companies.contains(_company)
                  ? _company
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Company'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Semua company akses'),
                ),
                for (final company in widget.companies)
                  DropdownMenuItem(value: company, child: Text(company)),
              ],
              onChanged: (value) => setState(() => _company = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _account,
              decoration: const InputDecoration(labelText: 'Difference Account'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _costCenter,
              decoration: const InputDecoration(labelText: 'Cost Center'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _RecoFilters(
                  company: _company,
                  expenseAccount: _account.text.trim().isEmpty
                      ? null
                      : _account.text.trim(),
                  costCenter: _costCenter.text.trim().isEmpty
                      ? null
                      : _costCenter.text.trim(),
                ),
              ),
              child: const Text('Terapkan'),
            ),
          ],
        ),
      ),
    );
  }
}
