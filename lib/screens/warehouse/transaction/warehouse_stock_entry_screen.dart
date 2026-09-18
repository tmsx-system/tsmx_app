import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/inventory_item.dart';
import '../../../models/warehouse_info.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../shared/warehouse_widgets.dart';

enum WarehouseOperation {
  transfer(
    title: 'Transfer Antar Gudang',
    stockEntryType: 'Material Transfer',
    icon: Icons.swap_horiz_rounded,
  ),
  receive(
    title: 'Goods Receive',
    stockEntryType: 'Material Receipt',
    icon: Icons.move_to_inbox_rounded,
  ),
  issue(
    title: 'Goods Issue',
    stockEntryType: 'Material Issue',
    icon: Icons.outbox_rounded,
  );

  final String title;
  final String stockEntryType;
  final IconData icon;

  const WarehouseOperation({
    required this.title,
    required this.stockEntryType,
    required this.icon,
  });
}

class WarehouseStockEntryScreen extends StatefulWidget {
  final WarehouseOperation operation;

  const WarehouseStockEntryScreen({super.key, required this.operation});

  @override
  State<WarehouseStockEntryScreen> createState() =>
      _WarehouseStockEntryScreenState();
}

class _WarehouseStockEntryScreenState extends State<WarehouseStockEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rows = <_WarehouseOperationRow>[];
  List<WarehouseInfo> _warehouses = const [];
  List<InventoryItem> _items = const [];
  String? _sourceWarehouse;
  String? _targetWarehouse;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _needsSource => widget.operation != WarehouseOperation.receive;
  bool get _needsTarget => widget.operation != WarehouseOperation.issue;

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
      if (state.warehouses.isEmpty) await state.refreshWarehouses();
      if (state.inventory.isEmpty) await state.refreshInventory();
      final warehouses =
          state.warehouses
              .where((row) => !row.isGroup && row.isDisabled != true)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      final uniqueItems = <String, InventoryItem>{};
      for (final item in state.inventory) {
        uniqueItems.putIfAbsent(item.sku, () => item);
      }
      if (!mounted) return;
      setState(() {
        _warehouses = warehouses;
        _items = uniqueItems.values.toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        _sourceWarehouse = _sourceWarehouse ?? _firstWarehouse(warehouses);
        _targetWarehouse =
            _targetWarehouse ??
            _firstWarehouse(warehouses, except: _sourceWarehouse);
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _firstWarehouse(List<WarehouseInfo> rows, {String? except}) {
    for (final row in rows) {
      if (row.name != except) return row.name;
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_rows.isEmpty) {
      setState(() => _error = 'Tambahkan minimal satu item.');
      return;
    }
    if (_needsSource && _needsTarget && _sourceWarehouse == _targetWarehouse) {
      setState(() => _error = 'Gudang asal dan tujuan harus berbeda.');
      return;
    }
    final rowError = _validateRows();
    if (rowError != null) {
      setState(() => _error = rowError);
      return;
    }
    final stockError = _validateSourceStock();
    if (stockError != null) {
      setState(() => _error = stockError);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = [
        for (final row in _rows)
          {
            'item_code': row.item.sku,
            'item_name': row.item.name,
            'qty': row.qty,
            if (row.item.unitValue > 0) 'basic_rate': row.item.unitValue,
            if (_needsSource) 's_warehouse': row.sourceWarehouse,
            if (_needsTarget) 't_warehouse': row.targetWarehouse,
          },
      ];
      await context.read<WarehouseStockState>().createStockEntry(
        stockEntryType: widget.operation.stockEntryType,
        company: _entryCompany(),
        items: payload,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.operation.title} berhasil dibuat sebagai draft.',
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

  String? _validateSourceStock() {
    if (!_needsSource) return null;
    for (final row in _rows) {
      final sourceWarehouse = row.sourceWarehouse;
      if (sourceWarehouse == null || sourceWarehouse.isEmpty) {
        return 'Source Warehouse wajib dipilih untuk ${row.item.name}.';
      }
      final available = context
          .read<WarehouseStockState>()
          .inventory
          .where(
            (item) =>
                item.sku == row.item.sku && item.warehouseId == sourceWarehouse,
          )
          .fold<int>(0, (sum, item) => sum + item.quantity);
      if (row.qty > available) {
        return '${row.item.name} hanya tersedia $available di $sourceWarehouse.';
      }
    }
    return null;
  }

  String _entryCompany() {
    for (final row in _rows) {
      final warehouse = row.sourceWarehouse ?? row.targetWarehouse;
      final company = _warehouseCompany(warehouse);
      if (company.isNotEmpty) return company;
    }
    final company = _warehouseCompany(_sourceWarehouse).isNotEmpty
        ? _warehouseCompany(_sourceWarehouse)
        : _warehouseCompany(_targetWarehouse);
    return company;
  }

  String? _validateRows() {
    final companies = <String>{};
    for (final row in _rows) {
      if (_needsSource &&
          (row.sourceWarehouse == null || row.sourceWarehouse!.isEmpty)) {
        return 'Source Warehouse wajib dipilih untuk ${row.item.name}.';
      }
      if (_needsTarget &&
          (row.targetWarehouse == null || row.targetWarehouse!.isEmpty)) {
        return 'Target Warehouse wajib dipilih untuk ${row.item.name}.';
      }
      if (_needsSource &&
          _needsTarget &&
          row.sourceWarehouse == row.targetWarehouse) {
        return 'Source dan Target Warehouse ${row.item.name} harus berbeda.';
      }
      final sourceCompany = _warehouseCompany(row.sourceWarehouse);
      final targetCompany = _warehouseCompany(row.targetWarehouse);
      if (_needsSource && _needsTarget && sourceCompany != targetCompany) {
        return 'Transfer ${row.item.name} hanya bisa antar gudang dalam company yang sama.';
      }
      final company = sourceCompany.isNotEmpty ? sourceCompany : targetCompany;
      if (company.isNotEmpty) companies.add(company);
    }
    if (companies.length > 1) {
      return 'Semua item dalam satu Stock Entry harus berada pada company yang sama.';
    }
    return null;
  }

  String _warehouseCompany(String? warehouse) {
    for (final row in _warehouses) {
      if (row.name == warehouse) return row.company;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(
        widget.operation.title,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: warehousePagePaddingOf(context),
              children: [
                _instructionPanel(),
                const SizedBox(height: 14),
                if (_needsSource)
                  _warehouseField(
                    label: 'Gudang asal',
                    value: _sourceWarehouse,
                    onChanged: (value) => setState(() {
                      _sourceWarehouse = value;
                      if (_targetWarehouse == value) {
                        _targetWarehouse = _firstWarehouse(
                          _warehouses,
                          except: value,
                        );
                      }
                    }),
                  ),
                if (_needsSource && _needsTarget) const SizedBox(height: 12),
                if (_needsTarget)
                  _warehouseField(
                    label: 'Gudang tujuan',
                    value: _targetWarehouse,
                    onChanged: (value) =>
                        setState(() => _targetWarehouse = value),
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Daftar Item',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _showItemPicker,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Tambah'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_rows.isEmpty)
                  const WarehouseModernCard(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Belum ada item. Tekan Tambah untuk memilih item.',
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
                  WarehouseInfoPanel(
                    icon: Icons.error_outline_rounded,
                    color: AppColors.danger,
                    message: _error!,
                  ),
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
                      _saving ? 'Menyimpan...' : 'Simpan Draft Stock Entry',
                    ),
                  ),
                ),
              ],
            ),
          ),
  );

  Widget _instructionPanel() => WarehouseInfoPanel(
    icon: widget.operation.icon,
    message: switch (widget.operation) {
      WarehouseOperation.transfer =>
        'Pindahkan beberapa item dari satu gudang ke gudang lain.',
      WarehouseOperation.receive => 'Catat barang yang masuk ke gudang tujuan.',
      WarehouseOperation.issue => 'Catat barang yang keluar dari gudang asal.',
    },
  );

  Widget _warehouseField({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final selected = _warehouseByName(value);
    return FormField<String>(
      initialValue: value,
      validator: (_) => value == null ? '$label wajib dipilih' : null,
      builder: (field) => InkWell(
        onTap: () async {
          final next = await _showWarehousePicker(label, value);
          if (next == null) return;
          onChanged(next.name);
          field.didChange(next.name);
        },
        borderRadius: BorderRadius.circular(18),
        child: WarehouseSelectTile(
          label: label,
          value: selected?.name ?? 'Pilih atau cari gudang',
          subtitle: selected == null ? null : _warehouseSubtitle(selected),
          icon: Icons.warehouse_outlined,
          errorText: field.errorText,
        ),
      ),
    );
  }

  WarehouseInfo? _warehouseByName(String? name) {
    for (final row in _warehouses) {
      if (row.name == name) return row;
    }
    return null;
  }

  String _warehouseSubtitle(WarehouseInfo row) => [
    if (row.company.isNotEmpty) row.company,
    if (row.parentWarehouse?.isNotEmpty == true) row.parentWarehouse!,
  ].join(' | ');

  Future<WarehouseInfo?> _showWarehousePicker(
    String title,
    String? selectedName,
  ) {
    return showModalBottomSheet<WarehouseInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final normalized = query.trim().toLowerCase();
            final filtered = normalized.isEmpty
                ? _warehouses
                : _warehouses.where((row) {
                    return row.name.toLowerCase().contains(normalized) ||
                        row.displayName.toLowerCase().contains(normalized) ||
                        row.company.toLowerCase().contains(normalized) ||
                        (row.parentWarehouse ?? '').toLowerCase().contains(
                          normalized,
                        );
                  }).toList();
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
                            hintText: 'Cari nama, lokasi, atau company',
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
                                    'Gudang tidak ditemukan',
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
                                itemBuilder: (context, index) {
                                  final row = filtered[index];
                                  return ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    leading: const CircleAvatar(
                                      backgroundColor: AppColors.softGreen,
                                      foregroundColor: AppColors.primary,
                                      child: Icon(Icons.warehouse_outlined),
                                    ),
                                    title: Text(
                                      row.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _warehouseSubtitle(row),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: row.name == selectedName
                                        ? const Icon(
                                            Icons.check_circle_rounded,
                                            color: AppColors.success,
                                          )
                                        : null,
                                    onTap: () =>
                                        Navigator.pop(sheetContext, row),
                                  );
                                },
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

  Widget _itemCard(int index, _WarehouseOperationRow row) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: WarehouseModernCard(
      child: InkWell(
        onTap: () => _editRow(existingIndex: index),
        borderRadius: BorderRadius.circular(18),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.softGreen,
              foregroundColor: AppColors.primary,
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
                  const SizedBox(height: 3),
                  Text(
                    '${row.item.sku} | Qty ${row.qty}',
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (_needsSource)
                        _rowChip(
                          Icons.logout_rounded,
                          'Source',
                          row.sourceWarehouse ?? '-',
                        ),
                      if (_needsTarget)
                        _rowChip(
                          Icons.login_rounded,
                          'Target',
                          row.targetWarehouse ?? '-',
                        ),
                      _rowChip(
                        Icons.payments_outlined,
                        'Rate',
                        row.item.unitValue > 0
                            ? 'Rp ${row.item.unitValue.toStringAsFixed(0)}'
                            : '-',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Hapus item',
              onPressed: () => setState(() => _rows.removeAt(index)),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _rowChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showItemPicker() async {
    final selected = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final normalized = query.trim().toLowerCase();
            final filtered = normalized.isEmpty
                ? _items.take(40).toList()
                : _items.where((item) {
                    return item.sku.toLowerCase().contains(normalized) ||
                        item.name.toLowerCase().contains(normalized);
                  }).toList();
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
                            const Expanded(
                              child: Text(
                                'Pilih Item',
                                style: TextStyle(
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
                            hintText: 'Cari item atau kode',
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
                                    'Item tidak ditemukan',
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
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  return ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    title: Text(
                                      item.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    subtitle: Text(item.sku),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, item),
                                  );
                                },
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
    if (selected != null) await _editRow(item: selected);
  }

  Future<void> _editRow({InventoryItem? item, int? existingIndex}) async {
    final existing = existingIndex == null ? null : _rows[existingIndex];
    final selectedItem = item ?? existing?.item;
    if (selectedItem == null) return;

    final controller = TextEditingController(
      text: existing == null ? '1' : '${existing.qty}',
    );
    var sourceWarehouse =
        existing?.sourceWarehouse ?? (_needsSource ? _sourceWarehouse : null);
    var targetWarehouse =
        existing?.targetWarehouse ?? (_needsTarget ? _targetWarehouse : null);

    final row = await showModalBottomSheet<_WarehouseOperationRow>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickWarehouse({
              required bool source,
              required String title,
            }) async {
              final current = source ? sourceWarehouse : targetWarehouse;
              final picked = await _showWarehousePicker(title, current);
              if (picked == null) return;
              setSheetState(() {
                if (source) {
                  sourceWarehouse = picked.name;
                  if (targetWarehouse == picked.name) targetWarehouse = null;
                } else {
                  targetWarehouse = picked.name;
                  if (sourceWarehouse == picked.name) sourceWarehouse = null;
                }
                errorText = null;
              });
            }

            void submit() {
              final qty = double.tryParse(controller.text.trim());
              if (qty == null || qty <= 0) {
                setSheetState(() => errorText = 'Qty harus lebih dari 0.');
                return;
              }
              if (_needsSource &&
                  (sourceWarehouse == null || sourceWarehouse!.isEmpty)) {
                setSheetState(
                  () => errorText = 'Source Warehouse wajib dipilih.',
                );
                return;
              }
              if (_needsTarget &&
                  (targetWarehouse == null || targetWarehouse!.isEmpty)) {
                setSheetState(
                  () => errorText = 'Target Warehouse wajib dipilih.',
                );
                return;
              }
              if (_needsSource &&
                  _needsTarget &&
                  sourceWarehouse == targetWarehouse) {
                setSheetState(
                  () =>
                      errorText = 'Source dan Target Warehouse harus berbeda.',
                );
                return;
              }
              if (_needsSource &&
                  _needsTarget &&
                  _warehouseCompany(sourceWarehouse) !=
                      _warehouseCompany(targetWarehouse)) {
                setSheetState(
                  () => errorText =
                      'Transfer hanya bisa dalam company yang sama.',
                );
                return;
              }
              Navigator.pop(
                sheetContext,
                _WarehouseOperationRow(
                  item: selectedItem,
                  qty: qty,
                  sourceWarehouse: sourceWarehouse,
                  targetWarehouse: targetWarehouse,
                ),
              );
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 12,
                ),
                child: Container(
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
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        selectedItem.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        selectedItem.sku,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        autofocus: existing == null,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Qty',
                          prefixIcon: const Icon(Icons.numbers_rounded),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_needsSource) ...[
                        const SizedBox(height: 10),
                        _sheetSelectTile(
                          label: 'Source Warehouse',
                          value: sourceWarehouse ?? 'Pilih gudang asal',
                          icon: Icons.logout_rounded,
                          onTap: () => pickWarehouse(
                            source: true,
                            title: 'Source Warehouse',
                          ),
                        ),
                      ],
                      if (_needsTarget) ...[
                        const SizedBox(height: 10),
                        _sheetSelectTile(
                          label: 'Target Warehouse',
                          value: targetWarehouse ?? 'Pilih gudang tujuan',
                          icon: Icons.login_rounded,
                          onTap: () => pickWarehouse(
                            source: false,
                            title: 'Target Warehouse',
                          ),
                        ),
                      ],
                      if (selectedItem.unitValue > 0) ...[
                        const SizedBox(height: 10),
                        _sheetInfoTile(
                          label: 'Basic Rate',
                          value:
                              'Rp ${selectedItem.unitValue.toStringAsFixed(0)}',
                          icon: Icons.payments_outlined,
                        ),
                      ],
                      if (errorText != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          errorText!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: submit,
                        icon: const Icon(Icons.check_rounded),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Simpan Item'),
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
    controller.dispose();
    if (row == null || !mounted) return;
    setState(() {
      final duplicate = _rows.indexWhere(
        (current) =>
            current.item.sku == row.item.sku &&
            current.sourceWarehouse == row.sourceWarehouse &&
            current.targetWarehouse == row.targetWarehouse,
      );
      if (existingIndex != null) {
        _rows[existingIndex] = row;
      } else if (duplicate >= 0) {
        _rows[duplicate] = row;
      } else {
        _rows.add(row);
      }
    });
  }

  Widget _sheetSelectTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: _sheetInfoTile(
        label: label,
        value: value,
        icon: icon,
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  Widget _sheetInfoTile({
    required String label,
    required String value,
    required IconData icon,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }

  String _friendlyError(Object error) {
    return error
        .toString()
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _WarehouseOperationRow {
  final InventoryItem item;
  final double qty;
  final String? sourceWarehouse;
  final String? targetWarehouse;

  const _WarehouseOperationRow({
    required this.item,
    required this.qty,
    this.sourceWarehouse,
    this.targetWarehouse,
  });
}
