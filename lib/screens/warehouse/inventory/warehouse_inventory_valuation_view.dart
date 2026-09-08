import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/inventory_item.dart';
import '../../../state/warehouse/warehouse_valuation_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../shared/warehouse_widgets.dart';

enum _ValuationSort { highestValue, lowestValue, highestQty, itemName }

class WarehouseInventoryValuationView extends StatefulWidget {
  const WarehouseInventoryValuationView({super.key});

  @override
  State<WarehouseInventoryValuationView> createState() =>
      _WarehouseInventoryValuationViewState();
}

class _WarehouseInventoryValuationViewState
    extends State<WarehouseInventoryValuationView> {
  final _search = TextEditingController();
  String? _warehouse;
  _ValuationSort _sort = _ValuationSort.highestValue;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<WarehouseValuationState>().refreshInventory();
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WarehouseValuationState>();
    final rows = _filteredRows(state.inventory);
    final warehouses =
        state.warehouses
            .where((row) => !row.isGroup && row.isDisabled != true)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: warehousePagePaddingOf(context),
        children: [
          WarehouseSearchField(
            controller: _search,
            hintText: 'Cari item atau kode',
          ),
          const SizedBox(height: 10),
          _buildFilterBar(warehouses.map((row) => row.name).toList()),
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
            title: 'Nilai per Item',
            subtitle: '${rows.length} baris stok ditampilkan',
            icon: Icons.list_alt_rounded,
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty && !_loading)
            const ErpEmptyState(
              title: 'Data valuasi tidak ditemukan',
              message: 'Ubah filter atau tarik ke bawah untuk refresh.',
            )
          else
            ...rows.map(_valuationCard),
        ],
      ),
    );
  }

  List<InventoryItem> _filteredRows(List<InventoryItem> inventory) {
    final query = _search.text.trim().toLowerCase();
    final rows = inventory.where((row) {
      return (_warehouse == null || row.warehouseId == _warehouse) &&
          (query.isEmpty ||
              row.sku.toLowerCase().contains(query) ||
              row.name.toLowerCase().contains(query));
    }).toList();
    rows.sort(switch (_sort) {
      _ValuationSort.highestValue => (a, b) => _value(b).compareTo(_value(a)),
      _ValuationSort.lowestValue => (a, b) => _value(a).compareTo(_value(b)),
      _ValuationSort.highestQty => (a, b) => b.quantity.compareTo(a.quantity),
      _ValuationSort.itemName => (a, b) => a.name.compareTo(b.name),
    });
    return rows;
  }

  double _value(InventoryItem row) => row.quantity * row.unitValue;

  Widget _buildFilterBar(List<String> warehouses) {
    final warehouseLabel = _warehouse ?? 'Semua gudang';
    return Container(
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
              Icons.filter_alt_outlined,
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
                  '$warehouseLabel | ${_sortLabel(_sort)}',
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
                  'Filter gudang dan urutan data valuasi',
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
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => _openFilterSheet(warehouses),
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

  Future<void> _openFilterSheet(List<String> warehouses) async {
    final result = await showModalBottomSheet<_ValuationFilterValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ValuationFilterSheet(
        warehouses: warehouses,
        selectedWarehouse: _warehouse,
        selectedSort: _sort,
      ),
    );
    if (result == null) return;
    setState(() {
      _warehouse = result.warehouse;
      _sort = result.sort;
    });
  }

  String _sortLabel(_ValuationSort sort) {
    return switch (sort) {
      _ValuationSort.highestValue => 'Nilai tertinggi',
      _ValuationSort.lowestValue => 'Nilai terendah',
      _ValuationSort.highestQty => 'Qty tertinggi',
      _ValuationSort.itemName => 'Nama item',
    };
  }

  Widget _valuationCard(InventoryItem row) => Padding(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'Rp ${formatErpCurrency(_value(row))}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${row.sku} | ${row.warehouseId}',
            style: const TextStyle(color: AppColors.slate, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _smallMetric('Qty', '${row.quantity}')),
              const SizedBox(width: 8),
              Expanded(
                child: _smallMetric(
                  'Harga/Unit',
                  'Rp ${formatErpCurrency(row.unitValue)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _smallMetric(
                  'Nilai',
                  'Rp ${formatErpCurrency(_value(row))}',
                ),
              ),
            ],
          ),
          if (row.unitValue <= 0) ...[
            const SizedBox(height: 8),
            const Text(
              'Harga item belum tersedia.',
              style: TextStyle(
                color: AppColors.danger,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _smallMetric(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.slate, fontSize: 9),
        ),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
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

class _ValuationFilterValue {
  const _ValuationFilterValue({required this.warehouse, required this.sort});

  final String? warehouse;
  final _ValuationSort sort;
}

class _ValuationFilterSheet extends StatefulWidget {
  const _ValuationFilterSheet({
    required this.warehouses,
    required this.selectedWarehouse,
    required this.selectedSort,
  });

  final List<String> warehouses;
  final String? selectedWarehouse;
  final _ValuationSort selectedSort;

  @override
  State<_ValuationFilterSheet> createState() => _ValuationFilterSheetState();
}

class _ValuationFilterSheetState extends State<_ValuationFilterSheet> {
  final TextEditingController _warehouseSearch = TextEditingController();
  late String? _warehouse = widget.selectedWarehouse;
  late _ValuationSort _sort = widget.selectedSort;
  String _query = '';

  @override
  void dispose() {
    _warehouseSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filteredWarehouses = query.isEmpty
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
                    'Filter Valuasi',
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
            DropdownButtonFormField<_ValuationSort>(
              initialValue: _sort,
              isExpanded: true,
              decoration: _sheetInputDecoration(
                label: 'Urutkan',
                icon: Icons.sort_rounded,
              ),
              items: _ValuationSort.values
                  .map(
                    (sort) => DropdownMenuItem<_ValuationSort>(
                      value: sort,
                      child: Text(_sortLabel(sort)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _sort = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _warehouseSearch,
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
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _warehouseSearch.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filteredWarehouses.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _WarehouseFilterTile(
                      title: 'Semua gudang',
                      selected: _warehouse == null,
                      onTap: () => setState(() => _warehouse = null),
                    );
                  }
                  final warehouse = filteredWarehouses[index - 1];
                  return _WarehouseFilterTile(
                    title: warehouse,
                    selected: _warehouse == warehouse,
                    onTap: () => setState(() => _warehouse = warehouse),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _warehouse = null;
                      _sort = _ValuationSort.highestValue;
                    }),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(
                      _ValuationFilterValue(warehouse: _warehouse, sort: _sort),
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
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _sortLabel(_ValuationSort sort) {
    return switch (sort) {
      _ValuationSort.highestValue => 'Nilai tertinggi',
      _ValuationSort.lowestValue => 'Nilai terendah',
      _ValuationSort.highestQty => 'Qty tertinggi',
      _ValuationSort.itemName => 'Nama item',
    };
  }

  InputDecoration _sheetInputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _WarehouseFilterTile extends StatelessWidget {
  const _WarehouseFilterTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
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
}
