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
import 'create_stock_entry_screen.dart';
import 'stock_entry_kind.dart';

class StockEntryDetailScreen extends StatefulWidget {
  final String stockEntryId;

  const StockEntryDetailScreen({super.key, required this.stockEntryId});

  @override
  State<StockEntryDetailScreen> createState() => _StockEntryDetailScreenState();
}

class _StockEntryDetailScreenState extends State<StockEntryDetailScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  StockEntryDetail? _detail;
  bool _canWrite = false;
  bool _canSubmit = false;
  bool _canPrint = false;

  bool get _isDraft =>
      _detail != null && isDocDraft(_detail!.docStatus);

  bool get _showDownloadPdf => _canPrint;
  bool get _showPrint => _canPrint;
  bool get _showEdit => _canWrite && _isDraft;
  bool get _showSubmit => _canSubmit && _isDraft;
  bool get _hasActions =>
      _showDownloadPdf || _showPrint || _showEdit || _showSubmit;

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
        state.fetchStockEntryDetail(widget.stockEntryId),
        state.canWriteDoctype('Stock Entry'),
        state.canSubmitDoctype('Stock Entry'),
        state.canPrintDoctype('Stock Entry'),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = results[0] as StockEntryDetail;
        _canWrite = results[1] as bool;
        _canSubmit = results[2] as bool;
        _canPrint = results[3] as bool;
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
    return context.read<WarehouseStockState>().downloadStockEntryPdf(
      widget.stockEntryId,
    );
  }

  Future<SavedShareFile> _savePdfFile(List<int> bytes) {
    return saveBytesForUser(
      bytes: bytes,
      fileName: '${widget.stockEntryId}.pdf',
      mimeType: 'application/pdf',
      appSubfolder: 'stock_entry_pdf',
    );
  }

  Future<void> _downloadPdf() async {
    await _runBusy(() async {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Mengunduh PDF Stock Entry ${widget.stockEntryId}...'),
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
          subject: 'Stock Entry ${widget.stockEntryId}',
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
        title: 'Stock Entry ${widget.stockEntryId}',
      );
    });
  }

  Future<void> _edit() async {
    final detail = _detail;
    if (detail == null || _busy) return;
    await _runBusy(() async {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => CreateStockEntryScreen(
            kind: StockEntryKind(
              name: detail.stockEntryType.isEmpty
                  ? 'Stock Entry'
                  : detail.stockEntryType,
              purpose: detail.purpose.isEmpty
                  ? detail.stockEntryType
                  : detail.purpose,
            ),
            company: detail.company,
            sourceWarehouse: detail.fromWarehouse,
            targetWarehouse: detail.toWarehouse,
            existingName: detail.id,
          ),
        ),
      );
      if (saved == true && mounted) {
        await _load();
      }
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final confirmed = await confirmErpAction(
      context,
      title: 'Submit Stock Entry?',
      message: 'Submit ${widget.stockEntryId} ke ERPNext?',
    );
    if (!confirmed || !mounted) return;
    await _runBusy(() async {
      final ok = await runErpWorkflowAction(
        context,
        action: () => context.read<WarehouseStockState>().submitDocument(
          'Stock Entry',
          widget.stockEntryId,
        ),
        successMessage: 'Stock Entry ${widget.stockEntryId} berhasil di-submit.',
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
          widget.stockEntryId,
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
                      title: detail.stockEntryType.isEmpty
                          ? 'Stock Entry'
                          : detail.stockEntryType,
                      subtitle: [
                        if (detail.company.isNotEmpty) detail.company,
                        detail.statusText,
                      ].join(' · '),
                      icon: Icons.swap_horiz_rounded,
                    ),
                    const SizedBox(height: 14),
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
                          _info('Purpose', detail.purpose),
                          _info('Company', detail.company),
                          _info(
                            'Posting Date',
                            [
                              detail.postingDate,
                              if (detail.postingTime.isNotEmpty)
                                detail.postingTime,
                            ].join(' · '),
                          ),
                          _info('Source Warehouse', detail.fromWarehouse),
                          _info('Target Warehouse', detail.toWarehouse),
                          _info(
                            'Total Qty',
                            detail.totalQty == 0
                                ? '${detail.items.length} item'
                                : detail.totalQty.toString(),
                          ),
                          if (detail.remarks.trim().isNotEmpty)
                            _info('Remarks', detail.remarks),
                        ],
                      ),
                    ),
                    warehouseSectionGap,
                    const WarehouseSectionHeader(
                      title: 'Items',
                      subtitle: 'Baris item Stock Entry',
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
                      if (_showEdit)
                        erpActionButton(
                          label: 'Edit',
                          icon: Icons.edit_outlined,
                          onPressed: _busy ? null : _edit,
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

  Widget _info(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemCard(int index, StockEntryItemLine item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: WarehouseModernCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Item ${index + 1}',
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.itemCode,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w900,
              ),
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
            Text(
              [
                'Qty ${item.qty}',
                if (item.uom.isNotEmpty) item.uom,
                if (item.basicRate > 0)
                  'Rate Rp ${formatErpCurrency(item.basicRate)}',
                if (item.amount > 0)
                  'Amount Rp ${formatErpCurrency(item.amount)}',
              ].join(' · '),
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (item.sourceWarehouse.isNotEmpty ||
                item.targetWarehouse.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (item.sourceWarehouse.isNotEmpty)
                    'Dari ${item.sourceWarehouse}',
                  if (item.targetWarehouse.isNotEmpty)
                    'Ke ${item.targetWarehouse}',
                ].join(' → '),
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
