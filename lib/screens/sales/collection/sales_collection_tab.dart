import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/selling/collection_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/date_range_presets.dart';
import 'ar_aging_tab.dart';
import 'outstanding_invoice_tab.dart';
import 'customer_payment_schedule_tab.dart';
import '../shared/sales_ui.dart';

class SalesCollectionTab extends StatefulWidget {
  const SalesCollectionTab({super.key});

  @override
  State<SalesCollectionTab> createState() => _SalesCollectionTabState();
}

class _SalesCollectionTabState extends State<SalesCollectionTab> {
  DateRangePreset _range = DateRangePresets.monthToDateRange();
  CollectionAgingDateBasis _dateBasis = CollectionAgingDateBasis.invoiceDate;
  bool _applyDateFilter = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<CollectionState>();
    final companies = state.sellingCompanies;
    if (state.sellingCompanyFilter.isEmpty && companies.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final current = context.read<CollectionState>();
        if (current.sellingCompanyFilter.isNotEmpty) return;
        final preferred = current.preferredCompany(current.sellingCompanies);
        if (preferred == null || preferred.isEmpty) return;
        current.setSellingPeriod(
          year: current.sellingPeriodYear,
          month: current.sellingPeriodMonth,
          company: preferred,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CollectionState>();
    final companies = state.sellingCompanies;
    final selectedCompany = state.sellingCompanyFilter.isNotEmpty
        ? state.sellingCompanyFilter
        : (state.preferredCompany(companies) ?? '');
    final pagePadding = SalesUi.screenPaddingOf(context);
    return DefaultTabController(
      length: 3,
      child: ColoredBox(
        color: AppColors.background,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  pagePadding.left,
                  18,
                  pagePadding.right,
                  12,
                ),
                child: Column(
                  children: [
                    _CollectionPeriodFilterBar(
                      selectedYear: state.sellingPeriodYear,
                      selectedMonth: state.sellingPeriodMonth,
                      selectedCompany: selectedCompany,
                      range: _range,
                      dateBasis: _dateBasis,
                      applyDateFilter: _applyDateFilter,
                      loading: state.isOrderSummaryLoading,
                      onOpenFilter: _openCollectionPeriodFilter,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  pagePadding.left,
                  0,
                  pagePadding.right,
                  12,
                ),
                child: SalesPillTabBar(
                  tabs: const [
                    Tab(text: 'AR Aging'),
                    Tab(text: 'Invoice'),
                    Tab(text: 'Janji Bayar'),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              ArAgingTab(
                key: ValueKey('ar-$selectedCompany'),
                range: _range,
                dateBasis: _dateBasis,
                applyDateFilter: _applyDateFilter,
              ),
              OutstandingInvoiceTab(
                key: ValueKey('invoice-$selectedCompany'),
                range: _range,
                dateBasis: _dateBasis,
                applyDateFilter: _applyDateFilter,
              ),
              CustomerPaymentScheduleTab(
                key: ValueKey('schedule-$selectedCompany'),
                range: _range,
                dateBasis: _dateBasis,
                applyDateFilter: _applyDateFilter,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCollectionPeriodFilter() async {
    final state = context.read<CollectionState>();
    final result = await showModalBottomSheet<_CollectionPeriodFilterValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => _CollectionPeriodFilterSheet(
        initialMonth: state.sellingPeriodMonth,
        initialYear: state.sellingPeriodYear,
        initialCompany: state.sellingCompanyFilter,
        initialRange: _range,
        initialDateBasis: _dateBasis,
        initialApplyDateFilter: _applyDateFilter,
        companies: state.sellingCompanies,
        loading: state.isOrderSummaryLoading,
      ),
    );
    if (result == null || !mounted) return;
    _setPeriod(
      year: result.year,
      month: result.month,
      company: result.company,
      range: result.range,
      dateBasis: result.dateBasis,
      applyDateFilter: result.applyDateFilter,
    );
  }

  void _setPeriod({
    required int year,
    required int month,
    String? company,
    DateRangePreset? range,
    CollectionAgingDateBasis? dateBasis,
    bool? applyDateFilter,
  }) {
    context.read<CollectionState>().setSellingPeriod(
      year: year,
      month: month,
      company: company,
      documentType: 'Sales Invoice',
    );
    setState(() {
      _range = range ?? _rangeForPeriod(year, month);
      _dateBasis = dateBasis ?? _dateBasis;
      _applyDateFilter = applyDateFilter ?? false;
    });
  }

  DateRangePreset _rangeForPeriod(int year, int month) {
    if (month == 0) {
      return DateRangePreset(from: DateTime(year), to: DateTime(year, 12, 31));
    }
    return DateRangePreset(
      from: DateTime(year, month, 1),
      to: DateTime(year, month + 1, 0),
    );
  }
}

class _CollectionPeriodFilterBar extends StatelessWidget {
  const _CollectionPeriodFilterBar({
    required this.selectedYear,
    required this.selectedMonth,
    required this.selectedCompany,
    required this.range,
    required this.dateBasis,
    required this.applyDateFilter,
    required this.loading,
    required this.onOpenFilter,
  });

  final int selectedYear;
  final int selectedMonth;
  final String selectedCompany;
  final DateRangePreset range;
  final CollectionAgingDateBasis dateBasis;
  final bool applyDateFilter;
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
    final agingLabel = applyDateFilter
        ? '${dateBasis == CollectionAgingDateBasis.invoiceDate ? 'Tanggal SI' : 'Tanggal TT'} | '
              '${DateRangePresets.toFrappeDate(range.from)} s/d ${DateRangePresets.toFrappeDate(range.to)}'
        : 'Aging mengikuti periode collection';

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
                  agingLabel,
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

class _CollectionPeriodFilterValue {
  const _CollectionPeriodFilterValue({
    required this.month,
    required this.year,
    required this.company,
    required this.range,
    required this.dateBasis,
    required this.applyDateFilter,
  });

  final int month;
  final int year;
  final String company;
  final DateRangePreset range;
  final CollectionAgingDateBasis dateBasis;
  final bool applyDateFilter;
}

class _CollectionPeriodFilterSheet extends StatefulWidget {
  const _CollectionPeriodFilterSheet({
    required this.initialMonth,
    required this.initialYear,
    required this.initialCompany,
    required this.initialRange,
    required this.initialDateBasis,
    required this.initialApplyDateFilter,
    required this.companies,
    required this.loading,
  });

  final int initialMonth;
  final int initialYear;
  final String initialCompany;
  final DateRangePreset initialRange;
  final CollectionAgingDateBasis initialDateBasis;
  final bool initialApplyDateFilter;
  final List<String> companies;
  final bool loading;

  @override
  State<_CollectionPeriodFilterSheet> createState() =>
      _CollectionPeriodFilterSheetState();
}

class _CollectionPeriodFilterSheetState
    extends State<_CollectionPeriodFilterSheet> {
  late int _month;
  late int _year;
  late String _company;
  late DateRangePreset _range;
  late CollectionAgingDateBasis _dateBasis;
  late bool _applyDateFilter;

  @override
  void initState() {
    super.initState();
    _month = widget.initialMonth;
    _year = widget.initialYear;
    _company = widget.initialCompany;
    _range = widget.initialRange;
    _dateBasis = widget.initialDateBasis;
    _applyDateFilter = widget.initialApplyDateFilter;
  }

  void _reset() {
    final now = DateTime.now();
    setState(() {
      _month = now.month;
      _year = now.year;
      _company = '';
      _range = DateRangePresets.monthToDateRange();
      _dateBasis = CollectionAgingDateBasis.invoiceDate;
      _applyDateFilter = false;
    });
  }

  Future<void> _pickRange() async {
    if (!_applyDateFilter) {
      setState(() => _applyDateFilter = true);
    }
    final today = DateTime.now();
    final lastDate = _range.to.isAfter(today) ? _range.to : today;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: lastDate,
      initialDateRange: DateTimeRange(start: _range.from, end: _range.to),
    );
    if (picked == null) return;
    setState(() {
      _range = DateRangePreset(from: picked.start, to: picked.end);
      _applyDateFilter = true;
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _CollectionPeriodFilterValue(
        month: _month,
        year: _year,
        company: _company,
        range: _applyDateFilter ? _range : _rangeForPeriod(_year, _month),
        dateBasis: _dateBasis,
        applyDateFilter: _applyDateFilter,
      ),
    );
  }

  DateRangePreset _rangeForPeriod(int year, int month) {
    if (month == 0) {
      return DateRangePreset(from: DateTime(year), to: DateTime(year, 12, 31));
    }
    return DateRangePreset(
      from: DateTime(year, month, 1),
      to: DateTime(year, month + 1, 0),
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
                    : (value) => setState(() {
                        _month = value ?? _month;
                        if (!_applyDateFilter) {
                          _range = _rangeForPeriod(_year, _month);
                        }
                      }),
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
                    : (value) => setState(() {
                        _year = value ?? _year;
                        if (!_applyDateFilter) {
                          _range = _rangeForPeriod(_year, _month);
                        }
                      }),
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
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const _CollectionIconTile(
                          icon: Icons.filter_alt_rounded,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Filter Aging Piutang',
                                style: TextStyle(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Pakai tanggal SI atau tanggal tukar faktur',
                                style: TextStyle(
                                  color: AppColors.slate,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _applyDateFilter,
                          activeThumbColor: AppColors.white,
                          activeTrackColor: AppColors.primary,
                          inactiveThumbColor: AppColors.white,
                          inactiveTrackColor: AppColors.border,
                          onChanged: widget.loading
                              ? null
                              : (value) =>
                                    setState(() => _applyDateFilter = value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _FilterChipButton(
                            label: 'Tanggal SI',
                            selected:
                                _dateBasis ==
                                CollectionAgingDateBasis.invoiceDate,
                            onTap: widget.loading
                                ? () {}
                                : () => setState(() {
                                    _dateBasis =
                                        CollectionAgingDateBasis.invoiceDate;
                                    _applyDateFilter = true;
                                  }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _FilterChipButton(
                            label: 'Tanggal TT',
                            selected:
                                _dateBasis ==
                                CollectionAgingDateBasis.tukarFakturDate,
                            onTap: widget.loading
                                ? () {}
                                : () => setState(() {
                                    _dateBasis = CollectionAgingDateBasis
                                        .tukarFakturDate;
                                    _applyDateFilter = true;
                                  }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Material(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: widget.loading ? null : _pickRange,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.08),
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.date_range_rounded,
                                color: AppColors.primary,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${DateRangePresets.toFrappeDate(_range.from)} s/d '
                                  '${DateRangePresets.toFrappeDate(_range.to)}',
                                  style: const TextStyle(
                                    color: AppColors.navy,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: AppColors.slate,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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

class _CollectionIconTile extends StatelessWidget {
  const _CollectionIconTile({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.softGreen,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: selected ? 0 : 0.18),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.white : AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
