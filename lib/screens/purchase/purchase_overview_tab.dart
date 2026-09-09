import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/purchase_order.dart';
import '../../state/purchasing/purchase_invoice_state.dart';
import '../../state/purchasing/purchase_order_state.dart';
import '../../state/purchasing/purchase_receipt_state.dart';
import '../../state/purchasing/purchasing_filter_state.dart';
import '../../state/purchasing/purchasing_summary_state.dart';
import '../../state/todo/todo_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/erp_format.dart';

class PurchaseOverviewTab extends StatefulWidget {
  final ValueChanged<int> onMenuSelected;
  final List<PurchaseOverviewAction> actions;

  const PurchaseOverviewTab({
    super.key,
    required this.onMenuSelected,
    this.actions = const [],
  });

  @override
  State<PurchaseOverviewTab> createState() => _PurchaseOverviewTabState();
}

class _PurchaseOverviewTabState extends State<PurchaseOverviewTab> {
  bool _didInitialLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialLoad) return;
    _didInitialLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final orderState = context.read<PurchaseOrderState>();
      final receiptState = context.read<PurchaseReceiptState>();
      final invoiceState = context.read<PurchaseInvoiceState>();
      final summaryState = context.read<PurchasingSummaryState>();
      Future.wait([
        summaryState.refreshBuyingSummaries(),
        if (orderState.purchaseOrders.isEmpty)
          orderState.refreshPurchaseOrders(),
        if (receiptState.purchaseReceipts.isEmpty)
          receiptState.refreshPurchaseReceipts(),
        if (invoiceState.purchaseInvoices.isEmpty)
          invoiceState.refreshPurchaseInvoices(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PurchasingFilterState>();
    final summaryState = context.watch<PurchasingSummaryState>();
    final orderState = context.watch<PurchaseOrderState>();
    final receiptState = context.watch<PurchaseReceiptState>();
    final invoiceState = context.watch<PurchaseInvoiceState>();
    final todoState = context.watch<TodoState>();
    final outstandingPo = orderState.purchaseOrders
        .where(
          (po) =>
              po.statusKey != PurchaseOrderStatusKey.completed &&
              po.statusKey != PurchaseOrderStatusKey.cancelled &&
              po.statusKey != PurchaseOrderStatusKey.closed,
        )
        .length;
    final outstandingDebt = invoiceState.purchaseInvoices.fold<double>(
      0,
      (sum, invoice) => sum + invoice.outstandingAmount,
    );
    final overdueInvoices = invoiceState.purchaseInvoices
        .where((invoice) => invoice.isOverdue)
        .length;
    final receiptIssues = receiptState.purchaseReceipts
        .where(
          (receipt) =>
              receipt.totalRejectedQty > 0 ||
              receipt.totalVarianceQty.abs() > 0.0001,
        )
        .length;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          summaryState.refreshBuyingSummaries(),
          orderState.refreshPurchaseOrders(),
          receiptState.refreshPurchaseReceipts(),
          invoiceState.refreshPurchaseInvoices(),
          state.refreshInventory(),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 104),
        children: [
          _PurchaseHeroCard(
            outstandingPo: outstandingPo,
            approvalCount: todoState.purchaseApprovalTodoCount,
            overdueInvoices: overdueInvoices,
            outstandingDebt: outstandingDebt,
          ),
          if (widget.actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            _PurchaseShortcutGrid(actions: widget.actions),
          ],
          const SizedBox(height: 18),
          _PurchaseMetricGrid(
            outstandingPo: outstandingPo,
            approvalCount: todoState.purchaseApprovalTodoCount,
            overdueInvoices: overdueInvoices,
            outstandingDebt: outstandingDebt,
          ),
          const SizedBox(height: 16),
          if (receiptIssues > 0) ...[
            _AlertStrip(
              icon: Icons.rule_folder_outlined,
              message:
                  '$receiptIssues receipt memiliki rejected qty atau selisih quantity.',
              onTap: () {
                final receiptAction = widget.actions.where(
                  (action) => action.key == 'pr',
                );
                if (receiptAction.isNotEmpty) receiptAction.first.onTap();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class PurchaseOverviewAction {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const PurchaseOverviewAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _PurchaseHeroCard extends StatelessWidget {
  final int outstandingPo;
  final int approvalCount;
  final int overdueInvoices;
  final double outstandingDebt;

  const _PurchaseHeroCard({
    required this.outstandingPo,
    required this.approvalCount,
    required this.overdueInvoices,
    required this.outstandingDebt,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.border),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF22C55E).withValues(alpha: 0.10),
          blurRadius: 24,
          offset: const Offset(0, 14),
        ),
      ],
    ),
    child: Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Purchase Workspace',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'PO, receipt, invoice supplier, dan request barang.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.slate,
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Transform.rotate(
          angle: -0.14,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.28),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(
              Icons.shopping_bag_rounded,
              color: AppColors.white,
              size: 30,
            ),
          ),
        ),
      ],
    ),
  );
}

class _PurchaseShortcutGrid extends StatelessWidget {
  final List<PurchaseOverviewAction> actions;

  const _PurchaseShortcutGrid({required this.actions});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: 14,
      crossAxisSpacing: 10,
      childAspectRatio: 0.82,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: actions.map((action) {
        return _PurchaseShortcutTile(action: action);
      }).toList(),
    );
  }
}

class _PurchaseShortcutTile extends StatelessWidget {
  final PurchaseOverviewAction action;

  const _PurchaseShortcutTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: action.label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: action.onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: action.color,
                  borderRadius: BorderRadius.circular(17),
                  boxShadow: [
                    BoxShadow(
                      color: action.color.withValues(alpha: 0.30),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(action.icon, color: AppColors.white, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                action.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 11,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchaseMetricGrid extends StatelessWidget {
  final int outstandingPo;
  final int approvalCount;
  final int overdueInvoices;
  final double outstandingDebt;

  const _PurchaseMetricGrid({
    required this.outstandingPo,
    required this.approvalCount,
    required this.overdueInvoices,
    required this.outstandingDebt,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _HeroMetric(
                label: 'Open PO',
                value: '$outstandingPo',
                icon: Icons.pending_actions_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HeroMetric(
                label: 'Overdue PI',
                value: '$overdueInvoices',
                icon: Icons.warning_amber_rounded,
                color: AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _HeroMetric(
                label: 'Approval',
                value: '$approvalCount',
                icon: Icons.fact_check_outlined,
                color: const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HeroMetric(
                label: 'Outstanding',
                value: 'Rp ${formatErpCurrency(outstandingDebt)}',
                icon: Icons.payments_outlined,
                color: const Color(0xFF0891B2),
                compact: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool compact;

  const _HeroMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: AppColors.border),
      boxShadow: AppColors.cardShadow,
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: compact ? 13 : 17,
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
                  fontSize: 10.5,
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

class _AlertStrip extends StatelessWidget {
  final IconData icon;
  final String message;
  final VoidCallback onTap;

  const _AlertStrip({
    required this.icon,
    required this.message,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warning.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.warning, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.warning),
            ],
          ),
        ),
      ),
    );
  }
}
