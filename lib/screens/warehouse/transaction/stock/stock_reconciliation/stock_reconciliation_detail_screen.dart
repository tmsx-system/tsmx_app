import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../models/stock_entry.dart';
import '../../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../../theme/app_colors.dart';
import '../../../../../utils/erp_doc_utils.dart';
import '../../../../../utils/erp_format.dart';
import '../../../../../utils/erp_share_file.dart';
import '../../../../../widgets/erp/erp_status_badge.dart';
import '../../../../../widgets/erp/erp_workflow_helper.dart';
import '../../../shared/warehouse_widgets.dart';
import '../../../../../widgets/print/erp_bluetooth_print.dart';

class StockReconciliationDetailScreen extends StatefulWidget {
  final String reconciliationId;

  const StockReconciliationDetailScreen({
    super.key,
    required this.reconciliationId,
  });

  @override
  State<StockReconciliationDetailScreen> createState() =>
      _StockReconciliationDetailScreenState();
}

class _StockReconciliationDetailScreenState
    extends State<StockReconciliationDetailScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  StockReconciliationDetail? _detail;
  bool _canSubmit = false;
  bool _canPrint = false;

  bool get _isDraft => _detail != null && isDocDraft(_detail!.docStatus);
  bool get _showDownloadPdf => _canPrint;
  bool get _showPrint => _canPrint;
  bool get _showSubmit => _canSubmit && _isDraft;
  bool get _hasActions => _showDownloadPdf || _showPrint || _showSubmit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<WarehouseStockState>();
      final results = await Future.wait([
        state.fetchStockReconciliationDetail(widget.reconciliationId),
        state.canSubmitDoctype('Stock Reconciliation'),
        state.canPrintDoctype('Stock Reconciliation'),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = results[0] as StockReconciliationDetail;
        _canSubmit = results[1] as bool;
        _canPrint = results[2] as bool;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error
            .toString()
            .replaceFirst(RegExp(r'^Exception:\s*'), '')
            .replaceAll(RegExp(r'<[^>]*>'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<int>> _downloadPdfBytes() {
    return context.read<WarehouseStockState>().downloadStockReconciliationPdf(
      widget.reconciliationId,
    );
  }

  Future<SavedShareFile> _savePdfFile(List<int> bytes) {
    return saveBytesForUser(
      bytes: bytes,
      fileName: '${widget.reconciliationId}.pdf',
      mimeType: 'application/pdf',
      appSubfolder: 'stock_reconciliation_pdf',
    );
  }

  Future<void> _downloadPdf() async {
    await _runBusy(() async {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Mengunduh PDF Stock Reconciliation ${widget.reconciliationId}...',
          ),
        ),
      );
      try {
        final saved = await _savePdfFile(await _downloadPdfBytes());
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              saved.savedToDownloads
                  ? 'PDF tersimpan di ${saved.locationLabel}. Bisa dibuka dari Files/Download.'
                  : 'PDF siap dibagikan: ${saved.locationLabel}',
            ),
          ),
        );
        await shareSavedFile(
          saved,
          subject: 'Stock Reconciliation ${widget.reconciliationId}',
        );
      } catch (error) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Gagal download PDF: $error')),
        );
      }
    });
  }

  Future<void> _printPdf() async {
    await _runBusy(() async {
      await printErpPdfViaBluetooth(
        context,
        downloadPdf: _downloadPdfBytes,
        title: 'Stock Reconciliation ${widget.reconciliationId}',
      );
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final confirmed = await confirmErpAction(
      context,
      title: 'Submit Stock Reconciliation?',
      message: 'Submit ${widget.reconciliationId} ke ERPNext?',
    );
    if (!confirmed || !mounted) return;
    await _runBusy(() async {
      final ok = await runErpWorkflowAction(
        context,
        action: () => context.read<WarehouseStockState>().submitDocument(
          'Stock Reconciliation',
          widget.reconciliationId,
        ),
        successMessage:
            'Stock Reconciliation ${widget.reconciliationId} berhasil di-submit.',
      );
      if (ok && mounted) {
        await _load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.reconciliationId,
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: warehousePagePaddingOf(context),
                children: [
                  if (_error != null)
                    WarehouseInfoPanel(
                      icon: Icons.error_outline_rounded,
                      color: AppColors.danger,
                      message: _error!,
                    )
                  else if (detail != null) ...[
                    WarehouseSectionHeader(
                      title: detail.purpose.isEmpty
                          ? 'Stock Reconciliation'
                          : detail.purpose,
                      subtitle: [
                        if (detail.company.isNotEmpty) detail.company,
                        detail.statusText,
                      ].join(' · '),
                      icon: Icons.fact_check_outlined,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: WarehouseMetricTile(
                            label: 'Selisih nilai',
                            value:
                                'Rp ${formatErpCurrency(detail.differenceAmount)}',
                            icon: Icons.payments_outlined,
                            color: warehousePurple,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: WarehouseMetricTile(
                            label: 'Baris item',
                            value: '${detail.items.length}',
                            icon: Icons.inventory_2_outlined,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    WarehouseModernCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  detail.id,
                                  style: const TextStyle(
                                    color: AppColors.navy,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              ErpStatusBadge(statusText: detail.statusText),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _pill(
                                Icons.apartment_outlined,
                                detail.company,
                              ),
                              _pill(
                                Icons.calendar_month_outlined,
                                [
                                  detail.postingDate,
                                  if (detail.postingTime.isNotEmpty)
                                    detail.postingTime,
                                ].join(' · '),
                              ),
                              _pill(
                                Icons.warehouse_outlined,
                                detail.warehouse,
                              ),
                              _pill(
                                Icons.account_balance_outlined,
                                detail.expenseAccount,
                              ),
                              _pill(
                                Icons.hub_outlined,
                                detail.costCenter,
                              ),
                            ],
                          ),
                          if (detail.remarks.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              detail.remarks,
                              style: const TextStyle(
                                color: AppColors.slate,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    warehouseSectionGap,
                    const WarehouseSectionHeader(
                      title: 'Items',
                      subtitle: 'Qty sistem vs qty fisik',
                      icon: Icons.inventory_2_outlined,
                    ),
                    const SizedBox(height: 12),
                    if (detail.items.isEmpty)
                      const WarehouseInfoPanel(
                        icon: Icons.inbox_outlined,
                        color: AppColors.slate,
                        message: 'Tidak ada item pada dokumen ini.',
                      )
                    else
                      ...detail.items.asMap().entries.map(
                        (entry) => _itemCard(entry.key, entry.value),
                      ),
                    if (_hasActions) ...[
                      warehouseSectionGap,
                      const WarehouseSectionHeader(
                        title: 'Actions',
                        subtitle: 'Hanya tombol yang diizinkan role Anda',
                        icon: Icons.tune_rounded,
                      ),
                      const SizedBox(height: 12),
                      if (_showDownloadPdf)
                        erpActionButton(
                          label: 'Download PDF',
                          icon: Icons.picture_as_pdf_outlined,
                          onPressed: _busy ? null : _downloadPdf,
                        ),
                      if (_showPrint)
                        erpActionButton(
                          label: 'Print',
                          icon: Icons.print_outlined,
                          onPressed: _busy ? null : _printPdf,
                        ),
                      if (_showSubmit)
                        erpActionButton(
                          label: 'Submit',
                          icon: Icons.check_circle_outline_rounded,
                          filled: true,
                          onPressed: _busy ? null : _submit,
                        ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _pill(IconData icon, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.slate),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyBox(String label, String value, {Color? color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: (color ?? AppColors.navy).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                color: color ?? AppColors.navy,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemCard(int index, StockReconciliationItemLine item) {
    final diff = item.qtyDifference;
    final diffColor = diff == 0
        ? AppColors.slate
        : (diff > 0 ? warehouseGreen : AppColors.danger);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WarehouseModernCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.itemCode,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '#${index + 1}',
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (item.itemName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                item.itemName,
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                _qtyBox(
                  'Qty sistem',
                  '${item.currentQty}${item.uom.isEmpty ? '' : ' ${item.uom}'}',
                ),
                const SizedBox(width: 8),
                _qtyBox(
                  'Qty fisik',
                  '${item.qty}${item.uom.isEmpty ? '' : ' ${item.uom}'}',
                ),
                const SizedBox(width: 8),
                _qtyBox(
                  'Selisih',
                  '${diff > 0 ? '+' : ''}$diff',
                  color: diffColor,
                ),
              ],
            ),
            if (item.warehouse.isNotEmpty ||
                item.batchNo.isNotEmpty ||
                item.valuationRate > 0) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(Icons.warehouse_outlined, item.warehouse),
                  _pill(
                    Icons.qr_code_2_rounded,
                    item.batchNo.isEmpty ? '' : 'Batch ${item.batchNo}',
                  ),
                  _pill(
                    Icons.payments_outlined,
                    item.valuationRate > 0
                        ? 'Rate Rp ${formatErpCurrency(item.valuationRate)}'
                        : '',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
