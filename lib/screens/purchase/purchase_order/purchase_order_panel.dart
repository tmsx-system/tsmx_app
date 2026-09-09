import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/purchase_order.dart';
import '../../../models/supplier_price_comparison.dart';
import '../../../../state/purchasing/purchase_order_state.dart';
import '../../../../state/purchasing/purchasing_summary_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_doc_utils.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/document_trend_card.dart';
import '../../../widgets/erp/erp_document_card.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/erp/erp_status_chip_bar.dart';
import '../../../widgets/erp/erp_workflow_helper.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../../purchase/purchase_order/create_purchase_order_screen.dart';
import '../shared/buying_document_detail_sheet.dart';
import '../shared/purchase_ui.dart';

enum _PurchaseSortOption { newest, oldestEta, valueHigh, valueLow }

enum _PoDocStatusFilter { all, draft, submitted, cancelled }

class PurchaseOrderPanel extends StatefulWidget {
  final bool canCreatePurchaseReceipt;
  final bool canCreatePurchaseInvoice;

  const PurchaseOrderPanel({
    super.key,
    this.canCreatePurchaseReceipt = true,
    this.canCreatePurchaseInvoice = true,
  });

  @override
  State<PurchaseOrderPanel> createState() => _PurchaseOrderPanelState();
}

