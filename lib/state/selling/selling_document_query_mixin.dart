import '../../utils/date_range_presets.dart';
import '../../utils/frappe_page_walker.dart';
import '../app_state_proxy_notifier.dart';
import 'selling_filter_state.dart';

mixin SellingDocumentQueryMixin on AppStateProxyNotifier {
  static const int documentPageSize = 50;
  static const int pageSize = 500;

  SellingFilterState get sellingFilterState;

  List<List<dynamic>> sellingPeriodFilters(String dateField) {
    final filters = <List<dynamic>>[
      [
        dateField,
        '>=',
        DateRangePresets.toFrappeDate(sellingFilterState.sellingPeriodFrom),
      ],
      [
        dateField,
        '<=',
        DateRangePresets.toFrappeDate(sellingFilterState.sellingPeriodTo),
      ],
    ];
    final company = sellingFilterState.sellingCompanyFilter.trim();
    if (company.isNotEmpty) {
      filters.add(['company', '=', company]);
    }
    return filters;
  }

  List<List<dynamic>>? statusFilters(String? status) {
    if (status == null || status.trim().isEmpty) return null;
    return [
      ['status', '=', status.trim()],
    ];
  }

  List<List<dynamic>>? searchFilters(String search, List<String> fields) {
    final query = search.trim();
    if (query.isEmpty) return null;
    return fields
        .map<List<dynamic>>((field) => [field, 'like', '%$query%'])
        .toList();
  }

  Future<List<List<dynamic>>?> salesDocumentScopeFilters() async {
    if (!appState.mobileAccess.shouldScopeSalesData) return const [];
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

  Future<List<Map<String, dynamic>>> fetchAllResourcePages({
    required String doctype,
    required List<String> fields,
    String? orderBy,
    List<List<dynamic>>? filters,
    int? maxRows,
  }) {
    return walkFrappePages(
      pageSize: pageSize,
      maxRows: maxRows,
      fetchPage: (start, limit) => fetchResourceWithFieldFallback(
        doctype: doctype,
        fields: fields,
        limit: limit,
        limitStart: start,
        orderBy: orderBy,
        filters: filters,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> fetchResourceWithFieldFallback({
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
        if (usesSalesTeamChildFilter(filters)) {
          return appState.frappeService.fetchReportView(
            doctype,
            fields: remainingFields,
            limit: limit,
            limitStart: limitStart,
            orderBy: currentOrderBy,
            filters: filters,
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

  bool usesSalesTeamChildFilter(List<List<dynamic>>? filters) {
    if (filters == null) return false;
    return filters.any((filter) {
      if (filter.length < 4) return false;
      if (filter.first.toString().trim() != 'Sales Team') return false;
      final field = filter[1].toString().trim();
      return field == 'parent_sales_person' || field == 'sales_person';
    });
  }
}
