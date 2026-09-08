import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/erp_approval_todo.dart';
import '../../models/sales_order_approval.dart';
import '../../state/todo/todo_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/erp_doc_utils.dart';
import '../../utils/erp_format.dart';
import '../../utils/num_parse.dart';
import '../../widgets/erp/erp_empty_state.dart';
import '../../widgets/erp/erp_status_badge.dart';
import '../../widgets/erp/erp_status_chip_bar.dart';
import '../../widgets/erp/erp_workflow_helper.dart';
import '../../widgets/responsive/responsive_layout.dart';

enum _ApprovalTodoSortOption { newest, oldest, amountHigh, amountLow }

enum _ApprovalReviewFilter {
  todo,
  done,
  submitted,
  approved,
  rejected,
  cancelled,
}

String _itemDiscountLabel(Map<String, dynamic> item) {
  final amount = NumParse.asDouble(item['discount_amount']);
  final percentage = NumParse.asDouble(item['discount_percentage']);
  final amountLabel = 'Rp ${formatErpCurrency(amount)}';
  if (percentage <= 0) return amountLabel;
  return '$amountLabel (${percentage.toStringAsFixed(2)}%)';
}

class SalesOrderApprovalScreen extends StatefulWidget {
  final bool embedded;
  final String title;
  final Set<String>? doctypeFilter;
  final bool showHistoryTab;

  const SalesOrderApprovalScreen({
    super.key,
    this.embedded = false,
    this.title = 'Approval Dokumen',
    this.doctypeFilter,
    this.showHistoryTab = true,
  });

  @override
  State<SalesOrderApprovalScreen> createState() =>
      _SalesOrderApprovalScreenState();
}

