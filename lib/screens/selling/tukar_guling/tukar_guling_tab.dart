import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/tukar_guling.dart';
import '../../../state/selling/tukar_guling_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/date_range_presets.dart';
import '../../../utils/erp_error_message.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../widgets/erp/erp_status_badge.dart';
import '../../../widgets/erp/erp_workflow_helper.dart';
import '../shared/sales_ui.dart';
import '../shared/selling_document_detail_sheet.dart';
import 'create_tukar_guling_screen.dart';

class TukarGulingTab extends StatefulWidget {
  const TukarGulingTab({super.key});

  @override
  State<TukarGulingTab> createState() => _TukarGulingTabState();
}

class _TukarGulingTabState extends State<TukarGulingTab> {
  bool _loading = true;
  bool _canCreate = false;
  bool _canWrite = false;
  bool _isOpeningDetail = false;
  bool _actionBusy = false;
  String? _error;
  List<TukarGulingSummary> _rows = const [];
  Map<String, List<String>> _actionsByName = const {};
  String _company = '';
  String _jenis = '';
  DateTime? _postingFrom;
  DateTime? _postingTo;
  Map<String, dynamic>? _detailCache;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final state = context.read<TukarGulingState>();
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
      final state = context.read<TukarGulingState>();
      final rows = await state.fetchList(
        company: _company,
        jenis: _jenis,
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

  Future<void> _preloadWorkflowActions(List<TukarGulingSummary> rows) async {
    if (rows.isEmpty) return;
    try {
      final actions = await context
          .read<TukarGulingState>()
          .fetchWorkflowActionsForRows(rows);
      if (!mounted) return;
      setState(() => _actionsByName = actions);
    } catch (_) {}
  }

  Future<void> _openCreate({String? existingName}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateTukarGulingScreen(
          existingName: existingName,
          initialCompany: _company.trim().isEmpty ? null : _company,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  bool _isDraftLike(TukarGulingSummary row) {
    final state = row.statusLabel.toLowerCase();
    return state.isEmpty ||
        state == 'draft' ||
        state.contains('reject') ||
        state.contains('revisi') ||
        state.contains('revise');
  }

  bool _isRejectWorkflowAction(String action) {
    final value = action.toLowerCase();
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

  Future<void> _openDetail(TukarGulingSummary row) async {
    if (_isOpeningDetail) return;
    setState(() => _isOpeningDetail = true);
    try {
      final state = context.read<TukarGulingState>();
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
      final customerName = detail['customer_name']?.toString().trim() ?? '';
      final createdBy = detail['owner']?.toString().trim() ?? '';
      final company = detail['company']?.toString() ?? row.company;
      final postingDate =
          detail['posting_date']?.toString() ?? row.postingDate;
      final keterangan = detail['keterangan']?.toString() ?? row.keterangan;
      final stockEntry = detail['stock_entry']?.toString() ?? row.stockEntry;
      final jenis = () {
        final custom = detail['custom_jenis_input']?.toString().trim() ?? '';
        if (custom.isNotEmpty) return custom;
        return detail['jenis_input']?.toString().trim() ?? '';
      }();
      final metode = detail['custom_metode_final']?.toString().trim() ?? '';
      final isFinal = jenis.toLowerCase() == 'final';
      final workflowState =
          detail['workflow_state']?.toString() ?? row.statusLabel;
      final rawClaims = state.claimRowsOf(detail);
      final rawItems = state.itemRowsOf(detail);
      final sourceDates = isFinal
          ? await state.postingDatesByName([
              for (final map in rawClaims)
                if (_detailDate(map).isEmpty) _claimSourceName(map),
            ])
          : const <String, String>{};
      final items = <SellingDetailItem>[];
      if (!isFinal) {
        for (final map in rawClaims) {
          final note = _detailNote(map);
          final date = _detailDate(map);
          items.add(
            SellingDetailItem(
              title: _detailItemTitle(map),
              subtitle: _detailItemCode(map),
              stats: [
                if (date.isNotEmpty)
                  SellingDetailStat(label: 'Tanggal Klaim', value: date),
                SellingDetailStat(label: 'Qty (kg)', value: _detailQty(map)),
                if (note.isNotEmpty)
                  SellingDetailStat(label: 'Keterangan', value: note),
              ],
            ),
          );
        }
      } else {
        for (final map in rawClaims) {
          final date = _detailDate(map);
          final sourceDate = sourceDates[_claimSourceName(map)] ?? '';
          final claimDate = date.isNotEmpty ? date : sourceDate;
          items.add(
            SellingDetailItem(
              title: _detailItemTitle(map),
              subtitle: 'Klaim kg',
              stats: [
                if (claimDate.isNotEmpty)
                  SellingDetailStat(label: 'Tanggal', value: claimDate),
                SellingDetailStat(label: 'Qty (kg)', value: _detailQty(map)),
              ],
            ),
          );
        }
        for (final map in rawItems) {
          final qty = map['qty']?.toString() ?? '';
          final uom = map['uom']?.toString() ?? '';
          if ((map['item_code']?.toString().trim() ?? '').isEmpty &&
              qty.isEmpty) {
            continue;
          }
          items.add(
            SellingDetailItem(
              title: map['item_name']?.toString().trim().isNotEmpty == true
                  ? map['item_name'].toString()
                  : (map['item_code']?.toString() ?? '-'),
              subtitle: map['item_code']?.toString() ?? '',
              stats: [
                SellingDetailStat(
                  label: 'Qty',
                  value: uom.isEmpty ? qty : '$qty $uom',
                ),
                SellingDetailStat(
                  label: 'Gudang',
                  value: map['source_warehouse']?.toString().trim().isNotEmpty ==
                          true
                      ? map['source_warehouse'].toString()
                      : (map['s_warehouse']?.toString() ??
                          map['warehouse']?.toString() ??
                          '-'),
                ),
              ],
            ),
          );
        }
      }

      final canEdit = _canWrite && _isDraftLike(row);
      List<Map<String, dynamic>> photos = const [];
      try {
        photos = await state.fetchAttachments(row.id);
      } catch (_) {
        photos = const [];
      }
      if (!mounted) return;

      final gottenBox = tukarGulingGottenBoxQty(rawItems);
      final storedBox =
          double.tryParse(detail['custom_total_box']?.toString() ?? '') ?? 0;
      final boxLabel = formatTukarGulingQty(
        gottenBox > 0 ? gottenBox : storedBox,
      );
      final processKg = isFinal ? tukarGulingProcessKg(detail) : null;

      await showSellingDocumentDetailPage(
        context: context,
        appBarTitle: 'Detail Tukar Guling',
        title: row.id,
        subtitle: customerName.isNotEmpty
            ? customerName
            : (customer.isEmpty ? company : customer),
        statusText: workflowState.isEmpty ? 'Draft' : workflowState,
        icon: Icons.swap_horiz_rounded,
        metrics: [
          SellingDetailMetric(
            label: isFinal ? 'Box' : 'Klaim',
            value: isFinal ? boxLabel : '${items.length}',
            icon: Icons.inventory_2_outlined,
          ),
          SellingDetailMetric(
            label: 'Tanggal',
            value: postingDate.isEmpty ? '-' : postingDate,
            icon: Icons.event_rounded,
          ),
          if (processKg != null) ...[
            SellingDetailMetric(
              label: 'Kg diproses',
              value: '${formatTukarGulingQty(processKg.processedKg)} kg',
              icon: Icons.scale_rounded,
            ),
            SellingDetailMetric(
              label: 'Sisa kg',
              value: '${formatTukarGulingQty(processKg.remainingKg)} kg',
              icon: Icons.hourglass_bottom_rounded,
            ),
          ],
        ],
        infos: [
          if (jenis.isNotEmpty)
            SellingDetailInfo(label: 'Jenis', value: jenis),
          if (metode.isNotEmpty)
            SellingDetailInfo(label: 'Metode', value: metode),
          SellingDetailInfo(label: 'Company', value: company),
          if (createdBy.isNotEmpty)
            SellingDetailInfo(label: 'Dibuat oleh', value: createdBy),
          if (jenis.toLowerCase() != 'final' && stockEntry.isNotEmpty)
            SellingDetailInfo(label: 'Stock Entry', value: stockEntry),
          if (!isFinal && keterangan.isNotEmpty)
            SellingDetailInfo(label: 'Keterangan', value: keterangan),
        ],
        itemsTitle: isFinal ? 'Final' : 'Klaim Harian',
        itemsBadge: isFinal ? '$boxLabel box' : null,
        items: items,
        extra: _TukarGulingPhotos(
          files: photos,
          baseUrl: state.frappeService.baseUrl,
          cookie: state.frappeService.sessionCookieHeader,
        ),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canEdit)
              erpActionButton(
                label: 'Edit Tukar Guling',
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
    final tukarState = context.read<TukarGulingState>();
    final doc = currentDocument ??
        (_detailCache != null && _detailCache!['name']?.toString() == id
            ? _detailCache
            : null);
    final ok = await runErpWorkflowAction(
      context,
      action: () => tukarState.applyDocumentWorkflow(
            name: id,
            action: action,
            reason: reason,
            currentDocument: doc,
          ),
      successMessage: 'Tukar Guling: $action berhasil',
    );
    if (!mounted) return;
    setState(() => _actionBusy = false);
    if (ok) {
      if (closeSheet && Navigator.canPop(context)) Navigator.pop(context);
      await _load();
    }
  }

  void _onMenuSelected(TukarGulingSummary row, String value) {
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
          ErpSearchableFilterField(
            label: 'Jenis',
            selectedId: _jenis.isEmpty ? null : _jenis,
            decoration: const InputDecoration(
              labelText: 'Jenis transaksi',
              prefixIcon: Icon(Icons.swap_horiz_rounded, size: 18),
              isDense: true,
            ),
            allLabel: 'Semua jenis',
            options: const [
              ErpItemOption(id: 'Harian', label: 'Harian'),
              ErpItemOption(id: 'Final', label: 'Finalisasi'),
            ],
            onSelected: _loading
                ? (_) {}
                : (value) {
                    setState(() => _jenis = value ?? '');
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
    final companies = context.watch<TukarGulingState>().sellingCompanies;
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
                  title: 'Belum ada Tukar Guling',
                  message:
                      'Belum ada dokumen untuk filter / akses Anda. Ubah filter atau buat transaksi baru.',
                  icon: Icons.swap_horiz_rounded,
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
              heroTag: 'create-tukar-guling',
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              onPressed: () => _openCreate(),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Buat Tukar Guling',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
      ],
    );
  }

  String _customerLine(TukarGulingSummary row) {
    final name = row.customerName.trim();
    if (name.isNotEmpty) return name;
    return row.customer.trim();
  }

  Widget _card(TukarGulingSummary row) {
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
                  child: Icon(Icons.swap_horiz_rounded),
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
                          if (_customerLine(row).isNotEmpty) _customerLine(row),
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

String _detailItemCode(Map map) {
  for (final key in ['item_code', 'item']) {
    final text = map[key]?.toString().trim() ?? '';
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

String _detailItemTitle(Map map) {
  final name = map['item_name']?.toString().trim() ?? '';
  if (name.isNotEmpty && name != 'null') return name;
  final code = _detailItemCode(map);
  return code.isEmpty ? '-' : code;
}

String _detailNote(Map map) {
  final note = map['keterangan']?.toString().trim() ?? '';
  return note == 'null' ? '' : note;
}

String _detailDate(Map map) {
  for (final key in ['tanggal_klaim', 'claim_date', 'posting_date']) {
    final text = _shortDate(map[key]);
    if (text.isNotEmpty) return text;
  }
  for (final entry in map.entries) {
    final key = entry.key.toString().toLowerCase();
    if (key == 'creation' || key == 'modified' || key.contains('modified')) {
      continue;
    }
    if (!key.contains('tanggal') && !key.endsWith('_date')) continue;
    final text = _shortDate(entry.value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _claimSourceName(Map map) {
  for (final key in ['notg', 'no_tg', 'source_name']) {
    final text = map[key]?.toString().trim() ?? '';
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

String _shortDate(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text.length >= 10 ? text.substring(0, 10) : text;
}

class _TukarGulingPhotos extends StatelessWidget {
  final List<Map<String, dynamic>> files;
  final String baseUrl;
  final String? cookie;

  const _TukarGulingPhotos({
    required this.files,
    required this.baseUrl,
    required this.cookie,
  });

  @override
  Widget build(BuildContext context) {
    final images = [
      for (final file in files)
        if (_isImage(file) && _url(file).isNotEmpty) file,
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Foto',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${images.length}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (images.isEmpty)
            const Text(
              'Belum ada foto pada dokumen ini.',
              style: TextStyle(
                color: AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: images.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder: (context, index) {
                final file = images[index];
                final url = _url(file);
                final name = file['file_name']?.toString().trim().isNotEmpty ==
                        true
                    ? file['file_name'].toString()
                    : 'Foto ${index + 1}';
                return InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _TukarGulingPhotoPage(
                        title: name,
                        imageUrl: url,
                        cookie: cookie,
                      ),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(
                      url,
                      headers: cookie == null ? null : {'cookie': cookie!},
                      fit: BoxFit.cover,
                      cacheWidth: 480,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: AppColors.background,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.slate,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  bool _isImage(Map<String, dynamic> file) {
    final name = (file['file_name'] ?? file['file_url'] ?? '')
        .toString()
        .toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif');
  }

  String _url(Map<String, dynamic> file) {
    final raw = file['file_url']?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final root = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (raw.startsWith('/')) return '$root$raw';
    return '$root/$raw';
  }
}

class _TukarGulingPhotoPage extends StatelessWidget {
  final String title;
  final String imageUrl;
  final String? cookie;

  const _TukarGulingPhotoPage({
    required this.title,
    required this.imageUrl,
    required this.cookie,
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
          minScale: 0.8,
          maxScale: 4,
          child: Image.network(
            imageUrl,
            headers: cookie == null ? null : {'cookie': cookie!},
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

String _detailQty(Map map) {
  Object? fallback;
  for (final entry in map.entries) {
    final key = entry.key.toString().toLowerCase();
    if (!key.contains('qty')) continue;
    if (key.contains('kg')) {
      fallback = entry.value;
      break;
    }
    fallback ??= entry.value;
  }
  final qty = double.tryParse(fallback?.toString().replaceAll(',', '.') ?? '');
  if (qty == null) return fallback?.toString() ?? '0';
  return qty == qty.roundToDouble() ? qty.toInt().toString() : qty.toString();
}
