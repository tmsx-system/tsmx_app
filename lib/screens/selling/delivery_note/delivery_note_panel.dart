import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/delivery_note.dart';
import '../../../state/selling/delivery_note_state.dart';
import '../../../state/selling/selling_summary_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_doc_utils.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/erp_document_card.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/erp/erp_status_chip_bar.dart';
import '../../../widgets/erp/erp_workflow_helper.dart';
import '../../../widgets/erp/document_trend_card.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/selling_document_detail_sheet.dart';
import '../shared/selling_filter_widgets.dart';

class DeliveryNotePanel extends StatefulWidget {
  const DeliveryNotePanel({super.key});

  @override
  State<DeliveryNotePanel> createState() => _DeliveryNotePanelState();
}

class _DeliveryNotePanelState extends State<DeliveryNotePanel> {
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  DeliveryNoteStatusKey? _statusFilter;
  SellingSortOption _sortOption = SellingSortOption.newest;
  SellingAdvancedFilters _advancedFilters = SellingAdvancedFilters.empty;
  Timer? _searchDebounce;

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
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
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
      if (mounted) {
        context.read<DeliveryNoteState>().setDeliveryNoteQuery(
          search: value,
          status: _statusText,
        );
      }
    });
  }

  List<DeliveryNote> _filter(List<DeliveryNote> docs) {
    final q = _search.toLowerCase();
    final filtered = docs.where((d) {
      final matchSearch =
          q.isEmpty ||
          d.id.toLowerCase().contains(q) ||
          d.customer.toLowerCase().contains(q);
      final matchStatus = _statusFilter == null || d.statusKey == _statusFilter;
      return matchSearch && matchStatus && _matchesAdvancedFilters(d);
    }).toList();

    filtered.sort((a, b) {
      return switch (_sortOption) {
        SellingSortOption.newest => _compareDateDesc(a.date, b.date),
        SellingSortOption.oldest => _compareDateAsc(a.date, b.date),
        SellingSortOption.valueHigh => b.value.compareTo(a.value),
        SellingSortOption.valueLow => a.value.compareTo(b.value),
      };
    });

    return filtered;
  }

  int _compareDateDesc(String a, String b) {
    final left = _parseDate(a);
    final right = _parseDate(b);
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  }

  int _compareDateAsc(String a, String b) {
    final left = _parseDate(a);
    final right = _parseDate(b);
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime? _parseDate(String rawDate) {
    final trimmed = rawDate.trim();
    if (trimmed.isEmpty) return null;

    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    final parts = trimmed.split('/');
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }

    return null;
  }

  String _sortLabel(SellingSortOption option) {
    return switch (option) {
      SellingSortOption.newest => 'Newest',
      SellingSortOption.oldest => 'Oldest',
      SellingSortOption.valueHigh => 'Value high',
      SellingSortOption.valueLow => 'Value low',
    };
  }

  bool _matchesAdvancedFilters(DeliveryNote doc) {
    final filters = _advancedFilters;
    final customer = filters.customer.toLowerCase();
    if (customer.isNotEmpty && !doc.customer.toLowerCase().contains(customer)) {
      return false;
    }
    if (filters.minValue != null && doc.value < filters.minValue!) {
      return false;
    }
    if (filters.maxValue != null && doc.value > filters.maxValue!) {
      return false;
    }

    final date = _parseDate(doc.date);
    if (filters.from != null) {
      if (date == null || _dateOnly(date).isBefore(_dateOnly(filters.from!))) {
        return false;
      }
    }
    if (filters.to != null) {
      if (date == null || _dateOnly(date).isAfter(_dateOnly(filters.to!))) {
        return false;
      }
    }

    return switch (filters.docStatus) {
      SellingDocStatusFilter.all => true,
      SellingDocStatusFilter.draft => doc.docStatus == 0,
      SellingDocStatusFilter.submitted => doc.docStatus == 1,
      SellingDocStatusFilter.cancelled => doc.docStatus == 2,
    };
  }

  int get _advancedFilterCount {
    var count = 0;
    if (_advancedFilters.customer.isNotEmpty) count++;
    if (_advancedFilters.minValue != null) count++;
    if (_advancedFilters.maxValue != null) count++;
    if (_advancedFilters.from != null) count++;
    if (_advancedFilters.to != null) count++;
    if (_advancedFilters.docStatus != SellingDocStatusFilter.all) count++;
    return count;
  }

  Future<void> _openAdvancedFilters() async {
    final result = await showModalBottomSheet<SellingAdvancedFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) {
        return SellingAdvancedFilterSheet(
          title: 'Advanced Delivery Filters',
          initial: _advancedFilters,
        );
      },
    );

    if (result == null || !mounted) return;
    setState(() => _advancedFilters = result);
  }

  void _resetFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _search = '';
      _statusFilter = null;
      _sortOption = SellingSortOption.newest;
      _advancedFilters = SellingAdvancedFilters.empty;
    });
    context.read<DeliveryNoteState>().setDeliveryNoteQuery(
      search: '',
      status: null,
    );
  }

  Future<void> _openDetail(DeliveryNote doc) async {
    final detail = await context
        .read<DeliveryNoteState>()
        .loadDeliveryNoteDetail(doc.id);
    if (!mounted) return;

    final canSubmit = isDocDraft(detail.docStatus);

    showSellingDocumentDetailSheet(
      context: context,
      title: detail.id,
      subtitle: detail.customer,
      statusText: detail.statusText,
      icon: Icons.local_shipping_rounded,
      metrics: [
        SellingDetailMetric(
          label: 'Total',
          value: 'Rp ${formatErpCurrency(detail.value)}',
          icon: Icons.payments_outlined,
        ),
        SellingDetailMetric(
          label: 'Qty',
          value: '${detail.itemsCount}',
          icon: Icons.inventory_2_outlined,
        ),
      ],
      infos: [
        SellingDetailInfo(
          label: 'Doc Status',
          value: docStatusLabel(detail.docStatus),
        ),
        SellingDetailInfo(label: 'Posting Date', value: detail.date),
      ],
      items: detail.items
          .map(
            (i) => SellingDetailItem(
              title: i.itemName,
              subtitle: i.itemCode,
              qty:
                  '${formatErpCurrency(i.qty)}${i.uom.isEmpty ? '' : ' ${i.uom}'}',
              rate: 'Rp ${formatErpCurrency(i.rate)}',
              amount: 'Rp ${formatErpCurrency(i.amount)}',
              note: i.warehouse,
            ),
          )
          .toList(),
      footer: canSubmit
          ? erpActionButton(
              label: 'Submit Delivery Note',
              icon: Icons.check_circle_outline_rounded,
              filled: true,
              onPressed: () => _submit(detail.id),
            )
          : null,
    );
  }

  Future<void> _submit(String id) async {
    if (!await confirmErpAction(
      context,
      title: 'Submit Delivery Note?',
      message: 'Submit $id?',
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await runErpWorkflowAction(
      context,
      action: () =>
          context.read<DeliveryNoteState>().submitDocument('Delivery Note', id),
      successMessage: 'Delivery Note submitted',
    );
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final sellingState = context.watch<DeliveryNoteState>();
    final summaryState = context.watch<SellingSummaryState>();
    final filtered = _filter(sellingState.deliveryNotes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DocumentTrendCard(
          title: 'Delivery Note',
          emptyMessage:
              'Belum ada nilai Delivery Note dari Sales Analytics pada periode ini.',
          points: summaryState.deliveryNoteTrendPoints,
          selectedYear: summaryState.sellingPeriodYear,
          selectedMonth: summaryState.sellingPeriodMonth,
          sourceLabel: 'Sumber: Sales Analytics ERPNext',
          isLoading: summaryState.isOrderSummaryLoading,
        ),

        const SizedBox(height: 12),

        TextField(
          controller: _searchController,
          onChanged: _searchChanged,
          decoration: InputDecoration(
            hintText: 'Search DN or customer…',
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 20,
              color: AppColors.navy,
            ),
            filled: true,
            fillColor: AppColors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.38),
                width: 1.4,
              ),
            ),
          ),
        ),

        if (sellingState.deliveryNotesError != null) ...[
          const SizedBox(height: 10),
          ErpErrorBox(message: sellingState.deliveryNotesError!),
        ],

        const SizedBox(height: 10),

        SellingQuickFilters(
          sortOption: _sortOption,
          sortLabel: _sortLabel,
          onSortChanged: (option) => setState(() => _sortOption = option),
          onReset: _resetFilters,
          advancedCount: _advancedFilterCount,
          onAdvancedFilters: _openAdvancedFilters,
        ),

        const SizedBox(height: 10),

        ErpStatusChipBar<DeliveryNoteStatusKey?>(
          chips: _chips,
          selected: _statusFilter,
          onSelected: (v) {
            setState(() => _statusFilter = v);
            context.read<DeliveryNoteState>().setDeliveryNoteQuery(
              search: _search,
              status: _statusText,
            );
          },
        ),

        const SizedBox(height: 12),

        if (filtered.isEmpty && !sellingState.isDeliveryNotesLoading)
          const ErpEmptyState(title: 'No delivery notes found')
        else
          TmsxResponsiveCardGrid(
            children: filtered
                .map(
                  (d) => ErpDocumentCard(
                    id: d.id,
                    party: d.customer,
                    statusText: d.statusText,
                    date: d.date,
                    value: d.value,
                    onTap: () => _openDetail(d),
                  ),
                )
                .toList(),
          ),

        if (sellingState.hasMoreDeliveryNotes ||
            sellingState.isMoreDeliveryNotesLoading) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: sellingState.isMoreDeliveryNotesLoading
                  ? null
                  : () => context
                        .read<DeliveryNoteState>()
                        .loadMoreDeliveryNotes(),
              icon: sellingState.isMoreDeliveryNotesLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(
                sellingState.isMoreDeliveryNotesLoading
                    ? 'Loading delivery notes...'
                    : 'Load more delivery notes',
              ),
            ),
          ),
        ],
      ],
    );
  }
}
