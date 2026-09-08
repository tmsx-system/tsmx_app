import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../models/sales_order.dart';
import '../../../state/selling/sales_order_state.dart';
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
import 'create_sales_order_screen.dart';
import '../shared/selling_document_detail_sheet.dart';

enum _OrderSortOption { newest, oldest, valueHigh, valueLow }

enum _DocStatusFilter { all, draft, submitted, cancelled }

const Color _soGreen = Color(0xFF16A34A);
const Color _soTeal = Color(0xFF14B8A6);
const Color _soBlue = Color(0xFF3B82F6);

class SalesOrderPanel extends StatefulWidget {
  const SalesOrderPanel({super.key});

  @override
  State<SalesOrderPanel> createState() => _SalesOrderPanelState();
}

class _SalesOrderPanelState extends State<SalesOrderPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  String? _statusFilter;
  _OrderSortOption _sortOption = _OrderSortOption.newest;
  String _advancedCustomer = '';
  String _advancedItem = '';
  String _advancedWarehouse = '';
  double? _advancedMinValue;
  double? _advancedMaxValue;
  DateTime? _advancedFrom;
  DateTime? _advancedTo;
  _DocStatusFilter _advancedDocStatus = _DocStatusFilter.all;
  Timer? _searchDebounce;
  bool _isOpeningDetail = false;

  static const _defaultStatusChips = <String>[
    'Draft',
    'Overdue',
    'To Deliver and Bill',
    'To Bill',
    'To Deliver',
    'Completed',
    'Closed',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sellingState = context.read<SalesOrderState>();
      if (sellingState.salesOrders.isEmpty) {
        sellingState.refreshSalesOrders();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _searchChanged(String value) {
    setState(() => _search = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        context.read<SalesOrderState>().setSalesOrderQuery(
          search: value,
          status: null,
        );
      }
    });
  }

  List<SalesOrder> _filter(List<SalesOrder> orders) {
    final filtered = _baseFilter(
      orders,
    ).where((order) => _matchesStatusFilter(order)).toList();

    _sortOrders(filtered);
    return filtered;
  }

  List<SalesOrder> _baseFilter(List<SalesOrder> orders) {
    final q = _search.toLowerCase();
    return orders.where((o) {
      final matchSearch =
          q.isEmpty ||
          o.id.toLowerCase().contains(q) ||
          o.customer.toLowerCase().contains(q);
      return matchSearch && _matchesAdvancedFilters(o);
    }).toList();
  }

  void _sortOrders(List<SalesOrder> filtered) {
    filtered.sort((a, b) {
      return switch (_sortOption) {
        _OrderSortOption.newest => _compareDateDesc(a.date, b.date),
        _OrderSortOption.oldest => _compareDateAsc(a.date, b.date),
        _OrderSortOption.valueHigh => b.value.compareTo(a.value),
        _OrderSortOption.valueLow => a.value.compareTo(b.value),
      };
    });
  }

  bool _matchesStatusFilter(SalesOrder order) {
    final filter = _statusFilter?.trim();
    if (filter == null || filter.isEmpty) return true;
    final filterKey = _statusIdentity(filter);
    return _statusCandidates(
      order,
    ).any((status) => _statusIdentity(status) == filterKey);
  }

  String _statusIdentity(String value) =>
      value.trim().toLowerCase().replaceAll('&', 'and');

  List<String> _statusCandidates(SalesOrder order) {
    final values = <String>[order.statusText, order.workflowState];
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .where((value) => seen.add(_statusIdentity(value)))
        .toList();
  }

  String _statusChipLabel(String status) {
    return status == 'To Deliver and Bill' ? 'Deliver & Bill' : status;
  }

  List<ErpStatusChip<String?>> _statusChips(List<SalesOrder> source) {
    final counts = <String, int>{};
    final labels = <String, String>{};
    for (final order in source) {
      for (final status in _statusCandidates(order)) {
        final key = _statusIdentity(status);
        counts[key] = (counts[key] ?? 0) + 1;
        labels.putIfAbsent(key, () => status);
      }
    }

    final chips = <ErpStatusChip<String?>>[
      ErpStatusChip(label: 'All (${source.length})', value: null),
    ];

    final used = <String>{};
    for (final status in _defaultStatusChips) {
      final key = _statusIdentity(status);
      final count = counts[key] ?? 0;
      if (count == 0) continue;
      used.add(key);
      chips.add(
        ErpStatusChip(
          label: '${_statusChipLabel(status)} ($count)',
          value: status,
        ),
      );
    }

    final dynamicKeys = counts.keys.where((key) => !used.contains(key)).toList()
      ..sort(
        (a, b) => labels[a]!.toLowerCase().compareTo(labels[b]!.toLowerCase()),
      );
    for (final key in dynamicKeys) {
      final label = labels[key]!;
      chips.add(
        ErpStatusChip(
          label: '${_statusChipLabel(label)} (${counts[key]})',
          value: label,
        ),
      );
    }

    return chips;
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

  String _sortLabel(_OrderSortOption option) {
    return switch (option) {
      _OrderSortOption.newest => 'Newest',
      _OrderSortOption.oldest => 'Oldest',
      _OrderSortOption.valueHigh => 'Value high',
      _OrderSortOption.valueLow => 'Value low',
    };
  }

  Future<void> _openAdvancedFilters() async {
    final result = await showModalBottomSheet<_SalesOrderAdvancedFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return _SalesOrderAdvancedFilterSheet(
          initial: _SalesOrderAdvancedFilters(
            customer: _advancedCustomer,
            item: _advancedItem,
            warehouse: _advancedWarehouse,
            minValue: _advancedMinValue,
            maxValue: _advancedMaxValue,
            from: _advancedFrom,
            to: _advancedTo,
            docStatus: _advancedDocStatus,
          ),
        );
      },
    );

    if (result == null || !mounted) return;
    setState(() {
      _advancedCustomer = result.customer;
      _advancedItem = result.item;
      _advancedWarehouse = result.warehouse;
      _advancedMinValue = result.minValue;
      _advancedMaxValue = result.maxValue;
      _advancedFrom = result.from;
      _advancedTo = result.to;
      _advancedDocStatus = result.docStatus;
    });
  }

  Future<void> _openDetail(SalesOrder order) async {
    if (_isOpeningDetail) return;
    setState(() => _isOpeningDetail = true);
    final sellingState = context.read<SalesOrderState>();
    late final SalesOrder detail;
    try {
      detail = await sellingState.loadSalesOrderDetail(order.id);
      if (!mounted) return;

      final relatedDn = await sellingState.fetchDeliveryNotesForSalesOrder(
        order.id,
      );
      final relatedSi = await sellingState.fetchSalesInvoicesForSalesOrder(
        order.id,
      );
      if (!mounted) return;

      var workflowActions = const <String>[];
      try {
        workflowActions = await sellingState.fetchDocumentWorkflowActions(
          doctype: 'Sales Order',
          name: detail.id,
        );
      } catch (_) {
        workflowActions = const <String>[];
      }
      if (!mounted) return;

      final canSubmit = isDocDraft(detail.docStatus)
          ? await sellingState.canSubmitDoctype('Sales Order')
          : false;
      final canEdit = isDocDraft(detail.docStatus);
      if (!mounted) return;

      showSellingDocumentDetailSheet(
        context: context,
        title: detail.id,
        subtitle: detail.customer,
        statusText: detail.effectiveStatusText,
        icon: Icons.point_of_sale_rounded,
        metrics: [
          SellingDetailMetric(
            label: 'Total',
            value: 'Rp ${formatErpCurrency(detail.value)}',
            icon: Icons.payments_outlined,
          ),
          SellingDetailMetric(
            label: 'Items',
            value: '${detail.itemsCount}',
            icon: Icons.inventory_2_outlined,
          ),
          SellingDetailMetric(
            label: 'Delivered',
            value: '${detail.perDelivered.toStringAsFixed(1)}%',
            icon: Icons.local_shipping_outlined,
          ),
          SellingDetailMetric(
            label: 'Billed',
            value: '${detail.perBilled.toStringAsFixed(1)}%',
            icon: Icons.receipt_long_outlined,
          ),
        ],
        infos: [
          SellingDetailInfo(
            label: 'Doc Status',
            value: docStatusLabel(detail.docStatus),
          ),
          SellingDetailInfo(label: 'Date', value: detail.date),
          if (detail.sellingPriceList.isNotEmpty)
            SellingDetailInfo(
              label: 'Price List',
              value: detail.sellingPriceList,
            ),
          if (detail.currency.isNotEmpty)
            SellingDetailInfo(label: 'Currency', value: detail.currency),
        ],
        items: detail.items
            .map(
              (i) => SellingDetailItem(
                title: i.itemName,
                subtitle: i.itemCode,
                qty: '${i.qty}',
                rate: 'Rp ${formatErpCurrency(i.rate)}',
                discount: 'Rp ${formatErpCurrency(i.discountAmount)}',
                amount: 'Rp ${formatErpCurrency(i.qty * i.rate)}',
                note: i.warehouse,
              ),
            )
            .toList(),
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (relatedDn.isNotEmpty)
              erpWorkflowSection(
                title: 'Delivery Notes',
                children: erpRelatedDocChips(
                  docIds: relatedDn.map((d) => d.id).toList(),
                  onTap: (_) {},
                ),
              ),
            if (relatedSi.isNotEmpty) ...[
              const SizedBox(height: 8),
              erpWorkflowSection(
                title: 'Sales Invoices',
                children: erpRelatedDocChips(
                  docIds: relatedSi.map((d) => d.id).toList(),
                  onTap: (_) {},
                ),
              ),
            ],
            const SizedBox(height: 12),
            erpActionButton(
              label: 'Duplicate Sales Order',
              icon: Icons.copy_rounded,
              onPressed: () => _duplicateSo(detail, closeSheet: true),
            ),
            erpActionButton(
              label: 'Download PDF / Share',
              icon: Icons.picture_as_pdf_outlined,
              onPressed: () => _downloadAndShareSoPdf(detail.id),
            ),
            if (canEdit)
              erpActionButton(
                label: 'Edit Sales Order',
                icon: Icons.edit_outlined,
                onPressed: () => _editSo(detail.id, closeSheet: true),
              ),
            ...workflowActions.map(
              (action) => erpActionButton(
                label: action,
                icon: _workflowActionIcon(action),
                filled: _isPositiveWorkflowAction(action),
                onPressed: () => _applySoWorkflowAction(detail.id, action),
              ),
            ),
            if (workflowActions.isEmpty && canSubmit)
              erpActionButton(
                label: 'Submit Sales Order',
                icon: Icons.check_circle_outline_rounded,
                filled: true,
                onPressed: () => _submitSo(detail.id),
              ),
            if (workflowActions.isEmpty && !canSubmit && !canEdit)
              const Text(
                'No workflow actions available for this document.',
                style: TextStyle(fontSize: 12, color: AppColors.slate),
              ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isOpeningDetail = false);
    }
  }

  Future<void> _applySoWorkflowAction(String id, String action) async {
    final reject = _isRejectWorkflowAction(action);
    var reason = '';
    if (reject) {
      reason = await _askWorkflowReason(id, action) ?? '';
      if (reason.trim().isEmpty || !mounted) return;
    } else {
      final ok = await confirmErpAction(
        context,
        title: '$action $id?',
        message: 'Lanjutkan action "$action" untuk Sales Order ini?',
      );
      if (!ok || !mounted) return;
    }

    final ok = await runErpWorkflowAction(
      context,
      action: () => context.read<SalesOrderState>().applyDocumentWorkflow(
        doctype: 'Sales Order',
        name: id,
        action: action,
        reason: reason,
      ),
      successMessage: 'Sales Order: $action berhasil',
    );
    if (ok && mounted) {
      await context.read<SalesOrderState>().refreshSalesOrders();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<String?> _askWorkflowReason(String id, String action) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action $id'),
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
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
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
        value.contains('deliver') ||
        value.contains('bill');
  }

  IconData _workflowActionIcon(String action) {
    final value = action.toLowerCase();
    if (_isRejectWorkflowAction(action)) return Icons.close_rounded;
    if (value.contains('approve')) return Icons.verified_rounded;
    if (value.contains('submit')) return Icons.send_rounded;
    if (value.contains('deliver')) return Icons.local_shipping_outlined;
    if (value.contains('bill')) return Icons.receipt_long_outlined;
    return Icons.check_circle_outline_rounded;
  }

  Future<void> _downloadAndShareSoPdf(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Mengunduh PDF Sales Order $id...')),
    );
    try {
      final bytes = await context.read<SalesOrderState>().downloadSalesOrderPdf(
        id,
      );
      final directory = await getApplicationDocumentsDirectory();
      final folder = Directory('${directory.path}/sales_order_pdf');
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      final fileName = '${_safeFileName(id)}.pdf';
      final file = File('${folder.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('PDF tersimpan: $fileName')),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Sales Order $id',
          text: 'Sales Order $id',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal download PDF $id: $error')),
      );
    }
  }

  String _safeFileName(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  bool _matchesAdvancedFilters(SalesOrder order) {
    final customer = _advancedCustomer.trim().toLowerCase();
    if (customer.isNotEmpty &&
        !order.customer.toLowerCase().contains(customer)) {
      return false;
    }

    if (_advancedMinValue != null && order.value < _advancedMinValue!) {
      return false;
    }
    if (_advancedMaxValue != null && order.value > _advancedMaxValue!) {
      return false;
    }

    final date = _parseDate(order.date);
    if (_advancedFrom != null &&
        (date == null || date.isBefore(_dateOnly(_advancedFrom!)))) {
      return false;
    }
    if (_advancedTo != null &&
        (date == null || date.isAfter(_dateOnly(_advancedTo!)))) {
      return false;
    }

    final item = _advancedItem.trim().toLowerCase();
    if (item.isNotEmpty &&
        !order.items.any(
          (row) =>
              row.itemCode.toLowerCase().contains(item) ||
              row.itemName.toLowerCase().contains(item),
        )) {
      return false;
    }

    final warehouse = _advancedWarehouse.trim().toLowerCase();
    if (warehouse.isNotEmpty &&
        !order.items.any(
          (row) => row.warehouse.toLowerCase().contains(warehouse),
        )) {
      return false;
    }

    return switch (_advancedDocStatus) {
      _DocStatusFilter.all => true,
      _DocStatusFilter.draft => order.docStatus == 0,
      _DocStatusFilter.submitted => order.docStatus == 1,
      _DocStatusFilter.cancelled => order.docStatus == 2,
    };
  }

  int get _advancedFilterCount {
    var count = 0;
    if (_advancedCustomer.trim().isNotEmpty) count++;
    if (_advancedItem.trim().isNotEmpty) count++;
    if (_advancedWarehouse.trim().isNotEmpty) count++;
    if (_advancedMinValue != null) count++;
    if (_advancedMaxValue != null) count++;
    if (_advancedFrom != null || _advancedTo != null) count++;
    if (_advancedDocStatus != _DocStatusFilter.all) count++;
    return count;
  }

  Future<void> _editSo(String id, {bool closeSheet = false}) async {
    if (closeSheet) Navigator.pop(context);
    final sellingState = context.read<SalesOrderState>();
    late final SalesOrder latest;
    try {
      latest = await sellingState.loadSalesOrderDetail(id);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal cek status terbaru $id: $err')),
      );
      return;
    }
    if (!mounted) return;
    if (!isDocDraft(latest.docStatus)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$id sudah ${docStatusLabel(latest.docStatus).toLowerCase()} di ERPNext, tidak bisa diedit.',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateSalesOrderScreen(editOrderId: id),
      ),
    );
    if (mounted) {
      await context.read<SalesOrderState>().refreshSalesOrders();
    }
  }

  Future<void> _duplicateSo(SalesOrder order, {bool closeSheet = false}) async {
    if (closeSheet) Navigator.pop(context);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateSalesOrderScreen(duplicateFrom: order),
      ),
    );
    if (mounted) {
      await context.read<SalesOrderState>().refreshSalesOrders();
    }
  }

  Future<void> _duplicateSoFromList(SalesOrder order) async {
    if (_isOpeningDetail) return;
    setState(() => _isOpeningDetail = true);
    try {
      final detail = await context.read<SalesOrderState>().loadSalesOrderDetail(
        order.id,
      );
      if (!mounted) return;
      await _duplicateSo(detail);
    } finally {
      if (mounted) setState(() => _isOpeningDetail = false);
    }
  }

  Future<void> _submitSo(String id) async {
    if (!await confirmErpAction(
      context,
      title: 'Submit Sales Order?',
      message: 'Submit $id?',
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await runErpWorkflowAction(
      context,
      action: () =>
          context.read<SalesOrderState>().submitDocument('Sales Order', id),
      successMessage: 'Sales Order submitted',
    );
    if (ok && mounted) {
      await context.read<SalesOrderState>().refreshSalesOrders();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sellingState = context.watch<SalesOrderState>();
    final baseFiltered = _baseFilter(sellingState.salesOrders);
    final filtered = _filter(sellingState.salesOrders);
    final statusChips = _statusChips(baseFiltered);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DocumentTrendCard(
          title: 'Pendapatan',
          emptyMessage:
              'Belum ada nilai Sales Order dari Sales Analytics pada periode ini.',
          points: sellingState.salesOrderTrendPoints,
          selectedYear: sellingState.sellingPeriodYear,
          selectedMonth: sellingState.sellingPeriodMonth,
          sourceLabel: 'Sumber: Sales Analytics ERPNext',
          isLoading: sellingState.isOrderSummaryLoading,
          accent: _soGreen,
        ),

        const SizedBox(height: 12),

        TextField(
          controller: _searchController,
          onChanged: _searchChanged,
          decoration: InputDecoration(
            hintText: 'Search SO or customer...',
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
              borderSide: BorderSide(color: _soGreen.withValues(alpha: 0.12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(color: _soGreen.withValues(alpha: 0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide(
                color: _soGreen.withValues(alpha: 0.45),
                width: 1.4,
              ),
            ),
          ),
        ),
        if (sellingState.salesOrdersError != null) ...[
          const SizedBox(height: 10),
          ErpErrorBox(message: sellingState.salesOrdersError!),
        ],
        const SizedBox(height: 10),
        _SalesOrderQuickFilters(
          sortOption: _sortOption,
          sortLabel: _sortLabel,
          onSortChanged: (v) => setState(() => _sortOption = v),
          onReset: () {
            setState(() {
              _searchController.clear();
              _search = '';
              _statusFilter = null;
              _sortOption = _OrderSortOption.newest;
              _advancedCustomer = '';
              _advancedItem = '';
              _advancedWarehouse = '';
              _advancedMinValue = null;
              _advancedMaxValue = null;
              _advancedFrom = null;
              _advancedTo = null;
              _advancedDocStatus = _DocStatusFilter.all;
            });
            context.read<SalesOrderState>().setSalesOrderQuery(
              search: '',
              status: null,
            );
          },
          advancedCount: _advancedFilterCount,
          onAdvancedFilters: _openAdvancedFilters,
        ),
        const SizedBox(height: 10),
        ErpStatusChipBar<String?>(
          chips: statusChips,
          selected: _statusFilter,
          onSelected: (v) {
            setState(() => _statusFilter = v);
          },
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty && !sellingState.isSalesOrdersLoading)
          const ErpEmptyState(title: 'No sales orders found')
        else
          TmsxResponsiveCardGrid(
            children: filtered
                .map(
                  (o) => ErpDocumentCard(
                    id: o.id,
                    party: o.customer,
                    statusText: o.effectiveStatusText,
                    date: o.date,
                    value: o.value,
                    onTap: () => _openDetail(o),
                    onEdit: isDocDraft(o.docStatus)
                        ? () => _editSo(o.id)
                        : null,
                    onDuplicate: () => _duplicateSoFromList(o),
                    onDownload: () => _downloadAndShareSoPdf(o.id),
                  ),
                )
                .toList(),
          ),
        if (sellingState.hasMoreSalesOrders ||
            sellingState.isMoreSalesOrdersLoading) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: sellingState.isMoreSalesOrdersLoading
                  ? null
                  : () => context.read<SalesOrderState>().loadMoreSalesOrders(),
              icon: sellingState.isMoreSalesOrdersLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(
                sellingState.isMoreSalesOrdersLoading
                    ? 'Loading orders...'
                    : 'Load more orders',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SalesOrderQuickFilters extends StatelessWidget {
  final _OrderSortOption sortOption;
  final String Function(_OrderSortOption) sortLabel;
  final ValueChanged<_OrderSortOption> onSortChanged;
  final VoidCallback onReset;
  final int advancedCount;
  final VoidCallback onAdvancedFilters;

  const _SalesOrderQuickFilters({
    required this.sortOption,
    required this.sortLabel,
    required this.onSortChanged,
    required this.onReset,
    required this.advancedCount,
    required this.onAdvancedFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _soTeal.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: _soTeal.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<_OrderSortOption>(
              initialValue: sortOption,
              decoration: InputDecoration(
                labelText: 'Urutkan',
                prefixIcon: const Icon(Icons.sort_rounded, size: 18),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: _soTeal.withValues(alpha: 0.30),
                  ),
                ),
              ),
              items: _OrderSortOption.values.map((option) {
                return DropdownMenuItem<_OrderSortOption>(
                  value: option,
                  child: Text(sortLabel(option)),
                );
              }).toList(),
              onChanged: (option) {
                if (option != null) onSortChanged(option);
              },
            ),
          ),
          const SizedBox(width: 8),
          _SalesFilterButton(
            icon: Icons.tune_rounded,
            label: advancedCount > 0 ? 'Filter $advancedCount' : 'Filter',
            color: _soTeal,
            onTap: onAdvancedFilters,
          ),
          const SizedBox(width: 8),
          _SalesFilterButton(
            icon: Icons.restart_alt_rounded,
            label: 'Reset',
            color: _soBlue,
            onTap: onReset,
          ),
        ],
      ),
    );
  }
}

class _SalesFilterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _SalesFilterButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 68,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesOrderAdvancedFilters {
  final String customer;
  final String item;
  final String warehouse;
  final double? minValue;
  final double? maxValue;
  final DateTime? from;
  final DateTime? to;
  final _DocStatusFilter docStatus;

  const _SalesOrderAdvancedFilters({
    required this.customer,
    required this.item,
    required this.warehouse,
    required this.minValue,
    required this.maxValue,
    required this.from,
    required this.to,
    required this.docStatus,
  });
}

class _SalesOrderAdvancedFilterSheet extends StatefulWidget {
  final _SalesOrderAdvancedFilters initial;

  const _SalesOrderAdvancedFilterSheet({required this.initial});

  @override
  State<_SalesOrderAdvancedFilterSheet> createState() =>
      _SalesOrderAdvancedFilterSheetState();
}

class _SalesOrderAdvancedFilterSheetState
    extends State<_SalesOrderAdvancedFilterSheet> {
  late final TextEditingController _customerCtrl;
  late final TextEditingController _itemCtrl;
  late final TextEditingController _warehouseCtrl;
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  DateTime? _from;
  DateTime? _to;
  late _DocStatusFilter _docStatus;

  @override
  void initState() {
    super.initState();
    _customerCtrl = TextEditingController(text: widget.initial.customer);
    _itemCtrl = TextEditingController(text: widget.initial.item);
    _warehouseCtrl = TextEditingController(text: widget.initial.warehouse);
    _minCtrl = TextEditingController(
      text: widget.initial.minValue?.toStringAsFixed(0) ?? '',
    );
    _maxCtrl = TextEditingController(
      text: widget.initial.maxValue?.toStringAsFixed(0) ?? '',
    );
    _from = widget.initial.from;
    _to = widget.initial.to;
    _docStatus = widget.initial.docStatus;
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _itemCtrl.dispose();
    _warehouseCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  String _dateText(DateTime? date) {
    if (date == null) return 'Any';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _SalesOrderAdvancedFilters(
        customer: _customerCtrl.text.trim(),
        item: _itemCtrl.text.trim(),
        warehouse: _warehouseCtrl.text.trim(),
        minValue: double.tryParse(_minCtrl.text.trim()),
        maxValue: double.tryParse(_maxCtrl.text.trim()),
        from: _from,
        to: _to,
        docStatus: _docStatus,
      ),
    );
  }

  void _reset() {
    Navigator.pop(
      context,
      const _SalesOrderAdvancedFilters(
        customer: '',
        item: '',
        warehouse: '',
        minValue: null,
        maxValue: null,
        from: null,
        to: null,
        docStatus: _DocStatusFilter.all,
      ),
    );
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
                'Advanced Sales Filters',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _customerCtrl,
                decoration: const InputDecoration(labelText: 'Customer'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _itemCtrl,
                decoration: const InputDecoration(labelText: 'Item keyword'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _warehouseCtrl,
                decoration: const InputDecoration(labelText: 'Warehouse'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Min value'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _maxCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Max value'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(isFrom: true),
                      icon: const Icon(Icons.date_range_rounded),
                      label: Text('From ${_dateText(_from)}'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(isFrom: false),
                      icon: const Icon(Icons.event_rounded),
                      label: Text('To ${_dateText(_to)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<_DocStatusFilter>(
                initialValue: _docStatus,
                decoration: const InputDecoration(labelText: 'Doc status'),
                items: const [
                  DropdownMenuItem(
                    value: _DocStatusFilter.all,
                    child: Text('All'),
                  ),
                  DropdownMenuItem(
                    value: _DocStatusFilter.draft,
                    child: Text('Draft'),
                  ),
                  DropdownMenuItem(
                    value: _DocStatusFilter.submitted,
                    child: Text('Submitted'),
                  ),
                  DropdownMenuItem(
                    value: _DocStatusFilter.cancelled,
                    child: Text('Cancelled'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _docStatus = value);
                },
              ),
              const SizedBox(height: 16),
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
                      child: const Text('Apply'),
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
