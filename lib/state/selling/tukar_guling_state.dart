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
              'docstatus': row.docstatus,
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
    var jenisField = 'custom_jenis_input';
    var metodeField = 'custom_metode_final';
    var customerNameField = 'customer_name';
    var claimTableField = 'custom_claim_details';
    var claimDoctype = 'Tukar Guling Harian';
    var claimDateField = 'posting_date';
    var claimItemField = 'item';
    var claimQtyField = 'qty_kg';
    var claimNoteField = 'keterangan';
    var claimSourceField = 'notg';
    var claimAllocatedField = 'allocated_kg';
    var sourceTableField = 'custom_sisa_sources';
    var sourceDoctype = '';
    var sourceRefField = 'tg_final_sumber';
    var balanceTableField = 'saldo_sisa_per_sku';
    var balanceDoctype = '';

    try {
      final forms = await _formFields(doctype);
      final parentRows = forms[doctype] ?? const <Map<String, dynamic>>[];
      for (final row in parentRows) {
        final fieldname = row['fieldname']?.toString().trim() ?? '';
        final fieldtype = row['fieldtype']?.toString() ?? '';
        final options = row['options']?.toString().trim() ?? '';
        final label = '${row['label'] ?? ''} $fieldname'.toLowerCase();
        if (fieldname.isEmpty) continue;
        if (fieldtype == 'Table') {
          final optionName = options.toLowerCase();
          final isClaim = fieldname == 'custom_claim_details' ||
              label.contains('klaim') ||
              label.contains('claim') ||
              optionName.contains('harian');
          final isItem = !isClaim &&
              fieldname != 'custom_sisa_sources' &&
              fieldname != 'saldo_sisa_per_sku' &&
              (optionName.contains('item') || label.contains('item'));
          if (fieldname == 'custom_sisa_sources') {
            sourceTableField = fieldname;
            sourceDoctype = options.isNotEmpty ? options : 'TG Sisa Source';
          } else if (fieldname == 'saldo_sisa_per_sku') {
            balanceTableField = fieldname;
            balanceDoctype = options.isNotEmpty ? options : 'TG Sisa Detail';
          } else if (isClaim) {
            claimTableField = fieldname;
            if (options.isNotEmpty) claimDoctype = options;
          } else if (label.contains('sisa') &&
              (label.contains('sumber') || fieldname.contains('source'))) {
            sourceTableField = fieldname;
            sourceDoctype = options;
          } else if (label.contains('sisa') ||
              label.contains('saldo') ||
              fieldname.contains('saldo')) {
            balanceTableField = fieldname;
            balanceDoctype = options;
          } else if (isItem && fieldname != 'items') {
            childTableField = fieldname;
            if (options.isNotEmpty) childDoctype = options;
          }
        } else if (fieldtype == 'Select' &&
            options.toLowerCase().contains('harian') &&
            options.toLowerCase().contains('final') &&
            !options.toLowerCase().contains('langsung')) {
          jenisField = fieldname;
        } else if (fieldtype == 'Select' &&
            options.toLowerCase().contains('input langsung')) {
          metodeField = fieldname;
        } else if (label.contains('customer name')) {
          customerNameField = fieldname;
        }
      }

      final itemFields =
          forms[childDoctype] ?? await _schemaFields(childDoctype);
      for (final row in itemFields) {
        final fieldname = row['fieldname']?.toString().trim() ?? '';
        final label = '${row['label'] ?? ''} $fieldname'.toLowerCase();
        if (fieldname.isEmpty) continue;
        if (fieldname.contains('warehouse') || label.contains('gudang')) {
          warehouseField = fieldname;
          break;
        }
      }

      final claimFields =
          forms[claimDoctype] ?? await _schemaFields(claimDoctype);
      String? qtyKg;
      String? itemLink;
      for (final row in claimFields) {
        final fieldname = row['fieldname']?.toString().trim() ?? '';
        final fieldtype = row['fieldtype']?.toString() ?? '';
        final label = '${row['label'] ?? ''} $fieldname'.toLowerCase();
        final options = row['options']?.toString().trim() ?? '';
        if (fieldname.isEmpty) continue;
        if (fieldname == 'posting_date' ||
            label.contains('tanggal') ||
            fieldname.contains('tanggal')) {
          claimDateField = fieldname;
        } else if (fieldname.contains('allocat')) {
          claimAllocatedField = fieldname;
        } else if (fieldname == 'qty_kg' ||
            (fieldname.contains('qty') && fieldname.contains('kg'))) {
          qtyKg = fieldname;
        } else if (fieldname == 'qty' && qtyKg == null) {
          claimQtyField = fieldname;
        } else if (fieldtype == 'Link' && options == 'Item') {
          itemLink = fieldname;
        } else if (fieldname == 'keterangan' || label.contains('keterangan')) {
          claimNoteField = fieldname;
        } else if (fieldtype == 'Link' && options == doctype) {
          claimSourceField = fieldname;
        }
      }
      if (qtyKg != null) claimQtyField = qtyKg;
      if (itemLink != null) claimItemField = itemLink;
      if (sourceDoctype.isNotEmpty) {
        final sourceFields =
            forms[sourceDoctype] ?? await _schemaFields(sourceDoctype);
        final names = {
          for (final row in sourceFields)
            row['fieldname']?.toString().trim() ?? '',
        };
        if (names.contains('tg_final_sumber')) {
          sourceRefField = 'tg_final_sumber';
        } else if (names.contains('source_final')) {
          sourceRefField = 'source_final';
        }
      }
    } catch (_) {
      // The form can still save with the field names already used by ERP.
    }

    _metaCache = TukarGulingMeta(
      childTableField: childTableField,
      childDoctype: childDoctype,
      warehouseField: warehouseField,
      jenisField: jenisField,
      metodeField: metodeField,
      customerNameField: customerNameField,
      claimTableField: claimTableField,
      claimDoctype: claimDoctype,
      claimDateField: claimDateField,
      claimItemField: claimItemField,
      claimQtyField: claimQtyField,
      claimNoteField: claimNoteField,
      claimSourceField: claimSourceField,
      claimAllocatedField: claimAllocatedField,
      sourceTableField: sourceTableField,
      sourceDoctype: sourceDoctype.trim().isEmpty
          ? 'TG Sisa Source'
          : sourceDoctype,
      sourceRefField: sourceRefField,
      balanceTableField: balanceTableField,
      balanceDoctype: balanceDoctype.trim().isEmpty
          ? 'TG Sisa Detail'
          : balanceDoctype,
    );
    return _metaCache!;
  }

  Future<Map<String, dynamic>> create(TukarGulingDraft draft) async {
    await frappeService.ensureLoggedIn();
    final meta = _metaForSave(await resolveMeta());
    final created = await frappeService.createDocument(
      doctype,
      draft.toFrappeJson(meta: meta),
    );
    final name = created['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      throw Exception('ERP tidak mengembalikan nomor dokumen Tukar Guling.');
    }
    _metaCache = meta;
    return created;
  }

  Future<void> update(String name, TukarGulingDraft draft) async {
    await frappeService.ensureLoggedIn();
    final id = name.trim();
    if (id.isEmpty) throw Exception('Dokumen Tukar Guling tidak valid.');
    final meta = _metaForSave(await resolveMeta());
    await frappeService.updateDocument(
      doctype,
      id,
      draft.toFrappeJson(meta: meta, parentName: id),
    );
    _metaCache = meta;
  }

  TukarGulingMeta _metaForSave(TukarGulingMeta meta) {
    final itemField = meta.childTableField.trim();
    if (itemField.isNotEmpty && itemField != 'items') return meta;
    return meta.copyWith(
      childTableField: 'tukar_guling_item',
      childDoctype: meta.childDoctype.trim().isEmpty
          ? 'Tukar Guling Item'
          : meta.childDoctype,
      warehouseField: meta.warehouseField.trim().isEmpty
          ? 'source_warehouse'
          : meta.warehouseField,
    );
  }

  /// Draft Harian claims for one customer, still counted in kg.
  Future<List<TukarGulingDailyClaim>> fetchDailyClaims({
    required String customer,
    String? company,
    String? excludeName,
    DateTime? postingDate,
  }) async {
    await frappeService.ensureLoggedIn();
    final meta = await resolveMeta();
    final selectedCustomer = customer.trim();
    if (selectedCustomer.isEmpty) return const [];
    final date = postingDate == null
        ? ''
        : '${postingDate.year.toString().padLeft(4, '0')}-'
            '${postingDate.month.toString().padLeft(2, '0')}-'
            '${postingDate.day.toString().padLeft(2, '0')}';
    final filters = <List<dynamic>>[
      ['customer', '=', selectedCustomer],
      ['docstatus', '=', 0],
      if ((company ?? '').trim().isNotEmpty) ['company', '=', company!.trim()],
      [meta.jenisField, '=', 'Harian'],
      ['workflow_state', '=', 'Draft'],
      if (date.isNotEmpty) ['posting_date', '<=', date],
    ];
    final rows = await _fetchListDroppingBlockedFields(
      fields: const ['name', 'posting_date', 'customer', 'company', 'docstatus'],
      filters: filters,
    );
    final claims = <TukarGulingDailyClaim>[];
    for (final row in rows) {
      final name = row['name']?.toString().trim() ?? '';
      if (name.isEmpty || name == excludeName?.trim()) continue;
      final doc = await frappeService.fetchDocument(doctype, name);
      final jenis = doc[meta.jenisField]?.toString().trim().toLowerCase() ?? '';
      if (jenis != 'harian') continue;
      final workflow = doc['workflow_state']?.toString().trim().toLowerCase() ?? '';
      if (workflow.isNotEmpty && workflow != 'draft') continue;
      if (postingDate != null) {
        final docDate = DateTime.tryParse(doc['posting_date']?.toString() ?? '');
        if (docDate != null &&
            DateTime(docDate.year, docDate.month, docDate.day).isAfter(
              DateTime(postingDate.year, postingDate.month, postingDate.day),
            )) {
          continue;
        }
      }
      final lines = claimRowsOf(doc);
      if (lines.isEmpty) continue;
      for (final line in lines) {
        final claim = _claimFromLine(doc, line, meta);
        if (claim != null) claims.add(claim);
      }
    }
    return claims;
  }

  String _frappeDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<List<Map<String, dynamic>>> searchDeliveryNotes({
    required String customer,
    required String company,
    required DateTime deliveryDate,
    String query = '',
  }) async {
    await frappeService.ensureLoggedIn();
    final q = query.trim();
    return frappeService.fetchResource(
      'Delivery Note',
      fields: const ['name', 'customer', 'customer_name', 'posting_date'],
      filters: [
        ['customer', '=', customer.trim()],
        ['company', '=', company.trim()],
        ['posting_date', '=', _frappeDate(deliveryDate)],
        ['docstatus', '=', 1],
        ['is_return', '=', 0],
        if (q.isNotEmpty) ['name', 'like', '%$q%'],
      ],
      orderBy: 'name desc',
      limit: 40,
    );
  }

  Future<List<Map<String, dynamic>>> fetchDeliveryNoteItems(String name) async {
    await frappeService.ensureLoggedIn();
    final doc = await frappeService.fetchDocument('Delivery Note', name.trim());
    final raw = doc['items'];
    if (raw is! List) return const [];
    return [
      for (final row in raw.whereType<Map>())
        if ((row['item_code']?.toString().trim() ?? '').isNotEmpty)
          Map<String, dynamic>.from(row),
    ];
  }

  Future<
      ({
        List<TukarGulingDailyClaim> claims,
        List<TukarGulingRemainder> remainders,
      })> fetchGetFromSources({
    required String customer,
    String? company,
    String? excludeName,
    DateTime? postingDate,
  }) async {
    await frappeService.ensureLoggedIn();
    try {
      final raw = await frappeService.callMethod(
        'tg_get_from_harian_sisa_v1',
        args: {
          'customer': customer.trim(),
          'exclude_final': excludeName?.trim() ?? '',
        },
      );
      final message = raw is Map && raw['message'] is Map
          ? Map<String, dynamic>.from(raw['message'] as Map)
          : (raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{});
      _rememberChildDoctypes(
        sourceDoctype: message['source_child_doctype']?.toString() ?? '',
        balanceDoctype: message['saldo_child_doctype']?.toString() ?? '',
        claimLinkField: message['claim_link_field']?.toString() ?? '',
      );
      final harian = message['harian'];
      final saldo = message['saldo'];
      return (
        claims: [
          for (final row in (harian is List ? harian : const []).whereType<Map>())
            if ((row['item_code']?.toString().trim() ?? '').isNotEmpty)
              TukarGulingDailyClaim(
                sourceName: row['no_tg']?.toString() ?? '',
                claimDate: DateTime.tryParse(row['posting_date']?.toString() ?? '') ??
                    DateTime.now(),
                itemCode: row['item_code'].toString().trim(),
                itemName: row['item_name']?.toString() ?? '',
                qtyKg: double.tryParse(row['qty_kg']?.toString() ?? '') ?? 0,
              ),
        ].where((row) => row.qtyKg > 0 && row.sourceName.isNotEmpty).toList(),
        remainders: [
          for (final row in (saldo is List ? saldo : const []).whereType<Map>())
            if ((row['item_code']?.toString().trim() ?? '').isNotEmpty)
              TukarGulingRemainder(
                sourceFinal: _sourceFinalRef(row),
                itemCode: row['item_code'].toString().trim(),
                itemName: row['item_name']?.toString() ?? '',
                qtyKg: double.tryParse(row['qty_kg']?.toString() ?? '') ?? 0,
                postingDate: row['posting_date']?.toString() ?? '',
              ),
        ].where((row) => row.qtyKg > 0 && row.sourceFinal.isNotEmpty).toList(),
      );
    } catch (_) {
      final claims = await fetchDailyClaims(
        customer: customer,
        company: company,
        excludeName: excludeName,
        postingDate: postingDate,
      );
      final remainders = await fetchAvailableRemainders(
        customer: customer,
        company: company,
        excludeName: excludeName,
      );
      return (claims: claims, remainders: remainders);
    }
  }

  void _rememberChildDoctypes({
    required String sourceDoctype,
    required String balanceDoctype,
    required String claimLinkField,
  }) {
    final current = _metaCache;
    if (current == null) return;
    _metaCache = TukarGulingMeta(
      childTableField: current.childTableField,
      childDoctype: current.childDoctype,
      warehouseField: current.warehouseField,
      jenisField: current.jenisField,
      metodeField: current.metodeField,
      customerNameField: current.customerNameField,
      claimTableField: current.claimTableField,
      claimDoctype: current.claimDoctype,
      claimDateField: current.claimDateField,
      claimItemField: current.claimItemField,
      claimQtyField: current.claimQtyField,
      claimNoteField: current.claimNoteField,
      claimSourceField: claimLinkField.trim().isEmpty
          ? current.claimSourceField
          : claimLinkField.trim(),
      claimAllocatedField: current.claimAllocatedField,
      sourceTableField: current.sourceTableField,
      sourceDoctype: sourceDoctype.trim().isEmpty
          ? current.sourceDoctype
          : sourceDoctype.trim(),
      sourceRefField: current.sourceRefField,
      balanceTableField: current.balanceTableField,
      balanceDoctype: balanceDoctype.trim().isEmpty
          ? current.balanceDoctype
          : balanceDoctype.trim(),
    );
  }

  /// Leftover kg from earlier Final documents. Uses the ERP API when it
  /// exists, otherwise reads saldo rows that have not been taken again.
  Future<List<TukarGulingRemainder>> fetchAvailableRemainders({
    required String customer,
    String? company,
    String? excludeName,
  }) async {
    await frappeService.ensureLoggedIn();
    try {
      final raw = await frappeService.callMethod(
        'tg_sisa_tersedia_v1',
        args: {
          'customer': customer.trim(),
          'exclude_final': excludeName?.trim() ?? '',
        },
      );
      final parsed = _remaindersFromApi(raw);
      if (parsed.isNotEmpty) return parsed;
    } catch (_) {}
    return _remaindersFromDocuments(
      customer: customer,
      company: company,
      excludeName: excludeName,
    );
  }

  String _sourceFinalRef(Map row) {
    final primary = row['tg_final_sumber']?.toString().trim() ?? '';
    if (primary.isNotEmpty) return primary;
    return row['source_final']?.toString().trim() ?? '';
  }

  List<TukarGulingRemainder> _remaindersFromApi(dynamic raw) {
    final message = raw is Map && raw['message'] != null ? raw['message'] : raw;
    final rows = message is List
        ? message
        : (message is Map && message['rows'] is List ? message['rows'] as List : const []);
    return [
      for (final row in rows.whereType<Map>())
        if (_sourceFinalRef(row).isNotEmpty &&
            (row['item_code']?.toString().trim() ?? '').isNotEmpty)
          TukarGulingRemainder(
            sourceFinal: _sourceFinalRef(row),
            itemCode: row['item_code'].toString().trim(),
            itemName: row['item_name']?.toString() ?? '',
            qtyKg: double.tryParse(row['qty_kg']?.toString() ?? '') ?? 0,
            postingDate: row['posting_date']?.toString() ?? '',
          ),
    ].where((row) => row.qtyKg > 0).toList();
  }

  Future<List<TukarGulingRemainder>> _remaindersFromDocuments({
    required String customer,
    String? company,
    String? excludeName,
  }) async {
    final filters = <List<dynamic>>[
      ['customer', '=', customer.trim()],
      ['docstatus', '=', 1],
      if ((company ?? '').trim().isNotEmpty) ['company', '=', company!.trim()],
    ];
    List<Map<String, dynamic>> rows;
    try {
      rows = await frappeService.fetchResource(
        doctype,
        fields: const ['name', 'posting_date', 'workflow_state'],
        filters: filters,
        orderBy: 'posting_date desc',
        limit: 40,
      );
    } catch (_) {
      return const [];
    }
    final docs = <Map<String, dynamic>>[];
    for (final row in rows) {
      final name = row['name']?.toString().trim() ?? '';
      if (name.isEmpty || name == excludeName?.trim()) continue;
      try {
        docs.add(await frappeService.fetchDocument(doctype, name));
      } catch (_) {}
    }
    final used = <String, double>{};
    for (final doc in docs) {
      final sources = doc['custom_sisa_sources'];
      if (sources is! List) continue;
      for (final source in sources.whereType<Map>()) {
        final ref = source['tg_final_sumber'] ?? source['source_final'];
        final key = '$ref|${source['item_code']}';
        final qty = double.tryParse(source['qty_kg']?.toString() ?? '') ?? 0;
        used[key] = (used[key] ?? 0) + qty;
      }
    }
    final available = <TukarGulingRemainder>[];
    for (final doc in docs) {
      final name = doc['name']?.toString().trim() ?? '';
      final jenis = doc['custom_jenis_input']?.toString().trim().toLowerCase() ??
          doc['jenis_input']?.toString().trim().toLowerCase() ??
          '';
      if (jenis != 'final') continue;
      final balances = doc['saldo_sisa_per_sku'];
      if (balances is! List) continue;
      for (final balance in balances.whereType<Map>()) {
        final code = balance['item_code']?.toString().trim() ?? '';
        final qty = double.tryParse(balance['sisa_kg']?.toString() ?? '') ?? 0;
        if (code.isEmpty || qty <= 0) continue;
        final left = qty - (used['$name|$code'] ?? 0);
        if (left <= 0.001) continue;
        available.add(
          TukarGulingRemainder(
            sourceFinal: name,
            itemCode: code,
            itemName: balance['item_name']?.toString() ?? '',
            qtyKg: left,
            postingDate: doc['posting_date']?.toString() ?? '',
          ),
        );
      }
    }
    return available;
  }

  TukarGulingDailyClaim? _claimFromLine(
    Map<String, dynamic> doc,
    Map line,
    TukarGulingMeta meta,
  ) {
    final item = line[meta.claimItemField]?.toString().trim() ??
        line['item_code']?.toString().trim() ??
        line['item']?.toString().trim() ??
        '';
    if (item.isEmpty) return null;
    final qty = double.tryParse(
          (line[meta.claimQtyField] ?? line['qty'] ?? line['qty_kg'])
                  ?.toString()
                  .replaceAll(',', '.') ??
              '',
        ) ??
        0;
    if (qty <= 0) return null;
    final parsed = DateTime.tryParse(
      line[meta.claimDateField]?.toString() ??
          doc['posting_date']?.toString() ??
          '',
    );
    return TukarGulingDailyClaim(
      sourceName: doc['name']?.toString() ?? '',
      claimDate: parsed ?? DateTime.now(),
      itemCode: item,
      itemName: line['item_name']?.toString() ?? '',
      qtyKg: qty,
      keterangan: line[meta.claimNoteField]?.toString() ??
          line['keterangan']?.toString() ??
          '',
    );
  }

  /// Same kg/box as the ERP client script, keyed by Item Group.
  /// Used only when the Item itself has no Box conversion.
  static const boxKgByItemGroup = <String, double>{
    'Cavendish': 13,
    'Ambon Lumut': 13,
    'Lakatan': 13,
    'Barangan Medan': 11,
    'Barangan Curah': 11,
    'Kepok': 11,
  };

  static double? kgPerBoxFromLabel({
    required String itemCode,
    String itemName = '',
    String itemGroup = '',
  }) {
    if (itemCode.trim() == 'SPF-JKT-029') return 13;
    final text = '${itemName.toLowerCase()} ${itemGroup.toLowerCase()}';
    if (text.contains('cavendish') ||
        text.contains('ambon lumut') ||
        text.contains('lakatan')) {
      return 13;
    }
    if (text.contains('barangan') || text.contains('kepok')) return 11;
    for (final entry in boxKgByItemGroup.entries) {
      if (itemGroup.trim().toLowerCase() == entry.key.toLowerCase()) {
        return entry.value;
      }
    }
    return null;
  }

  /// How many kg make one box. Known fruit names follow the ERP script.
  /// Any other item uses the Item's own Box or Kg conversion.
  Future<double?> kgPerBox(String itemCode, {String itemName = ''}) async {
    final known = kgPerBoxFromLabel(itemCode: itemCode, itemName: itemName);
    if (known != null) return known;
    await frappeService.ensureLoggedIn();
    final doc = await frappeService.fetchDocument('Item', itemCode.trim());
    final group = doc['item_group']?.toString().trim() ?? '';
    final named = kgPerBoxFromLabel(
      itemCode: itemCode,
      itemName: doc['item_name']?.toString() ?? itemName,
      itemGroup: group,
    );
    if (named != null) return named;
    final stock = (doc['stock_uom'] ?? '').toString().toLowerCase();
    final weightUom = (doc['weight_uom'] ?? '').toString().toLowerCase();
    final weight = double.tryParse(
      doc['weight_per_unit']?.toString().replaceAll(',', '.') ?? '',
    );
    final rawUoms = doc['uoms'];
    double? factorWhere(bool Function(String uom) match) {
      if (rawUoms is! List) return null;
      for (final row in rawUoms.whereType<Map>()) {
        final uom = (row['uom'] ?? '').toString().toLowerCase();
        if (!match(uom)) continue;
        final factor = double.tryParse(
          row['conversion_factor']?.toString().replaceAll(',', '.') ?? '',
        );
        if (factor != null && factor > 0) return factor;
      }
      return null;
    }

    bool isKg(String uom) => uom == 'kg' || uom.contains('kilogram');
    bool isBox(String uom) => uom == 'box' || uom.contains('box');

    if (weight != null && weight > 0 && isKg(weightUom) && !isKg(stock)) {
      return weight;
    }
    if (isKg(stock)) return factorWhere(isBox);
    if (isBox(stock)) {
      final kgFactor = factorWhere(isKg);
      if (kgFactor != null) {
        return kgFactor >= 1 ? kgFactor : 1 / kgFactor;
      }
    }
    final box = factorWhere(isBox);
    if (box != null && box > 1) return box;
    return boxKgByItemGroup[group];
  }

  Future<List<Map<String, dynamic>>> _fetchListDroppingBlockedFields({
    required List<String> fields,
    required List<List<dynamic>> filters,
  }) async {
    var remaining = [for (final filter in filters) [...filter]];
    while (true) {
      try {
        return await frappeService.fetchResource(
          doctype,
          fields: fields,
          filters: remaining,
          orderBy: 'posting_date asc',
          limit: 100,
        );
      } catch (error) {
        final blocked = RegExp(
          r'Field not permitted in query:\s*([A-Za-z0-9_]+)',
        ).firstMatch(error.toString())?.group(1);
        if (blocked == null) rethrow;
        final next = remaining.where((filter) => filter.first != blocked).toList();
        if (next.length == remaining.length) rethrow;
        remaining = next;
      }
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

  String? preferredWarehouseName(String? company) {
    final selected = (company ?? '').trim();
    final matches = appState.warehouses.where((warehouse) {
      if (warehouse.isGroup || warehouse.isDisabled == true) return false;
      if (selected.isEmpty) return true;
      return warehouse.company.trim() == selected;
    });
    final picked = appState.preferredWarehouse(matches);
    if (picked != null && picked.trim().isNotEmpty) return picked.trim();
    return appState.preferredWarehouse(
      appState.warehouses.where(
        (warehouse) => !warehouse.isGroup && warehouse.isDisabled != true,
      ),
    );
  }

  Future<Map<String, List<Map<String, dynamic>>>> _formFields(
    String parent,
  ) async {
    try {
      final message = await frappeService.callMethod(
        'frappe.desk.form.load.getdoctype',
        args: {'doctype': parent},
      );
      if (message is Map) {
        final docs = message['docs'];
        if (docs is List) {
          final forms = <String, List<Map<String, dynamic>>>{};
          for (final doc in docs.whereType<Map>()) {
            final name = doc['name']?.toString().trim() ?? '';
            final fields = doc['fields'];
            if (name.isEmpty || fields is! List) continue;
            forms[name] = [
              for (final field in fields.whereType<Map>())
                Map<String, dynamic>.from(field),
            ];
          }
          if (forms.containsKey(parent)) return forms;
        }
      }
    } catch (_) {}
    return {parent: await _schemaFields(parent)};
  }

  Future<List<Map<String, dynamic>>> _schemaFields(String parent) async {
    final rows = <Map<String, dynamic>>[];
    try {
      rows.addAll(
        await frappeService.fetchResource(
          'DocField',
          fields: const [
            'fieldname',
            'fieldtype',
            'options',
            'label',
            'parent',
          ],
          filters: [
            ['parent', '=', parent],
          ],
          limit: 200,
        ),
      );
    } catch (_) {}
    try {
      rows.addAll(
        await frappeService.fetchResource(
          'Custom Field',
          fields: const ['fieldname', 'fieldtype', 'options', 'label', 'dt'],
          filters: [
            ['dt', '=', parent],
          ],
          limit: 200,
        ),
      );
    } catch (_) {}
    return rows;
  }

  List<Map<String, dynamic>> claimRowsOf(Map<String, dynamic> doc) {
    return _childRows(doc, claims: true);
  }

  List<Map<String, dynamic>> itemRowsOf(Map<String, dynamic> doc) {
    return _childRows(doc, claims: false);
  }

  List<Map<String, dynamic>> _childRows(
    Map<String, dynamic> doc, {
    required bool claims,
  }) {
    final lists = <String, List<Map<String, dynamic>>>{};
    for (final entry in doc.entries) {
      final value = entry.value;
      if (value is! List || value.isEmpty) continue;
      final rows = [
        for (final raw in value.whereType<Map>())
          Map<String, dynamic>.from(raw),
      ];
      if (rows.isEmpty) continue;
      lists[entry.key.toString()] = rows;
    }
    final meta = _metaCache;
    final preferred = claims
        ? [
            meta?.claimTableField,
            'custom_claim_details',
            'klaim_harian',
          ]
        : [meta?.childTableField, 'tukar_guling_item', 'items'];
    for (final key in preferred) {
      if (key == null || key.isEmpty) continue;
      final rows = lists[key];
      if (rows != null) return rows;
    }
    for (final entry in lists.entries) {
      final key = entry.key.toLowerCase();
      final doctype =
          entry.value.first['doctype']?.toString().toLowerCase() ?? '';
      final isClaim = key.contains('klaim') || doctype.contains('klaim');
      final isItem = !isClaim &&
          (key.contains('item') || doctype.contains('tukar guling item'));
      if (claims && isClaim) return entry.value;
      if (!claims && isItem) return entry.value;
    }
    if (claims) {
      for (final entry in lists.entries) {
        final sample = entry.value.first;
        final keys = sample.keys.map((key) => key.toString().toLowerCase());
        final hasQty = keys.any((key) => key.contains('qty'));
        final hasItem = keys.any((key) => key.contains('item'));
        final isBox = keys.any(
          (key) => key.contains('warehouse') || key == 'uom',
        );
        if (hasQty && hasItem && !isBox) return entry.value;
      }
    }
    return const [];
  }
}
