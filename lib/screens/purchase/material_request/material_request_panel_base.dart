import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/inventory_item.dart';
import '../../../models/material_request.dart';
import '../../../../state/purchasing/material_request_state.dart';
import '../../../../state/purchasing/purchasing_summary_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_doc_utils.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/document_trend_card.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/erp/erp_status_badge.dart';
import '../../../widgets/erp/erp_status_chip_bar.dart';
import '../../../widgets/erp/erp_workflow_helper.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../../purchase/material_request/create_material_request_screen.dart';
import '../../purchase/purchase_order/create_purchase_order_screen.dart';
import '../shared/buying_document_detail_sheet.dart';
import '../shared/purchase_ui.dart';

enum _MaterialRequestFocusFilter {
  all,
  purchase,
  transfer,
  active,
  draft,
  ordered,
}

class MaterialRequestPanel extends StatefulWidget {
  final bool canCreateMaterialRequest;
  final bool canCreatePurchaseOrder;

  const MaterialRequestPanel({
    super.key,
    this.canCreateMaterialRequest = true,
    this.canCreatePurchaseOrder = true,
  });

  @override
  State<MaterialRequestPanel> createState() => _MaterialRequestPanelState();
}

class _MaterialRequestPanelState extends State<MaterialRequestPanel> {
  String _search = '';
  String? _statusFilter;
  _MaterialRequestFocusFilter _focusFilter = _MaterialRequestFocusFilter.all;
  Timer? _searchDebounce;

