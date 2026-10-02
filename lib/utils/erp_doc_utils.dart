import 'num_parse.dart';

int docStatusFromJson(Map<String, dynamic> json) =>
    NumParse.asInt(json['docstatus']);

bool isDocDraft(int docstatus) => docstatus == 0;

bool isDocSubmitted(int docstatus) => docstatus == 1;

bool isDocCancelled(int docstatus) => docstatus == 2;

String docStatusLabel(int docstatus) {
  switch (docstatus) {
    case 0:
      return 'Draft';
    case 1:
      return 'Submitted';
    case 2:
      return 'Cancelled';
    default:
      return 'Unknown';
  }
}

bool isApprovalDecisionAction(String action) {
  final text = action.trim().toLowerCase();
  if (text.isEmpty) return false;
  const submitLike = ['submit', 'save', 'amend', 'update'];
  if (submitLike.any(text.contains)) return false;
  const decisionLike = [
    'approve',
    'reject',
    'tolak',
    'setujui',
    'decline',
  ];
  return decisionLike.any(text.contains);
}

List<String> approvalDecisionActions(Iterable<String> actions) {
  return actions
      .map((action) => action.trim())
      .where(isApprovalDecisionAction)
      .toSet()
      .toList(growable: false);
}

bool isApprovalInboxCandidateRow(
  Map<String, dynamic> row, {
  Map<String, int> workflowStateDocStatus = const {},
}) {
  final docstatus = NumParse.asInt(row['docstatus']);
  if (docstatus != 0) return false;
  final workflowState = (row['workflow_state']?.toString() ?? '').trim();
  if (workflowState.isEmpty) return false;
  final mapped = workflowStateDocStatus[workflowState];
  if (mapped != null && mapped != 0) return false;
  return true;
}

bool isOpenWorkflowInbox({
  required int docStatus,
  required String workflowState,
  required Iterable<String> actions,
  Map<String, int> workflowStateDocStatus = const {},
}) {
  if (docStatus != 0 || !actions.any((action) => action.trim().isNotEmpty)) {
    return false;
  }
  final mapped = workflowStateDocStatus[workflowState.trim()];
  if (mapped != null && mapped != 0) return false;
  return true;
}

List<List<dynamic>> approvalInboxListFilters() => [
  ['docstatus', '=', 0],
  ['workflow_state', 'is', 'set'],
];

Map<String, int> workflowStateDocStatusByName(
  Iterable<Map<String, dynamic>> rows,
) {
  final mapped = <String, int>{};
  for (final row in rows) {
    final docStatus = NumParse.asInt(row['doc_status']);
    for (final key in [
      row['state'],
      row['name'],
      row['workflow_state_name'],
    ]) {
      final name = key?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final previous = mapped[name] ?? 0;
      if (docStatus > previous) mapped[name] = docStatus;
    }
  }
  return mapped;
}

bool isCancelPathWorkflowTransition(
  Map transition,
  Map<String, int> workflowStateDocStatus,
) {
  final nextState = (transition['next_state'] ?? transition['Next State'] ?? '')
      .toString()
      .trim();
  if (nextState.isEmpty) return false;
  return workflowStateDocStatus[nextState] == 2;
}

List<String> inboxActionsFromWorkflowTransitions(
  dynamic rawTransitions, {
  Map<String, int> workflowStateDocStatus = const {},
}) {
  var payload = rawTransitions;
  if (payload is Map) {
    payload = payload['message'] ?? payload['data'] ?? payload['transitions'];
  }
  if (payload is! List) return const [];
  final actions = <String>{};
  for (final row in payload) {
    if (row is Map) {
      if (isCancelPathWorkflowTransition(row, workflowStateDocStatus)) {
        continue;
      }
      final action = (row['action'] ?? row['Action'] ?? '').toString().trim();
      if (action.isNotEmpty) actions.add(action);
    } else if (row is String && row.trim().isNotEmpty) {
      actions.add(row.trim());
    }
  }
  return actions.toList(growable: false);
}

double _pendingQty(Map<String, dynamic> row, String deliveredField) {
  final qty = NumParse.asDouble(row['qty'] ?? row['stock_qty']);
  final done = NumParse.asDouble(row[deliveredField]);
  final pending = qty - done;
  return pending > 0 ? pending : qty;
}

