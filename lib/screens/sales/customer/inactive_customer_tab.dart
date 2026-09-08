import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/inactive_customer.dart';
import '../../../state/selling/customer_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../shared/sales_ui.dart';

const Color _inactiveGreen = Color(0xFF16A34A);
const Color _inactiveTeal = Color(0xFF14B8A6);
const Color _inactiveBlue = Color(0xFF3B82F6);
const Color _inactiveOrange = Color(0xFFF59E0B);

class InactiveCustomerTab extends StatefulWidget {
  const InactiveCustomerTab({super.key});

  @override
  State<InactiveCustomerTab> createState() => _InactiveCustomerTabState();
}

class _InactiveCustomerTabState extends State<InactiveCustomerTab> {
  final _searchController = TextEditingController();
  final _daysController = TextEditingController(text: '60');
  int _days = 60;
  final Set<String> _documentTypes = {'Sales Order'};
  String _query = '';
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CustomerState>().refreshInactiveCustomers(
        daysSinceLastOrder: _days,
        doctypes: _selectedDocumentTypes,
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CustomerState>();
    final customers = _filterCustomers(state.inactiveCustomers);

    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        onRefresh: () => context.read<CustomerState>().refreshInactiveCustomers(
          daysSinceLastOrder: _days,
          doctypes: _selectedDocumentTypes,
          forceRemote: true,
        ),
        child: ListView(
          padding: SalesUi.compactScreenPaddingOf(context),
          children: [
            _InactiveCustomerFilter(
              days: _days,
              selectedDocumentTypes: _documentTypes,
              controller: _searchController,
              loading: state.isInactiveCustomersLoading,
              onFilterChanged: (value) {
                setState(() {
                  _days = value.days;
                  _daysController.text = value.days.toString();
                  _documentTypes
                    ..clear()
                    ..addAll(value.documentTypes);
                });
                context.read<CustomerState>().refreshInactiveCustomers(
                  daysSinceLastOrder: _days,
                  doctypes: _selectedDocumentTypes,
                  forceRemote: true,
                );
              },
              onSearchChanged: (value) => setState(() => _query = value),
            ),
            SalesUi.gap(),
            if (state.inactiveCustomersError != null) ...[
              ErpErrorBox(
                message: state.inactiveCustomersError!,
                onRetry: () =>
                    context.read<CustomerState>().refreshInactiveCustomers(
                      daysSinceLastOrder: _days,
                      doctypes: _selectedDocumentTypes,
                      forceRemote: true,
                    ),
              ),
              SalesUi.gap(),
            ],
            _InactiveCustomerSummary(
              total: state.inactiveCustomers.length,
              visible: customers.length,
              days: _days,
              documentTypes: _documentTypes,
            ),
            SalesUi.gap(),
            if (state.isInactiveCustomersLoading &&
                state.inactiveCustomers.isEmpty)
              const _InactiveCustomerLoading()
            else if (customers.isEmpty)
              const ErpEmptyState(
                title: 'Belum ada inactive customer',
                message: 'Coba ubah range hari atau refresh report ERPNext.',
                icon: Icons.person_search_rounded,
              )
            else
              ...customers.map(_InactiveCustomerCard.new),
          ],
        ),
      ),
    );
  }

  List<String> get _selectedDocumentTypes {
    if (_documentTypes.isEmpty) return const ['Sales Order'];
    return _documentTypes.toList()..sort();
  }

  List<InactiveCustomer> _filterCustomers(List<InactiveCustomer> customers) {
    final keyword = _query.trim().toLowerCase();
    if (keyword.isEmpty) return customers;
    return customers.where((customer) {
      return customer.customer.toLowerCase().contains(keyword) ||
          customer.customerName.toLowerCase().contains(keyword) ||
          customer.customerGroup.toLowerCase().contains(keyword) ||
          customer.territory.toLowerCase().contains(keyword);
    }).toList();
  }
}

class _InactiveCustomerFilter extends StatelessWidget {
  const _InactiveCustomerFilter({
    required this.days,
    required this.selectedDocumentTypes,
    required this.controller,
    required this.loading,
    required this.onFilterChanged,
    required this.onSearchChanged,
  });