class _SalesOrderApprovalScreenState extends State<SalesOrderApprovalScreen> {
  final _search = TextEditingController();
  List<ErpApprovalTodo> _rows = const [];
  List<SalesOrderApprovalHistory> _history = const [];
  Timer? _syncTimer;
  Future<void>? _loadInFlight;
  bool _loading = true;
  String? _error;
  String? _historyError;
  String? _doctypeQuickFilter;
  String? _statusQuickFilter;
  _ApprovalReviewFilter _reviewFilter = _ApprovalReviewFilter.todo;
  _ApprovalTodoSortOption _sortOption = _ApprovalTodoSortOption.newest;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
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
      unawaited(_load(silent: cachedRows.isNotEmpty, forceRefresh: true));
      _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) {
        if (mounted) _load(silent: true, forceRefresh: true);
      });
    });
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
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
        _historyError = null;
      });
    }
    final appState = context.read<TodoState>();
    try {
      final rows = await appState.fetchApprovalTodos(
        forceRefresh: forceRefresh,
      );
      final filtered = _filterRows(rows);
      if (!mounted) return;
      setState(() => _rows = filtered);
    } catch (error) {
      if (!silent && mounted) setState(() => _error = _friendlyError(error));
    }
    if (widget.showHistoryTab) {
      try {
        final history = await appState.fetchSalesOrderApprovalHistory();
        if (mounted) setState(() => _history = history);
      } catch (error) {
        if (!silent && mounted) {
          setState(() => _historyError = _friendlyError(error));
        }
      }
    }
    if (!silent && mounted) setState(() => _loading = false);
  }

  List<ErpApprovalTodo> _filterRows(List<ErpApprovalTodo> rows) {
    final filter = widget.doctypeFilter;
    if (filter == null) return rows;
    return rows.where((row) => filter.contains(row.doctype)).toList();
  }

  Future<void> _selectApproval(ErpApprovalTodo approval) async {
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
    final query = _search.text.trim().toLowerCase();
    final allHistoryGroups = _groupedHistory();
    final reviewTabs = _availableReviewFilters(allHistoryGroups);
    final activeHistoryGroups = allHistoryGroups
        .where(
          (group) => _historyGroupMatchesReviewFilter(group, _reviewFilter),
        )
        .toList();
    final doctypeCounts = _reviewFilter == _ApprovalReviewFilter.todo
        ? _approvalTodoDoctypeCounts(_rows)
        : _approvalHistoryDoctypeCounts(activeHistoryGroups);
    final doctypeOptions = _sortedDoctypes(doctypeCounts.keys);
    final effectiveDoctypeFilter =
        doctypeCounts.containsKey(_doctypeQuickFilter)
        ? _doctypeQuickFilter
        : null;
    final baseRows = _rows.where((row) {
      final matchType =
          effectiveDoctypeFilter == null ||
          row.doctype == effectiveDoctypeFilter;
      final matchSearch =
          query.isEmpty ||
          row.name.toLowerCase().contains(query) ||
          row.doctype.toLowerCase().contains(query) ||
          row.party.toLowerCase().contains(query) ||
          row.partyName.toLowerCase().contains(query) ||
          row.workflowState.toLowerCase().contains(query);
      return matchType && matchSearch;
    }).toList();
    final historyGroups = _filteredHistoryGroups(
      query,
      doctypeFilter: effectiveDoctypeFilter,
    );
    final statusOptions = _approvalStatusOptions(baseRows);
    final statusCounts = _approvalStatusCounts(baseRows);
    final rows = baseRows.where((row) {
      return _statusQuickFilter == null ||
          _approvalStatus(row).toLowerCase() ==
              _statusQuickFilter!.toLowerCase();
    }).toList();
    rows.sort(_compareApprovalTodos);
    final visibleCount = _reviewFilter == _ApprovalReviewFilter.todo
        ? rows.length
        : historyGroups.length;
    final totalCount = _reviewFilter == _ApprovalReviewFilter.todo
        ? _rows.length
        : _reviewCount(_reviewFilter, allHistoryGroups);
    return RefreshIndicator(
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 90),
        children: [
          _ApprovalReviewTabBar(
            selected: _reviewFilter,
            tabs: reviewTabs,
            countFor: (filter) => _reviewCount(filter, allHistoryGroups),
            labelFor: _reviewFilterLabel,
            onChanged: (filter) {
              setState(() {
                _reviewFilter = filter;
                _statusQuickFilter = null;
              });
            },
          ),
          const SizedBox(height: 12),
          _approvalSearchBox(
            visibleCount: visibleCount,
            totalCount: totalCount,
            doctypeCounts: doctypeCounts,
            statusOptions: statusOptions,
            statusCounts: statusCounts,
            allStatusCount: baseRows.length,
            doctypeOptions: doctypeOptions,
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _errorBox(_error!),
          ],
          if (_historyError != null &&
              _reviewFilter != _ApprovalReviewFilter.todo) ...[
            const SizedBox(height: 12),
            _errorBox(_historyError!),
          ],
          const SizedBox(height: 16),
          if (_reviewFilter == _ApprovalReviewFilter.todo &&
              rows.isEmpty &&
              !_loading)
            const ErpEmptyState(
              title: 'Todo approval sudah kosong',
              message:
                  'Hanya action Workflow yang tersedia untuk role login yang ditampilkan.',
            )
          else if (_reviewFilter == _ApprovalReviewFilter.todo)
            TmsxResponsiveCardGrid(
              wideTabletColumns: 2,
              desktopColumns: 3,
              children: rows.map(_approvalCard).toList(),
            ),
          if (_reviewFilter != _ApprovalReviewFilter.todo &&
              historyGroups.isEmpty &&
              !_loading)
            const ErpEmptyState(
              title: 'Belum ada approval selesai',
              message:
                  'Dokumen yang sudah pernah di-approve/reject dari aplikasi akan muncul di sini.',
            )
          else if (_reviewFilter != _ApprovalReviewFilter.todo)
            TmsxResponsiveCardGrid(
              wideTabletColumns: 2,
              desktopColumns: 3,
              children: historyGroups.map(_historyGroupCard).toList(),
            ),
        ],
      ),
    );
  }

  Widget _approvalSearchBox({
    required int visibleCount,
    required int totalCount,
    required Map<String, int> doctypeCounts,
    required List<String> statusOptions,
    required Map<String, int> statusCounts,
    required int allStatusCount,
    required List<String> doctypeOptions,
  }) {
    final hasActiveFilter =
        _search.text.trim().isNotEmpty ||
        _doctypeQuickFilter != null ||
        _statusQuickFilter != null ||
        _reviewFilter != _ApprovalReviewFilter.todo ||
        _sortOption != _ApprovalTodoSortOption.newest;
    final selectedDoctype = doctypeOptions.contains(_doctypeQuickFilter)
        ? _doctypeQuickFilter
        : null;
    return Column(
      children: [
        _ApprovalCompactFilterBar(
          title: selectedDoctype == null
              ? 'Semua dokumen ($totalCount)'
              : '${_approvalShortLabel(selectedDoctype)} - $selectedDoctype (${doctypeCounts[selectedDoctype] ?? 0})',
          subtitle: _approvalSortLabel(_sortOption),
          hasActiveFilter: hasActiveFilter,
          onOpenFilter: () => _openApprovalFilterSheet(
            totalCount: totalCount,
            doctypeCounts: doctypeCounts,
            doctypeOptions: doctypeOptions,
            selectedDoctype: selectedDoctype,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.cardShadow,
          ),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search SO or customer...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Bersihkan pencarian',
                      onPressed: _search.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: Colors.transparent,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 16,
              ),
              isDense: true,
            ),
          ),
        ),
        if (_reviewFilter == _ApprovalReviewFilter.todo) ...[
          const SizedBox(height: 14),
          ErpStatusChipBar<String?>(
            selected: _statusQuickFilter,
            onSelected: (status) => setState(() => _statusQuickFilter = status),
            chips: [
              ErpStatusChip<String?>(
                label: 'All',
                value: null,
                count: allStatusCount,
              ),
              ...statusOptions.map(
                (status) => ErpStatusChip<String?>(
                  label: status,
                  value: status,
                  count: statusCounts[status] ?? 0,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(
              Icons.filter_list_rounded,
              size: 16,
              color: AppColors.slate,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$visibleCount dari $totalCount dokumen ditampilkan',
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openApprovalFilterSheet({
    required int totalCount,
    required Map<String, int> doctypeCounts,
    required List<String> doctypeOptions,
    required String? selectedDoctype,
  }) async {
    final result = await showModalBottomSheet<_ApprovalFilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => _ApprovalFilterSheet(
        totalCount: totalCount,
        doctypeCounts: doctypeCounts,
        doctypeOptions: doctypeOptions,
        selectedDoctype: selectedDoctype,
        selectedSort: _sortOption,
        labelForDoctype: (doctype) =>
            '${_approvalShortLabel(doctype)} - $doctype (${doctypeCounts[doctype] ?? 0})',
        labelForSort: _approvalSortLabel,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _doctypeQuickFilter = result.doctype;
      _sortOption = result.sort;
    });
  }

  Widget _approvalCard(ErpApprovalTodo row) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: () => _selectApproval(row),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(accent: _approvalAccent(row.doctype)),
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
                      child: Icon(_approvalIcon(row.doctype), color: accent),
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
                                    borderRadius: BorderRadius.circular(999),
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
    _ => Icons.approval_outlined,
  };

  Color _approvalAccent(String doctype) => switch (doctype) {
    'Sales Order' => const Color(0xFF16A34A),
    'Purchase Order' => const Color(0xFFF97316),
    'Purchase Invoice' => const Color(0xFF3B82F6),
    'Material Request' => const Color(0xFF6366F1),
    'Journal Entry' => const Color(0xFF0EA5E9),
    _ => AppColors.primary,
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
    _ => doctype,
  };

  int _compareApprovalTodos(ErpApprovalTodo a, ErpApprovalTodo b) {
    return switch (_sortOption) {
      _ApprovalTodoSortOption.newest => _compareDateDesc(a.date, b.date),
      _ApprovalTodoSortOption.oldest => _compareDateAsc(a.date, b.date),
      _ApprovalTodoSortOption.amountHigh => b.amount.compareTo(a.amount),
      _ApprovalTodoSortOption.amountLow => a.amount.compareTo(b.amount),
    };
  }

  int _compareDateDesc(String a, String b) {
    final left = DateTime.tryParse(a.trim());
    final right = DateTime.tryParse(b.trim());
    if (left == null && right == null) return b.compareTo(a);
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  }

  int _compareDateAsc(String a, String b) {
    final left = DateTime.tryParse(a.trim());
    final right = DateTime.tryParse(b.trim());
    if (left == null && right == null) return a.compareTo(b);
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }

  String _approvalSortLabel(_ApprovalTodoSortOption option) {
    return switch (option) {
      _ApprovalTodoSortOption.newest => 'Newest',
      _ApprovalTodoSortOption.oldest => 'Oldest',
      _ApprovalTodoSortOption.amountHigh => 'Nilai tertinggi',
      _ApprovalTodoSortOption.amountLow => 'Nilai terendah',
    };
  }

  String _approvalStatus(ErpApprovalTodo row) {
    final workflowState = row.workflowState.trim();
    if (workflowState.isNotEmpty) return workflowState;
    final status = row.status.trim();
    return status.isEmpty ? 'Tanpa status' : status;
  }

  List<String> _approvalStatusOptions(List<ErpApprovalTodo> rows) {
    final statuses = rows.map(_approvalStatus).toSet().toList();
    statuses.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return statuses;
  }

  Map<String, int> _approvalStatusCounts(List<ErpApprovalTodo> rows) {
    final counts = <String, int>{};
    for (final row in rows) {
      final status = _approvalStatus(row);
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
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

  Map<String, int> _approvalHistoryDoctypeCounts(
    List<_ApprovalHistoryGroup> groups,
  ) {
    final counts = <String, int>{};
    for (final group in groups) {
      final doctype = group.doctype.trim();
      if (doctype.isEmpty) continue;
      counts[doctype] = (counts[doctype] ?? 0) + 1;
    }
    return counts;
  }

  List<String> _sortedDoctypes(Iterable<String> values) {
    final doctypes = values
        .map((doctype) => doctype.trim())
        .where((doctype) => doctype.isNotEmpty)
        .toSet()
        .toList();
    doctypes.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return doctypes;
  }

  List<_ApprovalHistoryGroup> _filteredHistoryGroups(
    String query, {
    required String? doctypeFilter,
  }) {
    final groups = _groupedHistory().where((group) {
      if (!_historyGroupMatchesReviewFilter(group, _reviewFilter)) {
        return false;
      }
      final matchType = doctypeFilter == null || group.doctype == doctypeFilter;
      if (!matchType) return false;
      if (query.isEmpty) return true;
      final latest = group.latest;
      return group.documentName.toLowerCase().contains(query) ||
          group.doctype.toLowerCase().contains(query) ||
          latest.actor.toLowerCase().contains(query) ||
          latest.content.toLowerCase().contains(query) ||
          latest.createdAt.toLowerCase().contains(query);
    }).toList();
    groups.sort((a, b) {
      return switch (_sortOption) {
        _ApprovalTodoSortOption.newest => b.latest.createdAt.compareTo(
          a.latest.createdAt,
        ),
        _ApprovalTodoSortOption.oldest => a.latest.createdAt.compareTo(
          b.latest.createdAt,
        ),
        _ApprovalTodoSortOption.amountHigh ||
        _ApprovalTodoSortOption.amountLow => b.latest.createdAt.compareTo(
          a.latest.createdAt,
        ),
      };
    });
    return groups;
  }

  List<_ApprovalReviewFilter> _availableReviewFilters(
    List<_ApprovalHistoryGroup> historyGroups,
  ) {
    final filters = <_ApprovalReviewFilter>[_ApprovalReviewFilter.todo];
    if (historyGroups.isNotEmpty) filters.add(_ApprovalReviewFilter.done);
    for (final filter in const [
      _ApprovalReviewFilter.submitted,
      _ApprovalReviewFilter.approved,
      _ApprovalReviewFilter.rejected,
      _ApprovalReviewFilter.cancelled,
    ]) {
      if (_reviewCount(filter, historyGroups) > 0) filters.add(filter);
    }
    if (!filters.contains(_reviewFilter)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !filters.contains(_reviewFilter)) {
          setState(() => _reviewFilter = _ApprovalReviewFilter.todo);
        }
      });
    }
    return filters;
  }

  int _reviewCount(
    _ApprovalReviewFilter filter,
    List<_ApprovalHistoryGroup> historyGroups,
  ) {
    if (filter == _ApprovalReviewFilter.todo) return _rows.length;
    return historyGroups
        .where((group) => _historyGroupMatchesReviewFilter(group, filter))
        .length;
  }

  bool _historyGroupMatchesReviewFilter(
    _ApprovalHistoryGroup group,
    _ApprovalReviewFilter filter,
  ) {
    if (filter == _ApprovalReviewFilter.todo) return false;
    if (filter == _ApprovalReviewFilter.done) return true;
    return _historyReviewFilter(group) == filter;
  }

  _ApprovalReviewFilter _historyReviewFilter(_ApprovalHistoryGroup group) {
    final content = _plainText(group.latest.content).toLowerCase();
    if (content.contains('reject') ||
        content.contains('return') ||
        content.contains('tolak')) {
      return _ApprovalReviewFilter.rejected;
    }
    if (content.contains('cancel') || content.contains('batal')) {
      return _ApprovalReviewFilter.cancelled;
    }
    if (content.contains('submit')) return _ApprovalReviewFilter.submitted;
    if (content.contains('approve')) return _ApprovalReviewFilter.approved;
    return _ApprovalReviewFilter.done;
  }

  String _reviewFilterLabel(_ApprovalReviewFilter filter) {
    return switch (filter) {
      _ApprovalReviewFilter.todo => 'To-do',
      _ApprovalReviewFilter.done => 'Done',
      _ApprovalReviewFilter.submitted => 'Submitted',
      _ApprovalReviewFilter.approved => 'Approved',
      _ApprovalReviewFilter.rejected => 'Rejected',
      _ApprovalReviewFilter.cancelled => 'Cancelled',
    };
  }

  Widget _historyGroupCard(_ApprovalHistoryGroup group) {
    final latest = group.latest;
    final rejected = latest.content.toLowerCase().contains('reject');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _openHistoryDetail(group),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: _cardDecoration(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor:
                    (rejected ? AppColors.danger : AppColors.success)
                        .withValues(alpha: 0.1),
                foregroundColor: rejected
                    ? AppColors.danger
                    : AppColors.success,
                child: Icon(
                  rejected ? Icons.close_rounded : Icons.check_rounded,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.documentName,
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
                            color: AppColors.softGreen,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${group.items.length} log',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _plainText(latest.content),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      latest.doctype,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${latest.actor} | ${latest.createdAt}',
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppColors.slate),
            ],
          ),
        ),
      ),
    );
  }

  void _openHistoryDetail(_ApprovalHistoryGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SalesOrderApprovalHistoryDetailPage(group: group),
      ),
    );
  }

  List<_ApprovalHistoryGroup> _groupedHistory() {
    final grouped = <String, List<SalesOrderApprovalHistory>>{};
    for (final item in _history) {
      final documentName = item.salesOrder.isEmpty ? item.id : item.salesOrder;
      final key = '${item.doctype}::$documentName';
      grouped.putIfAbsent(key, () => []).add(item);
    }
    final groups = grouped.entries
        .map((entry) => _ApprovalHistoryGroup(entry.key, entry.value))
        .toList();
    groups.sort((a, b) => b.latest.createdAt.compareTo(a.latest.createdAt));
    return groups;
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

  String _plainText(String value) => value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _ApprovalCompactFilterBar extends StatelessWidget {
  const _ApprovalCompactFilterBar({
    required this.title,
    required this.subtitle,
    required this.hasActiveFilter,
    required this.onOpenFilter,
  });

  final String title;
  final String subtitle;
  final bool hasActiveFilter;
  final VoidCallback onOpenFilter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.assignment_turned_in_outlined,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
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
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onOpenFilter,
            icon: Icon(
              hasActiveFilter
                  ? Icons.filter_alt_rounded
                  : Icons.filter_alt_outlined,
              size: 15,
            ),
            label: const Text('Filter'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.softGreen,
              foregroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              minimumSize: const Size(0, 38),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalFilterResult {
  const _ApprovalFilterResult({required this.doctype, required this.sort});

  final String? doctype;
  final _ApprovalTodoSortOption sort;
}

class _ApprovalFilterSheet extends StatefulWidget {
  const _ApprovalFilterSheet({
    required this.totalCount,
    required this.doctypeCounts,
    required this.doctypeOptions,
    required this.selectedDoctype,
    required this.selectedSort,
    required this.labelForDoctype,
    required this.labelForSort,
  });

  final int totalCount;
  final Map<String, int> doctypeCounts;
  final List<String> doctypeOptions;
  final String? selectedDoctype;
  final _ApprovalTodoSortOption selectedSort;
  final String Function(String doctype) labelForDoctype;
  final String Function(_ApprovalTodoSortOption sort) labelForSort;

  @override
  State<_ApprovalFilterSheet> createState() => _ApprovalFilterSheetState();
}

class _ApprovalFilterSheetState extends State<_ApprovalFilterSheet> {
  late String? _doctype = widget.selectedDoctype;
  late _ApprovalTodoSortOption _sort = widget.selectedSort;

  void _reset() {
    setState(() {
      _doctype = null;
      _sort = _ApprovalTodoSortOption.newest;
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _ApprovalFilterResult(doctype: _doctype, sort: _sort),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDoctype = widget.doctypeOptions.contains(_doctype)
        ? _doctype
        : null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 14,
          right: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 14,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Filter Approval',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String?>(
                initialValue: selectedDoctype,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tipe dokumen',
                  prefixIcon: Icon(Icons.list_alt_rounded, size: 18),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua dokumen (${widget.totalCount})'),
                  ),
                  ...widget.doctypeOptions.map(
                    (doctype) => DropdownMenuItem<String?>(
                      value: doctype,
                      child: Text(
                        widget.labelForDoctype(doctype),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _doctype = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_ApprovalTodoSortOption>(
                initialValue: _sort,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Urutkan',
                  prefixIcon: Icon(Icons.sort_rounded, size: 18),
                ),
                items: _ApprovalTodoSortOption.values.map((option) {
                  return DropdownMenuItem<_ApprovalTodoSortOption>(
                    value: option,
                    child: Text(widget.labelForSort(option)),
                  );
                }).toList(),
                onChanged: (value) => setState(() {
                  _sort = value ?? _ApprovalTodoSortOption.newest;
                }),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reset,
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
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

class _ApprovalReviewTabBar extends StatelessWidget {
  const _ApprovalReviewTabBar({
    required this.selected,
    required this.tabs,
    required this.countFor,
    required this.labelFor,
    required this.onChanged,
  });

  final _ApprovalReviewFilter selected;
  final List<_ApprovalReviewFilter> tabs;
  final int Function(_ApprovalReviewFilter filter) countFor;
  final String Function(_ApprovalReviewFilter filter) labelFor;
  final ValueChanged<_ApprovalReviewFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          return _ApprovalReviewTabButton(
            label: labelFor(tab),
            count: countFor(tab),
            selected: selected == tab,
            onTap: () => onChanged(tab),
          );
        },
      ),
    );
  }
}

class _ApprovalReviewTabButton extends StatelessWidget {
  const _ApprovalReviewTabButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(minWidth: 92),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.16),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.14),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.white : AppColors.slate,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.white.withValues(alpha: 0.18)
                      : AppColors.softGreen,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? AppColors.white.withValues(alpha: 0.24)
                        : AppColors.primary.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? AppColors.white : AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesOrderApprovalDetailPage extends StatefulWidget {
  final SalesOrderApproval approval;
  final FutureOr<void> Function() onChanged;

  const _SalesOrderApprovalDetailPage({
    required this.approval,
    required this.onChanged,
  });

  @override
  State<_SalesOrderApprovalDetailPage> createState() =>
      _SalesOrderApprovalDetailPageState();
}

class _ApprovalHistoryGroup {
  final String key;
  final List<SalesOrderApprovalHistory> items;

  _ApprovalHistoryGroup(this.key, List<SalesOrderApprovalHistory> items)
    : items = List.unmodifiable(items);

  SalesOrderApprovalHistory get latest => items.first;
  String get doctype => latest.doctype;
  String get documentName {
    if (latest.salesOrder.isNotEmpty) return latest.salesOrder;
    final parts = key.split('::');
    return parts.length == 2 ? parts.last : key;
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
  String? _error;
  bool _loading = true;
  bool _processing = false;
  bool _addingApprover = false;
  bool _additionalApprovalProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appState = context.read<TodoState>();
      final results = await Future.wait<dynamic>([
        appState.fetchApprovalDocument(
          doctype: widget.approval.doctype,
          name: widget.approval.name,
          forceRefresh: true,
        ),
        appState.fetchApprovalDocumentActivity(
          doctype: widget.approval.doctype,
          name: widget.approval.name,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = Map<String, dynamic>.from(results[0] as Map);
        _activity = (results[1] as List)
            .whereType<SalesOrderApprovalHistory>()
            .toList();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
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
      if (mounted) setState(() => _error = _friendlyError(error));
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
      if (mounted) setState(() => _error = _friendlyError(error));
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
      if (mounted) setState(() => _error = _friendlyError(error));
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
    final items = _mapRows(detail?['items']);
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
              _detailHeader(),
              if (_loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                _errorBox(_error!),
              ],
              if (detail != null) ...[
                if (widget.approval.doctype == 'Sales Order') ...[
                  const SizedBox(height: 14),
                  _additionalApproverSection(detail),
                ],

                const SizedBox(height: 12),
                _decisionCard(detail),

                const SizedBox(height: 12),

                _sectionCard(
                  title: 'Informasi Dokumen',
                  children: _documentInfoRows(detail),
                ),

                const SizedBox(height: 12),

                _sectionCard(
                  title: widget.approval.doctype == 'Material Request'
                      ? 'Kebutuhan'
                      : 'Nilai Dokumen',
                  children: _amountRows(detail),
                ),

                const SizedBox(height: 12),

                _sectionCard(
                  title: 'Item (${items.length})',
                  children: items.isEmpty
                      ? [const Text('Tidak ada item.')]
                      : items.map(_itemRow).toList(),
                ),

                const SizedBox(height: 12),

                _activitySection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailHeader() => Container(
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
              label: '${widget.approval.actions.length} action tersedia',
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
    _ => Icons.approval_outlined,
  };

  Color _detailAccent(String doctype) => switch (doctype) {
    'Sales Order' => const Color(0xFF16A34A),
    'Purchase Order' => const Color(0xFFF97316),
    'Purchase Invoice' => const Color(0xFF3B82F6),
    'Material Request' => const Color(0xFF6366F1),
    'Journal Entry' => const Color(0xFF0EA5E9),
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

  List<Widget> _documentInfoRows(Map<String, dynamic> detail) {
    final partnerLabel = widget.approval.doctype == 'Sales Order'
        ? 'Customer'
        : widget.approval.doctype == 'Material Request'
        ? 'Tipe Request'
        : widget.approval.doctype == 'Journal Entry'
        ? 'Title'
        : 'Supplier';
    return [
      _detailRow(partnerLabel, widget.approval.partyLabel),
      _detailRow('Company', _text(detail['company'])),
      _detailRow(
        'Tanggal',
        _text(detail['transaction_date']).isNotEmpty
            ? _text(detail['transaction_date'])
            : _text(detail['posting_date']),
      ),
      _detailRow('Dibutuhkan', _text(detail['schedule_date'])),
      _detailRow('Jatuh Tempo', _text(detail['due_date'])),
      _detailRow('Dibuat oleh', _text(detail['owner'])),
    ];
  }

  List<Widget> _amountRows(Map<String, dynamic> detail) {
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
    final actions = hasPendingAdditional
        ? const <String>[]
        : widget.approval.actions;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Keputusan Approval',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Periksa detail, lalu pilih action sesuai Workflow ERPNext.',
            style: TextStyle(color: AppColors.slate, fontSize: 11),
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

  Widget _activitySection() => _sectionCard(
    title: 'Activity',
    children: _activity.isEmpty
        ? [const Text('Belum ada activity dokumen.')]
        : _activity.take(20).map(_activityRow).toList(),
  );

  Widget _activityRow(SalesOrderApprovalHistory item) {
    final content = _plainText(item.content);
    final actor = item.actor.isEmpty ? 'Unknown' : item.actor;
    final color = _activityColor(content);
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
                        text: ' ${_activityActionLabel(content)}',
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
                if (content.isNotEmpty) ...[
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
    if (plain.contains('created')) return 'created';
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

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _SalesOrderApprovalHistoryDetailPage extends StatefulWidget {
  final _ApprovalHistoryGroup group;

  const _SalesOrderApprovalHistoryDetailPage({required this.group});

  @override
  State<_SalesOrderApprovalHistoryDetailPage> createState() =>
      _SalesOrderApprovalHistoryDetailPageState();
}

class _SalesOrderApprovalHistoryDetailPageState
    extends State<_SalesOrderApprovalHistoryDetailPage> {
  Map<String, dynamic>? _detail;
  List<SalesOrderApprovalHistory> _activity = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _activity = widget.group.items;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final appState = context.read<TodoState>();
      final results = await Future.wait<dynamic>([
        appState.fetchApprovalDocument(
          doctype: widget.group.doctype,
          name: widget.group.documentName,
        ),
        appState.fetchApprovalDocumentActivity(
          doctype: widget.group.doctype,
          name: widget.group.documentName,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _detail = Map<String, dynamic>.from(results[0] as Map);
        _activity = (results[1] as List)
            .whereType<SalesOrderApprovalHistory>()
            .toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final party = _historyPartyName(detail);
    final state = _text(detail?['workflow_state']).isEmpty
        ? _text(detail?['status'])
        : _text(detail?['workflow_state']);
    final items = _mapRows(detail?['items']);
    final salesTeam = _mapRows(detail?['sales_team']);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Riwayat Approval',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadDetail,
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: TmsxResponsiveBody(
        maxWidth: 680,
        child: RefreshIndicator(
          onRefresh: _loadDetail,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 28),
            children: [
              _summaryHeader(
                documentName: widget.group.documentName,
                doctype: widget.group.doctype,
                party: party,
                state: state,
                total: _historyTotal(detail),
              ),
              if (_loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                _errorBox(_error!),
              ],
              if (detail != null) ...[
                const SizedBox(height: 14),
                _sectionCard(
                  title: 'Detail Dokumen',
                  children: _historyDetailRows(detail, party),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: widget.group.doctype == 'Material Request'
                      ? 'Kebutuhan'
                      : 'Nilai Dokumen',
                  children: _historyAmountRows(detail),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'Item (${items.length})',
                  children: items.isEmpty
                      ? [const Text('Tidak ada item.')]
                      : items.map(_itemRow).toList(),
                ),
                if (salesTeam.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: 'Sales Team',
                    children: salesTeam
                        .map(
                          (row) => _detailRow(
                            _text(row['sales_person']),
                            '${_number(row['allocated_percentage'])}% kontribusi',
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              const Text(
                'Activity Log',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              if (_activity.isEmpty)
                _sectionCard(
                  title: 'Belum ada aktivitas',
                  children: const [Text('Activity dokumen belum tersedia.')],
                )
              else
                ..._activity.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return _timelineItem(
                    item,
                    isFirst: index == 0,
                    isLast: index == _activity.length - 1,
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryHeader({
    required String documentName,
    required String doctype,
    required String party,
    required String state,
    required double total,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: _cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                documentName,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (state.isNotEmpty) ErpStatusBadge(statusText: state),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          doctype,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          party.isEmpty ? 'Party belum terbaca' : party,
          style: const TextStyle(color: AppColors.slate),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                doctype == 'Material Request'
                    ? '${formatErpCurrency(total)} qty'
                    : 'Rp ${formatErpCurrency(total)}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '${_activity.length} aktivitas',
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  String _historyPartyName(Map<String, dynamic>? detail) {
    if (detail == null) return '';
    if (widget.group.doctype == 'Sales Order') {
      return _text(detail['customer_name']).isEmpty
          ? _text(detail['customer'])
          : _text(detail['customer_name']);
    }
    if (widget.group.doctype == 'Material Request') {
      return _text(detail['company']).isEmpty
          ? _text(detail['material_request_type'])
          : _text(detail['company']);
    }
    return _text(detail['supplier_name']).isEmpty
        ? _text(detail['supplier'])
        : _text(detail['supplier_name']);
  }

  double _historyTotal(Map<String, dynamic>? detail) {
    if (detail == null) return 0;
    if (widget.group.doctype == 'Material Request') {
      return NumParse.asDouble(detail['total_qty']);
    }
    if (widget.group.doctype == 'Journal Entry') {
      return NumParse.asDouble(detail['total_debit'] ?? detail['total_credit']);
    }
    return NumParse.asDouble(detail['grand_total'] ?? detail['rounded_total']);
  }

  List<Widget> _historyDetailRows(Map<String, dynamic> detail, String party) {
    final partnerLabel = widget.group.doctype == 'Sales Order'
        ? 'Customer'
        : widget.group.doctype == 'Material Request'
        ? 'Tipe Request'
        : widget.group.doctype == 'Journal Entry'
        ? 'Title'
        : 'Supplier';
    return [
      _detailRow(partnerLabel, party),
      _detailRow('Company', _text(detail['company'])),
      _detailRow(
        'Tanggal',
        _text(detail['transaction_date']).isNotEmpty
            ? _text(detail['transaction_date'])
            : _text(detail['posting_date']),
      ),
      _detailRow('Dibutuhkan', _text(detail['schedule_date'])),
      _detailRow('Jatuh Tempo', _text(detail['due_date'])),
      _detailRow('Gudang', _text(detail['set_warehouse'])),
      _detailRow('Currency', _text(detail['currency'])),
      _detailRow('Dibuat oleh', _text(detail['owner'])),
    ];
  }

  List<Widget> _historyAmountRows(Map<String, dynamic> detail) {
    if (widget.group.doctype == 'Material Request') {
      return [
        _detailRow('Total Qty', formatErpCurrency(detail['total_qty'])),
        _detailRow('Status Dokumen', _text(detail['status'])),
      ];
    }
    if (widget.group.doctype == 'Journal Entry') {
      return [
        _moneyRow('Total Debit', detail['total_debit']),
        _moneyRow('Total Credit', detail['total_credit']),
        _detailRow('Status Dokumen', _text(detail['status'])),
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

  Widget _timelineItem(
    SalesOrderApprovalHistory item, {
    required bool isFirst,
    required bool isLast,
  }) {
    final plainContent = _plainText(item.content).toLowerCase();
    final rejected = plainContent.contains('reject');
    final isUpdate =
        plainContent.contains('changed') ||
        plainContent.contains('edited') ||
        plainContent.contains('created');
    final color = rejected
        ? AppColors.danger
        : isUpdate
        ? AppColors.slate
        : AppColors.success;
    final action = _approvalActionLabel(item.content);
    final content = _plainText(item.content);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst ? Colors.transparent : AppColors.border,
                  ),
                ),
                CircleAvatar(
                  radius: 14,
                  backgroundColor: color.withValues(alpha: 0.12),
                  foregroundColor: color,
                  child: Icon(
                    rejected ? Icons.close_rounded : Icons.check_rounded,
                    size: 16,
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : AppColors.border,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.zero,
              decoration: _cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: color.withValues(alpha: 0.1),
                          foregroundColor: color,
                          child: Text(
                            _initials(item.actor),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: item.actor.isEmpty
                                          ? 'Unknown'
                                          : item.actor,
                                      style: const TextStyle(
                                        color: AppColors.navy,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' $action',
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.createdAt,
                                style: const TextStyle(
                                  color: AppColors.slate,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _miniRow('Tipe', item.doctype),
                        const SizedBox(height: 3),
                        _miniRow('Dokumen', item.salesOrder),
                        const SizedBox(height: 6),
                        Text(
                          content.isEmpty ? '-' : content,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.slate, fontSize: 10),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
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

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: AppColors.border),
    boxShadow: AppColors.cardShadow,
  );

  String _approvalActionLabel(String content) {
    final plain = _plainText(content).toLowerCase();
    if (plain.contains('reject')) return 'rejected';
    if (plain.contains('approve')) return 'approved';
    if (plain.contains('created')) return 'created';
    if (plain.contains('changed') || plain.contains('edited')) return 'updated';
    return 'Aktivitas Approval';
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(16),
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
        const Divider(height: 22),
        ...children,
      ],
    ),
  );

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 115,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.slate, fontSize: 11),
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _text(item['item_name']).isEmpty
              ? _text(item['item_code'])
              : _text(item['item_name']),
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${_number(item['qty'])} ${_text(item['uom'])} x '
          'Rp ${formatErpCurrency(NumParse.asDouble(item['rate']))} = '
          'Rp ${formatErpCurrency(NumParse.asDouble(item['amount']))}',
          style: const TextStyle(color: AppColors.slate, fontSize: 11),
        ),
        const SizedBox(height: 3),
        Text(
          'Diskon ${_itemDiscountLabel(item)}',
          style: const TextStyle(color: AppColors.slate, fontSize: 11),
        ),
      ],
    ),
  );

  List<Map<String, dynamic>> _mapRows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

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

  String _plainText(String value) => value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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

class _SalesOrderApprovalDetailPageState
    extends State<_SalesOrderApprovalDetailPage> {
  Map<String, dynamic>? _detail;
  String? _error;
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await context
          .read<TodoState>()
          .fetchSalesOrderApprovalDetail(widget.approval.name);
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseAction(String action) async {
    final reject = _isRejectAction(action);
    final decision = await showDialog<_ApprovalDecision>(
      context: context,
      builder: (dialogContext) => _ApprovalDecisionDialog(
        approval: widget.approval,
        action: action,
        isReject: reject,
      ),
    );
    if (decision == null || !mounted) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await context.read<TodoState>().applySalesOrderWorkflow(
        approval: widget.approval,
        action: action,
        reason: decision.reason,
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
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final items = _mapRows(detail?['items']);
    final salesTeam = _mapRows(detail?['sales_team']);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Detail Approval',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _processing ? null : _loadDetail,
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: TmsxResponsiveBody(
        maxWidth: 680,
        child: RefreshIndicator(
          onRefresh: _loadDetail,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: TmsxResponsive.pagePadding(context, top: 16, bottom: 28),
            children: [
              _detailHeader(widget.approval),
              if (_loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                _errorBox(_error!),
              ],
              if (detail != null) ...[
                const SizedBox(height: 14),
                _sectionCard(
                  title: 'Informasi Order',
                  children: [
                    _detailRow('Customer', _text(detail['customer_name'])),
                    _detailRow(
                      'Tanggal Order',
                      _text(detail['transaction_date']),
                    ),
                    _detailRow('Tanggal Kirim', _text(detail['delivery_date'])),
                    _detailRow('Company', _text(detail['company'])),
                    _detailRow('Gudang', _text(detail['set_warehouse'])),
                    _detailRow(
                      'Price List',
                      _text(detail['selling_price_list']),
                    ),
                    _detailRow('Currency', _text(detail['currency'])),
                    _detailRow('Dibuat oleh', _text(detail['owner'])),
                  ],
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'Nilai Order',
                  children: [
                    _moneyRow('Subtotal', detail['net_total']),
                    _moneyRow('Diskon', detail['discount_amount']),
                    _moneyRow(
                      'Pajak & Biaya',
                      detail['total_taxes_and_charges'],
                    ),
                    _moneyRow(
                      'Grand Total',
                      detail['grand_total'],
                      emphasized: true,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'Item (${items.length})',
                  children: items.isEmpty
                      ? [const Text('Tidak ada item.')]
                      : items.map(_itemRow).toList(),
                ),
                if (salesTeam.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: 'Sales Team',
                    children: salesTeam
                        .map(
                          (row) => _detailRow(
                            _text(row['sales_person']),
                            '${_number(row['allocated_percentage'])}% kontribusi',
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
              const SizedBox(height: 16),
              _decisionCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailHeader(SalesOrderApproval approval) => Container(
    padding: const EdgeInsets.all(16),
    decoration: _cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                approval.name,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            ErpStatusBadge(
              statusText: approval.workflowState.isEmpty
                  ? approval.status
                  : approval.workflowState,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          approval.customerName,
          style: const TextStyle(color: AppColors.slate),
        ),
        const SizedBox(height: 10),
        Text(
          'Rp ${formatErpCurrency(approval.grandTotal)}',
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) => Container(
    padding: const EdgeInsets.all(16),
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
        const Divider(height: 22),
        ...children,
      ],
    ),
  );

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 115,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.slate, fontSize: 11),
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _text(item['item_name']).isEmpty
              ? _text(item['item_code'])
              : _text(item['item_name']),
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${_number(item['qty'])} ${_text(item['uom'])} x '
          'Rp ${formatErpCurrency(NumParse.asDouble(item['rate']))} = '
          'Rp ${formatErpCurrency(NumParse.asDouble(item['amount']))}',
          style: const TextStyle(color: AppColors.slate, fontSize: 11),
        ),
        const SizedBox(height: 3),
        Text(
          'Diskon ${_itemDiscountLabel(item)}',
          style: const TextStyle(color: AppColors.slate, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _decisionCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: _cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Keputusan Approval',
          style: TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        const Text(
          'Periksa detail, lalu pilih action sesuai Workflow ERPNext.',
          style: TextStyle(color: AppColors.slate, fontSize: 11),
        ),
        const SizedBox(height: 14),
        if (_processing)
          const LinearProgressIndicator()
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.approval.actions.map((action) {
              final reject = _isRejectAction(action);
              return reject
                  ? OutlinedButton.icon(
                      onPressed: () => _chooseAction(action),
                      icon: const Icon(Icons.close_rounded),
                      label: Text(action),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: () => _chooseAction(action),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(action),
                    );
            }).toList(),
          ),
      ],
    ),
  );

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

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: AppColors.border),
    boxShadow: AppColors.cardShadow,
  );

  List<Map<String, dynamic>> _mapRows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String _number(dynamic value) {
    final number = NumParse.asDouble(value);
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toStringAsFixed(2);
  }

  bool _isRejectAction(String action) {
    final normalized = action.toLowerCase();
    return normalized.contains('reject') ||
        normalized.contains('tolak') ||
        normalized.contains('decline');
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _ApprovalDecision {
  final String reason;

  const _ApprovalDecision({this.reason = ''});
}

class _ApprovalDecisionDialog extends StatefulWidget {
  final SalesOrderApproval approval;
  final String action;
  final bool isReject;

  const _ApprovalDecisionDialog({
    required this.approval,
    required this.action,
    required this.isReject,
  });

  @override
  State<_ApprovalDecisionDialog> createState() =>
      _ApprovalDecisionDialogState();
}

class _ApprovalDecisionDialogState extends State<_ApprovalDecisionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isReject ? 'Reject Sales Order?' : 'Approve Sales Order?',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.approval.name}\n${widget.approval.customerName}\n'
              'Rp ${formatErpCurrency(widget.approval.grandTotal)}',
            ),
            if (widget.isReject) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _reasonController,
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Alasan reject',
                  hintText: 'Wajib diisi agar sales dapat memperbaiki order',
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (!widget.isReject) return null;
                  final reason = value?.trim() ?? '';
                  if (reason.isEmpty) return 'Alasan reject wajib diisi';
                  return null;
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _ApprovalDecision(reason: _reasonController.text.trim()),
            );
          },
          style: widget.isReject
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          child: Text(widget.isReject ? 'Reject' : 'Approve'),
        ),
      ],
    );
  }
}
