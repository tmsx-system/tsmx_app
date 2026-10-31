import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/reject.dart';
import '../../../state/selling/reject_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/date_range_presets.dart';
import '../../../utils/erp_error_message.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../widgets/erp/erp_status_badge.dart';
import '../../../widgets/erp/erp_workflow_helper.dart';
import '../../selling/shared/sales_ui.dart';
import '../../selling/shared/selling_document_detail_sheet.dart';
import 'create_reject_screen.dart';

class RejectTab extends StatefulWidget {
  const RejectTab({super.key});

  @override
  State<RejectTab> createState() => _RejectTabState();
}

class _RejectTabState extends State<RejectTab> {
  bool _loading = true;
  bool _canCreate = false;
  bool _canWrite = false;
  bool _isOpeningDetail = false;
  bool _actionBusy = false;
  String? _error;
  List<RejectSummary> _rows = const [];
  Map<String, List<String>> _actionsByName = const {};
  String _company = '';
  DateTime? _postingFrom;
  DateTime? _postingTo;
  Map<String, dynamic>? _detailCache;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final state = context.read<RejectState>();
    await state.ensureCompanies();
    if (!mounted) return;
    final preferred = state.preferredCompany(state.sellingCompanies) ?? '';
    final permissions = await Future.wait([
      state.canCreate(),
      state.canWrite(),
    ]);
    if (!mounted) return;
    setState(() {
      _canCreate = permissions[0];
      _canWrite = permissions[1];
      if (_company.isEmpty && preferred.isNotEmpty) _company = preferred;
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<RejectState>();
      final rows = await state.fetchList(
        company: _company,
        postingDateFrom: _postingFrom,
        postingDateTo: _postingTo,
      );
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _actionsByName = const {};
        _detailCache = null;
      });
      // Non-blocking: batch get_transitions from list fields (no GET per row).
      unawaited(_preloadWorkflowActions(rows));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _preloadWorkflowActions(List<RejectSummary> rows) async {
    if (rows.isEmpty) return;
    try {
      final actions = await context
          .read<RejectState>()
          .fetchWorkflowActionsForRows(rows);
      if (!mounted) return;
      setState(() => _actionsByName = actions);
    } catch (_) {}
  }

