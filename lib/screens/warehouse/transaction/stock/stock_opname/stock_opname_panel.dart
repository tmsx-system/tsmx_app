import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../models/stock_opname.dart';
import '../../../../../state/warehouse/stock_opname_state.dart';
import '../../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../../theme/app_colors.dart';
import '../../../../../utils/erp_error_message.dart';
import '../../../../../widgets/erp/erp_empty_state.dart';
import '../../../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../../../widgets/erp/erp_status_badge.dart';
import '../../../../../widgets/erp/erp_workflow_helper.dart';
import '../../../shared/warehouse_widgets.dart';
import 'create_stock_opname_screen.dart';
import 'stock_opname_detail_screen.dart';

class StockOpnamePanel extends StatefulWidget {
  const StockOpnamePanel({super.key});

  @override
  State<StockOpnamePanel> createState() => _StockOpnamePanelState();
}

class _StockOpnamePanelState extends State<StockOpnamePanel> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  bool _canCreate = false;
  bool _canWrite = false;
  bool _canSubmit = false;
  bool _opening = false;
  bool _actionBusy = false;
  String? _error;
  String? _company;
  List<StockOpnameSummary> _rows = const [];

  StockOpnameState get _api =>
      StockOpnameState(context.read<WarehouseStockState>().appState);

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
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _bootstrap() async {
    final stock = context.read<WarehouseStockState>();
    if (stock.warehouses.isEmpty) {
      await stock.ensureWarehousesLoaded();
    }
    if (!mounted) return;
    _company ??= stock.preferredCompany(
      stock.stockCompanies.map((entry) => entry.key),
    );
    final access = await Future.wait([
      _api.canCreate(),
      _api.canWrite(),
      _api.canSubmit(),
    ]);
    if (!mounted) return;
    _canCreate = access[0];
    _canWrite = access[1];
    _canSubmit = access[2];
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _api.fetchList(company: _company, name: _search.text);
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateStockOpnameScreen(company: _company),
      ),
    );
    if (created == true && mounted) await _load();
  }

  Future<void> _edit(StockOpnameSummary row) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateStockOpnameScreen(existingName: row.id),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _submit(StockOpnameSummary row) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final doc = await _api.fetchDetail(row.id);
      final blocked = stockOpnameSubmitError(_api.linesOf(doc));
      if (!mounted) return;
      if (blocked != null) {
        setState(() => _error = blocked);
        return;
      }
      final ok = await confirmErpAction(
        context,
        title: 'Submit Stock Opname',
        message: 'Submit ${row.id}?',
      );
      if (ok != true || !mounted) return;
      await _api.submit(row.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${row.id} berhasil di-submit.')),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _open(StockOpnameSummary row) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => StockOpnameDetailScreen(name: row.id),
        ),
      );
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final companies = context
        .watch<WarehouseStockState>()
        .stockCompanies
        .map((entry) => ErpItemOption(id: entry.key, label: entry.value))
        .toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Stock Opname',
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
              label: const Text('Buat Opname'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: warehousePagePaddingOf(context),
          children: [
            ErpItemAutocompleteField(
              label: 'Company',
              selectedId: _company,
              options: companies,
              decoration: const InputDecoration(
                labelText: 'Company',
                prefixIcon: Icon(Icons.apartment_rounded),
              ),
              onSelected: (value) {
                setState(() => _company = value);
                unawaited(_load());
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Cari nomor',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              )
            else if (_rows.isEmpty)
              const ErpEmptyState(
                icon: Icons.fact_check_outlined,
                title: 'Belum ada Stock Opname',
                message: 'Buat opname baru untuk menghitung stock fisik.',
              )
            else
              for (final row in _rows) _card(row),
          ],
        ),
      ),
    );
  }

  void _onMenu(StockOpnameSummary row, String action) {
    switch (action) {
      case 'detail':
        unawaited(_open(row));
        break;
      case 'edit':
        unawaited(_edit(row));
        break;
      case 'submit':
        unawaited(_submit(row));
        break;
    }
  }

  Widget _card(StockOpnameSummary row) {
    final draft = row.docstatus == 0;
    final canEdit = draft && _canWrite;
    final canSubmit = draft && _canSubmit;
    final when = [
      row.postingDate,
      row.postingTime,
    ].where((part) => part.trim().isNotEmpty).join(' ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _opening ? null : () => unawaited(_open(row)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFDCFCE7),
                  foregroundColor: Color(0xFF15803D),
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
                          if (row.warehouse.isNotEmpty) row.warehouse,
                          if (row.itemGroup.isNotEmpty) row.itemGroup,
                          if (when.isNotEmpty) when,
                          if (row.statusPenyelesaian.trim().isNotEmpty)
                            row.statusPenyelesaian,
                        ].join('\n'),
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
                Column(
                  children: [
                    ErpStatusBadge(statusText: row.docStatusLabel),
                    PopupMenuButton<String>(
                      tooltip: 'Aksi',
                      enabled: !_actionBusy && !_opening,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: AppColors.white,
                      onSelected: (value) => _onMenu(row, value),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'detail',
                          child: Row(
                            children: [
                              Icon(Icons.visibility_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Lihat Detail'),
                            ],
                          ),
                        ),
                        if (canEdit)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                        if (canSubmit)
                          const PopupMenuItem(
                            value: 'submit',
                            child: Row(
                              children: [
                                Icon(Icons.verified_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Submit'),
                              ],
                            ),
                          ),
                      ],
                      icon: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.more_vert_rounded,
                          color: AppColors.slate,
                          size: 19,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
