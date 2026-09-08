import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/sales_invoice.dart';
import '../../../models/sales_workspace.dart';
import '../../../state/selling/collection_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/date_range_presets.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import 'collection_widgets.dart';
import '../shared/sales_ui.dart';

enum CollectionAgingDateBasis { invoiceDate, tukarFakturDate }

enum _CollectionFullListMode { invoices, payments }

class _CollectionSurfaceCard extends StatelessWidget {
  const _CollectionSurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: SalesUi.cardDecoration(),
      child: child,
    );
  }
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

class ArAgingTab extends StatefulWidget {
  const ArAgingTab({
    super.key,
    required this.range,
    required this.dateBasis,
    required this.applyDateFilter,
  });

  final DateRangePreset range;
  final CollectionAgingDateBasis dateBasis;
  final bool applyDateFilter;

  @override
  State<ArAgingTab> createState() => _ArAgingTabState();
}

class _ArAgingTabState extends State<ArAgingTab>
    with AutomaticKeepAliveClientMixin {
  List<SalesInvoice> outstanding = const [];
  List<CollectionPayment> payments = const [];
  Map<String, List<SalesInvoicePaymentAllocation>> invoicePaymentAllocations =
      const {};
  Future<void>? _loadInFlight;
  String? _loadInFlightKey;
  int _loadVersion = 0;
  bool loading = true;
  String? agingError;
  String? paymentError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant ArAgingTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.range.from != widget.range.from ||
        oldWidget.range.to != widget.range.to) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _load() {
    final key = _loadKey;
    final inFlight = _loadInFlight;
    if (inFlight != null && _loadInFlightKey == key) return inFlight;
    final request = _loadInternal();
    _loadInFlightKey = key;
    _loadInFlight = request;
    return request.whenComplete(() {
      if (identical(_loadInFlight, request)) {
        _loadInFlight = null;
        _loadInFlightKey = null;
      }
    });
  }

  String get _loadKey => [
    widget.range.from.toIso8601String(),
    widget.range.to.toIso8601String(),
    widget.dateBasis.name,
    widget.applyDateFilter,
  ].join('|');

  Future<void> _loadInternal() async {
    final version = ++_loadVersion;
    setState(() {
      loading = true;
      agingError = null;
      paymentError = null;
    });
    final state = context.read<CollectionState>();
    await Future.wait([
      () async {
        try {
          final nextOutstanding = await state
              .fetchCollectionOutstandingInvoices();
          final nextAllocations = await state
              .fetchSalesInvoicePaymentAllocations(
                nextOutstanding.map((invoice) => invoice.id),
              );
          if (version == _loadVersion) {
            outstanding = nextOutstanding;
            invoicePaymentAllocations = nextAllocations;
          }
        } catch (error) {
          if (version == _loadVersion) agingError = error.toString();
        }
      }(),
      () async {
        try {
          final nextPayments = await state.fetchCollectionPayments(
            from: widget.range.from,
            to: widget.range.to,
          );
          if (version == _loadVersion) payments = nextPayments;
        } catch (error) {
          if (version == _loadVersion) paymentError = error.toString();
        }
      }(),
    ]);
    if (mounted && version == _loadVersion) setState(() => loading = false);
  }

  List<SalesInvoice> get filteredOutstanding {
    if (!widget.applyDateFilter) return outstanding;
    return outstanding.where((invoice) {
      final rawDate = widget.dateBasis == CollectionAgingDateBasis.invoiceDate
          ? invoice.date
          : invoice.tukarFakturDate;
      final parsed = DateTime.tryParse(rawDate);
      if (parsed == null) return false;
      final date = DateTime(parsed.year, parsed.month, parsed.day);
      final from = DateTime(
        widget.range.from.year,
        widget.range.from.month,
        widget.range.from.day,
      );
      final to = DateTime(
        widget.range.to.year,
        widget.range.to.month,
        widget.range.to.day,
      );
      return !date.isBefore(from) && !date.isAfter(to);
    }).toList();
  }

  Map<String, double> _agingBucketsFor(List<SalesInvoice> invoices) {
    final buckets = <String, double>{
      'Sudah terlambat': 0,
      'Jatuh tempo hari ini': 0,
      'H-1': 0,
      'H-2 sampai H-7': 0,
      'H-8 sampai H-14': 0,
      'H-15 sampai H-25': 0,
      'H-26 sampai H-30': 0,
    };
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final invoice in invoices) {
      final due = DateTime.tryParse(invoice.collectionDueDate);
      if (due == null) continue;
      final days = due.difference(today).inDays;
      final key = days < 0
          ? 'Sudah terlambat'
          : days == 0
          ? 'Jatuh tempo hari ini'
          : days == 1
          ? 'H-1'
          : days <= 7
          ? 'H-2 sampai H-7'
          : days <= 14
          ? 'H-8 sampai H-14'
          : days <= 25
          ? 'H-15 sampai H-25'
          : 'H-26 sampai H-30';
      buckets[key] = buckets[key]! + invoice.outstandingAmount;
    }
    return buckets;
  }

  double _totalOverdueFor(List<SalesInvoice> invoices) {
    final today = DateTime.now();
    return invoices.fold(0, (sum, invoice) {
      final due = DateTime.tryParse(invoice.collectionDueDate);
      return due != null && due.isBefore(today)
          ? sum + invoice.outstandingAmount
          : sum;
    });
  }

  double get totalPayments =>
      payments.fold(0, (sum, payment) => sum + payment.amount);

  void _openFullList(_CollectionFullListMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CollectionFullListScreen(
          mode: mode,
          invoices: outstanding,
          payments: payments,
          allocations: invoicePaymentAllocations,
          initialRange: widget.range,
          initialDateBasis: widget.dateBasis,
          initialApplyDateFilter: widget.applyDateFilter,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final invoices = filteredOutstanding;
    final buckets = _agingBucketsFor(invoices);
    final totalOutstanding = invoices.fold<double>(
      0,
      (sum, invoice) => sum + invoice.outstandingAmount,
    );
    final totalOverdue = _totalOverdueFor(invoices);
    final previewInvoices = invoices.take(10).toList(growable: false);
    final previewPayments = payments.take(10).toList(growable: false);
    final pagePadding = SalesUi.screenPaddingOf(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              pagePadding.left,
              16,
              pagePadding.right,
              0,
            ),
            sliver: SliverList.list(
              children: [
                const CollectionSectionHeader(
                  title: 'Ringkasan Collection',
                  subtitle: 'Pantau piutang dan pembayaran dengan cepat',
                  icon: Icons.insights_rounded,
                ),
                const SizedBox(height: 10),
                CollectionMetricCard(
                  label: 'Total Piutang',
                  value: 'Rp ${formatErpCurrency(totalOutstanding)}',
                  icon: Icons.account_balance_wallet_rounded,
                ),
                const SizedBox(height: 10),
                CollectionMetricCard(
                  label: 'Sudah Overdue',
                  value: 'Rp ${formatErpCurrency(totalOverdue)}',
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.warning,
                ),
                const SizedBox(height: 10),
                CollectionMetricCard(
                  label: 'Pembayaran pada periode terpilih',
                  value: 'Rp ${formatErpCurrency(totalPayments)}',
                  icon: Icons.payments_rounded,
                  color: AppColors.success,
                ),
                const SizedBox(height: 14),
                if (loading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (agingError != null) ...[
                  const SizedBox(height: 12),
                  ErpErrorBox(message: agingError!),
                ],
                const SizedBox(height: 24),
                const CollectionSectionHeader(
                  title: 'Jadwal Penagihan',
                  subtitle: 'Due date SI ditambah durasi term tukar faktur',
                  icon: Icons.timelapse_rounded,
                ),
                ...buckets.entries.indexed.map((indexed) {
                  final index = indexed.$1;
                  final entry = indexed.$2;
                  final colors = [
                    AppColors.danger,
                    AppColors.warning,
                    const Color(0xFFEA580C),
                    const Color(0xFFEA580C),
                    AppColors.primary,
                    AppColors.primaryLight,
                    AppColors.success,
                  ];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CollectionSurfaceCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: colors[index].withValues(
                              alpha: 0.1,
                            ),
                            foregroundColor: colors[index],
                            child: Text('${index + 1}'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Rp ${formatErpCurrency(entry.value)}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: colors[index],
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 18),
                const CollectionSectionHeader(
                  title: 'Invoice Belum Dibayar',
                  subtitle:
                      'Menampilkan tgl SI, tgl TT, dan jatuh tempo dari TT',
                  icon: Icons.receipt_long_rounded,
                ),
                if (!loading && agingError == null && invoices.isEmpty)
                  const ErpEmptyState(
                    title: 'Tidak ada invoice pada filter ini',
                  ),
              ],
            ),
          ),
          if (loading || agingError != null || invoices.isEmpty)
            const SliverToBoxAdapter(child: SizedBox.shrink())
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pagePadding.left),
              sliver: SliverList.builder(
                itemCount: previewInvoices.length,
                itemBuilder: (context, index) {
                  final invoice = previewInvoices[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CollectionInvoiceCard(
                      invoice: invoice,
                      allocations:
                          invoicePaymentAllocations[invoice.id] ?? const [],
                    ),
                  );
                },
              ),
            ),
          if (!loading && agingError == null && invoices.length > 10)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                pagePadding.left,
                4,
                pagePadding.right,
                12,
              ),
              sliver: SliverToBoxAdapter(
                child: _CollectionMoreButton(
                  label: 'Lihat semua invoice',
                  count: invoices.length,
                  onPressed: () =>
                      _openFullList(_CollectionFullListMode.invoices),
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              pagePadding.left,
              10,
              pagePadding.right,
              0,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate.fixed([
                const SizedBox(height: 8),
                CollectionSectionHeader(
                  title: 'Histori Pembayaran',
                  subtitle: 'Pembayaran customer pada periode terpilih',
                  icon: Icons.history_rounded,
                ),
                if (paymentError != null)
                  ErpErrorBox(message: paymentError!)
                else if (!loading && payments.isEmpty)
                  const ErpEmptyState(
                    title: 'Belum ada pembayaran pada periode ini',
                  ),
              ]),
            ),
          ),
          if (paymentError != null || payments.isEmpty)
            const SliverToBoxAdapter(child: SizedBox.shrink())
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pagePadding.left),
              sliver: SliverList.builder(
                itemCount: previewPayments.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CollectionPaymentCard(
                      payment: previewPayments[index],
                    ),
                  );
                },
              ),
            ),
          if (!loading && paymentError == null && payments.length > 10)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                pagePadding.left,
                4,
                pagePadding.right,
                12,
              ),
              sliver: SliverToBoxAdapter(
                child: _CollectionMoreButton(
                  label: 'Lihat semua histori pembayaran',
                  count: payments.length,
                  onPressed: () =>
                      _openFullList(_CollectionFullListMode.payments),
                ),
              ),
            ),
          if (agingError != null || paymentError != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                pagePadding.left,
                12,
                pagePadding.right,
                90,
              ),
              sliver: SliverToBoxAdapter(
                child: OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Muat ulang data'),
                ),
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }
}

