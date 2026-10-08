import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../models/stock_entry.dart';
import '../../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../../theme/app_colors.dart';
import '../../../../../widgets/erp/erp_document_card.dart';
import '../../../../../widgets/erp/erp_empty_state.dart';
import '../../../../../utils/erp_error_message.dart';
import '../../../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../shared/warehouse_widgets.dart';
import 'create_stock_reconciliation_screen.dart';
import 'stock_reconciliation_detail_screen.dart';

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
  bool _isOpeningDetail = false;

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
      if (!mounted) return;
      _error = captureErpError(context, error);
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
        preferredCompany: state.preferredCompany(companies),
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

  Future<void> _openDetail(StockReconciliationSummary row) async {
    if (_isOpeningDetail) return;
    _isOpeningDetail = true;
    setState(() {});
    try {
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              StockReconciliationDetailScreen(reconciliationId: row.id),
        ),
      );
      if (mounted) await _load();
    } finally {
      _isOpeningDetail = false;
      if (mounted) setState(() {});
    }
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
              label: const Text('Create Reconciliation'),
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
                'Penyesuaian stok fisik vs sistem',
                if ((_company ?? '').isNotEmpty) _company!,
                '${rows.length} dokumen',
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
    final dateLabel = [
      if (row.date.isNotEmpty) row.date,
      if (row.postingTime.isNotEmpty) row.postingTime,
    ].join(' · ');
    final extras = [
      if (row.expenseAccount.isNotEmpty) row.expenseAccount,
      if (row.costCenter.isNotEmpty) row.costCenter,
    ].join(' · ');
    return ErpDocumentCard(
      id: row.id,
      party: row.company.isEmpty ? 'Stock Reconciliation' : row.company,
      statusText: row.statusText,
      date: dateLabel.isEmpty ? '-' : dateLabel,
      value: row.differenceAmount,
      trailing: extras.isEmpty ? null : extras,
      onTap: _isOpeningDetail ? null : () => unawaited(_openDetail(row)),
    );
  }
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
  final String? preferredCompany;

  const _RecoFilterSheet({
    required this.initial,
    required this.companies,
    this.preferredCompany,
  });

  @override
  State<_RecoFilterSheet> createState() => _RecoFilterSheetState();
}

class _RecoFilterSheetState extends State<_RecoFilterSheet> {
  late String? _company;
  String? _expenseAccount;
  String? _costCenter;

  @override
  void initState() {
    super.initState();
    _company = widget.initial.company;
    _expenseAccount = widget.initial.expenseAccount;
    _costCenter = widget.initial.costCenter;
  }

  InputDecoration _fieldDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      hintText: 'Pilih $label',
      prefixIcon: icon == null ? null : Icon(icon),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Future<List<ErpItemOption>> _fetchAccounts([String query = '']) async {
    final filters = <List<dynamic>>[
      ['is_group', '=', 0],
      if ((_company ?? '').trim().isNotEmpty) ['company', '=', _company],
    ];
    final q = query.trim();
    final orFilters = q.isEmpty
        ? null
        : [
            ['name', 'like', '%$q%'],
            ['account_name', 'like', '%$q%'],
          ];
    final rows = await context.read<WarehouseStockState>().frappeService
        .fetchResource(
          'Account',
          fields: const ['name'],
          filters: filters,
          orFilters: orFilters,
          orderBy: 'name asc',
          limit: 50,
        );
    return [
      for (final row in rows)
        if ((row['name']?.toString() ?? '').trim().isNotEmpty)
          ErpItemOption(
            id: row['name'].toString().trim(),
            label: row['name'].toString().trim(),
          ),
    ];
  }

  Future<List<ErpItemOption>> _fetchCostCenters([String query = '']) async {
    final filters = <List<dynamic>>[
      ['is_group', '=', 0],
      if ((_company ?? '').trim().isNotEmpty) ['company', '=', _company],
    ];
    final q = query.trim();
    final orFilters = q.isEmpty
        ? null
        : [
            ['name', 'like', '%$q%'],
            ['cost_center_name', 'like', '%$q%'],
          ];
    final rows = await context.read<WarehouseStockState>().frappeService
        .fetchResource(
          'Cost Center',
          fields: const ['name'],
          filters: filters,
          orFilters: orFilters,
          orderBy: 'name asc',
          limit: 50,
        );
    return [
      for (final row in rows)
        if ((row['name']?.toString() ?? '').trim().isNotEmpty)
          ErpItemOption(
            id: row['name'].toString().trim(),
            label: row['name'].toString().trim(),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
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
                'Filter Stock Reconciliation',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Saring dokumen berdasarkan company, akun selisih, dan cost center.',
                style: TextStyle(
                  color: AppColors.slate,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              ErpSearchableFilterField(
                label: 'Company',
                selectedId: _company,
                decoration: _fieldDecoration(
                  'Company',
                  icon: Icons.apartment_outlined,
                ),
                allLabel: 'Semua company akses',
                options: [
                  for (final company in widget.companies)
                    ErpItemOption(id: company, label: company),
                ],
                onSelected: (value) => setState(() {
                  _company = value;
                  _expenseAccount = null;
                  _costCenter = null;
                }),
              ),
              const SizedBox(height: 12),
              ErpItemAutocompleteField(
                key: ValueKey('filter-acc:${_company ?? ''}:${_expenseAccount ?? ''}'),
                label: 'Difference Account',
                selectedId: _expenseAccount,
                decoration: _fieldDecoration(
                  'Difference Account',
                  icon: Icons.account_balance_outlined,
                ),
                options: [
                  if ((_expenseAccount ?? '').isNotEmpty)
                    ErpItemOption(
                      id: _expenseAccount!,
                      label: _expenseAccount!,
                    ),
                ],
                onSearch: _fetchAccounts,
                onSelected: (value) => setState(() => _expenseAccount = value),
              ),
              const SizedBox(height: 12),
              ErpItemAutocompleteField(
                key: ValueKey('filter-cc:${_company ?? ''}:${_costCenter ?? ''}'),
                label: 'Cost Center',
                selectedId: _costCenter,
                decoration: _fieldDecoration(
                  'Cost Center',
                  icon: Icons.hub_outlined,
                ),
                options: [
                  if ((_costCenter ?? '').isNotEmpty)
                    ErpItemOption(id: _costCenter!, label: _costCenter!),
                ],
                onSearch: _fetchCostCenters,
                onSelected: (value) => setState(() => _costCenter = value),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _company = widget.preferredCompany;
                          _expenseAccount = null;
                          _costCenter = null;
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
                        _RecoFilters(
                          company: _company,
                          expenseAccount: (_expenseAccount ?? '').trim().isEmpty
                              ? null
                              : _expenseAccount!.trim(),
                          costCenter: (_costCenter ?? '').trim().isEmpty
                              ? null
                              : _costCenter!.trim(),
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
}
