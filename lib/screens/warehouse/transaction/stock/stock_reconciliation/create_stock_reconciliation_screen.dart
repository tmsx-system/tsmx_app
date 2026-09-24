import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../../models/warehouse_info.dart';
import '../../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../../theme/app_colors.dart';
import '../../../../../utils/num_parse.dart';
import '../../../../../widgets/erp/erp_error_dialog.dart';
import '../../../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../../../widgets/responsive/responsive_layout.dart';

class CreateStockReconciliationScreen extends StatefulWidget {
  final String? company;

  const CreateStockReconciliationScreen({super.key, this.company});

  @override
  State<CreateStockReconciliationScreen> createState() =>
      _CreateStockReconciliationScreenState();
}

class _CreateStockReconciliationScreenState
    extends State<CreateStockReconciliationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rows = <_RecoItemRow>[];
  List<WarehouseInfo> _warehouses = const [];
  List<ErpItemOption> _itemOptions = const [];
  List<String> _seriesOptions = const [];
  List<String> _purposeOptions = const [];
  final _itemMeta = <String, _ItemMeta>{};
  String? _company;
  String? _series;
  String? _purpose;
  String? _defaultWarehouse;
  String? _expenseAccount;
  String? _costCenter;
  DateTime _postingDate = DateTime.now();
  TimeOfDay _postingTime = TimeOfDay.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final company = widget.company?.trim() ?? '';
    _company = company.isEmpty ? null : company;
    _rows.add(_RecoItemRow());
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
      final items = await _fetchItems();
      final series = await state.appState.fetchNamingSeries(
        'Stock Reconciliation',
      );
      final purposes = await _fetchSelectOptions('purpose');
      if (!mounted) return;
      setState(() {
        _warehouses = warehouses;
        _itemOptions = items;
        _seriesOptions = series;
        _purposeOptions = purposes;
        _series ??= series.isEmpty ? null : series.first;
        _purpose ??= purposes.contains('Stock Reconciliation')
            ? 'Stock Reconciliation'
            : (purposes.isEmpty ? 'Stock Reconciliation' : purposes.first);
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = captureErpError(
            context,
            error,
            action: 'memuat form Stock Reconciliation',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<String>> _fetchSelectOptions(String fieldname) async {
    try {
      final docType = await context
          .read<WarehouseStockState>()
          .frappeService
          .fetchDocument('DocType', 'Stock Reconciliation');
      final fields = docType['fields'];
      if (fields is! List) return const [];
      for (final row in fields) {
        if (row is! Map) continue;
        if (row['fieldname']?.toString() != fieldname) continue;
        return row['options']
                ?.toString()
                .split('\n')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList() ??
            const [];
      }
    } catch (_) {}
    return const [];
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

  String get _postingTimeText {
    final now = DateTime.now();
    return DateFormat('HH:mm:ss').format(
      DateTime(
        now.year,
        now.month,
        now.day,
        _postingTime.hour,
        _postingTime.minute,
        now.second,
      ),
    );
  }

  void _addRow() {
    setState(() {
      _rows.add(_RecoItemRow(warehouse: _defaultWarehouse));
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) {
      final first = _rows.first;
      first.dispose();
      setState(() {
        _rows
          ..clear()
          ..add(_RecoItemRow(warehouse: _defaultWarehouse));
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
    row.warehouse ??= _defaultWarehouse;
    setState(() {});
  }

  void _setDefaultWarehouse(String? warehouse) {
    setState(() {
      _defaultWarehouse = warehouse;
      for (final row in _rows) {
        row.warehouse = warehouse;
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
    final missingWarehouse = filled.any(
      (row) => (row.warehouse ?? _defaultWarehouse ?? '').trim().isEmpty,
    );
    if (missingWarehouse) {
      setState(() => _error = 'Warehouse wajib diisi pada setiap item.');
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
            'warehouse': row.warehouse ?? _defaultWarehouse,
            'qty': row.qty,
            if (row.rate > 0) 'valuation_rate': row.rate,
          },
      ];
      await context.read<WarehouseStockState>().createStockReconciliation(
        company: _company ?? '',
        purpose: _purpose ?? 'Stock Reconciliation',
        warehouse: _defaultWarehouse,
        expenseAccount: _expenseAccount,
        costCenter: _costCenter,
        postingDate: _postingDate,
        postingTime: _postingTimeText,
        namingSeries: _series,
        items: payload,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock Reconciliation berhasil dibuat sebagai draft.'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = captureErpError(
            context,
            error,
            action: 'membuat Stock Reconciliation',
          ),
        );
      }
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
          'New Stock Reconciliation',
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
                              'Informasi Stock Reconciliation',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.slate,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_seriesOptions.isNotEmpty)
                              ErpItemAutocompleteField(
                                label: 'Series',
                                selectedId: _seriesOptions.contains(_series)
                                    ? _series
                                    : null,
                                decoration: _fieldDecoration('Series'),
                                options: [
                                  for (final series in _seriesOptions)
                                    ErpItemOption(id: series, label: series),
                                ],
                                onSelected: (value) =>
                                    setState(() => _series = value),
                              ),
                            if (_seriesOptions.isNotEmpty)
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
                                _defaultWarehouse = null;
                                _expenseAccount = null;
                                _costCenter = null;
                                for (final row in _rows) {
                                  row.warehouse = null;
                                }
                              }),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Company wajib dipilih'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            ErpItemAutocompleteField(
                              label: 'Purpose',
                              selectedId:
                                  _purposeOptions.contains(_purpose) ||
                                      _purpose == 'Stock Reconciliation'
                                  ? _purpose
                                  : null,
                              decoration: _fieldDecoration('Purpose'),
                              options: [
                                for (final purpose
                                    in _purposeOptions.isEmpty
                                        ? const ['Stock Reconciliation']
                                        : _purposeOptions)
                                  ErpItemOption(id: purpose, label: purpose),
                              ],
                              onSelected: (value) =>
                                  setState(() => _purpose = value),
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
                              child: _readonlyBox(
                                icon: Icons.calendar_today,
                                label: 'Posting Date',
                                value: DateFormat(
                                  'dd-MM-yyyy',
                                ).format(_postingDate),
                              ),
                            ),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _postingTime,
                                );
                                if (picked == null) return;
                                setState(() => _postingTime = picked);
                              },
                              child: _readonlyBox(
                                icon: Icons.schedule_rounded,
                                label: 'Posting Time',
                                value: _postingTimeText,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ErpItemAutocompleteField(
                              key: ValueKey(
                                'wh:${_company ?? ''}:${_defaultWarehouse ?? ''}',
                              ),
                              label: 'Default Warehouse',
                              selectedId: warehouses.any(
                                (row) => row.name == _defaultWarehouse,
                              )
                                  ? _defaultWarehouse
                                  : null,
                              decoration: _fieldDecoration(
                                'Default Warehouse',
                                hint: 'Pilih atau search gudang',
                              ),
                              options: [
                                for (final warehouse in warehouses)
                                  ErpItemOption(
                                    id: warehouse.name,
                                    label: warehouse.displayName,
                                  ),
                              ],
                              onSelected: _setDefaultWarehouse,
                            ),
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
                      const SizedBox(height: 16),
                      Container(
                        decoration: _cardDecoration,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ErpItemAutocompleteField(
                              key: ValueKey(
                                'acc:${_company ?? ''}:${_expenseAccount ?? ''}',
                              ),
                              label: 'Difference Account',
                              selectedId: _expenseAccount,
                              decoration: _fieldDecoration(
                                'Difference Account',
                              ),
                              options: [
                                if ((_expenseAccount ?? '').isNotEmpty)
                                  ErpItemOption(
                                    id: _expenseAccount!,
                                    label: _expenseAccount!,
                                  ),
                              ],
                              onSearch: _fetchAccounts,
                              onSelected: (value) =>
                                  setState(() => _expenseAccount = value),
                            ),
                            const SizedBox(height: 12),
                            ErpItemAutocompleteField(
                              key: ValueKey(
                                'cc:${_company ?? ''}:${_costCenter ?? ''}',
                              ),
                              label: 'Cost Center',
                              selectedId: _costCenter,
                              decoration: _fieldDecoration('Cost Center'),
                              options: [
                                if ((_costCenter ?? '').isNotEmpty)
                                  ErpItemOption(
                                    id: _costCenter!,
                                    label: _costCenter!,
                                  ),
                              ],
                              onSearch: _fetchCostCenters,
                              onSelected: (value) =>
                                  setState(() => _costCenter = value),
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
                          _saving
                              ? 'Menyimpan...'
                              : 'Save Stock Reconciliation',
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

  Widget _readonlyBox({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.slate),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.slate,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.navy,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRowCard(int index, _RecoItemRow row) {
    final warehouses = _companyWarehouses;
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
            label: 'Item Code',
            selectedId: row.itemCode,
            options: _itemOptions,
            onSearch: _fetchItems,
            decoration: _fieldDecoration(
              'Item Code',
              hint: 'Pilih atau search item',
            ),
            onSelected: (value) => _applyItem(index, value),
          ),
          const SizedBox(height: 10),
          ErpItemAutocompleteField(
            key: ValueKey(
              'row-wh-$index:${_company ?? ''}:${row.warehouse ?? ''}',
            ),
            label: 'Warehouse',
            selectedId: warehouses.any((wh) => wh.name == row.warehouse)
                ? row.warehouse
                : null,
            decoration: _fieldDecoration('Warehouse'),
            options: [
              for (final warehouse in warehouses)
                ErpItemOption(
                  id: warehouse.name,
                  label: warehouse.displayName,
                ),
            ],
            onSelected: (value) => setState(() => row.warehouse = value),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _fieldDecoration('Quantity'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: row.rateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _fieldDecoration('Valuation Rate'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('amt-$index-${row.amount}'),
            readOnly: true,
            enabled: false,
            initialValue: row.amount.toStringAsFixed(2),
            decoration: _fieldDecoration('Amount'),
          ),
        ],
      ),
    );
  }
}

class _ItemMeta {
  final String name;
  final String uom;
  final double rate;

  const _ItemMeta({required this.name, required this.uom, required this.rate});
}

class _RecoItemRow {
  String? itemCode;
  String itemName;
  String uom;
  String? warehouse;
  final TextEditingController qtyCtrl;
  final TextEditingController rateCtrl;

  _RecoItemRow({this.warehouse})
    : itemName = '',
      uom = '',
      qtyCtrl = TextEditingController(text: '0'),
      rateCtrl = TextEditingController(text: '0');

  double get qty => double.tryParse(qtyCtrl.text.trim()) ?? 0;
  double get rate => double.tryParse(rateCtrl.text.trim()) ?? 0;
  double get amount => qty * rate;

  void dispose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
  }
}