class _PurchaseOrderPanelState extends State<PurchaseOrderPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  PurchaseOrderStatusKey? _statusFilter;
  _PurchaseSortOption _sortOption = _PurchaseSortOption.newest;
  String _advancedSupplier = '';
  String _advancedItem = '';
  String _advancedWarehouse = '';
  double? _advancedMinValue;
  double? _advancedMaxValue;
  DateTime? _advancedFrom;
  DateTime? _advancedTo;
  _PoDocStatusFilter _advancedDocStatus = _PoDocStatusFilter.all;
  Timer? _searchDebounce;

  static final _chips = <ErpStatusChip<PurchaseOrderStatusKey?>>[
    const ErpStatusChip(label: 'All', value: null),
    const ErpStatusChip(label: 'Draft', value: PurchaseOrderStatusKey.draft),
    const ErpStatusChip(
      label: 'To Receive and To Bill',
      value: PurchaseOrderStatusKey.toReceiveAndBill,
    ),
    const ErpStatusChip(label: 'To Bill', value: PurchaseOrderStatusKey.toBill),
    const ErpStatusChip(
      label: 'To Receive',
      value: PurchaseOrderStatusKey.toReceive,
    ),
    const ErpStatusChip(
      label: 'Completed',
      value: PurchaseOrderStatusKey.completed,
    ),
    const ErpStatusChip(
      label: 'Cancelled',
      value: PurchaseOrderStatusKey.cancelled,
    ),
    const ErpStatusChip(label: 'Closed', value: PurchaseOrderStatusKey.closed),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final purchasingState = context.read<PurchaseOrderState>();
      if (purchasingState.purchaseOrders.isEmpty) {
        purchasingState.refreshPurchaseOrders();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String? get _statusText {
    return switch (_statusFilter) {
      PurchaseOrderStatusKey.draft => 'Draft',
      PurchaseOrderStatusKey.toReceiveAndBill => 'To Receive and To Bill',
      PurchaseOrderStatusKey.toBill => 'To Bill',
      PurchaseOrderStatusKey.toReceive => 'To Receive',
      PurchaseOrderStatusKey.completed => 'Completed',
      PurchaseOrderStatusKey.cancelled => 'Cancelled',
      PurchaseOrderStatusKey.closed => 'Closed',
      _ => null,
    };
  }

  void _searchChanged(String value) {
    setState(() => _search = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        context.read<PurchaseOrderState>().setPurchaseOrderQuery(
          search: value,
          status: _statusText,
        );
      }
    });
  }

  List<PurchaseOrder> _filter(List<PurchaseOrder> orders) {
    final q = _search.toLowerCase();
    final filtered = orders.where((o) {
      final matchSearch =
          q.isEmpty ||
          o.id.toLowerCase().contains(q) ||
          o.vendor.toLowerCase().contains(q);
      final matchStatus = _statusFilter == null || o.statusKey == _statusFilter;
      return matchSearch && matchStatus && _matchesAdvancedFilters(o);
    }).toList();

    filtered.sort((a, b) {
      return switch (_sortOption) {
        _PurchaseSortOption.newest => _compareDateDesc(
          a.modified.isNotEmpty ? a.modified : a.eta,
          b.modified.isNotEmpty ? b.modified : b.eta,
        ),
        _PurchaseSortOption.oldestEta => _compareDateAsc(a.eta, b.eta),
        _PurchaseSortOption.valueHigh => b.totalValue.compareTo(a.totalValue),
        _PurchaseSortOption.valueLow => a.totalValue.compareTo(b.totalValue),
      };
    });

    return filtered;
  }

  int _compareDateDesc(String a, String b) {
    final left = _parseDate(a);
    final right = _parseDate(b);
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  }

  int _compareDateAsc(String a, String b) {
    final left = _parseDate(a);
    final right = _parseDate(b);
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime? _parseDate(String rawDate) {
    final trimmed = rawDate.trim();
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

  String _sortLabel(_PurchaseSortOption option) {
    return switch (option) {
      _PurchaseSortOption.newest => 'Newest',
      _PurchaseSortOption.oldestEta => 'ETA terlama',
      _PurchaseSortOption.valueHigh => 'Nilai tertinggi',
      _PurchaseSortOption.valueLow => 'Nilai terendah',
    };
  }

  Future<void> _openAdvancedFilters() async {
    final result = await showModalBottomSheet<_PurchaseOrderAdvancedFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _PurchaseOrderAdvancedFilterSheet(
        initial: _PurchaseOrderAdvancedFilters(
          supplier: _advancedSupplier,
          item: _advancedItem,
          warehouse: _advancedWarehouse,
          minValue: _advancedMinValue,
          maxValue: _advancedMaxValue,
          from: _advancedFrom,
          to: _advancedTo,
          docStatus: _advancedDocStatus,
        ),
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      _advancedSupplier = result.supplier;
      _advancedItem = result.item;
      _advancedWarehouse = result.warehouse;
      _advancedMinValue = result.minValue;
      _advancedMaxValue = result.maxValue;
      _advancedFrom = result.from;
      _advancedTo = result.to;
      _advancedDocStatus = result.docStatus;
    });
  }

  Future<void> _openDetail(PurchaseOrder order) async {
    final purchasingState = context.read<PurchaseOrderState>();
    final detail = await purchasingState.loadPurchaseOrderDetail(order.id);
    var workflowActions = <String>[];
    try {
      workflowActions = await purchasingState.fetchDocumentWorkflowActions(
        doctype: 'Purchase Order',
        name: detail.id,
      );
    } catch (_) {}
    if (!mounted) return;

    final canReceive =
        isDocSubmitted(detail.docStatus) && detail.perReceived < 100;
    final canBill = isDocSubmitted(detail.docStatus) && detail.perBilled < 100;
    final canSubmit = isDocDraft(detail.docStatus);
    final canEdit = isDocDraft(detail.docStatus);
    final canDelete = isDocDraft(detail.docStatus);
    final canCancel =
        isDocSubmitted(detail.docStatus) &&
        detail.statusKey != PurchaseOrderStatusKey.completed &&
        detail.statusKey != PurchaseOrderStatusKey.closed &&
        detail.statusKey != PurchaseOrderStatusKey.cancelled;

    showBuyingDocumentDetailSheet(
      context: context,
      title: detail.id,
      subtitle: detail.vendor,
      statusText: detail.statusText,
      icon: Icons.shopping_bag_rounded,
      metrics: [
        BuyingDetailMetric(
          label: 'Total',
          value: 'Rp ${formatErpCurrency(detail.totalValue)}',
          icon: Icons.payments_outlined,
        ),
        BuyingDetailMetric(
          label: 'Items',
          value: '${detail.itemsCount}',
          icon: Icons.inventory_2_outlined,
        ),
        BuyingDetailMetric(
          label: 'Received',
          value: '${detail.perReceived.toStringAsFixed(1)}%',
          icon: Icons.move_to_inbox_outlined,
        ),
        BuyingDetailMetric(
          label: 'Billed',
          value: '${detail.perBilled.toStringAsFixed(1)}%',
          icon: Icons.receipt_long_outlined,
        ),
      ],
      infos: [
        BuyingDetailInfo(
          label: 'Doc Status',
          value: docStatusLabel(detail.docStatus),
        ),
        BuyingDetailInfo(label: 'ERP Status', value: detail.statusText),
        BuyingDetailInfo(
          label: 'Expected',
          value: detail.eta.isEmpty ? '-' : detail.eta,
        ),
        if (detail.isOverdue)
          const BuyingDetailInfo(label: 'ETA Risk', value: 'Overdue'),
      ],
      items: detail.items
          .map(
            (i) => BuyingDetailItem(
              title: i.itemName,
              subtitle: i.itemCode,
              qty: '${i.qty}',
              rate: 'Rp ${formatErpCurrency(i.rate)}',
              amount: 'Rp ${formatErpCurrency(i.qty * i.rate)}',
              note: i.warehouse,
            ),
          )
          .toList(),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._workflowButtons(
            doctype: 'Purchase Order',
            name: detail.id,
            actions: workflowActions,
          ),
          if (workflowActions.isEmpty && !canSubmit) ...[
            const _PoApprovalInfoCard(),
            const SizedBox(height: 10),
          ],
          if (detail.items.isNotEmpty)
            erpActionButton(
              label: 'Bandingkan Harga Supplier',
              icon: Icons.compare_arrows_rounded,
              onPressed: () => _openSupplierComparison(detail.items),
            ),
          if (canEdit)
            erpActionButton(
              label: 'Edit Purchase Order',
              icon: Icons.edit_outlined,
              onPressed: () => _editPo(detail.id, closeSheet: true),
            ),
          if (canSubmit)
            erpActionButton(
              label: 'Submit Purchase Order',
              icon: Icons.check_circle_outline_rounded,
              filled: true,
              onPressed: () => _submitPo(detail.id),
            ),
          if (canReceive && widget.canCreatePurchaseReceipt)
            erpActionButton(
              label: 'Create Purchase Receipt',
              icon: Icons.inventory_2_outlined,
              onPressed: () => _createPr(detail.id),
            ),
          if (canBill && widget.canCreatePurchaseInvoice)
            erpActionButton(
              label: 'Create Purchase Invoice',
              icon: Icons.receipt_outlined,
              onPressed: () => _createPi(detail.id),
            ),
          if (canCancel)
            erpActionButton(
              label: 'Cancel Purchase Order',
              icon: Icons.cancel_outlined,
              onPressed: () => _cancelPo(detail.id),
            ),
          if (canDelete)
            erpActionButton(
              label: 'Delete Draft',
              icon: Icons.delete_outline_rounded,
              onPressed: () => _deletePo(detail.id, closeSheet: true),
            ),
          if (!canSubmit &&
              !canReceive &&
              !canBill &&
              !canEdit &&
              !canCancel &&
              !canDelete)
            const Text(
              'No workflow actions available for this document.',
              style: TextStyle(fontSize: 12, color: AppColors.slate),
            ),
        ],
      ),
    );
  }

  bool _matchesAdvancedFilters(PurchaseOrder order) {
    final supplier = _advancedSupplier.trim().toLowerCase();
    if (supplier.isNotEmpty && !order.vendor.toLowerCase().contains(supplier)) {
      return false;
    }
    if (_advancedMinValue != null && order.totalValue < _advancedMinValue!) {
      return false;
    }
    if (_advancedMaxValue != null && order.totalValue > _advancedMaxValue!) {
      return false;
    }

    final date = _parseDate(order.eta);
    if (_advancedFrom != null &&
        (date == null || date.isBefore(_dateOnly(_advancedFrom!)))) {
      return false;
    }
    if (_advancedTo != null &&
        (date == null || date.isAfter(_dateOnly(_advancedTo!)))) {
      return false;
    }

    final item = _advancedItem.trim().toLowerCase();
    if (item.isNotEmpty &&
        !order.items.any(
          (row) =>
              row.itemCode.toLowerCase().contains(item) ||
              row.itemName.toLowerCase().contains(item),
        )) {
      return false;
    }

    final warehouse = _advancedWarehouse.trim().toLowerCase();
    if (warehouse.isNotEmpty &&
        !order.items.any(
          (row) => row.warehouse.toLowerCase().contains(warehouse),
        )) {
      return false;
    }

    return switch (_advancedDocStatus) {
      _PoDocStatusFilter.all => true,
      _PoDocStatusFilter.draft => order.docStatus == 0,
      _PoDocStatusFilter.submitted => order.docStatus == 1,
      _PoDocStatusFilter.cancelled => order.docStatus == 2,
    };
  }

  int get _advancedFilterCount {
    var count = 0;
    if (_advancedSupplier.trim().isNotEmpty) count++;
    if (_advancedItem.trim().isNotEmpty) count++;
    if (_advancedWarehouse.trim().isNotEmpty) count++;
    if (_advancedMinValue != null) count++;
    if (_advancedMaxValue != null) count++;
    if (_advancedFrom != null || _advancedTo != null) count++;
    if (_advancedDocStatus != _PoDocStatusFilter.all) count++;
    return count;
  }

  Future<void> _editPo(String id, {bool closeSheet = false}) async {
    if (closeSheet) Navigator.pop(context);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatePurchaseOrderScreen(editOrderId: id),
      ),
    );
    if (mounted) {
      await context.read<PurchaseOrderState>().refreshPurchaseOrders();
    }
  }

  Future<void> _submitPo(String id) async {
    if (!await confirmErpAction(
      context,
      title: 'Submit Purchase Order?',
      message: 'Submit $id?',
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await runErpWorkflowAction(
      context,
      action: () => context.read<PurchaseOrderState>().submitDocument(
        'Purchase Order',
        id,
      ),
      successMessage: 'Purchase Order submitted',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  Future<void> _cancelPo(String id) async {
    if (!await confirmErpAction(
      context,
      title: 'Cancel Purchase Order?',
      message: 'Batalkan $id?',
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await runErpWorkflowAction(
      context,
      action: () => context.read<PurchaseOrderState>().cancelDocument(
        'Purchase Order',
        id,
      ),
      successMessage: 'Purchase Order cancelled',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  Future<void> _deletePo(String id, {bool closeSheet = false}) async {
    if (!await confirmErpAction(
      context,
      title: 'Delete Draft Purchase Order?',
      message: 'Hapus draft $id?',
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await runErpWorkflowAction(
      context,
      action: () => context.read<PurchaseOrderState>().deletePurchaseOrder(id),
      successMessage: 'Purchase Order deleted',
    );
    if (ok && mounted && closeSheet) Navigator.pop(context);
  }

  Future<void> _createPr(String poId) async {
    final ok = await runErpWorkflowAction(
      context,
      action: () => context
          .read<PurchaseOrderState>()
          .createPurchaseReceiptFromPurchaseOrder(poId),
      successMessage: 'Purchase Receipt created',
    );
    if (ok && mounted) {
      Navigator.pop(context);
      await context.read<PurchaseOrderState>().refreshPurchaseReceipts();
    }
  }

  Future<void> _createPi(String poId) async {
    final ok = await runErpWorkflowAction(
      context,
      action: () => context
          .read<PurchaseOrderState>()
          .createPurchaseInvoiceFromPurchaseOrder(poId),
      successMessage: 'Purchase Invoice created',
    );
    if (ok && mounted) {
      Navigator.pop(context);
      await context.read<PurchaseOrderState>().refreshPurchaseInvoices();
    }
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
      action: () => context.read<PurchaseOrderState>().applyDocumentWorkflow(
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

  Future<void> _openSupplierComparison(List<PurchaseOrderItem> items) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupplierPriceComparisonSheet(items: items),
    );
  }

  @override
  Widget build(BuildContext context) {
    final purchasingState = context.watch<PurchaseOrderState>();
    final summaryState = context.watch<PurchasingSummaryState>();
    final filtered = _filter(purchasingState.purchaseOrders);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DocumentTrendCard(
          title: 'Purchase Order',
          emptyMessage:
              'Belum ada nilai Purchase Order dari Purchase Analytics pada periode ini.',
          points: summaryState.purchaseOrderTrendPoints,
          selectedYear: summaryState.buyingPeriodYear,
          selectedMonth: summaryState.buyingPeriodMonth,
          sourceLabel: 'Sumber: Purchase Analytics ERPNext',
        ),

        const SizedBox(height: 12),

        PurchaseSearchField(
          controller: _searchController,
          onChanged: _searchChanged,
          hintText: 'Cari PO atau supplier...',
        ),

        if (purchasingState.purchaseOrdersError != null) ...[
          const SizedBox(height: 10),
          ErpErrorBox(message: purchasingState.purchaseOrdersError!),
        ],

        const SizedBox(height: 10),

        _PurchaseOrderQuickFilters(
          sortOption: _sortOption,
          sortLabel: _sortLabel,
          onSortChanged: (v) => setState(() => _sortOption = v),
          onReset: () {
            setState(() {
              _searchController.clear();
              _search = '';
              _statusFilter = null;
              _sortOption = _PurchaseSortOption.newest;
              _advancedSupplier = '';
              _advancedItem = '';
              _advancedWarehouse = '';
              _advancedMinValue = null;
              _advancedMaxValue = null;
              _advancedFrom = null;
              _advancedTo = null;
              _advancedDocStatus = _PoDocStatusFilter.all;
            });
            context.read<PurchaseOrderState>().setPurchaseOrderQuery(
              search: '',
              status: null,
            );
          },
          advancedCount: _advancedFilterCount,
          onAdvancedFilters: _openAdvancedFilters,
        ),

        const SizedBox(height: 10),

        ErpStatusChipBar<PurchaseOrderStatusKey?>(
          chips: _chips,
          selected: _statusFilter,
          onSelected: (v) {
            setState(() => _statusFilter = v);
            context.read<PurchaseOrderState>().setPurchaseOrderQuery(
              search: _search,
              status: _statusText,
            );
          },
        ),

        const SizedBox(height: 12),

        if (filtered.isEmpty && !purchasingState.isPurchaseOrdersLoading)
          const ErpEmptyState(
            title: 'Belum ada Purchase Order',
            message: 'Gunakan tombol Buat PO untuk membuat dokumen baru.',
          )
        else
          TmsxResponsiveCardGrid(
            children: filtered
                .map(
                  (o) => ErpDocumentCard(
                    id: o.id,
                    party: o.vendor,
                    statusText: o.statusText,
                    date: o.eta,
                    value: o.totalValue,
                    onTap: () => _openDetail(o),
                    onEdit: isDocDraft(o.docStatus)
                        ? () => _editPo(o.id)
                        : null,
                    onDelete: isDocDraft(o.docStatus)
                        ? () => _deletePo(o.id)
                        : null,
                  ),
                )
                .toList(),
          ),

        if (purchasingState.hasMorePurchaseOrders ||
            purchasingState.isMorePurchaseOrdersLoading) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: purchasingState.isMorePurchaseOrdersLoading
                  ? null
                  : () => context
                        .read<PurchaseOrderState>()
                        .loadMorePurchaseOrders(),
              icon: purchasingState.isMorePurchaseOrdersLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(
                purchasingState.isMorePurchaseOrdersLoading
                    ? 'Memuat PO...'
                    : 'Muat PO lainnya',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PurchaseOrderQuickFilters extends StatelessWidget {
  final _PurchaseSortOption sortOption;
  final String Function(_PurchaseSortOption) sortLabel;
  final ValueChanged<_PurchaseSortOption> onSortChanged;
  final VoidCallback onReset;
  final int advancedCount;
  final VoidCallback onAdvancedFilters;

  const _PurchaseOrderQuickFilters({
    required this.sortOption,
    required this.sortLabel,
    required this.onSortChanged,
    required this.onReset,
    required this.advancedCount,
    required this.onAdvancedFilters,
  });

  @override
  Widget build(BuildContext context) {
    return PurchaseFilterSurface(
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<_PurchaseSortOption>(
              initialValue: sortOption,
              decoration: const InputDecoration(
                labelText: 'Urutkan',
                prefixIcon: Icon(Icons.sort_rounded, size: 18),
              ),
              items: _PurchaseSortOption.values.map((option) {
                return DropdownMenuItem<_PurchaseSortOption>(
                  value: option,
                  child: Text(sortLabel(option)),
                );
              }).toList(),
              onChanged: (option) {
                if (option != null) onSortChanged(option);
              },
            ),
          ),
          const SizedBox(width: 8),
          _PurchaseFilterButton(
            icon: Icons.tune_rounded,
            label: advancedCount > 0 ? 'Filter $advancedCount' : 'Filter',
            onTap: onAdvancedFilters,
          ),
          const SizedBox(width: 8),
          _PurchaseFilterButton(
            icon: Icons.restart_alt_rounded,
            label: 'Reset',
            onTap: onReset,
          ),
        ],
      ),
    );
  }
}

class _PurchaseFilterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PurchaseFilterButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.softGreen,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 64,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.primary, size: 18),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
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

class _SupplierPriceComparisonSheet extends StatefulWidget {
  final List<PurchaseOrderItem> items;

  const _SupplierPriceComparisonSheet({required this.items});

  @override
  State<_SupplierPriceComparisonSheet> createState() =>
      _SupplierPriceComparisonSheetState();
}

class _SupplierPriceComparisonSheetState
    extends State<_SupplierPriceComparisonSheet> {
  late PurchaseOrderItem _selectedItem;
  SupplierPriceComparison? _comparison;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedItem = widget.items.first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context
          .read<PurchaseOrderState>()
          .fetchSupplierPriceComparison(
            itemCode: _selectedItem.itemCode,
            itemName: _selectedItem.itemName,
          );
      if (!mounted) return;
      setState(() => _comparison = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comparison = _comparison;
    final cheapest = comparison?.cheapest;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _ComparisonHeader(onClose: () => Navigator.pop(context)),
              const SizedBox(height: 12),
              if (widget.items.length > 1)
                DropdownButtonFormField<PurchaseOrderItem>(
                  initialValue: _selectedItem,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Pilih Item',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  items: widget.items
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(
                            '${item.itemName} (${item.itemCode})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (item) {
                    if (item == null) return;
                    _selectedItem = item;
                    _load();
                  },
                )
              else
                _SelectedItemCard(item: _selectedItem),
              const SizedBox(height: 12),
              if (_loading)
                const LinearProgressIndicator()
              else if (_error != null)
                ErpErrorBox(message: _error!)
              else if (comparison == null || comparison.options.isEmpty)
                const ErpEmptyState(
                  title: 'Belum ada pembanding harga',
                  message:
                      'Tambahkan Item Price buying atau histori Purchase Order agar rekomendasi muncul.',
                )
              else ...[
                if (cheapest != null) _CheapestSupplierCard(option: cheapest),
                const SizedBox(height: 12),
                const Text(
                  'Daftar Pembanding',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                ...comparison.options.map(
                  (option) => _SupplierPriceOptionCard(
                    option: option,
                    cheapest: option == cheapest,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ComparisonHeader extends StatelessWidget {
  final VoidCallback onClose;

  const _ComparisonHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.softGreen,
            foregroundColor: AppColors.primary,
            child: Icon(Icons.price_check_rounded),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Supplier Price Comparison',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Bandingkan price list dan histori PO terakhir.',
                  style: TextStyle(color: AppColors.slate, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close_rounded)),
        ],
      ),
    );
  }
}

class _SelectedItemCard extends StatelessWidget {
  final PurchaseOrderItem item;

  const _SelectedItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  item.itemCode,
                  style: const TextStyle(color: AppColors.slate, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheapestSupplierCard extends StatelessWidget {
  final SupplierPriceOption option;

  const _CheapestSupplierCard({required this.option});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.white,
            child: Icon(Icons.recommend_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rekomendasi termurah',
                  style: TextStyle(color: AppColors.slate, fontSize: 12),
                ),
                Text(
                  option.displaySupplier,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  option.sourceLabel,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'Rp ${formatErpCurrency(option.rate)}',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierPriceOptionCard extends StatelessWidget {
  final SupplierPriceOption option;
  final bool cheapest;

  const _SupplierPriceOptionCard({
    required this.option,
    required this.cheapest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cheapest
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  option.displaySupplier,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (cheapest)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.softGreen,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Termurah',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: option.source == 'Item Price'
                      ? AppColors.softGreen
                      : AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  option.sourceLabel,
                  style: TextStyle(
                    color: option.source == 'Item Price'
                        ? AppColors.primary
                        : AppColors.warning,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'Rp ${formatErpCurrency(option.rate)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            option.sourceDescription,
            style: const TextStyle(color: AppColors.slate, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _PoApprovalInfoCard extends StatelessWidget {
  const _PoApprovalInfoCard();

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
              'Action approval akan muncul otomatis jika Workflow ERPNext untuk Purchase Order sudah aktif dan role user sesuai.',
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

class _PurchaseOrderAdvancedFilters {
  final String supplier;
  final String item;
  final String warehouse;
  final double? minValue;
  final double? maxValue;
  final DateTime? from;
  final DateTime? to;
  final _PoDocStatusFilter docStatus;

  const _PurchaseOrderAdvancedFilters({
    required this.supplier,
    required this.item,
    required this.warehouse,
    required this.minValue,
    required this.maxValue,
    required this.from,
    required this.to,
    required this.docStatus,
  });
}

class _PurchaseOrderAdvancedFilterSheet extends StatefulWidget {
  final _PurchaseOrderAdvancedFilters initial;

  const _PurchaseOrderAdvancedFilterSheet({required this.initial});

  @override
  State<_PurchaseOrderAdvancedFilterSheet> createState() =>
      _PurchaseOrderAdvancedFilterSheetState();
}

class _PurchaseOrderAdvancedFilterSheetState
    extends State<_PurchaseOrderAdvancedFilterSheet> {
  late final TextEditingController _supplierCtrl;
  late final TextEditingController _itemCtrl;
  late final TextEditingController _warehouseCtrl;
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  DateTime? _from;
  DateTime? _to;
  late _PoDocStatusFilter _docStatus;

  @override
  void initState() {
    super.initState();
    _supplierCtrl = TextEditingController(text: widget.initial.supplier);
    _itemCtrl = TextEditingController(text: widget.initial.item);
    _warehouseCtrl = TextEditingController(text: widget.initial.warehouse);
    _minCtrl = TextEditingController(
      text: widget.initial.minValue?.toStringAsFixed(0) ?? '',
    );
    _maxCtrl = TextEditingController(
      text: widget.initial.maxValue?.toStringAsFixed(0) ?? '',
    );
    _from = widget.initial.from;
    _to = widget.initial.to;
    _docStatus = widget.initial.docStatus;
  }

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _itemCtrl.dispose();
    _warehouseCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  String _dateText(DateTime? date) {
    if (date == null) return 'Any';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _PurchaseOrderAdvancedFilters(
        supplier: _supplierCtrl.text.trim(),
        item: _itemCtrl.text.trim(),
        warehouse: _warehouseCtrl.text.trim(),
        minValue: double.tryParse(_minCtrl.text.trim()),
        maxValue: double.tryParse(_maxCtrl.text.trim()),
        from: _from,
        to: _to,
        docStatus: _docStatus,
      ),
    );
  }

  void _reset() {
    Navigator.pop(
      context,
      const _PurchaseOrderAdvancedFilters(
        supplier: '',
        item: '',
        warehouse: '',
        minValue: null,
        maxValue: null,
        from: null,
        to: null,
        docStatus: _PoDocStatusFilter.all,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Advanced Purchase Filters',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _supplierCtrl,
                decoration: const InputDecoration(labelText: 'Supplier'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _itemCtrl,
                decoration: const InputDecoration(labelText: 'Item keyword'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _warehouseCtrl,
                decoration: const InputDecoration(labelText: 'Warehouse'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Min value'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _maxCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Max value'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(isFrom: true),
                      icon: const Icon(Icons.date_range_rounded),
                      label: Text('From ${_dateText(_from)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(isFrom: false),
                      icon: const Icon(Icons.event_rounded),
                      label: Text('To ${_dateText(_to)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<_PoDocStatusFilter>(
                initialValue: _docStatus,
                decoration: const InputDecoration(labelText: 'Doc status'),
                items: const [
                  DropdownMenuItem(
                    value: _PoDocStatusFilter.all,
                    child: Text('All'),
                  ),
                  DropdownMenuItem(
                    value: _PoDocStatusFilter.draft,
                    child: Text('Draft'),
                  ),
                  DropdownMenuItem(
                    value: _PoDocStatusFilter.submitted,
                    child: Text('Submitted'),
                  ),
                  DropdownMenuItem(
                    value: _PoDocStatusFilter.cancelled,
                    child: Text('Cancelled'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _docStatus = value);
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reset,
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      child: const Text('Apply'),
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
