import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/stock_ledger_movement.dart';
import '../../../state/warehouse/warehouse_dead_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../shared/warehouse_widgets.dart';

class WarehouseDeadStockView extends StatefulWidget {
  const WarehouseDeadStockView({super.key});

  @override
  State<WarehouseDeadStockView> createState() => _WarehouseDeadStockViewState();
}

class _WarehouseDeadStockViewState extends State<WarehouseDeadStockView> {
  final _search = TextEditingController();
  List<DeadStockItem> _rows = const [];
  int _threshold = 90;
  String? _warehouse;
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
      _rows = await context.read<WarehouseDeadStockState>().fetchDeadStock(
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
    final totalValue = rows.fold<double>(0, (sum, row) => sum + row.stockValue);
    final totalQty = rows.fold<int>(0, (sum, row) => sum + row.quantity);
    final warehouses = _rows.map((row) => row.warehouse).toSet().toList()
      ..sort();
    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: warehousePagePaddingOf(context),
        children: [
          Row(
            children: [
              Expanded(child: _metric('Item dead stock', '${rows.length}')),
              const SizedBox(width: 10),
              Expanded(child: _metric('Total qty', '$totalQty')),
            ],
          ),
          const SizedBox(height: 10),
          WarehouseInfoPanel(
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.warning,
            message:
                'Nilai modal tertahan: Rp ${formatErpCurrency(totalValue)}. Pergerakan diperiksa maksimal 365 hari terakhir.',
          ),
          warehouseSectionGap,
          WarehouseSearchField(
            controller: _search,
            hintText: 'Cari item atau kode',
          ),
          const SizedBox(height: 10),
          _DeadStockFilterBar(
            warehouse: _warehouse,
            threshold: _threshold,
            onTap: () => _openFilterSheet(warehouses),
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          warehouseSectionGap,
          WarehouseSectionHeader(
            title: 'Daftar Dead Stock',
            subtitle: '${rows.length} baris stok ditampilkan',
            icon: Icons.list_alt_rounded,
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty && !_loading)
            const ErpEmptyState(
              title: 'Dead stock tidak ditemukan',
              message: 'Ubah batas hari, filter gudang, atau pencarian.',
            )
          else
            ...rows.map(_deadStockCard),
        ],
      ),
    );
  }

  List<DeadStockItem> _filteredRows() {
    final query = _search.text.trim().toLowerCase();
    return _rows.where((row) {
      final meetsThreshold = _threshold == 365
          ? row.inactiveDays > 365
          : row.inactiveDays >= _threshold;
      return meetsThreshold &&
          (_warehouse == null || row.warehouse == _warehouse) &&
          (query.isEmpty ||
              row.itemCode.toLowerCase().contains(query) ||
              row.itemName.toLowerCase().contains(query));
    }).toList()..sort((a, b) {
      final age = b.inactiveDays.compareTo(a.inactiveDays);
      return age != 0 ? age : b.stockValue.compareTo(a.stockValue);
    });
  }

  Future<void> _openFilterSheet(List<String> warehouses) async {
    final result = await showModalBottomSheet<_DeadStockFilterValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeadStockFilterSheet(
        warehouses: warehouses,
        selectedWarehouse: _warehouse,
        selectedThreshold: _threshold,
      ),
    );
    if (result == null) return;
    setState(() {
      _warehouse = result.warehouse;
      _threshold = result.threshold;
    });
  }

  Widget _deadStockCard(DeadStockItem row) => Padding(
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
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              row.inactiveDays > 365 ? '>365' : '${row.inactiveDays}',
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.itemName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${row.itemCode} | ${row.warehouse}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.slate, fontSize: 11),
                ),
                const SizedBox(height: 5),
                Text(
                  'Qty ${row.quantity} | Rp ${formatErpCurrency(row.stockValue)}',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
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

class _DeadStockFilterValue {
  const _DeadStockFilterValue({
    required this.warehouse,
    required this.threshold,
  });

  final String? warehouse;
  final int threshold;
}

class _DeadStockFilterBar extends StatelessWidget {
  const _DeadStockFilterBar({
    required this.warehouse,
    required this.threshold,
    required this.onTap,
  });

  final String? warehouse;
  final int threshold;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      boxShadow: AppColors.cardShadow,
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.tune_rounded,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${warehouse ?? 'Semua gudang'} | ${_thresholdLabel(threshold)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Filter gudang dan batas tanpa pergerakan',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.slate,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.softGreen,
            foregroundColor: AppColors.primary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.tune_rounded, size: 15),
          label: const Text(
            'Filter',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    ),
  );
}

class _DeadStockFilterSheet extends StatefulWidget {
  const _DeadStockFilterSheet({
    required this.warehouses,
    required this.selectedWarehouse,
    required this.selectedThreshold,
  });

  final List<String> warehouses;
  final String? selectedWarehouse;
  final int selectedThreshold;

  @override
  State<_DeadStockFilterSheet> createState() => _DeadStockFilterSheetState();
}

class _DeadStockFilterSheetState extends State<_DeadStockFilterSheet> {
  final _search = TextEditingController();
  late String? _warehouse = widget.selectedWarehouse;
  late int _threshold = widget.selectedThreshold;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final rows = query.isEmpty
        ? widget.warehouses
        : widget.warehouses
              .where((warehouse) => warehouse.toLowerCase().contains(query))
              .toList(growable: false);
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Filter Dead Stock',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _threshold,
              decoration: InputDecoration(
                labelText: 'Batas tanpa pergerakan',
                prefixIcon: const Icon(Icons.hourglass_empty_rounded),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 90, child: Text('Minimal 90 hari')),
                DropdownMenuItem(value: 180, child: Text('Minimal 180 hari')),
                DropdownMenuItem(
                  value: 365,
                  child: Text('Lebih dari 365 hari'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _threshold = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Cari gudang...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _DeadStockWarehouseTile(
                    title: 'Semua gudang',
                    selected: _warehouse == null,
                    onTap: () => setState(() => _warehouse = null),
                  ),
                  ...rows.map(
                    (warehouse) => _DeadStockWarehouseTile(
                      title: warehouse,
                      selected: _warehouse == warehouse,
                      onTap: () => setState(() => _warehouse = warehouse),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                _DeadStockFilterValue(
                  warehouse: _warehouse,
                  threshold: _threshold,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text('Terapkan Filter'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeadStockWarehouseTile extends StatelessWidget {
  const _DeadStockWarehouseTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.softGreen : Colors.transparent,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primary : AppColors.slate,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _thresholdLabel(int threshold) {
  return threshold == 365 ? '>365 hari' : 'Minimal $threshold hari';
}
