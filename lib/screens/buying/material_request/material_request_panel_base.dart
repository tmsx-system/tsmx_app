import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import '../shared/buying_document_detail_sheet.dart';
import '../shared/purchase_ui.dart';

class MaterialRequestPanel extends StatefulWidget {
  const MaterialRequestPanel({super.key});

  @override
  State<MaterialRequestPanel> createState() => _MaterialRequestPanelState();
}

class _MaterialRequestPanelState extends State<MaterialRequestPanel> {
  String _search = '';
  String? _statusFilter;
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
      return matchSearch && matchStatus;
    }).toList();
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
            const ErpEmptyState(
              title: 'Belum ada request',
              message:
                  'Gunakan tombol Buat Request untuk mengajukan kebutuhan.',
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