List<Map<String, dynamic>> buildDeliveryNoteItemsFromSalesOrder(
  Map<String, dynamic> so,
) {
  final rawItems = so['items'];
  if (rawItems is! List) return [];

  final items = <Map<String, dynamic>>[];
  for (final row in rawItems) {
    if (row is! Map) continue;
    final m = Map<String, dynamic>.from(row);
    final qty = _pendingQty(m, 'delivered_qty');
    if (qty <= 0) continue;

    items.add({
      'item_code': m['item_code'],
      'qty': qty,
      'rate': m['rate'],
      if (m['warehouse'] != null) 'warehouse': m['warehouse'],
      'against_sales_order': so['name'],
      if (m['name'] != null) 'so_detail': m['name'],
    });
  }
  return items;
}

List<Map<String, dynamic>> buildSalesInvoiceItemsFromSalesOrder(
  Map<String, dynamic> so,
) {
  final rawItems = so['items'];
  if (rawItems is! List) return [];

  final items = <Map<String, dynamic>>[];
  for (final row in rawItems) {
    if (row is! Map) continue;
    final m = Map<String, dynamic>.from(row);
    final qtyField = NumParse.asDouble(m['qty']);
    final billedAmt = NumParse.asDouble(m['billed_amt']);
    final rate = NumParse.asDouble(m['rate']);
    final pendingQty = rate > 0 && billedAmt > 0
        ? (qtyField - (billedAmt / rate))
        : _pendingQty(m, 'billed_qty');
    final useQty = pendingQty > 0 ? pendingQty : qtyField;
    if (useQty <= 0) continue;

    items.add({
      'item_code': m['item_code'],
      'qty': useQty,
      'rate': m['rate'],
      if (m['warehouse'] != null) 'warehouse': m['warehouse'],
      'sales_order': so['name'],
      if (m['name'] != null) 'so_detail': m['name'],
    });
  }
  return items;
}

List<Map<String, dynamic>> buildPurchaseReceiptItemsFromPurchaseOrder(
  Map<String, dynamic> po,
) {
  final rawItems = po['items'];
  if (rawItems is! List) return [];

  final items = <Map<String, dynamic>>[];
  for (final row in rawItems) {
    if (row is! Map) continue;
    final m = Map<String, dynamic>.from(row);
    final qty = _pendingQty(m, 'received_qty');
    if (qty <= 0) continue;

    items.add({
      'item_code': m['item_code'],
      'qty': qty,
      'rate': m['rate'],
      if (m['warehouse'] != null) 'warehouse': m['warehouse'],
      'purchase_order': po['name'],
      if (m['name'] != null) 'po_detail': m['name'],
    });
  }
  return items;
}

List<Map<String, dynamic>> buildPurchaseInvoiceItemsFromPurchaseOrder(
  Map<String, dynamic> po,
) {
  final rawItems = po['items'];
  if (rawItems is! List) return [];

  final items = <Map<String, dynamic>>[];
  for (final row in rawItems) {
    if (row is! Map) continue;
    final m = Map<String, dynamic>.from(row);
    final qtyField = NumParse.asDouble(m['qty']);
    if (qtyField <= 0) continue;

    items.add({
      'item_code': m['item_code'],
      'qty': qtyField,
      'rate': m['rate'],
      if (m['warehouse'] != null) 'warehouse': m['warehouse'],
      'purchase_order': po['name'],
      if (m['name'] != null) 'po_detail': m['name'],
    });
  }
  return items;
}

List<ErpDetailRowData> itemRowsFromDoc(Map<String, dynamic> doc) {
  final rawItems = doc['items'];
  if (rawItems is! List || rawItems.isEmpty) {
    return [const ErpDetailRowData(label: 'Items', value: '—')];
  }

  return rawItems.take(12).map((row) {
    final m = Map<String, dynamic>.from(row as Map);
    final name =
        m['item_name']?.toString() ?? m['item_code']?.toString() ?? 'Item';
    final qty = NumParse.asDouble(m['qty'] ?? m['stock_qty']);
    final rate = NumParse.asDouble(m['rate']);
    return ErpDetailRowData(
      label: name,
      value: '${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2)} × ${rate.toStringAsFixed(0)}',
    );
  }).toList();
}

class ErpDetailRowData {
  final String label;
  final String value;

  const ErpDetailRowData({required this.label, required this.value});
}
