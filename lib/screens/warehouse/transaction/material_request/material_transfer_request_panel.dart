import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/material_request.dart';
import '../../../../state/warehouse/warehouse_stock_state.dart';
import '../../../../theme/app_colors.dart';
import '../../../../utils/erp_doc_utils.dart';
import '../../../../utils/erp_error_message.dart';
import '../../../../utils/erp_share_file.dart';
import '../../../../widgets/erp/erp_document_card.dart';
import '../../../../widgets/erp/erp_empty_state.dart';
import '../../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../../widgets/erp/erp_workflow_helper.dart';
import '../../../../widgets/print/erp_bluetooth_print.dart';
import '../../shared/warehouse_widgets.dart';
import 'create_material_transfer_request_screen.dart';
import 'material_request_detail_screen.dart';

class MaterialTransferRequestPanel extends StatefulWidget {
  final String purpose;

  const MaterialTransferRequestPanel({
    super.key,
    this.purpose = 'Material Transfer',
  });

  @override
  State<MaterialTransferRequestPanel> createState() =>
      _MaterialTransferRequestPanelState();
}

class _MaterialTransferRequestPanelState
    extends State<MaterialTransferRequestPanel> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  bool _canCreate = false;
  bool _canWrite = false;
  bool _canSubmit = false;
  bool _canPrint = false;
  bool _actionBusy = false;
  String? _error;
  String _status = '';
  String _company = '';
  DateTime? _fromDate;
  DateTime? _toDate;
  List<MaterialRequest> _rows = const [];

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(includePermissions: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load({bool includePermissions = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<WarehouseStockState>();
      if (includePermissions) {
        final permissions = await Future.wait([
          state.canCreateDoctype('Material Request'),
          state.canWriteDoctype('Material Request'),
          state.canSubmitDoctype('Material Request'),
          state.canPrintDoctype('Material Request'),
        ]);
        if (!mounted) return;
        setState(() {
          _canCreate = permissions[0];
          _canWrite = permissions[1];
          _canSubmit = permissions[2];
          _canPrint = permissions[3];
        });
      }
      final rows = await state.fetchMaterialRequestsByPurpose(
        purpose: widget.purpose,
        search: _search.text,
        status: _status,
        company: _company,
        fromDate: _fromDate,
        toDate: _toDate,
      );
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = captureErpError(
          context,
          error,
          action: 'memuat Material Request',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isDraft(MaterialRequest request) {
    final status = request.statusText.trim().toLowerCase();
    return isDocDraft(request.docStatus) || status == 'draft';
  }

  bool _canEdit(MaterialRequest request) => _canWrite && _isDraft(request);

  bool _canSubmitRow(MaterialRequest request) =>
      _canSubmit && _isDraft(request);

  Future<void> _runAction(Future<void> Function() action) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _submitRow(MaterialRequest request) async {
    if (!_canSubmitRow(request) || _actionBusy) return;
    final confirmed = await confirmErpAction(
      context,
      title: 'Submit Material Request?',
      message: 'Submit ${request.id} ke ERPNext?',
    );
    if (!confirmed || !mounted) return;
    await _runAction(() async {
      final ok = await runErpWorkflowAction(
        context,
        action: () => context.read<WarehouseStockState>().submitDocument(
          'Material Request',
          request.id,
        ),
        successMessage: 'Material Request ${request.id} berhasil di-submit.',
      );
      if (ok && mounted) await _load();
    });
  }

  Future<List<int>> _pdfBytes(String name) {
    return context.read<WarehouseStockState>().downloadMaterialRequestPdf(name);
  }

  Future<void> _downloadPdf(MaterialRequest request) async {
    if (!_canPrint || _actionBusy) return;
    await _runAction(() async {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Mengunduh PDF ${request.id}...')),
      );
      try {
        final saved = await saveBytesForUser(
          bytes: await _pdfBytes(request.id),
          fileName: '${request.id}.pdf',
          mimeType: 'application/pdf',
          appSubfolder: 'material_request_pdf',
        );
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('PDF siap: ${saved.locationLabel}')),
        );
        await shareSavedFile(saved, subject: 'Material Request ${request.id}');
      } catch (error) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Gagal download PDF: $error')),
        );
      }
    });
  }

  Future<void> _printPdf(MaterialRequest request) async {
    if (!_canPrint || _actionBusy) return;
    await _runAction(() async {
      await printErpPdfViaBluetooth(
        context,
        downloadPdf: () => _pdfBytes(request.id),
        title: 'Material Request ${request.id}',
      );
    });
  }

  Future<void> _openForm({String? existingName}) async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateMaterialTransferRequestScreen(
          purpose: widget.purpose,
          existingName: existingName,
        ),
      ),
    );
    if (created == true && mounted) await _load();
  }

  Future<void> _openDetail(MaterialRequest request) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MaterialRequestDetailScreen(
          request: request,
          canEdit: _canEdit(request),
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  bool get _hasFilter =>
      _status.isNotEmpty ||
      _company.isNotEmpty ||
      _fromDate != null ||
      _toDate != null;

  String get _filterSummary {
    final status = _status.isEmpty ? 'Semua status' : _status;
    final company = _company.isEmpty ? 'Semua perusahaan' : _company;
    return '$status  |  $company';
  }

  String get _dateSummary {
    String label(DateTime date) {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Mei',
        'Jun',
        'Jul',
        'Agu',
        'Sep',
        'Okt',
        'Nov',
        'Des',
      ];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    }

    if (_fromDate == null && _toDate == null) return 'Semua tanggal';
    if (_fromDate != null && _toDate != null) {
      return '${label(_fromDate!)} – ${label(_toDate!)}';
    }
    if (_fromDate != null) return 'Dari ${label(_fromDate!)}';
    return 'Sampai ${label(_toDate!)}';
  }

  Future<void> _openFilter() async {
    final state = context.read<WarehouseStockState>();
    if (state.stockCompanies.isEmpty) {
      await state.ensureWarehousesLoaded();
    }
    if (!mounted) return;
    final companies = state.stockCompanies.map((entry) => entry.key).toList();
    final result = await showModalBottomSheet<_MaterialRequestFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _MaterialRequestFilterSheet(
        status: _status,
        company: _company,
        fromDate: _fromDate,
        toDate: _toDate,
        companies: companies,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _status = result.status;
      _company = result.company;
      _fromDate = result.fromDate;
      _toDate = result.toDate;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Material Request',
          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900),
        ),
      ),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(widget.purpose),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: warehousePagePaddingOf(context),
          children: [
            _FilterSummaryCard(
              title: _filterSummary,
              subtitle: _dateSummary,
              onOpen: _openFilter,
            ),
            warehouseSectionGap,
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Cari nomor atau title',
              ),
            ),
            warehouseSectionGap,
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              )
            else if (_rows.isEmpty)
              ErpEmptyState(
                icon: Icons.assignment_outlined,
                title: _hasFilter
                    ? 'Tidak ada hasil filter'
                    : 'Belum ada ${widget.purpose}',
                message: _hasFilter
                    ? 'Ubah status, perusahaan, atau rentang tanggal.'
                    : 'Buat Material Request dengan purpose ${widget.purpose}.',
              )
            else
              for (final row in _rows)
                ErpDocumentCard(
                  id: row.id,
                  party: row.company.isEmpty ? row.type : row.company,
                  statusText: row.statusText,
                  date: row.transactionDate,
                  value: row.totalQty,
                  valueLabel:
                      '${row.itemsCount} item · qty ${row.totalQty}',
                  trailing: _routeLabel(row),
                  onTap: () => _openDetail(row),
                  onEdit: _canEdit(row)
                      ? () => _openForm(existingName: row.id)
                      : null,
                  onSubmit: _canSubmitRow(row) ? () => _submitRow(row) : null,
                  onPrint: _canPrint ? () => _printPdf(row) : null,
                  onDownload: _canPrint ? () => _downloadPdf(row) : null,
                ),
          ],
        ),
      ),
    );
  }
}

