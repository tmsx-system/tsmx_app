import '../../models/tukar_guling.dart';
import '../../services/frappe_service.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/erp_doc_utils.dart';
import '../app_state_proxy_notifier.dart';

class TukarGulingState extends AppStateProxyNotifier {
  TukarGulingState({required super.appState}) {
    startWatchingAppState();
  }

  static const doctype = 'Tukar Guling';

  TukarGulingMeta? _metaCache;

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.sellingCompanies,
  ];

  FrappeService get frappeService => appState.frappeService;
  List<String> get sellingCompanies => appState.sellingCompanies;

  Future<bool> canRead() => appState.canReadDoctype(doctype);
  Future<bool> canCreate() => appState.canCreateDoctype(doctype);
  Future<bool> canWrite() => appState.canWriteDoctype(doctype);

  String? preferredCompany(Iterable<String> options) {
    return appState.preferredCompany(options);
  }

  Future<List<TukarGulingSummary>> fetchList({
    String? company,
    String? customer,
    String? workflowState,
    DateTime? postingDateFrom,
    DateTime? postingDateTo,
    int limit = 50,
  }) async {
    await frappeService.ensureLoggedIn();
    final filters = <List<dynamic>>[];
    final selectedCompany = company?.trim() ?? '';
    if (selectedCompany.isNotEmpty) {
      filters.add(['company', '=', selectedCompany]);
    }
    final selectedCustomer = customer?.trim() ?? '';
    if (selectedCustomer.isNotEmpty) {
      filters.add(['customer', '=', selectedCustomer]);
    }
    final state = workflowState?.trim() ?? '';
    if (state.isNotEmpty) {
      filters.add(['workflow_state', '=', state]);
    }
    final from = postingDateFrom == null
        ? null
        : DateTime(
            postingDateFrom.year,
            postingDateFrom.month,
            postingDateFrom.day,
          );
    final to = postingDateTo == null
        ? null
        : DateTime(
            postingDateTo.year,
            postingDateTo.month,
            postingDateTo.day,
          );
    if (from != null && to != null) {
      final start = from.isBefore(to) ? from : to;
      final end = from.isBefore(to) ? to : from;
      filters.add([
        'posting_date',
        'between',
        [DateRangePresets.toFrappeDate(start), DateRangePresets.toFrappeDate(end)],
      ]);
    } else if (from != null) {
      filters.add([
        'posting_date',
        '>=',
        DateRangePresets.toFrappeDate(from),
      ]);
    } else if (to != null) {
      filters.add([
        'posting_date',
        '<=',
        DateRangePresets.toFrappeDate(to),
      ]);
    }

    Future<List<TukarGulingSummary>> load(List<List<dynamic>>? useFilters) async {
      final rows = await frappeService.fetchResource(
        doctype,
        fields: const [
          'name',
          'posting_date',
          'company',
          'customer',
          'stock_entry',
          'workflow_state',
          'keterangan',
          'modified',
          'docstatus',
        ],
        filters: useFilters == null || useFilters.isEmpty ? null : useFilters,
        orderBy: 'modified desc',
        limit: limit,
      );
      return rows
          .map(TukarGulingSummary.fromJson)
          .where((row) => row.id.isNotEmpty)
          .toList(growable: false);
    }

    try {
      return await load(filters);
    } catch (_) {
      // Retry without workflow_state / date between via simpler filters.
      try {
        return await load(
          filters
              .where(
                (f) =>
                    f.isNotEmpty &&
                    f.first != 'workflow_state' &&
                    !(f.first == 'posting_date' && f.length > 1 && f[1] == 'between'),
              )
              .toList(),
        );
      } catch (_) {
        return await load(
          filters
              .where(
                (f) =>
                    f.isNotEmpty &&
                    f.first != 'workflow_state' &&
                    f.first != 'posting_date',
              )
              .toList(),
        );
      }
    }
  }

  /// Batch get_transitions from list rows (no full GET per row).
  Future<Map<String, List<String>>> fetchWorkflowActionsForRows(
    List<TukarGulingSummary> rows, {
    int batchSize = 8,
  }) async {
    await frappeService.ensureLoggedIn();
    final actionsByName = <String, List<String>>{};
    final targets = rows.where((r) => r.id.isNotEmpty).take(24).toList();
    for (var start = 0; start < targets.length; start += batchSize) {
      final end = (start + batchSize > targets.length)
          ? targets.length
          : start + batchSize;
      final batch = targets.sublist(start, end);
      final results = await Future.wait(
        batch.map((row) async {
          try {
            final doc = <String, dynamic>{
              'doctype': doctype,
              'name': row.id,
              'workflow_state': row.workflowState.isEmpty
                  ? 'Draft'
                  : row.workflowState,
              'company': row.company,
              'customer': row.customer,
              'posting_date': row.postingDate,
              'docstatus': 0,
            };
            final raw = await frappeService.callMethod(
              'frappe.model.workflow.get_transitions',
              args: {'doc': doc},
            );
            final actions = inboxActionsFromWorkflowTransitions(raw);
            return (name: row.id, actions: actions);
          } catch (_) {
            return (name: row.id, actions: const <String>[]);
          }
        }),
      );
      for (final result in results) {
        if (result.actions.isNotEmpty) {
          actionsByName[result.name] = result.actions;
        }
      }
    }
    return actionsByName;
  }

  Future<List<String>> fetchWorkflowActionsForDocument(
    Map<String, dynamic> doc,
  ) async {
    await frappeService.ensureLoggedIn();
    final payload = Map<String, dynamic>.from(doc);
    payload['doctype'] = doctype;
    final raw = await frappeService.callMethod(
      'frappe.model.workflow.get_transitions',
      args: {'doc': payload},
    );
    return inboxActionsFromWorkflowTransitions(raw);
  }

  Future<Map<String, dynamic>> fetchDetail(String name) async {
    await frappeService.ensureLoggedIn();
    return frappeService.fetchDocument(doctype, name.trim());
  }

  Future<List<String>> fetchNamingSeries() {
    return appState.fetchNamingSeries(doctype);
  }

  Future<TukarGulingMeta> resolveMeta({bool forceRefresh = false}) async {
    if (!forceRefresh && _metaCache != null) return _metaCache!;
    await frappeService.ensureLoggedIn();
    var childTableField = 'tukar_guling_item';
    var childDoctype = 'Tukar Guling Item';
    var warehouseField = 'source_warehouse';

    try {
      final rows = await frappeService.fetchResource(
        'DocField',
        fields: const [
          'fieldname',
          'fieldtype',
          'options',
          'label',
          'parent',
        ],
        filters: [
          ['parent', 'in', [doctype, 'Tukar Guling Item']],
        ],
        limit: 200,
      );
      for (final row in rows) {
        if (row['parent']?.toString() != doctype) continue;
        if (row['fieldtype']?.toString() != 'Table') continue;
        final fieldname = row['fieldname']?.toString().trim() ?? '';
        final options = row['options']?.toString().trim() ?? '';
        if (fieldname.isEmpty) continue;
        childTableField = fieldname;
        if (options.isNotEmpty) childDoctype = options;
      }
      for (final row in rows) {
        if (row['parent']?.toString() != childDoctype) continue;
        final fieldname = row['fieldname']?.toString().trim() ?? '';
        final label = '${row['label'] ?? ''} $fieldname'.toLowerCase();
        if (fieldname.isEmpty) continue;
        if (fieldname.contains('warehouse') ||
            label.contains('source warehouse') ||
            label.contains('gudang')) {
          warehouseField = fieldname;
          break;
        }
      }
    } catch (_) {
      // Keep defaults; create() still tries known fieldname fallbacks.
    }

    _metaCache = TukarGulingMeta(
      childTableField: childTableField,
      childDoctype: childDoctype,
      warehouseField: warehouseField,
    );
    return _metaCache!;
  }

  Future<Map<String, dynamic>> create(TukarGulingDraft draft) async {
    await frappeService.ensureLoggedIn();
    final meta = await resolveMeta();
    final attempts = <TukarGulingMeta>[
      meta,
      const TukarGulingMeta(
        childTableField: 'tukar_guling_item',
        childDoctype: 'Tukar Guling Item',
        warehouseField: 'source_warehouse',
      ),
      const TukarGulingMeta(
        childTableField: 'items',
        childDoctype: 'Tukar Guling Item',
        warehouseField: 'source_warehouse',
      ),
      const TukarGulingMeta(
        childTableField: 'tukar_guling_item',
        childDoctype: 'Tukar Guling Item',
        warehouseField: 's_warehouse',
      ),
      const TukarGulingMeta(
        childTableField: 'items',
        childDoctype: 'Tukar Guling Item',
        warehouseField: 's_warehouse',
      ),
    ];

    Object? lastError;
    final tried = <String>{};
    for (final attempt in attempts) {
      final key =
          '${attempt.childTableField}|${attempt.warehouseField}|${attempt.childDoctype}';
      if (!tried.add(key)) continue;
      try {
        final created = await frappeService.createDocument(
          doctype,
          draft.toFrappeJson(
            childTableField: attempt.childTableField,
            childDoctype: attempt.childDoctype,
            warehouseField: attempt.warehouseField,
          ),
        );
        final name = created['name']?.toString().trim() ?? '';
        if (name.isEmpty) {
          throw Exception('ERP tidak mengembalikan nomor dokumen Tukar Guling.');
        }
        _metaCache = attempt;
        return created;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? Exception('Gagal membuat Tukar Guling.');
  }

  Future<void> update(String name, TukarGulingDraft draft) async {
    await frappeService.ensureLoggedIn();
    final id = name.trim();
    if (id.isEmpty) throw Exception('Dokumen Tukar Guling tidak valid.');
    final meta = await resolveMeta();
    try {
      await frappeService.updateDocument(
        doctype,
        id,
        draft.toFrappeJson(
          childTableField: meta.childTableField,
          childDoctype: meta.childDoctype,
          warehouseField: meta.warehouseField,
        ),
      );
    } catch (_) {
      await frappeService.updateDocument(
        doctype,
        id,
        draft.toFrappeJson(
          childTableField: 'items',
          childDoctype: meta.childDoctype,
          warehouseField: meta.warehouseField,
        ),
      );
    }
  }

  Future<List<String>> fetchDocumentWorkflowActions(String name) {
    return appState.fetchDocumentWorkflowActions(
      doctype: doctype,
      name: name,
    );
  }

  Future<void> applyDocumentWorkflow({
    required String name,
    required String action,
    String reason = '',
    Map<String, dynamic>? currentDocument,
  }) {
    return appState.applyDocumentWorkflow(
      doctype: doctype,
      name: name,
      action: action,
      reason: reason,
      refreshAfterApply: false,
      currentDocument: currentDocument,
    );
  }

  Future<List<Map<String, dynamic>>> searchCustomers({
    String query = '',
    int limit = 40,
  }) async {
    await frappeService.ensureLoggedIn();
    final q = query.trim();
    return frappeService.fetchResource(
      'Customer',
      fields: const ['name', 'customer_name'],
      filters: const [
        ['disabled', '=', 0],
      ],
      orFilters: q.isEmpty
          ? null
          : [
              ['name', 'like', '%$q%'],
              ['customer_name', 'like', '%$q%'],
            ],
      orderBy: 'customer_name asc',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> searchItems({
    String query = '',
    int limit = 40,
  }) async {
    await frappeService.ensureLoggedIn();
    final q = query.trim();
    return frappeService.fetchResource(
      'Item',
      fields: const ['name', 'item_name', 'stock_uom'],
      filters: [
        ['disabled', '=', 0],
        ['is_stock_item', '=', 1],
        if (q.isNotEmpty) ['item_name', 'like', '%$q%'],
      ],
      orFilters: q.isEmpty
          ? null
          : [
              ['name', 'like', '%$q%'],
              ['item_name', 'like', '%$q%'],
            ],
      orderBy: 'item_name asc',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> searchWarehouses({
    String query = '',
    String? company,
    int limit = 40,
  }) async {
    await frappeService.ensureLoggedIn();
    final q = query.trim();
    final selectedCompany = company?.trim() ?? '';
    return frappeService.fetchResource(
      'Warehouse',
      fields: const ['name', 'warehouse_name', 'company'],
      filters: [
        ['is_group', '=', 0],
        ['disabled', '=', 0],
        if (selectedCompany.isNotEmpty) ['company', '=', selectedCompany],
      ],
      orFilters: q.isEmpty
          ? null
          : [
              ['name', 'like', '%$q%'],
              ['warehouse_name', 'like', '%$q%'],
            ],
      orderBy: 'name asc',
      limit: limit,
    );
  }

  String formatDisplayDate(DateTime date) =>
      DateRangePresets.formatDisplay(date);
}
