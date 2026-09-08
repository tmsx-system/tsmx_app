import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../models/purchase_receipt.dart';
import '../../../models/quality_inspection_record.dart';
import '../../../../state/purchasing/purchase_receipt_state.dart';
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
import '../shared/buying_document_detail_sheet.dart';
import '../shared/purchase_ui.dart';

class PurchaseReceiptPanel extends StatefulWidget {
  const PurchaseReceiptPanel({super.key});

  @override
  State<PurchaseReceiptPanel> createState() => _PurchaseReceiptPanelState();
}

class _PurchaseReceiptPanelState extends State<PurchaseReceiptPanel> {
  final ImagePicker _picker = ImagePicker();
  String _search = '';
  DeliveryNoteStatusKey? _statusFilter;
  Timer? _searchDebounce;
  int _attachmentRefreshKey = 0;

  static final _chips = <ErpStatusChip<DeliveryNoteStatusKey?>>[
    const ErpStatusChip(label: 'All', value: null),
    const ErpStatusChip(label: 'Draft', value: DeliveryNoteStatusKey.draft),
    const ErpStatusChip(label: 'To Bill', value: DeliveryNoteStatusKey.toBill),
    const ErpStatusChip(
      label: 'Completed',
      value: DeliveryNoteStatusKey.completed,
    ),
    const ErpStatusChip(
      label: 'Return Issued',
      value: DeliveryNoteStatusKey.returnIssued,
    ),
    const ErpStatusChip(
      label: 'Return',
      value: DeliveryNoteStatusKey.returnDoc,
    ),
    const ErpStatusChip(
      label: 'Cancelled',
      value: DeliveryNoteStatusKey.cancelled,
    ),
    const ErpStatusChip(label: 'Closed', value: DeliveryNoteStatusKey.closed),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final purchasingState = context.read<PurchaseReceiptState>();
      if (purchasingState.purchaseReceipts.isEmpty) {
        purchasingState.refreshPurchaseReceipts();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  String? get _statusText => switch (_statusFilter) {
    DeliveryNoteStatusKey.draft => 'Draft',
    DeliveryNoteStatusKey.toBill => 'To Bill',
    DeliveryNoteStatusKey.completed => 'Completed',
    DeliveryNoteStatusKey.returnIssued => 'Return Issued',
    DeliveryNoteStatusKey.returnDoc => 'Return',
    DeliveryNoteStatusKey.cancelled => 'Cancelled',
    DeliveryNoteStatusKey.closed => 'Closed',
    _ => null,
  };

  void _searchChanged(String value) {
    setState(() => _search = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      context.read<PurchaseReceiptState>().setPurchaseReceiptQuery(
        search: value,
        status: _statusText,
      );
    });
  }

  List<PurchaseReceipt> _filter(List<PurchaseReceipt> docs) {
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

  Future<void> _openDetail(PurchaseReceipt doc) async {
    final detail = await context
        .read<PurchaseReceiptState>()
        .loadPurchaseReceiptDetail(doc.id);
    if (!mounted) return;

    final canSubmit = isDocDraft(detail.docStatus);

    showBuyingDocumentDetailSheet(
      context: context,
      title: detail.id,
      subtitle: detail.supplier,
      statusText: detail.statusText,
      icon: Icons.move_to_inbox_rounded,
      metrics: [
        BuyingDetailMetric(
          label: 'Total',
          value: 'Rp ${formatErpCurrency(detail.value)}',
          icon: Icons.payments_outlined,
        ),
        BuyingDetailMetric(
          label: 'Item',
          value: '${detail.itemsCount}',
          icon: Icons.inventory_2_outlined,
        ),
      ],
      infos: [
        BuyingDetailInfo(
          label: 'Status Dokumen',
          value: docStatusLabel(detail.docStatus),
        ),
        BuyingDetailInfo(label: 'Posting Date', value: detail.date),
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
              note: _receiptItemNote(i),
            ),
          )
          .toList(),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReceiptVarianceCard(receipt: detail),
          const SizedBox(height: 10),
          _ReceiptQcCard(receipt: detail, onCreate: _openQcForm),
          const SizedBox(height: 12),
          erpActionButton(
            label: 'Upload Foto Penerimaan',
            icon: Icons.add_a_photo_outlined,
            onPressed: () => _pickAndUploadEvidence(detail.id),
          ),
          const SizedBox(height: 10),
          _ReceiptAttachmentPreviewCard(
            key: ValueKey('${detail.id}-$_attachmentRefreshKey'),
            receiptId: detail.id,
          ),
          if (canSubmit) ...[
            const SizedBox(height: 10),
            erpActionButton(
              label: 'Ajukan Purchase Receipt',
              icon: Icons.check_circle_outline_rounded,
              filled: true,
              onPressed: () => _submit(detail.id),
            ),
          ],
        ],
      ),
    );
  }

  String _receiptItemNote(PurchaseReceiptItem item) {
    final parts = <String>[
      if (item.warehouse.isNotEmpty) item.warehouse,
      if (item.purchaseOrder.isNotEmpty) item.purchaseOrder,
      if (item.qualityInspection.isNotEmpty) item.qualityInspection,
    ];
    return parts.join(' | ');
  }

  Future<void> _pickAndUploadEvidence(String receiptId) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Ambil foto dengan kamera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Pilih foto dari galeri'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;

    final photo = await _picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (photo == null || !mounted) return;

    try {
      await context.read<PurchaseReceiptState>().uploadAttachment(
        doctype: 'Purchase Receipt',
        documentName: receiptId,
        filePath: photo.path,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Foto penerimaan terpasang ke $receiptId.'),
          backgroundColor: AppColors.success,
        ),
      );
      setState(() => _attachmentRefreshKey++);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyUploadError(error)),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _openQcForm(PurchaseReceipt receipt) async {
    if (receipt.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item receipt belum tersedia untuk dibuatkan QC.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CreateReceiptQcSheet(receipt: receipt),
    );
    if (created == true && mounted) {
      await context.read<PurchaseReceiptState>().refreshPurchaseReceipts();
    }
  }

  String _friendlyUploadError(Object error) {
    final message = error.toString();
    if (message.contains('File') || message.contains('permission')) {
      return 'Upload foto belum bisa. Cek permission File di ERPNext.';
    }
    return 'Upload foto gagal. Coba lagi setelah koneksi stabil.';
  }

  Future<void> _submit(String id) async {
    if (!await confirmErpAction(
      context,
      title: 'Submit Purchase Receipt?',
      message: 'Submit $id?',
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await runErpWorkflowAction(
      context,
      action: () => context.read<PurchaseReceiptState>().submitDocument(
        'Purchase Receipt',
        id,
      ),
      successMessage: 'Purchase Receipt submitted',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final purchasingState = context.watch<PurchaseReceiptState>();
    final filtered = _filter(purchasingState.purchaseReceipts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DocumentTrendCard(
          title: 'Purchase Receipt',
          emptyMessage:
              'Belum ada nilai Purchase Receipt dari Purchase Analytics pada periode ini.',
          points: purchasingState.purchaseReceiptTrendPoints,
          selectedYear: purchasingState.buyingPeriodYear,
          selectedMonth: purchasingState.buyingPeriodMonth,
          sourceLabel: 'Sumber: Purchase Analytics ERPNext',
        ),
        const SizedBox(height: 12),
        PurchaseSearchField(
          onChanged: _searchChanged,
          hintText: 'Cari receipt atau supplier',
        ),
        if (purchasingState.purchaseReceiptsError != null) ...[
          const SizedBox(height: 10),
          ErpErrorBox(message: purchasingState.purchaseReceiptsError!),
        ],
        const SizedBox(height: 10),
        ErpStatusChipBar<DeliveryNoteStatusKey?>(
          chips: _chips,
          selected: _statusFilter,
          onSelected: (v) {
            setState(() => _statusFilter = v);
            context.read<PurchaseReceiptState>().setPurchaseReceiptQuery(
              search: _search,
              status: _statusText,
            );
          },
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty && !purchasingState.isPurchaseReceiptsLoading)
          const ErpEmptyState(
            title: 'Belum ada Purchase Receipt',
            message: 'Gunakan tombol Terima Barang untuk mencatat penerimaan.',
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
        if (purchasingState.hasMorePurchaseReceipts ||
            purchasingState.isMorePurchaseReceiptsLoading) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: purchasingState.isMorePurchaseReceiptsLoading
                  ? null
                  : () => context
                        .read<PurchaseReceiptState>()
                        .loadMorePurchaseReceipts(),
              icon: purchasingState.isMorePurchaseReceiptsLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(
                purchasingState.isMorePurchaseReceiptsLoading
                    ? 'Memuat receipt...'
                    : 'Muat receipt lainnya',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReceiptVarianceCard extends StatelessWidget {
  final PurchaseReceipt receipt;

  const _ReceiptVarianceCard({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final hasItems = receipt.items.isNotEmpty;
    final hasVariance = receipt.totalVarianceQty.abs() > 0.0001;

    return _ReceiptInfoCard(
      icon: Icons.rule_folder_outlined,
      title: 'Tracking Selisih Quantity',
      subtitle: hasItems
          ? 'Pantau qty diterima, accepted, rejected, dan selisih.'
          : 'Detail item belum tersedia untuk menghitung selisih.',
      child: hasItems
          ? Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ReceiptMiniStat(
                        label: 'Received',
                        value: formatErpCurrency(receipt.totalReceivedQty),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ReceiptMiniStat(
                        label: 'Accepted',
                        value: formatErpCurrency(receipt.totalAcceptedQty),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ReceiptMiniStat(
                        label: 'Rejected',
                        value: formatErpCurrency(receipt.totalRejectedQty),
                        warning: receipt.totalRejectedQty > 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ...receipt.items.map(_ReceiptVarianceLine.new),
                if (!hasVariance) ...[
                  const SizedBox(height: 8),
                  const _ReceiptNote(
                    icon: Icons.check_circle_outline_rounded,
                    message:
                        'Belum ada selisih qty tercatat pada item penerimaan ini.',
                    success: true,
                  ),
                ],
              ],
            )
          : const _ReceiptNote(
              icon: Icons.info_outline_rounded,
              message:
                  'Detail item belum bisa dibaca. Cek permission Purchase Receipt Item jika data tidak muncul.',
            ),
    );
  }
}

class _ReceiptQcCard extends StatefulWidget {
  final PurchaseReceipt receipt;
  final ValueChanged<PurchaseReceipt> onCreate;

  const _ReceiptQcCard({required this.receipt, required this.onCreate});

  @override
  State<_ReceiptQcCard> createState() => _ReceiptQcCardState();
}

class _ReceiptQcCardState extends State<_ReceiptQcCard> {
  late Future<List<QualityInspectionRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _ReceiptQcCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receipt.id != widget.receipt.id) {
      _future = _load();
    }
  }

  Future<List<QualityInspectionRecord>> _load() {
    return context
        .read<PurchaseReceiptState>()
        .fetchQualityInspectionsForReceipt(widget.receipt.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QualityInspectionRecord>>(
      future: _future,
      builder: (context, snapshot) {
        final records = snapshot.data ?? const <QualityInspectionRecord>[];
        final fallbackRefs = widget.receipt.items
            .where((item) => item.qualityInspection.isNotEmpty)
            .toList();
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final hasError = snapshot.hasError;

        return _ReceiptInfoCard(
          icon: Icons.fact_check_outlined,
          title: 'QC Penerimaan',
          subtitle: loading
              ? 'Memuat Quality Inspection...'
              : records.isNotEmpty
              ? '${records.length} Quality Inspection terhubung.'
              : fallbackRefs.isNotEmpty
              ? '${fallbackRefs.length} referensi QC pada item receipt.'
              : 'QC belum terhubung, penerimaan tetap bisa dipantau.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (loading) const LinearProgressIndicator(),
              if (hasError)
                const _ReceiptNote(
                  icon: Icons.info_outline_rounded,
                  message:
                      'QC belum bisa dibaca. Cek permission Quality Inspection di ERPNext.',
                )
              else if (records.isNotEmpty)
                ...records.map(_QualityInspectionTile.new)
              else if (fallbackRefs.isNotEmpty)
                ...fallbackRefs.map(
                  (item) => _ReceiptReferenceRow(
                    title: item.qualityInspection,
                    subtitle: item.itemName,
                    icon: Icons.verified_outlined,
                  ),
                )
              else
                const _ReceiptNote(
                  icon: Icons.info_outline_rounded,
                  message:
                      'Belum ada Quality Inspection terhubung untuk receipt ini.',
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => widget.onCreate(widget.receipt),
                icon: Icon(
                  records.isEmpty && fallbackRefs.isEmpty
                      ? Icons.fact_check_outlined
                      : Icons.add_task_outlined,
                ),
                label: Text(
                  records.isEmpty && fallbackRefs.isEmpty
                      ? 'Buat QC Penerimaan'
                      : 'Tambah QC',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReceiptInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _ReceiptInfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
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
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
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
          child,
        ],
      ),
    );
  }
}

class _QualityInspectionTile extends StatelessWidget {
  final QualityInspectionRecord record;

  const _QualityInspectionTile(this.record);

  bool get _accepted => record.status.toLowerCase().contains('accept');

  String get _dateText {
    final date = record.reportDate;
    if (date == null) return '-';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _accepted ? AppColors.success : AppColors.danger;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              _accepted ? Icons.verified_outlined : Icons.report_outlined,
              color: color,
              size: 18,
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
                        record.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        record.status.isEmpty ? '-' : record.status,
                        style: TextStyle(
                          color: color,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  record.itemName.isEmpty ? record.itemCode : record.itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    _dateText,
                    if (record.inspectedBy.isNotEmpty) record.inspectedBy,
                  ].join(' | '),
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (record.remarks.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    record.remarks,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateReceiptQcSheet extends StatefulWidget {
  final PurchaseReceipt receipt;

  const _CreateReceiptQcSheet({required this.receipt});

  @override
  State<_CreateReceiptQcSheet> createState() => _CreateReceiptQcSheetState();
}

class _CreateReceiptQcSheetState extends State<_CreateReceiptQcSheet> {
  final _remarksCtrl = TextEditingController();
  final _inspectedByCtrl = TextEditingController();
  late PurchaseReceiptItem _selectedItem;
  String _status = 'Accepted';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedItem = widget.receipt.items.first;
  }

  @override
  void dispose() {
    _remarksCtrl.dispose();
    _inspectedByCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final record = await context
          .read<PurchaseReceiptState>()
          .createIncomingQualityInspection(
            purchaseReceiptId: widget.receipt.id,
            itemCode: _selectedItem.itemCode,
            status: _status,
            inspectedBy: _inspectedByCtrl.text,
            remarks: _remarksCtrl.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('QC ${record.name} berhasil dibuat.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyQcError(error)),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _friendlyQcError(Object error) {
    final message = error.toString();
    if (message.contains('Quality Inspection Template')) {
      return 'QC gagal. Item ini perlu Quality Inspection Template di ERPNext.';
    }
    if (message.contains('permission') || message.contains('Permission')) {
      return 'QC gagal. Cek permission Quality Inspection di ERPNext.';
    }
    return 'QC gagal dibuat. $message';
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
                'Buat QC Penerimaan',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<PurchaseReceiptItem>(
                initialValue: _selectedItem,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Item',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                items: widget.receipt.items
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
                  if (item != null) setState(() => _selectedItem = item);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status QC',
                  prefixIcon: Icon(Icons.verified_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'Accepted', child: Text('Accepted')),
                  DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _inspectedByCtrl,
                decoration: const InputDecoration(
                  labelText: 'Inspected By',
                  hintText: 'Opsional',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _remarksCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Catatan QC',
                  hintText: 'Opsional',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Menyimpan...' : 'Simpan QC'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptAttachmentPreviewCard extends StatefulWidget {
  final String receiptId;

  const _ReceiptAttachmentPreviewCard({super.key, required this.receiptId});

  @override
  State<_ReceiptAttachmentPreviewCard> createState() =>
      _ReceiptAttachmentPreviewCardState();
}

class _ReceiptAttachmentPreviewCardState
    extends State<_ReceiptAttachmentPreviewCard> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _ReceiptAttachmentPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.receiptId != widget.receiptId) {
      _future = _load();
    }
  }

  Future<List<Map<String, dynamic>>> _load() {
    return context.read<PurchaseReceiptState>().fetchDocumentAttachments(
      doctype: 'Purchase Receipt',
      documentName: widget.receiptId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final purchasingState = context.read<PurchaseReceiptState>();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        if (snapshot.hasError) {
          return _ReceiptInfoCard(
            icon: Icons.attach_file_outlined,
            title: 'Foto Penerimaan',
            subtitle: 'Preview attachment belum bisa dibaca.',
            child: _ReceiptNote(
              icon: Icons.info_outline_rounded,
              message: 'Cek permission File di ERPNext jika foto tidak muncul.',
            ),
          );
        }

        final files = snapshot.data ?? const <Map<String, dynamic>>[];
        return _ReceiptInfoCard(
          icon: Icons.photo_library_outlined,
          title: 'Foto Penerimaan',
          subtitle: files.isEmpty
              ? 'Belum ada attachment pada receipt ini.'
              : '${files.length} attachment terpasang.',
          child: files.isEmpty
              ? const _ReceiptNote(
                  icon: Icons.info_outline_rounded,
                  message: 'Upload foto penerimaan untuk dokumentasi receipt.',
                )
              : Column(
                  children: files
                      .map(
                        (file) => _ReceiptAttachmentTile(
                          file: file,
                          baseUrl: purchasingState.frappeService.baseUrl,
                        ),
                      )
                      .toList(),
                ),
        );
      },
    );
  }
}

class _ReceiptAttachmentTile extends StatelessWidget {
  final Map<String, dynamic> file;
  final String baseUrl;

  const _ReceiptAttachmentTile({required this.file, required this.baseUrl});

  bool get _isImage {
    final name = (file['file_name'] ?? file['file_url'] ?? '')
        .toString()
        .toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp');
  }

  String get _fileName =>
      file['file_name']?.toString() ?? file['name']?.toString() ?? 'Attachment';

  String get _url {
    final raw = file['file_url']?.toString() ?? '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) return '$baseUrl$raw';
    return raw.isEmpty ? '' : '$baseUrl/$raw';
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: _isImage && url.isNotEmpty
            ? Image.network(
                url,
                cacheWidth: 160,
                cacheHeight: 160,
                filterQuality: FilterQuality.medium,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.slate,
                ),
              )
            : const ColoredBox(
                color: AppColors.white,
                child: Icon(
                  Icons.insert_drive_file_outlined,
                  color: AppColors.slate,
                ),
              ),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _isImage && url.isNotEmpty
              ? InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _ReceiptAttachmentPreviewPage(
                        title: _fileName,
                        imageUrl: url,
                      ),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(10),
                  child: preview,
                )
              : preview,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  file['creation']?.toString() ?? url,
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
        ],
      ),
    );
  }
}

class _ReceiptAttachmentPreviewPage extends StatelessWidget {
  final String title;
  final String imageUrl;

  const _ReceiptAttachmentPreviewPage({
    required this.title,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.75,
          maxScale: 4,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Foto tidak bisa ditampilkan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiptMiniStat extends StatelessWidget {
  final String label;
  final String value;
  final bool warning;

  const _ReceiptMiniStat({
    required this.label,
    required this.value,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: warning
            ? AppColors.danger.withValues(alpha: 0.08)
            : AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: warning ? AppColors.danger : AppColors.slate,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: warning ? AppColors.danger : AppColors.navy,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptVarianceLine extends StatelessWidget {
  final PurchaseReceiptItem item;

  const _ReceiptVarianceLine(this.item);

  @override
  Widget build(BuildContext context) {
    final variance = item.varianceQty;
    final hasVariance = variance.abs() > 0.0001;
    final uom = item.uom.isEmpty ? '' : ' ${item.uom}';
    final poText = item.purchaseOrder.isEmpty
        ? 'PO reference belum tercatat'
        : item.purchaseOrder;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: hasVariance
                  ? AppColors.warning.withValues(alpha: 0.14)
                  : AppColors.softGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              hasVariance ? Icons.priority_high_rounded : Icons.check_rounded,
              color: hasVariance ? AppColors.warning : AppColors.primary,
              size: 17,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  poText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Received ${formatErpCurrency(item.receivedQty)}$uom | '
                  'Checked ${formatErpCurrency(item.checkedQty)}$uom',
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
          Text(
            '${variance >= 0 ? '+' : ''}${formatErpCurrency(variance)}',
            style: TextStyle(
              color: hasVariance ? AppColors.warning : AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptReferenceRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ReceiptReferenceRow({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
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
        ],
      ),
    );
  }
}

class _ReceiptNote extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool success;

  const _ReceiptNote({
    required this.icon,
    required this.message,
    this.success = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: success
            ? AppColors.softGreen
            : AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: success ? AppColors.primary : AppColors.warning,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: success ? AppColors.primary : AppColors.navy,
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
