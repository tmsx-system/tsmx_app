import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/sales_invoice.dart';
import '../../../state/selling/collection_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/date_range_presets.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import 'ar_aging_tab.dart';
import 'collection_widgets.dart';
import '../shared/sales_ui.dart';

class CustomerPaymentScheduleTab extends StatefulWidget {
  const CustomerPaymentScheduleTab({
    super.key,
    required this.range,
    required this.dateBasis,
    required this.applyDateFilter,
  });

  final DateRangePreset range;
  final CollectionAgingDateBasis dateBasis;
  final bool applyDateFilter;

  @override
  State<CustomerPaymentScheduleTab> createState() =>
      _CustomerPaymentScheduleTabState();
}

class _CustomerPaymentScheduleTabState extends State<CustomerPaymentScheduleTab>
    with AutomaticKeepAliveClientMixin {
  List<SalesInvoice> invoices = const [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      invoices = await context
          .read<CollectionState>()
          .fetchCollectionOutstandingInvoices();
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  bool get wantKeepAlive => true;

  bool _isDue(SalesInvoice row) {
    final date = DateTime.tryParse(row.collectionDueDate);
    if (date == null) return false;
    final today = DateTime.now();
    return !date.isAfter(DateTime(today.year, today.month, today.day));
  }

  List<SalesInvoice> get filteredInvoices {
    if (!widget.applyDateFilter) return invoices;
    return invoices.where((invoice) {
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final sorted = filteredInvoices.toList()
      ..sort((a, b) => a.collectionDueDate.compareTo(b.collectionDueDate));
    final due = sorted.where(_isDue).length;
    final total = sorted.fold<double>(
      0,
      (sum, row) => sum + row.outstandingAmount,
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: SalesUi.screenPaddingOf(context),
            sliver: SliverList.list(
              children: [
                const CollectionSectionHeader(
                  title: 'Janji Bayar Customer',
                  subtitle: 'Jadwal bayar mengikuti due date SI dan term TT',
                  icon: Icons.event_available_rounded,
                ),
                Row(
                  children: [
                    Expanded(
                      child: CollectionMetricCard(
                        label: 'Total Janji',
                        value: '${sorted.length}',
                        icon: Icons.event_note_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CollectionMetricCard(
                        label: 'Jatuh Tempo',
                        value: '$due',
                        icon: Icons.notification_important_outlined,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CollectionMetricCard(
                  label: 'Total Nominal Janji Bayar',
                  value: 'Rp ${formatErpCurrency(total)}',
                  icon: Icons.payments_outlined,
                  color: AppColors.success,
                ),
                if (loading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  ErpErrorBox(message: error!),
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Muat ulang'),
                  ),
                ],
                const SizedBox(height: 24),
                const CollectionSectionHeader(
                  title: 'Daftar Janji Bayar',
                  subtitle: 'Urut dari tanggal jatuh tempo terdekat',
                  icon: Icons.list_alt_rounded,
                ),
              ],
            ),
          ),
          if (!loading && error == null && sorted.isEmpty)
            SliverPadding(
              padding: SalesUi.screenPaddingOf(context).copyWith(top: 0),
              sliver: const SliverToBoxAdapter(
                child: ErpEmptyState(title: 'Belum ada janji bayar'),
              ),
            )
          else
            SliverPadding(
              padding: SalesUi.screenPaddingOf(context).copyWith(top: 0),
              sliver: SliverList.builder(
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  final row = sorted[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PaymentScheduleCard(row: row, due: _isDue(row)),
                  );
                },
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 84)),
        ],
      ),
    );
  }
}

class _PaymentScheduleCard extends StatelessWidget {
  const _PaymentScheduleCard({required this.row, required this.due});

  final SalesInvoice row;
  final bool due;

  @override
  Widget build(BuildContext context) {
    final color = due ? AppColors.warning : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              due
                  ? Icons.notification_important_outlined
                  : Icons.event_available_outlined,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.customer,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  row.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    CollectionStatusChip(
                      label: due ? 'Jatuh Tempo' : 'Terjadwal',
                      color: color,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        row.collectionDueDate,
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
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Rp ${formatErpCurrency(row.outstandingAmount)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
