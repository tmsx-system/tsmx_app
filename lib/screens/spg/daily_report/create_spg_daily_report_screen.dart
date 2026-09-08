import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/spg_workspace.dart';
import '../../../state/spg/spg_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/responsive/responsive_layout.dart';

class CreateSpgDailyReportScreen extends StatefulWidget {
  const CreateSpgDailyReportScreen({super.key});

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
  List<Map<String, dynamic>> _employees = const [];
  SpgCustomerOption? _customer;
  Map<String, dynamic>? _employee;
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
      final results = await Future.wait([
        state.mobileAccess.canSelectAnyEmployee
            ? Future.value(const <SpgCustomerOption>[])
            : state.fetchScheduledSpgCustomers(),
        state.fetchSpgSellingItems(''),
        if (state.mobileAccess.canSelectAnyEmployee)
          state.fetchEmployeeOptions(),
      ]);
      if (!mounted) return;
      setState(() {
        _customers = results[0] as List<SpgCustomerOption>;
        _items = results[1] as List<Map<String, dynamic>>;
        _employees = state.mobileAccess.canSelectAnyEmployee
            ? results[2] as List<Map<String, dynamic>>
            : const <Map<String, dynamic>>[];
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadScheduledCustomersForEmployee() async {
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
      final customers = await context
          .read<SpgState>()
          .fetchScheduledSpgCustomers(employee: employee);
      if (!mounted) return;
      setState(() => _customers = customers);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final canSelectEmployee = context
        .read<SpgState>()
        .mobileAccess
        .canSelectAnyEmployee;
    if (canSelectEmployee && _employee == null) {
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
      await context.read<SpgState>().createSpgDailyReport(
        customer: _customer!.id,
        sellingItems: _rows.map((row) => row.toPayload()).toList(),
        employee: _employee?['name']?.toString(),
        notes: _notes.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
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
        title: const Text('Buat Report Selling'),
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
              child: Text(_saving ? 'Menyimpan...' : 'Kirim Report Selling'),
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
          if (context.watch<SpgState>().mobileAccess.canSelectAnyEmployee) ...[
            _employeeSearchField(),
            const SizedBox(height: 12),
          ],
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
          Autocomplete<Map<String, dynamic>>(
            displayStringForOption: _itemLabel,
            optionsMaxHeight: 280,
            optionsBuilder: (value) async {
              final query = value.text.toLowerCase().trim();
              if (query.isEmpty) return _items;
              final remoteItems = await context
                  .read<SpgState>()
                  .fetchSpgSellingItems(query);
              if (remoteItems.isNotEmpty) return remoteItems;
              return _items.where((item) {
                final code = item['item_code']?.toString().toLowerCase() ?? '';
                final name = item['item_name']?.toString().toLowerCase() ?? '';
                final id = item['name']?.toString().toLowerCase() ?? '';
                return code.contains(query) ||
                    name.contains(query) ||
                    id.contains(query);
              });
            },
            onSelected: (option) {
              setState(() {
                row.item =
                    option['item_code']?.toString() ??
                    option['name']?.toString() ??
                    '';
                row.itemLabel = _itemLabel(option);
                row.uom = option['stock_uom']?.toString() ?? '';
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onSubmit) {
              if (row.itemLabel.isNotEmpty && controller.text.isEmpty) {
                controller.text = row.itemLabel;
              }
              return TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Cari name atau kode item',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                  suffixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) {
                  if (value.trim() != row.itemLabel) {
                    setState(() {
                      row.item = '';
                      row.itemLabel = value.trim();
                      row.uom = '';
                    });
                  }
                },
              );
            },
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
    final needsEmployee =
        context.read<SpgState>().mobileAccess.canSelectAnyEmployee &&
        _employee == null;
    return Autocomplete<SpgCustomerOption>(
      displayStringForOption: _customerLabel,
      optionsMaxHeight: 280,
      optionsBuilder: (value) {
        if (needsEmployee) return const Iterable<SpgCustomerOption>.empty();
        final query = value.text.toLowerCase().trim();
        if (query.isEmpty) return _customers;
        return _customers.where((customer) {
          return customer.id.toLowerCase().contains(query) ||
              customer.name.toLowerCase().contains(query) ||
              customer.address.toLowerCase().contains(query);
        });
      },
      onSelected: (value) => setState(() => _customer = value),
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        final selectedLabel = _customer == null
            ? ''
            : _customerLabel(_customer!);
        if (selectedLabel.isNotEmpty && controller.text.isEmpty) {
          controller.text = selectedLabel;
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: !_saving && !_loading && !needsEmployee,
          decoration: InputDecoration(
            labelText: 'Customer',
            hintText: needsEmployee
                ? 'Pilih employee dulu'
                : 'Cari customer dari schedule',
            prefixIcon: const Icon(Icons.storefront_outlined),
            suffixIcon: const Icon(Icons.search_rounded),
          ),
          onChanged: (text) {
            if (_customer != null && text != selectedLabel) {
              setState(() => _customer = null);
            }
          },
        );
      },
    );
  }

  Widget _employeeSearchField() {
    return Autocomplete<Map<String, dynamic>>(
      displayStringForOption: _employeeLabel,
      optionsMaxHeight: 280,
      optionsBuilder: (value) {
        final query = value.text.toLowerCase().trim();
        if (query.isEmpty) return _employees;
        return _employees.where((employee) {
          final name = employee['name']?.toString().toLowerCase() ?? '';
          final employeeName =
              employee['employee_name']?.toString().toLowerCase() ?? '';
          final userId = employee['user_id']?.toString().toLowerCase() ?? '';
          return name.contains(query) ||
              employeeName.contains(query) ||
              userId.contains(query);
        });
      },
      onSelected: (value) {
        setState(() => _employee = value);
        _loadScheduledCustomersForEmployee();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        final selectedLabel = _employee == null
            ? ''
            : _employeeLabel(_employee!);
        if (selectedLabel.isNotEmpty && controller.text.isEmpty) {
          controller.text = selectedLabel;
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: !_saving && !_loading,
          decoration: const InputDecoration(
            labelText: 'Employee',
            hintText: 'Cari employee',
            prefixIcon: Icon(Icons.badge_outlined),
            suffixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (text) {
            if (_employee != null && text != selectedLabel) {
              setState(() {
                _employee = null;
                _customer = null;
                _customers = const [];
              });
            }
          },
        );
      },
    );
  }

  String _customerLabel(SpgCustomerOption customer) {
    if (customer.id.trim().isEmpty) return customer.name;
    return '${customer.name} - ${customer.id}';
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
