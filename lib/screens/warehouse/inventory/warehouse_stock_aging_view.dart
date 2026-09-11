import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/stock_ledger_movement.dart';
import '../../../state/warehouse/warehouse_aging_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../shared/warehouse_widgets.dart';

enum _AgingBucket { all, fresh, medium, old, veryOld }

class WarehouseStockAgingView extends StatefulWidget {
  const WarehouseStockAgingView({super.key});

  @override
  State<WarehouseStockAgingView> createState() =>
      _WarehouseStockAgingViewState();
}

class _WarehouseStockAgingViewState extends State<WarehouseStockAgingView> {
  static const int _visiblePageSize = 50;

  final _search = TextEditingController();
  List<StockAgingItem> _rows = const [];
  _AgingBucket _bucket = _AgingBucket.all;
  String? _warehouse;
  int _visibleLimit = _visiblePageSize;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      setState(() => _visibleLimit = _visiblePageSize);
    });
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
      _rows = await context.read<WarehouseAgingState>().fetchStockAging(
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
    final visibleRows = rows.take(_visibleLimit).toList();
    final oldCount = _rows.where((row) => row.ageDays > 90).length;
    final oldValue = _rows
        .where((row) => row.ageDays > 90)
        .fold<double>(0, (sum, row) => sum + row.stockValue);
    final warehouses = _rows.map((row) => row.warehouse).toSet().toList()
      ..sort();
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter <= 280 &&
            _visibleLimit < rows.length) {
          setState(() {
            _visibleLimit = (_visibleLimit + _visiblePageSize).clamp(
              0,
              rows.length,
            );
          });
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: warehousePagePaddingOf(context),
          children: [
            Row(
              children: [
                Expanded(child: _metric('Stok >90 hari', '$oldCount')),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric(
                    'Nilai >90 hari',
                    'Rp ${formatErpCurrency(oldValue)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const WarehouseInfoPanel(
              icon: Icons.info_outline_rounded,
              message:
                  'Umur dihitung dari penerimaan terakhir dalam 365 hari. Item tanpa penerimaan pada periode tersebut ditandai >365 hari.',
            ),
            warehouseSectionGap,
            WarehouseSearchField(
              controller: _search,
              hintText: 'Cari item atau kode',
            ),
            const SizedBox(height: 10),
            _AgingFilterBar(
              warehouse: _warehouse,
              onTap: () => _openWarehouseFilter(warehouses),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('Semua', _AgingBucket.all),
                  _chip('0-30 hari', _AgingBucket.fresh),
                  _chip('31-60 hari', _AgingBucket.medium),
                  _chip('61-90 hari', _AgingBucket.old),
                  _chip('>90 hari', _AgingBucket.veryOld),
                ],
              ),
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
              title: 'Daftar Umur Stok',
              subtitle: _rowsSubtitle(visibleRows.length, rows.length),
              icon: Icons.list_alt_rounded,
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty && !_loading)
              const ErpEmptyState(
                title: 'Data stock aging tidak ditemukan',
                message: 'Ubah filter atau tarik ke bawah untuk refresh.',
              )
            else
              ...visibleRows.map(_agingCard),
          ],
        ),
      ),
    );
  }

  String _rowsSubtitle(int visible, int total) {
    if (visible >= total) return '$total baris stok ditampilkan';
    return '$visible dari $total baris stok ditampilkan';
  }

  Widget _chip(String label, _AgingBucket value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _bucket == value,
      onSelected: (_) => setState(() {
        _bucket = value;
        _visibleLimit = _visiblePageSize;
      }),
    ),
  );

  Future<void> _openWarehouseFilter(List<String> warehouses) async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgingWarehouseFilterSheet(
        warehouses: warehouses,
        selectedWarehouse: _warehouse,
      ),
    );
    if (!mounted || result == _warehouse) return;
    setState(() {
      _warehouse = result?.isEmpty == true ? null : result;
      _visibleLimit = _visiblePageSize;
    });
  }

  List<StockAgingItem> _filteredRows() {
    final query = _search.text.trim().toLowerCase();
    final rows = _rows.where((row) {
      return (_warehouse == null || row.warehouse == _warehouse) &&
          (query.isEmpty ||
              row.itemCode.toLowerCase().contains(query) ||
              row.itemName.toLowerCase().contains(query)) &&
          _matchesBucket(row.ageDays);
    }).toList()..sort((a, b) => b.ageDays.compareTo(a.ageDays));
    return rows;
  }

  bool _matchesBucket(int days) => switch (_bucket) {
    _AgingBucket.fresh => days <= 30,
    _AgingBucket.medium => days >= 31 && days <= 60,
    _AgingBucket.old => days >= 61 && days <= 90,
    _AgingBucket.veryOld => days > 90,
    _ => true,
  };

  Widget _agingCard(StockAgingItem row) => Padding(
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
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _color(row.ageDays).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              row.ageDays > 365 ? '>365' : '${row.ageDays}',
              style: TextStyle(
                color: _color(row.ageDays),
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
                  'Qty ${row.quantity} x Rp ${formatErpCurrency(row.valuationRate)} = Rp ${formatErpCurrency(row.stockValue)}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (row.valuationRate <= 0) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Harga belum tersedia',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 15,
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

  Color _color(int days) {
    if (days > 90) return AppColors.danger;
    if (days > 60) return AppColors.warning;
    if (days > 30) return const Color(0xFFCA8A04);
    return AppColors.success;
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _AgingFilterBar extends StatelessWidget {
  const _AgingFilterBar({required this.warehouse, required this.onTap});

  final String? warehouse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              Icons.warehouse_outlined,
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
                  warehouse ?? 'Semua gudang',
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
                  'Filter gudang stock aging',
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
}

class _AgingWarehouseFilterSheet extends StatefulWidget {
  const _AgingWarehouseFilterSheet({
    required this.warehouses,
    required this.selectedWarehouse,
  });

  final List<String> warehouses;
  final String? selectedWarehouse;

  @override
  State<_AgingWarehouseFilterSheet> createState() =>
      _AgingWarehouseFilterSheetState();
}

class _AgingWarehouseFilterSheetState
    extends State<_AgingWarehouseFilterSheet> {
  final _search = TextEditingController();
  String _query = '';
  String? _warehouse;

  @override
  void initState() {
    super.initState();
    _warehouse = widget.selectedWarehouse;
  }

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
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
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
                    'Filter Gudang',
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
                  _WarehouseChoiceTile(
                    title: 'Semua gudang',
                    selected: _warehouse == null,
                    onTap: () => setState(() => _warehouse = null),
                  ),
                  ...rows.map(
                    (warehouse) => _WarehouseChoiceTile(
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
              onPressed: () => Navigator.of(context).pop(_warehouse ?? ''),
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

class _WarehouseChoiceTile extends StatelessWidget {
  const _WarehouseChoiceTile({
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
