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

class OutstandingInvoiceTab extends StatefulWidget {
  const OutstandingInvoiceTab({
    super.key,
    required this.range,
    required this.dateBasis,
    required this.applyDateFilter,
  });

  final DateRangePreset range;
  final CollectionAgingDateBasis dateBasis;
  final bool applyDateFilter;

  @override
  State<OutstandingInvoiceTab> createState() => _OutstandingInvoiceTabState();
}

class _OutstandingInvoiceTabState extends State<OutstandingInvoiceTab>
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

  List<_CustomerOutstanding> get summaries {
    final grouped = <String, List<SalesInvoice>>{};
    for (final invoice in filteredInvoices) {
      grouped.putIfAbsent(invoice.customer, () => []).add(invoice);
    }
    final result =
        grouped.entries
            .map((entry) => _CustomerOutstanding(entry.key, entry.value))
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));
    return result;
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
    final rows = summaries;
    final overdue = rows.where((row) => row.overdueTotal > 0).toList()
      ..sort((a, b) => b.overdueTotal.compareTo(a.overdueTotal));
    final total = rows.fold<double>(0, (sum, row) => sum + row.total);
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
                  title: 'Piutang Customer',
                  subtitle: 'Lihat customer yang perlu segera ditagih',
                  icon: Icons.receipt_long_rounded,
                ),
                CollectionMetricCard(
                  label: 'Total Piutang',
                  value: 'Rp ${formatErpCurrency(total)}',
                  icon: Icons.account_balance_wallet_rounded,
                ),
                const SizedBox(height: 10),
                CollectionMetricCard(
                  label: 'Customer Overdue',
                  value: '${overdue.length}',
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.warning,
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
                    label: const Text('Coba lagi'),
                  ),
                ],
                const SizedBox(height: 24),
                const CollectionSectionHeader(
                  title: 'Prioritas Penagihan',
                  subtitle: 'Urut dari nilai overdue terbesar',
                  icon: Icons.priority_high_rounded,
                ),
              ],
            ),
          ),
          if (!loading && error == null && overdue.isEmpty)
            SliverPadding(
              padding: SalesUi.screenPaddingOf(context).copyWith(top: 0),
              sliver: const SliverToBoxAdapter(
                child: ErpEmptyState(title: 'Tidak ada customer overdue'),
              ),
            )
          else
            SliverPadding(
              padding: SalesUi.screenPaddingOf(context).copyWith(top: 0),
              sliver: SliverList.builder(
                itemCount: overdue.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PriorityCollectionCard(row: overdue[index]),
                ),
              ),
            ),
          SliverPadding(
            padding: SalesUi.screenPaddingOf(
              context,
            ).copyWith(top: 12, bottom: 0),
            sliver: SliverList.list(
              children: const [
                CollectionSectionHeader(
                  title: 'Semua Piutang',
                  subtitle: 'Tekan customer untuk melihat rincian invoice',
                  icon: Icons.people_alt_rounded,
                ),
              ],
            ),
          ),
          if (!loading && error == null && rows.isEmpty)
            SliverPadding(
              padding: SalesUi.screenPaddingOf(context).copyWith(top: 0),
              sliver: const SliverToBoxAdapter(
                child: ErpEmptyState(title: 'Tidak ada outstanding piutang'),
              ),
            )
          else
            SliverPadding(
              padding: SalesUi.screenPaddingOf(context).copyWith(top: 0),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CustomerOutstandingCard(row: rows[index]),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 84)),
        ],
      ),
    );
  }
}

class _PriorityCollectionCard extends StatelessWidget {
  const _PriorityCollectionCard({required this.row});

  final _CustomerOutstanding row;

  @override
  Widget build(BuildContext context) {
    final overdueInvoices = row.overdueInvoices.toList()
      ..sort((a, b) => a.collectionDueDate.compareTo(b.collectionDueDate));
    return _CustomerCollectionExpansionCard(
      row: row,
      invoices: overdueInvoices,
      icon: Icons.notifications_active_outlined,
      color: AppColors.warning,
      amount: row.overdueTotal,
      amountColor: AppColors.danger,
      titleMaxLines: 2,
      subtitle: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          CollectionStatusChip(
            label: '${row.overdueCount} invoice',
            color: AppColors.warning,
          ),
          CollectionStatusChip(
            label: 'Tertua ${row.oldestOverdueDays} hari',
            color: AppColors.danger,
          ),
        ],
      ),
    );
  }
}

class _CustomerCollectionExpansionCard extends StatelessWidget {
  const _CustomerCollectionExpansionCard({
    required this.row,
    required this.invoices,
    required this.icon,
    required this.color,
    required this.amount,
    required this.amountColor,
    required this.subtitle,
    this.titleMaxLines = 1,
  });

  final _CustomerOutstanding row;
  final List<SalesInvoice> invoices;
  final IconData icon;
  final Color color;
  final double amount;
  final Color amountColor;
  final Widget subtitle;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(15, 0, 15, 14),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          title: Text(
            row.customer,
            maxLines: titleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: subtitle,
          ),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 128),
            child: Text(
              'Rp ${formatErpCurrency(amount)}',
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: amountColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          children: invoices
              .map(
                (invoice) => Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        color: AppColors.slate,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              invoice.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Jatuh tempo ${invoice.collectionDueDate}',
                              style: const TextStyle(
                                color: AppColors.slate,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 112),
                        child: Text(
                          'Rp ${formatErpCurrency(invoice.outstandingAmount)}',
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _CustomerOutstandingCard extends StatelessWidget {
  const _CustomerOutstandingCard({required this.row});

  final _CustomerOutstanding row;

  @override
  Widget build(BuildContext context) {
    return _CustomerCollectionExpansionCard(
      row: row,
      invoices: row.invoices,
      icon: Icons.storefront_outlined,
      color: AppColors.primary,
      amount: row.total,
      amountColor: AppColors.primary,
      subtitle: Text(
        '${row.invoices.length} invoice outstanding',
        style: const TextStyle(
          color: AppColors.slate,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CustomerOutstanding {
  final String customer;
  final List<SalesInvoice> invoices;

  const _CustomerOutstanding(this.customer, this.invoices);

  double get total =>
      invoices.fold(0, (sum, invoice) => sum + invoice.outstandingAmount);

  Iterable<SalesInvoice> get overdueInvoices {
    final today = DateTime.now();
    return invoices.where((invoice) {
      final due = DateTime.tryParse(invoice.dueDate);
      return due != null &&
          due.isBefore(DateTime(today.year, today.month, today.day));
    });
  }

  int get overdueCount => overdueInvoices.length;

  double get overdueTotal => overdueInvoices.fold(
    0,
    (sum, invoice) => sum + invoice.outstandingAmount,
  );

  int get oldestOverdueDays {
    final today = DateTime.now();
    var oldest = 0;
    for (final invoice in overdueInvoices) {
      final due = DateTime.tryParse(invoice.dueDate);
      if (due == null) continue;
      final days = today.difference(due).inDays;
      if (days > oldest) oldest = days;
    }
    return oldest;
  }
}
