import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/material_request.dart';
import '../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../theme/app_colors.dart';
import '../../../../utils/erp_doc_utils.dart';
import '../../../../utils/erp_error_message.dart';
import '../../../../utils/erp_share_file.dart';
import '../../../../widgets/erp/erp_status_badge.dart';
import '../../../../widgets/erp/erp_workflow_helper.dart';
import '../../../../widgets/print/erp_bluetooth_print.dart';
import '../../../../widgets/responsive/responsive_layout.dart';
import 'create_material_transfer_request_screen.dart';
import 'material_request_purpose.dart';

class MaterialRequestDetailScreen extends StatefulWidget {
  final MaterialRequest request;
  final bool canEdit;

  const MaterialRequestDetailScreen({
    super.key,
    required this.request,
    this.canEdit = false,
  });

  @override
  State<MaterialRequestDetailScreen> createState() =>
      _MaterialRequestDetailScreenState();
}

class _MaterialRequestDetailScreenState
    extends State<MaterialRequestDetailScreen> {
  late MaterialRequest _request = widget.request;
  bool _loading = true;
  bool _busy = false;
  bool _edited = false;
  bool _canWrite = false;
  bool _canSubmit = false;
  bool _canPrint = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  MaterialRequestPurpose get _purpose => MaterialRequestPurpose.all.firstWhere(
    (row) => row.name.toLowerCase() == _request.type.toLowerCase(),
    orElse: () => MaterialRequestPurpose.all.first,
  );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<WarehouseStockState>();
      final results = await Future.wait([
        state.frappeService.fetchDocument('Material Request', widget.request.id),
        state.canWriteDoctype('Material Request'),
        state.canSubmitDoctype('Material Request'),
        state.canPrintDoctype('Material Request'),
      ]);
      if (!mounted) return;
      setState(() {
        _request = MaterialRequest.fromJson(
          results[0] as Map<String, dynamic>,
        );
        _canWrite = results[1] as bool;
        _canSubmit = results[2] as bool;
        _canPrint = results[3] as bool;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = captureErpError(
          context,
          error,
          action: 'membuka Material Request',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _request.sourceWarehouse.isNotEmpty
        ? _request.sourceWarehouse
        : _firstItemValue((item) => item.fromWarehouse);
    final target = _request.targetWarehouse.isNotEmpty
        ? _request.targetWarehouse
        : _firstItemValue((item) => item.warehouse);
    final draft = isDocDraft(_request.docStatus);
    final canEdit = _canWrite && draft;
    final canSubmit = _canSubmit && draft;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_edited);
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.primary,
        actions: [
          if (canEdit)
            TextButton.icon(
              onPressed: _loading ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
        ],
        title: Text(
          _request.id,
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ),
      body: ListView(
        padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 28),
        children: [
          TmsxResponsiveBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppColors.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: _purpose.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(_purpose.icon, color: _purpose.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _request.type,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _purpose.summary,
                              style: const TextStyle(
                                color: AppColors.slate,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ErpStatusBadge(statusText: _request.statusText),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _InfoCard(
                  rows: [
                    _InfoRow('Company', _request.company),
                    if (_request.customer.isNotEmpty)
                      _InfoRow('Customer', _request.customer),
                    if (_request.buyingPriceList.isNotEmpty)
                      _InfoRow('Price List', _request.buyingPriceList),
                    _InfoRow('Tanggal', _request.transactionDate),
                    _InfoRow('Required By', _request.scheduleDate),
                    _InfoRow('Status Dokumen', docStatusLabel(_request.docStatus)),
                    if (source != '-') _InfoRow('Gudang Asal', source),
                    if (target != '-') _InfoRow('Gudang Tujuan', target),
                    _InfoRow('Total Qty', _request.totalQty.toString()),
                  ],
                ),
                const SizedBox(height: 14),
                if (_loading)
                  const LinearProgressIndicator(minHeight: 3)
                else if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  _InfoCard(
                    title: 'Items',
                    rows: [
                      for (final item in _request.items)
                        _InfoRow(
                          item.itemName.isEmpty ? item.itemCode : item.itemName,
                          item.rate > 0
                              ? '${item.qty} ${item.uom} · rate ${item.rate}'
                              : '${item.qty} ${item.uom}'.trim(),
                          subtitle: [
                            item.itemCode,
                            if (item.fromWarehouse.isNotEmpty)
                              'Dari ${item.fromWarehouse}',
                            if (item.warehouse.isNotEmpty) 'Ke ${item.warehouse}',
                          ].join(' · '),
                        ),
                    ],
                  ),
                if (canEdit || canSubmit || _canPrint) ...[
                  const SizedBox(height: 16),
                  if (_canPrint)
                    erpActionButton(
                      label: 'Download PDF',
                      icon: Icons.picture_as_pdf_outlined,
                      onPressed: _loading || _busy ? null : _downloadPdf,
                    ),
                  if (_canPrint)
                    erpActionButton(
                      label: 'Print',
                      icon: Icons.print_outlined,
                      onPressed: _loading || _busy ? null : _printPdf,
                    ),
                  if (canEdit)
                    erpActionButton(
                      label: 'Edit',
                      icon: Icons.edit_outlined,
                      onPressed: _loading || _busy ? null : _edit,
                    ),
                  if (canSubmit)
                    erpActionButton(
                      label: 'Submit',
                      icon: Icons.check_circle_outline_rounded,
                      filled: true,
                      onPressed: _loading || _busy ? null : _submit,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    );
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

  Future<List<int>> _pdfBytes() {
    return context.read<WarehouseStockState>().downloadMaterialRequestPdf(
      _request.id,
    );
  }

  Future<void> _downloadPdf() async {
    await _runBusy(() async {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Mengunduh PDF ${_request.id}...')),
      );
      try {
        final saved = await saveBytesForUser(
          bytes: await _pdfBytes(),
          fileName: '${_request.id}.pdf',
          mimeType: 'application/pdf',
          appSubfolder: 'material_request_pdf',
        );
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('PDF siap: ${saved.locationLabel}')),
        );
        await shareSavedFile(saved, subject: 'Material Request ${_request.id}');
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
        downloadPdf: _pdfBytes,
        title: 'Material Request ${_request.id}',
      );
    });
  }

  Future<void> _submit() async {
    final confirmed = await confirmErpAction(
      context,
      title: 'Submit Material Request?',
      message: 'Submit ${_request.id} ke ERPNext?',
    );
    if (!confirmed || !mounted) return;
    await _runBusy(() async {
      final ok = await runErpWorkflowAction(
        context,
        action: () => context.read<WarehouseStockState>().submitDocument(
          'Material Request',
          _request.id,
        ),
        successMessage: 'Material Request ${_request.id} berhasil di-submit.',
      );
      if (ok && mounted) {
        _edited = true;
        await _load();
      }
    });
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateMaterialTransferRequestScreen(
          purpose: _request.type.isEmpty ? widget.request.type : _request.type,
          existingName: _request.id,
        ),
      ),
    );
    if (changed == true && mounted) {
      _edited = true;
      await _load();
    }
  }

  String _firstItemValue(String Function(MaterialRequestItem item) read) {
    for (final item in _request.items) {
      final value = read(item).trim();
      if (value.isNotEmpty) return value;
    }
    return '-';
  }
}

class _InfoRow {
  final String label;
  final String value;
  final String subtitle;

  const _InfoRow(this.label, this.value, {this.subtitle = ''});
}

class _InfoCard extends StatelessWidget {
  final String? title;
  final List<_InfoRow> rows;

  const _InfoCard({this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                color: AppColors.slate,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
          ],
          for (final row in rows) ...[
            Text(
              row.label,
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              row.value.isEmpty ? '-' : row.value,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (row.subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                row.subtitle,
                style: const TextStyle(color: AppColors.slate, fontSize: 12),
              ),
            ],
            if (row != rows.last) const Divider(height: 16),
          ],
        ],
      ),
    );
  }
}
