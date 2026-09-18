import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/inventory_item.dart';
import '../../../models/warehouse_info.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../shared/warehouse_widgets.dart';

class WarehouseStockOpnameScreen extends StatefulWidget {
  const WarehouseStockOpnameScreen({super.key});

  @override
  State<WarehouseStockOpnameScreen> createState() =>
      _WarehouseStockOpnameScreenState();
}

class _WarehouseStockOpnameScreenState
    extends State<WarehouseStockOpnameScreen> {
  final _rows = <_StockOpnameRow>[];
  List<WarehouseInfo> _warehouses = const [];
  String? _warehouse;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  WarehouseInfo? get _selectedWarehouse {
    for (final row in _warehouses) {
      if (row.name == _warehouse) return row;
    }
    return null;
  }

  List<InventoryItem> get _warehouseItems {
    final warehouse = _warehouse;
    if (warehouse == null) return const [];
    final items =
        context
            .read<WarehouseStockState>()
            .inventory
            .where((item) => item.warehouseId == warehouse)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = context.read<WarehouseStockState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await state.refreshWarehouses();
      await state.refreshInventory();
      final warehouses =
          state.warehouses
              .where((row) => !row.isGroup && row.isDisabled != true)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _warehouses = warehouses;
        if (_warehouse == null && warehouses.isNotEmpty) {
          _warehouse = warehouses.first.name;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final warehouse = _selectedWarehouse;
    if (warehouse == null) {
      setState(() => _error = 'Pilih gudang yang akan dihitung.');
      return;
    }
    if (_rows.isEmpty) {
      setState(
        () => _error = 'Tambahkan minimal satu item yang sudah dihitung.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await context
          .read<WarehouseStockState>()
          .createStockReconciliation(
            company: warehouse.company,
            warehouse: warehouse.name,
            items: [
              for (final row in _rows)
                {
                  'item_code': row.item.sku,
                  'qty': row.physicalQty,
                  'valuation_rate': row.item.unitValue,
                },
            ],
          );
      if (!mounted) return;
      final id = created['name']?.toString() ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            id.isEmpty
                ? 'Draft stock opname berhasil dibuat.'
                : 'Draft stock opname $id berhasil dibuat.',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Stock Opname Mobile',
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900),
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: warehousePagePaddingOf(context),
              children: [
                _instructionPanel(),
                const SizedBox(height: 14),
                _warehouseSelector(),
                const SizedBox(height: 14),
                _summaryPanel(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Item Dihitung',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _warehouse == null ? null : _showItemPicker,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Tambah Item'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_rows.isEmpty)
                  const WarehouseModernCard(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Belum ada item dihitung. Pilih Tambah Item lalu masukkan stok fisik.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.slate),
                      ),
                    ),
                  )
                else
                  ..._rows.indexed.map(
                    (entry) => _itemCard(entry.$1, entry.$2),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _errorPanel(_error!),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _saving ? 'Menyimpan...' : 'Simpan Draft Stock Opname',
                    ),
                  ),
                ),
              ],
            ),
          ),
  );

  Widget _instructionPanel() => const WarehouseInfoPanel(
    icon: Icons.inventory_outlined,
    message:
        'Hitung stok fisik di satu gudang. Selisih dihitung otomatis dan disimpan sebagai draft untuk diperiksa.',
  );

  Widget _warehouseSelector() {
    final selected = _selectedWarehouse;
    return InkWell(
      onTap: _showWarehousePicker,
      borderRadius: BorderRadius.circular(18),
      child: WarehouseSelectTile(
        label: 'Gudang yang dihitung',
        value: selected?.name ?? 'Pilih gudang',
        subtitle: selected?.company,
        icon: Icons.warehouse_outlined,
      ),
    );
  }

  Widget _summaryPanel() {
    final totalDifference = _rows.fold<double>(
      0,
      (sum, row) => sum + row.difference,
    );
    return Row(
      children: [
        Expanded(child: _metric('Item dihitung', '${_rows.length}')),
        const SizedBox(width: 8),
        Expanded(
          child: _metric(
            'Total selisih',
            _signed(totalDifference),
            color: totalDifference == 0 ? AppColors.success : AppColors.warning,
          ),
        ),
      ],
    );
  }

  Widget _metric(
    String label,
    String value, {
    Color color = AppColors.primary,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
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
  }

  Widget _itemCard(int index, _StockOpnameRow row) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: WarehouseModernCard(
      child: InkWell(
        onTap: () => _askPhysicalQty(row.item, existingIndex: index),
        borderRadius: BorderRadius.circular(18),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: row.difference == 0
                  ? AppColors.softGreen
                  : AppColors.warning.withValues(alpha: 0.12),
              foregroundColor: row.difference == 0
                  ? AppColors.success
                  : AppColors.warning,
              child: Text('${index + 1}'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${row.item.sku} | Sistem ${row.systemQty} | Fisik ${row.physicalQty}',
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _signed(row.difference),
                  style: TextStyle(
                    color: row.difference == 0
                        ? AppColors.success
                        : AppColors.warning,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text(
                  'Selisih',
                  style: TextStyle(color: AppColors.slate, fontSize: 10),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Hapus item',
              onPressed: () => setState(() => _rows.removeAt(index)),
              icon: Icon(
                Icons.close_rounded,
                color: row.difference == 0
                    ? AppColors.success
                    : AppColors.warning,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _showWarehousePicker() async {
    final selected = await _showPicker<WarehouseInfo>(
      title: 'Pilih Gudang Stock Opname',
      searchHint: 'Cari nama gudang atau company',
      rows: _warehouses,
      matches: (row, query) =>
          row.name.toLowerCase().contains(query) ||
          row.company.toLowerCase().contains(query),
      tile: (row) => ListTile(
        title: Text(
          row.name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(row.company),
      ),
    );
    if (selected == null || selected.name == _warehouse) return;
    if (_rows.isNotEmpty && !await _confirmWarehouseChange()) return;
    setState(() {
      _warehouse = selected.name;
      _rows.clear();
      _error = null;
    });
  }

  Future<bool> _confirmWarehouseChange() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Ganti gudang?'),
            content: const Text(
              'Daftar item yang sudah dihitung akan dikosongkan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Ganti Gudang'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showItemPicker() async {
    final selected = await _showPicker<InventoryItem>(
      title: 'Tambah Item',
      searchHint: 'Cari nama atau kode item',
      rows: _warehouseItems,
      matches: (row, query) =>
          row.sku.toLowerCase().contains(query) ||
          row.name.toLowerCase().contains(query),
      tile: (row) => ListTile(
        title: Text(
          row.name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text('${row.sku} | Stok sistem ${row.quantity}'),
      ),
    );
    if (selected != null) await _askPhysicalQty(selected);
  }

  Future<T?> _showPicker<T>({
    required String title,
    required String searchHint,
    required List<T> rows,
    required bool Function(T row, String query) matches,
    required Widget Function(T row) tile,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final normalized = query.trim().toLowerCase();
            final filtered = normalized.isEmpty
                ? rows.take(50).toList()
                : rows.where((row) => matches(row, normalized)).toList();
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
                ),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDark.withValues(alpha: 0.16),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.navy,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Tutup',
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextField(
                          autofocus: true,
                          onChanged: (value) =>
                              setSheetState(() => query = value),
                          decoration: InputDecoration(
                            hintText: searchHint,
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(28),
                                  child: Text(
                                    'Data tidak ditemukan',
                                    style: TextStyle(
                                      color: AppColors.slate,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  14,
                                ),
                                itemCount: filtered.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  color: AppColors.border,
                                ),
                                itemBuilder: (context, index) => InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => Navigator.pop(
                                    sheetContext,
                                    filtered[index],
                                  ),
                                  child: tile(filtered[index]),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _askPhysicalQty(InventoryItem item, {int? existingIndex}) async {
    final controller = TextEditingController(
      text: existingIndex == null
          ? '${item.quantity}'
          : '${_rows[existingIndex].physicalQty}',
    );
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(item.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stok sistem: ${item.quantity}'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Stok fisik'),
            ),
          ],
        ),
        actions: [
          if (existingIndex != null)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, -1),
              child: const Text('Hapus'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final qty = double.tryParse(controller.text.trim());
              if (qty != null && qty >= 0) Navigator.pop(dialogContext, qty);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() {
      if (result == -1 && existingIndex != null) {
        _rows.removeAt(existingIndex);
        return;
      }
      final row = _StockOpnameRow(item: item, physicalQty: result);
      final duplicate = _rows.indexWhere((entry) => entry.item.sku == item.sku);
      if (existingIndex != null) {
        _rows[existingIndex] = row;
      } else if (duplicate >= 0) {
        _rows[duplicate] = row;
      } else {
        _rows.add(row);
      }
    });
  }

  Widget _errorPanel(String message) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.danger.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      message,
      style: const TextStyle(
        color: AppColors.danger,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  String _signed(double value) {
    if (value > 0) return '+${value.toStringAsFixed(0)}';
    return value.toStringAsFixed(0);
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _StockOpnameRow {
  final InventoryItem item;
  final double physicalQty;

  const _StockOpnameRow({required this.item, required this.physicalQty});

  double get systemQty => item.quantity.toDouble();
  double get difference => physicalQty - systemQty;
}
