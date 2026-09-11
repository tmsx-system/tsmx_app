import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/stock_ledger_movement.dart';
import '../../../state/warehouse/warehouse_dead_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../shared/warehouse_widgets.dart';

enum _MovementFilter { all, fast, slow }

class WarehouseFastSlowMovingView extends StatefulWidget {
  const WarehouseFastSlowMovingView({super.key});

  @override
  State<WarehouseFastSlowMovingView> createState() =>
      _WarehouseFastSlowMovingViewState();
}

class _WarehouseFastSlowMovingViewState
    extends State<WarehouseFastSlowMovingView> {
  static const int _visiblePageSize = 50;

  final _search = TextEditingController();
  List<StockMovementVelocityItem> _rows = const [];
  _MovementFilter _filter = _MovementFilter.all;
  String? _warehouse;
  int _periodDays = 30;
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
      _rows = await context
          .read<WarehouseDeadStockState>()
          .fetchStockMovementVelocity(
            periodDays: _periodDays,
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
    final movingRows = _rows.where((row) => row.outgoingQuantity > 0).length;
    final idleRows = _rows.length - movingRows;
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
            const WarehouseSectionHeader(
              title: 'Fast & Slow Moving',
              subtitle: 'Analisis pergerakan barang keluar per gudang',
              icon: Icons.speed_rounded,
            ),
            warehouseSectionGap,
            Row(
              children: [
                Expanded(child: _metric('Stok bergerak', '$movingRows')),
                const SizedBox(width: 10),
                Expanded(child: _metric('Belum bergerak', '$idleRows')),
              ],
            ),
            const SizedBox(height: 10),
            const WarehouseInfoPanel(
              icon: Icons.info_outline_rounded,
              message:
                  'Fast moving memiliki qty keluar minimal sebesar rata-rata. Slow moving berada di bawah rata-rata, termasuk yang belum bergerak.',
            ),
            warehouseSectionGap,
            WarehouseSearchField(
              controller: _search,
              hintText: 'Cari item atau kode',
            ),
            const SizedBox(height: 10),
            _FastSlowFilterBar(
              warehouse: _warehouse,
              periodDays: _periodDays,
              onTap: () => _openFilterSheet(warehouses),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('Semua', _MovementFilter.all),
                  _chip('Fast moving', _MovementFilter.fast),
                  _chip('Slow moving', _MovementFilter.slow),
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
              title: 'Peringkat Pergerakan',
              subtitle: _rowsSubtitle(visibleRows.length, rows.length),
              icon: Icons.format_list_numbered_rounded,
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty && !_loading)
              const ErpEmptyState(
                title: 'Data pergerakan tidak ditemukan',
                message: 'Ubah filter atau tarik ke bawah untuk refresh.',
              )
            else
              ...visibleRows.asMap().entries.map(
                (entry) => _movementCard(entry.key + 1, entry.value),
              ),
          ],
        ),
      ),
    );
  }

  String _rowsSubtitle(int visible, int total) {
    if (visible >= total) return '$total baris stok ditampilkan';
    return '$visible dari $total baris stok ditampilkan';
  }

  Widget _chip(String label, _MovementFilter value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() {
        _filter = value;
        _visibleLimit = _visiblePageSize;
      }),
    ),
  );

  Future<void> _openFilterSheet(List<String> warehouses) async {
    final result = await showModalBottomSheet<_FastSlowFilterValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FastSlowFilterSheet(
        warehouses: warehouses,
        selectedWarehouse: _warehouse,
        selectedPeriodDays: _periodDays,
      ),
    );
    if (result == null) return;
    final shouldReload = result.periodDays != _periodDays;
    setState(() {
      _warehouse = result.warehouse;
      _periodDays = result.periodDays;
      _visibleLimit = _visiblePageSize;
    });
    if (shouldReload) _load();
  }

  List<StockMovementVelocityItem> _filteredRows() {
    final query = _search.text.trim().toLowerCase();
    final averageOutgoing = _rows.isEmpty
        ? 0.0
        : _rows.fold<double>(0, (sum, row) => sum + row.outgoingQuantity) /
              _rows.length;
    final rows = _rows.where((row) {
      final matchesMovement = switch (_filter) {
        _MovementFilter.fast =>
          row.outgoingQuantity > 0 && row.outgoingQuantity >= averageOutgoing,
        _MovementFilter.slow =>
          row.outgoingQuantity == 0 || row.outgoingQuantity < averageOutgoing,
        _ => true,
      };
      return matchesMovement &&
          (_warehouse == null || row.warehouse == _warehouse) &&
          (query.isEmpty ||
              row.itemCode.toLowerCase().contains(query) ||
              row.itemName.toLowerCase().contains(query));
    }).toList();
    rows.sort((a, b) {
      if (_filter == _MovementFilter.slow) {
        return a.outgoingQuantity.compareTo(b.outgoingQuantity);
      }
      return b.outgoingQuantity.compareTo(a.outgoingQuantity);
    });
    return rows;
  }

  Widget _movementCard(int rank, StockMovementVelocityItem row) => Padding(
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
              color: _movementColor(row).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              '#$rank',
              style: TextStyle(
                color: _movementColor(row),
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
                  'Keluar ${_formatQty(row.outgoingQuantity)} | ${row.transactionCount} transaksi | Stok ${row.currentQuantity}',
                  style: TextStyle(
                    color: _movementColor(row),
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

  Color _movementColor(StockMovementVelocityItem row) =>
      row.outgoingQuantity > 0 ? AppColors.success : AppColors.warning;

  String _formatQty(double value) => value == value.roundToDouble()
      ? '${value.toInt()}'
      : value.toStringAsFixed(2);

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _FastSlowFilterValue {
  const _FastSlowFilterValue({
    required this.warehouse,
    required this.periodDays,
  });

  final String? warehouse;
  final int periodDays;
}

class _FastSlowFilterBar extends StatelessWidget {
  const _FastSlowFilterBar({
    required this.warehouse,
    required this.periodDays,
    required this.onTap,
  });

  final String? warehouse;
  final int periodDays;
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
                '${warehouse ?? 'Semua gudang'} | $periodDays hari',
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
                'Filter gudang dan periode analisis',
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

class _FastSlowFilterSheet extends StatefulWidget {
  const _FastSlowFilterSheet({
    required this.warehouses,
    required this.selectedWarehouse,
    required this.selectedPeriodDays,
  });

  final List<String> warehouses;
  final String? selectedWarehouse;
  final int selectedPeriodDays;

  @override
  State<_FastSlowFilterSheet> createState() => _FastSlowFilterSheetState();
}

class _FastSlowFilterSheetState extends State<_FastSlowFilterSheet> {
  final _search = TextEditingController();
  late String? _warehouse = widget.selectedWarehouse;
  late int _periodDays = widget.selectedPeriodDays;
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
                    'Filter Pergerakan',
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
              initialValue: _periodDays,
              decoration: InputDecoration(
                labelText: 'Periode analisis',
                prefixIcon: const Icon(Icons.date_range_outlined),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 30, child: Text('30 hari terakhir')),
                DropdownMenuItem(value: 90, child: Text('90 hari terakhir')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _periodDays = value);
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
                  _FastSlowWarehouseTile(
                    title: 'Semua gudang',
                    selected: _warehouse == null,
                    onTap: () => setState(() => _warehouse = null),
                  ),
                  ...rows.map(
                    (warehouse) => _FastSlowWarehouseTile(
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
                _FastSlowFilterValue(
                  warehouse: _warehouse,
                  periodDays: _periodDays,
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

class _FastSlowWarehouseTile extends StatelessWidget {
  const _FastSlowWarehouseTile({
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