const materialRequestStatuses = [
  'Draft',
  'Submitted',
  'Stopped',
  'Cancelled',
  'Pending',
  'Partially Ordered',
  'Partially Received',
  'Ordered',
  'Issued',
  'Transferred',
  'Received',
];

class _MaterialRequestFilter {
  final String status;
  final String company;
  final DateTime? fromDate;
  final DateTime? toDate;

  const _MaterialRequestFilter({
    required this.status,
    required this.company,
    required this.fromDate,
    required this.toDate,
  });
}

class _FilterSummaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onOpen;

  const _FilterSummaryCard({
    required this.title,
    required this.subtitle,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            const Icon(Icons.tune_rounded, color: AppColors.slate, size: 18),
            const SizedBox(width: 8),
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
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.softGreen,
                foregroundColor: AppColors.primary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.filter_alt_outlined, size: 15),
              label: const Text(
                'Filter',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialRequestFilterSheet extends StatefulWidget {
  final String status;
  final String company;
  final DateTime? fromDate;
  final DateTime? toDate;
  final List<String> companies;

  const _MaterialRequestFilterSheet({
    required this.status,
    required this.company,
    required this.fromDate,
    required this.toDate,
    required this.companies,
  });

  @override
  State<_MaterialRequestFilterSheet> createState() =>
      _MaterialRequestFilterSheetState();
}

class _MaterialRequestFilterSheetState
    extends State<_MaterialRequestFilterSheet> {
  late String _status = widget.status;
  late String _company = widget.company;
  late DateTime? _fromDate = widget.fromDate;
  late DateTime? _toDate = widget.toDate;

  Future<void> _pickDate({required bool isFrom}) async {
    final current = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      final date = DateTime(picked.year, picked.month, picked.day);
      if (isFrom) {
        _fromDate = date;
      } else {
        _toDate = date;
      }
    });
  }

  String _dateText(DateTime? date) {
    if (date == null) return 'Semua';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          12,
          14,
          MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Filter Material Request',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              ErpSearchableFilterField(
                label: 'Status',
                selectedId: _status,
                allLabel: 'Semua status',
                decoration: const InputDecoration(
                  labelText: 'Status',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                options: [
                  for (final status in materialRequestStatuses)
                    ErpItemOption(id: status, label: status),
                ],
                onSelected: (value) => setState(() => _status = value ?? ''),
              ),
              const SizedBox(height: 12),
              ErpSearchableFilterField(
                label: 'Perusahaan',
                selectedId: _company,
                allLabel: 'Semua perusahaan',
                decoration: const InputDecoration(
                  labelText: 'Perusahaan',
                  prefixIcon: Icon(Icons.business_rounded),
                ),
                options: [
                  for (final company in widget.companies)
                    ErpItemOption(id: company, label: company),
                ],
                onSelected: (value) => setState(() => _company = value ?? ''),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _pickDate(isFrom: true),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Dari tanggal',
                    prefixIcon: const Icon(Icons.calendar_today_rounded),
                    suffixIcon: _fromDate == null
                        ? const Icon(Icons.expand_more_rounded)
                        : IconButton(
                            onPressed: () => setState(() => _fromDate = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  child: Text(
                    _dateText(_fromDate),
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _pickDate(isFrom: false),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Sampai tanggal',
                    prefixIcon: const Icon(Icons.event_rounded),
                    suffixIcon: _toDate == null
                        ? const Icon(Icons.expand_more_rounded)
                        : IconButton(
                            onPressed: () => setState(() => _toDate = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                  child: Text(
                    _dateText(_toDate),
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _status = '';
                        _company = '';
                        _fromDate = null;
                        _toDate = null;
                      }),
                      child: const Text('Atur ulang'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        _MaterialRequestFilter(
                          status: _status,
                          company: _company,
                          fromDate: _fromDate,
                          toDate: _toDate,
                        ),
                      ),
                      child: const Text('Terapkan Filter'),
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

String? _routeLabel(MaterialRequest request) {
  final source = request.sourceWarehouse.isNotEmpty
      ? request.sourceWarehouse
      : request.items
            .map((item) => item.fromWarehouse)
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  final target = request.targetWarehouse.isNotEmpty
      ? request.targetWarehouse
      : request.items
            .map((item) => item.warehouse)
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  final route = [
    if (source.isNotEmpty) source,
    if (target.isNotEmpty) target,
  ].join(' → ');
  return route.isEmpty ? null : route;
}
