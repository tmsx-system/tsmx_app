import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/purchase_invoice.dart';
import '../../../../state/purchasing/purchase_invoice_state.dart';
import '../../../../state/purchasing/purchasing_summary_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_doc_utils.dart';
import '../../../utils/erp_format.dart';
import '../../../utils/frappe_status.dart';
import '../../../widgets/erp/document_trend_card.dart';
import '../../../widgets/erp/erp_document_card.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/erp/erp_status_chip_bar.dart';
import '../../../widgets/erp/erp_workflow_helper.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/buying_document_detail_sheet.dart';
import '../shared/purchase_ui.dart';

class PurchaseInvoicePanel extends StatefulWidget {
  const PurchaseInvoicePanel({super.key});

  @override
  State<PurchaseInvoicePanel> createState() => _PurchaseInvoicePanelState();
}

class _PurchaseInvoicePanelState extends State<PurchaseInvoicePanel> {
  String _search = '';
  InvoiceStatusKey? _statusFilter;
  Timer? _searchDebounce;

  static final _chips = <ErpStatusChip<InvoiceStatusKey?>>[
    const ErpStatusChip(label: 'Semua', value: null),
    const ErpStatusChip(label: 'Draft', value: InvoiceStatusKey.draft),
    const ErpStatusChip(label: 'Unpaid', value: InvoiceStatusKey.unpaid),
    const ErpStatusChip(
      label: 'Partly Paid',
      value: InvoiceStatusKey.partlyPaid,
    ),
    const ErpStatusChip(label: 'Paid', value: InvoiceStatusKey.paid),
    const ErpStatusChip(label: 'Overdue', value: InvoiceStatusKey.overdue),
    const ErpStatusChip(label: 'Return', value: InvoiceStatusKey.returnDoc),
    const ErpStatusChip(
      label: 'Credit Note',
      value: InvoiceStatusKey.creditNoteIssued,
    ),
    const ErpStatusChip(label: 'Cancelled', value: InvoiceStatusKey.cancelled),
  ];

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  String? get _statusText => switch (_statusFilter) {
    InvoiceStatusKey.draft => 'Draft',
    InvoiceStatusKey.unpaid => 'Unpaid',
    InvoiceStatusKey.partlyPaid => 'Partly Paid',
    InvoiceStatusKey.paid => 'Paid',
    InvoiceStatusKey.overdue => 'Overdue',
    InvoiceStatusKey.returnDoc => 'Return',
    InvoiceStatusKey.creditNoteIssued => 'Credit Note Issued',
    InvoiceStatusKey.cancelled => 'Cancelled',
    _ => null,
  };

