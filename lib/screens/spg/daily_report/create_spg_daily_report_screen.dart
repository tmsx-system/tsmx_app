import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/spg_workspace.dart';
import '../../../state/spg/spg_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../utils/erp_error_message.dart';
import '../../../widgets/responsive/responsive_layout.dart';

class CreateSpgDailyReportScreen extends StatefulWidget {
  final String? existingName;

  const CreateSpgDailyReportScreen({super.key, this.existingName});

  @override
  State<CreateSpgDailyReportScreen> createState() =>
      _CreateSpgDailyReportScreenState();
}

class _CreateSpgDailyReportScreenState
    extends State<CreateSpgDailyReportScreen> {
  final _notes = TextEditingController();
  final List<_SpgSellingRow> _rows = [_SpgSellingRow()];
  List<SpgCustomerOption> _customers = const [];
  List<Map<String, dynamic>> _items = const [];
  final _itemCache = <String, Map<String, dynamic>>{};
  List<Map<String, dynamic>> _employees = const [];
  SpgCustomerOption? _customer;
  Map<String, dynamic>? _employee;
  DateTime _reportDate = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<SpgState>();
      final selectsEmployee = !state.mobileAccess.isSpg;
      final results = await Future.wait([
        selectsEmployee
            ? Future.value(const <SpgCustomerOption>[])
            : _customersFor(state, ''),
        state.fetchSpgSellingItems(''),
        if (selectsEmployee)
          state.fetchSpgEmployeeChoices(onDate: _reportDate),
      ]);
      if (!mounted) return;
      setState(() {
        _customers = results[0] as List<SpgCustomerOption>;
        _items = results[1] as List<Map<String, dynamic>>;
        _employees = selectsEmployee
            ? results[2] as List<Map<String, dynamic>>
            : const <Map<String, dynamic>>[];
      });
      await _applyExisting(state);
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _applyExisting(SpgState state) async {
    final name = widget.existingName?.trim() ?? '';
    if (name.isEmpty) return;
    final doc = await state.fetchSpgDailyReportDetail(name);
    final docstatus = int.tryParse(doc['docstatus']?.toString() ?? '') ?? 0;
    if (docstatus != 0) {
      throw Exception('Report yang sudah Submit tidak bisa diedit.');
    }
    final customerId = doc['customer']?.toString().trim() ?? '';
    final customerName = doc['customer_name']?.toString().trim() ?? '';
    final employeeId = doc['employee']?.toString().trim() ?? '';
    final employeeName = doc['employee_name']?.toString().trim() ?? '';
    final parsed = DateTime.tryParse(doc['report_date']?.toString() ?? '');
    if (customerId.isNotEmpty &&
        !_customers.any((customer) => customer.id == customerId)) {
      _customers = [
        SpgCustomerOption(
          id: customerId,
          name: customerName.isEmpty ? customerId : customerName,
        ),
        ..._customers,
      ];
    }
    if (employeeId.isNotEmpty &&
        !_employees.any((row) => row['name']?.toString() == employeeId)) {
      _employees = [
        {
          'name': employeeId,
          'employee_name': employeeName.isEmpty ? employeeId : employeeName,
        },
        ..._employees,
      ];
    }
    for (final row in _rows) {
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll(_rowsFromDoc(doc['selling_items']));
    if (_rows.isEmpty) _rows.add(_SpgSellingRow());
    _customer = customerId.isEmpty
        ? null
        : SpgCustomerOption(
            id: customerId,
            name: customerName.isEmpty ? customerId : customerName,
          );
    _employee = employeeId.isEmpty
        ? null
        : {
            'name': employeeId,
            'employee_name': employeeName.isEmpty ? employeeId : employeeName,
          };
    if (parsed != null) {
      _reportDate = DateTime(parsed.year, parsed.month, parsed.day);
    }
    _notes.text = doc['notes']?.toString() ?? '';
    if (mounted) setState(() {});
  }

  List<_SpgSellingRow> _rowsFromDoc(dynamic value) {
    if (value is! List) return const [];
    return [
      for (final raw in value.whereType<Map>())
        _SpgSellingRow(
          item: raw['item']?.toString() ?? '',
          itemLabel: raw['item']?.toString() ?? '',
          uom: raw['uom']?.toString() ?? '',
          opening: raw['opening_stock']?.toString() ?? '',
          closing: raw['closing_stock']?.toString() ?? '',
          sellOut: raw['sell_out']?.toString() ?? '',
        ),
    ];
  }

  Future<void> _loadScheduledCustomersForEmployee() async {
    final state = context.read<SpgState>();
    final employee = _employee?['name']?.toString().trim() ?? '';
    if (employee.isEmpty) {
      setState(() {
        _customers = const [];
        _customer = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _customer = null;
    });
    try {
      final customers = await _customersFor(state, '', employee: employee);
      if (!mounted) return;
      setState(() => _customers = customers);
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<SpgCustomerOption>> _customersFor(
    SpgState state,
    String query, {
    String? employee,
  }) async {
    final access = state.mobileAccess;
    final assigned = await state.fetchScheduledSpgCustomers(
      query: query,
      employee: employee,
      onDate: _reportDate,
    );
    if (access.isSpg || access.isSalesUser || assigned.isNotEmpty) {
      return assigned;
    }
    return state.fetchSpgCustomers(query: query);
  }

  Future<void> _pickReportDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _reportDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _reportDate = DateTime(picked.year, picked.month, picked.day);
    });
    await _refreshCustomersForDate();
  }

  Future<void> _refreshCustomersForDate() async {
    final state = context.read<SpgState>();
    if (!state.mobileAccess.isSpg && _employee == null) return;
    final customers = await _customersFor(
      state,
      '',
      employee: _employee?['name']?.toString(),
    );
    if (!mounted) return;
    setState(() {
      _customers = customers;
      if (_customer != null &&
          !customers.any((option) => option.id == _customer!.id)) {
        _customer = null;
      }
    });
  }

  String _reportDateLabel() {
    final day = _reportDate.day.toString().padLeft(2, '0');
    final month = _reportDate.month.toString().padLeft(2, '0');
    return '$day-$month-${_reportDate.year}';
  }

  Future<void> _save() async {
    final selectsEmployee = !context.read<SpgState>().mobileAccess.isSpg;
    if (selectsEmployee && _employee == null) {
      setState(() => _error = 'Employee wajib dipilih.');
      return;
    }
    if (_customer == null) {
      setState(() => _error = 'Customer wajib dipilih.');
      return;
    }
    final missingUom = _rows.any(
      (row) => row.item.trim().isNotEmpty && row.uom.trim().isEmpty,
    );
    if (missingUom) {
      setState(
        () => _error = 'Pilih item dari hasil pencarian agar UOM terisi.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final state = context.read<SpgState>();
      final draft = (
        customer: _customer!.id,
        sellingItems: _rows.map((row) => row.toPayload()).toList(),
        employee: _employee?['name']?.toString(),
        reportDate: _reportDate,
        notes: _notes.text,
      );
      final existing = widget.existingName?.trim() ?? '';
      if (existing.isNotEmpty) {
        await state.updateSpgDailyReport(
          name: existing,
          customer: draft.customer,
          sellingItems: draft.sellingItems,
          employee: draft.employee,
          reportDate: draft.reportDate,
          notes: draft.notes,
        );
      } else {
        await state.createSpgDailyReport(
          customer: draft.customer,
          sellingItems: draft.sellingItems,
          employee: draft.employee,
          reportDate: draft.reportDate,
          notes: draft.notes,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          (widget.existingName ?? '').trim().isEmpty
              ? 'Buat Report Selling'
              : 'Edit Report Selling',
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.navy,
      ),
      body: TmsxResponsiveBody(
        child: ListView(
          padding: TmsxResponsive.pagePadding(context, top: 12, bottom: 100),
          children: [
            _headerCard(),
            const SizedBox(height: 12),
            _formCard(),
            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErpErrorBox(message: _error!),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.fromLTRB(
          TmsxResponsive.horizontalPadding(context),
          8,
          TmsxResponsive.horizontalPadding(context),
          16,
        ),
        child: TmsxResponsiveBody(
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _saving
                    ? 'Menyimpan...'
                    : ((widget.existingName ?? '').trim().isEmpty
                          ? 'Kirim Report Selling'
                          : 'Simpan Perubahan'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0891B2).withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.bar_chart_outlined,
              color: Color(0xFF0891B2),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPG Daily Report',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Isi stock awal, stock akhir, dan sell out per item.',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!context.watch<SpgState>().mobileAccess.isSpg) ...[
            _employeeSearchField(),
            const SizedBox(height: 12),
          ],
          _reportDateField(),
          const SizedBox(height: 12),
          _customerSearchField(),
          const SizedBox(height: 12),
          ..._rows.asMap().entries.map(
            (entry) => _sellingRowCard(entry.key, entry.value),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _saving
                ? null
                : () => setState(() => _rows.add(_SpgSellingRow())),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Tambah Item'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 5,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Notes',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sellingRowCard(int index, _SpgSellingRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFE0F2FE),
                foregroundColor: const Color(0xFF0891B2),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.itemLabel.isEmpty ? 'Item Selling' : row.itemLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.item.isEmpty
                          ? 'Pilih item dari master Item'
                          : [row.item, row.uom]
                                .where((value) => value.trim().isNotEmpty)
                                .join(' · '),
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
              if (_rows.length > 1)
                IconButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          row.dispose();
                          _rows.removeAt(index);
                        }),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: 12),
          IgnorePointer(
            ignoring: _saving,
            child: ErpItemAutocompleteField(
              label: 'Name',
              selectedId: row.item.isEmpty ? null : row.item,
              options: _itemOptionsFor(row),
              onSearch: _searchItems,
              onSelected: (id) => _selectItem(row, id),
              decoration: _pickerDecoration(
                'Name',
                hint: 'Pilih atau search item',
                icon: Icons.inventory_2_outlined,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.softGreen.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.straighten_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text(
                  'UOM',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  row.uom.trim().isEmpty ? 'Pilih item dulu' : row.uom,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stockNumberField(
                  label: 'Stock Awal',
                  controller: row.stockAwal,
                  icon: Icons.login_rounded,
                  uom: row.uom,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _stockNumberField(
                  label: 'Stock Akhir',
                  controller: row.stockAkhir,
                  icon: Icons.logout_rounded,
                  uom: row.uom,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _stockNumberField(
            label: 'Sell Out',
            controller: row.sellOut,
            icon: Icons.point_of_sale_rounded,
            uom: row.uom,
          ),
        ],
      ),
    );
  }

  String _itemLabel(Map<String, dynamic> option) {
    final itemName = option['item_name']?.toString().trim() ?? '';
    final itemCode =
        (option['item_code']?.toString().trim().isNotEmpty == true
            ? option['item_code']?.toString().trim()
            : option['name']?.toString().trim()) ??
        '';
    if (itemName.isEmpty) return itemCode;
    if (itemCode.isEmpty || itemCode == itemName) return itemName;
    return '$itemName - $itemCode';
  }

  Widget _customerSearchField() {
    final needsEmployee = !context.read<SpgState>().mobileAccess.isSpg &&
        _employee == null;
    return IgnorePointer(
      ignoring: _saving,
      child: ErpItemAutocompleteField(
        label: 'Customer',
        selectedId: _customer?.id,
        options: [for (final customer in _customers) _customerOption(customer)],
        onSearch: needsEmployee ? null : _searchCustomers,
        onSelected: (id) {
          SpgCustomerOption? selected;
          if (id != null && id.isNotEmpty) {
            for (final customer in _customers) {
              if (customer.id == id) {
                selected = customer;
                break;
              }
            }
            selected ??= SpgCustomerOption(id: id, name: id);
          }
          setState(() => _customer = selected);
        },
        decoration: _pickerDecoration(
          'Customer',
          hint: needsEmployee
              ? 'Pilih employee dulu'
              : 'Pilih atau search customer',
          icon: Icons.storefront_outlined,
        ),
      ),
    );
  }

  Widget _reportDateField() {
    return InkWell(
      onTap: _saving ? null : _pickReportDate,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: _pickerDecoration(
          'Report Date',
          hint: 'Tanggal report',
          icon: Icons.calendar_today_rounded,
        ),
        child: Text(
          _reportDateLabel(),
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _employeeSearchField() {
    return IgnorePointer(
      ignoring: _saving,
      child: ErpItemAutocompleteField(
        label: 'Employee',
        selectedId: _employee?['name']?.toString(),
        options: [for (final employee in _employees) _employeeOption(employee)],
        onSearch: _searchEmployees,
        onSelected: (id) {
          Map<String, dynamic>? selected;
          if (id != null && id.isNotEmpty) {
            for (final employee in _employees) {
              if (employee['name']?.toString() == id) {
                selected = employee;
                break;
              }
            }
            selected ??= {'name': id, 'employee_name': id};
          }
          setState(() {
            _employee = selected;
            _customer = null;
            _customers = const [];
          });
          if (selected != null) _loadScheduledCustomersForEmployee();
        },
        decoration: _pickerDecoration(
          'Employee',
          hint: 'Pilih atau search employee',
          icon: Icons.badge_outlined,
        ),
      ),
    );
  }

  ErpItemOption _employeeOption(Map<String, dynamic> employee) {
    return ErpItemOption(
      id: employee['name']?.toString() ?? '',
      label: _employeeLabel(employee),
    );
  }

  Future<List<ErpItemOption>> _searchEmployees(String query) async {
    final rows = await context.read<SpgState>().fetchSpgEmployeeChoices(
      query: query,
      onDate: _reportDate,
    );
    final merged = <String, Map<String, dynamic>>{
      for (final employee in _employees)
        if ((employee['name']?.toString() ?? '').isNotEmpty)
          employee['name'].toString(): employee,
      for (final employee in rows)
        if ((employee['name']?.toString() ?? '').isNotEmpty)
          employee['name'].toString(): employee,
    };
    _employees = merged.values.toList();
    return [for (final employee in rows) _employeeOption(employee)];
  }

  String _customerLabel(SpgCustomerOption customer) {
    if (customer.id.trim().isEmpty) return customer.name;
    return '${customer.name} - ${customer.id}';
  }

  ErpItemOption _customerOption(SpgCustomerOption customer) {
    return ErpItemOption(id: customer.id, label: _customerLabel(customer));
  }

  Future<List<ErpItemOption>> _searchCustomers(String query) async {
    final state = context.read<SpgState>();
    List<SpgCustomerOption> scheduled = const [];
    try {
      scheduled = await state.fetchScheduledSpgCustomers(
        query: query,
        employee: _employee?['name']?.toString(),
        onDate: _reportDate,
      );
    } catch (_) {}
    final access = state.mobileAccess;
    final resolved = scheduled.isNotEmpty || access.isSpg || access.isSalesUser
        ? scheduled
        : await state.fetchSpgCustomers(query: query);
    final merged = <String, SpgCustomerOption>{
      for (final customer in _customers) customer.id: customer,
      for (final customer in resolved) customer.id: customer,
    };
    _customers = merged.values.toList();
    return [for (final customer in resolved) _customerOption(customer)];
  }

  List<ErpItemOption> _itemOptionsFor(_SpgSellingRow row) {
    final options = <ErpItemOption>[
      for (final item in _items) _rememberItem(item),
    ];
    if (row.item.isNotEmpty && !options.any((option) => option.id == row.item)) {
      options.insert(
        0,
        ErpItemOption(
          id: row.item,
          label: row.itemLabel.isEmpty ? row.item : row.itemLabel,
        ),
      );
    }
    return options;
  }

  Future<List<ErpItemOption>> _searchItems(String query) async {
    final rows = await context.read<SpgState>().fetchSpgSellingItems(query);
    if (query.trim().isEmpty) _items = rows;
    return [for (final item in rows) _rememberItem(item)];
  }

  ErpItemOption _rememberItem(Map<String, dynamic> item) {
    final code = item['item_code']?.toString().trim() ?? '';
    final name = item['name']?.toString().trim() ?? '';
    final id = code.isNotEmpty ? code : name;
    if (id.isNotEmpty) _itemCache[id] = item;
    return ErpItemOption(id: id, label: _itemLabel(item));
  }

  void _selectItem(_SpgSellingRow row, String? id) {
    final item = id == null ? null : _itemCache[id];
    setState(() {
      row.item = id?.trim() ?? '';
      row.itemLabel = item == null
          ? (id?.trim() ?? '')
          : _itemLabel(item);
      row.uom = item?['stock_uom']?.toString() ?? '';
    });
  }

  InputDecoration _pickerDecoration(
    String label, {
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
    );
  }

  String _employeeLabel(Map<String, dynamic> employee) {
    final name = employee['name']?.toString() ?? '';
    final employeeName = employee['employee_name']?.toString() ?? '';
    if (employeeName.trim().isEmpty) return name;
    if (name.trim().isEmpty) return employeeName;
    return '$employeeName - $name';
  }

  Widget _stockNumberField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String uom,
  }) {
    final suffix = uom.trim();
    return TextField(
      controller: controller,
      enabled: !_saving,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixText: suffix.isEmpty ? null : '/ $suffix',
        suffixStyle: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SpgSellingRow {
  String item = '';
  String itemLabel = '';
  String uom = '';
  final stockAwal = TextEditingController();
  final stockAkhir = TextEditingController();
  final sellOut = TextEditingController();

  _SpgSellingRow({
    this.item = '',
    this.itemLabel = '',
    this.uom = '',
    String opening = '',
    String closing = '',
    String sellOut = '',
  }) {
    stockAwal.text = opening;
    stockAkhir.text = closing;
    this.sellOut.text = sellOut;
  }

  Map<String, dynamic> toPayload() => {
    'item': item,
    'uom': uom,
    'opening_stock': stockAwal.text,
    'closing_stock': stockAkhir.text,
    'sell_out': sellOut.text,
  };

  void dispose() {
    stockAwal.dispose();
    stockAkhir.dispose();
    sellOut.dispose();
  }
}
