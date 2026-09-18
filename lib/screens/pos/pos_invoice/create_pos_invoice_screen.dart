import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/pos/pos_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/pos_document_actions.dart';
import '../shared/pos_ui.dart';

class CreatePosInvoiceScreen extends StatefulWidget {
  final String? editName;

  const CreatePosInvoiceScreen({super.key, this.editName});

  @override
  State<CreatePosInvoiceScreen> createState() => _CreatePosInvoiceScreenState();
}

class _ItemRow {
  String? itemCode;
  final TextEditingController qtyCtrl;
  final TextEditingController rateCtrl;
  final TextEditingController discountCtrl;

  _ItemRow({
    this.itemCode,
    String qty = '1',
    String rate = '0',
    String discount = '0',
  }) : qtyCtrl = TextEditingController(text: qty),
       rateCtrl = TextEditingController(text: rate),
       discountCtrl = TextEditingController(text: discount);

  double get qty => double.tryParse(qtyCtrl.text.trim()) ?? 0;
  double get rate => double.tryParse(rateCtrl.text.trim()) ?? 0;
  double get discountAmount {
    final value = double.tryParse(discountCtrl.text.trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  double get amount {
    final gross = qty * rate;
    final net = gross - discountAmount;
    return net < 0 ? 0 : net;
  }

  void dispose() {
    qtyCtrl.dispose();
    rateCtrl.dispose();
    discountCtrl.dispose();
  }
}

class _PaymentRow {
  String? modeOfPayment;
  final TextEditingController amountCtrl;

  _PaymentRow({this.modeOfPayment, String amount = '0'})
    : amountCtrl = TextEditingController(text: amount);

  double get amount => double.tryParse(amountCtrl.text.trim()) ?? 0;

  void dispose() => amountCtrl.dispose();
}

class _SalesTeamRow {
  String? salesPerson;
  final TextEditingController contributionCtrl;

  _SalesTeamRow({this.salesPerson, String contribution = '100'})
    : contributionCtrl = TextEditingController(text: contribution);

  double get contribution {
    final value = double.tryParse(contributionCtrl.text.trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  void dispose() => contributionCtrl.dispose();
}

class _CostCenterOption {
  final String name;
  final String company;

  const _CostCenterOption({required this.name, this.company = ''});
}

class _LinkOption {
  final String id;
  final String label;
  final double rate;

  const _LinkOption({required this.id, required this.label, this.rate = 0});
}

class _CreatePosInvoiceScreenState extends State<CreatePosInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _discountCtrl = TextEditingController(text: '0');

  List<String> _profiles = const [];
  List<String> _companies = const [];
  List<String> _warehouses = const [];
  List<_CostCenterOption> _costCenters = const [];
  List<_LinkOption> _customers = const [];
  List<_LinkOption> _items = const [];
  List<_LinkOption> _salesPersons = const [];
  List<String> _modes = const [];
  List<_ItemRow> _itemRows = [];
  List<_PaymentRow> _paymentRows = [];
  List<_SalesTeamRow> _salesTeamRows = [];

  String? _posProfile;
  String? _customer;
  String? _company;
  String? _warehouse;
  String? _costCenter;
  String? _sellingPriceList;
  DateTime _postingDate = DateTime.now();
  bool _updateStock = true;
  bool _printAfterSave = true;
  bool _canPrint = false;
  bool _loading = true;
  bool _saving = false;
  bool _loadingProfile = false;
  bool _loadingCustomerDefaults = false;
  final Set<int> _loadingItemRates = {};
  String? _error;
  String? _savedName;

  bool get _isEditing => widget.editName?.trim().isNotEmpty == true;
  String? get _documentName =>
      _isEditing ? widget.editName!.trim() : _savedName;

  double get _itemsTotal =>
      _itemRows.fold<double>(0, (sum, row) => sum + row.amount);

  double get _discount {
    final value = double.tryParse(_discountCtrl.text.trim()) ?? 0;
    return value < 0 ? 0 : value;
  }

  double get _grandTotal {
    final total = _itemsTotal - _discount;
    return total < 0 ? 0 : total;
  }

  double get _paidAmount =>
      _paymentRows.fold<double>(0, (sum, row) => sum + row.amount);

  double get _changeAmount {
    final change = _paidAmount - _grandTotal;
    return change > 0 ? change : 0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    for (final row in _itemRows) {
      row.dispose();
    }
    for (final row in _paymentRows) {
      row.dispose();
    }
    for (final row in _salesTeamRows) {
      row.dispose();
    }
    super.dispose();
  }

  List<_CostCenterOption> get _costCentersForCompany {
    final company = _company?.trim() ?? '';
    if (company.isEmpty) return _costCenters;
    final filtered = _costCenters
        .where((row) => row.company.isEmpty || row.company == company)
        .toList();
    return filtered.isNotEmpty ? filtered : _costCenters;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<PosState>();
      final results = await Future.wait([
        state.fetchSelectableProfileNames(),
        state.fetchNames('Company'),
        state.fetchNames('Warehouse'),
        state.fetchLinkOptions(
          'Customer',
          fields: const ['name', 'customer_name'],
          filters: const [
            ['disabled', '=', 0],
          ],
          orderBy: 'customer_name asc',
        ),
        state.fetchLinkOptions(
          'Item',
          fields: const ['name', 'item_name', 'standard_rate'],
          filters: const [
            ['disabled', '=', 0],
            ['is_sales_item', '=', 1],
          ],
          orderBy: 'item_name asc',
        ),
        state.fetchNames(
          'Mode of Payment',
          filters: const [
            ['enabled', '=', 1],
          ],
        ),
        state.canPrintDoctype('POS Invoice'),
        state.fetchLinkOptions(
          'Cost Center',
          fields: const ['name', 'company'],
          filters: const [
            ['is_group', '=', 0],
          ],
          orderBy: 'name asc',
        ),
      ]);

      if (!mounted) return;
      final profiles = results[0] as List<String>;
      final companies = results[1] as List<String>;
      final warehouses = results[2] as List<String>;
      final customerRows = results[3] as List<Map<String, dynamic>>;
      final itemRows = results[4] as List<Map<String, dynamic>>;
      final modes = results[5] as List<String>;
      final canPrint = results[6] as bool;
      final costCenterRows = results[7] as List<Map<String, dynamic>>;

      final customers = customerRows
          .map(
            (row) => _LinkOption(
              id: row['name']?.toString() ?? '',
              label:
                  row['customer_name']?.toString() ??
                  row['name']?.toString() ??
                  '',
            ),
          )
          .where((row) => row.id.isNotEmpty)
          .toList();
      final items = itemRows
          .map(
            (row) => _LinkOption(
              id: row['name']?.toString() ?? '',
              label:
                  row['item_name']?.toString() ??
                  row['name']?.toString() ??
                  '',
              rate:
                  double.tryParse(row['standard_rate']?.toString() ?? '') ?? 0,
            ),
          )
          .where((row) => row.id.isNotEmpty)
          .toList();
      final costCenters = costCenterRows
          .map(
            (row) => _CostCenterOption(
              name: row['name']?.toString() ?? '',
              company: row['company']?.toString() ?? '',
            ),
          )
          .where((row) => row.name.isNotEmpty)
          .toList();

      for (final row in _itemRows) {
        row.dispose();
      }
      for (final row in _paymentRows) {
        row.dispose();
      }
      for (final row in _salesTeamRows) {
        row.dispose();
      }

      setState(() {
        _profiles = profiles;
        _companies = companies;
        _warehouses = warehouses;
        _costCenters = costCenters;
        _customers = customers;
        _items = items;
        _modes = modes;
        _canPrint = canPrint;
        _printAfterSave = canPrint;
        _posProfile = profiles.isNotEmpty ? profiles.first : null;
        _company = companies.isNotEmpty ? companies.first : null;
        _customer = null;
        _itemRows = [_ItemRow()];
        _paymentRows = [
          _PaymentRow(modeOfPayment: modes.isNotEmpty ? modes.first : null),
        ];
      });

      if (_posProfile != null) {
        await _applyPosProfile(_posProfile!);
      }
      if (_isEditing) {
        await _loadExisting(widget.editName!.trim());
      } else {
        _syncPrimaryPaymentAmount();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyPosProfile(String profileName) async {
    setState(() => _loadingProfile = true);
    try {
      final state = context.read<PosState>();
      final doc = await state.loadProfileDocument(profileName);
      if (!mounted) return;

      final company = doc['company']?.toString().trim() ?? '';
      final warehouse = doc['warehouse']?.toString().trim() ?? '';
      final sellingPriceList =
          doc['selling_price_list']?.toString().trim() ?? '';
      final costCenter = (doc['cost_center'] ?? doc['custom_cost_center'])
              ?.toString()
              .trim() ??
          '';
      final profileModes = state.paymentModesFromProfile(doc);
      final updateStock = doc['update_stock'] == 1 ||
          doc['update_stock'] == true ||
          doc['update_stock']?.toString() == '1';

      setState(() {
        if (company.isNotEmpty) {
          _company = company;
          if (!_companies.contains(company)) {
            _companies = [company, ..._companies];
          }
        }
        if (warehouse.isNotEmpty) {
          _warehouse = warehouse;
          if (!_warehouses.contains(warehouse)) {
            _warehouses = [warehouse, ..._warehouses];
          }
        }
        if (sellingPriceList.isNotEmpty) {
          _sellingPriceList = sellingPriceList;
        }
        if (costCenter.isNotEmpty) {
          _costCenter = costCenter;
          if (!_costCenters.any((row) => row.name == costCenter)) {
            _costCenters = [
              _CostCenterOption(name: costCenter, company: company),
              ..._costCenters,
            ];
          }
        }
        if (profileModes.isNotEmpty) {
          _modes = {...profileModes, ..._modes}.toList();
          if (_paymentRows.isEmpty) {
            _paymentRows = [
              for (final mode in profileModes)
                _PaymentRow(modeOfPayment: mode),
            ];
          } else {
            for (var i = 0; i < _paymentRows.length; i++) {
              if (_paymentRows[i].modeOfPayment == null ||
                  !_modes.contains(_paymentRows[i].modeOfPayment)) {
                _paymentRows[i].modeOfPayment = profileModes[
                    i < profileModes.length ? i : 0];
              }
            }
          }
        }
        _updateStock = updateStock || _updateStock;
      });
      _syncPrimaryPaymentAmount();
    } catch (_) {
      // Keep existing values if profile detail fails.
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _loadExisting(String name) async {
    final state = context.read<PosState>();
    final doc = await state.loadInvoiceDocument(name);
    if (!mounted) return;

    final profile = doc['pos_profile']?.toString().trim() ?? '';
    final customer = doc['customer']?.toString().trim() ?? '';
    final company = doc['company']?.toString().trim() ?? '';
    final warehouse =
        (doc['set_warehouse'] ?? doc['warehouse'])?.toString().trim() ?? '';
    final costCenter = doc['cost_center']?.toString().trim() ?? '';
    final sellingPriceList =
        doc['selling_price_list']?.toString().trim() ?? '';
    final postingRaw = doc['posting_date']?.toString() ?? '';
    final discount = (doc['discount_amount'] ?? 0).toString();
    final updateStock = doc['update_stock'] == 1 ||
        doc['update_stock'] == true ||
        doc['update_stock']?.toString() == '1';

    for (final row in _itemRows) {
      row.dispose();
    }
    for (final row in _paymentRows) {
      row.dispose();
    }
    for (final row in _salesTeamRows) {
      row.dispose();
    }

    final itemRows = <_ItemRow>[];
    final rawItems = doc['items'];
    if (rawItems is List) {
      for (final row in rawItems.whereType<Map>()) {
        final itemCode = row['item_code']?.toString() ?? '';
        if (itemCode.isNotEmpty && !_items.any((item) => item.id == itemCode)) {
          _items = [
            _LinkOption(
              id: itemCode,
              label: row['item_name']?.toString() ?? itemCode,
              rate: double.tryParse(row['rate']?.toString() ?? '') ?? 0,
            ),
            ..._items,
          ];
        }
        itemRows.add(
          _ItemRow(
            itemCode: itemCode.isEmpty ? null : itemCode,
            qty: (row['qty'] ?? 1).toString(),
            rate: (row['rate'] ?? 0).toString(),
            discount: (row['discount_amount'] ?? 0).toString(),
          ),
        );
      }
    }

    final paymentRows = <_PaymentRow>[];
    final rawPayments = doc['payments'];
    if (rawPayments is List) {
      for (final row in rawPayments.whereType<Map>()) {
        final mode = row['mode_of_payment']?.toString() ?? '';
        if (mode.isNotEmpty && !_modes.contains(mode)) {
          _modes = [mode, ..._modes];
        }
        paymentRows.add(
          _PaymentRow(
            modeOfPayment: mode.isEmpty ? null : mode,
            amount: (row['amount'] ?? 0).toString(),
          ),
        );
      }
    }

    final salesTeamRows = <_SalesTeamRow>[];
    final rawSalesTeam = doc['sales_team'];
    if (rawSalesTeam is List) {
      for (final row in rawSalesTeam.whereType<Map>()) {
        final person = row['sales_person']?.toString().trim() ?? '';
        if (person.isEmpty) continue;
        if (!_salesPersons.any((item) => item.id == person)) {
          _salesPersons = [
            _LinkOption(id: person, label: person),
            ..._salesPersons,
          ];
        }
        salesTeamRows.add(
          _SalesTeamRow(
            salesPerson: person,
            contribution: (row['allocated_percentage'] ?? 100).toString(),
          ),
        );
      }
    }

    setState(() {
      _savedName = name;
      if (profile.isNotEmpty) {
        _posProfile = profile;
        if (!_profiles.contains(profile)) {
          _profiles = [profile, ..._profiles];
        }
      }
      if (customer.isNotEmpty) {
        _customer = customer;
        if (!_customers.any((row) => row.id == customer)) {
          _customers = [
            _LinkOption(id: customer, label: customer),
            ..._customers,
          ];
        }
      }
      if (company.isNotEmpty) {
        _company = company;
        if (!_companies.contains(company)) {
          _companies = [company, ..._companies];
        }
      }
      if (warehouse.isNotEmpty) {
        _warehouse = warehouse;
        if (!_warehouses.contains(warehouse)) {
          _warehouses = [warehouse, ..._warehouses];
        }
      }
      if (costCenter.isNotEmpty) {
        _costCenter = costCenter;
        if (!_costCenters.any((row) => row.name == costCenter)) {
          _costCenters = [
            _CostCenterOption(name: costCenter, company: company),
            ..._costCenters,
          ];
        }
      }
      if (sellingPriceList.isNotEmpty) {
        _sellingPriceList = sellingPriceList;
      }
      final postingDate = DateTime.tryParse(postingRaw);
      if (postingDate != null) _postingDate = postingDate;
      _updateStock = updateStock;
      _discountCtrl.text = discount;
      _itemRows = itemRows.isEmpty ? [_ItemRow()] : itemRows;
      _paymentRows = paymentRows.isEmpty
          ? [_PaymentRow(modeOfPayment: _modes.isNotEmpty ? _modes.first : null)]
          : paymentRows;
      _salesTeamRows = salesTeamRows;
    });
  }

  void _syncPrimaryPaymentAmount() {
    if (_paymentRows.isEmpty) return;
    if (_paymentRows.length == 1) {
      _paymentRows.first.amountCtrl.text = _grandTotal.toStringAsFixed(2);
    }
    setState(() {});
  }

  void _addItemRow() {
    setState(() {
      _itemRows.add(_ItemRow());
    });
  }

  void _removeItemRow(int index) {
    if (_itemRows.length <= 1) return;
    setState(() {
      _itemRows[index].dispose();
      _itemRows.removeAt(index);
    });
    _syncPrimaryPaymentAmount();
  }

  void _addPaymentRow() {
    setState(() {
      final unused = _modes
          .where(
            (mode) => !_paymentRows.any((row) => row.modeOfPayment == mode),
          )
          .toList();
      _paymentRows.add(
        _PaymentRow(
          modeOfPayment: unused.isNotEmpty
              ? unused.first
              : (_modes.isNotEmpty ? _modes.first : null),
          amount: '0',
        ),
      );
    });
  }

  void _removePaymentRow(int index) {
    if (_paymentRows.length <= 1) return;
    setState(() {
      _paymentRows[index].dispose();
      _paymentRows.removeAt(index);
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _postingDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    setState(() => _postingDate = date);
  }

  Future<List<_LinkOption>> _searchItems(String query) async {
    final state = context.read<PosState>();
    final byName = await state.fetchLinkOptions(
      'Item',
      fields: const ['name', 'item_name', 'standard_rate'],
      filters: [
        ['disabled', '=', 0],
        ['is_sales_item', '=', 1],
        ['item_name', 'like', '%$query%'],
      ],
      orderBy: 'item_name asc',
    );
    var mapped = byName
        .map(
          (row) => _LinkOption(
            id: row['name']?.toString() ?? '',
            label:
                row['item_name']?.toString() ??
                row['name']?.toString() ??
                '',
            rate:
                double.tryParse(row['standard_rate']?.toString() ?? '') ?? 0,
          ),
        )
        .where((row) => row.id.isNotEmpty)
        .toList();
    if (mapped.isEmpty) {
      final byId = await state.fetchLinkOptions(
        'Item',
        fields: const ['name', 'item_name', 'standard_rate'],
        filters: [
          ['disabled', '=', 0],
          ['is_sales_item', '=', 1],
          ['name', 'like', '%$query%'],
        ],
        orderBy: 'name asc',
      );
      mapped = byId
          .map(
            (row) => _LinkOption(
              id: row['name']?.toString() ?? '',
              label:
                  row['item_name']?.toString() ??
                  row['name']?.toString() ??
                  '',
              rate:
                  double.tryParse(row['standard_rate']?.toString() ?? '') ?? 0,
            ),
          )
          .where((row) => row.id.isNotEmpty)
          .toList();
    }
    return mapped;
  }

  Future<void> _applyItemPricing(_ItemRow row) async {
    final itemCode = row.itemCode?.trim() ?? '';
    if (itemCode.isEmpty) return;

    final rowKey = identityHashCode(row);
    setState(() => _loadingItemRates.add(rowKey));
    try {
      final state = context.read<PosState>();
      final pricing = await state.resolveItemSellingRate(
        itemCode: itemCode,
        customer: _customer,
        company: _company,
        priceList: _sellingPriceList,
        warehouse: _warehouse,
        postingDate: _postingDate,
        qty: row.qty > 0 ? row.qty : 1,
      );
      if (!mounted || row.itemCode != itemCode) return;
      if (pricing.rate > 0) {
        row.rateCtrl.text = pricing.rate.toStringAsFixed(2);
      } else {
        final match = _items.where((item) => item.id == itemCode);
        if (match.isNotEmpty && match.first.rate > 0) {
          row.rateCtrl.text = match.first.rate.toStringAsFixed(2);
        }
      }
      if (pricing.discountAmount > 0) {
        row.discountCtrl.text = pricing.discountAmount.toStringAsFixed(2);
      }
      _syncPrimaryPaymentAmount();
    } catch (_) {
      final match = _items.where((item) => item.id == itemCode);
      if (match.isNotEmpty && match.first.rate > 0 && mounted) {
        row.rateCtrl.text = match.first.rate.toStringAsFixed(2);
        _syncPrimaryPaymentAmount();
      }
    } finally {
      if (mounted) setState(() => _loadingItemRates.remove(rowKey));
    }
  }

  void _clearSalesTeam() {
    for (final row in _salesTeamRows) {
      row.dispose();
    }
    _salesTeamRows = [];
  }

  Future<void> _onCustomerSelected(String? value) async {
    setState(() {
      _customer = value;
      if (value == null || value.isEmpty) {
        _clearSalesTeam();
      }
    });
    if (value != null && value.isNotEmpty) {
      await _applyCustomerDefaults(value);
    }
  }

  Future<void> _applyCustomerDefaults(String customerId) async {
    setState(() => _loadingCustomerDefaults = true);
    try {
      final state = context.read<PosState>();
      final customer = await state.frappeService.fetchDocument(
        'Customer',
        customerId,
      );
      if (!mounted || _customer != customerId) return;

      final teamRows = <_SalesTeamRow>[];
      final salesPersons = <_LinkOption>[..._salesPersons];
      final rawTeam = customer['sales_team'];
      if (rawTeam is List) {
        for (final row in rawTeam.whereType<Map>()) {
          final person = row['sales_person']?.toString().trim() ?? '';
          if (person.isEmpty) continue;
          if (!salesPersons.any((item) => item.id == person)) {
            salesPersons.insert(0, _LinkOption(id: person, label: person));
          }
          teamRows.add(
            _SalesTeamRow(
              salesPerson: person,
              contribution: (row['allocated_percentage'] ??
                      row['contribution'] ??
                      100)
                  .toString(),
            ),
          );
        }
      }

      String defaultCostCenter = '';
      for (final field in const [
        'cost_center',
        'default_cost_center',
        'custom_cost_center',
        'custom_default_cost_center',
      ]) {
        final value = customer[field]?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          defaultCostCenter = value;
          break;
        }
      }

      String? matchingCostCenter;
      if (defaultCostCenter.isNotEmpty) {
        for (final center in _costCentersForCompany) {
          if (center.name.toLowerCase() == defaultCostCenter.toLowerCase()) {
            matchingCostCenter = center.name;
            break;
          }
        }
        matchingCostCenter ??= defaultCostCenter;
      }

      for (final row in _salesTeamRows) {
        row.dispose();
      }

      setState(() {
        _salesPersons = salesPersons;
        _salesTeamRows = teamRows;
        if (matchingCostCenter != null && matchingCostCenter.isNotEmpty) {
          _costCenter = matchingCostCenter;
          if (!_costCenters.any((row) => row.name == matchingCostCenter)) {
            _costCenters = [
              _CostCenterOption(
                name: matchingCostCenter,
                company: _company ?? '',
              ),
              ..._costCenters,
            ];
          }
        }
      });
    } catch (_) {
      // Customer defaults are optional.
    } finally {
      if (mounted) setState(() => _loadingCustomerDefaults = false);
    }
  }

  Future<List<_LinkOption>> _searchSalesPersons(String query) async {
    final state = context.read<PosState>();
    try {
      final rows = await state.fetchLinkOptions(
        'Sales Person',
        fields: const ['name'],
        filters: [
          ['name', 'like', '%$query%'],
        ],
        orderBy: 'name asc',
      );
      return rows
          .map(
            (row) => _LinkOption(
              id: row['name']?.toString() ?? '',
              label: row['name']?.toString() ?? '',
            ),
          )
          .where((row) => row.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _addSalesTeamRow() {
    setState(() {
      _salesTeamRows.add(
        _SalesTeamRow(
          contribution: _salesTeamRows.isEmpty ? '100' : '0',
        ),
      );
    });
  }

  void _removeSalesTeamRow(int index) {
    setState(() {
      _salesTeamRows[index].dispose();
      _salesTeamRows.removeAt(index);
    });
  }

  Future<void> _printInvoice(String name) async {
    if (!_canPrint) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User tidak punya permission Print untuk POS Invoice.'),
        ),
      );
      return;
    }
    await downloadAndSharePosPdf(context, 'POS Invoice', name);
  }

  Future<void> _save({bool andPrint = false}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_posProfile == null || _customer == null || _company == null) {
      setState(() => _error = 'Lengkapi POS Profile, Customer, dan Company.');
      return;
    }
    if (_updateStock && (_warehouse == null || _warehouse!.trim().isEmpty)) {
      setState(() => _error = 'Source Warehouse wajib saat Update Stock aktif.');
      return;
    }

    final items = <Map<String, dynamic>>[];
    for (final row in _itemRows) {
      final itemCode = row.itemCode?.trim() ?? '';
      if (itemCode.isEmpty) {
        setState(() => _error = 'Setiap baris item wajib punya Item Code.');
        return;
      }
      if (row.qty <= 0) {
        setState(() => _error = 'Qty item harus lebih dari 0.');
        return;
      }
      if (row.rate < 0) {
        setState(() => _error = 'Rate item tidak valid.');
        return;
      }
      items.add({
        'item_code': itemCode,
        'qty': row.qty,
        'rate': row.rate,
        'discount_amount': row.discountAmount,
        'amount': row.amount,
        if (_updateStock && _warehouse != null) 'warehouse': _warehouse,
      });
    }
    if (items.isEmpty) {
      setState(() => _error = 'Minimal satu item.');
      return;
    }

    final payments = <Map<String, dynamic>>[];
    for (final row in _paymentRows) {
      final mode = row.modeOfPayment?.trim() ?? '';
      if (mode.isEmpty) {
        setState(() => _error = 'Setiap pembayaran wajib punya Mode of Payment.');
        return;
      }
      if (row.amount < 0) {
        setState(() => _error = 'Amount pembayaran tidak valid.');
        return;
      }
      payments.add({
        'mode_of_payment': mode,
        'amount': row.amount,
      });
    }
    if (payments.isEmpty) {
      setState(() => _error = 'Minimal satu pembayaran.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = context.read<PosState>();
      final postingDate = DateFormat('yyyy-MM-dd').format(_postingDate);
      final payload = {
        'is_pos': 1,
        'pos_profile': _posProfile,
        'customer': _customer,
        'company': _company,
        'posting_date': postingDate,
        'update_stock': _updateStock ? 1 : 0,
        if (_updateStock && _warehouse != null) 'set_warehouse': _warehouse,
        if (_costCenter != null && _costCenter!.trim().isNotEmpty)
          'cost_center': _costCenter!.trim(),
        if (_sellingPriceList != null && _sellingPriceList!.isNotEmpty)
          'selling_price_list': _sellingPriceList,
        'discount_amount': _discount,
        'items': items,
        'payments': payments,
        if (_salesTeamRows.any(
          (row) => (row.salesPerson?.trim().isNotEmpty ?? false),
        ))
          'sales_team': [
            for (final row in _salesTeamRows)
              if ((row.salesPerson?.trim().isNotEmpty ?? false))
                {
                  'sales_person': row.salesPerson!.trim(),
                  'allocated_percentage': row.contribution,
                },
          ],
      };

      String savedName;
      if (_isEditing || (_savedName?.isNotEmpty == true)) {
        savedName = (_documentName ?? '').trim();
        await state.updateInvoice(savedName, payload);
      } else {
        final created = await state.createInvoice(payload);
        savedName = created.id;
      }

      if (!mounted) return;
      setState(() => _savedName = savedName);

      final shouldPrint = andPrint || _printAfterSave;
      if (shouldPrint && _canPrint) {
        await _printInvoice(savedName);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
          _isEditing ? 'Edit POS Invoice' : 'Buat POS Invoice',
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_canPrint && _documentName != null)
            IconButton(
              tooltip: 'Print / Share PDF',
              onPressed: _saving ? null : () => _printInvoice(_documentName!),
              icon: const Icon(Icons.print_rounded, color: AppColors.primary),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: TmsxResponsive.pagePadding(
                  context,
                  top: 16,
                  bottom: 28,
                ),
                child: TmsxResponsiveBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFC2410C),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  PosSectionCard(
                    title: 'Informasi POS Invoice',
                    children: [
                      DropdownButtonFormField<String>(
                        key: ValueKey('profile-${_posProfile ?? 'none'}'),
                        initialValue: _profiles.contains(_posProfile)
                            ? _posProfile
                            : null,
                        isExpanded: true,
                        decoration: posFieldDecoration('POS Profile *'),
                        items: [
                          for (final profile in _profiles)
                            DropdownMenuItem(
                              value: profile,
                              child: Text(
                                profile,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _loadingProfile
                            ? null
                            : (value) async {
                                setState(() => _posProfile = value);
                                if (value != null) {
                                  await _applyPosProfile(value);
                                }
                              },
                        validator: (value) =>
                            value == null ? 'POS Profile wajib' : null,
                      ),
                      const SizedBox(height: 12),
                      ErpItemAutocompleteField(
                        label: 'Customer *',
                        selectedId: _customer,
                        options: [
                          for (final customer in _customers)
                            ErpItemOption(
                              id: customer.id,
                              label: customer.label == customer.id
                                  ? customer.id
                                  : '${customer.label} (${customer.id})',
                            ),
                        ],
                        decoration: posFieldDecoration(
                          'Customer *',
                          hintText: 'Pilih atau search customer',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          suffixIcon: _customer != null
                              ? IconButton(
                                  tooltip: 'Bersihkan Customer',
                                  onPressed: () => _onCustomerSelected(null),
                                  icon: const Icon(Icons.close_rounded),
                                )
                              : const Icon(Icons.search_rounded),
                        ),
                        onSelected: _onCustomerSelected,
                        validator: (value) =>
                            value == null || value.isEmpty
                            ? 'Customer wajib'
                            : null,
                        onSearch: (query) async {
                          final state = context.read<PosState>();
                          final byName = await state.fetchLinkOptions(
                            'Customer',
                            fields: const ['name', 'customer_name'],
                            filters: [
                              ['disabled', '=', 0],
                              ['customer_name', 'like', '%$query%'],
                            ],
                            orderBy: 'customer_name asc',
                          );
                          var mapped = byName
                              .map(
                                (row) => ErpItemOption(
                                  id: row['name']?.toString() ?? '',
                                  label:
                                      '${row['customer_name'] ?? row['name']} (${row['name']})',
                                ),
                              )
                              .where((row) => row.id.isNotEmpty)
                              .toList();
                          if (mapped.isEmpty) {
                            final byId = await state.fetchLinkOptions(
                              'Customer',
                              fields: const ['name', 'customer_name'],
                              filters: [
                                ['disabled', '=', 0],
                                ['name', 'like', '%$query%'],
                              ],
                              orderBy: 'name asc',
                            );
                            mapped = byId
                                .map(
                                  (row) => ErpItemOption(
                                    id: row['name']?.toString() ?? '',
                                    label:
                                        '${row['customer_name'] ?? row['name']} (${row['name']})',
                                  ),
                                )
                                .where((row) => row.id.isNotEmpty)
                                .toList();
                          }
                          return mapped;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey('company-${_company ?? 'none'}'),
                        initialValue: _companies.contains(_company)
                            ? _company
                            : null,
                        isExpanded: true,
                        decoration: posFieldDecoration('Company *'),
                        items: [
                          for (final company in _companies)
                            DropdownMenuItem(
                              value: company,
                              child: Text(
                                company,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _company = value;
                          final centers = _costCentersForCompany;
                          if (_costCenter != null &&
                              !centers.any((row) => row.name == _costCenter)) {
                            _costCenter = null;
                          }
                        }),
                        validator: (value) =>
                            value == null ? 'Company wajib' : null,
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(10),
                        child: InputDecorator(
                          decoration: posFieldDecoration(
                            'Posting Date *',
                            suffixIcon: const Icon(
                              Icons.event_rounded,
                              color: AppColors.slate,
                            ),
                          ),
                          child: Text(
                            DateFormat('dd-MM-yyyy').format(_postingDate),
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ErpItemAutocompleteField(
                        key: ValueKey('cost-center-${_costCenter ?? 'none'}'),
                        label: 'Cost Center',
                        selectedId: _costCentersForCompany.any(
                              (row) => row.name == _costCenter,
                            )
                            ? _costCenter
                            : null,
                        options: [
                          for (final center in _costCentersForCompany)
                            ErpItemOption(id: center.name, label: center.name),
                        ],
                        decoration: posFieldDecoration(
                          'Cost Center',
                          hintText: 'Pilih cost center',
                          prefixIcon: const Icon(Icons.account_tree_outlined),
                        ),
                        onSelected: (value) =>
                            setState(() => _costCenter = value),
                      ),
                      if (_sellingPriceList != null &&
                          _sellingPriceList!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Price List: $_sellingPriceList',
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _updateStock,
                        activeColor: AppColors.primary,
                        title: const Text(
                          'Update Stock',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onChanged: (value) =>
                            setState(() => _updateStock = value ?? true),
                      ),
                      if (_updateStock) ...[
                        const SizedBox(height: 4),
                        ErpItemAutocompleteField(
                          key: ValueKey('warehouse-${_warehouse ?? 'none'}'),
                          label: 'Source Warehouse *',
                          selectedId: _warehouses.contains(_warehouse)
                              ? _warehouse
                              : null,
                          options: [
                            for (final warehouse in _warehouses)
                              ErpItemOption(id: warehouse, label: warehouse),
                          ],
                          decoration: posFieldDecoration(
                            'Source Warehouse *',
                            hintText: 'Pilih warehouse',
                            prefixIcon: const Icon(Icons.warehouse_outlined),
                          ),
                          onSelected: (value) =>
                              setState(() => _warehouse = value),
                          validator: (value) {
                            if (!_updateStock) return null;
                            return value == null || value.isEmpty
                                ? 'Source Warehouse wajib'
                                : null;
                          },
                        ),
                      ],
                      if (_loadingProfile || _loadingCustomerDefaults)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(
                            color: AppColors.primary,
                            minHeight: 2,
                          ),
                        ),
                    ],
                  ),
                  PosSectionCard(
                    title: 'Sales Team',
                    children: [
                      if (_salesTeamRows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Sales Team akan terisi otomatis dari Customer.',
                            style: TextStyle(
                              color: AppColors.slate,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        for (var i = 0; i < _salesTeamRows.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          _SalesTeamCard(
                            index: i,
                            row: _salesTeamRows[i],
                            salesPersons: _salesPersons,
                            canRemove: true,
                            onRemove: () => _removeSalesTeamRow(i),
                            onChanged: () => setState(() {}),
                            onSalesPersonsUpdated: (options) {
                              setState(() {
                                for (final option in options) {
                                  if (!_salesPersons.any(
                                    (item) => item.id == option.id,
                                  )) {
                                    _salesPersons = [option, ..._salesPersons];
                                  }
                                }
                              });
                            },
                            onSearchSalesPersons: _searchSalesPersons,
                          ),
                        ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addSalesTeamRow,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text(
                            'Add Row',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  PosSectionCard(
                    title: 'Items',
                    children: [
                      for (var i = 0; i < _itemRows.length; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        _InvoiceItemCard(
                          index: i,
                          row: _itemRows[i],
                          items: _items,
                          canRemove: _itemRows.length > 1,
                          isLoadingRate: _loadingItemRates.contains(
                            identityHashCode(_itemRows[i]),
                          ),
                          onRemove: () => _removeItemRow(i),
                          onChanged: _syncPrimaryPaymentAmount,
                          onItemsUpdated: (options) {
                            setState(() {
                              for (final option in options) {
                                if (!_items.any(
                                  (item) => item.id == option.id,
                                )) {
                                  _items = [option, ..._items];
                                }
                              }
                            });
                          },
                          onSearchItems: _searchItems,
                          onItemSelected: _applyItemPricing,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addItemRow,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text(
                            'Add Row',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  PosSectionCard(
                    title: 'Diskon & Total',
                    children: [
                      TextFormField(
                        controller: _discountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: posFieldDecoration(
                          'Additional Discount Amount',
                          prefixIcon: const Icon(Icons.discount_outlined),
                        ),
                        onChanged: (_) => _syncPrimaryPaymentAmount(),
                      ),
                      const SizedBox(height: 12),
                      _TotalRow(
                        label: 'Total Qty',
                        value: _itemRows
                            .fold<double>(0, (sum, row) => sum + row.qty)
                            .toStringAsFixed(0),
                      ),
                      _TotalRow(
                        label: 'Total',
                        value: 'Rp ${formatErpCurrency(_itemsTotal)}',
                      ),
                      _TotalRow(
                        label: 'Discount',
                        value: 'Rp ${formatErpCurrency(_discount)}',
                      ),
                      _TotalRow(
                        label: 'Grand Total',
                        value: 'Rp ${formatErpCurrency(_grandTotal)}',
                        emphasize: true,
                      ),
                    ],
                  ),
                  PosSectionCard(
                    title: 'Payments',
                    children: [
                      for (var i = 0; i < _paymentRows.length; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        _InvoicePaymentCard(
                          index: i,
                          row: _paymentRows[i],
                          modes: _modes,
                          canRemove: _paymentRows.length > 1,
                          onRemove: () => _removePaymentRow(i),
                          onChanged: () => setState(() {}),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addPaymentRow,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text(
                            'Add Payment',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _TotalRow(
                        label: 'Paid Amount',
                        value: 'Rp ${formatErpCurrency(_paidAmount)}',
                      ),
                      _TotalRow(
                        label: 'Change Amount',
                        value: 'Rp ${formatErpCurrency(_changeAmount)}',
                        emphasize: true,
                      ),
                    ],
                  ),
                  if (_canPrint)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _printAfterSave,
                      activeColor: AppColors.primary,
                      title: const Text(
                        'Print / Share PDF setelah simpan',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onChanged: (value) =>
                          setState(() => _printAfterSave = value ?? false),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _save(),
                    icon: const Icon(Icons.save_rounded),
                    label: Text(
                      _saving
                          ? 'Menyimpan...'
                          : (_isEditing || _savedName != null
                                ? 'Update Invoice'
                                : 'Simpan Invoice'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  if (_canPrint) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _save(andPrint: true),
                      icon: const Icon(Icons.print_rounded),
                      label: Text(
                        _saving ? 'Menyimpan...' : 'Simpan & Print',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;

  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: emphasize ? AppColors.navy : AppColors.slate,
                fontSize: emphasize ? 14 : 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: AppColors.navy,
              fontSize: emphasize ? 15 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceItemCard extends StatelessWidget {
  final int index;
  final _ItemRow row;
  final List<_LinkOption> items;
  final bool canRemove;
  final bool isLoadingRate;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final ValueChanged<List<_LinkOption>> onItemsUpdated;
  final Future<List<_LinkOption>> Function(String query) onSearchItems;
  final Future<void> Function(_ItemRow row) onItemSelected;

  const _InvoiceItemCard({
    required this.index,
    required this.row,
    required this.items,
    required this.canRemove,
    required this.isLoadingRate,
    required this.onRemove,
    required this.onChanged,
    required this.onItemsUpdated,
    required this.onSearchItems,
    required this.onItemSelected,
  });

  InputDecoration _field(String label, {Widget? prefixIcon, Widget? suffixIcon}) {
    return posFieldDecoration(
      label,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
    ).copyWith(fillColor: AppColors.white);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Item ${index + 1}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Hapus item',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 22,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ErpItemAutocompleteField(
            label: 'Nama Item / Kode',
            selectedId: row.itemCode,
            options: [
              for (final item in items)
                ErpItemOption(
                  id: item.id,
                  label: item.label == item.id
                      ? item.id
                      : '${item.label} (${item.id})',
                ),
            ],
            decoration: _field(
              'Nama Item / Kode',
              prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20),
              suffixIcon: const Icon(Icons.search_rounded, size: 20),
            ).copyWith(hintText: 'Pilih atau search item'),
            onSelected: (value) async {
              row.itemCode = value;
              row.rateCtrl.text = '0';
              row.discountCtrl.text = '0';
              onChanged();
              await onItemSelected(row);
            },
            validator: (value) =>
                value == null || value.isEmpty ? 'Item wajib' : null,
            onSearch: (query) async {
              final found = await onSearchItems(query);
              if (found.isNotEmpty) onItemsUpdated(found);
              return [
                for (final item in found)
                  ErpItemOption(
                    id: item.id,
                    label: item.label == item.id
                        ? item.id
                        : '${item.label} (${item.id})',
                  ),
              ];
            },
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: row.qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _field('Qty *'),
                  onChanged: (_) => onChanged(),
                  validator: (value) {
                    final qty = double.tryParse(value?.trim() ?? '');
                    if (qty == null || qty <= 0) return 'Qty > 0';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: row.rateCtrl,
                  readOnly: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _field(
                    'Harga/Unit',
                    prefixIcon: isLoadingRate
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(Icons.lock_outline_rounded, size: 18),
                  ),
                  validator: (value) {
                    final rate = double.tryParse(value?.trim() ?? '');
                    if (rate == null || rate < 0) return 'Harga >= 0';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: row.discountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _field(
              'Discount Amount',
              prefixIcon: const Icon(Icons.discount_outlined, size: 20),
            ),
            onChanged: (_) => onChanged(),
            validator: (value) {
              final discount = double.tryParse(value?.trim() ?? '');
              if (discount == null || discount < 0) {
                return 'Discount invalid';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Text(
                  'Amount',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  'Rp ${formatErpCurrency(row.amount)}',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
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

class _InvoicePaymentCard extends StatelessWidget {
  final int index;
  final _PaymentRow row;
  final List<String> modes;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _InvoicePaymentCard({
    required this.index,
    required this.row,
    required this.modes,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  InputDecoration _field(String label) {
    return posFieldDecoration(label).copyWith(fillColor: AppColors.white);
  }

  @override
  Widget build(BuildContext context) {
    final selected = modes.contains(row.modeOfPayment)
        ? row.modeOfPayment
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Pay ${index + 1}',
                  style: const TextStyle(
                    color: Color(0xFFC2410C),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Hapus pembayaran',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 22,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('pay-$index-${selected ?? 'none'}'),
            initialValue: selected,
            isExpanded: true,
            decoration: _field('Mode of Payment *'),
            items: [
              for (final mode in modes)
                DropdownMenuItem(
                  value: mode,
                  child: Text(mode, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              row.modeOfPayment = value;
              onChanged();
            },
            validator: (value) =>
                value == null ? 'Mode of Payment wajib' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: row.amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _field('Amount *'),
            onChanged: (_) => onChanged(),
            validator: (value) {
              final amount = double.tryParse(value?.trim() ?? '');
              if (amount == null || amount < 0) return 'Amount invalid';
              return null;
            },
          ),
        ],
      ),
    );
  }
}

class _SalesTeamCard extends StatelessWidget {
  final int index;
  final _SalesTeamRow row;
  final List<_LinkOption> salesPersons;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final ValueChanged<List<_LinkOption>> onSalesPersonsUpdated;
  final Future<List<_LinkOption>> Function(String query) onSearchSalesPersons;

  const _SalesTeamCard({
    required this.index,
    required this.row,
    required this.salesPersons,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
    required this.onSalesPersonsUpdated,
    required this.onSearchSalesPersons,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'No. ${index + 1}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Hapus sales person',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 22,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ErpItemAutocompleteField(
            label: 'Sales Person *',
            selectedId: row.salesPerson,
            options: [
              for (final person in salesPersons)
                ErpItemOption(
                  id: person.id,
                  label: person.label == person.id
                      ? person.id
                      : '${person.label} (${person.id})',
                ),
            ],
            decoration: posFieldDecoration(
              'Sales Person *',
              hintText: 'Pilih sales person',
              prefixIcon: const Icon(Icons.badge_outlined),
            ).copyWith(fillColor: AppColors.white),
            onSelected: (value) {
              row.salesPerson = value;
              onChanged();
            },
            validator: (value) =>
                value == null || value.isEmpty ? 'Sales Person wajib' : null,
            onSearch: (query) async {
              final found = await onSearchSalesPersons(query);
              if (found.isNotEmpty) onSalesPersonsUpdated(found);
              return [
                for (final person in found)
                  ErpItemOption(
                    id: person.id,
                    label: person.label == person.id
                        ? person.id
                        : '${person.label} (${person.id})',
                  ),
              ];
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: row.contributionCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: posFieldDecoration(
              'Contribution (%)',
            ).copyWith(fillColor: AppColors.white),
            onChanged: (_) => onChanged(),
            validator: (value) {
              final pct = double.tryParse(value?.trim() ?? '');
              if (pct == null || pct < 0 || pct > 100) {
                return '0 - 100';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }
}
