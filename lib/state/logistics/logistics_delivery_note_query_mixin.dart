import '../../models/delivery_note.dart';
import '../../utils/date_range_presets.dart';
import '../app_state_proxy_notifier.dart';

mixin LogisticsDeliveryNoteQueryMixin on AppStateProxyNotifier {
  static const int documentPageSize = 50;
  static const int pageSize = 500;

  Future<List<DeliveryNote>> fetchDeliveryNotePage({
    required int limitStart,
    String search = '',
    String? status,
  }) async {
    final filters = <List<dynamic>>[
      ..._sellingPeriodFilters('posting_date'),
      ..._companyScopeFilters(appState.sellingCompanyFilter),
      ...?_selectedParentSalesPersonFilter(),
      ...?_statusFilters(status),
      ...?await _salesPersonScopeFilter(),
    ];
    final rows = await _fetchResourceWithFieldFallback(
      doctype: 'Delivery Note',
      fields: const [
        'name',
        'owner',
        'customer',
        'customer_name',
        'status',
        'docstatus',
        'posting_date',
        'base_net_total',
        'net_total',
        'grand_total',
        'total_qty',
      ],
      limit: documentPageSize,
      limitStart: limitStart,
      orderBy: 'posting_date desc, name desc',
      filters: filters,
      orFilters: _searchFilters(search, const [
        'name',
        'customer',
        'customer_name',
      ]),
    );
    return rows.map(DeliveryNote.fromJson).toList();
  }

  Future<DeliveryNote> fetchDeliveryNoteDetail(String id) async {
    await appState.frappeService.ensureLoggedIn();
    final doc = await appState.frappeService.fetchDocument('Delivery Note', id);
    return DeliveryNote.fromJson(doc);
  }

  List<List<dynamic>> _sellingPeriodFilters(String dateField) {
    return [
      [
        dateField,
        '>=',
        DateRangePresets.toFrappeDate(appState.sellingPeriodFrom),
      ],
      [
        dateField,
        '<=',
        DateRangePresets.toFrappeDate(appState.sellingPeriodTo),
      ],
    ];
  }

  List<List<dynamic>> _companyScopeFilters(String selectedCompany) {
    final selected = selectedCompany.trim();
    if (selected.isEmpty) return const [];
    return [
      ['company', '=', selected],
    ];
  }

  List<List<dynamic>>? _selectedParentSalesPersonFilter() {
    if (appState.mobileAccess.shouldScopeSalesData) return null;
    final group = appState.sellingCustomerTypeFilter.trim();
    if (group.isEmpty || group.toLowerCase() == 'all') return null;
    return [
      ['parent_sales_person', '=', group],
    ];
  }

  Future<List<List<dynamic>>?> _salesPersonScopeFilter() async {
    if (!appState.mobileAccess.shouldScopeSalesData) return null;
    final salesPerson = await appState.resolveCurrentSalesIdentity();
    final normalized = salesPerson?.trim() ?? '';
    if (normalized.isEmpty) {
      throw Exception(
        appState.salesIdentityError ??
            'Sales Person user login belum tersedia.',
      );
    }
    return [
      ['Sales Team', 'sales_person', '=', normalized],
    ];
  }

  List<List<dynamic>>? _statusFilters(String? status) {
    if (status == null || status.trim().isEmpty) return null;
    return [
      ['status', '=', status.trim()],
    ];
  }

  List<List<dynamic>>? _searchFilters(String search, List<String> fields) {
    final query = search.trim();
    if (query.isEmpty) return null;
    return fields
        .map<List<dynamic>>((field) => [field, 'like', '%$query%'])
        .toList();
  }

  Future<List<Map<String, dynamic>>> _fetchResourceWithFieldFallback({
    required String doctype,
    required List<String> fields,
    required int limit,
    int limitStart = 0,
    String? orderBy,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
  }) async {
    var remainingFields = List<String>.from(fields);
    var currentOrderBy = orderBy;

    while (remainingFields.isNotEmpty) {
      try {
        if (_usesSalesTeamChildFilter(filters)) {
          return appState.frappeService.fetchReportView(
            doctype,
            fields: remainingFields,
            limit: limit,
            limitStart: limitStart,
            orderBy: currentOrderBy,
            filters: _salesTeamReportViewFilters(filters),
            orFilters: orFilters,
          );
        }
        return await appState.frappeService.fetchResource(
          doctype,
          fields: remainingFields,
          limit: limit,
          limitStart: limitStart,
          orderBy: currentOrderBy,
          filters: filters,
          orFilters: orFilters,
        );
      } catch (error) {
        final text = error.toString();
        final badField = RegExp(
          r'Field not permitted in query:\s*([a-zA-Z0-9_]+)',
        ).firstMatch(text)?.group(1);
        if (badField != null && remainingFields.contains(badField)) {
          remainingFields.remove(badField);
          continue;
        }
        if (currentOrderBy != null &&
            (text.contains('Unknown column') ||
                text.contains('Field not permitted in query'))) {
          currentOrderBy = null;
          continue;
        }
        rethrow;
      }
    }
    return const [];
  }

  bool _usesSalesTeamChildFilter(List<List<dynamic>>? filters) {
    if (filters == null) return false;
    return filters.any((filter) {
      if (filter.isEmpty) return false;
      final first = filter.first.toString().trim();
      if (first == 'parent_sales_person' || first == 'sales_person') {
        return true;
      }
      if (filter.length >= 4 && first == 'Sales Team') {
        final field = filter[1].toString().trim();
        return field == 'parent_sales_person' || field == 'sales_person';
      }
      return false;
    });
  }

  List<List<dynamic>>? _salesTeamReportViewFilters(
    List<List<dynamic>>? filters,
  ) {
    if (filters == null) return null;
    return filters.map((filter) {
      if (filter.length >= 4 &&
          filter.first.toString().trim() == 'Sales Team') {
        return filter;
      }
      if (filter.length >= 3) {
        final field = filter.first.toString().trim();
        if (field == 'parent_sales_person' || field == 'sales_person') {
          return ['Sales Team', field, filter[1], filter[2]];
        }
      }
      return filter;
    }).toList();
  }
}
