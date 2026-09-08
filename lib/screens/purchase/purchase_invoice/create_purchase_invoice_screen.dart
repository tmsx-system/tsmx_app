import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/warehouse_info.dart';
import '../../../state/purchasing/purchase_invoice_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/purchase_ui.dart';

class CreatePurchaseInvoiceScreen extends StatefulWidget {
  const CreatePurchaseInvoiceScreen({super.key});

  @override
  State<CreatePurchaseInvoiceScreen> createState() =>
      _CreatePurchaseInvoiceScreenState();
}

class _CreatePurchaseInvoiceScreenState
    extends State<CreatePurchaseInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController(text: '1');
  final _rateCtrl = TextEditingController();
  final List<_AdditionalInvoiceItemRow> _additionalItems = [];

  List<String> _series = [];
  List<_Option> _suppliers = [];
  List<_Option> _items = [];
  List<WarehouseInfo> _warehouses = [];
  String? _selectedSeries;
  String? _selectedSupplier;
  String? _selectedItem;
  String? _selectedWarehouse;
  DateTime _postingDate = DateTime.now();
  DateTime _dueDate = DateTime.now();
  bool _updateStock = false;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _qtyCtrl.addListener(_refreshTotal);
    _rateCtrl.addListener(_refreshTotal);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOptions());
  }

  @override
  void dispose() {
    _qtyCtrl.removeListener(_refreshTotal);
    _rateCtrl.removeListener(_refreshTotal);
    _qtyCtrl.dispose();
    _rateCtrl.dispose();
    for (final row in _additionalItems) {
      row.dispose();
    }
    super.dispose();
  }

  void _refreshTotal() => setState(() {});

  void _addItemRow() {
    final row = _AdditionalInvoiceItemRow(warehouse: _selectedWarehouse);
    row.qtyController.addListener(_refreshTotal);
    row.rateController.addListener(_refreshTotal);
    setState(() => _additionalItems.add(row));
  }

  void _removeItemRow(int index) {
    final row = _additionalItems.removeAt(index);
    row.dispose();
    _refreshTotal();
  }

  Future<List<_Option>> _fetchOptions(
    PurchaseInvoiceState appState,
    String doctype,
    String labelField,
  ) async {
    List<Map<String, dynamic>> rows;
    try {
      rows = await appState.frappeService.fetchResource(
        doctype,
        fields: ['name', labelField],
        filters: _activeMasterFilters(doctype),
        orderBy: '$labelField asc',
      );
    } catch (_) {
      rows = await appState.frappeService.fetchResource(
        doctype,
        fields: const ['name'],
        orderBy: 'name asc',
      );
    }
    return rows
        .map((row) {
          final id = row['name']?.toString() ?? '';
          if (id.isEmpty) return null;
          return _Option(id, row[labelField]?.toString() ?? id);
        })
        .whereType<_Option>()
        .toList();
  }

  List<List<dynamic>>? _activeMasterFilters(String doctype) {
    if (doctype == 'Item' || doctype == 'Supplier') {
      return const [
        ['disabled', '=', 0],
      ];
    }
    return null;
  }

  Future<void> _loadOptions() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final appState = context.read<PurchaseInvoiceState>();
      if (appState.warehouses.isEmpty) await appState.refreshWarehouses();
      final series = await appState.fetchNamingSeries('Purchase Invoice');
      final suppliers = await _fetchOptions(
        appState,
        'Supplier',
        'supplier_name',
      );
      final items = await _fetchOptions(appState, 'Item', 'item_name');
      final warehouses =
          appState.warehouses
              .where(
                (warehouse) =>
                    warehouse.name.isNotEmpty &&
                    !warehouse.isGroup &&
                    warehouse.isDisabled != true,
              )
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _series = series;
        _suppliers = suppliers;
        _items = items;
        _warehouses = warehouses;
        _selectedSeries = series.isNotEmpty ? series.first : null;
        _selectedWarehouse = appState.preferredWarehouse(warehouses);
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  WarehouseInfo? get _warehouseInfo {
    for (final warehouse in _warehouses) {
      if (warehouse.name == _selectedWarehouse) return warehouse;
    }
    return null;
  }

  double get _qty => double.tryParse(_qtyCtrl.text.trim()) ?? 0;
  double get _rate => double.tryParse(_rateCtrl.text.trim()) ?? 0;
  double get _total =>
      (_qty * _rate) +
      _additionalItems.fold<double>(0, (total, row) {
        final qty = double.tryParse(row.qtyController.text.trim()) ?? 0;
        final rate = double.tryParse(row.rateController.text.trim()) ?? 0;
        return total + (qty * rate);
      });

  List<Map<String, dynamic>> _buildItemsPayload() {
    Map<String, dynamic> itemPayload({
      required String itemCode,
      required double qty,
      double? rate,
      String? warehouse,
    }) {
      return {
        'item_code': itemCode.trim(),
        'qty': qty,
        if (rate != null && rate >= 0) 'rate': rate,
        if (_updateStock && warehouse?.trim().isNotEmpty == true)
          'warehouse': warehouse!.trim(),
      };
    }

    return [
      itemPayload(
        itemCode: _selectedItem!,
        qty: double.parse(_qtyCtrl.text.trim()),
        rate: double.tryParse(_rateCtrl.text.trim()),
        warehouse: _selectedWarehouse,
      ),
      ..._additionalItems.map(
        (row) => itemPayload(
          itemCode: row.itemCode!,
          qty: double.parse(row.qtyController.text.trim()),
          rate: double.tryParse(row.rateController.text.trim()),
          warehouse: row.warehouse ?? _selectedWarehouse,
        ),
      ),
    ];
  }

  Future<void> _pickDate({required bool dueDate}) async {
    final initial = dueDate ? _dueDate : _postingDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: dueDate ? _postingDate : DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      if (dueDate) {
        _dueDate = picked;
      } else {
        _postingDate = picked;
        if (_dueDate.isBefore(picked)) _dueDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dueDate.isBefore(_postingDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Due Date tidak boleh sebelum Date')),
      );
      return;
    }
    final invalidAdditional = _additionalItems.any((row) {
      final qty = double.tryParse(row.qtyController.text.trim());
      final rateText = row.rateController.text.trim();
      final rate = rateText.isEmpty ? 0 : double.tryParse(rateText);
      return row.itemCode == null ||
          qty == null ||
          qty <= 0 ||
          rate == null ||
          rate < 0 ||
          (_updateStock && (row.warehouse ?? _selectedWarehouse) == null);
    });
    if (invalidAdditional) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lengkapi semua tambahan item.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<PurchaseInvoiceState>().createPurchaseInvoice(
        supplier: _selectedSupplier!,
        items: _buildItemsPayload(),
        namingSeries: _selectedSeries!,
        postingDate: _postingDate,
        dueDate: _dueDate,
        updateStock: _updateStock,
        warehouse: _updateStock ? _selectedWarehouse : null,
        company: _warehouseInfo?.company,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchase Invoice draft berhasil dibuat'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membuat Purchase Invoice: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppColors.background,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  );

  Widget _dateField(String label, DateTime value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: InputDecorator(
        decoration: _decoration(label),
        child: Text(
          DateFormat('dd-MM-yyyy').format(value),
          style: const TextStyle(fontSize: 14),
        ),
      ),
    );
  }

  Widget _stockSettingsCard() {
    return PurchaseCreateSection(
      title: 'Stock Settings',
      subtitle: 'Atur update stok jika invoice langsung menerima barang.',
      icon: Icons.warehouse_outlined,
      accentColor: const Color(0xFF0EA5E9),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Update Stock'),
          subtitle: const Text('Aktifkan jika invoice langsung menambah stok'),
          value: _updateStock,
          onChanged: (value) => setState(() => _updateStock = value),
        ),
        if (_updateStock) ...[
          const SizedBox(height: 8),
          ErpItemAutocompleteField(
            label: 'Warehouse',
            selectedId: _selectedWarehouse,
            decoration: _decoration('Warehouse'),
            options: _warehouseSearchOptions(),
            onSelected: (value) => setState(() => _selectedWarehouse = value),
            validator: (value) => _updateStock && value == null
                ? 'Warehouse wajib dipilih'
                : null,
          ),
        ],
      ],
    );
  }

  List<ErpItemOption> _itemSearchOptions() {
    return _items
        .map((item) => ErpItemOption(id: item.id, label: item.label))
        .toList();
  }

  List<ErpItemOption> _supplierSearchOptions() {
    return _suppliers
        .map(
          (supplier) => ErpItemOption(id: supplier.id, label: supplier.label),
        )
        .toList();
  }

  List<ErpItemOption> _warehouseSearchOptions() {
    return _warehouses
        .map(
          (warehouse) =>
              ErpItemOption(id: warehouse.name, label: warehouse.name),
        )
        .toList();
  }

  static String _formatCurrency(double value) {
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 2,
    );
    return formatter.format(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        centerTitle: false,
        titleSpacing: 16,
        title: Text(
          'New Purchase Invoice',
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
              padding: TmsxResponsive.pagePadding(
                context,
                top: 16,
                bottom: 24,
              ).copyWith(bottom: 24 + MediaQuery.of(context).viewInsets.bottom),
              child: TmsxResponsiveBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PurchaseCreateHeader(
                      title: 'Buat Purchase Invoice',
                      subtitle: 'Catat tagihan supplier dan nilai pembelian.',
                      icon: Icons.request_quote_outlined,
                      accentColor: Color(0xFF0EA5E9),
                    ),
                    const SizedBox(height: 16),
                    if (_loadError != null) ...[
                      Card(
                        color: Colors.red.shade50,
                        child: ListTile(
                          title: Text(_loadError!),
                          trailing: IconButton(
                            onPressed: _loadOptions,
                            icon: const Icon(Icons.refresh),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.border),
                        boxShadow: AppColors.cardShadow,
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Purchase Invoice Info',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedSeries,
                            decoration: _decoration('Series'),
                            isExpanded: true,
                            items: _series
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(
                                      value,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _selectedSeries = value),
                            validator: (value) =>
                                value == null ? 'Series wajib dipilih' : null,
                          ),
                          const SizedBox(height: 12),
                          ErpItemAutocompleteField(
                            label: 'Supplier',
                            selectedId: _selectedSupplier,
                            decoration: _decoration('Supplier'),
                            options: _supplierSearchOptions(),
                            onSelected: (value) =>
                                setState(() => _selectedSupplier = value),
                            validator: (value) =>
                                value == null ? 'Supplier wajib dipilih' : null,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _dateField(
                                  'Date',
                                  _postingDate,
                                  () => _pickDate(dueDate: false),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _dateField(
                                  'Due Date',
                                  _dueDate,
                                  () => _pickDate(dueDate: true),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _stockSettingsCard(),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.border),
                        boxShadow: AppColors.cardShadow,
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Item Details',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ErpItemAutocompleteField(
                            label: 'Item',
                            selectedId: _selectedItem,
                            options: _itemSearchOptions(),
                            decoration: _decoration('Item'),
                            onSelected: (value) =>
                                setState(() => _selectedItem = value),
                            validator: (value) =>
                                value == null ? 'Item wajib dipilih' : null,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _qtyCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: _decoration('Accepted Qty'),
                                  validator: (value) {
                                    final qty = double.tryParse(
                                      value?.trim() ?? '',
                                    );
                                    return qty == null || qty <= 0
                                        ? 'Qty > 0'
                                        : null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: _rateCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: _decoration('Rate'),
                                  validator: (value) {
                                    final rate = double.tryParse(
                                      value?.trim() ?? '',
                                    );
                                    return rate == null || rate < 0
                                        ? 'Rate >= 0'
                                        : null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ..._additionalItems.asMap().entries.map((entry) {
                            final index = entry.key;
                            final row = entry.value;
                            return _AdditionalInvoiceItemCard(
                              index: index,
                              row: row,
                              itemItems: _itemSearchOptions(),
                              warehouseItems: _warehouseSearchOptions(),
                              updateStock: _updateStock,
                              defaultWarehouse: _selectedWarehouse,
                              decoration: _decoration,
                              onChanged: () => setState(() {}),
                              onRemove: () => _removeItemRow(index),
                            );
                          }),
                          OutlinedButton.icon(
                            onPressed: _addItemRow,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Tambah Item'),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.slate,
                                  ),
                                ),
                                Text(
                                  _formatCurrency(_total),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.all(TmsxResponsive.horizontalPadding(context)),
        child: TmsxResponsiveBody(
          child: PurchasePrimaryActionButton(
            label: 'Save Purchase Invoice',
            icon: Icons.save_alt_rounded,
            isLoading: _saving,
            onPressed: _loading || _loadError != null ? null : _save,
          ),
        ),
      ),
    );
  }
}

class _AdditionalInvoiceItemCard extends StatelessWidget {
  final int index;
  final _AdditionalInvoiceItemRow row;
  final List<ErpItemOption> itemItems;
  final List<ErpItemOption> warehouseItems;
  final bool updateStock;
  final String? defaultWarehouse;
  final InputDecoration Function(String label) decoration;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _AdditionalInvoiceItemCard({
    required this.index,
    required this.row,
    required this.itemItems,
    required this.warehouseItems,
    required this.updateStock,
    required this.defaultWarehouse,
    required this.decoration,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Item Tambahan ${index + 2}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Hapus item',
                onPressed: onRemove,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
          ErpItemAutocompleteField(
            label: 'Item',
            selectedId: row.itemCode,
            options: itemItems,
            decoration: decoration('Item'),
            onSelected: (value) {
              row.itemCode = value;
              onChanged();
            },
            validator: (value) => value == null ? 'Item wajib dipilih' : null,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: decoration('Accepted Qty'),
                  validator: (value) {
                    final qty = double.tryParse(value?.trim() ?? '');
                    return qty == null || qty <= 0 ? 'Qty > 0' : null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: row.rateController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: decoration('Rate'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final rate = double.tryParse(value.trim());
                    return rate == null || rate < 0 ? 'Rate >= 0' : null;
                  },
                ),
              ),
            ],
          ),
          if (updateStock) ...[
            const SizedBox(height: 10),
            ErpItemAutocompleteField(
              label: 'Warehouse',
              selectedId: row.warehouse ?? defaultWarehouse,
              decoration: decoration('Warehouse'),
              options: warehouseItems,
              onSelected: (value) {
                row.warehouse = value;
                onChanged();
              },
              validator: (value) =>
                  value == null ? 'Warehouse wajib dipilih' : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _AdditionalInvoiceItemRow {
  String? itemCode;
  String? warehouse;
  final TextEditingController qtyController;
  final TextEditingController rateController;

  _AdditionalInvoiceItemRow({
    this.warehouse,
    String qty = '1',
    String rate = '',
  }) : qtyController = TextEditingController(text: qty),
       rateController = TextEditingController(text: rate);

  void dispose() {
    qtyController.dispose();
    rateController.dispose();
  }
}

class _Option {
  final String id;
  final String label;

  const _Option(this.id, this.label);
}
