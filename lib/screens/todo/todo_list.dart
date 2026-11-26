import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/erp_approval_todo.dart';
import '../../models/sales_order.dart';
import '../../models/sales_order_approval.dart';
import '../../models/tukar_guling.dart';
import '../selling/shared/selling_document_detail_sheet.dart';
import '../../state/selling/tukar_guling_state.dart';
import '../../state/todo/todo_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/erp_doc_utils.dart';
import '../../utils/erp_format.dart';
import '../../utils/num_parse.dart';
import '../../widgets/erp/erp_empty_state.dart';
import '../../utils/erp_error_message.dart';
import '../../widgets/erp/erp_status_badge.dart';
import '../../widgets/erp/erp_workflow_helper.dart';
import '../../widgets/responsive/responsive_layout.dart';

String _itemDiscountLabel(Map<String, dynamic> item) {
  final amount = NumParse.asDouble(item['discount_amount']);
  final percentage = NumParse.asDouble(item['discount_percentage']);
  final amountLabel = 'Rp ${formatErpCurrency(amount)}';
  if (percentage <= 0) return amountLabel;
  return '$amountLabel (${percentage.toStringAsFixed(2)}%)';
}

List<Map<String, dynamic>> _childTableRows(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final row in value.whereType<Map>()) Map<String, dynamic>.from(row),
  ];
}

List<Map<String, dynamic>> _firstNamedChildTable(
  Map<String, dynamic> detail,
  List<String> keys,
) {
  for (final key in keys) {
    final rows = _childTableRows(detail[key]);
    if (rows.isNotEmpty) return rows;
  }
  return const [];
}

bool _tukarRowExcluded(String key, Map<String, dynamic> sample) {
  final doctype = (sample['doctype'] ?? '').toString().toLowerCase();
  final normalized = key.toLowerCase();
  return normalized.contains('sisa') ||
      normalized.contains('source') ||
      normalized.contains('saldo') ||
      doctype.contains('sisa');
}

bool _rowLooksLikeTukarClaim(String key, Map<String, dynamic> sample) {
  if (_tukarRowExcluded(key, sample)) return false;
  final doctype = (sample['doctype'] ?? '').toString().toLowerCase();
  final normalized = key.toLowerCase();
  if (normalized.contains('klaim') ||
      normalized.contains('claim') ||
      doctype.contains('klaim') ||
      doctype.contains('harian')) {
    return true;
  }
  final keys = sample.keys.map((entry) => entry.toString().toLowerCase());
  final hasQty = keys.any((entry) => entry.contains('qty'));
  final hasItem = keys.any((entry) => entry.contains('item'));
  final isBox = keys.any(
    (entry) => entry.contains('warehouse') || entry == 'uom',
  );
  return hasQty && hasItem && !isBox;
}

bool _rowLooksLikeTukarItem(String key, Map<String, dynamic> sample) {
  if (_tukarRowExcluded(key, sample) || _rowLooksLikeTukarClaim(key, sample)) {
    return false;
  }
  final doctype = (sample['doctype'] ?? '').toString().toLowerCase();
  return key.toLowerCase().contains('item') ||
      doctype.contains('tukar guling item');
}

List<Map<String, dynamic>> tukarGulingDocumentRows(
  Map<String, dynamic> detail,
) {
  var claims = _firstNamedChildTable(detail, const [
    'custom_claim_details',
    'klaim_harian',
    'tukar_guling_harian',
    'claim_details',
  ]);
  var items = _firstNamedChildTable(detail, const [
    'tukar_guling_item',
    'tukar_guling_items',
    'items',
  ]);
  if (claims.isEmpty || items.isEmpty) {
    for (final entry in detail.entries) {
      final rows = _childTableRows(entry.value);
      if (rows.isEmpty) continue;
      final key = entry.key.toString();
      if (claims.isEmpty && _rowLooksLikeTukarClaim(key, rows.first)) {
        claims = rows;
      } else if (items.isEmpty && _rowLooksLikeTukarItem(key, rows.first)) {
        items = rows;
      }
    }
  }
  return [...claims, ...items];
}

bool tukarGulingRowIsClaim(Map<String, dynamic> item) {
  final doctype = (item['doctype'] ?? '').toString().toLowerCase();
  if (doctype.contains('harian') || doctype.contains('klaim')) return true;
  if (doctype.contains('tukar guling item')) return false;
  final keys = item.keys.map((key) => key.toString().toLowerCase()).toList();
  final hasKg = keys.any((key) => key.contains('qty') && key.contains('kg'));
  final hasWarehouse = keys.any((key) => key.contains('warehouse'));
  final uom = (item['uom'] ?? '').toString().trim();
  if (hasWarehouse || uom.isNotEmpty) return false;
  final itemCode = (item['item_code'] ?? '').toString().trim();
  final itemRef = (item['item'] ?? '').toString().trim();
  return hasKg || (itemCode.isEmpty && itemRef.isNotEmpty);
}

String tukarGulingRowText(Map<String, dynamic> row, List<String> keys) {
  for (final key in keys) {
    final value = row[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return '';
}

String tukarGulingItemSectionTitle(
  List<Map<String, dynamic>> rows, {
  double storedBox = 0,
}) {
  if (rows.isNotEmpty && rows.every(tukarGulingRowIsClaim)) {
    return 'Klaim Pengajuan (${rows.length})';
  }
  final gotten = tukarGulingGottenBoxQty(
    rows.where((row) => !tukarGulingRowIsClaim(row)),
  );
  return 'Item (${formatTukarGulingQty(gotten > 0 ? gotten : storedBox)} box)';
}

String tukarGulingClaimDate(Map<String, dynamic> item) {
  final direct = tukarGulingRowText(item, [
    'tanggal_klaim',
    'claim_date',
    'posting_date',
  ]);
  if (direct.isNotEmpty) {
    return direct.length >= 10 ? direct.substring(0, 10) : direct;
  }
  for (final entry in item.entries) {
    final key = entry.key.toString().toLowerCase();
    if (key == 'creation' || key == 'modified' || key.contains('modified')) {
      continue;
    }
    if (!key.contains('tanggal') && !key.endsWith('_date')) continue;
    final text = entry.value?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') continue;
    return text.length >= 10 ? text.substring(0, 10) : text;
  }
  return '';
}

String tukarGulingClaimSource(Map<String, dynamic> item) {
  return tukarGulingRowText(item, ['notg', 'no_tg', 'source_name']);
}

Widget tukarGulingTodoItemCard(
  Map<String, dynamic> item, {
  Map<String, String> sourceDates = const {},
}) {
  final claim = tukarGulingRowIsClaim(item);
  final title = tukarGulingRowText(item, ['item_name', 'item', 'item_code']);
  final code = tukarGulingRowText(item, ['item_code', 'item']);
  final qtyRaw = claim
      ? tukarGulingRowText(item, ['qty_kg', 'qty'])
      : tukarGulingRowText(item, ['qty', 'qty_kg']);
  final qtyNumber = NumParse.asDouble(qtyRaw);
  final qty = qtyNumber == qtyNumber.roundToDouble()
      ? qtyNumber.toInt().toString()
      : qtyNumber.toStringAsFixed(2);
  final uom = claim ? 'kg' : tukarGulingRowText(item, ['uom']);
  final ownDate = tukarGulingClaimDate(item);
  final sourceDate = sourceDates[tukarGulingClaimSource(item)] ?? '';
  final dateLabel = ownDate.isNotEmpty ? ownDate : sourceDate;
  final note = tukarGulingRowText(item, ['keterangan']);
  final warehouse = tukarGulingRowText(item, [
    'source_warehouse',
    's_warehouse',
    'warehouse',
  ]);

  Widget pill(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? '-' : title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (code.isNotEmpty && code != title) ...[
            const SizedBox(height: 4),
            Text(
              code,
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (claim && dateLabel.isNotEmpty)
                pill(Icons.event_rounded, dateLabel),
              pill(Icons.inventory_2_outlined, uom.isEmpty ? qty : '$qty $uom'),
              if (!claim && warehouse.isNotEmpty)
                pill(Icons.warehouse_outlined, warehouse),
              if (claim && note.isNotEmpty) pill(Icons.notes_rounded, note),
            ],
          ),
        ],
      ),
    ),
  );
}

