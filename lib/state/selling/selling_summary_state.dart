import 'dart:async';

import '../../models/erp_summary.dart';
import '../../services/domains/selling_summary_service.dart';
import '../../services/local_app_database.dart';
import '../app_state.dart';
import '../app_state_proxy_notifier.dart';
import 'selling_filter_state.dart';

class SellingSummaryState extends AppStateProxyNotifier {
  SellingSummaryState({required super.appState, required this.filterState}) {
    _service = SellingSummaryService(frappe: appState.frappeService);
    _syncFromAppState();
    startWatchingAppState();
  }

  static const _cachePrefix = 'selling_trend';
  static const _cacheTtl = Duration(hours: 12);

  SellingFilterState filterState;
  late SellingSummaryService _service;
  bool _isOrderSummaryLoading = false;
  String? _orderSummaryError;
  DocumentSummary _salesOrderSummary = const DocumentSummary();
  DocumentSummary _deliveryNoteSummary = const DocumentSummary();
  DocumentSummary _salesInvoiceSummary = const DocumentSummary();
  List<DocumentTrendPoint> _salesOrderTrendPoints = const [];
  List<DocumentTrendPoint> _deliveryNoteTrendPoints = const [];
  List<DocumentTrendPoint> _salesInvoiceTrendPoints = const [];
  final Map<String, int> _sectionTokens = {};
  final Set<String> _loadedCacheKeys = {};
  final Set<String> _loadingTypes = {};
  final Map<String, Future<void>> _inFlight = {};

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.selectedSiteBaseUrl,
    appState.currentUser,
    appState.mobileAccess.shouldScopeSalesData,
    appState.currentSalesPerson,
    appState.salesIdentityError,
  ];

  bool get isOrderSummaryLoading => _isOrderSummaryLoading;
  String? get orderSummaryError => _orderSummaryError;
  int get sellingPeriodYear => filterState.sellingPeriodYear;
  int get sellingPeriodMonth => filterState.sellingPeriodMonth;
  DocumentSummary get salesOrderSummary => _salesOrderSummary;
  DocumentSummary get deliveryNoteSummary => _deliveryNoteSummary;
  DocumentSummary get salesInvoiceSummary => _salesInvoiceSummary;
  List<DocumentTrendPoint> get salesOrderTrendPoints => _salesOrderTrendPoints;
  List<DocumentTrendPoint> get deliveryNoteTrendPoints =>
      _deliveryNoteTrendPoints;
  List<DocumentTrendPoint> get salesInvoiceTrendPoints =>
      _salesInvoiceTrendPoints;

  @override
  void updateAppState(AppState value) {
    final previousFrappe = appState.frappeService;
    super.updateAppState(value);
    if (!identical(previousFrappe, appState.frappeService)) {
      _service = SellingSummaryService(frappe: appState.frappeService);
    }
  }

  void updateFilterState(SellingFilterState value) {
    filterState = value;
  }

  @override
  void handleWatchedFieldsChanged(List<Object?> previous, List<Object?> next) {
    if (didAuthScopeChange(
      previous,
      next,
      authIndex: 0,
      siteIndex: 2,
      userIndex: 3,
    )) {
      _resetLocalSummary();
      return;
    }

    final salesScopeChanged =
        previous.length > 5 &&
        next.length > 5 &&
        (previous[4] != next[4] ||
            previous[5] != next[5] ||
            previous[6] != next[6]);
    if (next[0] == true && salesScopeChanged) {
      unawaited(refreshSellingSummaries(forceRemote: true));
    }
  }

  void _resetLocalSummary() {
    _isOrderSummaryLoading = false;
    _orderSummaryError = null;
    _salesOrderSummary = const DocumentSummary();
    _deliveryNoteSummary = const DocumentSummary();
    _salesInvoiceSummary = const DocumentSummary();
    _salesOrderTrendPoints = const [];
    _deliveryNoteTrendPoints = const [];
    _salesInvoiceTrendPoints = const [];
    _loadedCacheKeys.clear();
    _loadingTypes.clear();
    _inFlight.clear();
    _sectionTokens.clear();
  }

  Future<void> refreshSellingSummaries({
    bool forceRemote = false,
    String documentType = 'Sales Order',
  }) async {
    if (appState.isSampleMode) {
      _syncFromAppState();
      notifyListeners();
      return;
    }

    final type = _normalizeDocumentType(documentType);
    final cacheKey = _sectionCacheKey(type);
    final flightKey = '$cacheKey|${forceRemote ? 1 : 0}';
    final running = _inFlight[flightKey];
    if (running != null) return running;

    final job = _refreshSellingSummaries(
      forceRemote: forceRemote,
      documentType: type,
      cacheKey: cacheKey,
    );
    _inFlight[flightKey] = job;
    try {
      await job;
    } finally {
      if (identical(_inFlight[flightKey], job)) {
        _inFlight.remove(flightKey);
      }
    }
  }

  Future<void> _refreshSellingSummaries({
    required bool forceRemote,
    required String documentType,
    required String cacheKey,
  }) async {
    final token = (_sectionTokens[documentType] ?? 0) + 1;
    _sectionTokens[documentType] = token;
    if (!forceRemote) {
      if (_loadedCacheKeys.contains(cacheKey)) return;
      final cached = await _readCachedSection(cacheKey);
      if (_sectionTokens[documentType] != token) return;
      if (cached != null) {
        _applySection(documentType, cached);
        _loadedCacheKeys.add(cacheKey);
        _orderSummaryError = null;
        notifyListeners();
        return;
      }
    }

    final selectedCompany = filterState.sellingCompanyFilter.trim();
    final effectiveCompany = selectedCompany.isNotEmpty
        ? selectedCompany
        : (appState.preferredCompany(filterState.sellingCompanies) ?? '');

    _loadingTypes.add(documentType);
    _isOrderSummaryLoading = true;
    _orderSummaryError = null;
    notifyListeners();
    try {
      final section = await _service.fetchSection(
        documentType: documentType,
        year: filterState.sellingPeriodYear,
        month: filterState.sellingPeriodMonth,
        from: filterState.sellingPeriodFrom,
        to: filterState.sellingPeriodTo,
        company: effectiveCompany,
        customerType: filterState.sellingCustomerTypeFilter,
        shouldScopeSalesData: appState.mobileAccess.shouldScopeSalesData,
        resolveCurrentSalesIdentity: appState.resolveCurrentSalesIdentity,
        salesIdentityError: appState.salesIdentityError,
      );
      if (_sectionTokens[documentType] != token) return;
      _applySection(documentType, section);
      _loadedCacheKeys.add(cacheKey);
      await _writeCachedSection(cacheKey, section);
    } catch (error) {
      if (_sectionTokens[documentType] != token) return;
      _orderSummaryError = error.toString();
    } finally {
      if (_sectionTokens[documentType] == token) {
        _loadingTypes.remove(documentType);
        _isOrderSummaryLoading = _loadingTypes.isNotEmpty;
        notifyListeners();
      }
    }
  }

  String _normalizeDocumentType(String documentType) {
    switch (documentType.trim()) {
      case 'Delivery Note':
      case 'Sales Invoice':
        return documentType.trim();
      default:
        return 'Sales Order';
    }
  }

  void _applySection(String documentType, SellingAnalyticsSection section) {
    if (documentType == 'Delivery Note') {
      _deliveryNoteSummary = section.summary;
      _deliveryNoteTrendPoints = section.trend;
      return;
    }
    if (documentType == 'Sales Invoice') {
      _salesInvoiceSummary = section.summary;
      _salesInvoiceTrendPoints = section.trend;
      return;
    }
    _salesOrderSummary = section.summary;
    _salesOrderTrendPoints = section.trend;
  }

  String _sectionCacheKey(String documentType) {
    final site = appState.frappeService.baseUrl.trim();
    final user =
        appState.currentUser?.trim() ??
        appState.frappeService.username?.trim() ??
        '';
    final selectedCompany = filterState.sellingCompanyFilter.trim();
    final company = selectedCompany.isNotEmpty
        ? selectedCompany
        : (appState.preferredCompany(filterState.sellingCompanies) ?? '');
    final salesScope = appState.mobileAccess.shouldScopeSalesData
        ? (appState.currentSalesPerson?.trim() ?? '')
        : filterState.sellingCustomerTypeFilter.trim();
    return [
      _cachePrefix,
      'section',
      site,
      user,
      filterState.sellingPeriodYear,
      filterState.sellingPeriodMonth,
      company,
      salesScope,
      documentType,
    ].join('|');
  }

  Future<SellingAnalyticsSection?> _readCachedSection(String cacheKey) async {
    final json = await LocalAppDatabase.instance.readJson(cacheKey);
    if (json == null) return null;
    try {
      return SellingAnalyticsSection.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedSection(
    String cacheKey,
    SellingAnalyticsSection section,
  ) async {
    await LocalAppDatabase.instance.writeJson(
      cacheKey,
      section.toJson(),
      ttl: _cacheTtl,
    );
  }

  void _syncFromAppState() {
    _isOrderSummaryLoading = appState.isOrderSummaryLoading;
    _orderSummaryError = appState.orderSummaryError;
    _salesOrderSummary = appState.salesOrderSummary;
    _deliveryNoteSummary = appState.deliveryNoteSummary;
    _salesInvoiceSummary = appState.salesInvoiceSummary;
    _salesOrderTrendPoints = appState.salesOrderTrendPoints;
    _deliveryNoteTrendPoints = appState.deliveryNoteTrendPoints;
    _salesInvoiceTrendPoints = appState.salesInvoiceTrendPoints;
  }
}
