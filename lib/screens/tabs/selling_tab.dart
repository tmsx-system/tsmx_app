import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/selling/delivery_note_state.dart';
import '../../state/selling/sales_invoice_state.dart';
import '../../state/selling/sales_order_state.dart';
import '../../state/selling/selling_filter_state.dart';
import '../../state/selling/selling_summary_state.dart';
import '../../theme/app_colors.dart';
import '../sales/shared/sales_ui.dart';
import '../sales/delivery_note/delivery_note_panel.dart';
import '../sales/sales_invoice/sales_invoice_panel.dart';
import '../sales/sales_order/sales_order_panel.dart';

const _defaultSellingSegmentIds = ['so', 'dn', 'si'];

class SellingTab extends StatefulWidget {
  final String selectedSegment;
  final List<String> allowedSegments;
  final ValueChanged<String>? onSegmentChanged;

  const SellingTab({
    super.key,
    required this.selectedSegment,
    this.allowedSegments = _defaultSellingSegmentIds,
    this.onSegmentChanged,
  });

  @override
  State<SellingTab> createState() => SellingTabState();
}

class SellingTabState extends State<SellingTab>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

  List<String> get _allowedSegments {
    final allowed = widget.allowedSegments
        .where(_defaultSellingSegmentIds.contains)
        .toSet()
        .toList(growable: false);
    return allowed.isEmpty ? const ['so'] : allowed;
  }

  String get _activeDocumentType {
    final controller = _tabController;
    final index = controller?.index ?? _initialIndex;
    return switch (_allowedSegments[index]) {
      'dn' => 'Delivery Note',
      'si' => 'Sales Invoice',
      _ => 'Sales Order',
    };
  }

  int get _initialIndex {
    final index = _allowedSegments.indexOf(widget.selectedSegment);
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: _allowedSegments.length,
      vsync: this,
      initialIndex: _initialIndex,
    );

    _tabController!.addListener(_handleTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sellingState = context.read<SellingFilterState>();
      final summaryState = context.read<SellingSummaryState>();

      sellingState.loadSellingFilterOptions();
      summaryState.refreshSellingSummaries(documentType: _activeDocumentType);
      _ensureActiveDocumentLoaded();
    });
  }

  @override
  void didUpdateWidget(covariant SellingTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    final controller = _tabController;
    if (controller == null) return;

    if (oldWidget.selectedSegment == widget.selectedSegment) return;

    final nextIndex = _allowedSegments.indexOf(widget.selectedSegment);
    if (nextIndex < 0 || nextIndex == controller.index) return;

    controller.animateTo(nextIndex);
  }

  @override
  void dispose() {
    final controller = _tabController;
    if (controller != null) {
      controller.removeListener(_handleTabChanged);
      controller.dispose();
    }
    super.dispose();
  }

  void _handleTabChanged() {
    final controller = _tabController;
    if (controller == null) return;
    if (controller.indexIsChanging) return;

    final id = _allowedSegments[controller.index];

    widget.onSegmentChanged?.call(id);

    context.read<SellingSummaryState>().refreshSellingSummaries(
      documentType: _activeDocumentType,
    );
    _ensureActiveDocumentLoaded();
  }

  void _ensureActiveDocumentLoaded() {
    final controller = _tabController;
    final id = _allowedSegments[controller?.index ?? _initialIndex];
    switch (id) {
      case 'dn':
        final state = context.read<DeliveryNoteState>();
        if (state.deliveryNotes.isEmpty) {
          state.refreshDeliveryNotes();
        }
        break;

      case 'si':
        final state = context.read<SalesInvoiceState>();
        if (state.salesInvoices.isEmpty) {
          state.refreshSalesInvoices();
        }
        break;

      case 'so':
      default:
        final state = context.read<SalesOrderState>();
        if (state.salesOrders.isEmpty) {
          state.refreshSalesOrders();
        }
        break;
    }
  }

  Future<void> refreshCurrent() async {
    final controller = _tabController;
    if (controller == null) return;

    final summaryState = context.read<SellingSummaryState>();

    await Future.wait([
      summaryState.refreshSellingSummaries(
        forceRemote: true,
        documentType: _activeDocumentType,
      ),
      switch (_allowedSegments[controller.index]) {
        'dn' => context.read<DeliveryNoteState>().refreshDeliveryNotes(),
        'si' => context.read<SalesInvoiceState>().refreshSalesInvoices(),
        _ => context.read<SalesOrderState>().refreshSalesOrders(),
      },
    ]);
  }

  void _handleLoadMore() {
    final controller = _tabController;
    if (controller == null) return;

    final id = _allowedSegments[controller.index];

    switch (id) {
      case 'dn':
        context.read<DeliveryNoteState>().loadMoreDeliveryNotes();
        break;

      case 'si':
        context.read<SalesInvoiceState>().loadMoreSalesInvoices();
        break;

      case 'so':
      default:
        context.read<SalesOrderState>().loadMoreSalesOrders();
        break;
    }
  }

  Future<void> _openSellingPeriodFilter() async {
    final sellingState = context.read<SellingFilterState>();
    final summaryState = context.read<SellingSummaryState>();
    final salesGroupFilter =
        sellingState.sellingCustomerTypeFilter == 'all' ||
            sellingState.sellingSalesGroups.contains(
              sellingState.sellingCustomerTypeFilter,
            )
        ? sellingState.sellingCustomerTypeFilter
        : 'all';

    final result = await showModalBottomSheet<_SellingPeriodFilterValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => _SellingPeriodFilterSheet(
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

    await context.read<SellingFilterState>().setSellingPeriod(
      year: result.year,
      month: result.month,
      company: result.company,
      customerType: result.salesGroup,
      documentType: _activeDocumentType,
    );
    if (!mounted) return;
    await switch (_activeDocumentType) {
      'Delivery Note' =>
        context.read<DeliveryNoteState>().refreshDeliveryNotes(),
      'Sales Invoice' =>
        context.read<SalesInvoiceState>().refreshSalesInvoices(),
      _ => context.read<SalesOrderState>().refreshSalesOrders(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final sellingState = context.watch<SellingFilterState>();
    final summaryState = context.watch<SellingSummaryState>();
    final salesGroupFilter =
        sellingState.sellingCustomerTypeFilter == 'all' ||
            sellingState.sellingSalesGroups.contains(
              sellingState.sellingCustomerTypeFilter,
            )
        ? sellingState.sellingCustomerTypeFilter
        : 'all';

    final controller = _tabController;

    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: refreshCurrent,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.extentAfter > 320) return false;
            _handleLoadMore();
            return false;
          },
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: SalesUi.screenPaddingOf(context),
                children: [
                  _SellingPeriodFilterBar(
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
                    onOpenFilter: _openSellingPeriodFilter,
                  ),

                  const SizedBox(height: 12),

                  SalesPillTabBar(
                    controller: controller,
                    tabs: [
                      for (final segment in _allowedSegments)
                        Tab(text: _segmentLabel(segment)),
                    ],
                  ),

                  const SizedBox(height: 14),

                  switch (controller.index) {
                    _ => _segmentPanel(_allowedSegments[controller.index]),
                  },
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _segmentLabel(String segment) => switch (segment) {
    'dn' => 'Delivery Note',
    'si' => 'Invoice',
    _ => 'Sales Order',
  };

  Widget _segmentPanel(String segment) => switch (segment) {
    'dn' => const DeliveryNotePanel(),
    'si' => const SalesInvoicePanel(),
    _ => const SalesOrderPanel(),
  };
}

class _SellingPeriodFilterBar extends StatelessWidget {
  const _SellingPeriodFilterBar({
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

class _SellingPeriodFilterValue {
  const _SellingPeriodFilterValue({
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

class _SellingPeriodFilterSheet extends StatefulWidget {
  const _SellingPeriodFilterSheet({
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
  State<_SellingPeriodFilterSheet> createState() =>
      _SellingPeriodFilterSheetState();
}

class _SellingPeriodFilterSheetState extends State<_SellingPeriodFilterSheet> {
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
      _SellingPeriodFilterValue(
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
