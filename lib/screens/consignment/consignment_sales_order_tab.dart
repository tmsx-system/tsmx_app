import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/selling/sales_order_state.dart';
import '../../state/selling/selling_filter_state.dart';
import '../../state/selling/selling_summary_state.dart';
import '../../theme/app_colors.dart';
import '../selling/sales_order/sales_order_panel.dart';
import '../selling/shared/sales_ui.dart';

/// Consignment SO host: scroll wrapper + period filter (Bulan/Tahun/Company/Sales Group)
/// without editing shared [SellingTab] / [SalesOrderPanel].
class ConsignmentSalesOrderTab extends StatefulWidget {
  const ConsignmentSalesOrderTab({super.key});

  @override
  State<ConsignmentSalesOrderTab> createState() =>
      _ConsignmentSalesOrderTabState();
}

class _ConsignmentSalesOrderTabState extends State<ConsignmentSalesOrderTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<SellingFilterState>().loadSellingFilterOptions();
    });
  }

  Future<void> _refresh() async {
    await Future.wait([
      context.read<SalesOrderState>().refreshSalesOrders(),
      context.read<SellingSummaryState>().refreshSellingSummaries(
        documentType: 'Sales Order',
      ),
    ]);
  }

  Future<void> _openPeriodFilter() async {
    final sellingState = context.read<SellingFilterState>();
    final summaryState = context.read<SellingSummaryState>();
    final salesGroupFilter =
        sellingState.sellingCustomerTypeFilter == 'all' ||
            sellingState.sellingSalesGroups.contains(
              sellingState.sellingCustomerTypeFilter,
            )
        ? sellingState.sellingCustomerTypeFilter
        : 'all';

    final result = await showModalBottomSheet<_ConsignmentPeriodFilterValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => _ConsignmentPeriodFilterSheet(
        initialMonth: sellingState.sellingPeriodMonth,
        initialYear: sellingState.sellingPeriodYear,
        initialCompany: sellingState.sellingCompanyFilter,
        initialSalesGroup: salesGroupFilter,
        companies: sellingState.sellingCompanies,
        salesGroups: sellingState.sellingSalesGroups,
        lockSalesPerson: sellingState.mobileAccess.shouldScopeSalesData,
        loading: summaryState.isOrderSummaryLoading,
      ),
    );
    if (result == null || !mounted) return;

    context.read<SellingFilterState>().setSellingPeriod(
      year: result.year,
      month: result.month,
      company: result.company,
      customerType: result.salesGroup,
      documentType: 'Sales Order',
    );
    if (!mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final sellingState = context.watch<SellingFilterState>();
    final summaryState = context.watch<SellingSummaryState>();
    final padding = SalesUi.screenPaddingOf(context);
    final salesGroupFilter =
        sellingState.sellingCustomerTypeFilter == 'all' ||
            sellingState.sellingSalesGroups.contains(
              sellingState.sellingCustomerTypeFilter,
            )
        ? sellingState.sellingCustomerTypeFilter
        : 'all';

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              padding.left,
              padding.top > 0 ? padding.top : 12,
              padding.right,
              120,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ConsignmentPeriodFilterBar(
                    selectedYear: sellingState.sellingPeriodYear,
                    selectedMonth: sellingState.sellingPeriodMonth,
                    selectedCompany: sellingState.sellingCompanyFilter,
                    selectedSalesGroup:
                        sellingState.mobileAccess.shouldScopeSalesData
                        ? 'all'
                        : salesGroupFilter,
                    lockSalesPerson:
                        sellingState.mobileAccess.shouldScopeSalesData,
                    loading: summaryState.isOrderSummaryLoading,
                    onOpenFilter: _openPeriodFilter,
                  ),
                  const SizedBox(height: 12),
                  const SalesOrderPanel(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConsignmentPeriodFilterBar extends StatelessWidget {
  const _ConsignmentPeriodFilterBar({
    required this.selectedYear,
    required this.selectedMonth,
    required this.selectedCompany,
    required this.selectedSalesGroup,
    required this.lockSalesPerson,
    required this.loading,
    required this.onOpenFilter,
  });

  final int selectedYear;
  final int selectedMonth;
  final String selectedCompany;
  final String selectedSalesGroup;
  final bool lockSalesPerson;
  final bool loading;
  final VoidCallback onOpenFilter;

  @override
  Widget build(BuildContext context) {
    final periodLabel = selectedMonth == 0
        ? '$selectedYear'
        : '${_monthName(selectedMonth)} $selectedYear';
    final companyLabel = selectedCompany.trim().isEmpty
        ? 'Semua Company'
        : selectedCompany.trim();
    final salesGroupLabel = lockSalesPerson
        ? 'Sales login'
        : selectedSalesGroup.trim().isEmpty || selectedSalesGroup == 'all'
        ? 'All Sales Group'
        : selectedSalesGroup.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$periodLabel  |  $companyLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  salesGroupLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: loading ? null : onOpenFilter,
            icon: const Icon(Icons.filter_alt_rounded, size: 15),
            label: const Text('Filter'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.softGreen,
              foregroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              minimumSize: const Size(0, 38),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsignmentPeriodFilterValue {
  const _ConsignmentPeriodFilterValue({
    required this.month,
    required this.year,
    required this.company,
    required this.salesGroup,
  });

  final int month;
  final int year;
  final String company;
  final String salesGroup;
}

class _ConsignmentPeriodFilterSheet extends StatefulWidget {
  const _ConsignmentPeriodFilterSheet({
    required this.initialMonth,
    required this.initialYear,
    required this.initialCompany,
    required this.initialSalesGroup,
    required this.companies,
    required this.salesGroups,
    required this.lockSalesPerson,
    required this.loading,
  });

  final int initialMonth;
  final int initialYear;
  final String initialCompany;
  final String initialSalesGroup;
  final List<String> companies;
  final List<String> salesGroups;
  final bool lockSalesPerson;
  final bool loading;

  @override
  State<_ConsignmentPeriodFilterSheet> createState() =>
      _ConsignmentPeriodFilterSheetState();
}

class _ConsignmentPeriodFilterSheetState
    extends State<_ConsignmentPeriodFilterSheet> {
  late int _month;
  late int _year;
  late String _company;
  late String _salesGroup;

  @override
  void initState() {
    super.initState();
    _month = widget.initialMonth;
    _year = widget.initialYear;
    _company = widget.initialCompany;
    _salesGroup = widget.initialSalesGroup;
  }

  void _reset() {
    final now = DateTime.now();
    setState(() {
      _month = now.month;
      _year = now.year;
      _company = '';
      _salesGroup = widget.lockSalesPerson ? widget.initialSalesGroup : 'all';
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _ConsignmentPeriodFilterValue(
        month: _month,
        year: _year,
        company: _company,
        salesGroup: widget.lockSalesPerson ? 'all' : _salesGroup,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = [
      for (var year = currentYear; year >= currentYear - 5; year--) year,
    ];
    final companies = {
      ...widget.companies.where((name) => name.trim().isNotEmpty),
      if (_company.trim().isNotEmpty) _company.trim(),
    }.toList()..sort();
    final selectedCompany = companies.contains(_company) ? _company : '';
    final selectedSalesGroup =
        _salesGroup == 'all' || widget.salesGroups.contains(_salesGroup)
        ? _salesGroup
        : 'all';

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filter Periode & Lainnya',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<int>(
                initialValue: _month,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Bulan',
                  prefixIcon: Icon(Icons.calendar_today_rounded, size: 18),
                ),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Semua Bulan')),
                  for (var i = 1; i <= 12; i++)
                    DropdownMenuItem(value: i, child: Text(_monthName(i))),
                ],
                onChanged: widget.loading
                    ? null
                    : (value) => setState(() => _month = value ?? _month),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: years.contains(_year) ? _year : currentYear,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tahun',
                  prefixIcon: Icon(Icons.event_rounded, size: 18),
                ),
                items: [
                  for (final year in years)
                    DropdownMenuItem(value: year, child: Text('$year')),
                ],
                onChanged: widget.loading
                    ? null
                    : (value) => setState(() => _year = value ?? _year),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedCompany,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Company',
                  prefixIcon: Icon(Icons.business_rounded, size: 18),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Semua Company'),
                  ),
                  for (final company in companies)
                    DropdownMenuItem(
                      value: company,
                      child: Text(company, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: widget.loading
                    ? null
                    : (value) => setState(() => _company = value ?? ''),
              ),
              if (!widget.lockSalesPerson) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedSalesGroup,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sales Group',
                    prefixIcon: Icon(Icons.account_tree_rounded, size: 18),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All')),
                    for (final group in widget.salesGroups)
                      DropdownMenuItem(
                        value: group,
                        child: Text(group, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: widget.loading
                      ? null
                      : (value) => setState(() => _salesGroup = value ?? 'all'),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.loading ? null : _reset,
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.loading ? null : _apply,
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
}

String _monthName(int month) {
  const names = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  if (month < 1 || month > 12) return '-';
  return names[month - 1];
}
