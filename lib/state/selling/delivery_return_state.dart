import '../../models/delivery_return.dart';
import '../../services/frappe_service.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/erp_doc_utils.dart';
import '../app_state_proxy_notifier.dart';

class DeliveryReturnState extends AppStateProxyNotifier {
  DeliveryReturnState({required super.appState}) {
    startWatchingAppState();
  }

  static const doctype = 'Delivery Return';

  DeliveryReturnMeta? _metaCache;

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

  Future<void> ensureCompanies() async {
    if (sellingCompanies.isNotEmpty) return;
    await appState.loadSellingFilterOptions();
  }

  Future<List<DeliveryReturnSummary>> fetchList({
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

    Future<List<DeliveryReturnSummary>> load(List<List<dynamic>>? useFilters) async {
      final rows = await frappeService.fetchResource(
        doctype,
        fields: const [
          'name',
          'posting_date',
          'company',
          'customer',
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
          .map(DeliveryReturnSummary.fromJson)
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

  /// Workflow actions for the signed-in role, from the saved document.
  Future<Map<String, List<String>>> fetchWorkflowActionsForRows(
    List<DeliveryReturnSummary> rows, {
    int batchSize = 6,
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
            final actions = await _workflowActionsForName(row.id);
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
    final name = doc['name']?.toString().trim() ?? '';
    if (name.isEmpty) return const [];
    return _workflowActionsForName(name, fallback: doc);
  }

  Future<List<String>> _workflowActionsForName(
    String name, {
    Map<String, dynamic>? fallback,
  }) async {
    Map<String, dynamic> payload;
    try {
      payload = await frappeService.fetchDocument(doctype, name);
    } catch (_) {
      payload = Map<String, dynamic>.from(fallback ?? const {});
    }
    payload['doctype'] = doctype;
    payload['name'] = name;
    if ((payload['workflow_state']?.toString().trim() ?? '').isEmpty) {
      payload['workflow_state'] = 'Draft';
    }
    final raw = await frappeService.callMethod(
      'frappe.model.workflow.get_transitions',
      args: {'doc': payload},
    );
    return inboxActionsFromWorkflowTransitions(raw);
  }

  bool _permissionsEnsured = false;

  /// Gives the workflow roles the same document rights Sales Order uses.
  Future<void> ensureWorkflowRolePermissions() async {
    if (_permissionsEnsured) return;
    _permissionsEnsured = true;
    const roles = <String, Map<String, int>>{
      'Sales': _salesOrderLikePerms,
      'Sales Manager': _salesOrderLikePerms,
      'Sales User': _salesOrderLikePerms,
      'Manager Operational': _salesOrderLikePerms,
      'QC': _salesOrderLikePerms,
      'Quality Control': _salesOrderLikePerms,
      'Admin Warehouse': _salesOrderLikePerms,
      'Warehouse Manager': _salesOrderLikePerms,
    };
    var changed = false;
    try {
      await frappeService.ensureLoggedIn();
      final existing = await frappeService.fetchResource(
        'Custom DocPerm',
        fields: const ['name', 'role', 'read', 'write', 'create'],
        filters: [
          ['parent', '=', doctype],
        ],
        limit: 100,
      );
      final present = {
        for (final row in existing)
          if ((row['role']?.toString().trim() ?? '').isNotEmpty)
            row['role'].toString().trim(),
      };
      for (final entry in roles.entries) {
        if (present.contains(entry.key)) continue;
        try {
          await frappeService.createDocument('Custom DocPerm', {
            'parent': doctype,
            'parenttype': 'DocType',
            'parentfield': 'permissions',
            'role': entry.key,
            'permlevel': 0,
            ...entry.value,
          });
          changed = true;
        } catch (_) {}
      }
    } catch (_) {
      return;
    }
    if (changed) appState.invalidateDoctypePermissionCache();
  }

  Future<Map<String, dynamic>> fetchDetail(String name) async {
    await frappeService.ensureLoggedIn();
    return frappeService.fetchDocument(doctype, name.trim());
  }

  Future<List<String>> fetchNamingSeries() {
    return appState.fetchNamingSeries(doctype);
  }

  Future<DeliveryReturnMeta> resolveMeta({bool forceRefresh = false}) async {
    if (!forceRefresh && _metaCache != null) return _metaCache!;
    await frappeService.ensureLoggedIn();
    var childTableField = 'return_detail';
    var childDoctype = 'Delivery Return Detail';
    var qtyDnField = 'qty_dn';
    var qtyTolakField = 'qty_tolak';
    var customerNameField = 'customer_name';
    var deliveryNoteField = 'delivery_asal';

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
          ['parent', '=', doctype],
        ],
        limit: 200,
      );
      for (final row in rows) {
        if (row['fieldtype']?.toString() != 'Table') continue;
        final fieldname = row['fieldname']?.toString().trim() ?? '';
        final options = row['options']?.toString().trim() ?? '';
        if (fieldname.isEmpty) continue;
        childTableField = fieldname;
        if (options.isNotEmpty) childDoctype = options;
        break;
      }
      for (final row in rows) {
        final fieldname = row['fieldname']?.toString().trim() ?? '';
        final label = '${row['label'] ?? ''} $fieldname'.toLowerCase();
        final options = row['options']?.toString().trim() ?? '';
        if (fieldname.isEmpty) continue;
        if (label.contains('customer name')) {
          customerNameField = fieldname;
        } else if (options == 'Delivery Note' ||
            label.contains('delivery asal') ||
            label.contains('delivery note')) {
          deliveryNoteField = fieldname;
        }
      }
      final childRows = await frappeService.fetchResource(
        'DocField',
        fields: const ['fieldname', 'label', 'parent'],
        filters: [
          ['parent', '=', childDoctype],
        ],
        limit: 200,
      );
      for (final row in childRows) {
        final fieldname = row['fieldname']?.toString().trim() ?? '';
        final label = '${row['label'] ?? ''} $fieldname'.toLowerCase();
        if (fieldname.isEmpty) continue;
        if (label.contains('qty dn') || fieldname == 'qty_dn') {
          qtyDnField = fieldname;
        } else if (label.contains('qty tolak') ||
            label.contains('qty_tolak') ||
            fieldname.contains('tolak')) {
          qtyTolakField = fieldname;
        }
      }
    } catch (_) {
      // Keep defaults; create() still tries known fieldname fallbacks.
    }

    _metaCache = DeliveryReturnMeta(
      childTableField: childTableField,
      childDoctype: childDoctype,
      qtyDnField: qtyDnField,
      qtyTolakField: qtyTolakField,
      customerNameField: customerNameField,
      deliveryNoteField: deliveryNoteField,
    );
    return _metaCache!;
  }

  Future<Map<String, dynamic>> create(DeliveryReturnDraft draft) async {
    await frappeService.ensureLoggedIn();
    final meta = await resolveMeta();
    final attempts = <DeliveryReturnMeta>[
      meta,
      const DeliveryReturnMeta(
        childTableField: 'return_detail',
        childDoctype: 'Delivery Return Detail',
      ),
      const DeliveryReturnMeta(
        childTableField: 'items',
        childDoctype: 'Delivery Return Item',
      ),
      const DeliveryReturnMeta(
        childTableField: 'return_detail',
        childDoctype: 'Return Detail',
      ),
    ];

    Object? lastError;
    final tried = <String>{};
    for (final attempt in attempts) {
      final key =
          '${attempt.childTableField}|${attempt.qtyDnField}|${attempt.qtyTolakField}|${attempt.childDoctype}';
      if (!tried.add(key)) continue;
      try {
        final created = await frappeService.createDocument(
          doctype,
          draft.toFrappeJson(
            childTableField: attempt.childTableField,
            childDoctype: attempt.childDoctype,
            qtyDnField: attempt.qtyDnField,
            qtyTolakField: attempt.qtyTolakField,
            customerNameField: meta.customerNameField,
            deliveryNoteField: meta.deliveryNoteField,
            setDraftWorkflow: true,
          ),
        );
        final name = created['name']?.toString().trim() ?? '';
        if (name.isEmpty) {
          throw Exception(
            'ERP tidak mengembalikan nomor dokumen Delivery Return.',
          );
        }
        _metaCache = attempt;
        return created;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? Exception('Gagal membuat Delivery Return.');
  }

  Future<void> update(String name, DeliveryReturnDraft draft) async {
    await frappeService.ensureLoggedIn();
    final id = name.trim();
    if (id.isEmpty) throw Exception('Dokumen Delivery Return tidak valid.');
    final meta = await resolveMeta();
    try {
      await frappeService.updateDocument(
        doctype,
        id,
        draft.toFrappeJson(
          childTableField: meta.childTableField,
          childDoctype: meta.childDoctype,
          qtyDnField: meta.qtyDnField,
          qtyTolakField: meta.qtyTolakField,
          customerNameField: meta.customerNameField,
          deliveryNoteField: meta.deliveryNoteField,
        ),
      );
    } catch (_) {
      await frappeService.updateDocument(
        doctype,
        id,
        draft.toFrappeJson(
          childTableField: 'items',
          childDoctype: meta.childDoctype,
          qtyDnField: meta.qtyDnField,
          qtyTolakField: meta.qtyTolakField,
          customerNameField: meta.customerNameField,
          deliveryNoteField: meta.deliveryNoteField,
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

  Future<void> uploadAttachment(String name, String filePath) {
    return appState.uploadAttachment(
      doctype: doctype,
      documentName: name,
      filePath: filePath,
    );
  }

  Future<List<Map<String, dynamic>>> fetchAttachments(String name) {
    return appState.fetchDocumentAttachments(
      doctype: doctype,
      documentName: name,
    );
  }

  Future<List<Map<String, dynamic>>> searchDeliveryNotes({
    required String customer,
    String? company,
    String query = '',
    int limit = 40,
  }) async {
    await frappeService.ensureLoggedIn();
    final selectedCustomer = customer.trim();
    if (selectedCustomer.isEmpty) return const [];
    final q = query.trim();
    final selectedCompany = company?.trim() ?? '';
    return frappeService.fetchResource(
      'Delivery Note',
      fields: const ['name', 'posting_date', 'customer', 'customer_name'],
      filters: [
        ['customer', '=', selectedCustomer],
        ['docstatus', '!=', 2],
        if (selectedCompany.isNotEmpty) ['company', '=', selectedCompany],
        if (q.isNotEmpty) ['name', 'like', '%$q%'],
      ],
      orderBy: 'posting_date desc',
      limit: limit,
    );
  }

  Future<List<DeliveryReturnItemDraft>> itemsFromDeliveryNote(String name) async {
    await frappeService.ensureLoggedIn();
    final doc = await frappeService.fetchDocument('Delivery Note', name.trim());
    final rawItems = doc['items'];
    if (rawItems is! List) return const [];
    return [
      for (final raw in rawItems.whereType<Map>())
        if ((raw['item_code']?.toString().trim() ?? '').isNotEmpty)
          DeliveryReturnItemDraft(
            itemCode: raw['item_code'].toString(),
            itemName: raw['item_name']?.toString() ?? '',
            qtyDn: double.tryParse(
                  (raw['qty'] ?? raw['stock_qty'])?.toString() ?? '',
                ) ??
                0,
            qtyTolak: 0,
            uom: raw['uom']?.toString() ?? raw['stock_uom']?.toString() ?? '',
          ),
    ];
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

const _salesOrderLikePerms = <String, int>{
  'select': 1,
  'read': 1,
  'write': 1,
  'create': 1,
  'delete': 1,
  'submit': 1,
  'cancel': 1,
  'amend': 1,
  'report': 1,
  'export': 1,
  'print': 1,
  'email': 1,
  'share': 1,
};