class _CollectionMoreButton extends StatelessWidget {
  const _CollectionMoreButton({
    required this.label,
    required this.count,
    required this.onPressed,
  });

  final String label;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.open_in_new_rounded, size: 18),
      label: Text('$label ($count)'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.28)),
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _CollectionFullListScreen extends StatefulWidget {
  const _CollectionFullListScreen({
    required this.mode,
    required this.invoices,
    required this.payments,
    required this.allocations,
    required this.initialRange,
    required this.initialDateBasis,
    required this.initialApplyDateFilter,
  });

  final _CollectionFullListMode mode;
  final List<SalesInvoice> invoices;
  final List<CollectionPayment> payments;
  final Map<String, List<SalesInvoicePaymentAllocation>> allocations;
  final DateRangePreset initialRange;
  final CollectionAgingDateBasis initialDateBasis;
  final bool initialApplyDateFilter;

  @override
  State<_CollectionFullListScreen> createState() =>
      _CollectionFullListScreenState();
}

class _CollectionFullListScreenState extends State<_CollectionFullListScreen> {
  late DateRangePreset _range;
  late CollectionAgingDateBasis _dateBasis;
  late bool _applyDateFilter;
  late List<CollectionPayment> _payments;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _loadingPayments = false;
  String? _paymentError;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
    _dateBasis = widget.initialDateBasis;
    _applyDateFilter = widget.initialApplyDateFilter;
    _payments = widget.payments;
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    if (!_applyDateFilter) setState(() => _applyDateFilter = true);
    final today = DateTime.now();
    final lastDate = _range.to.isAfter(today) ? _range.to : today;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: lastDate,
      initialDateRange: DateTimeRange(start: _range.from, end: _range.to),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _range = DateRangePreset(from: picked.start, to: picked.end);
      _applyDateFilter = true;
    });
    if (widget.mode == _CollectionFullListMode.payments) {
      await _reloadPayments();
    }
  }

  Future<void> _reloadPayments() async {
    setState(() {
      _loadingPayments = true;
      _paymentError = null;
    });
    try {
      final rows = await context
          .read<CollectionState>()
          .fetchCollectionPayments(from: _range.from, to: _range.to);
      if (!mounted) return;
      setState(() => _payments = rows);
    } catch (error) {
      if (mounted) setState(() => _paymentError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingPayments = false);
    }
  }

  List<SalesInvoice> get _filteredInvoices {
    var rows = widget.invoices;
    if (_applyDateFilter) {
      rows = rows
          .where((invoice) {
            final rawDate = _dateBasis == CollectionAgingDateBasis.invoiceDate
                ? invoice.date
                : invoice.tukarFakturDate;
            final parsed = DateTime.tryParse(rawDate);
            if (parsed == null) return false;
            final date = DateTime(parsed.year, parsed.month, parsed.day);
            final from = DateTime(
              _range.from.year,
              _range.from.month,
              _range.from.day,
            );
            final to = DateTime(_range.to.year, _range.to.month, _range.to.day);
            return !date.isBefore(from) && !date.isAfter(to);
          })
          .toList(growable: false);
    }
    if (_query.isEmpty) return rows;
    return rows
        .where((invoice) {
          return [
            invoice.customer,
            invoice.id,
            invoice.date,
            invoice.tukarFaktur,
            invoice.tukarFakturDate,
            invoice.collectionDueDate,
            formatErpCurrency(invoice.outstandingAmount),
          ].any((value) => value.toLowerCase().contains(_query));
        })
        .toList(growable: false);
  }

  List<CollectionPayment> get _filteredPayments {
    var rows = _payments;
    if (_query.isEmpty) return rows;
    return rows
        .where((payment) {
          final invoiceRefs = payment.salesInvoiceReferences
              .map((reference) => reference.documentName)
              .join(' ');
          return [
            payment.customer,
            payment.customerName,
            payment.id,
            payment.postingDate,
            payment.referenceNo,
            payment.remarks,
            invoiceRefs,
            formatErpCurrency(payment.amount),
          ].any((value) => value.toLowerCase().contains(_query));
        })
        .toList(growable: false);
  }

  String get _title => widget.mode == _CollectionFullListMode.invoices
      ? 'Semua Invoice'
      : 'Semua Histori Pembayaran';

  @override
  Widget build(BuildContext context) {
    final isInvoiceMode = widget.mode == _CollectionFullListMode.invoices;
    final invoices = _filteredInvoices;
    final payments = _filteredPayments;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.navy,
        elevation: 0,
        title: Text(
          _title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: isInvoiceMode ? () async {} : _reloadPayments,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: SalesUi.screenPaddingOf(context).copyWith(bottom: 28),
          children: [
            _CollectionFullListFilterPanel(
              searchController: _searchController,
              range: _range,
              dateBasis: _dateBasis,
              showDateBasis: isInvoiceMode,
              applyDateFilter: _applyDateFilter,
              onApplyDateFilterChanged: (value) =>
                  setState(() => _applyDateFilter = value),
              onDateBasisChanged: (value) => setState(() {
                _dateBasis = value;
                _applyDateFilter = true;
              }),
              onPickRange: _pickRange,
            ),
            const SizedBox(height: 14),
            CollectionSectionHeader(
              title: isInvoiceMode
                  ? 'Invoice Belum Dibayar'
                  : 'Histori Pembayaran',
              subtitle: isInvoiceMode
                  ? '${invoices.length} invoice sesuai filter'
                  : '${payments.length} pembayaran sesuai filter',
              icon: isInvoiceMode
                  ? Icons.receipt_long_rounded
                  : Icons.history_rounded,
            ),
            if (_loadingPayments) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if (_paymentError != null) ...[
              const SizedBox(height: 10),
              ErpErrorBox(message: _paymentError!),
            ],
            if (isInvoiceMode && invoices.isEmpty)
              const ErpEmptyState(title: 'Tidak ada invoice sesuai filter')
            else if (!isInvoiceMode && !_loadingPayments && payments.isEmpty)
              const ErpEmptyState(title: 'Tidak ada pembayaran sesuai filter')
            else if (isInvoiceMode)
              ...invoices.map(
                (invoice) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CollectionInvoiceCard(
                    invoice: invoice,
                    allocations: widget.allocations[invoice.id] ?? const [],
                  ),
                ),
              )
            else
              ...payments.map(
                (payment) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CollectionPaymentCard(payment: payment),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CollectionFullListFilterPanel extends StatelessWidget {
  const _CollectionFullListFilterPanel({
    required this.searchController,
    required this.range,
    required this.dateBasis,
    required this.showDateBasis,
    required this.applyDateFilter,
    required this.onApplyDateFilterChanged,
    required this.onDateBasisChanged,
    required this.onPickRange,
  });

  final TextEditingController searchController;
  final DateRangePreset range;
  final CollectionAgingDateBasis dateBasis;
  final bool showDateBasis;
  final bool applyDateFilter;
  final ValueChanged<bool> onApplyDateFilterChanged;
  final ValueChanged<CollectionAgingDateBasis> onDateBasisChanged;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
    return _CollectionSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          TextField(
            controller: searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: showDateBasis
                  ? 'Cari customer, invoice, TT'
                  : 'Cari customer, payment, invoice',
              filled: true,
              fillColor: AppColors.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CollectionDateFilterButton(
                  range: range,
                  onTap: onPickRange,
                ),
              ),
              const SizedBox(width: 8),
              Switch.adaptive(
                value: applyDateFilter,
                activeThumbColor: AppColors.white,
                activeTrackColor: AppColors.primary,
                inactiveThumbColor: AppColors.white,
                inactiveTrackColor: AppColors.border,
                onChanged: onApplyDateFilterChanged,
              ),
            ],
          ),
          if (showDateBasis) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _FilterChipButton(
                    label: 'Tanggal SI',
                    selected: dateBasis == CollectionAgingDateBasis.invoiceDate,
                    onTap: () => onDateBasisChanged(
                      CollectionAgingDateBasis.invoiceDate,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FilterChipButton(
                    label: 'Tanggal TT',
                    selected:
                        dateBasis == CollectionAgingDateBasis.tukarFakturDate,
                    onTap: () => onDateBasisChanged(
                      CollectionAgingDateBasis.tukarFakturDate,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CollectionDateFilterButton extends StatelessWidget {
  const _CollectionDateFilterButton({required this.range, required this.onTap});

  final DateRangePreset range;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
            borderRadius: BorderRadius.circular(18),
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
                  '${DateRangePresets.toFrappeDate(range.from)} s/d '
                  '${DateRangePresets.toFrappeDate(range.to)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 12,
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

class _CollectionPaymentCard extends StatelessWidget {
  const _CollectionPaymentCard({required this.payment});

  final CollectionPayment payment;

  @override
  Widget build(BuildContext context) {
    final references = payment.salesInvoiceReferences.toList();
    final allocated = payment.allocatedToSalesInvoices;
    final unallocated = payment.unallocatedAmount;
    final isAllocated = payment.isAllocatedToSalesInvoice;
    return _CollectionSurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CollectionIconTile(
            icon: isAllocated
                ? Icons.payments_outlined
                : Icons.priority_high_rounded,
            color: isAllocated ? AppColors.primary : AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.customerName,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${payment.postingDate} | ${payment.id}',
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    CollectionStatusChip(
                      label: isAllocated ? 'Teralokasi SI' : 'Belum alokasi SI',
                      color: isAllocated
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    if (allocated > 0)
                      CollectionStatusChip(
                        label: 'Alokasi Rp ${formatErpCurrency(allocated)}',
                        color: AppColors.primary,
                      ),
                    if (unallocated > 0)
                      CollectionStatusChip(
                        label:
                            'Belum alokasi Rp ${formatErpCurrency(unallocated)}',
                        color: AppColors.warning,
                      ),
                  ],
                ),
                if (references.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Invoice: ${references.map((reference) => '${reference.documentName} (Rp ${formatErpCurrency(reference.allocatedAmount)})').join(', ')}',
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Rp ${formatErpCurrency(payment.amount)}',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.success,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionInvoiceCard extends StatelessWidget {
  const _CollectionInvoiceCard({
    required this.invoice,
    required this.allocations,
  });

  final SalesInvoice invoice;
  final List<SalesInvoicePaymentAllocation> allocations;

  @override
  Widget build(BuildContext context) {
    final dueDate = invoice.collectionDueDate;
    final hasTukarFaktur =
        invoice.tukarFakturDate.trim().isNotEmpty ||
        invoice.tukarFaktur.trim().isNotEmpty;
    final allocated = allocations.fold<double>(
      0,
      (sum, allocation) => sum + allocation.allocatedAmount,
    );
    return _CollectionSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _CollectionIconTile(
                icon: Icons.description_outlined,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.customer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      invoice.id,
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'Rp ${formatErpCurrency(invoice.outstandingAmount)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          _InvoiceDateLine(label: 'Tgl SI', value: invoice.date),
          _InvoiceDateLine(
            label: 'Tgl TT',
            value: hasTukarFaktur ? invoice.tukarFakturDate : '-',
          ),
          _InvoiceDateLine(
            label: 'Jatuh Tempo Collection',
            value: dueDate.isEmpty ? '-' : dueDate,
          ),
          if (invoice.tukarFaktur.trim().isNotEmpty)
            _InvoiceDateLine(label: 'No TT', value: invoice.tukarFaktur),
          if (allocated > 0) ...[
            const Divider(height: 18),
            _InvoiceDateLine(
              label: 'Terbayar',
              value: 'Rp ${formatErpCurrency(allocated)}',
            ),
            ...allocations
                .take(3)
                .map(
                  (allocation) => _InvoiceDateLine(
                    label: allocation.postingDate.isEmpty
                        ? 'Payment'
                        : allocation.postingDate,
                    value:
                        '${allocation.paymentEntry} | Rp ${formatErpCurrency(allocation.allocatedAmount)}',
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _InvoiceDateLine extends StatelessWidget {
  const _InvoiceDateLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
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
              value.trim().isEmpty ? '-' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