  Future<void> _openCreate({String? existingName}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateRejectScreen(existingName: existingName),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  /// Matches Reject Workflow: QC may edit Draft + Rejected (Revise path).
  bool _isDraftLike(RejectSummary row) {
    final state = row.statusLabel.toLowerCase().trim();
    return state.isEmpty ||
        state == 'draft' ||
        state == 'rejected' ||
        state.contains('revisi') ||
        state.contains('revise');
  }

  bool _isRejectWorkflowAction(String action) {
    final value = action.toLowerCase();
    // Workflow action "Reject" needs a reason; Cancel does not.
    return value.contains('reject') ||
        value.contains('tolak') ||
        value.contains('return') ||
        value.contains('decline');
  }

  bool _isPositiveWorkflowAction(String action) {
    final value = action.toLowerCase();
    return value.contains('approve') ||
        value.contains('submit') ||
        value.contains('revise');
  }

  IconData _workflowActionIcon(String action) {
    final value = action.toLowerCase();
    if (_isRejectWorkflowAction(action)) return Icons.close_rounded;
    if (value.contains('cancel')) return Icons.cancel_outlined;
    if (value.contains('approve')) return Icons.verified_rounded;
    if (value.contains('submit')) return Icons.send_rounded;
    if (value.contains('revise') || value.contains('revisi')) {
      return Icons.edit_outlined;
    }
    return Icons.check_circle_outline_rounded;
  }

  Future<void> _pickPostingRange() async {
    final today = DateTime.now();
    final initial = DateTimeRange(
      start: _postingFrom ?? DateRangePresets.monthToDateRange().from,
      end: _postingTo ?? today,
    );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: initial,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _postingFrom = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _postingTo = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
      );
    });
    await _load();
  }

  void _clearPostingRange() {
    if (_postingFrom == null && _postingTo == null) return;
    setState(() {
      _postingFrom = null;
      _postingTo = null;
    });
    unawaited(_load());
  }

  Future<void> _openDetail(RejectSummary row) async {
    if (_isOpeningDetail) return;
    setState(() => _isOpeningDetail = true);
    try {
      final state = context.read<RejectState>();
      final cachedActions = _actionsByName[row.id] ?? const <String>[];

      // Single GET for detail; derive transitions from that doc (no 2nd GET).
      final detail = await state.fetchDetail(row.id);
      if (!mounted) return;
      _detailCache = detail;

      var workflowActions = cachedActions;
      try {
        workflowActions = await state.fetchWorkflowActionsForDocument(detail);
        if (mounted && workflowActions.isNotEmpty) {
          setState(() {
            _actionsByName = {
              ..._actionsByName,
              row.id: workflowActions,
            };
          });
        }
      } catch (_) {
        workflowActions = cachedActions;
      }
      if (!mounted) return;

      final customer = detail['customer']?.toString() ?? row.customer;
      final company = detail['company']?.toString() ?? row.company;
      final postingDate =
          detail['posting_date']?.toString() ?? row.postingDate;
      final keterangan = detail['keterangan']?.toString() ?? row.keterangan;
      final stockEntry = detail['stock_entry']?.toString() ?? row.stockEntry;
      final workflowState =
          detail['workflow_state']?.toString() ?? row.statusLabel;
      final rawItems = detail['reject_item'] ??
          detail['items'] ??
          detail['reject_items'];
      final items = <SellingDetailItem>[];
      if (rawItems is List) {
        for (final raw in rawItems.whereType<Map>()) {
          final map = Map<String, dynamic>.from(raw);
          final qty = map['qty']?.toString() ?? '';
          final uom = map['uom']?.toString() ?? '';
          items.add(
            SellingDetailItem(
              title: map['item_name']?.toString() ??
                  map['item_code']?.toString() ??
                  '-',
              subtitle: map['item_code']?.toString() ?? '',
              qty: uom.isEmpty ? qty : '$qty $uom',
              note: map['source_warehouse']?.toString() ??
                  map['s_warehouse']?.toString() ??
                  map['warehouse']?.toString() ??
                  '',
            ),
          );
        }
      }

      final canEdit = _canWrite && _isDraftLike(row);

      await showSellingDocumentDetailSheet(
        context: context,
        title: row.id,
        subtitle: customer.isEmpty ? company : customer,
        statusText: workflowState.isEmpty ? 'Draft' : workflowState,
        icon: Icons.highlight_off_rounded,
        metrics: [
          SellingDetailMetric(
            label: 'Item',
            value: '${items.length}',
            icon: Icons.inventory_2_outlined,
          ),
          SellingDetailMetric(
            label: 'Tanggal',
            value: postingDate.isEmpty ? '-' : postingDate,
            icon: Icons.event_rounded,
          ),
        ],
        infos: [
          SellingDetailInfo(label: 'Customer', value: customer),
          SellingDetailInfo(label: 'Company', value: company),
          SellingDetailInfo(label: 'Posting Date', value: postingDate),
          SellingDetailInfo(label: 'Workflow', value: workflowState),
          if (stockEntry.isNotEmpty)
            SellingDetailInfo(label: 'Stock Entry', value: stockEntry),
          if (keterangan.isNotEmpty)
            SellingDetailInfo(label: 'Keterangan', value: keterangan),
        ],
        items: items,
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canEdit)
              erpActionButton(
                label: 'Edit Reject',
                icon: Icons.edit_outlined,
                onPressed: () {
                  Navigator.pop(context);
                  unawaited(_openCreate(existingName: row.id));
                },
              ),
            ...workflowActions.map(
              (action) => erpActionButton(
                label: action,
                icon: _workflowActionIcon(action),
                filled: _isPositiveWorkflowAction(action),
                onPressed: () => unawaited(
                  _applyWorkflowAction(
                    row.id,
                    action,
                    closeSheet: true,
                    currentDocument: detail,
                  ),
                ),
              ),
            ),
            if (workflowActions.isEmpty && !canEdit)
              const Text(
                'Tidak ada aksi workflow untuk dokumen ini / role Anda.',
                style: TextStyle(fontSize: 12, color: AppColors.slate),
              ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(captureErpError(context, error))),
      );
    } finally {
      if (mounted) setState(() => _isOpeningDetail = false);
    }
  }

  Future<String?> _askWorkflowReason(String id, String action) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$action $id'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Alasan',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();
    if (ok != true) return null;
    return reason;
  }

  Future<void> _applyWorkflowAction(
    String id,
    String action, {
    bool closeSheet = false,
    Map<String, dynamic>? currentDocument,
  }) async {
    if (_actionBusy) return;
    var reason = '';
    if (_isRejectWorkflowAction(action)) {
      reason = await _askWorkflowReason(id, action) ?? '';
      if (reason.isEmpty || !mounted) return;
    } else {
      final ok = await confirmErpAction(
        context,
        title: '$action?',
        message: 'Lanjutkan "$action" untuk $id?',
      );
      if (!ok || !mounted) return;
    }

    setState(() => _actionBusy = true);
    final rejectState = context.read<RejectState>();
    final doc = currentDocument ??
        (_detailCache != null && _detailCache!['name']?.toString() == id
            ? _detailCache
            : null);
    final ok = await runErpWorkflowAction(
      context,
      action: () => rejectState.applyDocumentWorkflow(
            name: id,
            action: action,
            reason: reason,
            currentDocument: doc,
          ),
      successMessage: 'Reject: $action berhasil',
    );
    if (!mounted) return;
    setState(() => _actionBusy = false);
    if (ok) {
      if (closeSheet && Navigator.canPop(context)) Navigator.pop(context);
      await _load();
    }
  }

  void _onMenuSelected(RejectSummary row, String value) {
    switch (value) {
      case 'detail':
        unawaited(_openDetail(row));
      case 'edit':
        unawaited(_openCreate(existingName: row.id));
      default:
        if (value.startsWith('wf:')) {
          unawaited(_applyWorkflowAction(row.id, value.substring(3)));
        }
    }
  }

  Widget _filterBar(List<String> companies) {
    final selectedCompany =
        _company.isEmpty || companies.contains(_company) ? _company : '';
    final hasDate = _postingFrom != null || _postingTo != null;
    final dateLabel = !hasDate
        ? 'Semua tanggal'
        : (_postingFrom != null && _postingTo != null)
            ? DateRangePresets.formatRangeLabel(
                DateRangePreset(from: _postingFrom!, to: _postingTo!),
              )
            : _postingFrom != null
                ? '≥ ${DateRangePresets.formatDisplay(_postingFrom!)}'
                : '≤ ${DateRangePresets.formatDisplay(_postingTo!)}';

    return SalesInfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ErpSearchableFilterField(
            label: 'Company',
            selectedId: selectedCompany.isEmpty ? null : selectedCompany,
            decoration: const InputDecoration(
              labelText: 'Company',
              prefixIcon: Icon(Icons.business_rounded, size: 18),
              isDense: true,
            ),
            allLabel: 'Semua company',
            options: [
              for (final company in companies)
                ErpItemOption(id: company, label: company),
            ],
            onSelected: _loading
                ? (_) {}
                : (value) {
                    setState(() => _company = value ?? '');
                    unawaited(_load());
                  },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Material(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _loading ? null : _pickPostingRange,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Posting Date',
                        prefixIcon: Icon(Icons.event_rounded, size: 18),
                        suffixIcon: Icon(Icons.expand_more_rounded, size: 18),
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        dateLabel,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (hasDate) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Hapus filter tanggal',
                  onPressed: _loading ? null : _clearPostingRange,
                  icon: const Icon(Icons.clear_rounded, size: 18),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companies = context.watch<RejectState>().sellingCompanies;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: SalesUi.compactScreenPaddingOf(context),
            children: [
              _filterBar(companies),
              SalesUi.gap(),
              if (_loading && _rows.isEmpty)
                const SalesInfoCard(
                  child: SizedBox(
                    height: 140,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_error != null)
                SalesInfoCard(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (_rows.isEmpty)
                const ErpEmptyState(
                  title: 'Belum ada Reject',
                  message:
                      'Belum ada dokumen untuk filter / akses Anda. Ubah filter atau buat transaksi baru.',
                  icon: Icons.highlight_off_rounded,
                )
              else
                ..._rows.map(_card),
              const SizedBox(height: 88),
            ],
          ),
        ),
        if (_canCreate)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'create-reject',
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              onPressed: () => _openCreate(),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Buat Reject',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
      ],
    );
  }

  Widget _card(RejectSummary row) {
    final workflowActions = _actionsByName[row.id] ?? const <String>[];
    final canEdit = _canWrite && _isDraftLike(row);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: _isOpeningDetail ? null : () => unawaited(_openDetail(row)),
          child: SalesInfoCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.softGreen,
                  foregroundColor: AppColors.primary,
                  child: Icon(Icons.highlight_off_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.id,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (row.customer.isNotEmpty) row.customer,
                          if (row.company.isNotEmpty) row.company,
                          if (row.postingDate.isNotEmpty) row.postingDate,
                          if (row.stockEntry.isNotEmpty)
                            'SE: ${row.stockEntry}',
                        ].join('\n'),
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ErpStatusBadge(statusText: row.statusLabel),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: PopupMenuButton<String>(
                        tooltip: 'Aksi',
                        padding: EdgeInsets.zero,
                        enabled: !_actionBusy && !_isOpeningDetail,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: AppColors.white,
                        icon: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.more_vert_rounded,
                            color: AppColors.slate,
                            size: 19,
                          ),
                        ),
                        onSelected: (value) => _onMenuSelected(row, value),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'detail',
                            child: Row(
                              children: [
                                Icon(Icons.visibility_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Lihat Detail'),
                              ],
                            ),
                          ),
                          if (canEdit)
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                          for (final action in workflowActions)
                            PopupMenuItem(
                              value: 'wf:$action',
                              child: Row(
                                children: [
                                  Icon(_workflowActionIcon(action), size: 18),
                                  const SizedBox(width: 8),
                                  Flexible(child: Text(action)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
