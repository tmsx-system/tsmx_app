import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/warehouse_info.dart';
import '../../../state/purchasing/purchase_receipt_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/purchase_ui.dart';

class CreatePurchaseReceiptScreen extends StatefulWidget {
  const CreatePurchaseReceiptScreen({super.key});

  @override
  State<CreatePurchaseReceiptScreen> createState() =>
      _CreatePurchaseReceiptScreenState();
}

class _CreatePurchaseReceiptScreenState
    extends State<CreatePurchaseReceiptScreen> {
  static const String _doctype = 'Purchase Receipt';

  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController(text: '1');
  final _rejectedQtyCtrl = TextEditingController(text: '0');
  final _rateCtrl = TextEditingController();
  final List<_AdditionalReceiptItemRow> _additionalItems = [];

  List<String> _series = [];
  List<_Option> _suppliers = [];
  List<_Option> _items = [];
  List<WarehouseInfo> _warehouses = [];
  String? _selectedSeries;
  String? _selectedSupplier;
  String? _selectedItem;
  String? _selectedWarehouse;
  DateTime _date = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _qtyCtrl.addListener(_refreshTotal);
    _rejectedQtyCtrl.addListener(_refreshTotal);
    _rateCtrl.addListener(_refreshTotal);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _qtyCtrl.removeListener(_refreshTotal);
    _rejectedQtyCtrl.removeListener(_refreshTotal);
    _rateCtrl.removeListener(_refreshTotal);
    _qtyCtrl.dispose();
    _rejectedQtyCtrl.dispose();
    _rateCtrl.dispose();
    for (final row in _additionalItems) {
      row.dispose();
    }
    super.dispose();
  }

  void _refreshTotal() => setState(() {});

  void _addItemRow() {
    final row = _AdditionalReceiptItemRow(warehouse: _selectedWarehouse);
    row.qtyController.addListener(_refreshTotal);
    row.rateController.addListener(_refreshTotal);
    row.rejectedQtyController.addListener(_refreshTotal);
    setState(() => _additionalItems.add(row));
  }

  void _removeItemRow(int index) {
    final row = _additionalItems.removeAt(index);
    row.dispose();
    _refreshTotal();
  }

  Future<List<_Option>> _options(
    PurchaseReceiptState appState,
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
          return id.isEmpty
              ? null
              : _Option(id, row[labelField]?.toString() ?? id);
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appState = context.read<PurchaseReceiptState>();
      if (appState.warehouses.isEmpty) await appState.refreshWarehouses();
      final series = await appState.fetchNamingSeries(_doctype);
      final items = await _options(appState, 'Item', 'item_name');
      final suppliers = await _options(appState, 'Supplier', 'supplier_name');
      final warehouses =
          appState.warehouses
              .where(
                (w) => w.name.isNotEmpty && !w.isGroup && w.isDisabled != true,
              )
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));

      if (!mounted) return;
      setState(() {
        _series = series;
        _items = items;
        _suppliers = suppliers;
        _warehouses = warehouses;
        _selectedSeries = series.isNotEmpty ? series.first : null;
        _selectedWarehouse = appState.preferredWarehouse(warehouses);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  WarehouseInfo? get _warehouse {
    for (final warehouse in _warehouses) {
      if (warehouse.name == _selectedWarehouse) return warehouse;
    }
    return null;
  }

  double get _qty => double.tryParse(_qtyCtrl.text.trim()) ?? 0;
  double get _rejectedQty => double.tryParse(_rejectedQtyCtrl.text.trim()) ?? 0;
  double get _rate => double.tryParse(_rateCtrl.text.trim()) ?? 0;
  double get _total =>
      (_qty * _rate) +
      _additionalItems.fold<double>(0, (total, row) {
        final qty = double.tryParse(row.qtyController.text.trim()) ?? 0;
        final rate = double.tryParse(row.rateController.text.trim()) ?? 0;
        return total + (qty * rate);
      });
  double get _totalAcceptedQty =>
      _qty +
      _additionalItems.fold<double>(0, (total, row) {
        return total + (double.tryParse(row.qtyController.text.trim()) ?? 0);
      });
  double get _totalRejectedQty =>
      _rejectedQty +
      _additionalItems.fold<double>(0, (total, row) {
        return total +
            (double.tryParse(row.rejectedQtyController.text.trim()) ?? 0);
      });

  List<Map<String, dynamic>> _buildItemsPayload() {
    Map<String, dynamic> itemPayload({
      required String itemCode,
      required double qty,
      required String warehouse,
      double? rate,
      double? rejectedQty,
    }) {
      return {
        'item_code': itemCode.trim(),
        'qty': qty,
        'warehouse': warehouse.trim(),
        if (rate != null && rate >= 0) 'rate': rate,
        if (rejectedQty != null && rejectedQty > 0) 'rejected_qty': rejectedQty,
      };
    }

    return [
      itemPayload(
        itemCode: _selectedItem!,
        qty: double.parse(_qtyCtrl.text.trim()),
        warehouse: _selectedWarehouse!,
        rate: double.tryParse(_rateCtrl.text.trim()),
        rejectedQty: double.tryParse(_rejectedQtyCtrl.text.trim()),
      ),
      ..._additionalItems.map(
        (row) => itemPayload(
          itemCode: row.itemCode!,
          qty: double.parse(row.qtyController.text.trim()),
          warehouse: row.warehouse ?? _selectedWarehouse!,
          rate: double.tryParse(row.rateController.text.trim()),
          rejectedQty: double.tryParse(row.rejectedQtyController.text.trim()),
        ),
      ),
    ];
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final invalidAdditional = _additionalItems.any((row) {
      final qty = double.tryParse(row.qtyController.text.trim());
      final rejectedQty = double.tryParse(
        row.rejectedQtyController.text.trim(),
      );
      final rateText = row.rateController.text.trim();
      final rate = rateText.isEmpty ? 0 : double.tryParse(rateText);
      return row.itemCode == null ||
          row.warehouse == null ||
          qty == null ||
          qty <= 0 ||
          rejectedQty == null ||
          rejectedQty < 0 ||
          rate == null ||
          rate < 0;
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
      await context.read<PurchaseReceiptState>().createPurchaseReceipt(
        supplier: _selectedSupplier!,
        items: _buildItemsPayload(),
        namingSeries: _selectedSeries!,
        warehouse: _selectedWarehouse!,
        postingDate: _date,
        company: _warehouse?.company,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_doctype draft berhasil dibuat'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membuat $_doctype: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(
    String label, {
    String? hintText,
    IconData? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.14),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _dropdownField({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    IconData? icon,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: _decoration(label, prefixIcon: icon),
      items: items,
      onChanged: items.isEmpty ? null : onChanged,
      validator: validator,
    );
  }

  Widget _dateField(String label, DateTime value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: _decoration(
          label,
          prefixIcon: Icons.calendar_today_outlined,
        ),
        child: Text(DateFormat('dd-MM-yyyy').format(value)),
      ),
    );
  }

  Widget _readOnlyField(String label, String value, {IconData? icon}) {
    return InputDecorator(
      decoration: _decoration(label, prefixIcon: icon),
      child: Text(
        value.isEmpty ? '-' : value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
    IconData? icon,
  }) {
    return PurchaseCreateSection(
      title: title,
      icon: icon ?? Icons.inventory_2_outlined,
      accentColor: const Color(0xFF2563EB),
      children: children,
    );
  }

  List<DropdownMenuItem<String>> _seriesItems() {
    return _series
        .map(
          (series) => DropdownMenuItem(
            value: series,
            child: Text(series, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList();
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

  static String _formatNumber(double value) {
    final formatter = NumberFormat('#,##0.##', 'id_ID');
    return formatter.format(value);
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
        title: const Text(
          'New Purchase Receipt',
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
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _load)
          : SingleChildScrollView(
              padding: TmsxResponsive.pagePadding(
                context,
                top: 16,
                bottom: 24,
              ).copyWith(bottom: 24 + MediaQuery.of(context).viewInsets.bottom),
              child: TmsxResponsiveBody(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PurchaseCreateHeader(
                        title: 'Buat Purchase Receipt',
                        subtitle: 'Catat penerimaan barang dari supplier.',
                        icon: Icons.local_shipping_outlined,
                        accentColor: Color(0xFF2563EB),
                      ),
                      const SizedBox(height: 16),
                      _sectionCard(
                        title: 'Receipt Information',
                        icon: Icons.receipt_long_outlined,
                        children: [
                          _dropdownField(
                            label: 'Series',
                            value: _selectedSeries,
                            items: _seriesItems(),
                            onChanged: (value) =>
                                setState(() => _selectedSeries = value),
                            icon: Icons.tag_outlined,
                            validator: (value) =>
                                value == null ? 'Series wajib dipilih' : null,
                          ),
                          const SizedBox(height: 12),
                          ErpItemAutocompleteField(
                            label: 'Supplier',
                            selectedId: _selectedSupplier,
                            options: _supplierSearchOptions(),
                            decoration: _decoration(
                              'Supplier',
                              prefixIcon: Icons.storefront_outlined,
                            ),
                            onSelected: (value) =>
                                setState(() => _selectedSupplier = value),
                            validator: (value) =>
                                value == null ? 'Supplier wajib dipilih' : null,
                          ),
                          const SizedBox(height: 12),
                          _dateField('Posting Date', _date, _pickDate),
                          const SizedBox(height: 12),
                          _readOnlyField(
                            'Company',
                            _warehouse?.company ?? '-',
                            icon: Icons.business_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionCard(
                        title: 'Item Receipt',
                        icon: Icons.inventory_2_outlined,
                        children: [
                          ErpItemAutocompleteField(
                            label: 'Item',
                            selectedId: _selectedItem,
                            options: _itemSearchOptions(),
                            onSelected: (value) =>
                                setState(() => _selectedItem = value),
                            decoration: _decoration(
                              'Item',
                              prefixIcon: Icons.search_rounded,
                            ),
                            validator: (value) =>
                                value == null ? 'Item wajib dipilih' : null,
                          ),
                          const SizedBox(height: 12),
                          ErpItemAutocompleteField(
                            label: 'Accepted Warehouse',
                            selectedId: _selectedWarehouse,
                            options: _warehouseSearchOptions(),
                            decoration: _decoration(
                              'Accepted Warehouse',
                              prefixIcon: Icons.warehouse_outlined,
                            ),
                            onSelected: (value) =>
                                setState(() => _selectedWarehouse = value),
                            validator: (value) => value == null
                                ? 'Warehouse wajib dipilih'
                                : null,
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
                                  decoration: _decoration(
                                    'Accepted Qty',
                                    prefixIcon: Icons.numbers_rounded,
                                  ),
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
                                  controller: _rejectedQtyCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: _decoration('Rejected Qty'),
                                  validator: (value) {
                                    final qty = double.tryParse(
                                      value?.trim() ?? '',
                                    );
                                    return qty == null || qty < 0
                                        ? 'Qty >= 0'
                                        : null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _rateCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: _decoration(
                              'Rate',
                              prefixIcon: Icons.payments_outlined,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return null;
                              }
                              final rate = double.tryParse(value.trim());
                              return rate == null || rate < 0
                                  ? 'Rate >= 0'
                                  : null;
                            },
                          ),
                          const SizedBox(height: 12),
                          ..._additionalItems.asMap().entries.map((entry) {
                            final index = entry.key;
                            final row = entry.value;
                            return _AdditionalReceiptItemCard(
                              index: index,
                              row: row,
                              itemItems: _itemSearchOptions(),
                              warehouseItems: _warehouseSearchOptions(),
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
                        ],
                      ),
                      const SizedBox(height: 16),
                      _ReceiptSummaryCard(
                        qty: _formatNumber(_totalAcceptedQty),
                        rejectedQty: _formatNumber(_totalRejectedQty),
                        total: _formatCurrency(_total),
                        warehouse: _selectedWarehouse,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.all(TmsxResponsive.horizontalPadding(context)),
        child: TmsxResponsiveBody(
          child: PurchasePrimaryActionButton(
            label: 'Save Purchase Receipt',
            icon: Icons.save_alt_rounded,
            isLoading: _saving,
            onPressed: _loading || _error != null ? null : _save,
          ),
        ),
      ),
    );
  }
}

class _ReceiptSummaryCard extends StatelessWidget {
  final String qty;
  final String rejectedQty;
  final String total;
  final String? warehouse;

  const _ReceiptSummaryCard({
    required this.qty,
    required this.rejectedQty,
    required this.total,
    required this.warehouse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 18,
        runSpacing: 10,
        children: [
          _SummaryMetric(label: 'Accepted Qty', value: qty),
          _SummaryMetric(label: 'Rejected Qty', value: rejectedQty),
          _SummaryMetric(label: 'Total', value: total),
          _SummaryMetric(label: 'Warehouse', value: warehouse ?? '-'),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 145,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.slate),
          ),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdditionalReceiptItemCard extends StatelessWidget {
  final int index;
  final _AdditionalReceiptItemRow row;
  final List<ErpItemOption> itemItems;
  final List<ErpItemOption> warehouseItems;
  final InputDecoration Function(
    String label, {
    String? hintText,
    IconData? prefixIcon,
  })
  decoration;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _AdditionalReceiptItemCard({
    required this.index,
    required this.row,
    required this.itemItems,
    required this.warehouseItems,
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
          ErpItemAutocompleteField(
            label: 'Accepted Warehouse',
            selectedId: row.warehouse,
            decoration: decoration('Accepted Warehouse'),
            options: warehouseItems,
            onSelected: (value) {
              row.warehouse = value;
              onChanged();
            },
            validator: (value) =>
                value == null ? 'Warehouse wajib dipilih' : null,
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
                  controller: row.rejectedQtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: decoration('Rejected Qty'),
                  validator: (value) {
                    final qty = double.tryParse(value?.trim() ?? '');
                    return qty == null || qty < 0 ? 'Qty >= 0' : null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: row.rateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: decoration('Rate'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return null;
              final rate = double.tryParse(value.trim());
              return rate == null || rate < 0 ? 'Rate >= 0' : null;
            },
          ),
        ],
      ),
    );
  }
}

class _AdditionalReceiptItemRow {
  String? itemCode;
  String? warehouse;
  final TextEditingController qtyController;
  final TextEditingController rejectedQtyController;
  final TextEditingController rateController;

  _AdditionalReceiptItemRow({
    this.warehouse,
    String qty = '1',
    String rejectedQty = '0',
    String rate = '',
  }) : qtyController = TextEditingController(text: qty),
       rejectedQtyController = TextEditingController(text: rejectedQty),
       rateController = TextEditingController(text: rate);

  void dispose() {
    qtyController.dispose();
    rejectedQtyController.dispose();
    rateController.dispose();
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option {
  final String id;
  final String label;

  const _Option(this.id, this.label);
}
