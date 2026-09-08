import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/inventory_item.dart';
import '../../../models/purchase_order.dart';
import '../../../models/warehouse_info.dart';
import '../../../state/purchasing/purchase_order_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/purchase_ui.dart';

class CreatePurchaseOrderScreen extends StatefulWidget {
  final String? editOrderId;
  final InventoryItem? initialItem;

  const CreatePurchaseOrderScreen({
    super.key,
    this.editOrderId,
    this.initialItem,
  });

  bool get isEditMode => editOrderId != null;

  @override
  State<CreatePurchaseOrderScreen> createState() =>
      _CreatePurchaseOrderScreenState();
}

class _CreatePurchaseOrderScreenState extends State<CreatePurchaseOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supplierCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _uomCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _notedCtrl = TextEditingController();
  final List<_AdditionalPurchaseItemRow> _additionalItems = [];

  TextEditingController? _itemTextController;
  String? _initialItemText;
  String? _selectedItemCode;
  String? _selectedWarehouse;
  String? _selectedCompany;
  String? _selectedSeries;
  DateTime _selectedDate = DateTime.now();
  DateTime _requiredByDate = DateTime.now();

  bool _isLoadingSelectors = true;
  bool _isSaving = false;
  String? _supplierError;
  String? _itemError;

  List<WarehouseInfo> _warehouseOptions = [];
  List<String> _companyOptions = [];
  List<String> _seriesOptions = [];
  List<_SupplierOption> _supplierOptions = [];
  List<_ItemOption> _itemOptions = [];

  @override
  void initState() {
    super.initState();
    _qtyCtrl.addListener(_calculateTotal);
    _rateCtrl.addListener(_calculateTotal);
    _discountCtrl.addListener(_calculateTotal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSelectors();
    });
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _qtyCtrl.dispose();
    _uomCtrl.dispose();
    _rateCtrl.removeListener(_calculateTotal);
    _rateCtrl.dispose();
    _discountCtrl.removeListener(_calculateTotal);
    _discountCtrl.dispose();
    _notedCtrl.dispose();
    _itemTextController?.dispose();
    for (final row in _additionalItems) {
      row.dispose();
    }
    super.dispose();
  }

  void _calculateTotal() {
    setState(() {});
  }

  void _addItemRow() {
    final row = _AdditionalPurchaseItemRow(warehouse: _selectedWarehouse);
    row.qtyController.addListener(_calculateTotal);
    row.rateController.addListener(_calculateTotal);
    row.discountController.addListener(_calculateTotal);
    setState(() => _additionalItems.add(row));
  }

  void _removeItemRow(int index) {
    final row = _additionalItems.removeAt(index);
    row.dispose();
    _calculateTotal();
  }

  Future<List<_SupplierOption>> _fetchSupplierOptions(
    PurchaseOrderState appState,
  ) async {
    try {
      final supplierData = await appState.frappeService.fetchResource(
        'Supplier',
        fields: const ['name', 'supplier_name'],
        filters: const [
          ['disabled', '=', 0],
        ],
        orderBy: 'supplier_name asc',
        limit: 200,
      );
      return supplierData
          .map((row) {
            final name = row['name']?.toString() ?? '';
            final label = row['supplier_name']?.toString() ?? name;
            if (name.isEmpty) return null;
            return _SupplierOption(id: name, label: label);
          })
          .whereType<_SupplierOption>()
          .toList();
    } catch (_) {
      try {
        final supplierData = await appState.frappeService.fetchResource(
          'Supplier',
          fields: const ['name'],
          orderBy: 'name asc',
          limit: 200,
        );
        return supplierData
            .map((row) {
              final name = row['name']?.toString() ?? '';
              if (name.isEmpty) return null;
              return _SupplierOption(id: name, label: name);
            })
            .whereType<_SupplierOption>()
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  _SupplierOption? _selectedSupplierOption() {
    final id = _supplierCtrl.text.trim();
    if (id.isEmpty) return null;
    for (final supplier in _supplierOptions) {
      if (supplier.id == id) return supplier;
    }
    return _SupplierOption(id: id, label: id);
  }

  String _selectedSupplierLabel() {
    final supplier = _selectedSupplierOption();
    final label = supplier?.label.trim() ?? '';
    final id = _supplierCtrl.text.trim();
    if (label.isEmpty || label == id) return '';
    return label;
  }

  void _clearSupplier() {
    setState(() {
      _supplierCtrl.clear();
      _supplierError = null;
    });
  }

  String? _companyForWarehouse(String? warehouseName) {
    final selected = warehouseName?.trim() ?? '';
    if (selected.isEmpty) return null;
    for (final warehouse in _warehouseOptions) {
      if (warehouse.name == selected && warehouse.company.trim().isNotEmpty) {
        return warehouse.company.trim();
      }
    }
    return null;
  }

  List<String> get _visibleCompanyOptions {
    final values = {
      ..._companyOptions,
      if (_selectedCompany?.trim().isNotEmpty == true) _selectedCompany!.trim(),
    }.where((company) => company.trim().isNotEmpty).toList();
    values.sort();
    return values;
  }

  _SupplierOption? _supplierOptionFromRow(Map<String, dynamic> row) {
    final name = row['name']?.toString().trim() ?? '';
    final label = row['supplier_name']?.toString().trim() ?? name;
    if (name.isEmpty) return null;
    return _SupplierOption(id: name, label: label);
  }

  Future<List<ErpItemOption>> _searchSupplierOptions(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];
    final appState = context.read<PurchaseOrderState>();
    try {
      final rows = await appState.frappeService.fetchResource(
        'Supplier',
        fields: const ['name', 'supplier_name'],
        filters: const [
          ['disabled', '=', 0],
        ],
        orFilters: [
          ['name', 'like', '%$normalized%'],
          ['supplier_name', 'like', '%$normalized%'],
        ],
        orderBy: 'supplier_name asc, name asc',
        limit: 50,
      );
      return rows
          .map(_supplierOptionFromRow)
          .whereType<_SupplierOption>()
          .map(
            (supplier) => ErpItemOption(id: supplier.id, label: supplier.label),
          )
          .toList();
    } catch (_) {
      final rows = await appState.frappeService.fetchResource(
        'Supplier',
        fields: const ['name'],
        orFilters: [
          ['name', 'like', '%$normalized%'],
        ],
        orderBy: 'name asc',
        limit: 50,
      );
      return rows
          .map(_supplierOptionFromRow)
          .whereType<_SupplierOption>()
          .map(
            (supplier) => ErpItemOption(id: supplier.id, label: supplier.label),
          )
          .toList();
    }
  }

  Future<List<_ItemOption>> _fetchItemOptions(
    PurchaseOrderState appState,
  ) async {
    try {
      final itemData = await appState.fetchPurchasableItems(limit: 200);
      return itemData.map(_itemOptionFromRow).whereType<_ItemOption>().toList();
    } catch (_) {
      return [];
    }
  }

  _ItemOption? _itemOptionFromRow(Map<String, dynamic> row) {
    final itemCode = row['item_code']?.toString().trim() ?? '';
    final name = row['name']?.toString().trim() ?? '';
    final code = itemCode.isNotEmpty ? itemCode : name;
    final itemName = row['item_name']?.toString().trim() ?? code;
    final uom = row['purchase_uom']?.toString().trim().isNotEmpty == true
        ? row['purchase_uom']!.toString().trim()
        : row['stock_uom']?.toString().trim() ?? '';
    if (code.isEmpty) return null;
    return _ItemOption(code: code, label: '$itemName ($code)', uom: uom);
  }

  Future<Iterable<_ItemOption>> _searchItemOptions(String value) async {
    final query = value.trim();
    if (query.isEmpty) return _itemOptions.take(20);

    final rows = await context.read<PurchaseOrderState>().fetchPurchasableItems(
      query: query,
      limit: 50,
    );
    final remoteOptions = rows
        .map(_itemOptionFromRow)
        .whereType<_ItemOption>()
        .toList();
    if (remoteOptions.isNotEmpty) return remoteOptions;

    final needle = query.toLowerCase();
    return _itemOptions.where((option) {
      return option.label.toLowerCase().contains(needle) ||
          option.code.toLowerCase().contains(needle);
    });
  }

  Future<_SupplierOption?> _showSupplierSelectSheet() async {
    final result = await showModalBottomSheet<_SupplierOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        Future<List<_SupplierOption>> loadOptions(String query) async {
          if (query.trim().isEmpty) return _supplierOptions.take(30).toList();
          final rows = await _searchSupplierOptions(query);
          return rows
              .map((row) => _SupplierOption(id: row.id, label: row.label))
              .toList();
        }

        return _PurchaseSelectSheet<_SupplierOption>(
          title: 'Pilih Supplier',
          subtitle: 'Cari supplier berdasarkan nama atau kode.',
          icon: Icons.store_mall_directory_outlined,
          searchHint: 'Search supplier',
          loadOptions: loadOptions,
          selectedId: _supplierCtrl.text.trim(),
          idOf: (supplier) => supplier.id,
          titleOf: (supplier) => supplier.label,
          subtitleOf: (supplier) => supplier.id,
        );
      },
    );
    return result;
  }

  Future<_ItemOption?> _showItemSelectSheet({
    required String title,
    String? selectedCode,
  }) async {
    final result = await showModalBottomSheet<_ItemOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        Future<List<_ItemOption>> loadOptions(String query) async {
          final options = await _searchItemOptions(query);
          return options.toList();
        }

        return _PurchaseSelectSheet<_ItemOption>(
          title: title,
          subtitle: 'Cari item pembelian berdasarkan nama atau kode.',
          icon: Icons.inventory_2_outlined,
          searchHint: 'Search item name or item code',
          loadOptions: loadOptions,
          selectedId: selectedCode,
          idOf: (item) => item.code,
          titleOf: (item) => item.name,
          subtitleOf: (item) =>
              item.uom.isEmpty ? item.code : '${item.code} • ${item.uom}',
        );
      },
    );
    return result;
  }

  Future<void> _selectSupplier() async {
    final supplier = await _showSupplierSelectSheet();
    if (supplier == null || !mounted) return;
    setState(() {
      _supplierCtrl.text = supplier.id;
      _supplierError = null;
    });
  }

  Future<void> _selectPrimaryItem() async {
    final item = await _showItemSelectSheet(
      title: 'Pilih Item',
      selectedCode: _selectedItemCode,
    );
    if (item == null || !mounted) return;
    setState(() {
      _selectedItemCode = item.code;
      _initialItemText = item.label;
      _uomCtrl.text = item.uom;
      _itemTextController?.text = item.label;
      _itemError = null;
    });
  }

  Future<void> _selectAdditionalItem(_AdditionalPurchaseItemRow row) async {
    final item = await _showItemSelectSheet(
      title: 'Pilih Item Tambahan',
      selectedCode: row.itemCode,
    );
    if (item == null || !mounted) return;
    setState(() {
      row.itemCode = item.code;
      row.itemTextController.text = item.label;
      row.uomController.text = item.uom;
    });
  }

  Future<void> _loadSelectors() async {
    final appState = context.read<PurchaseOrderState>();
    setState(() {
      _isLoadingSelectors = true;
    });

    try {
      if (appState.warehouses.isEmpty) {
        await appState.refreshWarehouses();
      }
      final warehouses = appState.warehouses.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _warehouseOptions = warehouses
          .where((warehouse) => warehouse.name.trim().isNotEmpty)
          .toList();
      _selectedWarehouse = appState.preferredWarehouse(_warehouseOptions);
      _companyOptions = {
        ...appState.buyingCompanies,
        ..._warehouseOptions.map((warehouse) => warehouse.company),
      }.where((company) => company.trim().isNotEmpty).toList()..sort();
      _selectedCompany =
          _companyForWarehouse(_selectedWarehouse) ??
          appState.preferredCompany(_companyOptions) ??
          (_companyOptions.isNotEmpty ? _companyOptions.first : null);

      final suppliers = await _fetchSupplierOptions(appState);
      final items = await _fetchItemOptions(appState);
      final series = await appState.fetchNamingSeries('Purchase Order');

      if (!mounted) return;
      setState(() {
        _supplierOptions = suppliers;
        _itemOptions = items;
        _seriesOptions = series;
        _selectedSeries = series.isNotEmpty ? series.first : null;
        if (!widget.isEditMode && widget.initialItem != null) {
          final item = widget.initialItem!;
          _selectedItemCode = item.sku;
          _selectedWarehouse = item.warehouseId.trim().isNotEmpty
              ? item.warehouseId
              : _selectedWarehouse;
          _selectedCompany =
              _companyForWarehouse(_selectedWarehouse) ?? _selectedCompany;
          _qtyCtrl.text = _recommendedPurchaseQty(item).toString();
          _uomCtrl.text = '';
          _initialItemText = item.name.trim().isNotEmpty
              ? '${item.name} (${item.sku})'
              : item.sku;
          _itemTextController?.text = _initialItemText!;
        }
      });
      if (widget.isEditMode) {
        final editingOrder = await appState.loadPurchaseOrderDetail(
          widget.editOrderId!,
        );
        if (!mounted) return;
        _applyEditingOrder(editingOrder);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSelectors = false;
        });
      }
    }
  }

  int _recommendedPurchaseQty(InventoryItem item) {
    if (item.minStockThreshold <= 0) {
      return item.quantity <= 0 ? 1 : item.quantity;
    }
    final deficit = item.minStockThreshold - item.quantity;
    return deficit <= 0 ? 1 : deficit;
  }

  void _applyEditingOrder(PurchaseOrder order) {
    final firstItem = order.items.isNotEmpty ? order.items.first : null;
    setState(() {
      _supplierCtrl.text = order.supplierId;
      _selectedDate = _parseDate(order.eta) ?? _selectedDate;
      _requiredByDate = _selectedDate;
      if (firstItem != null) {
        _selectedItemCode = firstItem.itemCode.isNotEmpty
            ? firstItem.itemCode
            : firstItem.itemName;
        _qtyCtrl.text = firstItem.qty.toString();
        _rateCtrl.text = firstItem.rate > 0 ? firstItem.rate.toString() : '';
        if (firstItem.warehouse.isNotEmpty) {
          _selectedWarehouse = firstItem.warehouse;
        }
        _initialItemText = firstItem.itemCode.isNotEmpty
            ? '${firstItem.itemName} (${firstItem.itemCode})'
            : firstItem.itemName;
        _itemTextController?.text = _initialItemText!;
      }
      _supplierError = null;
      _itemError = null;
    });
  }

  DateTime? _parseDate(String rawDate) {
    final trimmed = rawDate.trim();
    if (trimmed.isEmpty) return null;
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;
    final parts = trimmed.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  String get _formattedTotal {
    final qty = _parseNumber(_qtyCtrl.text);
    final rate = _parseNumber(_rateCtrl.text);
    final discount = _parseNumber(_discountCtrl.text);
    final effectiveRate = (rate - discount)
        .clamp(0, double.infinity)
        .toDouble();
    final total =
        (qty * effectiveRate) +
        _additionalItems.fold<double>(0, (sum, row) {
          final rowQty = _parseNumber(row.qtyController.text);
          final rowRate = _parseNumber(row.rateController.text);
          final rowDiscount = _parseNumber(row.discountController.text);
          final rowEffectiveRate = (rowRate - rowDiscount)
              .clamp(0, double.infinity)
              .toDouble();
          return sum + (rowQty * rowEffectiveRate);
        });
    return 'Rp ${total.toStringAsFixed(0).replaceAllMapped(RegExp(r"\B(?=(\d{3})+(?!\d))"), (m) => '.')}';
  }

  double _parseNumber(String value) {
    final normalized = value.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }

  String _formatMoney(double value) {
    return 'Rp ${value.toStringAsFixed(0).replaceAllMapped(RegExp(r"\B(?=(\d{3})+(?!\d))"), (m) => '.')}';
  }

  double _itemSubtotal({
    required TextEditingController qty,
    required TextEditingController rate,
    required TextEditingController discount,
  }) {
    final itemQty = _parseNumber(qty.text);
    final itemRate = _parseNumber(rate.text);
    final itemDiscount = _parseNumber(discount.text);
    final effectiveRate = (itemRate - itemDiscount)
        .clamp(0, double.infinity)
        .toDouble();
    return itemQty * effectiveRate;
  }

  List<Map<String, dynamic>> _buildItemsPayload(String firstItemCode) {
    final scheduleDate = _requiredByDate.toIso8601String().split('T').first;
    Map<String, dynamic> itemPayload({
      required String itemCode,
      required double qty,
      String? uom,
      double? rate,
      double? discountAmount,
      String? warehouse,
    }) {
      final effectiveRate = ((rate ?? 0) - (discountAmount ?? 0))
          .clamp(0, double.infinity)
          .toDouble();
      return {
        'item_code': itemCode.trim(),
        'qty': qty,
        if (uom != null && uom.trim().isNotEmpty) 'uom': uom.trim(),
        'schedule_date': scheduleDate,
        if (rate != null && rate > 0) 'rate': rate,
        if (discountAmount != null && discountAmount > 0)
          'discount_amount': discountAmount,
        if (effectiveRate > 0) 'amount': qty * effectiveRate,
        if (warehouse != null && warehouse.trim().isNotEmpty)
          'warehouse': warehouse.trim(),
      };
    }

    return [
      itemPayload(
        itemCode: firstItemCode,
        qty: _parseNumber(_qtyCtrl.text),
        uom: _uomCtrl.text,
        rate: _parseNumber(_rateCtrl.text),
        discountAmount: _parseNumber(_discountCtrl.text),
        warehouse: _selectedWarehouse,
      ),
      ..._additionalItems.map(
        (row) => itemPayload(
          itemCode: row.itemCode!,
          qty: _parseNumber(row.qtyController.text),
          uom: row.uomController.text,
          rate: _parseNumber(row.rateController.text),
          discountAmount: _parseNumber(row.discountController.text),
          warehouse: _selectedWarehouse,
        ),
      ),
    ];
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSeries == null) return;
    if (_supplierError != null || _itemError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silakan validasi supplier dan item terlebih dahulu'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final invalidAdditional = _additionalItems.any((row) {
      final qty = _parseNumber(row.qtyController.text);
      final rateText = row.rateController.text.trim();
      final rate = rateText.isEmpty ? 0 : _parseNumber(rateText);
      final discount = _parseNumber(row.discountController.text);
      return row.itemCode == null ||
          qty <= 0 ||
          rate < 0 ||
          discount < 0 ||
          (rate > 0 && discount > rate);
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

    try {
      setState(() {
        _isSaving = true;
      });

      final appState = context.read<PurchaseOrderState>();
      final itemCode =
          _selectedItemCode ?? _itemTextController?.text.trim() ?? '';
      if (itemCode.isEmpty) {
        throw Exception('Item code tidak boleh kosong');
      }
      final items = _buildItemsPayload(itemCode);

      if (widget.isEditMode) {
        await appState.updatePurchaseOrder(
          orderId: widget.editOrderId!,
          supplier: _supplierCtrl.text.trim(),
          items: items,
          warehouse: _selectedWarehouse,
          company: _selectedCompany,
          transactionDate: _selectedDate,
          requiredBy: _requiredByDate,
          noted: _notedCtrl.text,
        );
      } else {
        await appState.createPurchaseOrder(
          supplier: _supplierCtrl.text.trim(),
          items: items,
          namingSeries: _selectedSeries!,
          warehouse: _selectedWarehouse,
          company: _selectedCompany,
          transactionDate: _selectedDate,
          requiredBy: _requiredByDate,
          noted: _notedCtrl.text,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditMode
                ? 'Purchase Order berhasil diperbarui'
                : 'Purchase Order berhasil dibuat',
          ),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditMode
                ? 'Gagal memperbarui Purchase Order: $e'
                : 'Gagal membuat Purchase Order: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  InputDecoration _fieldDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.12),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.36),
          width: 1.4,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _dateTile({
    required String label,
    required IconData icon,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
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
              DateFormat('dd-MM-yyyy').format(value),
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.navy,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        centerTitle: false,
        titleSpacing: 16,
        title: Text(
          widget.isEditMode ? 'Edit Purchase Order' : 'New Purchase Order',
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
      body: SingleChildScrollView(
        padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 24),
        child: TmsxResponsiveBody(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Informasi Purchase Order',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.slate,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedSeries,
                        decoration: _fieldDecoration('Series'),
                        items: _seriesOptions
                            .map(
                              (series) => DropdownMenuItem(
                                value: series,
                                child: Text(series),
                              ),
                            )
                            .toList(),
                        onChanged: widget.isEditMode
                            ? null
                            : (value) =>
                                  setState(() => _selectedSeries = value),
                        validator: (value) => widget.isEditMode || value != null
                            ? null
                            : 'Series wajib dipilih',
                        hint: _isLoadingSelectors
                            ? const Text('Loading series...')
                            : const Text('Pilih series'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _dateTile(
                              label: 'Date',
                              icon: Icons.calendar_today,
                              value: _selectedDate,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _selectedDate = picked;
                                    if (_requiredByDate.isBefore(picked)) {
                                      _requiredByDate = picked;
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _dateTile(
                              label: 'Required By',
                              icon: Icons.local_shipping_outlined,
                              value: _requiredByDate,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _requiredByDate.isBefore(_selectedDate)
                                      ? _selectedDate
                                      : _requiredByDate,
                                  firstDate: _selectedDate,
                                  lastDate: DateTime(2035),
                                );
                                if (picked != null) {
                                  setState(() => _requiredByDate = picked);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _supplierCtrl,
                        readOnly: true,
                        onTap: _selectSupplier,
                        decoration:
                            _fieldDecoration(
                              'Supplier',
                              icon: Icons.storefront_outlined,
                            ).copyWith(
                              hintText: _isLoadingSelectors
                                  ? 'Loading supplier...'
                                  : 'Pilih atau search supplier',
                              suffixIcon: _supplierCtrl.text.isNotEmpty
                                  ? IconButton(
                                      tooltip: 'Bersihkan Supplier',
                                      onPressed: _clearSupplier,
                                      icon: const Icon(Icons.close_rounded),
                                    )
                                  : IconButton(
                                      tooltip: 'Search supplier',
                                      onPressed: _selectSupplier,
                                      icon: const Icon(Icons.search_rounded),
                                    ),
                              errorText: _supplierError,
                            ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Supplier wajib diisi'
                            : null,
                      ),
                      if (_selectedSupplierLabel().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          key: ValueKey(
                            'supplier_name_${_supplierCtrl.text.trim()}',
                          ),
                          initialValue: _selectedSupplierLabel(),
                          readOnly: true,
                          decoration: _fieldDecoration(
                            'Supplier Name',
                            icon: Icons.badge_outlined,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),

                      Builder(
                        builder: (context) {
                          final companyOptions = _visibleCompanyOptions;
                          final selectedCompany =
                              _selectedCompany != null &&
                                  companyOptions.contains(_selectedCompany)
                              ? _selectedCompany
                              : null;
                          return DropdownButtonFormField<String>(
                            initialValue: selectedCompany,
                            decoration: _fieldDecoration(
                              'Company',
                              icon: Icons.apartment_rounded,
                            ),
                            items: companyOptions
                                .map(
                                  (company) => DropdownMenuItem(
                                    value: company,
                                    child: Text(
                                      company,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: companyOptions.isEmpty
                                ? null
                                : (value) =>
                                      setState(() => _selectedCompany = value),
                            validator: (value) =>
                                (value ?? _selectedCompany)
                                        ?.trim()
                                        .isNotEmpty ==
                                    true
                                ? null
                                : 'Company wajib diisi',
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      if (_warehouseOptions.isNotEmpty)
                        ErpItemAutocompleteField(
                          label: 'Pilih Warehouse',
                          selectedId:
                              _warehouseOptions.any(
                                (w) => w.name == _selectedWarehouse,
                              )
                              ? _selectedWarehouse
                              : context
                                    .read<PurchaseOrderState>()
                                    .preferredWarehouse(_warehouseOptions),
                          decoration: _fieldDecoration(
                            'Pilih Warehouse',
                            icon: Icons.warehouse_outlined,
                          ),
                          options: _warehouseOptions
                              .map(
                                (warehouse) => ErpItemOption(
                                  id: warehouse.name,
                                  label: warehouse.name,
                                ),
                              )
                              .toList(),
                          onSelected: (value) => setState(() {
                            _selectedWarehouse = value;
                            _selectedCompany =
                                _companyForWarehouse(value) ?? _selectedCompany;
                          }),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.5),
                            ),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: const Text(
                            'Warehouse tidak tersedia. Refresh data warehouse terlebih dahulu.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
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
                      TextFormField(
                        controller: _itemTextController ??=
                            TextEditingController(text: _initialItemText ?? ''),
                        readOnly: true,
                        onTap: _selectPrimaryItem,
                        decoration:
                            _fieldDecoration(
                              'Nama Item / Kode',
                              icon: Icons.inventory_2_rounded,
                            ).copyWith(
                              hintText: 'Pilih atau search item',
                              suffixIcon: IconButton(
                                tooltip: 'Search item',
                                onPressed: _selectPrimaryItem,
                                icon: const Icon(Icons.search_rounded),
                              ),
                              errorText: _itemError,
                            ),
                        validator: (v) {
                          if ((_selectedItemCode ?? '').trim().isEmpty) {
                            return 'Item wajib dipilih';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _uomCtrl,
                        readOnly: true,
                        decoration:
                            _fieldDecoration(
                              'UOM',
                              icon: Icons.straighten_rounded,
                            ).copyWith(
                              hintText: 'Pilih item dulu',
                              fillColor: AppColors.softGreen,
                            ),
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
                              decoration: _fieldDecoration('Quantity'),
                              validator: (v) {
                                final q = double.tryParse(v?.trim() ?? '');
                                if (q == null || q <= 0) return 'Qty harus > 0';
                                return null;
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
                              decoration: _fieldDecoration('Rate (optional)'),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                final r = double.tryParse(v.trim());
                                if (r == null || r < 0) {
                                  return 'Rate harus >= 0';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _discountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _fieldDecoration(
                          'Diskon',
                          icon: Icons.discount_outlined,
                        ).copyWith(hintText: '0'),
                        validator: (v) {
                          final discount = _parseNumber(v ?? '');
                          final rate = _parseNumber(_rateCtrl.text);
                          if (discount < 0) return 'Diskon harus >= 0';
                          if (rate > 0 && discount > rate) {
                            return 'Diskon tidak boleh lebih besar dari rate';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _PurchaseItemSubtotalBox(
                        subtotal: _itemSubtotal(
                          qty: _qtyCtrl,
                          rate: _rateCtrl,
                          discount: _discountCtrl,
                        ),
                        formatMoney: _formatMoney,
                      ),
                      const SizedBox(height: 12),
                      ..._additionalItems.asMap().entries.map((entry) {
                        final index = entry.key;
                        final row = entry.value;
                        return _AdditionalPurchaseItemCard(
                          index: index,
                          row: row,
                          onChanged: () => setState(() {}),
                          onSelectItem: () => _selectAdditionalItem(row),
                          onRemove: () => _removeItemRow(index),
                          formatMoney: _formatMoney,
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
                              _formattedTotal,
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
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Noted',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notedCtrl,
                        minLines: 3,
                        maxLines: 5,
                        decoration:
                            _fieldDecoration(
                              'Noted',
                              icon: Icons.notes_rounded,
                            ).copyWith(
                              hintText: 'Catatan tambahan untuk purchase order',
                              prefixIcon: const Padding(
                                padding: EdgeInsets.only(bottom: 54),
                                child: Icon(Icons.notes_rounded),
                              ),
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
      ),
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.all(TmsxResponsive.horizontalPadding(context)),
        child: TmsxResponsiveBody(
          child: PurchasePrimaryActionButton(
            label: widget.isEditMode
                ? 'Update Purchase Order'
                : 'Save Purchase Order',
            icon: widget.isEditMode
                ? Icons.sync_rounded
                : Icons.save_alt_rounded,
            isLoading: _isSaving,
            onPressed: _save,
          ),
        ),
      ),
    );
  }
}

class _PurchaseItemSubtotalBox extends StatelessWidget {
  final double subtotal;
  final String Function(double value) formatMoney;

  const _PurchaseItemSubtotalBox({
    required this.subtotal,
    required this.formatMoney,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Amount',
            style: TextStyle(
              color: AppColors.slate,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            formatMoney(subtotal),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseSelectSheet<T> extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String searchHint;
  final Future<List<T>> Function(String query) loadOptions;
  final String? selectedId;
  final String Function(T item) idOf;
  final String Function(T item) titleOf;
  final String Function(T item) subtitleOf;

  const _PurchaseSelectSheet({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.searchHint,
    required this.loadOptions,
    required this.selectedId,
    required this.idOf,
    required this.titleOf,
    required this.subtitleOf,
  });

  @override
  State<_PurchaseSelectSheet<T>> createState() =>
      _PurchaseSelectSheetState<T>();
}

class _PurchaseSelectSheetState<T> extends State<_PurchaseSelectSheet<T>> {
  late Future<List<T>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = widget.loadOptions(_query);
  }

  void _search(String value) {
    setState(() {
      _query = value;
      _future = widget.loadOptions(_query);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.84,
          ),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.16),
                blurRadius: 26,
                offset: const Offset(0, 14),
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
                  width: 44,
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
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.softGreen,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(widget.icon, color: AppColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.navy,
                            ),
                          ),
                          Text(
                            widget.subtitle,
                            style: const TextStyle(
                              color: AppColors.slate,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.28),
                      ),
                    ),
                  ),
                  onChanged: _search,
                ),
              ),
              Flexible(
                child: FutureBuilder<List<T>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    final items = snapshot.data ?? const [];
                    if (items.isEmpty) {
                      return const Center(
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
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final id = widget.idOf(item);
                        final selected = id == widget.selectedId;
                        return Material(
                          color: selected
                              ? AppColors.softGreen
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => Navigator.pop(context, item),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primary.withValues(
                                          alpha: 0.28,
                                        )
                                      : AppColors.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: AppColors.white,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      widget.icon,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.titleOf(item),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.navy,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          widget.subtitleOf(item),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.slate,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    selected
                                        ? Icons.check_circle_rounded
                                        : Icons.chevron_right_rounded,
                                    color: selected
                                        ? AppColors.success
                                        : AppColors.slate,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdditionalPurchaseItemCard extends StatelessWidget {
  final int index;
  final _AdditionalPurchaseItemRow row;
  final VoidCallback onChanged;
  final VoidCallback onSelectItem;
  final VoidCallback onRemove;
  final String Function(double value) formatMoney;

  const _AdditionalPurchaseItemCard({
    required this.index,
    required this.row,
    required this.onChanged,
    required this.onSelectItem,
    required this.onRemove,
    required this.formatMoney,
  });

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          TextFormField(
            controller: row.itemTextController,
            readOnly: true,
            onTap: onSelectItem,
            decoration: _decoration('Item Code / Nama').copyWith(
              hintText: 'Pilih atau search item',
              prefixIcon: const Icon(Icons.inventory_2_outlined),
              suffixIcon: IconButton(
                tooltip: 'Search item',
                onPressed: onSelectItem,
                icon: const Icon(Icons.search_rounded),
              ),
            ),
            validator: (value) =>
                row.itemCode == null || row.itemCode!.trim().isEmpty
                ? 'Item wajib dipilih'
                : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: row.uomController,
            readOnly: true,
            decoration: _decoration('UOM').copyWith(
              hintText: 'Pilih item dulu',
              prefixIcon: const Icon(Icons.straighten_rounded),
              fillColor: AppColors.softGreen,
            ),
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
                  decoration: _decoration('Quantity'),
                  validator: (value) {
                    final qty = double.tryParse(value?.trim() ?? '');
                    return qty == null || qty <= 0 ? 'Qty harus > 0' : null;
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
                  decoration: _decoration('Rate'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final rate = double.tryParse(value.trim());
                    return rate == null || rate < 0 ? 'Rate harus >= 0' : null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: row.discountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration('Diskon').copyWith(
              prefixIcon: const Icon(Icons.discount_outlined),
              hintText: '0',
            ),
            validator: (value) {
              final discount = _parseNumber(value ?? '');
              final rate = _parseNumber(row.rateController.text);
              if (discount < 0) return 'Diskon harus >= 0';
              if (rate > 0 && discount > rate) {
                return 'Diskon tidak boleh lebih besar dari rate';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          _PurchaseItemSubtotalBox(
            subtotal:
                _parseNumber(row.qtyController.text) *
                (_parseNumber(row.rateController.text) -
                        _parseNumber(row.discountController.text))
                    .clamp(0, double.infinity)
                    .toDouble(),
            formatMoney: formatMoney,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  double _parseNumber(String value) {
    final normalized = value.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }
}

class _AdditionalPurchaseItemRow {
  String? itemCode;
  String? warehouse;
  final TextEditingController itemTextController;
  final TextEditingController qtyController;
  final TextEditingController uomController;
  final TextEditingController rateController;
  final TextEditingController discountController;

  _AdditionalPurchaseItemRow({
    this.warehouse,
    String itemText = '',
    String qty = '1',
    String uom = '',
    String rate = '',
    String discount = '0',
  }) : itemTextController = TextEditingController(text: itemText),
       qtyController = TextEditingController(text: qty),
       uomController = TextEditingController(text: uom),
       rateController = TextEditingController(text: rate),
       discountController = TextEditingController(text: discount);

  void dispose() {
    itemTextController.dispose();
    qtyController.dispose();
    uomController.dispose();
    rateController.dispose();
    discountController.dispose();
  }
}

class _SupplierOption {
  final String id;
  final String label;

  const _SupplierOption({required this.id, required this.label});
}

class _ItemOption {
  final String code;
  final String label;
  final String uom;

  _ItemOption({required this.code, required this.label, this.uom = ''});

  String get name {
    final dashIndex = label.lastIndexOf(' - ');
    if (dashIndex > 0) return label.substring(0, dashIndex).trim();
    final parenIndex = label.lastIndexOf(' (');
    if (parenIndex > 0) return label.substring(0, parenIndex).trim();
    return label;
  }
}