  final int days;
  final Set<String> selectedDocumentTypes;
  final TextEditingController controller;
  final bool loading;
  final ValueChanged<_InactiveCustomerFilterValue> onFilterChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SalesInfoCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          accent: _inactiveGreen,
          child: Row(
            children: [
              const Icon(
                Icons.person_search_rounded,
                color: AppColors.slate,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_documentTypeLabel(selectedDocumentTypes)} | $days hari',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Inactive Customers ERPNext',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: loading ? null : () => _openFilterSheet(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.softGreen,
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.filter_alt_outlined, size: 15),
                label: const Text(
                  'Filter',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
        SalesUi.gap(),
        SalesInfoCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: controller,
                onChanged: onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: _inputDecoration(
                  label: 'Cari customer',
                  icon: Icons.search_rounded,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _documentTypeLabel(Set<String> doctypes) {
    final hasSo = doctypes.contains('Sales Order');
    final hasSi = doctypes.contains('Sales Invoice');
    if (hasSo && hasSi) return 'SO + SI';
    if (hasSi) return 'Sales Invoice';
    return 'Sales Order';
  }

  Future<void> _openFilterSheet(BuildContext context) async {
    final result = await showModalBottomSheet<_InactiveCustomerFilterValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InactiveCustomerFilterSheet(
        days: days,
        selectedDocumentTypes: selectedDocumentTypes,
      ),
    );
    if (result == null) return;
    onFilterChanged(result);
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix == null
          ? null
          : Padding(padding: const EdgeInsets.only(right: 6), child: suffix),
      suffixIconConstraints: const BoxConstraints(minWidth: 72),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _InactiveCustomerFilterValue {
  const _InactiveCustomerFilterValue({
    required this.days,
    required this.documentTypes,
  });

  final int days;
  final Set<String> documentTypes;
}

class _InactiveCustomerFilterSheet extends StatefulWidget {
  const _InactiveCustomerFilterSheet({
    required this.days,
    required this.selectedDocumentTypes,
  });

  final int days;
  final Set<String> selectedDocumentTypes;

  @override
  State<_InactiveCustomerFilterSheet> createState() =>
      _InactiveCustomerFilterSheetState();
}

class _InactiveCustomerFilterSheetState
    extends State<_InactiveCustomerFilterSheet> {
  late final TextEditingController _daysController = TextEditingController(
    text: widget.days.toString(),
  );
  late final Set<String> _selected = {...widget.selectedDocumentTypes};

  @override
  void dispose() {
    _daysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppColors.cardShadow,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filter Inactive Customer',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _DocumentTypePicker(
                selected: _selected,
                onChanged: (value) => setState(() {
                  _selected
                    ..clear()
                    ..addAll(value);
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _daysController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: _inputDecoration(
                  label: 'Tidak order selama',
                  icon: Icons.schedule_rounded,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reset,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Terapkan Filter'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  void _reset() {
    _daysController.text = '60';
    setState(() {
      _selected
        ..clear()
        ..add('Sales Order');
    });
  }

  void _apply() {
    final parsed = int.tryParse(_daysController.text.trim());
    if (parsed == null || parsed <= 0 || _selected.isEmpty) return;
    Navigator.of(context).pop(
      _InactiveCustomerFilterValue(
        days: parsed,
        documentTypes: _selected.toSet(),
      ),
    );
  }
}

class _InactiveCustomerSummary extends StatelessWidget {
  const _InactiveCustomerSummary({
    required this.total,
    required this.visible,
    required this.days,
    required this.documentTypes,
  });

  final int total;
  final int visible;
  final int days;
  final Set<String> documentTypes;

  @override
  Widget build(BuildContext context) {
    return SalesInfoCard(
      child: Row(
        children: [
          _SummaryMetric(
            label: 'Inactive',
            value: total.toString(),
            icon: Icons.person_off_rounded,
            color: _inactiveGreen,
          ),
          const SizedBox(width: 10),
          _SummaryMetric(
            label: 'Tampil',
            value: visible.toString(),
            icon: Icons.visibility_rounded,
            color: _inactiveTeal,
          ),
          const SizedBox(width: 10),
          _SummaryMetric(
            label: 'Dokumen',
            value: _documentTypeLabel(documentTypes),
            icon: Icons.date_range_rounded,
            color: _inactiveBlue,
          ),
        ],
      ),
    );
  }

  String _documentTypeLabel(Set<String> doctypes) {
    final hasSo = doctypes.contains('Sales Order');
    final hasSi = doctypes.contains('Sales Invoice');
    if (hasSo && hasSi) return 'SO + SI';
    if (hasSi) return 'SI';
    return 'SO';
  }
}

class _DocumentTypePicker extends StatelessWidget {
  const _DocumentTypePicker({required this.selected, required this.onChanged});

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openSheet(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Dokumen',
          prefixIcon: const Icon(Icons.description_rounded),
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
        child: Text(
          _label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  String get _label {
    final hasSo = selected.contains('Sales Order');
    final hasSi = selected.contains('Sales Invoice');
    if (hasSo && hasSi) return 'Sales Order, Sales Invoice';
    if (hasSi) return 'Sales Invoice';
    return 'Sales Order';
  }

  Future<void> _openSheet(BuildContext context) async {
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DocumentTypeSheet(selected: selected),
    );
    if (result == null || result.isEmpty) return;
    onChanged(result);
  }
}

class _DocumentTypeSheet extends StatefulWidget {
  const _DocumentTypeSheet({required this.selected});

  final Set<String> selected;

  @override
  State<_DocumentTypeSheet> createState() => _DocumentTypeSheetState();
}

class _DocumentTypeSheetState extends State<_DocumentTypeSheet> {
  static const _options = [('Sales Order', 'SO'), ('Sales Invoice', 'SI')];
  late final Set<String> _selected = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _options.where((option) {
      final keyword = _query.trim().toLowerCase();
      if (keyword.isEmpty) return true;
      return option.$1.toLowerCase().contains(keyword) ||
          option.$2.toLowerCase().contains(keyword);
    }).toList();

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pilih Dokumen',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Cari SO atau SI',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...filtered.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SalesPickerOptionTile(
                  title: option.$1,
                  subtitle: option.$2,
                  icon: Icons.description_outlined,
                  selected: _selected.contains(option.$1),
                  accent: _inactiveGreen,
                  onTap: () => _toggle(option.$1),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_selected),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Pilih'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(String value) {
    setState(() {
      if (_selected.contains(value)) {
        _selected.remove(value);
      } else {
        _selected.add(value);
      }
    });
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
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
    );
  }
}

class _InactiveCustomerCard extends StatelessWidget {
  const _InactiveCustomerCard(this.customer);

  final InactiveCustomer customer;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(customer.totalOrderValue);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SalesInfoCard(
        accent: _inactiveGreen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.softGreen,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.store_mall_directory_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (customer.customer.isNotEmpty &&
                          customer.customer != customer.displayName) ...[
                        const SizedBox(height: 3),
                        Text(
                          customer.customer,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _inactiveOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _inactiveOrange.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Text(
                    '${customer.daysSinceLastOrder} hari',
                    style: const TextStyle(
                      color: _inactiveOrange,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            SalesUi.gap(),
            _InfoRow(label: 'Last Order', value: _lastOrderLabel(customer)),
            if (customer.customerGroup.isNotEmpty)
              _InfoRow(label: 'Group', value: customer.customerGroup),
            if (customer.territory.isNotEmpty)
              _InfoRow(label: 'Territory', value: customer.territory),
            if (customer.totalOrderValue > 0)
              _InfoRow(label: 'Total Order', value: money),
            _InfoRow(
              label: 'Dokumen',
              value: customer.documentType == 'Sales Invoice' ? 'SI' : 'SO',
            ),
          ],
        ),
      ),
    );
  }

  String _lastOrderLabel(InactiveCustomer customer) {
    final parts = [
      if (customer.lastOrderDate.isNotEmpty) customer.lastOrderDate,
      if (customer.lastOrder.isNotEmpty) customer.lastOrder,
    ];
    return parts.isEmpty ? '-' : parts.join(' - ');
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InactiveCustomerLoading extends StatelessWidget {
  const _InactiveCustomerLoading();

  @override
  Widget build(BuildContext context) {
    return SalesInfoCard(
      child: Row(
        children: const [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Memuat report Inactive Customers dari ERPNext...',
              style: TextStyle(
                color: AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
