import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../../models/sales_order.dart';
import '../../../models/sales_order_insight.dart';
import '../../../models/sales_workspace.dart';
import '../../../models/warehouse_info.dart';
import '../../../state/selling/sales_order_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/sales_ui.dart';

class CreateSalesOrderScreen extends StatefulWidget {
  final String? editOrderId;
  final SalesOrder? duplicateFrom;

  const CreateSalesOrderScreen({
    super.key,
    this.editOrderId,
    this.duplicateFrom,
  });

  bool get isEditMode => editOrderId != null;
  bool get isDuplicateMode => duplicateFrom != null && editOrderId == null;

  @override
  State<CreateSalesOrderScreen> createState() => _CreateSalesOrderScreenState();
}

class _CreateSalesOrderScreenState extends State<CreateSalesOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _rateCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _notedCtrl = TextEditingController();
  final List<_AdditionalItemRow> _additionalItems = [];
  final ImagePicker _imagePicker = ImagePicker();
  final List<XFile> _photos = [];
  CustomerSalesInsight? _customerInsight;
  final Map<String, ItemSalesInsight> _itemInsights = {};
  final Set<String> _loadingItemPrices = {};
  bool _isLoadingCustomerInsight = false;
  String? _customerInsightError;
  Timer? _pricingDebounce;
  String? _selectedCurrency;
  String? _selectedPriceList;
  String? _priceListCurrency;

  TextEditingController? _itemTextController;
  String? _initialItemText;
  String? _selectedItemCode;
  String? _selectedSeries;
  String? _selectedCompany;
  String? _selectedWarehouse;
  String? _selectedCenter;
  String? _selectedSalesPerson;
  DateTime _selectedDate = DateTime.now();
  DateTime _selectedDeliveryDate = DateTime.now();

  bool _isLoadingSelectors = true;
  bool _isSaving = false;
  bool _isValidatingItem = false;
  String? _seriesError;
  String? _selectorLoadError;
  String? _customerError;
  String? _itemError;
  double _totalAmount = 0.0;

  bool get _isCustomerLocked => widget.isDuplicateMode;

  String get _screenTitle {
    if (widget.isEditMode) return 'Edit Sales Order';
    if (widget.isDuplicateMode) return 'Duplicate Sales Order';
    return 'New Sales Order';
  }

  String get _saveButtonLabel {
    if (widget.isEditMode) return 'Update Sales Order';
    if (widget.isDuplicateMode) return 'Create Duplicate SO';
    return 'Save Sales Order';
  }

  List<String> _seriesOptions = [];
  List<String> _customerSeriesOptions = [];
  List<String> _customerTypeOptions = [];
  List<String> _customerGroupOptions = [];
  List<String> _territoryOptions = [];
  List<String> _paymentTermsOptions = [];
  List<String> _salesPersonOptions = [];
  List<String> _companyOptions = [];
  List<String> _currencyOptions = [];
  List<String> _priceListOptions = [];
  List<_CostCenterOption> _costCenterOptions = [];
  List<_CustomerOption> _customerOptions = [];
  List<_ItemOption> _itemOptions = [];

  List<WarehouseInfo> _warehouseOptions(SalesOrderState appState) {
    final warehouses = appState.warehouses.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final seen = <String>{};
    return warehouses.where((warehouse) {
      final name = warehouse.name.trim();
      if (name.isEmpty || warehouse.isDisabled == true || seen.contains(name)) {
        return false;
      }
      seen.add(name);
      return true;
    }).toList();
  }

  List<WarehouseInfo> _warehousesForCompany(SalesOrderState appState) {
    final warehouses = _warehouseOptions(appState);
    final company = _selectedCompany?.trim() ?? '';
    if (company.isEmpty) return warehouses;
    return warehouses
        .where((warehouse) => warehouse.company == company)
        .toList();
  }

  Future<void> _ensureWarehouseEnabled(SalesOrderState appState) async {
    final warehouse = _selectedWarehouse?.trim() ?? '';
    if (warehouse.isEmpty) return;

    final document = await appState.frappeService.fetchDocument(
      'Warehouse',
      warehouse,
    );
    final disabled = document['disabled'] == 1 || document['disabled'] == true;
    final isGroup = document['is_group'] == 1 || document['is_group'] == true;
    if (disabled || isGroup) {
      throw Exception(
        disabled
            ? 'Warehouse $warehouse sudah dinonaktifkan. Pilih warehouse lain.'
            : 'Warehouse $warehouse merupakan group dan tidak dapat digunakan.',
      );
    }
  }

  List<String> _splitFrappeOptions(dynamic raw) {
    if (raw is List) {
      return raw
          .map((value) => value?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();
    }

    return raw
            ?.toString()
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList() ??
        <String>[];
  }

  List<String> _normalizeOptions(List<String> options) {
    final seen = <String>{};
    final result = <String>[];
    for (var option in options) {
      final trimmed = option.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) continue;
      seen.add(trimmed);
      result.add(trimmed);
    }
    return result;
  }

  List<_CostCenterOption> _normalizeCostCenterOptions(
    List<_CostCenterOption> options,
  ) {
    final seen = <String>{};
    final result = <_CostCenterOption>[];
    for (final option in options) {
      final trimmed = option.name.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) continue;
      seen.add(trimmed);
      result.add(option);
    }
    return result;
  }

  Future<List<String>> _fetchSalesOrderSeriesOptions(
    SalesOrderState appState,
  ) async {
    return appState.fetchNamingSeries('Sales Order');
  }

  Future<List<String>> _fetchDocTypeSelectOptions(
    SalesOrderState appState, {
    required String doctype,
    required String fieldname,
  }) async {
    try {
      final docType = await appState.frappeService.fetchDocument(
        'DocType',
        doctype,
      );
      final fields = docType['fields'];
      if (fields is List) {
        for (final row in fields) {
          if (row is! Map) continue;
          if (row['fieldname']?.toString() != fieldname) continue;
          return _splitFrappeOptions(row['options']);
        }
      }
    } catch (_) {}
    return [];
  }

  Future<List<String>> _fetchLinkOptions(
    SalesOrderState appState, {
    required String doctype,
    List<List<dynamic>>? filters,
  }) async {
    final data = await appState.frappeService.fetchResource(
      doctype,
      fields: const ['name'],
      filters: filters,
      orderBy: 'name asc',
    );
    return data
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  String _selectorErrorMessage(Object error) {
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();
  }

  Future<T> _loadSelector<T>({
    required String label,
    required Future<T> Function() load,
    required T fallback,
    required List<String> errors,
  }) async {
    try {
      return await load();
    } catch (error) {
      errors.add('$label: ${_selectorErrorMessage(error)}');
      return fallback;
    }
  }

  Future<List<String>> _fetchSalesPersonOptions(
    SalesOrderState appState,
  ) async {
    Future<List<String>> fetch(List<List<dynamic>> filters) async {
      final data = await appState.frappeService.fetchResource(
        'Sales Person',
        fields: const ['name'],
        filters: filters,
        orderBy: 'name asc',
      );
      return data
          .map((row) => row['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    }

    try {
      return await fetch(const [
        ['is_group', '=', 0],
        ['enabled', '=', 1],
      ]);
    } catch (_) {
      return fetch(const [
        ['is_group', '=', 0],
      ]);
    }
  }

  WarehouseInfo? _selectedWarehouseInfo(List<WarehouseInfo> warehouses) {
    for (final warehouse in warehouses) {
      if (warehouse.name == _selectedWarehouse) return warehouse;
    }
    return null;
  }

  List<_CostCenterOption> _costCentersForCompany() {
    final company = _selectedCompany?.trim() ?? '';
    if (company.isEmpty) {
      return _ensureSelectedCostCenterOption(_costCenterOptions);
    }

    final filtered = _costCenterOptions
        .where((center) => center.company == company)
        .toList();
    final options = filtered.isNotEmpty ? filtered : _costCenterOptions;
    return _ensureSelectedCostCenterOption(options);
  }

  List<_CostCenterOption> _ensureSelectedCostCenterOption(
    List<_CostCenterOption> options,
  ) {
    final selected = _selectedCenter?.trim() ?? '';
    if (selected.isEmpty || options.any((center) => center.name == selected)) {
      return options;
    }
    return [
      ...options,
      _CostCenterOption(name: selected, company: _selectedCompany ?? ''),
    ];
  }

  String _activeCompany() => _selectedCompany?.trim() ?? '';

  String? _customerSalesPerson(_CustomerOption? customer) {
    if (customer == null) return null;
    for (final row in customer.salesTeam) {
      final salesPerson = row['sales_person']?.toString().trim() ?? '';
      if (salesPerson.isNotEmpty) return salesPerson;
    }
    return null;
  }

  void _clearCustomer() {
    setState(() {
      _customerCtrl.clear();
      _customerError = null;
      _customerInsight = null;
      _customerInsightError = null;
      _itemInsights.clear();
    });
  }

  void _applyCustomerSelection(String customerId) {
    final appState = context.read<SalesOrderState>();
    _customerCtrl.text = customerId;
    final customer = _selectedCustomerOption();
    if (appState.mobileAccess.isSalesUser) {
      _selectedSalesPerson = appState.currentSalesPerson;
    } else {
      final customerSalesPerson = _customerSalesPerson(customer);
      _selectedSalesPerson = _salesPersonOptions.contains(customerSalesPerson)
          ? customerSalesPerson
          : null;
    }
    _customerError = null;
    _customerInsight = null;
    _customerInsightError = null;
    _itemInsights.clear();
  }

  Future<void> _applyCustomerErpDefaults(String customerId) async {
    final appState = context.read<SalesOrderState>();
    try {
      final customer = await appState.frappeService.fetchDocument(
        'Customer',
        customerId,
      );
      if (!mounted || _customerCtrl.text.trim() != customerId) return;

      String resolveDefault({
        required List<String> fields,
        required List<String> keyFragments,
      }) {
        String fromRow(Map<dynamic, dynamic> row) {
          for (final field in fields) {
            final value = row[field]?.toString().trim() ?? '';
            if (value.isNotEmpty) return value;
          }
          for (final entry in row.entries) {
            final key = entry.key.toString().toLowerCase();
            if (!keyFragments.any(key.contains)) continue;
            final value = entry.value?.toString().trim() ?? '';
            if (value.isNotEmpty && value != 'null') return value;
          }
          return '';
        }

        final direct = fromRow(customer);
        if (direct.isNotEmpty) return direct;

        final company = _activeCompany().toLowerCase();
        for (final value in customer.values) {
          if (value is! List) continue;
          for (final rawRow in value) {
            if (rawRow is! Map) continue;
            final rowCompany =
                rawRow['company']?.toString().trim().toLowerCase() ?? '';
            if (company.isNotEmpty &&
                rowCompany.isNotEmpty &&
                rowCompany != company) {
              continue;
            }
            final nested = fromRow(rawRow);
            if (nested.isNotEmpty) return nested;
          }
        }
        return '';
      }

      final defaultCostCenter = resolveDefault(
        fields: const [
          'cost_center',
          'default_cost_center',
          'custom_cost_center',
          'custom_default_cost_center',
        ],
        keyFragments: const ['cost_center', 'costcentre'],
      );
      final defaultWarehouse = resolveDefault(
        fields: const [
          'warehouse',
          'default_warehouse',
          'custom_warehouse',
          'custom_default_warehouse',
        ],
        keyFragments: const ['warehouse'],
      );
      final salesTeam = customer['sales_team'];

      String? customerSalesPerson;
      if (salesTeam is List) {
        for (final rawRow in salesTeam) {
          if (rawRow is! Map) continue;
          final salesPerson = rawRow['sales_person']?.toString().trim() ?? '';
          if (salesPerson.isNotEmpty) {
            customerSalesPerson = salesPerson;
            break;
          }
        }
      }

      final warehouses = _warehousesForCompany(appState);
      final costCenters = _costCentersForCompany();
      String? matchingWarehouse;
      for (final warehouse in warehouses) {
        if (warehouse.name.trim().toLowerCase() ==
            defaultWarehouse.toLowerCase()) {
          matchingWarehouse = warehouse.name;
          break;
        }
      }
      String? matchingCostCenter;
      for (final costCenter in costCenters) {
        if (costCenter.name.trim().toLowerCase() ==
            defaultCostCenter.toLowerCase()) {
          matchingCostCenter = costCenter.name;
          break;
        }
      }
      setState(() {
        _selectedCenter = matchingCostCenter;
        _selectedWarehouse = matchingWarehouse;
        if (appState.mobileAccess.isSalesUser) {
          _selectedSalesPerson = appState.currentSalesPerson;
        } else {
          _selectedSalesPerson =
              _salesPersonOptions.contains(customerSalesPerson)
              ? customerSalesPerson
              : null;
        }
      });
      _scheduleRepriceAllItems();
    } catch (_) {
      // Customer defaults are optional; manual selectors remain available.
    }
  }

  Future<void> _onCompanySelected(String? company) async {
    final appState = context.read<SalesOrderState>();
    setState(() {
      _selectedCompany = company;
      final warehouses = _warehousesForCompany(appState);
      if (!warehouses.any((row) => row.name == _selectedWarehouse)) {
        _selectedWarehouse = null;
      }
      final costCenters = _costCentersForCompany();
      if (!costCenters.any((row) => row.name == _selectedCenter)) {
        _selectedCenter = null;
      }
    });

    if (company?.trim().isNotEmpty == true) {
      try {
        final companyDoc = await appState.frappeService.fetchDocument(
          'Company',
          company!,
        );
        final currency =
            companyDoc['default_currency']?.toString() ??
            companyDoc['currency']?.toString() ??
            '';
        if (mounted && _currencyOptions.contains(currency)) {
          setState(() {
            _selectedCurrency = currency;
            _priceListCurrency ??= currency;
          });
        }
      } catch (_) {}
    }
    if (!mounted) return;
    await _loadCustomerInsight();
    _scheduleRepriceAllItems();
  }

  Future<List<_CostCenterOption>> _fetchCostCenterOptions(
    SalesOrderState appState,
  ) async {
    Future<List<_CostCenterOption>> fetch({
      required List<String> fields,
      List<List<dynamic>>? filters,
    }) async {
      final data = await appState.frappeService.fetchResource(
        'Cost Center',
        fields: fields,
        filters: filters,
        orderBy: 'name asc',
      );
      return data
          .map((row) {
            final name = row['name']?.toString() ?? '';
            if (name.isEmpty) return null;
            return _CostCenterOption(
              name: name,
              company: row['company']?.toString() ?? '',
            );
          })
          .whereType<_CostCenterOption>()
          .toList();
    }

    try {
      return await fetch(
        fields: const ['name', 'company', 'is_group', 'disabled'],
        filters: const [
          ['is_group', '=', 0],
          ['disabled', '=', 0],
        ],
      );
    } catch (_) {
      try {
        return await fetch(
          fields: const ['name', 'company', 'is_group'],
          filters: const [
            ['is_group', '=', 0],
          ],
        );
      } catch (_) {
        try {
          return await fetch(fields: const ['name', 'company']);
        } catch (_) {
          return fetch(fields: const ['name']);
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _itemTextController = TextEditingController();
    _qtyCtrl.addListener(_onPricingInputChanged);
    _rateCtrl.addListener(_calculateTotal);
    _discountCtrl.addListener(_calculateTotal);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final appState = context.read<SalesOrderState>();
      final defaultWarehouse = appState.preferredWarehouse(
        _warehouseOptions(appState),
      );
      if (defaultWarehouse != null && _selectedWarehouse == null) {
        setState(() => _selectedWarehouse = defaultWarehouse);
      }
      _loadSelectors();
    });
  }

  @override
  void dispose() {
    _pricingDebounce?.cancel();
    _customerCtrl.dispose();
    _qtyCtrl.dispose();
    _rateCtrl.dispose();
    _discountCtrl.dispose();
    _notedCtrl.dispose();
    _itemTextController?.dispose();
    for (final row in _additionalItems) {
      row.dispose();
    }
    _itemTextController = null;
    super.dispose();
  }

  void _calculateTotal() {
    setState(() {
      _totalAmount =
          _itemSubtotal(
            qtyText: _qtyCtrl.text,
            rateText: _rateCtrl.text,
            discountText: _discountCtrl.text,
          ) +
          _additionalItems.fold<double>(
            0,
            (total, row) =>
                total +
                _itemSubtotal(
                  qtyText: row.qtyController.text,
                  rateText: row.rateController.text,
                  discountText: row.discountController.text,
                ),
          );
    });
  }

  double _parseNumber(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    return double.tryParse(cleaned) ?? 0;
  }

  double _itemQty(String value) => _parseNumber(value);

  double _itemRate(String value) => _parseNumber(value);

  double _itemDiscount(String value) => _parseNumber(value);

  double _effectiveItemRate({
    required String rateText,
    required String discountText,
  }) {
    final rate = _itemRate(rateText);
    final discount = _itemDiscount(discountText);
    return (rate - discount).clamp(0, double.infinity);
  }

  double _itemSubtotal({
    required String qtyText,
    required String rateText,
    required String discountText,
  }) {
    return _itemQty(qtyText) *
        _effectiveItemRate(rateText: rateText, discountText: discountText);
  }

  String _formatRupiah(double value) {
    return NumberFormat.currency(
      locale: 'id_ID',
      symbol: '',
      decimalDigits: 0,
    ).format(value).trim();
  }

  void _formatMoneyController(TextEditingController controller) {
    if (controller.text.trim().isEmpty) return;
    final value = _parseNumber(controller.text);
    controller.text = _formatRupiah(value);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
  }

  void _onPricingInputChanged() {
    _calculateTotal();
    _scheduleRepriceAllItems();
  }

  void _addItemRow() {
    final row = _AdditionalItemRow();
    row.qtyController.addListener(_onPricingInputChanged);
    row.rateController.addListener(_calculateTotal);
    row.discountController.addListener(_calculateTotal);
    setState(() => _additionalItems.add(row));
  }

  void _clearPrimaryItem() {
    setState(() {
      _selectedItemCode = null;
      _initialItemText = null;
      _itemTextController?.clear();
      _qtyCtrl.text = '1';
      _rateCtrl.clear();
      _discountCtrl.text = '0';
      _itemError = null;
    });
    _calculateTotal();
  }

  void _adjustQuantity(TextEditingController controller, double delta) {
    final current = _parseNumber(controller.text);
    final next = (current + delta).clamp(1, double.infinity);
    controller.text = next == next.roundToDouble()
        ? next.toInt().toString()
        : next.toStringAsFixed(2);
  }

  void _scheduleRepriceAllItems() {
    _pricingDebounce?.cancel();
    _pricingDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _repriceAllItems();
    });
  }

  Future<void> _repriceAllItems() async {
    final firstCode = _selectedItemCode;
    if (firstCode != null && firstCode.isNotEmpty) {
      await _loadItemInsight(firstCode, applyPrice: true);
    }
    for (final row in _additionalItems) {
      final code = row.itemCode;
      if (code != null && code.isNotEmpty) {
        await _loadItemInsight(code, applyPrice: true, row: row);
      }
    }
  }

  void _removeItemRow(int index) {
    final row = _additionalItems.removeAt(index);
    row.dispose();
    _calculateTotal();
  }

  List<Map<String, dynamic>> _buildItemsPayload(String firstItemCode) {
    final deliveryDate = _selectedDeliveryDate
        .toIso8601String()
        .split('T')
        .first;
    Map<String, dynamic> itemPayload({
      required String itemCode,
      required double qty,
      double? rate,
      double? discountAmount,
      String? warehouse,
    }) {
      final pricing = _itemInsights[itemCode];
      final originalRate = rate ?? 0;
      final discount = discountAmount ?? 0;
      final effectiveRate = (originalRate - discount).clamp(0, double.infinity);
      final rowAmount = qty * effectiveRate;
      return {
        'item_code': itemCode,
        'qty': qty,
        'delivery_date': deliveryDate,
        if (originalRate > 0) 'price_list_rate': originalRate,
        if (effectiveRate > 0) 'rate': effectiveRate,
        if (effectiveRate > 0) 'net_rate': effectiveRate,
        if (rowAmount > 0) 'amount': rowAmount,
        if (rowAmount > 0) 'net_amount': rowAmount,
        'discount_amount': discount,
        if (originalRate <= 0 && pricing != null && pricing.priceListRate > 0)
          'price_list_rate': pricing.priceListRate,
        if ((discountAmount == null || discountAmount <= 0) &&
            pricing != null &&
            pricing.discountPercentage > 0)
          'discount_percentage': pricing.discountPercentage,
        if ((discountAmount == null || discountAmount <= 0) &&
            pricing != null &&
            pricing.pricingRule.isNotEmpty)
          'pricing_rule': pricing.pricingRule,
        if (warehouse != null && warehouse.trim().isNotEmpty)
          'warehouse': warehouse.trim(),
        if (_selectedCenter != null && _selectedCenter!.trim().isNotEmpty)
          'cost_center': _selectedCenter!.trim(),
      };
    }

    return [
      itemPayload(
        itemCode: firstItemCode,
        qty: double.parse(_qtyCtrl.text.trim()),
        rate: _itemRate(_rateCtrl.text),
        discountAmount: _itemDiscount(_discountCtrl.text),
        warehouse: _selectedWarehouse,
      ),
      ..._additionalItems.map(
        (row) => itemPayload(
          itemCode: row.itemCode!,
          qty: double.parse(row.qtyController.text.trim()),
          rate: _itemRate(row.rateController.text),
          discountAmount: _itemDiscount(row.discountController.text),
          warehouse: row.warehouse ?? _selectedWarehouse,
        ),
      ),
    ];
  }

  Future<void> _loadCustomerInsight() async {
    final customer = _customerCtrl.text.trim();
    if (customer.isEmpty) return;
    setState(() {
      _isLoadingCustomerInsight = true;
      _customerInsightError = null;
    });
    try {
      final insight = await context
          .read<SalesOrderState>()
          .fetchCustomerSalesInsight(customer, company: _activeCompany());
      if (!mounted) return;
      setState(() {
        _customerInsight = insight;
        _selectedPriceList = insight.priceList.isNotEmpty
            ? insight.priceList
            : _selectedPriceList;
        _selectedCurrency = insight.currency.isNotEmpty
            ? insight.currency
            : _selectedCurrency;
        _priceListCurrency = insight.priceListCurrency.isNotEmpty
            ? insight.priceListCurrency
            : (_selectedCurrency ?? _priceListCurrency);
      });
      await _repriceAllItems();
    } catch (error) {
      if (!mounted) return;
      setState(() => _customerInsightError = error.toString());
    } finally {
      if (mounted) setState(() => _isLoadingCustomerInsight = false);
    }
  }

  Future<ItemSalesInsight?> _loadItemInsight(
    String itemCode, {
    bool applyPrice = false,
    _AdditionalItemRow? row,
  }) async {
    if (itemCode.isEmpty) return null;
    final loadingKey = row == null ? 'first:$itemCode' : 'row:${row.hashCode}';
    String pricingContextKey() {
      final controller = row?.qtyController ?? _qtyCtrl;
      return [
        itemCode,
        _customerCtrl.text.trim(),
        _activeCompany(),
        _selectedPriceList ?? '',
        _selectedCurrency ?? '',
        row?.warehouse ?? _selectedWarehouse ?? '',
        controller.text.trim(),
      ].join('|');
    }

    final requestContextKey = pricingContextKey();
    setState(() => _loadingItemPrices.add(loadingKey));
    try {
      final qty =
          double.tryParse((row?.qtyController ?? _qtyCtrl).text.trim()) ?? 1;
      final insight = await _withTransientRetry(
        () => context.read<SalesOrderState>().fetchItemSalesInsight(
          itemCode,
          customer: _customerCtrl.text.trim(),
          company: _activeCompany(),
          priceList: _selectedPriceList,
          currency: _selectedCurrency,
          warehouse: row?.warehouse ?? _selectedWarehouse,
          customerGroup: _customerInsight?.customerGroup,
          transactionDate: _selectedDate,
          qty: qty,
          ignorePricingRule: false,
        ),
      );
      if (!mounted || requestContextKey != pricingContextKey()) {
        return insight;
      }
      if (row == null && _selectedItemCode != itemCode) return insight;
      if (row != null && row.itemCode != itemCode) return insight;
      final resolvedPrice = insight.priceListRate > 0
          ? insight.priceListRate
          : insight.price;
      setState(() {
        _itemInsights[itemCode] = insight;
        if (applyPrice && resolvedPrice > 0) {
          if (row == null) {
            _rateCtrl.text = _formatRupiah(resolvedPrice);
            if (insight.discountAmount > 0) {
              _discountCtrl.text = _formatRupiah(insight.discountAmount);
            }
          } else {
            row.rateController.text = _formatRupiah(resolvedPrice);
            if (insight.discountAmount > 0) {
              row.discountController.text = _formatRupiah(
                insight.discountAmount,
              );
            }
          }
        }
      });
      return insight;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_pricingErrorMessage(error))));
      }
      return null;
    } finally {
      if (mounted) setState(() => _loadingItemPrices.remove(loadingKey));
    }
  }

  Future<T> _withTransientRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      if (!_isTransientNetworkError(error)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 650));
      return action();
    }
  }

  bool _isTransientNetworkError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('socketexception') ||
        message.contains('connection abort') ||
        message.contains('connection reset') ||
        message.contains('connection closed') ||
        message.contains('connection refused') ||
        message.contains('failed host lookup') ||
        message.contains('timed out') ||
        message.contains('timeout');
  }

  String _pricingErrorMessage(Object error) {
    if (_isTransientNetworkError(error)) {
      return 'Koneksi ke ERPNext terputus saat mengambil stok/harga. Coba refresh atau pilih item lagi.';
    }
    return 'Gagal mengambil stok/harga: ${_selectorErrorMessage(error)}';
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final photo = await _imagePicker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (photo != null && mounted) setState(() => _photos.add(photo));
  }

  void _showCustomerHistory() {
    final customer = _customerCtrl.text.trim();
    if (customer.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _CustomerHistorySheet(customer: customer, company: _activeCompany()),
    );
  }

  Future<bool> _confirmOrderRisks(List<Map<String, dynamic>> items) async {
    final warnings = <String>[];
    final customer = _customerInsight;
    if (customer != null &&
        customer.creditLimit > 0 &&
        customer.outstanding + _totalAmount > customer.creditLimit) {
      warnings.add(
        'Total order melewati limit kredit customer sebesar '
        'Rp ${(customer.outstanding + _totalAmount - customer.creditLimit).toStringAsFixed(0)}.',
      );
    }

    for (final item in items) {
      final itemCode = item['item_code']?.toString() ?? '';
      final warehouse = item['warehouse']?.toString() ?? '';
      final qty = (item['qty'] as num?)?.toDouble() ?? 0;
      if (itemCode.isEmpty || warehouse.isEmpty) continue;
      final insight =
          _itemInsights[itemCode] ?? await _loadItemInsight(itemCode);
      if (insight == null) continue;
      final matching = insight.stocks.where(
        (row) => row.warehouse == warehouse,
      );
      final actual = matching.isEmpty ? 0 : matching.first.actualQty;
      if (actual < qty) {
        warnings.add(
          '$itemCode di $warehouse hanya tersedia ${actual.toStringAsFixed(0)}, '
          'order ${qty.toStringAsFixed(0)}.',
        );
      }
    }

    if (warnings.isEmpty || !mounted) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Konfirmasi Risiko Order'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: warnings
                    .map(
                      (warning) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('• $warning'),
                      ),
                    )
                    .toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Periksa Lagi'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Tetap Simpan Draft'),
              ),
            ],
          ),
        ) ??
        false;
  }

  String _normalizeItemCode(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return '';
    final match = RegExp(r'\(([^)]+)\)$').firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.trim();
    }
    final dashIndex = trimmed.lastIndexOf(' - ');
    if (dashIndex >= 0 && dashIndex + 3 < trimmed.length) {
      return trimmed.substring(dashIndex + 3).trim();
    }
    return trimmed;
  }

  _ItemOption? _itemOptionFromRow(Map<String, dynamic> row) {
    final itemCode = row['item_code']?.toString().trim() ?? '';
    final name = row['name']?.toString().trim() ?? '';
    final code = itemCode.isNotEmpty ? itemCode : name;
    final itemName = row['item_name']?.toString().trim() ?? code;
    if (code.isEmpty) return null;
    return _ItemOption(code: code, name: itemName);
  }

  Future<Iterable<_ItemOption>> _searchItemOptions(
    BuildContext context,
    String value,
  ) async {
    final query = value.trim();
    if (query.isEmpty) return _itemOptions.take(20);

    final remoteRows = await context.read<SalesOrderState>().fetchSellableItems(
      query: query,
      limit: 50,
    );
    final remoteOptions = remoteRows
        .map(_itemOptionFromRow)
        .whereType<_ItemOption>()
        .toList();
    if (remoteOptions.isNotEmpty) return remoteOptions;

    final needle = query.toLowerCase();
    return _itemOptions.where((option) {
      final label = option.label.toLowerCase();
      return label.contains(needle) ||
          option.code.toLowerCase().contains(needle);
    });
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
        var query = '';
        Future<List<_ItemOption>> loadOptions() async {
          final options = await _searchItemOptions(sheetContext, query);
          return options.toList();
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.84,
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
                              child: const Icon(
                                Icons.inventory_2_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                  const Text(
                                    'Cari nama atau kode item yang boleh dijual.',
                                    style: TextStyle(
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
                          decoration: InputDecoration(
                            hintText: 'Search item name or item code',
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
                                color: AppColors.primary.withValues(
                                  alpha: 0.28,
                                ),
                              ),
                            ),
                          ),
                          onChanged: (value) =>
                              setSheetState(() => query = value),
                        ),
                      ),
                      Flexible(
                        child: FutureBuilder<List<_ItemOption>>(
                          future: loadOptions(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.waiting &&
                                query.trim().isNotEmpty) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(28),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }

                            final items =
                                snapshot.data ?? const <_ItemOption>[];
                            if (items.isEmpty) {
                              return const Center(
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
                                final selected = item.code == selectedCode;
                                return Material(
                                  color: selected
                                      ? AppColors.softGreen
                                      : AppColors.background,
                                  borderRadius: BorderRadius.circular(18),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () =>
                                        Navigator.pop(sheetContext, item),
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
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: const Icon(
                                              Icons.inventory_2_rounded,
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
                                                  item.name,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: AppColors.navy,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  item.code,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: AppColors.slate,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (selected)
                                            const Icon(
                                              Icons.check_circle_rounded,
                                              color: AppColors.success,
                                            )
                                          else
                                            const Icon(
                                              Icons.chevron_right_rounded,
                                              color: AppColors.slate,
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
          },
        );
      },
    );
    return result;
  }

  Future<void> _selectPrimaryItem() async {
    final option = await _showItemSelectSheet(
      title: 'Pilih Item',
      selectedCode: _selectedItemCode,
    );
    if (option == null || !mounted) return;
    setState(() {
      _selectedItemCode = option.code;
      _initialItemText = option.label;
      _itemTextController?.text = option.label;
      _itemError = null;
      _rateCtrl.clear();
      _isValidatingItem = true;
    });
    try {
      await _loadItemInsight(option.code, applyPrice: true);
    } finally {
      if (mounted) setState(() => _isValidatingItem = false);
    }
  }

  Future<void> _selectAdditionalItem(_AdditionalItemRow row) async {
    final option = await _showItemSelectSheet(
      title: 'Pilih Item Tambahan',
      selectedCode: row.itemCode,
    );
    if (option == null || !mounted) return;
    setState(() {
      row.itemCode = option.code;
      row.itemTextController.text = option.label;
      row.rateController.clear();
    });
    await _loadItemInsight(option.code, applyPrice: true, row: row);
  }

  List<_CustomerOption> _filteredCustomers(String query) {
    final customers = _salesScopedCustomerOptions();
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return customers.take(30).toList();

    return customers.where((customer) {
      return customer.id.toLowerCase().contains(normalized) ||
          customer.name.toLowerCase().contains(normalized);
    }).toList();
  }

  List<_CustomerOption> _salesScopedCustomerOptions() {
    final appState = context.read<SalesOrderState>();
    if (!appState.mobileAccess.isSalesUser) return _customerOptions;

    final salesPerson = appState.currentSalesPerson?.trim() ?? '';
    if (salesPerson.isEmpty) return const [];

    return _customerOptions.where((customer) {
      return customer.salesTeam.any(
        (row) => row['sales_person']?.toString().trim() == salesPerson,
      );
    }).toList();
  }

  _CustomerOption? _selectedCustomerOption() {
    final id = _customerCtrl.text.trim();
    for (final customer in _customerOptions) {
      if (customer.id == id) return customer;
    }
    return null;
  }

  String _selectedCustomerName() {
    final customer = _selectedCustomerOption();
    final name = customer?.name.trim() ?? '';
    final id = _customerCtrl.text.trim();
    if (name.isEmpty || name == id) return '';
    return name;
  }

  Future<void> _showCustomerSelectSheet() async {
    String? selectedCustomerId;
    var shouldAddCustomer = false;

    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final customers = _filteredCustomers(query);
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
                                'Pilih Customer',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.navy,
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
                          decoration: InputDecoration(
                            hintText: 'Cari nama atau ID customer',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (value) =>
                              setSheetState(() => query = value),
                        ),
                      ),
                      if (!context
                          .read<SalesOrderState>()
                          .mobileAccess
                          .isSalesUser) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext, true);
                            },
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                            label: const Text('Add Customer Baru'),
                          ),
                        ),
                      ],
                      Flexible(
                        child: customers.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(28),
                                  child: Text(
                                    'Customer tidak ditemukan',
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
                                itemCount: customers.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final customer = customers[index];
                                  final selected =
                                      customer.id == _customerCtrl.text.trim();
                                  return Material(
                                    color: selected
                                        ? AppColors.softGreen
                                        : AppColors.background,
                                    borderRadius: BorderRadius.circular(18),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () {
                                        Navigator.pop(
                                          sheetContext,
                                          customer.id,
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
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
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: const Icon(
                                                Icons.storefront_rounded,
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
                                                    customer.name,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: AppColors.navy,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                  if (customer.name !=
                                                      customer.id) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      customer.id,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: AppColors.slate,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (selected)
                                              const Icon(
                                                Icons.check_circle_rounded,
                                                color: AppColors.success,
                                              )
                                            else
                                              const Icon(
                                                Icons.chevron_right_rounded,
                                                color: AppColors.slate,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
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

    if (result is bool && result) {
      shouldAddCustomer = true;
    } else if (result is String && result.isNotEmpty) {
      selectedCustomerId = result;
    }

    if (selectedCustomerId != null && mounted) {
      setState(() => _applyCustomerSelection(selectedCustomerId!));
      await _applyCustomerErpDefaults(selectedCustomerId);
      await _loadCustomerInsight();
    }

    if (shouldAddCustomer && mounted) {
      await _showAddCustomerSheet();
    }
  }

  Future<void> _showAddCustomerSheet() async {
    final appState = context.read<SalesOrderState>();
    final company = _activeCompany();
    final nameCtrl = TextEditingController(text: _customerCtrl.text.trim());
    final formKey = GlobalKey<FormState>();
    String? selectedSeries = _customerSeriesOptions.isNotEmpty
        ? _customerSeriesOptions.first
        : null;
    String? selectedType = _customerTypeOptions.isNotEmpty
        ? _customerTypeOptions.first
        : null;
    String? selectedGroup = _customerGroupOptions.isNotEmpty
        ? _customerGroupOptions.first
        : null;
    String? selectedTerritory = _territoryOptions.isNotEmpty
        ? _territoryOptions.first
        : null;
    String? selectedPaymentTerms = _paymentTermsOptions.isNotEmpty
        ? _paymentTermsOptions.first
        : null;

    if (company.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih Company terlebih dahulu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        var isCreatingCustomer = false;
        var sheetOpen = true;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              if (selectedSeries == null ||
                  selectedType == null ||
                  selectedPaymentTerms == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Series, tipe customer, dan payment terms wajib tersedia.',
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              setSheetState(() => isCreatingCustomer = true);
              try {
                final created = await appState.createCustomer(
                  customerName: nameCtrl.text.trim(),
                  customerType: selectedType!,
                  namingSeries: selectedSeries!,
                  paymentTerms: selectedPaymentTerms!,
                  company: company,
                  customerGroup: selectedGroup,
                  territory: selectedTerritory,
                );
                final customerId =
                    created['name']?.toString() ?? nameCtrl.text.trim();
                if (!mounted || !sheetContext.mounted) return;
                setState(() {
                  _customerCtrl.text = customerId;
                  _customerError = null;
                  if (!_customerOptions.any(
                    (customer) => customer.id == customerId,
                  )) {
                    _customerOptions = [
                      _CustomerOption(
                        id: customerId,
                        name: nameCtrl.text.trim(),
                      ),
                      ..._customerOptions,
                    ];
                  }
                });
                setSheetState(() => isCreatingCustomer = false);
                sheetOpen = false;
                Navigator.of(sheetContext).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text('Customer $customerId berhasil dibuat'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text('Gagal membuat customer: $e'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              } finally {
                if (mounted && sheetOpen) {
                  setSheetState(() => isCreatingCustomer = false);
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Add Customer',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Customer Name',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Customer name wajib diisi'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    _buildSheetDropdown(
                      label: 'Series',
                      value: selectedSeries,
                      options: _customerSeriesOptions,
                      onChanged: (value) =>
                          setSheetState(() => selectedSeries = value),
                    ),
                    const SizedBox(height: 10),
                    _buildSheetDropdown(
                      label: 'Customer Type',
                      value: selectedType,
                      options: _customerTypeOptions,
                      onChanged: (value) =>
                          setSheetState(() => selectedType = value),
                    ),
                    const SizedBox(height: 10),
                    _buildSheetDropdown(
                      label: 'Customer Group',
                      value: selectedGroup,
                      options: _customerGroupOptions,
                      requiredField: false,
                      onChanged: (value) =>
                          setSheetState(() => selectedGroup = value),
                    ),
                    const SizedBox(height: 10),
                    _buildSheetDropdown(
                      label: 'Territory',
                      value: selectedTerritory,
                      options: _territoryOptions,
                      requiredField: false,
                      onChanged: (value) =>
                          setSheetState(() => selectedTerritory = value),
                    ),
                    const SizedBox(height: 10),
                    _buildSheetDropdown(
                      label: 'Payment Terms',
                      value: selectedPaymentTerms,
                      options: _paymentTermsOptions,
                      onChanged: (value) =>
                          setSheetState(() => selectedPaymentTerms = value),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: isCreatingCustomer ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: isCreatingCustomer
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('Create Customer'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSheetDropdown({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    bool requiredField = true,
  }) {
    final normalizedOptions = _normalizeOptions(options);
    return DropdownButtonFormField<String>(
      initialValue: normalizedOptions.contains(value)
          ? value
          : (normalizedOptions.isNotEmpty ? normalizedOptions.first : null),
      decoration: InputDecoration(labelText: label),
      items: normalizedOptions
          .map((option) => DropdownMenuItem(value: option, child: Text(option)))
          .toList(),
      onChanged: normalizedOptions.isEmpty ? null : onChanged,
      validator: (value) =>
          requiredField && (value == null || value.trim().isEmpty)
          ? '$label wajib diisi'
          : null,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dateOnly(_selectedDeliveryDate).isBefore(_dateOnly(_selectedDate))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery Date tidak boleh sebelum Transaction Date'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_selectedSeries == null || _selectedSeries!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Naming series Sales Order wajib dipilih'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_selectedCompany == null || _selectedCompany!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Company wajib dipilih'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_selectedWarehouse == null || _selectedWarehouse!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Warehouse wajib dipilih'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final appState = context.read<SalesOrderState>();
    final customerSalesTeam = _selectedCustomerOption()?.salesTeam ?? const [];
    final isSalesUser = appState.mobileAccess.isSalesUser;
    if (isSalesUser && customerSalesTeam.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appState.salesIdentityError ??
                'Customer belum memiliki Sales Team untuk akun Sales ini.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!isSalesUser &&
        (_selectedSalesPerson == null ||
            _selectedSalesPerson!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sales Person wajib dipilih'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_customerError != null || _itemError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Silakan validasi customer dan item terlebih dahulu'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final invalidAdditionalItem = _additionalItems.any((row) {
      final qty = double.tryParse(row.qtyController.text.trim());
      final rateText = row.rateController.text.trim();
      final rate = rateText.isEmpty ? 0 : _itemRate(rateText);
      return row.itemCode == null ||
          row.itemCode!.isEmpty ||
          qty == null ||
          qty <= 0 ||
          rate < 0;
    });
    if (invalidAdditionalItem) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lengkapi item tambahan, qty, dan harga dengan benar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      setState(() {
        _isSaving = true;
      });

      await _ensureWarehouseEnabled(appState);
      final itemCode = (_selectedItemCode ?? '').isNotEmpty
          ? _selectedItemCode!
          : _normalizeItemCode(_itemTextController?.text ?? '');
      if (itemCode.isEmpty) {
        throw Exception('Item code tidak boleh kosong');
      }
      final items = _buildItemsPayload(itemCode);
      if (!await _confirmOrderRisks(items)) return;
      final SalesOrder savedOrder;
      if (widget.isEditMode) {
        savedOrder = await appState.updateSalesOrder(
          orderId: widget.editOrderId!,
          customer: _customerCtrl.text.trim(),
          items: items,
          warehouse: _selectedWarehouse,
          costCenter: _selectedCenter,
          company: _selectedCompany,
          currency: _selectedCurrency,
          sellingPriceList: _selectedPriceList,
          priceListCurrency: _priceListCurrency,
          ignorePricingRule: false,
          salesPerson: _selectedSalesPerson,
          noted: _notedCtrl.text.trim(),
          transactionDate: _selectedDate,
          deliveryDate: _selectedDeliveryDate,
          refreshAfterSave: false,
        );
      } else {
        savedOrder = await appState.createSalesOrder(
          customer: _customerCtrl.text.trim(),
          items: items,
          warehouse: _selectedWarehouse,
          series: _selectedSeries,
          costCenter: _selectedCenter,
          company: _selectedCompany,
          currency: _selectedCurrency,
          sellingPriceList: _selectedPriceList,
          priceListCurrency: _priceListCurrency,
          salesPerson: _selectedSalesPerson,
          noted: _notedCtrl.text.trim(),
          transactionDate: _selectedDate,
          deliveryDate: _selectedDeliveryDate,
          refreshAfterSave: false,
        );
      }
      var failedUploads = 0;
      final uploadErrors = <String>[];
      for (final photo in _photos) {
        try {
          await appState.uploadSalesOrderAttachment(savedOrder.id, photo.path);
        } catch (error) {
          failedUploads++;
          uploadErrors.add(error.toString());
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.isEditMode ? 'Sales Order berhasil diperbarui' : 'Sales Order berhasil dibuat'}'
            '${failedUploads > 0 ? ', tetapi $failedUploads foto gagal di-upload' : ''}',
          ),
          backgroundColor: failedUploads > 0
              ? Colors.orange
              : AppColors.primary,
        ),
      );
      if (uploadErrors.isNotEmpty && mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Upload Attachment Gagal'),
            content: Text(uploadErrors.join('\n\n')),
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditMode
                ? 'Gagal memperbarui Sales Order: $e'
                : 'Gagal membuat Sales Order: $e',
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

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  Future<void> _loadSelectors() async {
    final appState = context.read<SalesOrderState>();
    setState(() {
      _isLoadingSelectors = true;
      _selectorLoadError = null;
    });

    try {
      final selectorErrors = <String>[];
      final seriesFuture = _loadSelector<List<String>>(
        label: 'Series Sales Order',
        load: () => _fetchSalesOrderSeriesOptions(appState),
        fallback: const [],
        errors: selectorErrors,
      );
      final costCentersFuture = _loadSelector<List<_CostCenterOption>>(
        label: 'Cost Center',
        load: () => _fetchCostCenterOptions(appState),
        fallback: const [],
        errors: selectorErrors,
      );
      final customerSeriesFuture = _loadSelector<List<String>>(
        label: 'Customer Naming Series',
        load: () => _fetchDocTypeSelectOptions(
          appState,
          doctype: 'Customer',
          fieldname: 'naming_series',
        ),
        fallback: const [],
        errors: selectorErrors,
      );
      final customerTypeFuture = _loadSelector<List<String>>(
        label: 'Customer Type',
        load: () => _fetchDocTypeSelectOptions(
          appState,
          doctype: 'Customer',
          fieldname: 'customer_type',
        ),
        fallback: const [],
        errors: selectorErrors,
      );
      final customerGroupFuture = _loadSelector<List<String>>(
        label: 'Customer Group',
        load: () => _fetchLinkOptions(
          appState,
          doctype: 'Customer Group',
          filters: const [
            ['is_group', '=', 0],
          ],
        ),
        fallback: const [],
        errors: selectorErrors,
      );
      final territoryFuture = _loadSelector<List<String>>(
        label: 'Territory',
        load: () => _fetchLinkOptions(
          appState,
          doctype: 'Territory',
          filters: const [
            ['is_group', '=', 0],
          ],
        ),
        fallback: const [],
        errors: selectorErrors,
      );
      final paymentTermsFuture = _loadSelector<List<String>>(
        label: 'Payment Terms Template',
        load: () =>
            _fetchLinkOptions(appState, doctype: 'Payment Terms Template'),
        fallback: const [],
        errors: selectorErrors,
      );
      final salesPersonFuture = _loadSelector<List<String>>(
        label: 'Sales Person',
        load: () => _fetchSalesPersonOptions(appState),
        fallback: const [],
        errors: selectorErrors,
      );
      final currencyFuture = _loadSelector<List<String>>(
        label: 'Currency',
        load: () => _fetchLinkOptions(appState, doctype: 'Currency'),
        fallback: const [],
        errors: selectorErrors,
      );
      final priceListFuture = _loadSelector<List<String>>(
        label: 'Price List',
        load: () => _fetchLinkOptions(
          appState,
          doctype: 'Price List',
          filters: const [
            ['selling', '=', 1],
            ['enabled', '=', 1],
          ],
        ),
        fallback: const [],
        errors: selectorErrors,
      );
      final sellingSettingsFuture = appState.frappeService
          .fetchDocument('Selling Settings', 'Selling Settings')
          .catchError((_) => <String, dynamic>{});
      final salesCustomersFuture = _loadSelector<List<SalesCustomerOption>>(
        label: 'Customer / Sales Team',
        load: appState.fetchSalesCustomers,
        fallback: const [],
        errors: selectorErrors,
      );
      final itemDataFuture = _loadSelector<List<Map<String, dynamic>>>(
        label: 'Item',
        load: () => appState.fetchSellableItems(limit: 200),
        fallback: const [],
        errors: selectorErrors,
      );
      final warehouseFuture = appState.warehouses.isEmpty
          ? _loadSelector<void>(
              label: 'Warehouse',
              load: appState.refreshWarehouses,
              fallback: null,
              errors: selectorErrors,
            )
          : Future<void>.value();

      final seriesOptions = await seriesFuture;
      final costCenters = await costCentersFuture;
      final customerSeriesOptions = await customerSeriesFuture;
      final customerTypeOptions = await customerTypeFuture;
      final customerGroupOptions = await customerGroupFuture;
      final territoryOptions = await territoryFuture;
      final paymentTermsOptions = await paymentTermsFuture;
      final salesPersonOptions = await salesPersonFuture;
      final currencyOptions = await currencyFuture;
      var priceListOptions = await priceListFuture;
      if (priceListOptions.isEmpty) {
        priceListOptions = await _loadSelector<List<String>>(
          label: 'Price List',
          load: () => _fetchLinkOptions(
            appState,
            doctype: 'Price List',
            filters: const [
              ['selling', '=', 1],
            ],
          ),
          fallback: const [],
          errors: selectorErrors,
        );
      }
      final sellingSettings = await sellingSettingsFuture;
      final defaultSellingPriceList =
          sellingSettings['selling_price_list']?.toString() ??
          sellingSettings['default_price_list']?.toString() ??
          '';
      final salesCustomers = await salesCustomersFuture;
      var customerOptions = salesCustomers
          .map(
            (customer) => _CustomerOption(
              id: customer.id,
              name: customer.name,
              salesTeam: customer.salesTeam,
            ),
          )
          .toList();
      if (appState.mobileAccess.isSalesUser) {
        final salesPerson = appState.currentSalesPerson?.trim() ?? '';
        customerOptions = customerOptions.where((customer) {
          return salesPerson.isNotEmpty &&
              customer.salesTeam.any(
                (row) => row['sales_person']?.toString().trim() == salesPerson,
              );
        }).toList();
      }

      final itemData = await itemDataFuture;
      final itemOptions = itemData
          .map(_itemOptionFromRow)
          .whereType<_ItemOption>()
          .toList();

      await warehouseFuture;
      final warehouseOptions = _warehouseOptions(appState);
      final companyOptions = <String>{
        ...appState.sellingCompanies,
        ...warehouseOptions
            .map((warehouse) => warehouse.company)
            .where((company) => company.trim().isNotEmpty),
      }.toList()..sort();
      final warehouseCompany = _selectedWarehouseInfo(
        warehouseOptions,
      )?.company;
      final selectedCompany = companyOptions.contains(_selectedCompany)
          ? _selectedCompany
          : (companyOptions.contains(warehouseCompany)
                ? warehouseCompany
                : appState.preferredCompany(companyOptions));
      final companyWarehouses = selectedCompany?.isNotEmpty == true
          ? warehouseOptions
                .where((warehouse) => warehouse.company == selectedCompany)
                .toList()
          : warehouseOptions;
      final selectedWarehouseValid = companyWarehouses.any(
        (warehouse) => warehouse.name == _selectedWarehouse,
      );
      final selectedWarehouse = selectedWarehouseValid
          ? _selectedWarehouse
          : appState.preferredWarehouse(companyWarehouses);
      String companyCurrency = '';
      if (selectedCompany?.isNotEmpty == true) {
        try {
          final companyDoc = await appState.frappeService.fetchDocument(
            'Company',
            selectedCompany!,
          );
          companyCurrency =
              companyDoc['default_currency']?.toString() ??
              companyDoc['currency']?.toString() ??
              '';
        } catch (_) {}
      }
      final availableCostCenters = selectedCompany?.isNotEmpty != true
          ? costCenters
          : costCenters
                .where((center) => center.company == selectedCompany)
                .toList();
      final costCenterChoices = availableCostCenters.isNotEmpty
          ? availableCostCenters
          : costCenters;
      final defaultCostCenter = costCenterChoices.isNotEmpty
          ? costCenterChoices.first.name
          : null;

      if (!mounted) return;
      setState(() {
        _seriesOptions = _normalizeOptions(seriesOptions);
        _seriesError = seriesOptions.isEmpty
            ? 'Series Sales Order tidak dapat dibaca.'
            : null;
        _selectorLoadError = selectorErrors.isEmpty
            ? null
            : selectorErrors.toSet().join('\n');
        _customerSeriesOptions = _normalizeOptions(customerSeriesOptions);
        _customerTypeOptions = _normalizeOptions(customerTypeOptions);
        _customerGroupOptions = _normalizeOptions(customerGroupOptions);
        _territoryOptions = _normalizeOptions(territoryOptions);
        _paymentTermsOptions = _normalizeOptions(paymentTermsOptions);
        _salesPersonOptions = _normalizeOptions(salesPersonOptions);
        _companyOptions = _normalizeOptions(companyOptions);
        _currencyOptions = _normalizeOptions(currencyOptions);
        _priceListOptions = _normalizeOptions(priceListOptions);
        _costCenterOptions = _normalizeCostCenterOptions(costCenters);
        _customerOptions = customerOptions;
        _selectedSeries = _seriesOptions.contains(_selectedSeries)
            ? _selectedSeries
            : (_seriesOptions.isNotEmpty ? _seriesOptions.first : null);
        _selectedCompany = selectedCompany;
        _selectedCenter =
            _selectedCenter?.trim().isNotEmpty == true &&
                _ensureSelectedCostCenterOption(
                  costCenterChoices,
                ).any((center) => center.name == _selectedCenter)
            ? _selectedCenter
            : (defaultCostCenter ??
                  (costCenterChoices.isNotEmpty
                      ? costCenterChoices.first.name
                      : null));
        _selectedSalesPerson = appState.mobileAccess.isSalesUser
            ? appState.currentSalesPerson
            : (_salesPersonOptions.contains(_selectedSalesPerson)
                  ? _selectedSalesPerson
                  : null);
        _itemOptions = itemOptions;
        _selectedWarehouse = selectedWarehouse;
        _selectedCurrency = _currencyOptions.contains(_selectedCurrency)
            ? _selectedCurrency
            : (_currencyOptions.contains(companyCurrency)
                  ? companyCurrency
                  : (_currencyOptions.isNotEmpty
                        ? _currencyOptions.first
                        : null));
        _selectedPriceList = _priceListOptions.contains(_selectedPriceList)
            ? _selectedPriceList
            : (_priceListOptions.contains(defaultSellingPriceList)
                  ? defaultSellingPriceList
                  : (_priceListOptions.isNotEmpty
                        ? _priceListOptions.first
                        : null));
        _priceListCurrency ??= _selectedCurrency;
      });
      if (widget.isEditMode) {
        final editingOrder = await appState.loadSalesOrderDetail(
          widget.editOrderId!,
        );
        if (!mounted) return;
        _applyOrderToForm(editingOrder, keepCurrentDates: false);
      } else if (widget.isDuplicateMode) {
        _applyOrderToForm(widget.duplicateFrom!, keepCurrentDates: true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _selectorLoadError = _selectorErrorMessage(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSelectors = false;
        });
      }
    }
  }

  void _applyOrderToForm(SalesOrder order, {required bool keepCurrentDates}) {
    final firstItem = order.items.isNotEmpty ? order.items.first : null;
    for (final row in _additionalItems) {
      row.dispose();
    }
    _additionalItems.clear();
    for (final item in order.items.skip(1)) {
      final row = _AdditionalItemRow(
        itemCode: item.itemCode,
        itemLabel: item.itemCode.isNotEmpty
            ? '${item.itemName} - ${item.itemCode}'
            : item.itemName,
        qty: item.qty.toString(),
        rate: item.rate > 0 ? _formatRupiah(item.rate) : '',
        discount: item.discountAmount > 0
            ? _formatRupiah(item.discountAmount)
            : '0',
        warehouse: item.warehouse.isNotEmpty ? item.warehouse : null,
      );
      row.qtyController.addListener(_onPricingInputChanged);
      row.rateController.addListener(_calculateTotal);
      row.discountController.addListener(_calculateTotal);
      _additionalItems.add(row);
    }
    setState(() {
      _customerCtrl.text = order.customerId;
      _selectedCurrency = order.currency.isNotEmpty
          ? order.currency
          : _selectedCurrency;
      _selectedPriceList = order.sellingPriceList.isNotEmpty
          ? order.sellingPriceList
          : _selectedPriceList;
      _priceListCurrency = order.priceListCurrency.isNotEmpty
          ? order.priceListCurrency
          : _priceListCurrency;
      final orderCostCenter = order.costCenter.trim().isNotEmpty
          ? order.costCenter.trim()
          : firstItem?.costCenter.trim() ?? '';
      if (orderCostCenter.isNotEmpty) {
        _selectedCenter = orderCostCenter;
      }
      _notedCtrl.text = order.noted;
      _discountCtrl.text = firstItem?.discountAmount != null
          ? _formatRupiah(firstItem!.discountAmount)
          : '0';
      if (!keepCurrentDates) {
        _selectedDate = DateTime.tryParse(order.date) ?? _selectedDate;
        final deliveryDate = order.deliveryDate.isNotEmpty
            ? order.deliveryDate
            : firstItem?.deliveryDate;
        _selectedDeliveryDate =
            DateTime.tryParse(deliveryDate ?? '') ?? _selectedDeliveryDate;
      }
      if (order.salesPerson.isNotEmpty &&
          _salesPersonOptions.contains(order.salesPerson)) {
        _selectedSalesPerson = order.salesPerson;
      }
      if (firstItem != null) {
        _selectedItemCode = firstItem.itemCode.isNotEmpty
            ? firstItem.itemCode
            : firstItem.itemName;
        _qtyCtrl.text = firstItem.qty.toString();
        _rateCtrl.text = firstItem.rate > 0
            ? _formatRupiah(firstItem.rate)
            : '';
        if (firstItem.warehouse.isNotEmpty) {
          _selectedWarehouse = firstItem.warehouse;
          final warehouse = _selectedWarehouseInfo(
            _warehouseOptions(context.read<SalesOrderState>()),
          );
          if (warehouse?.company.isNotEmpty == true) {
            _selectedCompany = warehouse!.company;
          }
        }
        _initialItemText = firstItem.itemCode.isNotEmpty
            ? '${firstItem.itemName} - ${firstItem.itemCode}'
            : firstItem.itemName;
        _itemTextController?.text = _initialItemText!;
      }
      _customerError = null;
      _itemError = null;
    });
    _loadCustomerInsight();
    _calculateTotal();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<SalesOrderState>();
    final warehouseOptions = _warehousesForCompany(appState);
    final costCenterOptions = _costCentersForCompany();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        centerTitle: false,
        titleSpacing: 16,
        title: Text(
          _screenTitle,
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
                if (_selectorLoadError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Sebagian data tidak dapat dibaca',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectorLoadError!,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Coba lagi',
                          onPressed: _isLoadingSelectors
                              ? null
                              : _loadSelectors,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Document Info Section
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
                        'Informasi Sales Order',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.slate,
                        ),
                      ),

                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        initialValue: _seriesOptions.isNotEmpty
                            ? (_seriesOptions.contains(_selectedSeries)
                                  ? _selectedSeries
                                  : _seriesOptions.first)
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Series',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        items: _seriesOptions
                            .map(
                              (series) => DropdownMenuItem(
                                value: series,
                                child: Text(series),
                              ),
                            )
                            .toList(),
                        onChanged: _seriesOptions.isEmpty
                            ? null
                            : (v) => setState(() => _selectedSeries = v),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Series wajib dipilih'
                            : null,
                        hint: _isLoadingSelectors
                            ? const Text('Loading series...')
                            : const Text('Pilih series'),
                      ),
                      if (_seriesError != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _seriesError!,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _isLoadingSelectors
                                  ? null
                                  : _loadSelectors,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ],

                      if (!appState.mobileAccess.isSalesUser) ...[
                        const SizedBox(height: 12),
                        ErpItemAutocompleteField(
                          label: 'Sales Person',
                          selectedId:
                              _salesPersonOptions.contains(_selectedSalesPerson)
                              ? _selectedSalesPerson
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Sales Person',
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                          options: _salesPersonOptions
                              .map(
                                (salesPerson) => ErpItemOption(
                                  id: salesPerson,
                                  label: salesPerson,
                                ),
                              )
                              .toList(),
                          onSelected: (value) =>
                              setState(() => _selectedSalesPerson = value),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Sales Person wajib dipilih'
                              : null,
                        ),
                      ],

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
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

                                    if (_dateOnly(
                                      _selectedDeliveryDate,
                                    ).isBefore(_dateOnly(picked))) {
                                      _selectedDeliveryDate = picked;
                                    }
                                  });
                                  _scheduleRepriceAllItems();
                                }
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
                                          'Date',
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
                                      ).format(_selectedDate),
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
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _dateOnly(
                                        _selectedDeliveryDate,
                                      ).isBefore(_dateOnly(_selectedDate))
                                      ? _dateOnly(_selectedDate)
                                      : _selectedDeliveryDate,
                                  firstDate: _dateOnly(_selectedDate),
                                  lastDate: DateTime(2030),
                                );

                                if (picked != null) {
                                  setState(
                                    () => _selectedDeliveryDate = picked,
                                  );
                                }
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
                                          Icons.local_shipping_outlined,
                                          size: 14,
                                          color: AppColors.slate,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Delivery',
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
                                      ).format(_selectedDeliveryDate),
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
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      ErpItemAutocompleteField(
                        label: 'Company',
                        selectedId: _companyOptions.contains(_selectedCompany)
                            ? _selectedCompany
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Company',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        options: _companyOptions
                            .map(
                              (company) =>
                                  ErpItemOption(id: company, label: company),
                            )
                            .toList(),
                        onSelected: _onCompanySelected,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Company wajib dipilih'
                            : null,
                      ),

                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _customerCtrl,
                        readOnly: true,
                        onTap: _isCustomerLocked
                            ? null
                            : _showCustomerSelectSheet,
                        decoration: InputDecoration(
                          labelText: 'Nama Customer',
                          hintText: _isLoadingSelectors
                              ? 'Loading customer...'
                              : (_isCustomerLocked
                                    ? 'Customer dikunci dari dokumen asal'
                                    : 'Pilih atau search customer'),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          suffixIcon: _isCustomerLocked
                              ? const Icon(Icons.lock_outline_rounded)
                              : _customerCtrl.text.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Bersihkan Customer',
                                  onPressed: _clearCustomer,
                                  icon: const Icon(Icons.close_rounded),
                                )
                              : const Icon(Icons.search_rounded),
                          errorText: _customerError,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Customer wajib diisi'
                            : null,
                      ),
                      if (_selectedCustomerName().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          key: ValueKey(
                            'customer_name_${_customerCtrl.text.trim()}',
                          ),
                          initialValue: _selectedCustomerName(),
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Customer Name',
                            filled: true,
                            fillColor: AppColors.background,
                            prefixIcon: const Icon(Icons.storefront_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ErpItemAutocompleteField(
                        label: 'Cost Center',
                        selectedId:
                            costCenterOptions.any(
                              (center) => center.name == _selectedCenter,
                            )
                            ? _selectedCenter
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Cost Center',
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        options: costCenterOptions
                            .map(
                              (center) => ErpItemOption(
                                id: center.name,
                                label: center.name,
                              ),
                            )
                            .toList(),
                        onSelected: (v) => setState(() => _selectedCenter = v),
                      ),
                      const SizedBox(height: 12),
                      if (warehouseOptions.isNotEmpty)
                        ErpItemAutocompleteField(
                          key: ValueKey(
                            'warehouse:${_selectedWarehouse ?? ''}',
                          ),
                          label: 'Warehouse',
                          selectedId:
                              warehouseOptions.any(
                                (warehouse) =>
                                    warehouse.name == _selectedWarehouse,
                              )
                              ? _selectedWarehouse
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Warehouse',
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                          options: warehouseOptions
                              .map(
                                (warehouse) => ErpItemOption(
                                  id: warehouse.name,
                                  label: warehouse.name,
                                ),
                              )
                              .toList(),
                          onSelected: (value) {
                            setState(() => _selectedWarehouse = value);
                            _loadCustomerInsight();
                            _scheduleRepriceAllItems();
                          },
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Warehouse wajib dipilih'
                              : null,
                        )
                      else
                        const Text(
                          'Warehouse tidak tersedia untuk Company ini.',
                          style: TextStyle(color: Colors.orange),
                        ),
                      if (_isLoadingCustomerInsight) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(),
                      ] else if (_customerInsight != null) ...[
                        const SizedBox(height: 10),
                        _CustomerInsightCard(
                          insight: _customerInsight!,
                          orderTotal: _totalAmount,
                          onHistory: _showCustomerHistory,
                        ),
                      ] else if (_customerInsightError != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Informasi kredit customer gagal dimuat.',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              TextButton.icon(
                                onPressed: _loadCustomerInsight,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Retry informasi customer'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: AppColors.cardShadow,
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Currency & Price List',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.slate,
                        ),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Currency',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          _selectedCurrency ?? '-',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Selling Price List',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          _selectedPriceList ??
                              (_priceListOptions.isEmpty
                                  ? 'Price List tidak tersedia'
                                  : '-'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_priceListCurrency != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Price List Currency: $_priceListCurrency',
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 11,
                          ),
                        ),
                      ],
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
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Items',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navy,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed:
                                _selectedItemCode == null &&
                                    (_itemTextController?.text.isEmpty ?? true)
                                ? null
                                : _clearPrimaryItem,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Hapus Item'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _itemTextController,
                        readOnly: true,
                        onTap: _selectPrimaryItem,
                        decoration: InputDecoration(
                          labelText: 'Nama Item / Kode',
                          hintText: 'Pilih atau search item',
                          prefixIcon: const Icon(Icons.inventory_2_rounded),
                          suffixIcon: _isValidatingItem
                              ? const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  tooltip: 'Search item',
                                  onPressed: _selectPrimaryItem,
                                  icon: const Icon(Icons.search_rounded),
                                ),
                          filled: true,
                          fillColor: AppColors.background,
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
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
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
                        controller: _qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Quantity',
                          prefixIcon: IconButton(
                            tooltip: 'Kurangi quantity',
                            onPressed: () => _adjustQuantity(_qtyCtrl, -1),
                            icon: const Icon(Icons.remove_rounded),
                          ),
                          suffixIcon: IconButton(
                            tooltip: 'Tambah quantity',
                            onPressed: () => _adjustQuantity(_qtyCtrl, 1),
                            icon: const Icon(Icons.add_rounded),
                          ),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        validator: (v) {
                          final q = double.tryParse(v?.trim() ?? '');
                          if (q == null || q <= 0) return 'Qty > 0';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _rateCtrl,
                        readOnly: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onEditingComplete: () =>
                            _formatMoneyController(_rateCtrl),
                        onTapOutside: (_) => _formatMoneyController(_rateCtrl),
                        decoration: InputDecoration(
                          labelText: 'Harga/Unit',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final r = _itemRate(v);
                          if (r < 0) return 'Harga >= 0';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _discountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onEditingComplete: () =>
                            _formatMoneyController(_discountCtrl),
                        onTapOutside: (_) =>
                            _formatMoneyController(_discountCtrl),
                        decoration: InputDecoration(
                          labelText: 'Discount Amount',
                          prefixIcon: const Icon(Icons.discount_outlined),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        validator: (value) {
                          final discount = _itemDiscount(value ?? '');
                          if (discount < 0) {
                            return 'Diskon harus 0 atau lebih';
                          }
                          final rate = _itemRate(_rateCtrl.text);
                          if (rate > 0 && discount > rate) {
                            return 'Diskon tidak boleh melebihi harga';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _ItemSubtotalSummary(
                        qty: _itemQty(_qtyCtrl.text),
                        rate: _itemRate(_rateCtrl.text),
                        discount: _itemDiscount(_discountCtrl.text),
                        effectiveRate: _effectiveItemRate(
                          rateText: _rateCtrl.text,
                          discountText: _discountCtrl.text,
                        ),
                        subtotal: _itemSubtotal(
                          qtyText: _qtyCtrl.text,
                          rateText: _rateCtrl.text,
                          discountText: _discountCtrl.text,
                        ),
                        formatCurrency: _formatRupiah,
                      ),
                      const SizedBox(height: 12),
                      ..._additionalItems.asMap().entries.map((entry) {
                        final index = entry.key;
                        final row = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.18),
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Item ${index + 2}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.navy,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Hapus item',
                                    onPressed: () => _removeItemRow(index),
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
                                onTap: () => _selectAdditionalItem(row),
                                decoration: InputDecoration(
                                  labelText: 'Nama Item / Kode',
                                  hintText: 'Pilih atau search item',
                                  prefixIcon: const Icon(
                                    Icons.inventory_2_rounded,
                                  ),
                                  suffixIcon: IconButton(
                                    tooltip: 'Search item',
                                    onPressed: () => _selectAdditionalItem(row),
                                    icon: const Icon(Icons.search_rounded),
                                  ),
                                  filled: true,
                                  fillColor: AppColors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.16,
                                      ),
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.10,
                                      ),
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.36,
                                      ),
                                      width: 1.4,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (row.itemCode == null ||
                                      row.itemCode!.trim().isEmpty) {
                                    return 'Item wajib dipilih';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: row.qtyController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: 'Quantity',
                                  prefixIcon: IconButton(
                                    tooltip: 'Kurangi quantity',
                                    onPressed: () =>
                                        _adjustQuantity(row.qtyController, -1),
                                    icon: const Icon(Icons.remove_rounded),
                                  ),
                                  suffixIcon: IconButton(
                                    tooltip: 'Tambah quantity',
                                    onPressed: () =>
                                        _adjustQuantity(row.qtyController, 1),
                                    icon: const Icon(Icons.add_rounded),
                                  ),
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
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: row.rateController,
                                readOnly: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onEditingComplete: () =>
                                    _formatMoneyController(row.rateController),
                                onTapOutside: (_) =>
                                    _formatMoneyController(row.rateController),
                                decoration: const InputDecoration(
                                  labelText: 'Harga/Unit',
                                  prefixIcon: Icon(Icons.lock_outline_rounded),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return null;
                                  }
                                  final rate = _itemRate(value);
                                  return rate < 0 ? 'Harga >= 0' : null;
                                },
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: row.discountController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onEditingComplete: () => _formatMoneyController(
                                  row.discountController,
                                ),
                                onTapOutside: (_) => _formatMoneyController(
                                  row.discountController,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Discount Amount',
                                  prefixIcon: Icon(Icons.discount_outlined),
                                ),
                                validator: (value) {
                                  final discount = _itemDiscount(value ?? '');
                                  if (discount < 0) {
                                    return 'Diskon harus 0 atau lebih';
                                  }
                                  final rate = _itemRate(
                                    row.rateController.text,
                                  );
                                  if (rate > 0 && discount > rate) {
                                    return 'Diskon tidak boleh melebihi harga';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 10),
                              _ItemSubtotalSummary(
                                qty: _itemQty(row.qtyController.text),
                                rate: _itemRate(row.rateController.text),
                                discount: _itemDiscount(
                                  row.discountController.text,
                                ),
                                effectiveRate: _effectiveItemRate(
                                  rateText: row.rateController.text,
                                  discountText: row.discountController.text,
                                ),
                                subtotal: _itemSubtotal(
                                  qtyText: row.qtyController.text,
                                  rateText: row.rateController.text,
                                  discountText: row.discountController.text,
                                ),
                                formatCurrency: _formatRupiah,
                              ),
                            ],
                          ),
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
                              'Total Amount',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.slate,
                              ),
                            ),
                            Text(
                              'Rp ${_formatRupiah(_totalAmount)}',
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

                _SalesOrderNotedCard(controller: _notedCtrl),

                const SizedBox(height: 16),

                _AttachmentCard(
                  photos: _photos,
                  onCamera: () => _pickPhoto(ImageSource.camera),
                  onGallery: () => _pickPhoto(ImageSource.gallery),
                  onRemove: (index) => setState(() => _photos.removeAt(index)),
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
          child: ElevatedButton(
            onPressed:
                (_isSaving ||
                    _isLoadingSelectors ||
                    _isValidatingItem ||
                    _selectedSeries == null)
                ? null
                : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    _saveButtonLabel,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ItemOption {
  final String code;
  final String name;

  _ItemOption({required this.code, required this.name});

  String get label => '$name - $code';
}

class _CustomerOption {
  final String id;
  final String name;
  final List<Map<String, dynamic>> salesTeam;

  const _CustomerOption({
    required this.id,
    required this.name,
    this.salesTeam = const [],
  });
}

class _CostCenterOption {
  final String name;
  final String company;

  const _CostCenterOption({required this.name, required this.company});
}

class _AdditionalItemRow {
  String? itemCode;
  String? warehouse;
  final TextEditingController qtyController;
  final TextEditingController rateController;
  final TextEditingController discountController;
  final TextEditingController itemTextController;

  _AdditionalItemRow({
    this.itemCode,
    String itemLabel = '',
    String qty = '1',
    String rate = '',
    String discount = '0',
    this.warehouse,
  }) : qtyController = TextEditingController(text: qty),
       rateController = TextEditingController(text: rate),
       discountController = TextEditingController(text: discount),
       itemTextController = TextEditingController(text: itemLabel);

  void dispose() {
    qtyController.dispose();
    rateController.dispose();
    discountController.dispose();
    itemTextController.dispose();
  }
}

class _SalesOrderNotedCard extends StatelessWidget {
  final TextEditingController controller;

  const _SalesOrderNotedCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Noted', style: TextStyle(fontWeight: FontWeight.w800)),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 10),
            child: Text(
              'Catatan tambahan, termasuk permintaan diskon dari customer.',
              style: TextStyle(fontSize: 11, color: AppColors.slate),
            ),
          ),
          TextFormField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: 'Noted',
              hintText: 'Contoh: Customer meminta diskon tambahan.',
              prefixIcon: const Icon(Icons.notes_rounded),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemSubtotalSummary extends StatelessWidget {
  final double qty;
  final double rate;
  final double discount;
  final double effectiveRate;
  final double subtotal;
  final String Function(double value) formatCurrency;

  const _ItemSubtotalSummary({
    required this.qty,
    required this.rate,
    required this.discount,
    required this.effectiveRate,
    required this.subtotal,
    required this.formatCurrency,
  });

  @override
  Widget build(BuildContext context) {
    final qtyLabel = qty == qty.roundToDouble()
        ? qty.toInt().toString()
        : qty.toStringAsFixed(2);
    final notes = <String>[
      'Harga asli Rp ${formatCurrency(rate)}',
      if (discount > 0) 'Diskon per item Rp ${formatCurrency(discount)}',
      'Harga final Rp ${formatCurrency(effectiveRate)}',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.softGreen.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SubtotalLine(
            label:
                'Sub total ($qtyLabel x Rp ${formatCurrency(effectiveRate)})',
            value: 'Rp ${formatCurrency(subtotal)}',
            highlight: true,
          ),
          const SizedBox(height: 6),
          Text(
            notes.join(' • '),
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtotalLine extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _SubtotalLine({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight ? AppColors.primary : AppColors.navy;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 12,
              fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: highlight ? 14 : 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _CustomerInsightCard extends StatelessWidget {
  final CustomerSalesInsight insight;
  final double orderTotal;
  final VoidCallback onHistory;

  const _CustomerInsightCard({
    required this.insight,
    required this.orderTotal,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final overLimit =
        insight.creditLimit > 0 &&
        insight.projectedOutstanding(orderTotal) > insight.creditLimit;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: overLimit
            ? Colors.red.withValues(alpha: 0.06)
            : AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: overLimit
              ? Colors.red.withValues(alpha: 0.25)
              : AppColors.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Informasi Kredit Customer',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _InsightMetric(
                label: 'Credit Limit',
                value: insight.creditLimit > 0
                    ? 'Rp ${insight.creditLimit.toStringAsFixed(0)}'
                    : 'Tidak dibatasi',
              ),
              _InsightMetric(
                label: 'Outstanding',
                value: 'Rp ${insight.outstanding.toStringAsFixed(0)}',
                warning: overLimit,
              ),
              _InsightMetric(
                label: 'Deposit',
                value: 'Rp ${insight.depositBalance.toStringAsFixed(0)}',
              ),
              _InsightMetric(
                label: 'Sisa Kredit',
                value: insight.creditLimit > 0
                    ? 'Rp ${insight.availableCredit.toStringAsFixed(0)}'
                    : '-',
                warning: insight.availableCredit < 0,
              ),
              _InsightMetric(
                label: 'Total Order',
                value: 'Rp ${orderTotal.toStringAsFixed(0)}',
              ),
              _InsightMetric(
                label: 'Projected Piutang',
                value:
                    'Rp ${insight.projectedOutstanding(orderTotal).toStringAsFixed(0)}',
                warning: overLimit,
              ),
              _InsightMetric(
                label: 'Sisa Setelah Order',
                value: insight.creditLimit > 0
                    ? 'Rp ${insight.projectedAvailableCredit(orderTotal).toStringAsFixed(0)}'
                    : '-',
                warning: insight.projectedAvailableCredit(orderTotal) < 0,
              ),
              _InsightMetric(
                label: 'Price List',
                value: insight.priceList.isEmpty
                    ? 'Default'
                    : insight.priceList,
              ),
            ],
          ),
          if (insight.depositBalance > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Deposit customer tersedia Rp ${insight.depositBalance.toStringAsFixed(0)} dari AR minus.',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onHistory,
              icon: const Icon(Icons.history_rounded),
              label: const Text('Lihat history pembelian'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerHistorySheet extends StatefulWidget {
  final String customer;
  final String company;

  const _CustomerHistorySheet({required this.customer, required this.company});

  @override
  State<_CustomerHistorySheet> createState() => _CustomerHistorySheetState();
}

class _CustomerHistorySheetState extends State<_CustomerHistorySheet>
    with SingleTickerProviderStateMixin {
  static const _pageSize = 20;
  late final TabController _tabController;
  final Map<String, List<CustomerPurchaseHistory>> _rows = {
    'Sales Order': [],
    'Sales Invoice': [],
  };
  final Map<String, bool> _loading = {
    'Sales Order': false,
    'Sales Invoice': false,
  };
  final Map<String, bool> _hasMore = {
    'Sales Order': true,
    'Sales Invoice': true,
  };
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMore('Sales Order');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMore(String doctype) async {
    if (_loading[doctype] == true || _hasMore[doctype] != true) return;
    setState(() {
      _loading[doctype] = true;
      _error = null;
    });
    try {
      final page = await context
          .read<SalesOrderState>()
          .fetchCustomerPurchaseHistory(
            customer: widget.customer,
            doctype: doctype,
            company: widget.company,
            offset: _rows[doctype]!.length,
            limit: _pageSize,
          );
      if (!mounted) return;
      final known = _rows[doctype]!.map((row) => row.id).toSet();
      setState(() {
        _rows[doctype]!.addAll(page.where((row) => known.add(row.id)));
        _hasMore[doctype] = page.isNotEmpty;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading[doctype] = false);
    }
  }

  Future<void> _showDetail(CustomerPurchaseHistory row) async {
    showDialog<void>(
      context: context,
      builder: (context) => FutureBuilder<Map<String, dynamic>>(
        future: context.read<SalesOrderState>().loadSalesHistoryDetail(
          row.doctype,
          row.id,
        ),
        builder: (context, snapshot) {
          final doc = snapshot.data;
          final items = doc?['items'];
          return AlertDialog(
            title: Text(row.id),
            content: snapshot.connectionState != ConnectionState.done
                ? const SizedBox(
                    height: 80,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : snapshot.hasError
                ? Text('Gagal memuat detail: ${snapshot.error}')
                : SizedBox(
                    width: double.maxFinite,
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        Text('${row.date} | ${row.status}'),
                        const SizedBox(height: 8),
                        if (items is List)
                          ...items.map((item) {
                            final title = item is Map
                                ? item['item_name']?.toString() ??
                                      item['item_code']?.toString() ??
                                      'Item'
                                : 'Item';
                            final qty = item is Map
                                ? 'Qty ${item['qty']?.toString() ?? '0'}'
                                : '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SalesPickerOptionTile(
                                title: title,
                                subtitle: qty,
                                icon: Icons.inventory_2_rounded,
                                onTap: () {},
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTab(String doctype) {
    final rows = _rows[doctype]!;
    if (rows.isEmpty && _loading[doctype] == true) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        if (rows.isEmpty && _loading[doctype] != true)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Belum ada transaksi customer ini.'),
          ),
        ...rows.map(
          (row) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SalesPickerOptionTile(
              title: row.id,
              subtitle:
                  '${row.date} | ${row.status}'
                  '${row.itemsCount > 0 ? ' | Qty ${row.itemsCount}' : ''}'
                  '${row.outstanding > 0 ? ' | Outstanding Rp ${row.outstanding.toStringAsFixed(0)}' : ''}'
                  ' | Rp ${row.total.toStringAsFixed(0)}',
              icon: Icons.receipt_long_rounded,
              onTap: () => _showDetail(row),
            ),
          ),
        ),
        if (_hasMore[doctype] == true)
          TextButton.icon(
            onPressed: _loading[doctype] == true
                ? null
                : () => _loadMore(doctype),
            icon: _loading[doctype] == true
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.expand_more_rounded),
            label: const Text('Load more'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'History Pembelian Customer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            TabBar(
              controller: _tabController,
              onTap: (index) =>
                  _loadMore(index == 0 ? 'Sales Order' : 'Sales Invoice'),
              tabs: const [
                Tab(text: 'Sales Order'),
                Tab(text: 'Sales Invoice'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTab('Sales Order'),
                  _buildTab('Sales Invoice'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool warning;

  const _InsightMetric({
    required this.label,
    required this.value,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 135,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.slate),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: warning ? Colors.red : AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  final List<XFile> photos;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final ValueChanged<int> onRemove;

  const _AttachmentCard({
    required this.photos,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Attachment Sales Order',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Foto akan masuk ke panel Attachments setelah Draft Sales Order berhasil disimpan.',
              style: TextStyle(fontSize: 11, color: AppColors.slate),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Kamera'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Galeri'),
                ),
              ),
            ],
          ),
          ...photos.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.image_outlined,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.value.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => onRemove(entry.key),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