class SalesOrderApprovalScreen extends StatefulWidget {
  final bool embedded;
  final String title;
  final Set<String>? doctypeFilter;

  const SalesOrderApprovalScreen({
    super.key,
    this.embedded = false,
    this.title = 'Approval Dokumen',
    this.doctypeFilter,
  });

  @override
  State<SalesOrderApprovalScreen> createState() =>
      _SalesOrderApprovalScreenState();
}

class _SalesOrderApprovalScreenState extends State<SalesOrderApprovalScreen> {
  List<ErpApprovalTodo> _rows = const [];
  Timer? _syncTimer;
  Future<void>? _loadInFlight;
  bool _loading = true;
  String? _error;
  String? _openDoctype;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cachedRows = _filterRows(
        context.read<TodoState>().cachedApprovalTodos,
      );
      if (cachedRows.isNotEmpty) {
        setState(() {
          _rows = cachedRows;
          _loading = false;
        });
      }
      unawaited(_load(silent: cachedRows.isNotEmpty, forceRefresh: false));
      _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (mounted) _load(silent: true, forceRefresh: true);
      });
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false, bool forceRefresh = false}) {
    final inFlight = _loadInFlight;
    if (inFlight != null) return inFlight;
    final request = _loadInternal(silent: silent, forceRefresh: forceRefresh);
    _loadInFlight = request;
    return request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
  }

  Future<void> _loadInternal({
    required bool silent,
    required bool forceRefresh,
  }) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final appState = context.read<TodoState>();
    if (!appState.appState.canUseApprovals) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    try {
      final rows = await appState.fetchApprovalTodos(
        forceRefresh: forceRefresh,
        onProgress: (partial) {
          if (!mounted) return;
          final filtered = _filterRows(partial);
          if (filtered.isEmpty) return;
          setState(() {
            _rows = filtered;
            if (!silent) _loading = false;
            _error = null;
          });
        },
      );
      final filtered = _filterRows(rows);
      if (!mounted) return;
      setState(() {
        _rows = filtered;
        if (!silent) _loading = false;
      });
    } catch (error) {
      if (!silent && mounted) {
        setState(() {
          _error = captureErpError(
            context,
            error,
            action: 'memuat daftar approval',
          );
          _loading = false;
        });
      }
    }
  }

  List<ErpApprovalTodo> _filterRows(List<ErpApprovalTodo> rows) {
    final filter = widget.doctypeFilter;
    if (filter == null) return rows;
    return rows.where((row) => filter.contains(row.doctype)).toList();
  }

  Future<void> _selectApproval(ErpApprovalTodo approval) async {
    unawaited(
      context
          .read<TodoState>()
          .fetchApprovalDocument(doctype: approval.doctype, name: approval.name)
          .catchError((_) => <String, dynamic>{}),
    );
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _ErpApprovalDetailPage(approval: approval, onChanged: () async {}),
      ),
    );
    if (changed == true && mounted) {
      setState(() {
        _rows = _rows
            .where(
              (row) =>
                  row.doctype != approval.doctype || row.name != approval.name,
            )
            .toList();
      });
      unawaited(_load(silent: true, forceRefresh: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _approvalList();
    if (widget.embedded) {
      return ColoredBox(color: AppColors.background, child: content);
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 72,
        title: Text(
          widget.title,
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sinkronkan',
            onPressed: _loading ? null : () => _load(forceRefresh: true),
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _approvalList() {
    final allRows = List<ErpApprovalTodo>.from(_rows)
      ..sort(_compareApprovalTodos);
    final statusCounts = <String, int>{};
    final statusLabels = <String, String>{};
    for (final row in allRows) {
      final label = _todoStatusLabel(row);
      final key = label.toLowerCase();
      statusLabels.putIfAbsent(key, () => label);
      statusCounts[key] = (statusCounts[key] ?? 0) + 1;
    }
    final statusKeys = statusCounts.keys.toList()
      ..sort((a, b) {
        final byCount = (statusCounts[b] ?? 0).compareTo(statusCounts[a] ?? 0);
        if (byCount != 0) return byCount;
        return a.compareTo(b);
      });
    final selectedStatus = statusCounts.containsKey(_statusFilter)
        ? _statusFilter
        : null;
    final rows = allRows.where((row) {
      if (selectedStatus == null) return true;
      return _todoStatusLabel(row).toLowerCase() == selectedStatus;
    }).toList();
    final counts = _approvalTodoDoctypeCounts(rows);
    final doctypes = counts.keys.toList()
      ..sort((a, b) {
        final byCount = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
        if (byCount != 0) return byCount;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    final open = _openDoctype == ''
        ? null
        : counts.containsKey(_openDoctype)
        ? _openDoctype
        : (doctypes.isEmpty ? null : doctypes.first);
    final grouped = <String, List<ErpApprovalTodo>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.doctype, () => []).add(row);
    }
    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 90),
        children: [
          _todoHeader(allRows.length),
          if (allRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            _statusFilterBar(
              total: allRows.length,
              statusKeys: statusKeys,
              statusLabels: statusLabels,
              statusCounts: statusCounts,
              selected: selectedStatus,
            ),
          ],
          const SizedBox(height: 14),
          if (doctypes.isNotEmpty) _todoSummaryCards(doctypes, counts, open),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _errorBox(_error!),
          ],
          const SizedBox(height: 8),
          if (rows.isEmpty && !_loading)
            ErpEmptyState(
              title: allRows.isEmpty
                  ? 'Todo approval sudah kosong'
                  : 'Tidak ada dokumen di filter ini',
              message: allRows.isEmpty
                  ? 'Hanya action Workflow yang tersedia untuk role login yang ditampilkan.'
                  : 'Pilih Semua atau status workflow lain untuk melihat dokumen yang tersisa.',
            )
          else
            for (final doctype in doctypes)
              _todoSection(
                doctype: doctype,
                rows: grouped[doctype] ?? const [],
                expanded: doctype == open,
              ),
        ],
      ),
    );
  }

  String _todoStatusLabel(ErpApprovalTodo row) {
    final workflow = row.workflowState.trim();
    if (workflow.isNotEmpty) return workflow;
    final status = row.status.trim();
    if (status.isNotEmpty) return status;
    if (row.docStatus == 0) return 'Draft';
    return 'Tanpa status';
  }

  Widget _statusFilterBar({
    required int total,
    required List<String> statusKeys,
    required Map<String, String> statusLabels,
    required Map<String, int> statusCounts,
    required String? selected,
  }) {
    Widget chip({
      required String label,
      required int count,
      required String? value,
    }) {
      final active = selected == value;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: active ? AppColors.primary : AppColors.white,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: () => setState(() => _statusFilter = value),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Text(
                '$label  $count',
                style: TextStyle(
                  color: active ? AppColors.white : AppColors.navy,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip(label: 'Semua', count: total, value: null),
          for (final key in statusKeys)
            chip(
              label: statusLabels[key] ?? key,
              count: statusCounts[key] ?? 0,
              value: key,
            ),
        ],
      ),
    );
  }

  Widget _todoHeader(int total) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To-do List',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Dokumen yang perlu ditindaklanjuti',
                style: TextStyle(
                  color: AppColors.slate,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Total  $total',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _todoSummaryCards(
    List<String> doctypes,
    Map<String, int> counts,
    String? focused,
  ) {
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: doctypes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final doctype = doctypes[index];
          final selected = doctype == focused;
          final accent = _approvalAccent(doctype);
          return InkWell(
            onTap: () => setState(() => _openDoctype = doctype),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 116,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.white
                    : accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? accent : accent.withValues(alpha: 0.16),
                  width: selected ? 1.6 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.16),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          _approvalIcon(doctype),
                          color: accent,
                          size: 16,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _approvalShortLabel(doctype),
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '${counts[doctype] ?? 0}',
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    doctype,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 3,
                    width: selected ? 36 : 18,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _todoSection({
    required String doctype,
    required List<ErpApprovalTodo> rows,
    required bool expanded,
  }) {
    final accent = _approvalAccent(doctype);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _openDoctype = expanded ? '' : doctype),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: expanded
                    ? accent.withValues(alpha: 0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _approvalIcon(doctype),
                      color: accent,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      doctype,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${rows.length}',
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.slate,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            ...rows.map(_approvalCard),
          ],
        ],
      ),
    );
  }

  Widget _approvalCard(ErpApprovalTodo row) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: () => _selectApproval(row),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: _cardDecoration(accent: _approvalAccent(row.doctype)),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(color: _approvalAccent(row.doctype)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Builder(
                        builder: (context) {
                          final accent = _approvalAccent(row.doctype);
                          return Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(17),
                            ),
                            child: Icon(
                              _approvalIcon(row.doctype),
                              color: accent,
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final accent = _approvalAccent(row.doctype);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          row.moduleLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: accent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ErpStatusBadge(
                                      statusText: row.workflowState.isEmpty
                                          ? row.status
                                          : row.workflowState,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  row.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.navy,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  row.partyLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.slate,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.slate,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _approvalMetaPill(
                        icon: Icons.payments_outlined,
                        label: _approvalAmount(row),
                        color: _approvalAccent(row.doctype),
                      ),
                      if (row.date.isNotEmpty)
                        _approvalMetaPill(
                          icon: Icons.event_available_rounded,
                          label: row.date,
                          color: const Color(0xFF0EA5E9),
                        ),
                      _approvalMetaPill(
                        icon: Icons.task_alt_rounded,
                        label: '${row.actions.length} action',
                        color: const Color(0xFF6366F1),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _approvalMetaPill({
    required IconData icon,
    required String label,
    Color color = AppColors.primary,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  IconData _approvalIcon(String doctype) => switch (doctype) {
    'Sales Order' => Icons.point_of_sale_rounded,
    'Purchase Order' => Icons.shopping_bag_rounded,
    'Purchase Invoice' => Icons.receipt_long_rounded,
    'Material Request' => Icons.assignment_turned_in_rounded,
    'Journal Entry' => Icons.auto_stories_rounded,
    'Tukar Guling' => Icons.swap_horiz_rounded,
    'Delivery Return' => Icons.assignment_return_rounded,
    'Reject' => Icons.highlight_off_rounded,
    _ => Icons.approval_outlined,
  };

  Color _approvalAccent(String doctype) => switch (doctype) {
    'Sales Order' => const Color(0xFF15803D),
    'Purchase Order' => const Color(0xFFEA580C),
    'Purchase Invoice' => const Color(0xFF0F766E),
    'Material Request' => const Color(0xFF4F46E5),
    'Journal Entry' => const Color(0xFF0284C7),
    'Tukar Guling' => const Color(0xFF7C3AED),
    'Delivery Return' => const Color(0xFF2563EB),
    'Reject' => const Color(0xFFE11D48),
    _ => const Color(0xFF0F766E),
  };

  String _approvalAmount(ErpApprovalTodo row) {
    if (row.doctype == 'Material Request') {
      return '${formatErpCurrency(row.amount)} qty';
    }
    if (row.doctype == 'Journal Entry') {
      return 'Debit Rp ${formatErpCurrency(row.amount)}';
    }
    return 'Rp ${formatErpCurrency(row.amount)}';
  }

  String _approvalShortLabel(String doctype) => switch (doctype) {
    'Purchase Order' => 'PO',
    'Purchase Invoice' => 'PI',
    'Material Request' => 'MR',
    'Journal Entry' => 'JE',
    'Sales Order' => 'SO',
    'Tukar Guling' => 'TG',
    'Delivery Return' => 'DR',
    'Reject' => 'RJ',
    _ => doctype,
  };

  int _compareApprovalTodos(ErpApprovalTodo a, ErpApprovalTodo b) {
    return _compareDateDesc(a.date, b.date);
  }

  int _compareDateDesc(String a, String b) {
    final left = DateTime.tryParse(a.trim());
    final right = DateTime.tryParse(b.trim());
    if (left == null && right == null) return b.compareTo(a);
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  }

  Map<String, int> _approvalTodoDoctypeCounts(List<ErpApprovalTodo> rows) {
    final counts = <String, int>{};
    for (final row in rows) {
      final doctype = row.doctype.trim();
      if (doctype.isEmpty) continue;
      counts[doctype] = (counts[doctype] ?? 0) + 1;
    }
    return counts;
  }

  Widget _errorBox(String message) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.danger.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      message,
      style: const TextStyle(
        color: AppColors.danger,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  BoxDecoration _cardDecoration({Color? accent}) {
    final color = accent ?? AppColors.primary;
    return BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: color.withValues(alpha: 0.13)),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.07),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

class _ErpApprovalDetailPage extends StatefulWidget {
  final ErpApprovalTodo approval;
  final FutureOr<void> Function() onChanged;

  const _ErpApprovalDetailPage({
    required this.approval,
    required this.onChanged,
  });

  @override
  State<_ErpApprovalDetailPage> createState() => _ErpApprovalDetailPageState();
}

class _ErpApprovalDetailPageState extends State<_ErpApprovalDetailPage> {
  Map<String, dynamic>? _detail;
  List<SalesOrderApprovalHistory> _activity = const [];
  List<String> _workflowActions = const [];
  String? _error;
  bool _loading = true;
  bool _processing = false;
  bool _addingApprover = false;
  bool _additionalApprovalProcessing = false;
  List<Map<String, dynamic>> _photos = const [];
  Map<String, String> _harianDates = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
      _workflowActions = widget.approval.actions;
    });
    try {
      final appState = context.read<TodoState>();
      Map<String, dynamic>? detail;
      try {
        detail = await appState.fetchApprovalDocument(
          doctype: widget.approval.doctype,
          name: widget.approval.name,
        );
      } catch (_) {}
      if (detail != null && mounted) {
        setState(() {
          _detail = detail;
          _loading = false;
        });
      }

      final freshFuture = appState.fetchApprovalDocument(
        doctype: widget.approval.doctype,
        name: widget.approval.name,
        forceRefresh: true,
      );
      final activityFuture = appState.fetchApprovalDocumentActivity(
        doctype: widget.approval.doctype,
        name: widget.approval.name,
      );

      Object? documentError;
      try {
        detail = await freshFuture;
      } catch (error) {
        documentError = error;
      }
      if (!mounted) return;
      setState(() {
        if (detail != null) _detail = detail;
        _error = documentError == null
            ? null
            : captureErpError(
                context,
                documentError,
                action: 'memuat detail approval',
              );
        _loading = false;
      });
      if (widget.approval.doctype == 'Tukar Guling' && detail != null) {
        final claims = tukarGulingDocumentRows(
          detail,
        ).where(tukarGulingRowIsClaim);
        final missing = [
          for (final claim in claims)
            if (tukarGulingClaimDate(claim).isEmpty)
              tukarGulingClaimSource(claim),
        ];
        if (missing.isNotEmpty) {
          try {
            final dates = await context
                .read<TukarGulingState>()
                .postingDatesByName(missing);
            if (mounted) setState(() => _harianDates = dates);
          } catch (_) {}
        } else if (mounted && _harianDates.isNotEmpty) {
          setState(() => _harianDates = const {});
        }
      }
      if (widget.approval.doctype == 'Tukar Guling') {
        try {
          final files = await appState.appState.fetchDocumentAttachments(
            doctype: widget.approval.doctype,
            documentName: widget.approval.name,
          );
          if (mounted) setState(() => _photos = files);
        } catch (_) {
          if (mounted) setState(() => _photos = const []);
        }
      }
      if (detail != null) {
        try {
          final loaded = await appState.fetchDocumentWorkflowActions(detail);
          if (loaded.isNotEmpty && mounted) {
            setState(() => _workflowActions = loaded);
          }
        } catch (_) {}
      }
      try {
        final activity = await activityFuture;
        if (mounted) setState(() => _activity = activity);
      } catch (_) {}
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = captureErpError(
            context,
            error,
            action: 'memuat detail approval',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseAction(String action) async {
    final reject = _isRejectAction(action);
    var reason = '';
    if (reject) {
      reason = await _askReason(action) ?? '';
      if (reason.trim().isEmpty || !mounted) return;
    } else {
      final ok = await confirmErpAction(
        context,
        title: '$action ${widget.approval.name}?',
        message: 'Lanjutkan action "$action" untuk dokumen ini?',
      );
      if (!ok || !mounted) return;
    }

    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await context.read<TodoState>().applyDocumentWorkflow(
        doctype: widget.approval.doctype,
        name: widget.approval.name,
        action: action,
        reason: reason,
        refreshAfterApply: false,
        waitForComment: false,
        currentDocument: _detail,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.approval.name}: action $action berhasil.'),
          backgroundColor: reject ? AppColors.danger : AppColors.success,
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<String?> _askReason(String action) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action - alasan wajib'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
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

  bool get _canAddAdditionalApprover {
    final state = _approvalWorkflowState;
    return widget.approval.doctype == 'Sales Order' &&
        _stateKey(state) == _stateKey('Pending for Lead') &&
        !_loading &&
        !_processing &&
        !_addingApprover &&
        !_additionalApprovalProcessing;
  }

  String get _approvalWorkflowState {
    final detailState = _text(_detail?['workflow_state']);
    return detailState.isNotEmpty ? detailState : widget.approval.workflowState;
  }

  String _stateKey(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _openAddApprover() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const _ApproverPickerSheet(),
    );
    if (selected == null || selected.trim().isEmpty || !mounted) return;
    final reason = await _askAdditionalApprovalReason();
    if (reason == null || reason.trim().isEmpty || !mounted) return;

    setState(() {
      _addingApprover = true;
      _error = null;
    });
    try {
      await context.read<TodoState>().addSalesOrderAdditionalApprover(
        salesOrder: widget.approval.name,
        approver: selected,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Additional approver $selected ditambahkan.'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadDetail();
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _addingApprover = false);
    }
  }

  Future<String?> _askAdditionalApprovalReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alasan Additional Approval'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Reason / Note',
            hintText: 'Contoh: butuh approval direksi karena diskon khusus.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _decideAdditionalApproval({
    required Map<String, dynamic> row,
    required bool approved,
  }) async {
    final note = await _askAdditionalDecisionNote(approved: approved) ?? '';
    if (note.trim().isEmpty || !mounted) return;

    setState(() {
      _additionalApprovalProcessing = true;
      _error = null;
    });
    try {
      await context.read<TodoState>().decideSalesOrderAdditionalApproval(
        salesOrder: widget.approval.name,
        approverRow: row,
        approved: approved,
        reason: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Additional approval ${approved ? 'approved' : 'rejected'}.',
          ),
          backgroundColor: approved ? AppColors.success : AppColors.danger,
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _additionalApprovalProcessing = false);
    }
  }

  Future<String?> _askAdditionalDecisionNote({required bool approved}) {
    final controller = TextEditingController();
    final title = approved ? 'Approve Additional' : 'Reject Additional';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title - Note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: 'Note',
            hintText: approved
                ? 'Tulis catatan approval.'
                : 'Tulis alasan reject.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Submit'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final items = _documentItemRows(detail);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 72,
        title: const Text(
          'Detail Approval',
          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              tooltip: 'Refresh',
              onPressed: _loading || _processing ? null : _loadDetail,
              icon: const Icon(Icons.sync_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.softGreen,
                foregroundColor: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
      body: TmsxResponsiveBody(
        maxWidth: 680,
        child: RefreshIndicator(
          onRefresh: _loadDetail,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: TmsxResponsive.pagePadding(context, top: 14, bottom: 28),
            children: [
              if (widget.approval.doctype == 'Sales Order' && detail != null)
                _salesOrderDocument(detail)
              else
                _detailHeader(),
              if (_loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                _errorBox(_error!),
              ],
              if (detail != null &&
                  widget.approval.doctype != 'Sales Order') ...[
                const SizedBox(height: 12),

                _sectionCard(
                  title: widget.approval.doctype == 'Material Request'
                      ? 'Kebutuhan'
                      : widget.approval.doctype == 'Tukar Guling'
                      ? 'Ringkasan'
                      : 'Nilai Dokumen',
                  children: _amountRows(detail),
                ),

                const SizedBox(height: 12),

                _sectionCard(
                  title: widget.approval.doctype == 'Tukar Guling'
                      ? _tukarItemsTitle(detail, items)
                      : 'Item (${items.length})',
                  children: _todoItemChildren(detail, items),
                ),

                if (widget.approval.doctype == 'Tukar Guling') ...[
                  const SizedBox(height: 12),
                  _ApprovalPhotoGrid(
                    files: _photos,
                    baseUrl: context
                        .read<TodoState>()
                        .appState
                        .frappeService
                        .baseUrl,
                    cookie: context
                        .read<TodoState>()
                        .appState
                        .frappeService
                        .sessionCookieHeader,
                  ),
                ],
              ],
              if (detail != null) ...[
                const SizedBox(height: 12),
                _decisionCard(detail),

                if (widget.approval.doctype == 'Sales Order') ...[
                  const SizedBox(height: 12),
                  _additionalApproverSection(detail),
                ],

                const SizedBox(height: 12),
                _activitySection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _salesOrderDocument(Map<String, dynamic> detail) {
    final order = SalesOrder.fromJson(detail);
    return SellingDocumentDetailView(
      title: order.id,
      subtitle: order.customer,
      statusText: order.effectiveStatusText,
      icon: Icons.point_of_sale_rounded,
      metrics: [
        SellingDetailMetric(
          label: 'Total',
          value: 'Rp ${formatErpCurrency(order.value)}',
          icon: Icons.payments_outlined,
        ),
        SellingDetailMetric(
          label: 'Items',
          value: '${order.itemsCount}',
          icon: Icons.inventory_2_outlined,
        ),
        SellingDetailMetric(
          label: 'Delivered',
          value: '${order.perDelivered.toStringAsFixed(1)}%',
          icon: Icons.local_shipping_outlined,
        ),
        SellingDetailMetric(
          label: 'Billed',
          value: '${order.perBilled.toStringAsFixed(1)}%',
          icon: Icons.receipt_long_outlined,
        ),
      ],
      infos: [
        SellingDetailInfo(
          label: 'Doc Status',
          value: docStatusLabel(order.docStatus),
        ),
        SellingDetailInfo(label: 'Date', value: order.date),
        if (order.sellingPriceList.isNotEmpty)
          SellingDetailInfo(label: 'Price List', value: order.sellingPriceList),
        if (order.currency.isNotEmpty)
          SellingDetailInfo(label: 'Currency', value: order.currency),
        SellingDetailInfo(
          label: 'Noted',
          value: order.noted.trim().isEmpty ? '-' : order.noted.trim(),
        ),
      ],
      items: order.items
          .map(
            (item) => SellingDetailItem(
              title: item.itemName,
              subtitle: item.itemCode,
              qty: '${item.qty}',
              rate: 'Rp ${formatErpCurrency(item.rate)}',
              discount: 'Rp ${formatErpCurrency(item.discountAmount)}',
              description: item.description,
              amount: 'Rp ${formatErpCurrency(item.qty * item.rate)}',
            ),
          )
          .toList(),
    );
  }

  Widget _detailHeader() {
    if (widget.approval.doctype == 'Tukar Guling') {
      return _tukarDetailHeader();
    }
    return _standardDetailHeader();
  }

  Widget _tukarDetailHeader() {
    final detail = _detail;
    final customer = detail == null
        ? widget.approval.partyLabel
        : (_text(detail['customer_name']).isNotEmpty
              ? _text(detail['customer_name'])
              : _text(detail['customer']));
    final date = detail == null
        ? widget.approval.date
        : (_text(detail['posting_date']).isNotEmpty
              ? _text(detail['posting_date'])
              : widget.approval.date);
    final shortDate = date.length >= 10 ? date.substring(0, 10) : date;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(accent: AppColors.primary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ErpStatusBadge(
                statusText: widget.approval.workflowState.isEmpty
                    ? widget.approval.status
                    : widget.approval.workflowState,
              ),
              if (shortDate.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  shortDate,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.approval.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (customer.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              customer,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _standardDetailHeader() => Container(
    padding: const EdgeInsets.all(18),
    decoration: _cardDecoration(accent: _detailAccent(widget.approval.doctype)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: _detailAccent(
                  widget.approval.doctype,
                ).withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(19),
              ),
              child: Icon(
                _detailIcon(widget.approval.doctype),
                color: _detailAccent(widget.approval.doctype),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _detailAccent(
                            widget.approval.doctype,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          widget.approval.moduleLabel,
                          style: TextStyle(
                            color: _detailAccent(widget.approval.doctype),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      ErpStatusBadge(
                        statusText: widget.approval.workflowState.isEmpty
                            ? widget.approval.status
                            : widget.approval.workflowState,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.approval.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          widget.approval.partyLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.slate,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _detailAccent(
              widget.approval.doctype,
            ).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            widget.approval.doctype == 'Material Request'
                ? '${formatErpCurrency(widget.approval.amount)} qty'
                : 'Rp ${formatErpCurrency(widget.approval.amount)}',
            style: TextStyle(
              color: _detailAccent(widget.approval.doctype),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (widget.approval.date.isNotEmpty)
              _detailMetaPill(
                icon: Icons.event_available_rounded,
                label: widget.approval.date,
                color: const Color(0xFF0EA5E9),
              ),
            _detailMetaPill(
              icon: Icons.task_alt_rounded,
              label:
                  '${(_workflowActions.isNotEmpty ? _workflowActions : widget.approval.actions).length} action tersedia',
              color: const Color(0xFF6366F1),
            ),
            _detailMetaPill(
              icon: Icons.description_outlined,
              label: docStatusLabel(widget.approval.docStatus),
              color: _detailAccent(widget.approval.doctype),
            ),
          ],
        ),
      ],
    ),
  );

  IconData _detailIcon(String doctype) => switch (doctype) {
    'Sales Order' => Icons.point_of_sale_rounded,
    'Purchase Order' => Icons.shopping_bag_rounded,
    'Purchase Invoice' => Icons.receipt_long_rounded,
    'Material Request' => Icons.assignment_turned_in_rounded,
    'Journal Entry' => Icons.auto_stories_rounded,
    'Tukar Guling' => Icons.swap_horiz_rounded,
    'Delivery Return' => Icons.assignment_return_rounded,
    'Reject' => Icons.highlight_off_rounded,
    _ => Icons.approval_outlined,
  };

  Color _detailAccent(String doctype) => switch (doctype) {
    'Sales Order' => const Color(0xFF16A34A),
    'Purchase Order' => const Color(0xFFF97316),
    'Purchase Invoice' => const Color(0xFF3B82F6),
    'Material Request' => const Color(0xFF6366F1),
    'Journal Entry' => const Color(0xFF0EA5E9),
    'Tukar Guling' => AppColors.primary,
    'Delivery Return' => AppColors.primary,
    'Reject' => AppColors.danger,
    _ => AppColors.primary,
  };

  Widget _detailMetaPill({
    required IconData icon,
    required String label,
    Color color = AppColors.primary,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.18)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  bool _isCancelAction(String action) {
    final value = action.trim().toLowerCase();
    return value == 'cancel' || value == 'cancelled' || value == 'batal';
  }

  bool _tukarIsFinal(
    Map<String, dynamic> detail,
    List<Map<String, dynamic>> rows,
  ) {
    final jenis = _text(detail['custom_jenis_input']).isNotEmpty
        ? _text(detail['custom_jenis_input'])
        : _text(detail['jenis_input']);
    return jenis.toLowerCase() == 'final' ||
        rows.any((row) => !tukarGulingRowIsClaim(row));
  }

  String _tukarItemsTitle(
    Map<String, dynamic> detail,
    List<Map<String, dynamic>> items,
  ) {
    return _tukarIsFinal(detail, items) ? 'Final Items' : 'Klaim Pengajuan';
  }

  List<Widget> _todoItemChildren(
    Map<String, dynamic> detail,
    List<Map<String, dynamic>> items,
  ) {
    if (widget.approval.doctype != 'Tukar Guling') {
      if (items.isEmpty) return [const Text('Tidak ada item.')];
      return items.map(_itemRow).toList();
    }
    final claims = items.where(tukarGulingRowIsClaim).toList();
    final shown = claims.isNotEmpty ? claims : items;
    if (shown.isEmpty) return [const Text('Tidak ada item.')];
    final claimKg = claims.fold<double>(0, (sum, row) {
      final text = tukarGulingRowText(row, ['qty_kg', 'allocated_kg', 'qty']);
      return sum + (double.tryParse(text.replaceAll(',', '.')) ?? 0);
    });
    return [
      for (final item in shown)
        tukarGulingTodoItemCard(item, sourceDates: _harianDates),
      if (claims.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Total kg',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${formatTukarGulingQty(claimKg)} kg',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _amountRows(Map<String, dynamic> detail) {
    if (widget.approval.doctype == 'Tukar Guling') {
      final tukarRows = tukarGulingDocumentRows(detail);
      final claims = tukarRows.where(tukarGulingRowIsClaim);
      final isFinalTukar = _tukarIsFinal(detail, tukarRows);
      final gottenBox = tukarGulingGottenBoxQty(
        tukarRows.where((row) => !tukarGulingRowIsClaim(row)),
      );
      final storedBox =
          double.tryParse(detail['custom_total_box']?.toString() ?? '') ?? 0;
      final boxLabel = formatTukarGulingQty(
        gottenBox > 0 ? gottenBox : storedBox,
      );
      final claimKg = claims.fold<double>(0, (sum, row) {
        final text = tukarGulingRowText(row, ['qty_kg', 'allocated_kg', 'qty']);
        return sum + (double.tryParse(text.replaceAll(',', '.')) ?? 0);
      });
      final jenis = _text(detail['custom_jenis_input']).isNotEmpty
          ? _text(detail['custom_jenis_input'])
          : _text(detail['jenis_input']);
      final metode = _text(detail['custom_metode_final']);
      final process = tukarGulingProcessKg(detail);
      return [
        if (isFinalTukar) _detailRow('Total box', boxLabel),
        if (isFinalTukar)
          _detailRow('Total kg', '${formatTukarGulingQty(claimKg)} kg'),
        if (isFinalTukar)
          _detailRow(
            'Kg diproses',
            '${formatTukarGulingQty(process.processedKg)} kg',
          ),
        if (isFinalTukar)
          _detailRow(
            'Sisa kg',
            '${formatTukarGulingQty(process.remainingKg)} kg',
          ),
        if (jenis.isNotEmpty) _detailRow('Jenis', tukarGulingJenisLabel(jenis)),
        if (metode.isNotEmpty) _detailRow('Metode', metode),
        _detailRow('Company', _text(detail['company'])),
        _detailRow('Dibuat oleh', _text(detail['owner'])),
      ];
    }
    if (widget.approval.doctype == 'Material Request') {
      return [
        _detailRow('Total Qty', formatErpCurrency(detail['total_qty'])),
        _detailRow('Status Dokumen', docStatusLabel(widget.approval.docStatus)),
      ];
    }
    if (widget.approval.doctype == 'Journal Entry') {
      return [
        _moneyRow('Total Debit', detail['total_debit']),
        _moneyRow('Total Credit', detail['total_credit']),
        _detailRow('Status Dokumen', docStatusLabel(widget.approval.docStatus)),
      ];
    }
    final hasMoney =
        NumParse.asDouble(
          detail['grand_total'] ??
              detail['rounded_total'] ??
              detail['net_total'],
        ) >
        0;
    if (!hasMoney) {
      final tukarRows = widget.approval.doctype == 'Tukar Guling'
          ? tukarGulingDocumentRows(detail)
          : const <Map<String, dynamic>>[];
      final jenis = _text(detail['custom_jenis_input']).isNotEmpty
          ? _text(detail['custom_jenis_input'])
          : _text(detail['jenis_input']);
      final isFinalTukar =
          widget.approval.doctype == 'Tukar Guling' &&
          (jenis.toLowerCase() == 'final' ||
              tukarRows.any((row) => !tukarGulingRowIsClaim(row)));
      final gottenBox = tukarGulingGottenBoxQty(
        tukarRows.where((row) => !tukarGulingRowIsClaim(row)),
      );
      final storedBox =
          double.tryParse(detail['custom_total_box']?.toString() ?? '') ?? 0;
      final boxLabel = formatTukarGulingQty(
        gottenBox > 0 ? gottenBox : storedBox,
      );
      return [
        _detailRow(
          'Customer',
          _text(detail['customer_name']).isNotEmpty
              ? _text(detail['customer_name'])
              : _text(detail['customer']),
        ),
        _detailRow('Company', _text(detail['company'])),
        _detailRow(
          'Tanggal',
          _text(detail['posting_date']).isNotEmpty
              ? _text(detail['posting_date'])
              : _text(detail['transaction_date']),
        ),
        if (isFinalTukar) _detailRow('Box', boxLabel),
        if (isFinalTukar)
          _detailRow(
            'Kg diproses',
            '${formatTukarGulingQty(tukarGulingProcessKg(detail).processedKg)} kg',
          ),
        if (isFinalTukar)
          _detailRow(
            'Sisa belum diganti',
            '${formatTukarGulingQty(tukarGulingProcessKg(detail).remainingKg)} kg',
          ),
        _detailRow('Keterangan', _text(detail['keterangan'])),
        _detailRow(
          'Workflow',
          _text(detail['workflow_state']).isNotEmpty
              ? _text(detail['workflow_state'])
              : widget.approval.workflowState,
        ),
        _detailRow('Status Dokumen', docStatusLabel(widget.approval.docStatus)),
      ];
    }
    return [
      _moneyRow('Subtotal', detail['net_total']),
      _moneyRow('Diskon', detail['discount_amount']),
      _moneyRow('Pajak & Biaya', detail['total_taxes_and_charges']),
      _moneyRow('Outstanding', detail['outstanding_amount']),
      _moneyRow('Grand Total', detail['grand_total'], emphasized: true),
    ];
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Divider(height: 24),
        ...children,
      ],
    ),
  );

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _moneyRow(String label, dynamic value, {bool emphasized = false}) {
    final formatted = 'Rp ${formatErpCurrency(NumParse.asDouble(value))}';
    if (!emphasized) return _detailRow(label, formatted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            formatted,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(Map<String, dynamic> item) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _text(item['item_name']).isEmpty
                ? _text(item['item_code'])
                : _text(item['item_name']),
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _detailMetaPill(
                icon: Icons.inventory_2_outlined,
                label: '${_number(item['qty'])} ${_text(item['uom'])}',
              ),
              _detailMetaPill(
                icon: Icons.sell_outlined,
                label:
                    'Rp ${formatErpCurrency(NumParse.asDouble(item['rate']))}',
              ),
              _detailMetaPill(
                icon: Icons.discount_outlined,
                label: 'Diskon ${_itemDiscountLabel(item)}',
              ),
              _detailMetaPill(
                icon: Icons.payments_outlined,
                label:
                    'Rp ${formatErpCurrency(NumParse.asDouble(item['amount']))}',
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _decisionCard(Map<String, dynamic> detail) {
    final hasPendingAdditional = _hasPendingAdditionalApprovals(detail);
    final source = hasPendingAdditional
        ? const <String>[]
        : (_workflowActions.isNotEmpty
              ? _workflowActions
              : widget.approval.actions);
    final actions = widget.approval.doctype == 'Tukar Guling'
        ? source.where((action) => !_isCancelAction(action)).toList()
        : source;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            actions.length == 1 &&
                    actions.first.toLowerCase() == 'submit' &&
                    widget.approval.workflowState.trim().isEmpty
                ? 'Submit Dokumen'
                : 'Keputusan Approval',
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            actions.length == 1 &&
                    actions.first.toLowerCase() == 'submit' &&
                    widget.approval.workflowState.trim().isEmpty
                ? 'Dokumen masih Draft. Submit mengubahnya menjadi Submitted sesuai izin role.'
                : 'Periksa detail, lalu pilih action sesuai Workflow ERPNext.',
            style: const TextStyle(color: AppColors.slate, fontSize: 11),
          ),
          const SizedBox(height: 16),
          if (_processing)
            const LinearProgressIndicator()
          else if (hasPendingAdditional)
            const Text(
              'Workflow utama dikunci sampai semua Additional Approval selesai.',
              style: TextStyle(
                color: AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (actions.isEmpty)
            const Text(
              'Tidak ada workflow action untuk user ini.',
              style: TextStyle(
                color: AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            ...actions.map((action) {
              final reject = _isRejectAction(action);
              final button = reject
                  ? OutlinedButton.icon(
                      onPressed: () => _chooseAction(action),
                      icon: const Icon(Icons.close_rounded),
                      label: Text(action),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () => _chooseAction(action),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(action),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    );
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: button,
              );
            }),
        ],
      ),
    );
  }

  Widget _additionalApproverSection(Map<String, dynamic> detail) {
    final approvers = _additionalApproverRows(detail);
    return _sectionCard(
      title: 'Additional Approval',
      children: [
        if (approvers.isEmpty)
          const Text(
            'Belum ada additional approver.',
            style: TextStyle(
              color: AppColors.slate,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          )
        else
          ...approvers.map(_approverRow),
        if (_canAddAdditionalApprover &&
            !_hasPendingAdditionalForCurrentUser(detail)) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _openAddApprover,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add Approver'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ] else if (_addingApprover) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ] else ...[
          const SizedBox(height: 10),
          Text(
            'Add Approver aktif setelah Sales Order masuk workflow Pending for Lead. '
            'Saat ini: ${_approvalWorkflowState.isEmpty ? '-' : _approvalWorkflowState}.',
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  List<Map<String, dynamic>> _additionalApproverRows(
    Map<String, dynamic> detail,
  ) {
    return _mapRows(
      detail['approvers'] ??
          detail['additional_approvers'] ??
          detail['additional_approval'] ??
          detail['custom_approvers'] ??
          detail['custom_additional_approvers'],
    );
  }

  bool _hasPendingAdditionalApprovals(Map<String, dynamic> detail) {
    return _additionalApproverRows(detail).any((row) {
      final approvalType = _text(row['approval_type']).isEmpty
          ? 'additional'
          : _text(row['approval_type']).toLowerCase();
      final status = _text(row['status']).isEmpty
          ? 'pending'
          : _text(row['status']).toLowerCase();
      return approvalType == 'additional' && status == 'pending';
    });
  }

  bool _hasPendingAdditionalForCurrentUser(Map<String, dynamic> detail) {
    final currentUser = context.read<TodoState>().currentUser?.trim() ?? '';
    if (currentUser.isEmpty) return false;
    return _additionalApproverRows(detail).any((row) {
      final approver = _text(row['approver']);
      final approvalType = _text(row['approval_type']).isEmpty
          ? 'additional'
          : _text(row['approval_type']).toLowerCase();
      final status = _text(row['status']).isEmpty
          ? 'pending'
          : _text(row['status']).toLowerCase();
      return approver.toLowerCase() == currentUser.toLowerCase() &&
          approvalType == 'additional' &&
          status == 'pending';
    });
  }

  Widget _approverRow(Map<String, dynamic> row) {
    final approver = _text(row['approver']);
    final approvalType = _text(row['approval_type']).isEmpty
        ? 'Additional'
        : _text(row['approval_type']);
    final status = _text(row['status']).isEmpty
        ? 'Pending'
        : _text(row['status']);
    final requestedBy = _text(row['requested_by']);
    final reason = _firstText(row, const [
      'reason',
      'remarks',
      'remark',
      'description',
    ]);
    final note = _text(row['note']);
    final isPending = status.toLowerCase() == 'pending';
    final isRejected = status.toLowerCase() == 'rejected';
    final color = isPending
        ? const Color(0xFFF59E0B)
        : isRejected
        ? AppColors.danger
        : AppColors.success;
    final canDecide = _canDecideAdditionalApproval(row);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.14),
                foregroundColor: color,
                child: Text(
                  _initials(approver),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      approver.isEmpty ? '-' : approver,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      requestedBy.isEmpty
                          ? approvalType
                          : '$approvalType | requested by $requestedBy',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Reason: $reason',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (note.isNotEmpty && note != reason) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Note: $note',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ErpStatusBadge(statusText: status),
            ],
          ),
          if (canDecide) ...[
            const SizedBox(height: 12),
            if (_additionalApprovalProcessing)
              const LinearProgressIndicator()
            else
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          _decideAdditionalApproval(row: row, approved: true),
                      icon: const Icon(Icons.check_rounded, size: 17),
                      label: const Text('Approve'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _decideAdditionalApproval(row: row, approved: false),
                      icon: const Icon(Icons.close_rounded, size: 17),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        minimumSize: const Size.fromHeight(42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  bool _canDecideAdditionalApproval(Map<String, dynamic> row) {
    if (widget.approval.doctype != 'Sales Order') return false;
    if (_loading ||
        _processing ||
        _addingApprover ||
        _additionalApprovalProcessing) {
      return false;
    }
    final currentUser = context.read<TodoState>().currentUser?.trim() ?? '';
    if (currentUser.isEmpty) return false;
    final approver = _text(row['approver']);
    final approvalType = _text(row['approval_type']).isEmpty
        ? 'additional'
        : _text(row['approval_type']).toLowerCase();
    final status = _text(row['status']).isEmpty
        ? 'pending'
        : _text(row['status']).toLowerCase();
    return approver.toLowerCase() == currentUser.toLowerCase() &&
        approvalType == 'additional' &&
        status == 'pending';
  }

  List<SalesOrderApprovalHistory> get _visibleActivity {
    final rows = [..._activity];
    final hasCreated = rows.any(
      (row) => row.content.toLowerCase().contains('created this'),
    );
    if (!hasCreated) {
      final owner = _text(_detail?['owner']).isNotEmpty
          ? _text(_detail?['owner'])
          : widget.approval.owner.trim();
      if (owner.isNotEmpty) {
        rows.add(
          SalesOrderApprovalHistory(
            id: '${widget.approval.doctype}::${widget.approval.name}::created',
            doctype: widget.approval.doctype,
            salesOrder: widget.approval.name,
            content: 'created this',
            actor: owner,
            createdAt: _text(_detail?['creation']),
          ),
        );
      }
    }
    rows.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows;
  }

  Widget _activitySection() {
    final activity = _visibleActivity;
    return _sectionCard(
      title: 'Activity',
      children: activity.isEmpty
          ? [const Text('Belum ada activity dokumen.')]
          : activity.take(20).map(_activityRow).toList(),
    );
  }

  Widget _activityRow(SalesOrderApprovalHistory item) {
    final content = _plainText(item.content);
    final actor = item.actor.isEmpty ? 'Unknown' : item.actor;
    final action = _activityActionLabel(content);
    final color = _activityColor(content);
    final showBody =
        content.isNotEmpty && content.toLowerCase().trim() != action;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: actor,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text: ' $action',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.createdAt.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.createdAt,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 10,
                    ),
                  ),
                ],
                if (showBody) ...[
                  const SizedBox(height: 5),
                  Text(
                    content,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11,
                      height: 1.35,
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

  Color _activityColor(String content) {
    final plain = content.toLowerCase();
    if (plain.contains('reject')) return AppColors.danger;
    if (plain.contains('approve') || plain.contains('submit')) {
      return AppColors.success;
    }
    return AppColors.slate;
  }

  String _activityActionLabel(String content) {
    final plain = content.toLowerCase();
    if (plain.contains('reject')) return 'rejected';
    if (plain.contains('approve')) return 'approved';
    if (plain.contains('submit')) return 'submitted';
    if (plain.contains('created this') || plain.trim() == 'created') {
      return 'created this';
    }
    if (plain.contains('last edited this')) return 'last edited this';
    if (plain.contains('changed') || plain.contains('edited')) return 'updated';
    return 'activity';
  }

  Widget _errorBox(String message) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.danger.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      message,
      style: const TextStyle(
        color: AppColors.danger,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  BoxDecoration _cardDecoration({Color? accent}) {
    final color = accent ?? AppColors.primary;
    return BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: color.withValues(alpha: 0.13)),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.07),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _mapRows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  List<Map<String, dynamic>> _documentItemRows(Map<String, dynamic>? detail) {
    if (detail == null) return const [];
    if (widget.approval.doctype == 'Tukar Guling') {
      return tukarGulingDocumentRows(detail);
    }
    for (final key in const [
      'items',
      'tukar_guling_item',
      'tukar_guling_items',
      'reject_item',
      'reject_items',
    ]) {
      final rows = _mapRows(detail[key]);
      if (rows.isNotEmpty) return rows;
    }
    return const [];
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _firstText(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = _text(row[key]);
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return '';
  }

  String _plainText(String value) => value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();

  String _number(dynamic value) {
    final number = NumParse.asDouble(value);
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toStringAsFixed(2);
  }

  String _initials(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '?';
    final parts = clean
        .replaceAll('@', ' ')
        .replaceAll('.', ' ')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return clean.characters.first.toUpperCase();
    return parts
        .take(2)
        .map((part) => part.characters.first)
        .join()
        .toUpperCase();
  }

  bool _isRejectAction(String action) {
    final normalized = action.toLowerCase();
    return normalized.contains('reject') ||
        normalized.contains('tolak') ||
        normalized.contains('decline') ||
        normalized.contains('return');
  }
}

class _ApprovalPhotoGrid extends StatelessWidget {
  final List<Map<String, dynamic>> files;
  final String baseUrl;
  final String? cookie;

  const _ApprovalPhotoGrid({
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
                final name =
                    file['file_name']?.toString().trim().isNotEmpty == true
                    ? file['file_name'].toString()
                    : 'Foto ${index + 1}';
                return InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _ApprovalPhotoPage(
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

class _ApprovalPhotoPage extends StatelessWidget {
  final String title;
  final String imageUrl;
  final String? cookie;

  const _ApprovalPhotoPage({
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

class _ApproverPickerSheet extends StatefulWidget {
  const _ApproverPickerSheet();

  @override
  State<_ApproverPickerSheet> createState() => _ApproverPickerSheetState();
}

class _ApproverPickerSheetState extends State<_ApproverPickerSheet> {
  final _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<TodoState>().fetchEnabledUsersForApproval();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Pilih Additional Approver',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Cari nama atau email user...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _search.clear,
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _pickerMessage(
                        'Gagal memuat user: ${snapshot.error}',
                      );
                    }
                    final users = (snapshot.data ?? const []).where((row) {
                      final email = _text(row['name']).toLowerCase();
                      final fullName = _text(row['full_name']).toLowerCase();
                      return query.isEmpty ||
                          email.contains(query) ||
                          fullName.contains(query);
                    }).toList();
                    if (users.isEmpty) {
                      return _pickerMessage('User tidak ditemukan.');
                    }
                    return ListView.separated(
                      itemCount: users.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final row = users[index];
                        final email = _text(row['name']);
                        final fullName = _text(row['full_name']);
                        return Material(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.pop(context, email),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppColors.softGreen,
                                    foregroundColor: AppColors.primary,
                                    child: Text(
                                      _initials(
                                        fullName.isEmpty ? email : fullName,
                                      ),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fullName.isEmpty ? email : fullName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.navy,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        if (fullName.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            email,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.slate,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppColors.slate,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pickerMessage(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.slate,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static String _initials(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '?';
    final parts = clean
        .replaceAll('@', ' ')
        .replaceAll('.', ' ')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return clean.characters.first.toUpperCase();
    return parts
        .take(2)
        .map((part) => part.characters.first)
        .join()
        .toUpperCase();
  }
}
