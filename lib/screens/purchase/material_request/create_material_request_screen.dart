import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/inventory_item.dart';
import '../../../models/warehouse_info.dart';
import '../../../state/purchasing/material_request_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/purchase_ui.dart';

class CreateMaterialRequestScreen extends StatefulWidget {
  final InventoryItem? initialItem;

  const CreateMaterialRequestScreen({super.key, this.initialItem});

  @override
  State<CreateMaterialRequestScreen> createState() =>
      _CreateMaterialRequestScreenState();
}

class _CreateMaterialRequestScreenState
    extends State<CreateMaterialRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _qtyCtrl = TextEditingController(text: '1');
  final List<_AdditionalItemRow> _additionalItems = [];

  List<String> _series = [];
  List<_Option> _items = [];
  List<String> _companies = [];
  List<WarehouseInfo> _warehouses = [];
  String? _selectedSeries;
  String _requestType = 'Purchase';
  String? _selectedItem;
  String? _selectedCompany;
  String? _selectedWarehouse;
  DateTime _transactionDate = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedItem = widget.initialItem?.sku;
    _selectedWarehouse = widget.initialItem?.warehouseId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    for (final row in _additionalItems) {
      row.dispose();
    }
    super.dispose();
  }

  void _addItemRow() {
    setState(() => _additionalItems.add(_AdditionalItemRow()));
  }

  void _removeItemRow(int index) {
    final row = _additionalItems.removeAt(index);
    row.dispose();
    setState(() {});
  }

  List<Map<String, dynamic>> _buildItemsPayload() {
    final scheduleDate = _transactionDate.toIso8601String().split('T').first;
    Map<String, dynamic> itemPayload({
      required String itemCode,
      required double qty,
      String? warehouse,
    }) {
      return {
        'item_code': itemCode.trim(),
        'qty': qty,
        'schedule_date': scheduleDate,
        if (warehouse?.trim().isNotEmpty == true)
          'warehouse': warehouse!.trim(),
      };
    }

    return [
      itemPayload(
        itemCode: _selectedItem!,
        qty: double.parse(_qtyCtrl.text.trim()),
        warehouse: _selectedWarehouse,
      ),
      ..._additionalItems.map(
        (row) => itemPayload(
          itemCode: row.itemCode!,
          qty: double.parse(row.qtyController.text.trim()),
          warehouse: row.warehouse ?? _selectedWarehouse,
        ),
      ),
    ];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appState = context.read<MaterialRequestState>();
      if (appState.warehouses.isEmpty) await appState.refreshWarehouses();
      if (appState.buyingCompanies.isEmpty) {
        await appState.loadBuyingFilterOptions();
      }
      final series = await appState.fetchNamingSeries('Material Request');
      final items = await _options(appState, 'Item', 'item_name');
      final companies = appState.buyingCompanies.isNotEmpty
          ? appState.buyingCompanies
          : await _names(appState, 'Company');
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
        _items = items;
        _companies = companies;
        _warehouses = warehouses;
        _selectedSeries = series.isNotEmpty ? series.first : null;
        _selectedItem ??= items.isNotEmpty ? items.first.id : null;
        _selectedCompany ??= appState.preferredCompany(companies);
        _selectedWarehouse ??= appState.preferredWarehouse(warehouses);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<_Option>> _options(
    MaterialRequestState appState,
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
          final label = row[labelField]?.toString() ?? id;
          return _Option(id, label);
        })
        .whereType<_Option>()
        .toList();
  }

  List<List<dynamic>>? _activeMasterFilters(String doctype) {
    if (doctype == 'Item') {
      return const [
        ['disabled', '=', 0],
      ];
    }
    return null;
  }

  Future<List<String>> _names(
    MaterialRequestState appState,
    String doctype,
  ) async {
    final rows = await appState.frappeService.fetchResource(
      doctype,
      fields: const ['name'],
      orderBy: 'name asc',
    );
    return rows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _transactionDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final invalidAdditional = _additionalItems.any((row) {
      final qty = double.tryParse(row.qtyController.text.trim());
      return row.itemCode == null || qty == null || qty <= 0;
    });
    if (invalidAdditional) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lengkapi semua tambahan item dan quantity.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<MaterialRequestState>().createMaterialRequest(
        materialRequestType: _requestType,
        items: _buildItemsPayload(),
        transactionDate: _transactionDate,
        scheduleDate: _transactionDate,
        company: _selectedCompany,
        warehouse: _selectedWarehouse,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Material Request draft berhasil dibuat'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membuat Material Request: $error'),
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

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
    IconData? icon,
  }) {
    return PurchaseCreateSection(
      title: title,
      icon: icon ?? Icons.assignment_outlined,
      accentColor: const Color(0xFFF59E0B),
      children: children,
    );
  }

  List<ErpItemOption> _itemSearchOptions() {
    return _items
        .map((item) => ErpItemOption(id: item.id, label: item.label))
        .toList();
  }

  List<ErpItemOption> _companySearchOptions() {
    return _companies
        .map((company) => ErpItemOption(id: company, label: company))
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
          'New Material Request',
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
                        title: 'Buat Material Request',
                        subtitle: 'Ajukan kebutuhan material sesuai warehouse.',
                        icon: Icons.assignment_outlined,
                        accentColor: Color(0xFFF59E0B),
                      ),
                      const SizedBox(height: 16),
                      if (widget.initialItem != null) ...[
                        _InfoCard(initialItem: widget.initialItem),
                        const SizedBox(height: 16),
                      ],
                      _sectionCard(
                        title: 'Request Information',
                        icon: Icons.assignment_outlined,
                        children: [
                          _dropdownField(
                            label: 'Series',
                            value: _selectedSeries,
                            items: _seriesItems(),
                            onChanged: (value) =>
                                setState(() => _selectedSeries = value),
                            icon: Icons.tag_outlined,
                          ),
                          const SizedBox(height: 12),
                          _dropdownField(
                            label: 'Purpose',
                            value: _requestType,
                            items: const [
                              DropdownMenuItem(
                                value: 'Purchase',
                                child: Text('Purchase'),
                              ),
                              DropdownMenuItem(
                                value: 'Material Transfer',
                                child: Text('Material Transfer'),
                              ),
                              DropdownMenuItem(
                                value: 'Material Issue',
                                child: Text('Material Issue'),
                              ),
                              DropdownMenuItem(
                                value: 'Manufacture',
                                child: Text('Manufacture'),
                              ),
                              DropdownMenuItem(
                                value: 'Customer Provided',
                                child: Text('Customer Provided'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _requestType = value);
                              }
                            },
                            icon: Icons.flag_outlined,
                          ),
                          const SizedBox(height: 12),
                          _dateField(
                            'Transaction Date',
                            _transactionDate,
                            _pickDate,
                          ),
                          const SizedBox(height: 12),
                          ErpItemAutocompleteField(
                            label: 'Company',
                            selectedId: _selectedCompany,
                            options: _companySearchOptions(),
                            decoration: _decoration(
                              'Company',
                              prefixIcon: Icons.business_outlined,
                            ),
                            onSelected: (value) =>
                                setState(() => _selectedCompany = value),
                            validator: (value) =>
                                value == null ? 'Company wajib dipilih' : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionCard(
                        title: 'Item Details',
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
                          TextFormField(
                            controller: _qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: _decoration(
                              'Quantity',
                              prefixIcon: Icons.numbers_rounded,
                            ),
                            validator: (value) {
                              final qty = double.tryParse(value?.trim() ?? '');
                              if (qty == null || qty <= 0) {
                                return 'Qty harus lebih dari 0';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          ErpItemAutocompleteField(
                            label: 'Target Warehouse',
                            selectedId: _selectedWarehouse,
                            options: _warehouseSearchOptions(),
                            decoration: _decoration(
                              'Target Warehouse',
                              prefixIcon: Icons.warehouse_outlined,
                            ),
                            onSelected: (value) =>
                                setState(() => _selectedWarehouse = value),
                          ),
                          const SizedBox(height: 12),
                          ..._additionalItems.asMap().entries.map((entry) {
                            final index = entry.key;
                            final row = entry.value;
                            return _AdditionalItemCard(
                              index: index,
                              row: row,
                              itemItems: _itemSearchOptions(),
                              warehouseItems: _warehouseSearchOptions(),
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
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SummaryCard(
                        requestType: _requestType,
                        transactionDate: _transactionDate,
                        company: _selectedCompany,
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
            label: 'Save Material Request',
            icon: Icons.save_alt_rounded,
            isLoading: _saving,
            onPressed: _loading || _error != null ? null : _save,
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final InventoryItem? initialItem;

  const _InfoCard({required this.initialItem});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          const Icon(Icons.assignment_add, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              initialItem == null
                  ? 'Buat request barang untuk kebutuhan stok.'
                  : 'Prefill dari low stock: ${initialItem!.name}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String requestType;
  final DateTime transactionDate;
  final String? company;
  final String? warehouse;

  const _SummaryCard({
    required this.requestType,
    required this.transactionDate,
    required this.company,
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
          _SummaryMetric(label: 'Purpose', value: requestType),
          _SummaryMetric(
            label: 'Date',
            value: DateFormat('dd-MM-yyyy').format(transactionDate),
          ),
          _SummaryMetric(label: 'Company', value: company ?? '-'),
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

class _AdditionalItemCard extends StatelessWidget {
  final int index;
  final _AdditionalItemRow row;
  final List<ErpItemOption> itemItems;
  final List<ErpItemOption> warehouseItems;
  final String? defaultWarehouse;
  final InputDecoration Function(
    String label, {
    String? hintText,
    IconData? prefixIcon,
  })
  decoration;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _AdditionalItemCard({
    required this.index,
    required this.row,
    required this.itemItems,
    required this.warehouseItems,
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
          TextFormField(
            controller: row.qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: decoration('Quantity'),
            validator: (value) {
              final qty = double.tryParse(value?.trim() ?? '');
              return qty == null || qty <= 0 ? 'Qty harus lebih dari 0' : null;
            },
          ),
          const SizedBox(height: 10),
          ErpItemAutocompleteField(
            label: 'Target Warehouse',
            selectedId: row.warehouse ?? defaultWarehouse,
            decoration: decoration('Target Warehouse'),
            options: warehouseItems,
            onSelected: (value) {
              row.warehouse = value;
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

class _AdditionalItemRow {
  String? itemCode;
  String? warehouse;
  final TextEditingController qtyController;

  _AdditionalItemRow() : qtyController = TextEditingController(text: '1');

  void dispose() {
    qtyController.dispose();
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
