import 'dart:async';

import '../../models/erp_summary.dart';
import '../../services/domains/purchasing_summary_service.dart';
import '../../services/local_app_database.dart';
import '../app_state.dart';
import '../app_state_proxy_notifier.dart';
import 'purchasing_filter_state.dart';

class PurchasingSummaryState extends AppStateProxyNotifier {
  PurchasingSummaryState({required super.appState, required this.filterState}) {
    _service = PurchasingSummaryService(frappe: appState.frappeService);
    _syncFromAppState();
    startWatchingAppState();
  }

  static const _cachePrefix = 'buying_trend';
  static const _cacheTtl = Duration(hours: 12);

  PurchasingFilterState filterState;
  late PurchasingSummaryService _service;
  bool _isOrderSummaryLoading = false;
  String? _orderSummaryError;
  DocumentSummary _purchaseOrderSummary = const DocumentSummary();
  DocumentSummary _purchaseReceiptSummary = const DocumentSummary();
  DocumentSummary _purchaseInvoiceSummary = const DocumentSummary();
  List<DocumentTrendPoint> _purchaseOrderTrendPoints = const [];
  List<DocumentTrendPoint> _purchaseReceiptTrendPoints = const [];
  List<DocumentTrendPoint> _purchaseInvoiceTrendPoints = const [];
  List<DocumentTrendPoint> _materialRequestTrendPoints = const [];
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
  ];

  bool get isOrderSummaryLoading => _isOrderSummaryLoading;
  String? get orderSummaryError => _orderSummaryError;
  int get buyingPeriodYear => filterState.buyingPeriodYear;
  int get buyingPeriodMonth => filterState.buyingPeriodMonth;
  DocumentSummary get purchaseOrderSummary => _purchaseOrderSummary;
  DocumentSummary get purchaseReceiptSummary => _purchaseReceiptSummary;
  DocumentSummary get purchaseInvoiceSummary => _purchaseInvoiceSummary;
  List<DocumentTrendPoint> get purchaseOrderTrendPoints =>
      _purchaseOrderTrendPoints;
  List<DocumentTrendPoint> get purchaseReceiptTrendPoints =>
      _purchaseReceiptTrendPoints;
  List<DocumentTrendPoint> get purchaseInvoiceTrendPoints =>
      _purchaseInvoiceTrendPoints;
  List<DocumentTrendPoint> get materialRequestTrendPoints =>
      _materialRequestTrendPoints;

  @override
  void updateAppState(AppState value) {
    final previousFrappe = appState.frappeService;
    super.updateAppState(value);
    if (!identical(previousFrappe, appState.frappeService)) {
      _service = PurchasingSummaryService(frappe: appState.frappeService);
    }
  }

  void updateFilterState(PurchasingFilterState value) {
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
    }
  }

  void _resetLocalSummary() {
    _isOrderSummaryLoading = false;
    _orderSummaryError = null;
    _purchaseOrderSummary = const DocumentSummary();
    _purchaseReceiptSummary = const DocumentSummary();
    _purchaseInvoiceSummary = const DocumentSummary();
    _purchaseOrderTrendPoints = const [];
    _purchaseReceiptTrendPoints = const [];
    _purchaseInvoiceTrendPoints = const [];
    _materialRequestTrendPoints = const [];
    _loadedCacheKeys.clear();
    _loadingTypes.clear();
    _inFlight.clear();
    _sectionTokens.clear();
  }

  Future<void> refreshBuyingSummaries({
    bool forceRemote = false,
    String documentType = 'Purchase Order',
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

    final job = _refreshBuyingSummaries(
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

  Future<void> _refreshBuyingSummaries({
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

    final selectedCompany = filterState.buyingCompanyFilter.trim();
    final effectiveCompany = selectedCompany.isNotEmpty
        ? selectedCompany
        : (appState.preferredCompany(filterState.buyingCompanies) ?? '');

    _loadingTypes.add(documentType);
    _isOrderSummaryLoading = true;
    _orderSummaryError = null;
    notifyListeners();
    try {
      final section = await _service.fetchSection(
        documentType: documentType,
        year: filterState.buyingPeriodYear,
        month: filterState.buyingPeriodMonth,
        from: filterState.buyingPeriodFrom,
        to: filterState.buyingPeriodTo,
        company: effectiveCompany,
        supplierType: filterState.buyingSupplierTypeFilter,
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
      case 'Purchase Receipt':
      case 'Purchase Invoice':
      case 'Material Request':
        return documentType.trim();
      default:
        return 'Purchase Order';
    }
  }

  void _applySection(String documentType, PurchasingAnalyticsSection section) {
    switch (documentType) {
      case 'Purchase Receipt':
        _purchaseReceiptSummary = section.summary;
        _purchaseReceiptTrendPoints = section.trend;
        return;
      case 'Purchase Invoice':
        _purchaseInvoiceSummary = section.summary;
        _purchaseInvoiceTrendPoints = section.trend;
        return;
      case 'Material Request':
        _materialRequestTrendPoints = section.trend;
        return;
      default:
        _purchaseOrderSummary = section.summary;
        _purchaseOrderTrendPoints = section.trend;
    }
  }

  String _sectionCacheKey(String documentType) {
    final site = appState.frappeService.baseUrl.trim();
    final user =
        appState.currentUser?.trim() ??
        appState.frappeService.username?.trim() ??
        '';
    final selectedCompany = filterState.buyingCompanyFilter.trim();
    final company = selectedCompany.isNotEmpty
        ? selectedCompany
        : (appState.preferredCompany(filterState.buyingCompanies) ?? '');
    return [
      _cachePrefix,
      'section',
      site,
      user,
      filterState.buyingPeriodYear,
      filterState.buyingPeriodMonth,
      company,
      filterState.buyingSupplierTypeFilter.trim(),
      documentType,
    ].join('|');
  }

  Future<PurchasingAnalyticsSection?> _readCachedSection(
    String cacheKey,
  ) async {
    final json = await LocalAppDatabase.instance.readJson(cacheKey);
    if (json == null) return null;
    try {
      return PurchasingAnalyticsSection.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCachedSection(
    String cacheKey,
    PurchasingAnalyticsSection section,
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
    _purchaseOrderSummary = appState.purchaseOrderSummary;
    _purchaseReceiptSummary = appState.purchaseReceiptSummary;
    _purchaseInvoiceSummary = appState.purchaseInvoiceSummary;
    _purchaseOrderTrendPoints = appState.purchaseOrderTrendPoints;
    _purchaseReceiptTrendPoints = appState.purchaseReceiptTrendPoints;
    _purchaseInvoiceTrendPoints = appState.purchaseInvoiceTrendPoints;
    _materialRequestTrendPoints = appState.materialRequestTrendPoints;
  }
}
