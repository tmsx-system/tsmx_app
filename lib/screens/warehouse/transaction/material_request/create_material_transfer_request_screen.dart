import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../models/material_request.dart';
import '../../../../models/warehouse_info.dart';
import '../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../theme/app_colors.dart';
import '../../../../utils/erp_error_message.dart';
import '../../../../utils/num_parse.dart';
import '../../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../../widgets/responsive/responsive_layout.dart';
import 'material_request_purpose.dart';

class CreateMaterialTransferRequestScreen extends StatefulWidget {
  final String purpose;
  final String? existingName;

  const CreateMaterialTransferRequestScreen({
    super.key,
    this.purpose = 'Material Transfer',
    this.existingName,
  });

  MaterialRequestPurpose get purposeInfo => MaterialRequestPurpose.all.firstWhere(
    (row) => row.name == purpose,
    orElse: () => MaterialRequestPurpose.all[1],
  );

  @override
  State<CreateMaterialTransferRequestScreen> createState() =>
      _CreateMaterialTransferRequestScreenState();
}

class _CreateMaterialTransferRequestScreenState
    extends State<CreateMaterialTransferRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rows = <_ItemRow>[];
  List<WarehouseInfo> _warehouses = const [];
  List<ErpItemOption> _items = const [];
  List<String> _seriesOptions = const [];
  String? _series;
  String? _company;
  String? _sourceWarehouse;
  String? _targetWarehouse;
  String? _customer;
  String? _priceList;
  List<ErpItemOption> _priceLists = const [];
  DateTime _transactionDate = DateTime.now();
  DateTime _requiredBy = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if ((widget.existingName ?? '').trim().isEmpty) {
      _rows.add(_ItemRow());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<WarehouseStockState>();
      var warehouses = await state.fetchFreshWarehouses();
      warehouses = warehouses
          .where((row) => !row.isGroup && row.isDisabled != true)
          .toList();
      final companies = state.stockCompanies.map((entry) => entry.key).toList();
      _company = state.preferredCompany(companies);
      final series = await state.appState.fetchNamingSeries('Material Request');
      final items = await _searchItems('');
      var priceLists = const <ErpItemOption>[];
      if (widget.purposeInfo.showPrice) {
        try {
          priceLists = await _searchPriceLists();
        } catch (_) {
          priceLists = const [
            ErpItemOption(id: 'Standard Buying', label: 'Standard Buying'),
          ];
        }
      }
      await _applyExisting(state, items);
      if (!mounted) return;
      setState(() {
        _warehouses = warehouses;
        _seriesOptions = series;
        _series ??= series.isEmpty ? null : series.first;
        _items = items;
        _priceLists = priceLists;
        _priceList ??= priceLists.any((row) => row.id == 'Standard Buying')
            ? 'Standard Buying'
            : (priceLists.isEmpty ? null : priceLists.first.id);
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = captureErpError(
          context,
          error,
          action: 'memuat form Material Request',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<WarehouseInfo> get _companyWarehouses {
    final company = _company?.trim() ?? '';
    return _warehouses
        .where((row) => company.isEmpty || row.company == company)
        .toList();
  }

  Future<void> _applyExisting(
    WarehouseStockState state,
    List<ErpItemOption> items,
  ) async {
    final name = widget.existingName?.trim() ?? '';
    if (name.isEmpty) return;
    final doc = await state.frappeService.fetchDocument('Material Request', name);
    final request = MaterialRequest.fromJson(doc);
    _company = request.company.isEmpty ? _company : request.company;
    _sourceWarehouse = request.sourceWarehouse.isEmpty
        ? null
        : request.sourceWarehouse;
    _targetWarehouse = request.targetWarehouse.isEmpty
        ? null
        : request.targetWarehouse;
    final transaction = DateTime.tryParse(request.transactionDate);
    final requiredBy = DateTime.tryParse(request.scheduleDate);
    if (transaction != null) _transactionDate = transaction;
    if (requiredBy != null) _requiredBy = requiredBy;
    final series = doc['naming_series']?.toString().trim() ?? '';
    if (series.isNotEmpty) _series = series;
    if (request.customer.isNotEmpty) _customer = request.customer;
    if (request.buyingPriceList.isNotEmpty) {
      _priceList = request.buyingPriceList;
    }
    for (final row in _rows) {
      row.dispose();
    }
    _rows.clear();
    for (final item in request.items) {
      final row = _ItemRow();
      row.itemCode = item.itemCode;
      row.uom = item.uom;
      row.qty.text = item.qty.toString();
      if (item.rate > 0) row.rate.text = item.rate.toString();
      if (item.fromWarehouse.isNotEmpty) {
        _sourceWarehouse ??= item.fromWarehouse;
      }
      if (item.warehouse.isNotEmpty) _targetWarehouse ??= item.warehouse;
      if (item.itemCode.isNotEmpty &&
          items.every((option) => option.id != item.itemCode)) {
        items.insert(
          0,
          ErpItemOption(
            id: item.itemCode,
            label: item.itemName.isEmpty
                ? item.itemCode
                : '${item.itemName} · ${item.itemCode}',
          ),
        );
      }
      _rows.add(row);
    }
    if (_rows.isEmpty) _rows.add(_ItemRow());
  }

  Future<List<ErpItemOption>> _searchPriceLists() async {
    final state = context.read<WarehouseStockState>();
    final rows = await state.frappeService.fetchResource(
      'Price List',
      fields: const ['name'],
      filters: const [
        ['buying', '=', 1],
        ['enabled', '=', 1],
      ],
      orderBy: 'name asc',
      limit: 40,
    );
    return [
      for (final row in rows)
        if ((row['name']?.toString().trim() ?? '').isNotEmpty)
          ErpItemOption(
            id: row['name'].toString().trim(),
            label: row['name'].toString().trim(),
          ),
    ];
  }

  Future<List<ErpItemOption>> _searchCustomers(String query) async {
    final state = context.read<WarehouseStockState>();
    final q = query.trim();
    final rows = await state.frappeService.fetchResource(
      'Customer',
      fields: const ['name', 'customer_name'],
      filters: const [
        ['disabled', '=', 0],
      ],
      orFilters: q.isEmpty
          ? null
          : [
              ['name', 'like', '%$q%'],
              ['customer_name', 'like', '%$q%'],
            ],
      orderBy: 'customer_name asc',
      limit: 40,
    );
    return [
      for (final row in rows)
        if ((row['name']?.toString().trim() ?? '').isNotEmpty)
          ErpItemOption(
            id: row['name'].toString().trim(),
            label: (row['customer_name']?.toString().trim().isNotEmpty == true)
                ? '${row['customer_name']} · ${row['name']}'
                : row['name'].toString().trim(),
          ),
    ];
  }

  Future<double> _lookupRate(String itemCode) async {
    final priceList = _priceList?.trim() ?? '';
    if (priceList.isEmpty || itemCode.trim().isEmpty) return 0;
    final state = context.read<WarehouseStockState>();
    final rows = await state.frappeService.fetchResource(
      'Item Price',
      fields: const ['price_list_rate'],
      filters: [
        ['item_code', '=', itemCode],
        ['price_list', '=', priceList],
      ],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return NumParse.asDouble(rows.first['price_list_rate']);
  }

  Future<List<ErpItemOption>> _searchItems(String query) async {
    final state = context.read<WarehouseStockState>();
    final q = query.trim();
    final rows = await state.frappeService.fetchResource(
      'Item',
      fields: const ['name', 'item_name', 'stock_uom'],
      filters: const [
        ['disabled', '=', 0],
        ['is_stock_item', '=', 1],
      ],
      orFilters: q.isEmpty
          ? null
          : [
              ['item_code', 'like', '%$q%'],
              ['item_name', 'like', '%$q%'],
            ],
      orderBy: 'item_name asc',
      limit: 40,
    );
    return [
      for (final row in rows)
        if ((row['name']?.toString().trim() ?? '').isNotEmpty)
          ErpItemOption(
            id: row['name'].toString().trim(),
            label:
                '${row['item_name']?.toString().trim().isNotEmpty == true ? row['item_name'] : row['name']} · ${row['name']}',
          ),
    ];
  }

  Future<void> _pickItem(_ItemRow row, String? itemCode) async {
    row.itemCode = itemCode;
    row.uom = '';
    final code = itemCode?.trim() ?? '';
    if (code.isEmpty) {
      setState(() {});
      return;
    }
    try {
      final state = context.read<WarehouseStockState>();
      final rows = await state.frappeService.fetchResource(
        'Item',
        fields: const ['stock_uom'],
        filters: [
          ['name', '=', code],
        ],
        limit: 1,
      );
      row.uom = rows.isEmpty ? '' : rows.first['stock_uom']?.toString() ?? '';
      if (widget.purposeInfo.showPrice) {
        final rate = await _lookupRate(code);
        if (rate > 0) row.rate.text = rate.toString();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _pickDate({required bool requiredBy}) async {
    final initial = requiredBy ? _requiredBy : _transactionDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (requiredBy) {
        _requiredBy = picked;
      } else {
        _transactionDate = picked;
        if (_requiredBy.isBefore(picked)) _requiredBy = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final company = _company?.trim() ?? '';
    final source = _sourceWarehouse?.trim() ?? '';
    final target = _targetWarehouse?.trim() ?? '';
    final purpose = widget.purposeInfo;
    if (purpose.needsCustomer && (_customer?.trim().isEmpty ?? true)) {
      setState(() => _error = 'Customer wajib diisi.');
      return;
    }
    if (company.isEmpty ||
        (purpose.needsSource && source.isEmpty) ||
        (purpose.needsTarget && target.isEmpty)) {
      setState(() => _error = 'Company dan gudang wajib diisi.');
      return;
    }
    if (purpose.needsSource && purpose.needsTarget && source == target) {
      setState(() => _error = 'Gudang asal dan gudang tujuan harus berbeda.');
      return;
    }
    final items = <Map<String, dynamic>>[];
    for (final row in _rows) {
      final code = row.itemCode?.trim() ?? '';
      final qty = NumParse.asDouble(row.qty.text);
      if (code.isEmpty || qty <= 0) continue;
      items.add({
        'item_code': code,
        'qty': qty,
        if (row.uom.trim().isNotEmpty) 'uom': row.uom.trim(),
        if (row.uom.trim().isNotEmpty) 'stock_uom': row.uom.trim(),
        if (purpose.showPrice) 'rate': NumParse.asDouble(row.rate.text),
      });
    }
    if (items.isEmpty) {
      setState(() => _error = 'Minimal satu item dengan qty lebih dari 0.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = context.read<WarehouseStockState>();
      await state.createMaterialRequestByPurpose(
        purpose: purpose.name,
        needsSource: purpose.needsSource,
        needsTarget: purpose.needsTarget,
        transactionDate: _transactionDate,
        requiredBy: _requiredBy,
        company: company,
        sourceWarehouse: source,
        targetWarehouse: target,
        namingSeries: _series,
        existingName: widget.existingName,
        customer: purpose.needsCustomer ? _customer : null,
        buyingPriceList: purpose.showPrice ? _priceList : null,
        items: items,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = captureErpError(
          context,
          error,
          action: 'menyimpan Material Request',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _boxDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _selectField({
    required String label,
    required String? selectedId,
    required List<ErpItemOption> options,
    required ValueChanged<String?> onSelected,
    String? Function(String?)? validator,
  }) {
    final selected = options.any((option) => option.id == selectedId)
        ? selectedId
        : null;
    return ErpItemAutocompleteField(
      key: ValueKey('$label:${selected ?? ''}'),
      label: label,
      selectedId: selected,
      options: options,
      decoration: _boxDecoration(label),
      onSelected: onSelected,
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd-MM-yyyy');
    final warehouses = _companyWarehouses;
    final companies = {
      for (final row in _warehouses)
        if (row.company.trim().isNotEmpty) row.company.trim(),
    }.toList()..sort();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          (widget.existingName ?? '').trim().isEmpty
              ? 'Material Request'
              : 'Edit ${widget.existingName}',
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
                padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 28),
                children: [
                  TmsxResponsiveBody(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PurposeInfoCard(purpose: widget.purposeInfo),
                        const SizedBox(height: 14),
                        _FormSection(
                          title: 'Informasi Dokumen',
                          child: Column(
                            children: [
                        if (_seriesOptions.isNotEmpty) ...[
                          _selectField(
                            label: 'Series',
                            selectedId: _series,
                            options: [
                              for (final series in _seriesOptions)
                                ErpItemOption(id: series, label: series),
                            ],
                            onSelected: (value) => setState(() => _series = value),
                          ),
                          const SizedBox(height: 12),
                        ],
                        InputDecorator(
                          decoration: _boxDecoration('Purpose'),
                          child: Text(
                            widget.purpose,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _selectField(
                          label: 'Company',
                          selectedId: _company,
                          options: [
                            for (final company in companies)
                              ErpItemOption(id: company, label: company),
                          ],
                          onSelected: (value) => setState(() {
                            _company = value;
                            _sourceWarehouse = null;
                            _targetWarehouse = null;
                          }),
                          validator: (value) =>
                              (value ?? '').trim().isEmpty ? 'Company wajib' : null,
                        ),
                        if (widget.purposeInfo.needsCustomer) ...[
                          const SizedBox(height: 12),
                          ErpItemAutocompleteField(
                            label: 'Customer',
                            selectedId: _customer,
                            options: [
                              if ((_customer ?? '').isNotEmpty)
                                ErpItemOption(id: _customer!, label: _customer!),
                            ],
                            onSearch: _searchCustomers,
                            decoration: _boxDecoration('Customer'),
                            onSelected: (value) => setState(() => _customer = value),
                            validator: (value) => (value ?? '').trim().isEmpty
                                ? 'Customer wajib'
                                : null,
                          ),
                        ],
                        if (widget.purposeInfo.showPrice) ...[
                          const SizedBox(height: 12),
                          _selectField(
                            label: 'Price List',
                            selectedId: _priceList,
                            options: _priceLists,
                            onSelected: (value) => setState(() => _priceList = value),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _DateField(
                          value: dateFormat.format(_transactionDate),
                          decoration: _boxDecoration('Transaction Date'),
                          onTap: () => _pickDate(requiredBy: false),
                        ),
                        const SizedBox(height: 12),
                        _DateField(
                          value: dateFormat.format(_requiredBy),
                          decoration: _boxDecoration('Required By'),
                          onTap: () => _pickDate(requiredBy: true),
                        ),
                        if (widget.purposeInfo.needsSource) ...[
                          const SizedBox(height: 12),
                          _selectField(
                            label: 'Set Source Warehouse',
                            selectedId: _sourceWarehouse,
                            options: [
                              for (final row in warehouses)
                                ErpItemOption(id: row.name, label: row.name),
                            ],
                            onSelected: (value) =>
                                setState(() => _sourceWarehouse = value),
                            validator: (value) => (value ?? '').trim().isEmpty
                                ? 'Gudang asal wajib'
                                : null,
                          ),
                        ],
                        if (widget.purposeInfo.needsTarget) ...[
                          const SizedBox(height: 12),
                          _selectField(
                            label: 'Set Target Warehouse',
                            selectedId: _targetWarehouse,
                            options: [
                              for (final row in warehouses)
                                ErpItemOption(id: row.name, label: row.name),
                            ],
                            onSelected: (value) =>
                                setState(() => _targetWarehouse = value),
                            validator: (value) => (value ?? '').trim().isEmpty
                                ? 'Gudang tujuan wajib'
                                : null,
                          ),
                        ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _FormSection(
                          title: 'Items',
                          child: Column(
                            children: [
                        const SizedBox(height: 4),
                        for (var index = 0; index < _rows.length; index++) ...[
                          _itemCard(index),
                          const SizedBox(height: 10),
                        ],
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _rows.add(_ItemRow())),
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
                              color: AppColors.danger,
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
                          ),
                          child: Text(
                            _saving
                                ? 'Menyimpan...'
                                : (widget.existingName ?? '').trim().isEmpty
                                ? 'Simpan'
                                : 'Simpan Perubahan',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _itemCard(int index) {
    final row = _rows[index];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          ErpItemAutocompleteField(
            label: 'Item Code',
            selectedId: row.itemCode,
            options: _items,
            onSearch: _searchItems,
            decoration: _boxDecoration('Item Code'),
            onSelected: (value) => _pickItem(row, value),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: row.qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _boxDecoration('Quantity'),
            onChanged: widget.purposeInfo.showPrice ? (_) => setState(() {}) : null,
          ),
          if (widget.purposeInfo.showPrice) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: row.rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _boxDecoration('Rate'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: _boxDecoration('Amount'),
              child: Text(
                (NumParse.asDouble(row.qty.text) * NumParse.asDouble(row.rate.text))
                    .toStringAsFixed(2),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
          const SizedBox(height: 8),
          InputDecorator(
            decoration: _boxDecoration('UOM'),
            child: Text(
              row.uom.isEmpty ? '-' : row.uom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_rows.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  final removed = _rows.removeAt(index);
                  removed.dispose();
                  setState(() {});
                },
                child: const Text('Hapus'),
              ),
            ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String value;
  final InputDecoration decoration;
  final VoidCallback onTap;

  const _DateField({
    required this.value,
    required this.decoration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: decoration,
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ItemRow {
  String? itemCode;
  String uom = '';
  final qty = TextEditingController(text: '1');
  final rate = TextEditingController(text: '0');

  void dispose() {
    qty.dispose();
    rate.dispose();
  }
}

class _PurposeInfoCard extends StatelessWidget {
  final MaterialRequestPurpose purpose;

  const _PurposeInfoCard({required this.purpose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: purpose.color.withValues(alpha: 0.25)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: purpose.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(purpose.icon, color: purpose.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  purpose.name,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  purpose.summary,
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
        ],
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _FormSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.slate,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