  static const _allStatusFilter = '__all__';
  static const _chips = <ErpStatusChip<String>>[
    ErpStatusChip(label: 'Semua', value: _allStatusFilter),
    ErpStatusChip(label: 'Draft', value: 'Draft'),
    ErpStatusChip(label: 'Pending', value: 'Pending'),
    ErpStatusChip(label: 'Partly Ordered', value: 'Partially Ordered'),
    ErpStatusChip(label: 'Ordered', value: 'Ordered'),
    ErpStatusChip(label: 'Stopped', value: 'Stopped'),
    ErpStatusChip(label: 'Cancelled', value: 'Cancelled'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final purchasingState = context.read<MaterialRequestState>();
      if (purchasingState.materialRequests.isEmpty) {
        purchasingState.refreshMaterialRequests();
      }
      if (purchasingState.inventory.isEmpty) {
        purchasingState.refreshInventory();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _searchChanged(String value) {
    setState(() => _search = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        context.read<MaterialRequestState>().setMaterialRequestQuery(
          search: value,
          status: _statusFilter,
        );
      }
    });
  }

  List<MaterialRequest> _filter(List<MaterialRequest> docs) {
    final q = _search.toLowerCase();
    return docs.where((doc) {
      final matchSearch =
          q.isEmpty ||
          doc.id.toLowerCase().contains(q) ||
          doc.type.toLowerCase().contains(q) ||
          doc.company.toLowerCase().contains(q) ||
          doc.items.any(
            (item) =>
                item.itemCode.toLowerCase().contains(q) ||
                item.itemName.toLowerCase().contains(q),
          );
      final matchStatus =
          _statusFilter == null ||
          doc.statusText.toLowerCase() == _statusFilter!.toLowerCase();
      return matchSearch && matchStatus && _matchesFocusFilter(doc);
    }).toList();
  }

  bool _matchesFocusFilter(MaterialRequest doc) {
    final type = doc.type.toLowerCase();
    final status = doc.statusText.toLowerCase();
    return switch (_focusFilter) {
      _MaterialRequestFocusFilter.all => true,
      _MaterialRequestFocusFilter.purchase => type.contains('purchase'),
      _MaterialRequestFocusFilter.transfer =>
        type.contains('transfer') || type.contains('material transfer'),
      _MaterialRequestFocusFilter.active =>
        !status.contains('cancel') &&
            !status.contains('stopped') &&
            !status.contains('ordered'),
      _MaterialRequestFocusFilter.draft => isDocDraft(doc.docStatus),
      _MaterialRequestFocusFilter.ordered => status.contains('ordered'),
    };
  }

  String _emptyMessage() {
    return switch (_focusFilter) {
      _MaterialRequestFocusFilter.all =>
        'Gunakan tombol Buat Request untuk mengajukan kebutuhan.',
      _MaterialRequestFocusFilter.purchase =>
        'Tidak ada Material Request pembelian pada filter ini.',
      _MaterialRequestFocusFilter.transfer =>
        'Tidak ada Material Request antar departemen pada filter ini.',
      _MaterialRequestFocusFilter.active =>
        'Tidak ada kebutuhan barang aktif pada filter ini.',
      _MaterialRequestFocusFilter.draft =>
        'Tidak ada draft Material Request pada filter ini.',
      _MaterialRequestFocusFilter.ordered =>
        'Tidak ada Material Request yang sudah ordered pada filter ini.',
    };
  }

  bool _isPermissionError(String? message) {
    final text = message?.toLowerCase() ?? '';
    return text.contains('permission') ||
        text.contains('tidak dizinkan') ||
        text.contains('tidak diizinkan') ||
        text.contains('not permitted') ||
        text.contains('not allowed') ||
        text.contains('akses erpnext');
  }

  String _friendlyError(String message) {
    if (_isPermissionError(message)) {
      return 'Akses Material Request ditolak ERPNext. Cek Role Permission untuk Material Request dan Material Request Item, lalu cek User Permission Company jika role sudah benar.';
    }
    return message.replaceFirst('Exception: ', '');
  }

  List<InventoryItem> _planningItems(MaterialRequestState purchasingState) {
    final rows =
        purchasingState.inventory
            .where(
              (item) =>
                  item.quantity <= 0 ||
                  (item.minStockThreshold > 0 &&
                      item.quantity <= item.minStockThreshold),
            )
            .toList()
          ..sort((a, b) {
            final aScore = a.minStockThreshold > 0
                ? a.quantity / a.minStockThreshold
                : a.quantity;
            final bScore = b.minStockThreshold > 0
                ? b.quantity / b.minStockThreshold
                : b.quantity;
            return aScore.compareTo(bScore);
          });
    return rows.take(5).toList();
  }

  Future<void> _openCreate({InventoryItem? item}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateMaterialRequestScreen(initialItem: item),
      ),
    );
    if (mounted) {
      await context.read<MaterialRequestState>().refreshMaterialRequests();
    }
  }

  int _recommendedQty(InventoryItem item) {
    if (item.minStockThreshold <= 0) {
      return item.quantity <= 0 ? 1 : item.quantity;
    }
    final deficit = item.minStockThreshold - item.quantity;
    return deficit <= 0 ? 1 : deficit;
  }

  Future<void> _createDraftMrFor(InventoryItem item) async {
    final qty = _recommendedQty(item).toDouble();
    final purchasingState = context.read<MaterialRequestState>();
    try {
      await purchasingState.createMaterialRequest(
        materialRequestType: 'Purchase',
        itemCode: item.sku,
        qty: qty,
        transactionDate: DateTime.now(),
        scheduleDate: DateTime.now(),
        warehouse: item.warehouseId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Draft Material Request untuk ${item.name} dibuat.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal membuat draft MR. $error'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _openDraftPoFor(InventoryItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatePurchaseOrderScreen(initialItem: item),
      ),
    );
    if (mounted) {
      await context.read<MaterialRequestState>().refreshPurchaseOrders();
    }
  }

  Future<void> _openDetail(MaterialRequest doc) async {
    final purchasingState = context.read<MaterialRequestState>();
    final detail = await purchasingState.loadMaterialRequestDetail(doc.id);
    var workflowActions = <String>[];
    try {
      workflowActions = await purchasingState.fetchDocumentWorkflowActions(
        doctype: 'Material Request',
        name: detail.id,
      );
    } catch (_) {}
    if (!mounted) return;

    final canSubmit = isDocDraft(detail.docStatus);
    showBuyingDocumentDetailSheet(
      context: context,
      title: detail.id,
      subtitle: detail.type,
      statusText: detail.statusText,
      icon: Icons.assignment_turned_in_rounded,
      metrics: [
        BuyingDetailMetric(
          label: 'Qty',
          value: formatErpCurrency(detail.totalQty),
          icon: Icons.inventory_2_outlined,
        ),
        BuyingDetailMetric(
          label: 'Item',
          value: '${detail.itemsCount}',
          icon: Icons.list_alt_rounded,
        ),
      ],
      infos: [
        BuyingDetailInfo(
          label: 'Status Dokumen',
          value: docStatusLabel(detail.docStatus),
        ),
        BuyingDetailInfo(label: 'Company', value: detail.company),
        BuyingDetailInfo(label: 'Tanggal', value: detail.transactionDate),
        BuyingDetailInfo(label: 'Dibutuhkan', value: detail.scheduleDate),
      ],
      items: detail.items
          .map(
            (item) => BuyingDetailItem(
              title: item.itemName,
              subtitle: item.itemCode,
              qty:
                  '${formatErpCurrency(item.qty)}${item.uom.isEmpty ? '' : ' ${item.uom}'}',
              rate: 'Ordered ${formatErpCurrency(item.orderedQty)}',
              amount: item.scheduleDate.isEmpty ? '-' : item.scheduleDate,
              note: item.warehouse,
            ),
          )
          .toList(),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ..._workflowButtons(
            doctype: 'Material Request',
            name: detail.id,
            actions: workflowActions,
          ),
          if (workflowActions.isEmpty && !canSubmit)
            const _MaterialRequestApprovalInfoCard(),
          if (canSubmit) ...[
            if (workflowActions.isNotEmpty) const SizedBox(height: 10),
            erpActionButton(
              label: 'Ajukan Material Request',
              icon: Icons.check_circle_outline_rounded,
              filled: true,
              onPressed: () => _submit(detail.id),
            ),
          ],
        ],
      ),
    );
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
      action: () => context.read<MaterialRequestState>().applyDocumentWorkflow(
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

  Future<void> _submit(String id) async {
    if (!await confirmErpAction(
      context,
      title: 'Ajukan Material Request?',
      message: 'Ajukan $id ke ERPNext?',
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await runErpWorkflowAction(
      context,
      action: () => context.read<MaterialRequestState>().submitDocument(
        'Material Request',
        id,
      ),
      successMessage: 'Material Request berhasil diajukan',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final purchasingState = context.watch<MaterialRequestState>();
    final summaryState = context.watch<PurchasingSummaryState>();
    final filtered = _filter(purchasingState.materialRequests);
    final planningItems = _planningItems(purchasingState);
    final focusSummary = _MaterialRequestFocusSummary.from(
      purchasingState.materialRequests,
    );
    final materialRequestError = purchasingState.materialRequestsError;
    final hasBlockingError =
        materialRequestError != null &&
        purchasingState.materialRequests.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DocumentTrendCard(
          title: 'Material Request',
          emptyMessage:
              'Belum ada kebutuhan barang pada periode dan filter ini.',
          points: summaryState.materialRequestTrendPoints,
          selectedYear: summaryState.buyingPeriodYear,
          selectedMonth: summaryState.buyingPeriodMonth,
          valuePrefix: '',
          valueSuffix: ' qty',
          sourceLabel: 'Sumber: Material Request ERPNext',
        ),

        const SizedBox(height: 12),

        _MaterialRequestSummaryCard(requests: filtered),

        const SizedBox(height: 12),

        _MaterialRequestFocusCard(
          summary: focusSummary,
          selected: _focusFilter,
          onSelected: (filter) => setState(() => _focusFilter = filter),
        ),

        const SizedBox(height: 12),

        _PlanningCard(
          items: planningItems,
          onPick: (item) => _openCreate(item: item),
          onCreateMaterialRequest: widget.canCreateMaterialRequest
              ? _createDraftMrFor
              : null,
          onCreatePurchaseOrder: widget.canCreatePurchaseOrder
              ? _openDraftPoFor
              : null,
        ),

        const SizedBox(height: 12),

        PurchaseSearchField(
          onChanged: _searchChanged,
          hintText: 'Cari MR, tipe, company, atau item...',
        ),

        if (materialRequestError != null) ...[
          const SizedBox(height: 10),
          ErpErrorBox(
            message: _friendlyError(materialRequestError),
            onRetry: () =>
                context.read<MaterialRequestState>().refreshMaterialRequests(),
          ),
        ],

        if (!hasBlockingError) ...[
          const SizedBox(height: 10),

          ErpStatusChipBar<String>(
            chips: _chips,
            selected: _statusFilter ?? _allStatusFilter,
            onSelected: (value) {
              final status = value == _allStatusFilter ? null : value;
              setState(() => _statusFilter = status);
              context.read<MaterialRequestState>().setMaterialRequestQuery(
                search: _search,
                status: status,
              );
            },
          ),

          const SizedBox(height: 12),

          if (filtered.isEmpty &&
              !purchasingState.isMaterialRequestsLoading &&
              purchasingState.materialRequestsError == null)
            ErpEmptyState(
              title: _focusFilter == _MaterialRequestFocusFilter.all
                  ? 'Belum ada request'
                  : 'Request tidak ditemukan',
              message: _emptyMessage(),
            )
          else
            TmsxResponsiveCardGrid(
              children: filtered
                  .map(
                    (doc) => _MaterialRequestCard(
                      doc: doc,
                      onTap: () => _openDetail(doc),
                    ),
                  )
                  .toList(),
            ),
        ],
        if (purchasingState.materialRequestsError == null &&
            (purchasingState.hasMoreMaterialRequests ||
                purchasingState.isMoreMaterialRequestsLoading)) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: purchasingState.isMoreMaterialRequestsLoading
                  ? null
                  : () => context
                        .read<MaterialRequestState>()
                        .loadMoreMaterialRequests(),
              icon: purchasingState.isMoreMaterialRequestsLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(
                purchasingState.isMoreMaterialRequestsLoading
                    ? 'Memuat request...'
                    : 'Muat request lainnya',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MaterialRequestCard extends StatelessWidget {
  final MaterialRequest doc;
  final VoidCallback onTap;

  const _MaterialRequestCard({required this.doc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final date = doc.scheduleDate.isEmpty
        ? doc.transactionDate
        : doc.scheduleDate;
    final firstItem = doc.items.isNotEmpty
        ? doc.items.first.itemName
        : doc.type;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.06),
            ),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      doc.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'HankenGrotesk',
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  ErpStatusBadge(statusText: doc.statusText),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                firstItem,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      date.isEmpty ? '-' : date,
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.slate,
                      ),
                    ),
                  ),
                  Text(
                    '${formatErpCurrency(doc.totalQty)} qty',
                    style: const TextStyle(
                      fontFamily: 'HankenGrotesk',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              if (doc.company.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  doc.company,
                  style: const TextStyle(fontSize: 9, color: AppColors.slate),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialRequestSummaryCard extends StatelessWidget {
  final List<MaterialRequest> requests;

  const _MaterialRequestSummaryCard({required this.requests});

  @override
  Widget build(BuildContext context) {
    final draftCount = requests
        .where((doc) => isDocDraft(doc.docStatus))
        .length;
    final activeQty = requests.fold<double>(
      0,
      (sum, doc) => sum + doc.totalQty,
    );
    final activeCount = requests.where((doc) {
      final status = doc.statusText.toLowerCase();
      return !status.contains('cancel') &&
          !status.contains('stopped') &&
          !status.contains('ordered');
    }).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.assignment_turned_in_outlined,
                  color: AppColors.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kebutuhan Barang',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Ringkasan request sesuai filter aktif.',
                      style: TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PurchaseMetricGrid(
            children: [
              PurchaseMetricTile(
                label: 'Aktif',
                value: '$activeCount request',
                icon: Icons.pending_actions_rounded,
                color: AppColors.primary,
              ),
              PurchaseMetricTile(
                label: 'Draft',
                value: '$draftCount draft',
                icon: Icons.edit_note_rounded,
                color: AppColors.warning,
              ),
              PurchaseMetricTile(
                label: 'Qty',
                value: formatErpCurrency(activeQty),
                icon: Icons.inventory_2_outlined,
                color: AppColors.slate,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MaterialRequestFocusSummary {
  final int total;
  final int purchase;
  final int transfer;
  final int active;
  final int draft;
  final int ordered;

  const _MaterialRequestFocusSummary({
    required this.total,
    required this.purchase,
    required this.transfer,
    required this.active,
    required this.draft,
    required this.ordered,
  });

  factory _MaterialRequestFocusSummary.from(List<MaterialRequest> requests) {
    var purchase = 0;
    var transfer = 0;
    var active = 0;
    var draft = 0;
    var ordered = 0;
    for (final doc in requests) {
      final type = doc.type.toLowerCase();
      final status = doc.statusText.toLowerCase();
      if (type.contains('purchase')) purchase++;
      if (type.contains('transfer') || type.contains('material transfer')) {
        transfer++;
      }
      if (!status.contains('cancel') &&
          !status.contains('stopped') &&
          !status.contains('ordered')) {
        active++;
      }
      if (isDocDraft(doc.docStatus)) draft++;
      if (status.contains('ordered')) ordered++;
    }
    return _MaterialRequestFocusSummary(
      total: requests.length,
      purchase: purchase,
      transfer: transfer,
      active: active,
      draft: draft,
      ordered: ordered,
    );
  }

  int countFor(_MaterialRequestFocusFilter filter) {
    return switch (filter) {
      _MaterialRequestFocusFilter.all => total,
      _MaterialRequestFocusFilter.purchase => purchase,
      _MaterialRequestFocusFilter.transfer => transfer,
      _MaterialRequestFocusFilter.active => active,
      _MaterialRequestFocusFilter.draft => draft,
      _MaterialRequestFocusFilter.ordered => ordered,
    };
  }
}

class _MaterialRequestFocusCard extends StatelessWidget {
  final _MaterialRequestFocusSummary summary;
  final _MaterialRequestFocusFilter selected;
  final ValueChanged<_MaterialRequestFocusFilter> onSelected;

  const _MaterialRequestFocusCard({
    required this.summary,
    required this.selected,
    required this.onSelected,
  });

  String _label(_MaterialRequestFocusFilter filter) {
    return switch (filter) {
      _MaterialRequestFocusFilter.all => 'Semua',
      _MaterialRequestFocusFilter.purchase => 'Purchase',
      _MaterialRequestFocusFilter.transfer => 'Transfer',
      _MaterialRequestFocusFilter.active => 'Aktif',
      _MaterialRequestFocusFilter.draft => 'Draft',
      _MaterialRequestFocusFilter.ordered => 'Ordered',
    };
  }

  IconData _icon(_MaterialRequestFocusFilter filter) {
    return switch (filter) {
      _MaterialRequestFocusFilter.all => Icons.list_alt_rounded,
      _MaterialRequestFocusFilter.purchase => Icons.shopping_cart_outlined,
      _MaterialRequestFocusFilter.transfer => Icons.swap_horiz_rounded,
      _MaterialRequestFocusFilter.active => Icons.pending_actions_rounded,
      _MaterialRequestFocusFilter.draft => Icons.edit_note_rounded,
      _MaterialRequestFocusFilter.ordered => Icons.task_alt_rounded,
    };
  }

  Color _color(_MaterialRequestFocusFilter filter) {
    return switch (filter) {
      _MaterialRequestFocusFilter.all => AppColors.primary,
      _MaterialRequestFocusFilter.purchase => AppColors.primary,
      _MaterialRequestFocusFilter.transfer => AppColors.navy,
      _MaterialRequestFocusFilter.active => AppColors.warning,
      _MaterialRequestFocusFilter.draft => AppColors.slate,
      _MaterialRequestFocusFilter.ordered => AppColors.success,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filter Kebutuhan Barang',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Pisahkan request pembelian, transfer antar departemen, dan status kebutuhan.',
            style: TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _MaterialRequestFocusFilter.values.map((filter) {
              final active = selected == filter;
              final color = _color(filter);
              return ChoiceChip(
                selected: active,
                onSelected: (_) => onSelected(filter),
                avatar: Icon(
                  _icon(filter),
                  size: 16,
                  color: active ? AppColors.white : color,
                ),
                label: Text('${_label(filter)} ${summary.countFor(filter)}'),
                labelStyle: TextStyle(
                  color: active ? AppColors.white : color,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
                selectedColor: color,
                backgroundColor: color.withValues(alpha: 0.08),
                side: BorderSide(color: color.withValues(alpha: 0.18)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _MaterialRequestApprovalInfoCard extends StatelessWidget {
  const _MaterialRequestApprovalInfoCard();

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
              'Action approval akan muncul otomatis jika Workflow ERPNext untuk Material Request sudah aktif dan role user sesuai.',
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

class _PlanningCard extends StatelessWidget {
  final List<InventoryItem> items;
  final ValueChanged<InventoryItem> onPick;
  final ValueChanged<InventoryItem>? onCreateMaterialRequest;
  final ValueChanged<InventoryItem>? onCreatePurchaseOrder;

  const _PlanningCard({
    required this.items,
    required this.onPick,
    required this.onCreateMaterialRequest,
    required this.onCreatePurchaseOrder,
  });

  int _recommendedQty(InventoryItem item) {
    if (item.minStockThreshold <= 0) {
      return item.quantity <= 0 ? 1 : item.quantity;
    }
    final deficit = item.minStockThreshold - item.quantity;
    return deficit <= 0 ? 1 : deficit;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.auto_awesome_motion_outlined,
                  color: AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Rekomendasi Pembelian',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${items.length} item',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            items.isEmpty
                ? 'Belum ada item di bawah reorder level dari data inventory saat ini.'
                : 'Item stok kosong atau di bawah reorder level bisa langsung dibuatkan request.',
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...items.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${item.sku} | Stok ${item.quantity}'
                                '${item.minStockThreshold > 0 ? ' / Reorder ${item.minStockThreshold}' : ''}',
                                style: const TextStyle(
                                  color: AppColors.slate,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Saran ${_recommendedQty(item)}',
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (onCreateMaterialRequest != null)
                          OutlinedButton.icon(
                            onPressed: () => onPick(item),
                            icon: const Icon(Icons.edit_note_rounded, size: 18),
                            label: const Text('Form MR'),
                          ),
                        if (onCreateMaterialRequest != null)
                          OutlinedButton.icon(
                            onPressed: () => onCreateMaterialRequest!(item),
                            icon: const Icon(Icons.assignment_add, size: 18),
                            label: const Text('Draft MR'),
                          ),
                        if (onCreatePurchaseOrder != null)
                          FilledButton.icon(
                            onPressed: () => onCreatePurchaseOrder!(item),
                            icon: const Icon(Icons.add_shopping_cart, size: 18),
                            label: const Text('Draft PO'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