  void _searchChanged(String value) {
    setState(() => _search = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        context.read<PurchaseInvoiceState>().setPurchaseInvoiceQuery(
          search: value,
          status: _statusText,
        );
      }
    });
  }

  List<PurchaseInvoice> _filter(List<PurchaseInvoice> docs) {
    final q = _search.toLowerCase();
    return docs.where((d) {
      final matchSearch =
          q.isEmpty ||
          d.id.toLowerCase().contains(q) ||
          d.supplier.toLowerCase().contains(q);
      final matchStatus = _statusFilter == null || d.statusKey == _statusFilter;
      return matchSearch && matchStatus;
    }).toList();
  }

  Future<void> _openDetail(PurchaseInvoice doc) async {
    final purchasingState = context.read<PurchaseInvoiceState>();
    final detail = await purchasingState.loadPurchaseInvoiceDetail(doc.id);
    var workflowActions = <String>[];
    try {
      workflowActions = await purchasingState.fetchDocumentWorkflowActions(
        doctype: 'Purchase Invoice',
        name: detail.id,
      );
    } catch (_) {}
    if (!mounted) return;

    final canSubmit = isDocDraft(detail.docStatus);

    showBuyingDocumentDetailSheet(
      context: context,
      title: detail.id,
      subtitle: detail.supplier,
      statusText: detail.statusText,
      icon: Icons.receipt_long_rounded,
      metrics: [
        BuyingDetailMetric(
          label: 'Total Invoice',
          value: 'Rp ${formatErpCurrency(detail.value)}',
          icon: Icons.payments_outlined,
        ),
        BuyingDetailMetric(
          label: 'Belum Dibayar',
          value: 'Rp ${formatErpCurrency(detail.outstandingAmount)}',
          icon: Icons.account_balance_wallet_outlined,
        ),
        BuyingDetailMetric(
          label: 'Item',
          value: '${detail.items.length}',
          icon: Icons.inventory_2_outlined,
        ),
      ],
      infos: [
        BuyingDetailInfo(
          label: 'Status Dokumen',
          value: docStatusLabel(detail.docStatus),
        ),
        BuyingDetailInfo(label: 'Tanggal Posting', value: detail.date),
        BuyingDetailInfo(
          label: 'Jatuh Tempo',
          value: detail.dueDate.isEmpty ? '-' : detail.dueDate,
        ),
      ],
      items: detail.items
          .map(
            (i) => BuyingDetailItem(
              title: i.itemName,
              subtitle: i.itemCode,
              qty:
                  '${formatErpCurrency(i.qty)}${i.uom.isEmpty ? '' : ' ${i.uom}'}',
              rate: 'Rp ${formatErpCurrency(i.rate)}',
              amount: 'Rp ${formatErpCurrency(i.amount)}',
              note: i.warehouse,
            ),
          )
          .toList(),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InvoiceMonitoringCard(invoice: detail),
          const SizedBox(height: 12),
          ..._workflowButtons(
            doctype: 'Purchase Invoice',
            name: detail.id,
            actions: workflowActions,
          ),
          if (workflowActions.isEmpty && !canSubmit) ...[
            const _InvoiceApprovalInfoCard(),
            const SizedBox(height: 10),
          ],
          if (canSubmit)
            erpActionButton(
              label: 'Ajukan Purchase Invoice',
              icon: Icons.check_circle_outline_rounded,
              filled: true,
              onPressed: () => _submit(detail.id),
            ),
        ],
      ),
    );
  }

  Future<void> _submit(String id) async {
    if (!await confirmErpAction(
      context,
      title: 'Ajukan Purchase Invoice?',
      message: 'Ajukan $id ke ERPNext?',
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await runErpWorkflowAction(
      context,
      action: () => context.read<PurchaseInvoiceState>().submitDocument(
        'Purchase Invoice',
        id,
      ),
      successMessage: 'Purchase Invoice berhasil diajukan',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  List<Widget> _workflowButtons({
    required String doctype,
    required String name,
    required List<String> actions,
  }) {
    return actions.map((action) {
      final lower = action.toLowerCase();
      final needsReason =
          lower.contains('reject') ||
          lower.contains('tolak') ||
          lower.contains('decline') ||
          lower.contains('return');
      final isApprove =
          lower.contains('approve') ||
          lower.contains('submit') ||
          lower.contains('confirm');
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: erpActionButton(
          label: action,
          icon: needsReason
              ? Icons.cancel_outlined
              : isApprove
              ? Icons.verified_outlined
              : Icons.route_outlined,
          filled: isApprove && !needsReason,
          onPressed: () => _applyWorkflowAction(
            doctype: doctype,
            name: name,
            action: action,
            needsReason: needsReason,
          ),
        ),
      );
    }).toList();
  }

  Future<void> _applyWorkflowAction({
    required String doctype,
    required String name,
    required String action,
    required bool needsReason,
  }) async {
    var reason = '';
    if (needsReason) {
      reason = await _askReason(action) ?? '';
      if (reason.trim().isEmpty) return;
      if (!mounted) return;
    } else {
      final ok = await confirmErpAction(
        context,
        title: '$action $name?',
        message: 'Lanjutkan action "$action" untuk $name?',
      );
      if (!ok || !mounted) return;
    }

    final ok = await runErpWorkflowAction(
      context,
      action: () => context.read<PurchaseInvoiceState>().applyDocumentWorkflow(
        doctype: doctype,
        name: name,
        action: action,
        reason: reason,
      ),
      successMessage: '$action berhasil',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  Future<String?> _askReason(String action) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action - alasan wajib'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Alasan',
            hintText: 'Tulis alasan agar tercatat di ERPNext',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final purchasingState = context.watch<PurchaseInvoiceState>();
    final summaryState = context.watch<PurchasingSummaryState>();
    final filtered = _filter(purchasingState.purchaseInvoices);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DocumentTrendCard(
          title: 'Purchase Invoice',
          emptyMessage:
              'Belum ada nilai Purchase Invoice dari Purchase Analytics pada periode ini.',
          points: summaryState.purchaseInvoiceTrendPoints,
          selectedYear: summaryState.buyingPeriodYear,
          selectedMonth: summaryState.buyingPeriodMonth,
          sourceLabel: 'Sumber: Purchase Analytics ERPNext',
        ),

        const SizedBox(height: 12),

        PurchaseSearchField(
          onChanged: _searchChanged,
          hintText: 'Cari invoice atau supplier...',
        ),

        if (purchasingState.purchaseInvoicesError != null) ...[
          const SizedBox(height: 10),
          ErpErrorBox(message: purchasingState.purchaseInvoicesError!),
        ],

        const SizedBox(height: 10),

        ErpStatusChipBar<InvoiceStatusKey?>(
          chips: _chips,
          selected: _statusFilter,
          onSelected: (v) {
            setState(() => _statusFilter = v);
            context.read<PurchaseInvoiceState>().setPurchaseInvoiceQuery(
              search: _search,
              status: _statusText,
            );
          },
        ),

        const SizedBox(height: 12),

        if (filtered.isEmpty && !purchasingState.isPurchaseInvoicesLoading)
          const ErpEmptyState(
            title: 'Belum ada Purchase Invoice',
            message:
                'Gunakan tombol Buat Invoice untuk membuat invoice supplier.',
          )
        else
          TmsxResponsiveCardGrid(
            children: filtered
                .map(
                  (d) => ErpDocumentCard(
                    id: d.id,
                    party: d.supplier,
                    statusText: d.statusText,
                    date: d.date,
                    value: d.value,
                    onTap: () => _openDetail(d),
                  ),
                )
                .toList(),
          ),
        if (purchasingState.hasMorePurchaseInvoices ||
            purchasingState.isMorePurchaseInvoicesLoading) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: purchasingState.isMorePurchaseInvoicesLoading
                  ? null
                  : () => context
                        .read<PurchaseInvoiceState>()
                        .loadMorePurchaseInvoices(),
              icon: purchasingState.isMorePurchaseInvoicesLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(
                purchasingState.isMorePurchaseInvoicesLoading
                    ? 'Memuat invoice...'
                    : 'Muat invoice lainnya',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InvoiceApprovalInfoCard extends StatelessWidget {
  const _InvoiceApprovalInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            color: AppColors.primary,
            size: 19,
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Action approval akan muncul otomatis jika Workflow ERPNext untuk Purchase Invoice sudah aktif dan role user sesuai.',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceMonitoringCard extends StatelessWidget {
  final PurchaseInvoice invoice;

  const _InvoiceMonitoringCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final dueDate = _parseDate(invoice.dueDate);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final dueOnly = dueDate == null
        ? null
        : DateTime(dueDate.year, dueDate.month, dueDate.day);
    final outstanding = invoice.outstandingAmount;
    final isPaid = outstanding <= 0;
    final isOverdue = !isPaid && dueOnly != null && dueOnly.isBefore(todayOnly);
    final days = dueOnly?.difference(todayOnly).inDays;
    final stateColor = isPaid
        ? AppColors.success
        : isOverdue
        ? AppColors.danger
        : AppColors.warning;
    final stateText = isPaid
        ? 'Lunas'
        : isOverdue
        ? 'Lewat tempo ${days?.abs() ?? 0} hari'
        : days == null
        ? 'Jatuh tempo belum tersedia'
        : days == 0
        ? 'Jatuh tempo hari ini'
        : 'Jatuh tempo $days hari lagi';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPaid
                      ? Icons.check_circle_outline_rounded
                      : Icons.account_balance_wallet_outlined,
                  color: stateColor,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monitoring Hutang Supplier',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Ringkasan pembayaran dan jatuh tempo invoice.',
                      style: TextStyle(color: AppColors.slate, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InvoiceInfoTile(
                label: 'Total Invoice',
                value: 'Rp ${formatErpCurrency(invoice.value)}',
              ),
              _InvoiceInfoTile(
                label: 'Belum Dibayar',
                value: 'Rp ${formatErpCurrency(outstanding)}',
                valueColor: isPaid ? AppColors.success : AppColors.danger,
              ),
              _InvoiceInfoTile(
                label: 'Jatuh Tempo',
                value: invoice.dueDate.isEmpty ? '-' : invoice.dueDate,
              ),
              _InvoiceInfoTile(
                label: 'Kondisi',
                value: stateText,
                valueColor: stateColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  DateTime? _parseDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;
    final parts = trimmed.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }
}

class _InvoiceInfoTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InvoiceInfoTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.navy,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
