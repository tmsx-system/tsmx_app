import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../../models/warehouse_info.dart';
import '../../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../../theme/app_colors.dart';
import '../../../../../utils/num_parse.dart';
import '../../../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../../../widgets/responsive/responsive_layout.dart';
import 'stock_entry_kind.dart';

class CreateStockEntryScreen extends StatefulWidget {
  final StockEntryKind kind;

  const CreateStockEntryScreen({super.key, required this.kind});

  @override
  State<CreateStockEntryScreen> createState() => _CreateStockEntryScreenState();
}

class _CreateStockEntryScreenState extends State<CreateStockEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rows = <_StockEntryItemRow>[];
  List<WarehouseInfo> _warehouses = const [];
  List<ErpItemOption> _itemOptions = const [];
  final _itemMeta = <String, _ItemMeta>{};
  String? _company;
  String? _sourceWarehouse;
  String? _targetWarehouse;
  DateTime _postingDate = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _needsSource => widget.kind.needsSource;
  bool get _needsTarget => widget.kind.needsTarget;

  @override
  void initState() {
    super.initState();
    _rows.add(_StockEntryItemRow());
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<WarehouseStockState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (state.warehouses.isEmpty) await state.refreshWarehouses();
      final warehouses =
          state.warehouses
              .where((row) => !row.isGroup && row.isDisabled != true)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      final companies = state.stockCompanies.map((entry) => entry.key);
      _company ??= state.preferredCompany(companies);
      final options = await _fetchItems();
      if (!mounted) return;
      setState(() {
        _warehouses = warehouses;
        _itemOptions = options;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<ErpItemOption>> _fetchItems([String query = '']) async {
    final state = context.read<WarehouseStockState>();
      final q = query.trim();
    final filters = <List<dynamic>>[
      ['disabled', '=', 0],
      ['is_stock_item', '=', 1],
    ];
    final orFilters = q.isEmpty
        ? null
        : [
            ['item_code', 'like', '%$q%'],
            ['item_name', 'like', '%$q%'],
          ];
    List<Map<String, dynamic>> itemRows;
    try {
      itemRows = await state.frappeService.fetchResource(
        'Item',
        fields: const [
          'name',
          'item_name',
          'stock_uom',
          'valuation_rate',
          'standard_rate',
        ],
        filters: filters,
        orFilters: orFilters,
        orderBy: 'item_name asc',
        limit: 80,
      );
    } catch (_) {
      itemRows = await state.frappeService.fetchResource(
        'Item',
        fields: const ['name', 'item_name', 'stock_uom'],
        orFilters: orFilters,
        orderBy: 'item_name asc',
        limit: 80,
      );
    }

    final options = <ErpItemOption>[];
    for (final row in itemRows) {
      final id = row['name']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      final name = row['item_name']?.toString().trim().isNotEmpty == true
          ? row['item_name'].toString().trim()
          : id;
      _itemMeta[id] = _ItemMeta(
        name: name,
        uom: row['stock_uom']?.toString() ?? '',
        rate: NumParse.asDouble(row['valuation_rate'] ?? row['standard_rate']),
      );
      options.add(ErpItemOption(id: id, label: '$name - $id'));
    }
    return options;
  }

  List<String> get _companies {
    return context
        .read<WarehouseStockState>()
        .stockCompanies
        .map((entry) => entry.key)
        .toList();
  }

  List<WarehouseInfo> get _companyWarehouses {
    final company = _company?.trim() ?? '';
    return _warehouses
        .where((row) => company.isEmpty || row.company == company)
        .toList();
  }

  void _addRow() {
    setState(() {
      _rows.add(
        _StockEntryItemRow(
          sourceWarehouse: _sourceWarehouse,
          targetWarehouse: _targetWarehouse,
        ),
      );
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) {
      final first = _rows.first;
      first.dispose();
      setState(() {
        _rows
          ..clear()
          ..add(
            _StockEntryItemRow(
              sourceWarehouse: _sourceWarehouse,
              targetWarehouse: _targetWarehouse,
            ),
          );
      });
      return;
    }
    final row = _rows.removeAt(index);
    row.dispose();
    setState(() {});
  }

  void _applyItem(int index, String? itemCode) {
    final row = _rows[index];
    row.itemCode = itemCode;
    final meta = itemCode == null ? null : _itemMeta[itemCode];
    row.itemName = meta?.name ?? '';
    row.uom = meta?.uom ?? '';
    if (meta != null &&
        (double.tryParse(row.rateCtrl.text.trim()) ?? 0) <= 0 &&
        meta.rate > 0) {
      row.rateCtrl.text = meta.rate.toString();
    }
    row.sourceWarehouse ??= _sourceWarehouse;
    row.targetWarehouse ??= _targetWarehouse;
    setState(() {});
  }

  void _setDefaultSource(String? warehouse) {
    setState(() {
      _sourceWarehouse = warehouse;
      for (final row in _rows) {
        row.sourceWarehouse = warehouse;
      }
    });
  }

  void _setDefaultTarget(String? warehouse) {
    setState(() {
      _targetWarehouse = warehouse;
      for (final row in _rows) {
        row.targetWarehouse = warehouse;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final filled = _rows
        .where((row) => (row.itemCode ?? '').isNotEmpty)
        .toList();
    if (filled.isEmpty) {
      setState(() => _error = 'Tambahkan minimal satu item.');
      return;
    }
    if (_needsSource &&
        _needsTarget &&
        !widget.kind.allowSameWarehouse &&
        (_sourceWarehouse ?? '') == (_targetWarehouse ?? '') &&
        (_sourceWarehouse ?? '').isNotEmpty) {
      setState(() => _error = 'Gudang asal dan tujuan harus berbeda.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = [
        for (final row in filled)
          {
            'item_code': row.itemCode,
            'item_name': row.itemName,
            'qty': row.qty,
            'uom': row.uom,
            'conversion_factor': 1,
            if (row.rate > 0) 'basic_rate': row.rate,
            if (_needsSource)
              's_warehouse': row.sourceWarehouse ?? _sourceWarehouse,
            if (_needsTarget)
              't_warehouse': row.targetWarehouse ?? _targetWarehouse,
          },
      ];
      await context.read<WarehouseStockState>().createStockEntry(
        stockEntryType: widget.kind.stockEntryType,
        purpose: widget.kind.purpose,
        company: _company,
        postingDate: _postingDate,
        fromWarehouse: _needsSource ? _sourceWarehouse : null,
        toWarehouse: _needsTarget ? _targetWarehouse : null,
        items: payload,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.kind.title} berhasil dibuat sebagai draft.'),
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

  InputDecoration _fieldDecoration(
    String label, {
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  BoxDecoration get _cardDecoration => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final companies = _companies;
    final warehouses = _companyWarehouses;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        centerTitle: false,
        titleSpacing: 16,
        title: const Text(
          'New Stock Entry',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 24),
              child: TmsxResponsiveBody(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: _cardDecoration,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Informasi Stock Entry',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.slate,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: widget.kind.title,
                              readOnly: true,
                              enabled: false,
                              decoration: _fieldDecoration(
                                'Stock Entry Type',
                              ).copyWith(
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ErpItemAutocompleteField(
                              label: 'Company',
                              selectedId: companies.contains(_company)
                                  ? _company
                                  : null,
                              decoration: _fieldDecoration('Company'),
                              options: [
                                for (final company in companies)
                                  ErpItemOption(id: company, label: company),
                              ],
                              onSelected: (value) => setState(() {
                                _company = value;
                                _sourceWarehouse = null;
                                _targetWarehouse = null;
                                for (final row in _rows) {
                                  row.sourceWarehouse = null;
                                  row.targetWarehouse = null;
                                }
                              }),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Company wajib dipilih'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _postingDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 365),
                                  ),
                                );
                                if (picked == null) return;
                                setState(() => _postingDate = picked);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.calendar_today,
                                          size: 14,
                                          color: AppColors.slate,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Posting Date',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.slate,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      DateFormat(
                                        'dd-MM-yyyy',
                                      ).format(_postingDate),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.navy,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_needsSource) ...[
                              const SizedBox(height: 12),
                              ErpItemAutocompleteField(
                                key: ValueKey(
                                  'source:${_company ?? ''}:${_sourceWarehouse ?? ''}',
                                ),
                                label: 'Default Source Warehouse',
                                selectedId: warehouses.any(
                                  (row) => row.name == _sourceWarehouse,
                                )
                                    ? _sourceWarehouse
                                    : null,
                                decoration: _fieldDecoration(
                                  'Default Source Warehouse',
                                  hint: 'Pilih atau search gudang asal',
                                ),
                                options: [
                                  for (final warehouse in warehouses)
                                    ErpItemOption(
                                      id: warehouse.name,
                                      label: warehouse.displayName,
                                    ),
                                ],
                                onSelected: _setDefaultSource,
                              ),
                            ],
                            if (_needsTarget) ...[
                              const SizedBox(height: 12),
                              ErpItemAutocompleteField(
                                key: ValueKey(
                                  'target:${_company ?? ''}:${_targetWarehouse ?? ''}',
                                ),
                                label: 'Default Target Warehouse',
                                selectedId: warehouses.any(
                                  (row) => row.name == _targetWarehouse,
                                )
                                    ? _targetWarehouse
                                    : null,
                                decoration: _fieldDecoration(
                                  'Default Target Warehouse',
                                  hint: 'Pilih atau search gudang tujuan',
                                ),
                                options: [
                                  for (final warehouse in warehouses)
                                    ErpItemOption(
                                      id: warehouse.name,
                                      label: warehouse.displayName,
                                    ),
                                ],
                                onSelected: _setDefaultTarget,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: _cardDecoration,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Items',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navy,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._rows.indexed.map(
                              (entry) => _itemRowCard(entry.$1, entry.$2),
                            ),
                            OutlinedButton.icon(
                              onPressed: _addRow,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Add Row'),
                            ),
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _saving ? 'Menyimpan...' : 'Save Stock Entry',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _itemRowCard(int index, _StockEntryItemRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Item ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hapus item',
                onPressed: () => _removeRow(index),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
          ErpItemAutocompleteField(
            label: 'Nama Item / Kode',
            selectedId: row.itemCode,
            options: _itemOptions,
            onSearch: _fetchItems,
            decoration: InputDecoration(
              labelText: 'Nama Item / Kode',
              hintText: 'Pilih atau search item',
              prefixIcon: const Icon(Icons.inventory_2_rounded),
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.16),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.10),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.36),
                  width: 1.4,
                ),
              ),
            ),
            onSelected: (value) => _applyItem(index, value),
          ),
          if (row.itemName.isNotEmpty) ...[
            const SizedBox(height: 10),
            TextFormField(
              key: ValueKey('name-${row.itemCode}-$index'),
              initialValue: row.itemName,
              readOnly: true,
              enabled: false,
              decoration: _fieldDecoration('Item Name'),
            ),
          ],
          const SizedBox(height: 10),
          TextFormField(
            controller: row.qtyCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _fieldDecoration(
              'Qty',
              prefixIcon: IconButton(
                tooltip: 'Kurangi quantity',
                onPressed: () {
                  final next = (row.qty - 1).clamp(0, 999999);
                  row.qtyCtrl.text = next == 0 ? '1' : '$next';
                  setState(() {});
                },
                icon: const Icon(Icons.remove_rounded),
              ),
              suffixIcon: IconButton(
                tooltip: 'Tambah quantity',
                onPressed: () {
                  row.qtyCtrl.text = '${row.qty + 1}';
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded),
              ),
            ),
            validator: (value) {
              if ((row.itemCode ?? '').isEmpty) return null;
              final qty = double.tryParse(value?.trim() ?? '');
              return qty == null || qty <= 0 ? 'Qty > 0' : null;
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('uom-${row.itemCode}-$index-${row.uom}'),
                  initialValue: row.uom,
                  readOnly: true,
                  enabled: false,
                  decoration: _fieldDecoration('UOM'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: row.rateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _fieldDecoration('Basic Rate'),
                ),
              ),
            ],
          ),
        ],
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

class _ItemMeta {
  final String name;
  final String uom;
  final double rate;

  const _ItemMeta({required this.name, required this.uom, required this.rate});
}

class _StockEntryItemRow {
  String? itemCode;
  String itemName;
  String uom;
  String? sourceWarehouse;
  String? targetWarehouse;
  final TextEditingController qtyCtrl;
  final TextEditingController rateCtrl;

  _StockEntryItemRow({this.sourceWarehouse, this.targetWarehouse})
    : itemName = '',
      uom = '',
      qtyCtrl = TextEditingController(text: '1'),
      rateCtrl = TextEditingController(text: '0');

  double get qty => double.tryParse(qtyCtrl.text.trim()) ?? 0;
  double get rate => double.tryParse(rateCtrl.text.trim()) ?? 0;

  void dispose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
  }
}
