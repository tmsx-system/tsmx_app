import '../../models/stock_opname.dart';
import '../../services/frappe_service.dart';
import '../app_state.dart';

class StockOpnameState {
  StockOpnameState(this.appState);

  final AppState appState;

  static const doctype = 'Stock Opname';
  static const tableField = 'stock_opname_detail';

  FrappeService get _frappe => appState.frappeService;

  Future<bool> canCreate() => appState.canCreateDoctype(doctype);
  Future<bool> canWrite() => appState.canWriteDoctype(doctype);
  Future<bool> canSubmit() => appState.canSubmitDoctype(doctype);

  Future<List<StockOpnameSummary>> fetchList({
    String? company,
    String? name,
  }) async {
    await _frappe.ensureLoggedIn();
    final filters = <List<dynamic>>[
      if ((company ?? '').trim().isNotEmpty) ['company', '=', company!.trim()],
      if ((name ?? '').trim().isNotEmpty) ['name', 'like', '%${name!.trim()}%'],
    ];
    try {
      return _mapList(
        await _frappe.fetchResource(
          doctype,
          fields: const [
            'name',
            'posting_date',
            'posting_time',
            'company',
            'warehouse',
            'item_group',
            'status_penyelesaian',
            'docstatus',
          ],
          filters: filters,
          orderBy: 'modified desc',
          limit: 80,
        ),
      );
    } catch (_) {
      return _mapList(
        await _frappe.fetchResource(
          doctype,
          fields: const [
            'name',
            'posting_date',
            'posting_time',
            'company',
            'warehouse',
            'item_group',
            'docstatus',
          ],
          filters: filters,
          orderBy: 'modified desc',
          limit: 80,
        ),
      );
    }
  }

  List<StockOpnameSummary> _mapList(List<Map<String, dynamic>> rows) {
    return [
      for (final row in rows)
        if ((row['name']?.toString().trim() ?? '').isNotEmpty)
          StockOpnameSummary.fromJson(row),
    ];
  }

  Future<Map<String, dynamic>> fetchDetail(String name) async {
    await _frappe.ensureLoggedIn();
    return _frappe.fetchDocument(doctype, name.trim());
  }

  Future<List<String>> fetchNamingSeries() {
    return appState.fetchNamingSeries(doctype);
  }

  Future<List<String>> searchItemGroups(String query) async {
    await _frappe.ensureLoggedIn();
    final text = query.trim();
    final rows = await _frappe.fetchResource(
      'Item Group',
      fields: const ['name'],
      filters: [
        if (text.isNotEmpty) ['name', 'like', '%$text%'],
      ],
      orderBy: 'name asc',
      limit: text.isEmpty ? 40 : 30,
    );
    return [
      for (final row in rows)
        if ((row['name']?.toString().trim() ?? '').isNotEmpty)
          row['name'].toString().trim(),
    ];
  }

  Future<List<String>> itemGroupsUnder(String itemGroup) async {
    final name = itemGroup.trim();
    if (name.isEmpty) return const [];
    await _frappe.ensureLoggedIn();
    final doc = await _frappe.fetchDocument('Item Group', name);
    final lft = num.tryParse(doc['lft']?.toString() ?? '');
    final rgt = num.tryParse(doc['rgt']?.toString() ?? '');
    if (lft == null || rgt == null) return [name];
    final rows = await _frappe.fetchResource(
      'Item Group',
      fields: const ['name'],
      filters: [
        ['lft', '>=', lft],
        ['rgt', '<=', rgt],
      ],
      limit: 1000,
    );
    final names = [
      for (final row in rows)
        if ((row['name']?.toString().trim() ?? '').isNotEmpty)
          row['name'].toString().trim(),
    ];
    return names.isEmpty ? [name] : names;
  }

  Future<List<StockOpnameItemChoice>> itemsInGroups(List<String> groups) async {
    if (groups.isEmpty) return const [];
    await _frappe.ensureLoggedIn();
    final rows = await _frappe.fetchResource(
      'Item',
      fields: const ['name', 'item_name', 'item_group', 'stock_uom'],
      filters: [
        ['disabled', '=', 0],
        ['is_stock_item', '=', 1],
        ['item_group', 'in', groups],
      ],
      orderBy: 'item_name asc',
      limit: 1000,
    );
    return [
      for (final row in rows)
        if ((row['name']?.toString().trim() ?? '').isNotEmpty)
          StockOpnameItemChoice(
            code: row['name'].toString().trim(),
            name: (row['item_name']?.toString().trim().isNotEmpty ?? false)
                ? row['item_name'].toString().trim()
                : row['name'].toString().trim(),
            itemGroup: row['item_group']?.toString() ?? '',
            uom: row['stock_uom']?.toString().trim().isNotEmpty == true
                ? row['stock_uom'].toString()
                : 'Box',
          ),
    ];
  }

  /// Stock on hand at the opname date and time, from Stock Ledger Entry.
  Future<double> stockAwal({
    required String company,
    required String warehouse,
    required String postingDate,
    required String postingTime,
    required String itemCode,
  }) async {
    if (company.trim().isEmpty ||
        warehouse.trim().isEmpty ||
        postingDate.trim().isEmpty ||
        itemCode.trim().isEmpty) {
      return 0;
    }
    await _frappe.ensureLoggedIn();
    final time = postingTime.trim().isEmpty ? '23:59:59' : postingTime.trim();
    const fields = [
      'name',
      'posting_date',
      'posting_time',
      'qty_after_transaction',
    ];
    const orderBy = 'posting_date desc, posting_time desc, creation desc';
    final base = <List<dynamic>>[
      ['company', '=', company.trim()],
      ['warehouse', '=', warehouse.trim()],
      ['item_code', '=', itemCode.trim()],
      ['is_cancelled', '=', 0],
    ];
    final current = await _frappe.fetchResource(
      'Stock Ledger Entry',
      fields: fields,
      filters: [
        ...base,
        ['posting_date', '=', postingDate.trim()],
        ['posting_time', '<=', time],
      ],
      orderBy: orderBy,
      limit: 1,
    );
    if (current.isNotEmpty) return _qty(current.first['qty_after_transaction']);
    final previous = await _frappe.fetchResource(
      'Stock Ledger Entry',
      fields: fields,
      filters: [
        ...base,
        ['posting_date', '<', postingDate.trim()],
      ],
      orderBy: orderBy,
      limit: 1,
    );
    if (previous.isNotEmpty) {
      return _qty(previous.first['qty_after_transaction']);
    }
    return 0;
  }

  Future<Map<String, dynamic>> create(StockOpnameDraft draft) async {
    await _frappe.ensureLoggedIn();
    return _frappe.createDocument(doctype, draft.toFrappeJson());
  }

  Future<void> update(String name, StockOpnameDraft draft) async {
    await _frappe.ensureLoggedIn();
    await _frappe.updateDocument(
      doctype,
      name.trim(),
      draft.toFrappeJson(parentName: name.trim()),
    );
  }

  Future<void> submit(String name) async {
    await _frappe.ensureLoggedIn();
    await _frappe.submitDocument(doctype, name.trim());
  }

  List<StockOpnameLine> linesOf(Map<String, dynamic> doc) => _linesOf(doc);

  List<StockOpnameLine> _linesOf(Map<String, dynamic> doc) {
    final raw = doc[tableField];
    if (raw is! List) return const [];
    return [
      for (final row in raw.whereType<Map>())
        if ((row['item_code']?.toString().trim() ?? '').isNotEmpty)
          StockOpnameLine.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  double _qty(Object? value) {
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  }
}
