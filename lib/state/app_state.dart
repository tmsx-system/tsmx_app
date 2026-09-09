import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/sales_order.dart';
import '../models/sales_order_approval.dart';
import '../models/purchase_order.dart';
import '../models/delivery_note.dart';
import '../models/delivery_activity_log.dart';
import '../models/erp_approval_todo.dart';
import '../models/sales_invoice.dart';
import '../models/purchase_receipt.dart';
import '../models/purchase_invoice.dart';
import '../models/material_request.dart';
import '../models/mobile_boot.dart';
import '../models/quality_inspection_record.dart';
import '../models/supplier_price_comparison.dart';
import '../models/stock_entry.dart';
import '../models/stock_ledger_movement.dart';
import '../models/inventory_item.dart';
import '../models/inactive_customer.dart';
import '../models/noo_request.dart';
import '../models/promo_request.dart';
import '../utils/date_range_presets.dart';
import '../models/warehouse_info.dart';
import '../models/warehouse_tracking_record.dart';
import '../models/stock_area_option.dart';
import '../models/erp_summary.dart';
import '../models/sales_order_insight.dart';
import '../models/sales_workspace.dart';
import '../models/spg_workspace.dart';
import '../services/domains/auth_service.dart';
import '../services/domains/customer_service.dart';
import '../services/domains/purchase_invoice_service.dart';
import '../services/domains/purchase_order_service.dart';
import '../services/domains/sales_invoice_service.dart';
import '../services/domains/sales_order_service.dart';
import '../services/erp_services.dart';
import '../services/frappe_service.dart';
import '../services/local_app_database.dart';
import '../services/mobile_site_registry_service.dart';
import '../services/native_notification_service.dart';
import '../services/sales_visit_location_service.dart';
import '../utils/erp_doc_utils.dart';
import '../utils/num_parse.dart';
import '../utils/frappe_page_walker.dart';
import '../config/mobile_role_registry.dart';
import '../utils/mobile_access.dart';

class _ResolvedFrappeSite {
  final String code;
  final String name;
  final String baseUrl;

  const _ResolvedFrappeSite({
    required this.code,
    required this.name,
    required this.baseUrl,
  });
}

class _CachedDocument {
  final DateTime storedAt;
  final Map<String, dynamic> document;

  const _CachedDocument({required this.storedAt, required this.document});

  bool get isFresh =>
      DateTime.now().difference(storedAt) < AppState._documentCacheTtl;
}

class AppState with ChangeNotifier {
  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;
  bool _isSampleMode = false;
  bool get isSampleMode => _isSampleMode;

  String? _currentUser;
  String? get currentUser => _currentUser;
  String? _currentEmployee;
  String? get currentEmployee => _currentEmployee;
  Map<String, dynamic> _currentEmployeeProfile = const {};
  Map<String, dynamic> get currentEmployeeProfile => _currentEmployeeProfile;
  String? _currentSalesPerson;
  String? get currentSalesPerson => _currentSalesPerson;
  String? _salesIdentityUser;
  Future<String?>? _salesIdentityRequest;
  String? _salesIdentityError;
  String? get salesIdentityError => _salesIdentityError;

  bool _rememberDevice = true;
  bool get rememberDevice => _rememberDevice;

  bool _isInitializing = true;
  bool get isInitializing => _isInitializing;
  String? _lastAuthError;
  String? get lastAuthError => _lastAuthError;
  String? _mobileCompatibilityWarning;
  String? get mobileCompatibilityWarning => _mobileCompatibilityWarning;
  MobileBoot? _mobileBoot;
  MobileBoot? get mobileBoot => _mobileBoot;
  String get appDisplayName => _mobileBoot?.appName.trim().isNotEmpty == true
      ? _mobileBoot!.appName.trim()
      : MobileRoleRegistry.defaultAppName;
  String _selectedSiteName = '';
  String get selectedSiteName => _selectedSiteName;
  String _selectedSiteCode = '';
  String get selectedSiteCode => _selectedSiteCode;
  String get selectedSiteBaseUrl => _frappeService.baseUrl;
  bool get hasSelectedSite => _frappeService.baseUrl.trim().isNotEmpty;

  String _userRole = 'Unassigned';
  String get userRole => _userRole;
  MobileAccess get mobileAccess =>
      MobileAccess(role: _userRole, boot: _mobileBoot);
  bool get isSalesUserRole => mobileAccess.isSalesUser;
  bool get isSpgRole => mobileAccess.isSpg;
  bool get isSalesManagerRole => mobileAccess.isSalesManager;
  bool get isSalesAreaRole => mobileAccess.isSalesArea;
  bool get isPurchaseUserRole => mobileAccess.isPurchaseUser;
  bool get isPurchaseManagerRole => mobileAccess.isPurchaseManager;
  bool get isPurchaseAreaRole => mobileAccess.isPurchaseArea;
  bool get _shouldScopeSalesData => mobileAccess.shouldScopeSalesData;
  bool get hasMobileBoot => _mobileBoot != null;
  bool hasMobileModule(String module) =>
      mobileAccess.enabledModules.contains(module.trim().toLowerCase());
  bool canUseMobileModule(String module) => mobileAccess.canUse(module);
  bool get canUseDashboard => mobileAccess.canUse(MobileModule.dashboard);
  bool get canUseSales => mobileAccess.canUse(MobileModule.sales);
  bool get canUseSpg => mobileAccess.canUse(MobileModule.spg);
  bool get canUsePurchase => mobileAccess.canUse(MobileModule.purchase);
  bool get canUseStock => mobileAccess.canUse(MobileModule.stock);
  bool get canUseWarehouse => mobileAccess.canUse(MobileModule.warehouse);
  bool get canUseLogistics => mobileAccess.canUse(MobileModule.logistics);
  bool get canUseApprovals => mobileAccess.canUse(MobileModule.approvals);
  bool get canUseQualityControl =>
      mobileAccess.canUse(MobileModule.qualityControl);
  bool get canUseFinance => mobileAccess.canUse(MobileModule.finance);
  bool get canUseAccounting => mobileAccess.canUse(MobileModule.accounting);
  bool get canUsePlantation => mobileAccess.canUse(MobileModule.plantation);

  Future<bool> canReadDoctype(String doctype) =>
      _hasDoctypePermission(doctype, 'read');

  Future<bool> canCreateDoctype(String doctype) =>
      _hasDoctypePermission(doctype, 'create');

  Future<bool> canWriteDoctype(String doctype) =>
      _hasDoctypePermission(doctype, 'write');

  Future<bool> canSubmitDoctype(String doctype) =>
      _hasDoctypePermission(doctype, 'submit');

  Future<bool> _hasDoctypePermission(String doctype, String permType) async {
    final normalizedDoctype = doctype.trim();
    final normalizedPermType = permType.trim().toLowerCase();
    if (normalizedDoctype.isEmpty || !_isAuthenticated) return false;
    if (normalizedPermType.isEmpty) return false;
    if (MobileRoleRegistry.isFullAccessRole(_userRole)) return true;

    final site = _frappeService.baseUrl.trim();
    final user = _currentUser?.trim() ?? _frappeService.username?.trim() ?? '';
    final cacheKey = '$site::$user::$normalizedDoctype::$normalizedPermType';
    final cached = _doctypeSubmitPermissionCache[cacheKey];
    if (cached != null) return cached;

    try {
      final result = await _frappeService.callMethod(
        'frappe.client.has_permission',
        args: {'doctype': normalizedDoctype, 'perm_type': normalizedPermType},
      );
      final allowed = _permissionResultToBool(result);
      _doctypeSubmitPermissionCache[cacheKey] = allowed;
      return allowed;
    } catch (_) {
      _doctypeSubmitPermissionCache[cacheKey] = false;
      return false;
    }
  }

  bool _permissionResultToBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is Map) {
      if (value.containsKey('message')) {
        return _permissionResultToBool(value['message']);
      }
      if (value.containsKey('has_permission')) {
        return _permissionResultToBool(value['has_permission']);
      }
      if (value.containsKey('allowed')) {
        return _permissionResultToBool(value['allowed']);
      }
    }
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == '1' || text == 'true' || text == 'yes' || text == 'allowed';
  }

  static const purchaseApprovalDoctypes = {
    'Purchase Order',
    'Purchase Invoice',
    'Material Request',
  };

  static const financeApprovalDoctypes = {'Journal Entry'};

  static const String _prefsUserRoleKey = 'user_role';
  int _runtimeGeneration = 0;

  Future<void> refreshDataForCurrentRole() async {
    if (!_isAuthenticated) return;
    if (isSalesUserRole) {
      await resolveCurrentSalesIdentity();
      await Future.wait([
        fetchWarehousesFromFrappe(),
        fetchInventoryFromFrappe(
          filters: _inventoryScopeFiltersForCurrentRole(),
        ),
      ]);
      return;
    }
    await prefetchInitialData();
  }

  Future<void> syncCurrentUserRoleFromFrappe() async {
    final currentUser = _currentUser?.trim() ?? '';
    if (currentUser.isEmpty) {
      throw Exception('User login Frappe tidak tersedia.');
    }
    final boot = await fetchMobileBoot();
    final bootRole = _roleProfileFromMobileBoot(boot);
    if (bootRole.isNotEmpty && bootRole != MobileRole.unassigned) {
      await _applyCurrentRole(bootRole);
      return;
    }
    final access = await _authService.fetchCurrentUserAccess(currentUser);
    await _applyCurrentRole(access.roleProfile);
  }

  Future<void> _applyCurrentRole(String roleProfile) async {
    _userRole = _normalizeRoleProfile(roleProfile);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefsUserRoleKey, _userRole);
    notifyListeners();
  }

  String _normalizeRoleProfile(String roleProfile) {
    return MobileRoleRegistry.normalizeRoleProfile(roleProfile);
  }

  String _roleProfileFromMobileBoot(MobileBoot? boot) {
    if (boot == null) return '';
    final directRole = _cleanRoleValue(boot.roleProfile);
    if (directRole.isNotEmpty) return directRole;

    final roles = boot.roles.map((role) => role.toLowerCase()).toSet();
    return _roleProfileFromRoleNames(roles);
  }

  String _roleProfileFromRoleNames(Set<String> roles) {
    return MobileRoleRegistry.fromFrappeRoles(roles);
  }

  String _cleanRoleValue(Object? value) {
    final cleaned = value?.toString().trim() ?? '';
    final lower = cleaned.toLowerCase();
    if (lower == 'null' || lower == 'none' || lower == 'undefined') return '';
    return cleaned;
  }

  Future<String?> resolveCurrentSalesIdentity() async {
    final user = _currentUser?.trim() ?? '';
    if (user.isEmpty) {
      _currentEmployee = null;
      _currentEmployeeProfile = const {};
      _currentSalesPerson = null;
      _salesIdentityUser = null;
      _salesIdentityRequest = null;
      _salesIdentityError = 'User login ERPNext tidak tersedia.';
      notifyListeners();
      return null;
    }

    final hasResolvedValue =
        _currentSalesPerson?.trim().isNotEmpty == true ||
        _salesIdentityError?.trim().isNotEmpty == true;
    if (_salesIdentityUser == user && hasResolvedValue) {
      return _currentSalesPerson;
    }

    final existingRequest = _salesIdentityRequest;
    if (_salesIdentityUser == user && existingRequest != null) {
      return existingRequest;
    }

    _salesIdentityUser = user;
    final request = _resolveCurrentSalesIdentityForUser(user);
    _salesIdentityRequest = request;
    try {
      return await request;
    } finally {
      if (_salesIdentityRequest == request) {
        _salesIdentityRequest = null;
      }
    }
  }

  Future<String?> _resolveCurrentSalesIdentityForUser(String user) async {
    _currentEmployee = null;
    _currentEmployeeProfile = const {};
    _currentSalesPerson = null;
    _salesIdentityError = null;
    try {
      final identity = await _authService.resolveSalesIdentity(user);
      _currentEmployee = identity.employee;
      _currentEmployeeProfile = identity.employeeProfile;
      _currentSalesPerson = identity.salesPerson;
    } catch (error) {
      _salesIdentityError = error.toString();
    }
    notifyListeners();
    return _currentSalesPerson;
  }

  Future<Map<String, dynamic>> _ensureCurrentEmployee() async {
    final existing = _currentEmployee?.trim() ?? '';
    if (existing.isNotEmpty) return _currentEmployeeProfile;

    final user = _currentUser?.trim() ?? '';
    if (user.isEmpty) {
      throw Exception('User login belum tersedia.');
    }

    List<Map<String, dynamic>> rows;
    try {
      try {
        rows = await _frappeService.fetchResource(
          'Employee',
          fields: const [
            'name',
            'employee_name',
            'user_id',
            'status',
            'company',
            'designation',
            'department',
            'branch',
          ],
          filters: [
            ['user_id', '=', user],
          ],
          limit: 1,
        );
      } catch (_) {
        rows = await _frappeService.fetchResource(
          'Employee',
          fields: const ['name', 'employee_name', 'user_id'],
          filters: [
            ['user_id', '=', user],
          ],
          limit: 1,
        );
      }
    } catch (error) {
      throw Exception(
        'Role tidak memiliki izin membaca Employee.user_id. Detail: $error',
      );
    }

    if (rows.isEmpty) {
      throw Exception(
        'User $user belum terhubung ke Employee melalui field User ID.',
      );
    }

    _currentEmployeeProfile = Map<String, dynamic>.from(rows.first);
    _currentEmployee = _currentEmployeeProfile['name']?.toString() ?? '';
    notifyListeners();
    return _currentEmployeeProfile;
  }

  List<SalesOrder> _salesOrders = [];
  List<PurchaseOrder> _purchaseOrders = [];
  List<DeliveryNote> _deliveryNotes = [];
  List<SalesInvoice> _salesInvoices = [];
  List<PurchaseReceipt> _purchaseReceipts = [];
  List<PurchaseInvoice> _purchaseInvoices = [];
  List<MaterialRequest> _materialRequests = [];
  List<StockEntry> _stockEntries = [];
  List<StockReconciliationSummary> _stockReconciliations = [];
  List<InventoryItem> _inventory = [];
  List<String> _itemGroups = [];
  DocumentSummary _salesOrderSummary = const DocumentSummary();
  DocumentSummary _deliveryNoteSummary = const DocumentSummary();
  DocumentSummary _salesInvoiceSummary = const DocumentSummary();
  DocumentSummary _purchaseOrderSummary = const DocumentSummary();
  DocumentSummary _purchaseReceiptSummary = const DocumentSummary();
  DocumentSummary _purchaseInvoiceSummary = const DocumentSummary();
  DashboardSummary _dashboardSummary = const DashboardSummary();
  List<DocumentTrendPoint> _salesOrderTrendPoints = const [];
  List<DocumentTrendPoint> _deliveryNoteTrendPoints = const [];
  List<DocumentTrendPoint> _salesInvoiceTrendPoints = const [];
  List<DocumentTrendPoint> _purchaseOrderTrendPoints = const [];
  List<DocumentTrendPoint> _purchaseReceiptTrendPoints = const [];
  List<DocumentTrendPoint> _purchaseInvoiceTrendPoints = const [];
  List<DocumentTrendPoint> _materialRequestTrendPoints = const [];

  DocumentSummary get salesOrderSummary => _salesOrderSummary;
  DocumentSummary get deliveryNoteSummary => _deliveryNoteSummary;
  DocumentSummary get salesInvoiceSummary => _salesInvoiceSummary;
  DocumentSummary get purchaseOrderSummary => _purchaseOrderSummary;
  DocumentSummary get purchaseReceiptSummary => _purchaseReceiptSummary;
  DocumentSummary get purchaseInvoiceSummary => _purchaseInvoiceSummary;
  DashboardSummary get dashboardSummary => _dashboardSummary;
  List<DocumentTrendPoint> get salesOrderTrendPoints => _salesOrderTrendPoints;
  List<DocumentTrendPoint> get deliveryNoteTrendPoints =>
      _deliveryNoteTrendPoints;
  List<DocumentTrendPoint> get salesInvoiceTrendPoints =>
      _salesInvoiceTrendPoints;
  List<DocumentTrendPoint> get purchaseOrderTrendPoints =>
      _purchaseOrderTrendPoints;
  List<DocumentTrendPoint> get purchaseReceiptTrendPoints =>
      _purchaseReceiptTrendPoints;
  List<DocumentTrendPoint> get purchaseInvoiceTrendPoints =>
      _purchaseInvoiceTrendPoints;
  List<DocumentTrendPoint> get materialRequestTrendPoints =>
      _materialRequestTrendPoints;

  List<SalesOrder> get salesOrders => _salesOrders;
  List<PurchaseOrder> get purchaseOrders => _purchaseOrders;
  List<DeliveryNote> get deliveryNotes => _deliveryNotes;
  List<SalesInvoice> get salesInvoices => _salesInvoices;
  List<PurchaseReceipt> get purchaseReceipts => _purchaseReceipts;
  List<PurchaseInvoice> get purchaseInvoices => _purchaseInvoices;
  List<MaterialRequest> get materialRequests => _materialRequests;
  List<StockEntry> get stockEntries => _stockEntries;
  List<StockReconciliationSummary> get stockReconciliations =>
      _stockReconciliations;
  List<InventoryItem> get inventory => _inventory;
  List<String> get itemGroups => List.unmodifiable(_itemGroups);
  List<SalesOrder> get dashboardSalesOrders => _salesOrders;
  List<PurchaseOrder> get dashboardPurchaseOrders => _purchaseOrders;

  List<WarehouseInfo> _warehouses = [];
  List<WarehouseInfo> get warehouses => _warehouses;

  int _salesOrderApprovalTodoCount = 0;
  int get salesOrderApprovalTodoCount => _salesOrderApprovalTodoCount;
  int get approvalTodoCount => _salesOrderApprovalTodoCount;

  int get purchaseApprovalTodoCount => _purchaseApprovalTodoCount;
  int _purchaseApprovalTodoCount = 0;
  List<ErpApprovalTodo> _sampleApprovalTodos = const [];
  List<ErpApprovalTodo> _approvalTodoSnapshot = const [];
  Future<List<ErpApprovalTodo>>? _approvalTodoFetchInFlight;
  List<ErpApprovalTodo> get cachedApprovalTodos => _isSampleMode
      ? _sampleApprovalTodos
      : List<ErpApprovalTodo>.unmodifiable(_approvalTodoSnapshot);

  Timer? _notificationPollTimer;
  Future<void>? _notificationTickInFlight;
  final Map<String, Future<List<SalesInvoice>>> _collectionInvoiceInFlight = {};
  final Map<String, Future<List<CollectionPayment>>>
  _collectionPaymentInFlight = {};
  final Map<String, Future<Map<String, List<SalesInvoicePaymentAllocation>>>>
  _collectionAllocationInFlight = {};
  final Map<String, Future<List<StockAgingItem>>> _stockAgingInFlight = {};
  final Map<String, Future<List<DeadStockItem>>> _deadStockInFlight = {};
  final Map<String, Future<List<StockMovementVelocityItem>>>
  _stockVelocityInFlight = {};
  Future<List<WarehouseBatchRecord>>? _warehouseBatchInFlight;
  Future<List<WarehouseSerialRecord>>? _warehouseSerialInFlight;
  final Map<String, Future<List<QualityInspectionRecord>>>
  _qualityInspectionInFlight = {};
  static const Duration _notificationPollInterval = Duration(minutes: 2);
  static const Duration _documentCacheTtl = Duration(minutes: 2);
  static const Duration _approvalTodoCacheTtl = Duration(minutes: 1);
  static const String _approvalTodoDbCachePrefix = 'approval_todo_cache';
  static const Duration _salesVisitCacheTtl = Duration(seconds: 45);
  static const Duration _collectionCacheTtl = Duration(minutes: 10);
  static const String _collectionDbCachePrefix = 'collection_cache';
  static const Duration _stockReportCacheTtl = Duration(minutes: 2);
  static const String _stockReportDbCachePrefix = 'stock_report_cache';
  static const Duration _warehouseTrackingCacheTtl = Duration(minutes: 2);
  static const String _warehouseTrackingDbCachePrefix =
      'warehouse_tracking_cache';
  static const Duration _qualityInspectionCacheTtl = Duration(minutes: 2);
  static const String _qualityInspectionDbCachePrefix =
      'quality_inspection_cache';
  final Map<String, _CachedDocument> _documentCache = {};
  final Map<String, bool> _doctypeSubmitPermissionCache = {};

  bool _isSalesOrdersLoading = false;
  bool get isSalesOrdersLoading => _isSalesOrdersLoading;

  bool _isMoreSalesOrdersLoading = false;
  bool get isMoreSalesOrdersLoading => _isMoreSalesOrdersLoading;

  bool _hasMoreSalesOrders = true;
  bool get hasMoreSalesOrders => _hasMoreSalesOrders;

  String? _salesOrdersError;
  String? get salesOrdersError => _salesOrdersError;
  String _salesOrderSearch = '';
  String? _salesOrderStatus;
  int _salesOrderQueryVersion = 0;
  Future<void>? _salesOrdersFetchInFlight;

  int _sellingPeriodYear = DateTime.now().year;
  int _sellingPeriodMonth = DateTime.now().month;
  String _sellingCompanyFilter = '';
  String _sellingCustomerTypeFilter = 'all';
  List<String> _sellingCompanies = const [];
  List<String> _sellingSalesGroups = const [];
  List<InactiveCustomer> _inactiveCustomers = const [];
  bool _isInactiveCustomersLoading = false;
  String? _inactiveCustomersError;
  int _inactiveCustomersDays = 60;
  List<String> _inactiveCustomerDoctypes = const ['Sales Order'];
  int get sellingPeriodYear => _sellingPeriodYear;
  int get sellingPeriodMonth => _sellingPeriodMonth;
  String get sellingCompanyFilter => _sellingCompanyFilter;
  String get sellingCustomerTypeFilter => _sellingCustomerTypeFilter;
  List<String> get sellingCompanies => _scopedCompanyNames(_sellingCompanies);
  List<String> get sellingSalesGroups => List.unmodifiable(_sellingSalesGroups);
  List<InactiveCustomer> get inactiveCustomers =>
      List.unmodifiable(_inactiveCustomers);
  bool get isInactiveCustomersLoading => _isInactiveCustomersLoading;
  String? get inactiveCustomersError => _inactiveCustomersError;
  int get inactiveCustomersDays => _inactiveCustomersDays;
  List<String> get inactiveCustomerDoctypes =>
      List.unmodifiable(_inactiveCustomerDoctypes);
  DateTime get sellingPeriodFrom => _sellingPeriodMonth == 0
      ? DateTime(_sellingPeriodYear, 1, 1)
      : DateTime(_sellingPeriodYear, _sellingPeriodMonth, 1);
  DateTime get sellingPeriodTo => _sellingPeriodMonth == 0
      ? DateTime(_sellingPeriodYear, 12, 31)
      : DateTime(_sellingPeriodYear, _sellingPeriodMonth + 1, 0);

  bool _isPurchaseOrdersLoading = false;
  bool get isPurchaseOrdersLoading => _isPurchaseOrdersLoading;

  bool _isMorePurchaseOrdersLoading = false;
  bool get isMorePurchaseOrdersLoading => _isMorePurchaseOrdersLoading;

  bool _hasMorePurchaseOrders = true;
  bool get hasMorePurchaseOrders => _hasMorePurchaseOrders;

  String? _purchaseOrdersError;
  String? get purchaseOrdersError => _purchaseOrdersError;
  String _purchaseOrderSearch = '';
  String? _purchaseOrderStatus;
  int _purchaseOrderQueryVersion = 0;
  Future<void>? _purchaseOrdersFetchInFlight;

  int _buyingPeriodYear = DateTime.now().year;
  int _buyingPeriodMonth = DateTime.now().month;
  String _buyingCompanyFilter = '';
  String _buyingSupplierTypeFilter = 'all';
  List<String> _buyingCompanies = const [];
  String? _buyingSupplierTypeIdsCacheKey;
  List<String>? _buyingSupplierTypeIdsCache;
  int get buyingPeriodYear => _buyingPeriodYear;
  int get buyingPeriodMonth => _buyingPeriodMonth;
  String get buyingCompanyFilter => _buyingCompanyFilter;
  String get buyingSupplierTypeFilter => _buyingSupplierTypeFilter;
  List<String> get buyingCompanies => _scopedCompanyNames(_buyingCompanies);
  DateTime get buyingPeriodFrom => _buyingPeriodMonth == 0
      ? DateTime(_buyingPeriodYear, 1, 1)
      : DateTime(_buyingPeriodYear, _buyingPeriodMonth, 1);
  DateTime get buyingPeriodTo => _buyingPeriodMonth == 0
      ? DateTime(_buyingPeriodYear, 12, 31)
      : DateTime(_buyingPeriodYear, _buyingPeriodMonth + 1, 0);

  List<String> _scopedCompanyNames(List<String> fallback) {
    final allowed = _mobileBoot?.companies ?? const <String>[];
    final normalizedAllowed = allowed
        .map((company) => company.trim())
        .where((company) => company.isNotEmpty)
        .toSet();
    if (normalizedAllowed.isEmpty) return fallback;
    if (fallback.isNotEmpty) {
      final merged = {
        ...fallback
            .map((company) => company.trim())
            .where((company) => company.isNotEmpty),
        ...normalizedAllowed,
      }.toList()..sort();
      return merged;
    }

    final scoped = fallback
        .where((company) => normalizedAllowed.contains(company.trim()))
        .toList();
    if (scoped.isNotEmpty) return scoped;
    final sorted = normalizedAllowed.toList()..sort();
    return sorted;
  }

  String? preferredCompany(Iterable<String> options) {
    final available = options
        .map((company) => company.trim())
        .where((company) => company.isNotEmpty)
        .toList();
    if (available.isEmpty) return null;

    final bootDefault = _mobileBoot?.defaultCompany.trim() ?? '';
    if (bootDefault.isNotEmpty && available.contains(bootDefault)) {
      return bootDefault;
    }

    final bootCompanies = _mobileBoot?.companies ?? const <String>[];
    for (final company in bootCompanies) {
      final trimmed = company.trim();
      if (trimmed.isNotEmpty && available.contains(trimmed)) return trimmed;
    }
    return available.first;
  }

  String? preferredWarehouse(Iterable<WarehouseInfo> options) {
    final warehouses = options
        .where((warehouse) => warehouse.name.trim().isNotEmpty)
        .toList();
    if (warehouses.isEmpty) return null;

    final bootWarehouses = _mobileBoot?.warehouses ?? const <String>[];
    for (final bootWarehouse in bootWarehouses) {
      final trimmed = bootWarehouse.trim();
      if (trimmed.isEmpty) continue;
      for (final warehouse in warehouses) {
        if (warehouse.name == trimmed) return warehouse.name;
      }
    }

    return warehouses.first.name;
  }

  Future<void>? _orderSummaryJob;
  Future<void>? _sellingSummaryJob;
  String? _sellingSummaryJobKey;
  int _sellingSummaryRequestToken = 0;
  bool _isOrderSummaryLoading = false;
  bool get isOrderSummaryLoading => _isOrderSummaryLoading;
  String? _orderSummaryError;
  String? get orderSummaryError => _orderSummaryError;
  SummarySyncStatus _summarySyncStatus = SummarySyncStatus.idle;
  SummarySyncStatus get summarySyncStatus => _summarySyncStatus;
  int _summaryProcessedRows = 0;
  int get summaryProcessedRows => _summaryProcessedRows;
  String get summarySyncSubtitle => switch (_summarySyncStatus) {
    SummarySyncStatus.syncing =>
      'Syncing all ERP data: $_summaryProcessedRows processed',
    SummarySyncStatus.completed => 'Synced from all ERP data',
    SummarySyncStatus.error => 'Showing last complete sync',
    SummarySyncStatus.idle => 'Waiting for full ERP sync',
  };
  bool get hasFullOrderSummary =>
      _salesOrderSummary.documentCount > 0 ||
      _dashboardSummary.purchasePendingCount > 0;

  bool _isDeliveryNotesLoading = false;
  bool get isDeliveryNotesLoading => _isDeliveryNotesLoading;
  bool _isMoreDeliveryNotesLoading = false;
  bool get isMoreDeliveryNotesLoading => _isMoreDeliveryNotesLoading;
  bool _hasMoreDeliveryNotes = true;
  bool get hasMoreDeliveryNotes => _hasMoreDeliveryNotes;
  String? _deliveryNotesError;
  String? get deliveryNotesError => _deliveryNotesError;
  String _deliveryNoteSearch = '';
  String? _deliveryNoteStatus;
  int _deliveryNoteQueryVersion = 0;
  Future<void>? _deliveryNotesFetchInFlight;

  bool _isSalesInvoicesLoading = false;
  bool get isSalesInvoicesLoading => _isSalesInvoicesLoading;
  bool _isMoreSalesInvoicesLoading = false;
  bool get isMoreSalesInvoicesLoading => _isMoreSalesInvoicesLoading;
  bool _hasMoreSalesInvoices = true;
  bool get hasMoreSalesInvoices => _hasMoreSalesInvoices;
  String? _salesInvoicesError;
  String? get salesInvoicesError => _salesInvoicesError;
  String _salesInvoiceSearch = '';
  String? _salesInvoiceStatus;
  int _salesInvoiceQueryVersion = 0;
  Future<void>? _salesInvoicesFetchInFlight;

  bool _isPurchaseReceiptsLoading = false;
  bool get isPurchaseReceiptsLoading => _isPurchaseReceiptsLoading;
  bool _isMorePurchaseReceiptsLoading = false;
  bool get isMorePurchaseReceiptsLoading => _isMorePurchaseReceiptsLoading;
  bool _hasMorePurchaseReceipts = true;
  bool get hasMorePurchaseReceipts => _hasMorePurchaseReceipts;
  String? _purchaseReceiptsError;
  String? get purchaseReceiptsError => _purchaseReceiptsError;
  String _purchaseReceiptSearch = '';
  String? _purchaseReceiptStatus;
  int _purchaseReceiptQueryVersion = 0;
  Future<void>? _purchaseReceiptsFetchInFlight;

  bool _isPurchaseInvoicesLoading = false;
  bool get isPurchaseInvoicesLoading => _isPurchaseInvoicesLoading;
  bool _isMorePurchaseInvoicesLoading = false;
  bool get isMorePurchaseInvoicesLoading => _isMorePurchaseInvoicesLoading;
  bool _hasMorePurchaseInvoices = true;
  bool get hasMorePurchaseInvoices => _hasMorePurchaseInvoices;
  String? _purchaseInvoicesError;
  String? get purchaseInvoicesError => _purchaseInvoicesError;
  String _purchaseInvoiceSearch = '';
  String? _purchaseInvoiceStatus;
  int _purchaseInvoiceQueryVersion = 0;
  Future<void>? _purchaseInvoicesFetchInFlight;

  bool _isMaterialRequestsLoading = false;
  bool get isMaterialRequestsLoading => _isMaterialRequestsLoading;
  bool _isMoreMaterialRequestsLoading = false;
  bool get isMoreMaterialRequestsLoading => _isMoreMaterialRequestsLoading;
  bool _hasMoreMaterialRequests = true;
  bool get hasMoreMaterialRequests => _hasMoreMaterialRequests;
  String? _materialRequestsError;
  String? get materialRequestsError => _materialRequestsError;
  String _materialRequestSearch = '';
  String? _materialRequestStatus;
  int _materialRequestQueryVersion = 0;
  Future<void>? _materialRequestsFetchInFlight;

  bool _isStockEntriesLoading = false;
  bool get isStockEntriesLoading => _isStockEntriesLoading;
  String? _stockEntriesError;
  String? get stockEntriesError => _stockEntriesError;

  bool _isInventoryLoading = false;
  bool get isInventoryLoading => _isInventoryLoading;
  Future<void>? _warehousesFetchInFlight;
  Future<void>? _inventoryFetchInFlight;
  int _warehouseQueryVersion = 0;
  int _inventoryQueryVersion = 0;

  String? _inventoryError;
  String? get inventoryError => _inventoryError;

  static const int _frappePageSize = 500;
  static const int _defaultFetchRowLimit = 500;
  static const int _documentPageSize = 50;
  static const String _prefsFrappeConfigKey = 'frappe_config';
  static const String _prefsFrappeSiteHistoryKey = 'frappe_site_history';
  static const String _prefsSummaryCacheKey = 'erp_summary_cache';
  static const String _sellingTrendCachePrefix = 'selling_trend';
  static const String _documentDbCachePrefix = 'document_cache';
  static const Duration _sellingTrendCacheTtl = Duration(hours: 12);
  static const Duration _sellingTrendRemoteTimeout = Duration(seconds: 45);
  static const String _prefsApprovalNotificationCountKey =
      'approval_notification_count';

  final ErpServices services;
  final SalesVisitLocationService _visitLocationService =
      SalesVisitLocationService();
  SalesVisit? _activeSalesVisit;
  SalesVisit? get activeSalesVisit => _activeSalesVisit;
  SalesVisit? _activeSpgVisit;
  SalesVisit? get activeSpgVisit => _activeSpgVisit;
  List<SalesVisit> _salesVisitCache = const [];
  DateTime? _salesVisitCacheAt;
  Future<List<SalesVisit>>? _salesVisitFetchInFlight;
  VisitLocationPoint? _latestVisitLocation;
  VisitLocationPoint? get latestVisitLocation => _latestVisitLocation;
  String? _activeDeliveryTrackingNote;
  String? get activeDeliveryTrackingNote => _activeDeliveryTrackingNote;
  String? _latestDeliveryTrackingNote;
  String? get latestDeliveryTrackingNote => _latestDeliveryTrackingNote;
  VisitLocationPoint? _latestDeliveryDriverLocation;
  VisitLocationPoint? get latestDeliveryDriverLocation =>
      _latestDeliveryDriverLocation;
  bool get isDeliveryDriverTrackingActive =>
      _activeDeliveryTrackingNote?.isNotEmpty == true;

  FrappeService get _frappeService => services.frappe;
  AuthService get _authService => services.auth;
  CustomerService get _customerService => services.customer;
  SalesOrderService get _salesOrderService => services.salesOrder;
  PurchaseOrderService get _purchaseOrderService => services.purchaseOrder;
  SalesInvoiceService get _salesInvoiceService => services.salesInvoice;
  PurchaseInvoiceService get _purchaseInvoiceService =>
      services.purchaseInvoice;

  FrappeService get frappeService => _frappeService;
  final MobileSiteRegistryService _siteRegistryService =
      MobileSiteRegistryService();

  Future<List<Map<String, String>>> loadFrappeSiteHistory() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsFrappeSiteHistoryKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) {
            return entry.map((key, value) {
              return MapEntry(key.toString(), value.toString());
            });
          })
          .where((entry) => (entry['baseUrl'] ?? '').trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>> fetchCurrentUserProfile() {
    final user = _currentUser?.trim() ?? '';
    if (user.isEmpty) throw Exception('User login tidak tersedia.');
    return _authService.fetchCurrentUserProfile(user);
  }

  Future<String> uploadCurrentUserImage(String filePath) {
    final user = _currentUser?.trim() ?? '';
    if (user.isEmpty) throw Exception('User login tidak tersedia.');
    return _authService.uploadCurrentUserImage(user, filePath);
  }

  Future<void> changeCurrentUserPassword({
    required String oldPassword,
    required String newPassword,
    bool logoutAllSessions = false,
  }) {
    return _authService.changeCurrentUserPassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
      logoutAllSessions: logoutAllSessions,
    );
  }

  Future<void> _restoreFrappeConfig() async {
    final cfg = await _loadFrappeConfig();
    final savedBaseUrl = cfg?['baseUrl'] ?? AppConfig.optionalFrappeBaseUrl;
    if (savedBaseUrl.trim().isNotEmpty) {
      _frappeService.baseUrl = _normalizeBaseUrl(savedBaseUrl);
      _selectedSiteName = _publicSiteName(
        baseUrl: _frappeService.baseUrl,
        storedName: cfg?['siteName'],
      );
      _selectedSiteCode = (cfg?['siteCode'] ?? '').trim().toUpperCase();
    }
    if (cfg == null) return;

    if (cfg['username'] != null) {
      _frappeService.username = cfg['username'];
    }
    if (cfg['password'] != null) {
      _frappeService.password = cfg['password'];
    }
  }

  String _normalizeBaseUrl(String value) {
    final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  String _hostLabel(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    final host = uri?.host ?? '';
    return host.isEmpty ? baseUrl : host;
  }

  bool _looksLikeTechnicalHost(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return true;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return true;
    }
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?$').hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  String _publicSiteName({required String baseUrl, String? storedName}) {
    final name = storedName?.trim() ?? '';
    if (name.isNotEmpty && !_looksLikeTechnicalHost(name)) return name;
    final normalized = _normalizeBaseUrl(baseUrl);
    if (normalized.isEmpty) return 'ERP Site';
    return _hostLabel(normalized);
  }

  String _activeFrappeBaseUrl([String? baseUrl]) {
    final explicit = baseUrl?.trim() ?? '';
    if (explicit.isNotEmpty) return _normalizeBaseUrl(explicit);
    final current = _frappeService.baseUrl.trim();
    if (current.isNotEmpty) return _normalizeBaseUrl(current);
    return AppConfig.optionalFrappeBaseUrl;
  }

  Future<bool> configureFrappeSite({
    required String codeOrUrl,
    String? displayName,
  }) async {
    final resolved = await _resolveRegisteredSite(codeOrUrl);
    if (resolved == null) {
      notifyListeners();
      return false;
    }

    final baseUrl = _normalizeBaseUrl(resolved.baseUrl);
    final previousBaseUrl = _normalizeBaseUrl(_frappeService.baseUrl);
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      _lastAuthError = 'URL Frappe site tidak valid.';
      notifyListeners();
      return false;
    }

    if (previousBaseUrl.isNotEmpty && previousBaseUrl != baseUrl) {
      _resetRuntimeDataForTenantSwitch();
      await _clearSummaryCache();
    }
    _frappeService.baseUrl = baseUrl;
    _selectedSiteCode = resolved.code;
    _selectedSiteName = _publicSiteName(
      baseUrl: baseUrl,
      storedName: displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : resolved.name,
    );
    await _saveFrappeConfigPatch({
      'baseUrl': baseUrl,
      'siteCode': _selectedSiteCode,
      'siteName': _selectedSiteName,
    });
    _lastAuthError = null;
    notifyListeners();
    return true;
  }

  Future<_ResolvedFrappeSite?> _resolveRegisteredSite(String codeOrUrl) async {
    try {
      final registered = await _siteRegistryService.resolveSite(codeOrUrl);
      if (!registered.enabled) {
        _lastAuthError =
            'Site ${registered.siteName} belum aktif. Tunggu approval developer TMSX Hub.';
        return null;
      }
      final baseUrl = _normalizeBaseUrl(registered.siteUrl);
      if (baseUrl.isEmpty) {
        _lastAuthError = 'Site URL registry tidak valid.';
        return null;
      }
      return _ResolvedFrappeSite(
        code: registered.siteCode.trim().isEmpty
            ? _hostLabel(baseUrl).toUpperCase()
            : registered.siteCode.trim().toUpperCase(),
        name: registered.siteName,
        baseUrl: baseUrl,
      );
    } catch (error) {
      _lastAuthError =
          'Site belum aktif atau belum terdaftar di registry TMSX Hub. Detail: ${_cleanShortFrappeError(error)}';
      return null;
    }
  }

  Future<void> _saveFrappeConfigPatch(Map<String, String> patch) async {
    final sp = await SharedPreferences.getInstance();
    final current = await _loadFrappeConfig() ?? <String, String>{};
    current.addAll(patch);
    await sp.setString(_prefsFrappeConfigKey, jsonEncode(current));
  }

  Future<void> _saveFrappeSiteHistory({
    required String baseUrl,
    required String siteCode,
    required String siteName,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final normalizedBaseUrl = _normalizeBaseUrl(baseUrl);
    if (normalizedBaseUrl.isEmpty) return;

    final current = await loadFrappeSiteHistory();
    final next = <Map<String, String>>[
      {
        'baseUrl': normalizedBaseUrl,
        if (siteCode.trim().isNotEmpty) 'siteCode': siteCode.trim(),
        'siteName': _publicSiteName(
          baseUrl: normalizedBaseUrl,
          storedName: siteName,
        ),
      },
      for (final entry in current)
        if (_normalizeBaseUrl(entry['baseUrl'] ?? '') != normalizedBaseUrl)
          {
            'baseUrl': _normalizeBaseUrl(entry['baseUrl'] ?? ''),
            if ((entry['siteCode'] ?? '').trim().isNotEmpty)
              'siteCode': entry['siteCode']!.trim(),
            'siteName': _publicSiteName(
              baseUrl: entry['baseUrl'] ?? '',
              storedName: entry['siteName'],
            ),
          },
    ].where((entry) => (entry['baseUrl'] ?? '').isNotEmpty).take(5).toList();

    await sp.setString(_prefsFrappeSiteHistoryKey, jsonEncode(next));
  }

  AppState({ErpServices? services}) : services = services ?? ErpServices() {
    () async {
      await _restoreFrappeConfig();
      await _restoreSummaryCache();
      unawaited(LocalAppDatabase.instance.cleanupExpired());
      _isInitializing = false;
      notifyListeners();
    }();
  }

  /// Called from splash — restores session and prefetches core data.
  Future<bool> initApp() async {
    _isInitializing = true;
    notifyListeners();

    final ok = await restoreSession();

    _isInitializing = false;
    notifyListeners();
    return ok;
  }

  Future<bool> restoreSession() async {
    await _restoreFrappeConfig();

    final cfg = await _loadFrappeConfig();
    final password = cfg?['password'] ?? '';
    if (cfg == null || !cfg.containsKey('username') || password.isEmpty) {
      return false;
    }

    try {
      if (_frappeService.baseUrl.trim().isEmpty) return false;
      _userRole = 'Unassigned';
      await _frappeService.login(cfg['username']!, password);
      _isAuthenticated = true;
      _currentUser = cfg['username'];
      await syncCurrentUserRoleFromFrappe();
      _startNotificationPolling();
      unawaited(prefetchInitialData());
      notifyListeners();
      return true;
    } catch (_) {
      await clearSessionConfig();
      _isAuthenticated = false;
      _currentUser = null;
      _userRole = 'Unassigned';
      _mobileBoot = null;
      notifyListeners();
      return false;
    }
  }

  Future<void> prefetchInitialData() async {
    final generation = _runtimeGeneration;
    final user = _currentUser;
    final baseUrl = _frappeService.baseUrl;
    try {
      await Future.wait([
        if (canUseApprovals) fetchApprovalTodos(),
        refreshNotifications(silent: true),
      ]);
      if (!_isSameRuntime(generation, user: user, baseUrl: baseUrl)) return;
    } catch (_) {
      // Prefetch failures should not block login.
    }
    if (_isSameRuntime(generation, user: user, baseUrl: baseUrl)) {
      notifyListeners();
    }
  }

  bool _isSameRuntime(int generation, {String? user, String? baseUrl}) {
    return generation == _runtimeGeneration &&
        user == _currentUser &&
        baseUrl == _frappeService.baseUrl &&
        _isAuthenticated;
  }

  Future<void> _restoreSummaryCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw =
          sp.getString(_summaryCachePrefsKey) ??
          sp.getString(_prefsSummaryCacheKey);
      if (raw == null) return;
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      DocumentSummary documentSummary(String key) {
        final value = json[key];
        return value is Map
            ? DocumentSummary.fromJson(Map<String, dynamic>.from(value))
            : const DocumentSummary();
      }

      _salesOrderSummary = DocumentSummary.fromJson(
        Map<String, dynamic>.from(json['salesOrder'] as Map),
      );
      _deliveryNoteSummary = DocumentSummary.fromJson(
        Map<String, dynamic>.from(json['deliveryNote'] as Map),
      );
      _salesInvoiceSummary = DocumentSummary.fromJson(
        Map<String, dynamic>.from(json['salesInvoice'] as Map),
      );
      _purchaseOrderSummary = documentSummary('purchaseOrder');
      _purchaseReceiptSummary = documentSummary('purchaseReceipt');
      _purchaseInvoiceSummary = documentSummary('purchaseInvoice');
      _dashboardSummary = DashboardSummary.fromJson(
        Map<String, dynamic>.from(json['dashboard'] as Map),
      );
    } catch (_) {}
  }

  Future<void> _saveSummaryCache() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _summaryCachePrefsKey,
      jsonEncode({
        'salesOrder': _salesOrderSummary.toJson(),
        'deliveryNote': _deliveryNoteSummary.toJson(),
        'salesInvoice': _salesInvoiceSummary.toJson(),
        'purchaseOrder': _purchaseOrderSummary.toJson(),
        'purchaseReceipt': _purchaseReceiptSummary.toJson(),
        'purchaseInvoice': _purchaseInvoiceSummary.toJson(),
        'dashboard': _dashboardSummary.toJson(),
      }),
    );
  }

  Future<void> clearSessionConfig() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cfg = await _loadFrappeConfig();
      if (cfg == null) {
        await sp.remove(_prefsFrappeConfigKey);
      } else {
        final next = <String, String>{
          if (cfg['baseUrl']?.trim().isNotEmpty == true)
            'baseUrl': cfg['baseUrl']!,
          if (cfg['siteName']?.trim().isNotEmpty == true)
            'siteName': cfg['siteName']!,
          if (cfg['siteCode']?.trim().isNotEmpty == true)
            'siteCode': cfg['siteCode']!,
        };
        if (next.isEmpty) {
          await sp.remove(_prefsFrappeConfigKey);
        } else {
          await sp.setString(_prefsFrappeConfigKey, jsonEncode(next));
        }
      }
      await sp.remove(_prefsUserRoleKey);
    } catch (_) {}
    _frappeService.username = null;
    _frappeService.password = null;
  }

  Future<void> _clearSummaryCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_summaryCachePrefsKey);
      await sp.remove(_prefsSummaryCacheKey);
      await LocalAppDatabase.instance.deleteByPrefix(_sellingTrendCachePrefix);
      await LocalAppDatabase.instance.deleteByPrefix(_documentDbCachePrefix);
      await LocalAppDatabase.instance.deleteByPrefix(_collectionDbCachePrefix);
      await LocalAppDatabase.instance.deleteByPrefix(_stockReportDbCachePrefix);
      await LocalAppDatabase.instance.deleteByPrefix(
        _warehouseTrackingDbCachePrefix,
      );
      await LocalAppDatabase.instance.deleteByPrefix(
        _qualityInspectionDbCachePrefix,
      );
      await LocalAppDatabase.instance.deleteByPrefix(
        _approvalTodoDbCachePrefix,
      );
    } catch (_) {}
  }

  String get _summaryCachePrefsKey {
    final site = _frappeService.baseUrl.trim();
    final user = _currentUser?.trim() ?? _frappeService.username?.trim() ?? '';
    return '$_prefsSummaryCacheKey::$site::$user';
  }

  Future<void> resetLocalAppCache({bool keepSiteSelection = true}) async {
    _stopNotificationPolling();
    await _visitLocationService.stopTracking();
    final sp = await SharedPreferences.getInstance();
    final cfg = keepSiteSelection ? await _loadFrappeConfig() : null;
    final history = keepSiteSelection
        ? sp.getString(_prefsFrappeSiteHistoryKey)
        : null;

    for (final key in sp.getKeys().toList()) {
      if (key == _prefsFrappeConfigKey && keepSiteSelection) continue;
      if (key == _prefsFrappeSiteHistoryKey && keepSiteSelection) continue;
      if (key.startsWith(_prefsSummaryCacheKey) ||
          key == _prefsUserRoleKey ||
          key == _prefsFrappeConfigKey ||
          key == _prefsFrappeSiteHistoryKey) {
        await sp.remove(key);
      }
    }
    await LocalAppDatabase.instance.deleteByPrefix(_sellingTrendCachePrefix);
    await LocalAppDatabase.instance.deleteByPrefix(_documentDbCachePrefix);

    if (keepSiteSelection && cfg != null) {
      await sp.setString(_prefsFrappeConfigKey, jsonEncode(cfg));
    }
    if (keepSiteSelection && history != null) {
      await sp.setString(_prefsFrappeSiteHistoryKey, history);
    }

    _frappeService.username = null;
    _frappeService.password = null;
    _mobileBoot = null;
    _mobileCompatibilityWarning = null;
    _currentUser = null;
    _currentEmployee = null;
    _currentEmployeeProfile = const {};
    _currentSalesPerson = null;
    _salesIdentityUser = null;
    _salesIdentityRequest = null;
    _salesIdentityError = null;
    _userRole = 'Unassigned';
    _isAuthenticated = false;
    _resetRuntimeDataForTenantSwitch();
    notifyListeners();
  }

  void _resetRuntimeDataForTenantSwitch() {
    _runtimeGeneration++;
    _salesOrders = [];
    _purchaseOrders = [];
    _deliveryNotes = [];
    _salesInvoices = [];
    _purchaseReceipts = [];
    _purchaseInvoices = [];
    _materialRequests = [];
    _stockEntries = [];
    _stockReconciliations = [];
    _inventory = [];
    _itemGroups = [];
    _warehouses = [];
    _salesOrderSummary = const DocumentSummary();
    _deliveryNoteSummary = const DocumentSummary();
    _salesInvoiceSummary = const DocumentSummary();
    _purchaseOrderSummary = const DocumentSummary();
    _purchaseReceiptSummary = const DocumentSummary();
    _purchaseInvoiceSummary = const DocumentSummary();
    _dashboardSummary = const DashboardSummary();
    _salesOrderTrendPoints = const [];
    _deliveryNoteTrendPoints = const [];
    _salesInvoiceTrendPoints = const [];
    _purchaseOrderTrendPoints = const [];
    _purchaseReceiptTrendPoints = const [];
    _purchaseInvoiceTrendPoints = const [];
    _materialRequestTrendPoints = const [];

    _salesOrdersError = null;
    _purchaseOrdersError = null;
    _deliveryNotesError = null;
    _salesInvoicesError = null;
    _purchaseReceiptsError = null;
    _purchaseInvoicesError = null;
    _materialRequestsError = null;
    _stockEntriesError = null;
    _inventoryError = null;
    _orderSummaryError = null;

    _isSalesOrdersLoading = false;
    _isMoreSalesOrdersLoading = false;
    _isPurchaseOrdersLoading = false;
    _isMorePurchaseOrdersLoading = false;
    _isDeliveryNotesLoading = false;
    _isMoreDeliveryNotesLoading = false;
    _isSalesInvoicesLoading = false;
    _isMoreSalesInvoicesLoading = false;
    _isPurchaseReceiptsLoading = false;
    _isMorePurchaseReceiptsLoading = false;
    _isPurchaseInvoicesLoading = false;
    _isMorePurchaseInvoicesLoading = false;
    _isMaterialRequestsLoading = false;
    _isMoreMaterialRequestsLoading = false;
    _isStockEntriesLoading = false;
    _isInventoryLoading = false;
    _isOrderSummaryLoading = false;

    _hasMoreSalesOrders = true;
    _hasMorePurchaseOrders = true;
    _hasMoreDeliveryNotes = true;
    _hasMoreSalesInvoices = true;
    _hasMorePurchaseReceipts = true;
    _hasMorePurchaseInvoices = true;
    _hasMoreMaterialRequests = true;

    _salesOrderSearch = '';
    _purchaseOrderSearch = '';
    _deliveryNoteSearch = '';
    _salesInvoiceSearch = '';
    _purchaseReceiptSearch = '';
    _purchaseInvoiceSearch = '';
    _materialRequestSearch = '';
    _salesOrderStatus = null;
    _purchaseOrderStatus = null;
    _deliveryNoteStatus = null;
    _salesInvoiceStatus = null;
    _purchaseReceiptStatus = null;
    _purchaseInvoiceStatus = null;
    _materialRequestStatus = null;
    _salesOrderQueryVersion++;
    _purchaseOrderQueryVersion++;
    _deliveryNoteQueryVersion++;
    _salesInvoiceQueryVersion++;
    _purchaseReceiptQueryVersion++;
    _purchaseInvoiceQueryVersion++;
    _materialRequestQueryVersion++;
    _warehouseQueryVersion++;
    _inventoryQueryVersion++;

    _sellingCompanyFilter = '';
    _buyingCompanyFilter = '';
    _sellingCompanies = const [];
    _sellingSalesGroups = const [];
    _inactiveCustomers = const [];
    _inactiveCustomersError = null;
    _inactiveCustomersDays = 60;
    _inactiveCustomerDoctypes = const ['Sales Order'];
    _isInactiveCustomersLoading = false;
    _buyingCompanies = const [];
    _sellingCustomerTypeFilter = 'all';
    _buyingSupplierTypeFilter = 'all';
    _buyingSupplierTypeIdsCacheKey = null;
    _buyingSupplierTypeIdsCache = null;
    _salesOrderApprovalTodoCount = 0;
    _purchaseApprovalTodoCount = 0;
    _summarySyncStatus = SummarySyncStatus.idle;
    _summaryProcessedRows = 0;
    _doctypeSubmitPermissionCache.clear();
    _documentCache.clear();
    _approvalTodoSnapshot = const [];
    _approvalTodoFetchInFlight = null;
    _activeSalesVisit = null;
    _activeSpgVisit = null;
    _salesVisitCache = const [];
    _salesVisitCacheAt = null;
    _salesVisitFetchInFlight = null;
    _collectionInvoiceInFlight.clear();
    _collectionPaymentInFlight.clear();
    _collectionAllocationInFlight.clear();
    _stockAgingInFlight.clear();
    _deadStockInFlight.clear();
    _stockVelocityInFlight.clear();
    _warehouseBatchInFlight = null;
    _warehouseSerialInFlight = null;
    _qualityInspectionInFlight.clear();
  }

  void setRememberDevice(bool value) {
    _rememberDevice = value;
    notifyListeners();
  }

  Future<bool> login(
    String username,
    String password, {
    String? baseUrl,
  }) async {
    try {
      _lastAuthError = null;
      _isSampleMode = false;
      if (baseUrl != null && baseUrl.trim().isNotEmpty) {
        final nextBaseUrl = _normalizeBaseUrl(baseUrl);
        if (_normalizeBaseUrl(_frappeService.baseUrl) != nextBaseUrl) {
          _resetRuntimeDataForTenantSwitch();
          await _clearSummaryCache();
        }
        _frappeService.baseUrl = nextBaseUrl;
      }
      if (_frappeService.baseUrl.trim().isEmpty) {
        throw Exception('Pilih Frappe site sebelum login.');
      }
      _userRole = 'Unassigned';
      _mobileBoot = null;
      _resetRuntimeDataForTenantSwitch();
      await _frappeService.login(username, password);
      _isAuthenticated = true;
      _currentUser = username;
      await syncCurrentUserRoleFromFrappe();
      _startNotificationPolling();
      unawaited(prefetchInitialData());
      notifyListeners();
      return true;
    } catch (e, st) {
      _lastAuthError = e.toString();
      if (!kReleaseMode) {
        developer.log('Login failed', error: e, stackTrace: st);
      }
      _isAuthenticated = false;
      _currentUser = null;
      _userRole = 'Unassigned';
      notifyListeners();
      return false;
    }
  }

  void loginSample() {
    _stopNotificationPolling();
    _resetRuntimeDataForTenantSwitch();

    _isSampleMode = true;
    _isAuthenticated = true;
    _currentUser = 'example@gmail.com';
    _currentEmployee = 'EMP-SAMPLE-001';
    _currentEmployeeProfile = const {
      'employee_name': 'Example User',
      'designation': 'Sales Reviewer',
      'company': 'Sample Company',
    };
    _currentSalesPerson = 'Example Sales';
    _salesIdentityUser = _currentUser;
    _salesIdentityError = null;
    _userRole = MobileRole.developer;
    _selectedSiteName = 'Sample Offline';
    _selectedSiteCode = 'SAMPLE';
    _frappeService.baseUrl = '';

    _loadSampleData();
    notifyListeners();
  }

  void _loadSampleData() {
    final today = DateTime.now();
    String date(int daysAgo) => today
        .subtract(Duration(days: daysAgo))
        .toIso8601String()
        .split('T')
        .first;

    _warehouses = [
      WarehouseInfo(
        name: 'Sample Warehouse - SC',
        displayName: 'Sample Warehouse',
        company: 'Sample Company',
      ),
      WarehouseInfo(
        name: 'Transit Sample - SC',
        displayName: 'Transit Sample',
        company: 'Sample Company',
      ),
    ];

    _inventory = [
      InventoryItem.fromJson({
        'item_code': 'ITEM-SAMPLE-001',
        'item_name': 'Pisang Cavendish CL',
        'warehouse': 'Sample Warehouse - SC',
        'actual_qty': 128,
        'reorder_level': 40,
        'valuation_rate': 246500,
        'item_group': 'Fresh Produce',
      }),
      InventoryItem.fromJson({
        'item_code': 'ITEM-SAMPLE-002',
        'item_name': 'Fresh Pack 1 Kg',
        'warehouse': 'Sample Warehouse - SC',
        'actual_qty': 18,
        'reorder_level': 35,
        'valuation_rate': 62500,
        'item_group': 'Packaging',
      }),
      InventoryItem.fromJson({
        'item_code': 'ITEM-SAMPLE-003',
        'item_name': 'Display Rack Mini',
        'warehouse': 'Transit Sample - SC',
        'actual_qty': 4,
        'reorder_level': 12,
        'valuation_rate': 185000,
        'item_group': 'Merchandising',
      }),
    ];

    _salesOrders = [
      SalesOrder.fromJson({
        'name': 'SO-SAMPLE-0001',
        'customer': 'CUST-SAMPLE-001',
        'customer_name': 'Sample Retail Nusantara',
        'transaction_date': date(0),
        'delivery_date': date(1),
        'status': 'Draft',
        'docstatus': 0,
        'grand_total': 1250000,
        'total_qty': 5,
        'currency': 'IDR',
        'selling_price_list': 'Standard Selling',
        'noted': 'Customer meminta diskon tambahan untuk pembelian rutin.',
        'sales_team': [
          {'sales_person': 'Example Sales', 'allocated_percentage': 100},
        ],
        'items': [
          {
            'item_code': 'ITEM-SAMPLE-001',
            'item_name': 'Pisang Cavendish CL',
            'qty': 5,
            'rate': 246500,
            'discount_amount': 5000,
            'warehouse': 'Sample Warehouse - SC',
            'delivery_date': date(1),
          },
        ],
      }),
      SalesOrder.fromJson({
        'name': 'SO-SAMPLE-0002',
        'customer': 'CUST-SAMPLE-002',
        'customer_name': 'Cocomart Sample',
        'transaction_date': date(2),
        'delivery_date': date(3),
        'status': 'Pending Approval',
        'workflow_state': 'Pending Approval',
        'docstatus': 0,
        'grand_total': 842000,
        'total_qty': 8,
        'currency': 'IDR',
        'sales_team': [
          {'sales_person': 'Example Sales', 'allocated_percentage': 100},
        ],
        'items': [
          {
            'item_code': 'ITEM-SAMPLE-002',
            'item_name': 'Fresh Pack 1 Kg',
            'qty': 8,
            'rate': 105250,
            'warehouse': 'Sample Warehouse - SC',
            'delivery_date': date(3),
          },
        ],
      }),
    ];

    _deliveryNotes = [
      DeliveryNote.fromJson({
        'name': 'DN-SAMPLE-0001',
        'customer': 'CUST-SAMPLE-001',
        'customer_name': 'Sample Retail Nusantara',
        'posting_date': date(1),
        'status': 'To Bill',
        'docstatus': 1,
        'grand_total': 1250000,
        'total_qty': 5,
      }),
    ];

    _salesInvoices = [
      SalesInvoice.fromJson({
        'name': 'SI-SAMPLE-0001',
        'customer': 'CUST-SAMPLE-001',
        'customer_name': 'Sample Retail Nusantara',
        'posting_date': date(1),
        'due_date': date(-14),
        'status': 'Unpaid',
        'docstatus': 1,
        'grand_total': 1250000,
        'outstanding_amount': 1250000,
      }),
    ];

    _purchaseOrders = [
      PurchaseOrder.fromJson({
        'name': 'PO-SAMPLE-0001',
        'supplier': 'SUP-SAMPLE-001',
        'supplier_name': 'Sample Supplier',
        'transaction_date': date(4),
        'schedule_date': date(2),
        'status': 'To Receive and Bill',
        'docstatus': 1,
        'grand_total': 3500000,
        'total_qty': 20,
      }),
    ];

    _salesOrderSummary = const DocumentSummary(
      totalValue: 2092000,
      documentCount: 2,
    );
    _deliveryNoteSummary = const DocumentSummary(
      totalValue: 1250000,
      documentCount: 1,
    );
    _salesInvoiceSummary = const DocumentSummary(
      totalValue: 1250000,
      documentCount: 1,
    );
    _purchaseOrderSummary = const DocumentSummary(
      totalValue: 3500000,
      documentCount: 1,
    );
    _dashboardSummary = const DashboardSummary(
      salesTotal: 2092000,
      salesOpen: 842000,
      salesCompleted: 1250000,
      salesDraftCount: 1,
      salesOpenCount: 1,
      salesCompletedCount: 1,
      purchaseTotal: 3500000,
      purchasePending: 3500000,
      purchasePendingCount: 1,
      unpaidSalesInvoices: 1,
      stockAlerts: 2,
    );

    _salesOrderTrendPoints = [
      DocumentTrendPoint(label: 'W-3', value: 780000, documentCount: 1),
      DocumentTrendPoint(label: 'W-2', value: 1250000, documentCount: 1),
      DocumentTrendPoint(label: 'W-1', value: 2092000, documentCount: 2),
    ];
    _purchaseOrderTrendPoints = [
      DocumentTrendPoint(label: 'W-3', value: 1800000, documentCount: 1),
      DocumentTrendPoint(label: 'W-2', value: 2400000, documentCount: 1),
      DocumentTrendPoint(label: 'W-1', value: 3500000, documentCount: 1),
    ];

    _sampleApprovalTodos = [
      ErpApprovalTodo(
        doctype: 'Sales Order',
        name: 'SO-SAMPLE-0002',
        party: 'CUST-SAMPLE-002',
        partyName: 'Cocomart Sample',
        workflowState: 'Pending Approval',
        status: 'Pending Approval',
        owner: 'example@gmail.com',
        date: date(2),
        amount: 842000,
        docStatus: 0,
        actions: const ['Approve', 'Reject'],
      ),
      ErpApprovalTodo(
        doctype: 'Purchase Order',
        name: 'PO-SAMPLE-0001',
        party: 'SUP-SAMPLE-001',
        partyName: 'Sample Supplier',
        workflowState: 'Pending Approval',
        status: 'To Receive and Bill',
        owner: 'example@gmail.com',
        date: date(4),
        amount: 3500000,
        docStatus: 1,
        actions: const ['Approve', 'Reject'],
      ),
    ];
    _salesOrderApprovalTodoCount = _sampleApprovalTodos.length;
    _purchaseApprovalTodoCount = 1;
  }

  Future<void> logout() async {
    _stopNotificationPolling();
    await _visitLocationService.stopTracking();
    _activeSalesVisit = null;
    _activeSpgVisit = null;
    _latestVisitLocation = null;
    _mobileCompatibilityWarning = null;
    _mobileBoot = null;
    _salesOrderApprovalTodoCount = 0;
    _purchaseApprovalTodoCount = 0;
    _resetRuntimeDataForTenantSwitch();
    _isSampleMode = false;
    _isAuthenticated = false;
    _currentUser = null;
    _userRole = 'Unassigned';
    await clearSessionConfig();
    notifyListeners();
  }

  Future<MobileBoot?> fetchMobileBoot() async {
    try {
      final result = await _frappeService.callMethod(
        'tmsx_mobile.api.auth.get_mobile_boot',
      );
      final payload = result is Map<String, dynamic>
          ? result
          : result is Map
          ? Map<String, dynamic>.from(result)
          : null;
      if (payload == null) {
        _mobileBoot = null;
        return null;
      }
      _mobileBoot = MobileBoot.fromJson(payload);
      _mobileCompatibilityWarning = null;
      notifyListeners();
      return _mobileBoot;
    } catch (_) {
      _mobileBoot = null;
      _mobileCompatibilityWarning =
          'Site ini belum memasang package tmsx_mobile. App memakai API ERPNext langsung.';
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> checkMobileBackendCompatibility() async {
    final boot = await fetchMobileBoot();
    return boot?.raw;
  }

  void _startNotificationPolling() {
    _notificationPollTimer?.cancel();
    _notificationPollTimer = Timer.periodic(
      _notificationPollInterval,
      (_) => _refreshNotificationTick(),
    );
    unawaited(_refreshNotificationTick());
  }

  void _stopNotificationPolling() {
    _notificationPollTimer?.cancel();
    _notificationPollTimer = null;
    _notificationTickInFlight = null;
  }

  Future<void> _refreshNotificationTick() async {
    final inFlight = _notificationTickInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final request = _refreshApprovalTodoSystemNotification();
    _notificationTickInFlight = request;
    try {
      await request;
    } finally {
      if (identical(_notificationTickInFlight, request)) {
        _notificationTickInFlight = null;
      }
    }
  }

  Future<void> _refreshApprovalTodoSystemNotification() async {
    if (_isSampleMode ||
        !_isAuthenticated ||
        _currentUser == null ||
        !canUseApprovals) {
      return;
    }
    try {
      final sp = await SharedPreferences.getInstance();
      final previous = sp.getInt(_approvalNotificationCountPrefsKey);
      final todos = await fetchApprovalTodos();
      final count = todos.where((todo) => todo.actions.isNotEmpty).length;
      await sp.setInt(_approvalNotificationCountPrefsKey, count);
      if (count <= 0) return;
      if (previous != null && count <= previous) return;

      await NativeNotificationService.instance.requestPermission();
      await NativeNotificationService.instance.showApprovalTodoNotification(
        count: count,
        siteName: selectedSiteName,
      );
    } catch (_) {
      // System notifications are best-effort and must not break polling.
    }
  }

  Future<void> refreshNotifications({bool silent = false}) async {
    if (!silent) {
      notifyListeners();
    }
  }

  String get _approvalNotificationCountPrefsKey {
    final site = _frappeService.baseUrl.trim();
    final user = _currentUser?.trim() ?? '';
    return '$_prefsApprovalNotificationCountKey::$site::$user';
  }

  @override
  void dispose() {
    _stopNotificationPolling();
    unawaited(_visitLocationService.stopTracking());
    super.dispose();
  }

  Future<SalesOrder> loadSalesOrderDetail(String orderId) async {
    final order = await _salesOrderService.load(orderId);
    _replaceSalesOrderSnapshot(order);
    return order;
  }

  void _replaceSalesOrderSnapshot(SalesOrder order) {
    final index = _salesOrders.indexWhere((item) => item.id == order.id);
    if (index < 0) return;
    _salesOrders = List<SalesOrder>.from(_salesOrders)..[index] = order;
    notifyListeners();
  }

  Future<String?> _salesPersonScopeName() async {
    if (!_shouldScopeSalesData) return null;
    if (_currentSalesPerson == null || _currentSalesPerson!.isEmpty) {
      await resolveCurrentSalesIdentity();
    }
    final salesPerson = _currentSalesPerson?.trim();
    if (salesPerson == null || salesPerson.isEmpty) {
      throw Exception(
        _salesIdentityError ?? 'Sales Person user login belum tersedia.',
      );
    }
    return salesPerson;
  }

  Future<List<List<dynamic>>?> _salesDocumentScopeFilters(String _) async {
    final salesPerson = await _salesPersonScopeName();
    if (salesPerson == null) return const [];

    // Avoid scanning Sales Team rows and then querying parent documents by a
    // large name list. ERPNext Report View can filter SO/DN/SI through the
    // Sales Team child table directly, which is much faster for Sales User.
    return [
      ['Sales Team', 'sales_person', '=', salesPerson],
    ];
  }

  Future<List<T>> _filterSalesDocumentsByCurrentSalesPerson<T>({
    required String doctype,
    required List<T> docs,
    required String Function(T doc) idOf,
  }) async {
    final salesPerson = await _salesPersonScopeName();
    if (salesPerson == null || docs.isEmpty) return docs;

    final documents = await _fetchDocumentsInBatches(
      doctype,
      docs.map(idOf),
      batchSize: 12,
    );
    return docs.where((doc) {
      final document = documents[idOf(doc)];
      if (document == null) return false;
      return _documentChildRows(
        document['sales_team'],
      ).any((row) => row['sales_person']?.toString().trim() == salesPerson);
    }).toList();
  }

  Future<bool> _salesDocumentBelongsToCurrentSalesPerson({
    required String doctype,
    required String name,
  }) async {
    final salesPerson = await _salesPersonScopeName();
    if (salesPerson == null || name.trim().isEmpty) return true;
    try {
      final document = await _fetchCachedDocument(doctype, name);
      return _documentChildRows(
        document['sales_team'],
      ).any((row) => row['sales_person']?.toString().trim() == salesPerson);
    } catch (_) {
      return false;
    }
  }

  Future<List<SalesCustomerOption>> fetchSalesCustomers() async {
    if (_isSampleMode) {
      return const [
        SalesCustomerOption(
          id: 'CUST-SAMPLE-001',
          name: 'Sample Retail Nusantara',
          address: 'Jl. Sample Raya No. 1',
          salesTeam: [
            {'sales_person': 'Example Sales', 'allocated_percentage': 100},
          ],
        ),
        SalesCustomerOption(
          id: 'CUST-SAMPLE-002',
          name: 'Cocomart Sample',
          address: 'Jl. Demo Market No. 8',
          salesTeam: [
            {'sales_person': 'Example Sales', 'allocated_percentage': 100},
          ],
        ),
      ];
    }
    if (_shouldScopeSalesData &&
        (_currentSalesPerson == null || _currentSalesPerson!.isEmpty)) {
      await resolveCurrentSalesIdentity();
    }
    if (_shouldScopeSalesData &&
        (_currentSalesPerson == null || _currentSalesPerson!.isEmpty)) {
      throw Exception(
        _salesIdentityError ?? 'Sales Person user login belum tersedia.',
      );
    }
    final customers = await _customerService.fetchSalesCustomers(
      salesPerson: _shouldScopeSalesData ? _currentSalesPerson : null,
    );
    if (!_shouldScopeSalesData || customers.isNotEmpty) return customers;
    return _fetchSalesCustomersFromSalesDocuments(_currentSalesPerson!.trim());
  }

  Future<List<SalesCustomerOption>> _fetchSalesCustomersFromSalesDocuments(
    String salesPerson,
  ) async {
    final customerRows = <String, Map<String, dynamic>>{};
    for (final spec in const [
      _SalesCustomerDocumentSpec(
        doctype: 'Sales Order',
        dateField: 'transaction_date',
      ),
      _SalesCustomerDocumentSpec(
        doctype: 'Delivery Note',
        dateField: 'posting_date',
      ),
      _SalesCustomerDocumentSpec(
        doctype: 'Sales Invoice',
        dateField: 'posting_date',
      ),
    ]) {
      final rows = await _tryFetchSalesCustomerRowsFromDocumentType(
        spec,
        salesPerson,
      );
      for (final row in rows) {
        final customer = row['customer']?.toString().trim() ?? '';
        if (customer.isEmpty || customerRows.containsKey(customer)) continue;
        customerRows[customer] = row;
      }
    }
    final result =
        customerRows.values
            .map(
              (row) => SalesCustomerOption(
                id: row['customer']?.toString().trim() ?? '',
                name: row['customer_name']?.toString().trim().isNotEmpty == true
                    ? row['customer_name']!.toString()
                    : row['customer']?.toString().trim() ?? '',
                salesTeam: [
                  {'sales_person': salesPerson, 'allocated_percentage': 100},
                ],
              ),
            )
            .where((customer) => customer.id.isNotEmpty)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  Future<List<Map<String, dynamic>>> _tryFetchSalesCustomerRowsFromDocumentType(
    _SalesCustomerDocumentSpec spec,
    String salesPerson,
  ) async {
    try {
      final rows = await _fetchAllResourcePages(
        doctype: spec.doctype,
        fields: const ['name', 'customer', 'customer_name'],
        filters: const [
          ['docstatus', '!=', 2],
        ],
        orderBy: '${spec.dateField} desc, modified desc',
        maxRows: 80,
      );
      final documents = await _fetchDocumentsInBatches(
        spec.doctype,
        rows.map((row) => row['name']?.toString().trim() ?? ''),
      );
      return rows.where((row) {
        final name = row['name']?.toString().trim() ?? '';
        final document = documents[name];
        if (document == null) return false;
        return _documentChildRows(
          document['sales_team'],
        ).any((team) => team['sales_person']?.toString().trim() == salesPerson);
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<SalesInvoice>> fetchCollectionOutstandingInvoices() async {
    final key = _collectionOutstandingCacheKey();
    final cachedRows = await _readDbRowList(key);
    if (cachedRows != null) {
      return cachedRows.map(SalesInvoice.fromJson).toList();
    }
    final inFlight = _collectionInvoiceInFlight[key];
    if (inFlight != null) return inFlight;
    final request = _fetchCollectionOutstandingInvoicesFromErp();
    _collectionInvoiceInFlight[key] = request;
    try {
      final invoices = await request;
      await _writeDbRowList(
        key,
        invoices.map(_collectionInvoiceToCacheJson).toList(),
        ttl: _collectionCacheTtl,
      );
      return invoices;
    } finally {
      if (identical(_collectionInvoiceInFlight[key], request)) {
        _collectionInvoiceInFlight.remove(key);
      }
    }
  }

  Future<List<SalesInvoice>>
  _fetchCollectionOutstandingInvoicesFromErp() async {
    final scopeFilters = await _salesDocumentScopeFilters('Sales Invoice');
    final company = _sellingCompanyFilter.trim();
    final rows = await _fetchAllResourcePages(
      doctype: 'Sales Invoice',
      fields: const [
        'name',
        'owner',
        'customer',
        'customer_name',
        'company',
        'status',
        'docstatus',
        'posting_date',
        'base_net_total',
        'net_total',
        'grand_total',
        'outstanding_amount',
        'due_date',
      ],
      filters: [
        ['docstatus', '=', 1],
        ['outstanding_amount', '>', 0],
        [
          'status',
          'not in',
          ['Cancelled', 'Closed'],
        ],
        if (company.isNotEmpty) ['company', '=', company],
        ...?scopeFilters,
      ],
      orderBy: 'due_date asc, name asc',
      maxRows: null,
    );
    final enrichedRows = await _enrichCollectionInvoiceRows(rows);
    var invoices = enrichedRows.map(SalesInvoice.fromJson).toList();
    if (scopeFilters == null) {
      invoices = await _filterSalesDocumentsByCurrentSalesPerson(
        doctype: 'Sales Invoice',
        docs: invoices,
        idOf: (invoice) => invoice.id,
      );
    }
    return invoices;
  }

  String _collectionOutstandingCacheKey() {
    return [
      _collectionDbCachePrefix,
      selectedSiteBaseUrl.trim(),
      _currentUser?.trim() ?? '',
      'outstanding',
      _sellingCompanyFilter.trim(),
      _shouldScopeSalesData,
      _currentSalesPerson?.trim() ?? '',
    ].join('|');
  }

  Map<String, dynamic> _collectionInvoiceToCacheJson(SalesInvoice invoice) => {
    'name': invoice.id,
    'customer_name': invoice.customer,
    'base_net_total': invoice.value,
    'outstanding_amount': invoice.outstandingAmount,
    'status': invoice.statusText,
    'docstatus': invoice.docStatus,
    'posting_date': invoice.date,
    'due_date': invoice.dueDate,
    '_resolved_tukar_faktur': invoice.tukarFaktur,
    '_resolved_tukar_faktur_date': invoice.tukarFakturDate,
    '_resolved_tukar_faktur_due_date': invoice.tukarFakturDueDate,
  };

  Future<List<Map<String, dynamic>>> _enrichCollectionInvoiceRows(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return rows;
    final ids = rows
        .map((row) => row['name']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    final documents = await _fetchDocumentsInBatches('Sales Invoice', ids);
    final enriched = rows.map((row) {
      final id = row['name']?.toString().trim() ?? '';
      return {...row, if (documents[id] != null) ...documents[id]!};
    }).toList();

    final tukarFakturIds = enriched
        .map(_collectionTukarFakturId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (tukarFakturIds.isEmpty) return enriched;

    final tukarFakturDocs = await _fetchDocumentsInBatches(
      'Tukar Faktur',
      tukarFakturIds,
    );
    if (tukarFakturDocs.isEmpty) return enriched;

    return enriched.map((row) {
      final tukarFakturId = _collectionTukarFakturId(row);
      final doc = tukarFakturDocs[tukarFakturId];
      if (doc == null) return row;
      return {
        ...row,
        '_resolved_tukar_faktur': tukarFakturId,
        '_resolved_tukar_faktur_date': _firstCollectionField(doc, const [
          'tanggal_tukar_faktur',
          'tgl_tukar_faktur',
          'posting_date',
          'transaction_date',
          'date',
        ]),
        '_resolved_tukar_faktur_due_date': _firstCollectionField(doc, const [
          'jatuh_tempo_tukar_faktur',
          'tanggal_jatuh_tempo_tukar_faktur',
          'tgl_jatuh_tempo_tukar_faktur',
          'due_date',
          'payment_due_date',
        ]),
      };
    }).toList();
  }

  String _collectionTukarFakturId(Map<String, dynamic> row) {
    return _firstCollectionField(row, const [
      'tukar_faktur',
      'custom_tukar_faktur',
      'no_tukar_faktur',
      'nomor_tukar_faktur',
      'tukar_faktur_no',
      'tt_no',
      'no_tt',
    ]);
  }

  String _firstCollectionField(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return '';
  }

  Future<List<CollectionRanking>> fetchCollectionRanking({
    DateTime? from,
    DateTime? to,
    String? filterSalesPerson,
    List<String>? filterSalesPersons,
    String? parentSalesPerson,
    String? company,
  }) async {
    final allowedSalesPersons = filterSalesPersons
        ?.map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final singleFilterSalesPerson = filterSalesPerson?.trim() ?? '';
    final selectedParentSalesPerson = parentSalesPerson?.trim() ?? '';
    final selectedCompany = company?.trim() ?? '';
    final totals = <String, double>{};
    final salesPersons = await _fetchAllResourcePages(
      doctype: 'Sales Person',
      fields: const ['name', 'enabled', 'is_group'],
      filters: const [
        ['is_group', '=', 0],
      ],
      orderBy: 'name asc',
      maxRows: null,
    );
    for (final row in salesPersons) {
      final name = row['name']?.toString() ?? '';
      final enabled = row['enabled'];
      if (name.isEmpty || enabled == 0 || enabled == false) continue;
      if ((allowedSalesPersons != null && allowedSalesPersons.contains(name)) ||
          (allowedSalesPersons == null &&
              (singleFilterSalesPerson.isEmpty ||
                  name == singleFilterSalesPerson))) {
        totals[name] = 0;
      }
    }

    final orderRows = await _fetchAllResourcePages(
      doctype: 'Sales Order',
      fields: const ['name', 'grand_total', 'net_total', 'transaction_date'],
      filters: [
        ['docstatus', '!=', 2],
        if (selectedCompany.isNotEmpty) ['company', '=', selectedCompany],
        if (selectedParentSalesPerson.isNotEmpty)
          ['parent_sales_person', '=', selectedParentSalesPerson],
        if (from != null)
          ['transaction_date', '>=', DateRangePresets.toFrappeDate(from)],
        if (to != null)
          ['transaction_date', '<=', DateRangePresets.toFrappeDate(to)],
      ],
      orderBy: 'transaction_date desc, name desc',
      maxRows: null,
    );
    if (orderRows.isEmpty) return _collectionRankingRows(totals);

    final orderAmounts = <String, double>{};
    for (final order in orderRows) {
      final id = order['name']?.toString() ?? '';
      if (id.isEmpty) continue;
      final amount = NumParse.asDouble(
        order['grand_total'] ?? order['net_total'],
      );
      orderAmounts[id] = amount.clamp(0, double.infinity);
    }
    if (orderAmounts.isEmpty) return _collectionRankingRows(totals);

    final orderDocuments = await _fetchDocumentsInBatches(
      'Sales Order',
      orderAmounts.keys,
    );
    for (final order in orderAmounts.entries) {
      final document = orderDocuments[order.key];
      if (document == null) continue;
      for (final team in _documentChildRows(document['sales_team'])) {
        final salesPerson = team['sales_person']?.toString() ?? '';
        if (salesPerson.isEmpty) continue;
        if (allowedSalesPersons != null &&
            !allowedSalesPersons.contains(salesPerson)) {
          continue;
        }
        if (allowedSalesPersons == null &&
            singleFilterSalesPerson.isNotEmpty &&
            salesPerson != singleFilterSalesPerson) {
          continue;
        }
        final percentage = NumParse.asDouble(team['allocated_percentage']);
        final ratio = percentage > 0 ? percentage / 100 : 1.0;
        totals[salesPerson] =
            (totals[salesPerson] ?? 0) +
            order.value.clamp(0, double.infinity) * ratio;
      }
    }

    return _collectionRankingRows(totals);
  }

  Future<List<SalesPersonCustomerRanking>> fetchTopCustomersBySalesPerson({
    DateTime? from,
    DateTime? to,
    int limit = 10,
    bool scopeToCurrentSales = true,
    String? salesPerson,
    List<String>? salesPersons,
    String? parentSalesPerson,
    String? company,
  }) async {
    final explicitSalesPerson = salesPerson?.trim() ?? '';
    final explicitSalesPersons = salesPersons
        ?.map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final scopedSalesPerson = explicitSalesPerson.isNotEmpty
        ? explicitSalesPerson
        : (explicitSalesPersons == null && scopeToCurrentSales
              ? await _salesPersonScopeName()
              : null);
    final selectedParentSalesPerson = parentSalesPerson?.trim() ?? '';
    final selectedCompany = company?.trim() ?? '';
    final orderRows = await _fetchAllResourcePages(
      doctype: 'Sales Order',
      fields: const [
        'name',
        'customer',
        'customer_name',
        'grand_total',
        'net_total',
        'transaction_date',
      ],
      filters: [
        ['docstatus', '!=', 2],
        if (selectedCompany.isNotEmpty) ['company', '=', selectedCompany],
        if (selectedParentSalesPerson.isNotEmpty)
          ['parent_sales_person', '=', selectedParentSalesPerson],
        if (from != null)
          ['transaction_date', '>=', DateRangePresets.toFrappeDate(from)],
        if (to != null)
          ['transaction_date', '<=', DateRangePresets.toFrappeDate(to)],
      ],
      orderBy: 'transaction_date desc, name desc',
      maxRows: null,
    );
    if (orderRows.isEmpty) return const [];

    final orderData = <String, Map<String, dynamic>>{};
    for (final order in orderRows) {
      final id = order['name']?.toString() ?? '';
      if (id.isEmpty) continue;
      orderData[id] = order;
    }
    if (orderData.isEmpty) return const [];

    final orderDocuments = await _fetchDocumentsInBatches(
      'Sales Order',
      orderData.keys,
    );
    final totals = <String, _CustomerSalesTotal>{};
    for (final entry in orderData.entries) {
      final document = orderDocuments[entry.key];
      if (document == null) continue;
      final order = entry.value;
      final amount = NumParse.asDouble(
        order['grand_total'] ?? order['net_total'],
      ).clamp(0, double.infinity);
      if (amount <= 0) continue;
      final customer = order['customer']?.toString() ?? '';
      if (customer.isEmpty) continue;
      final customerName =
          order['customer_name']?.toString().trim().isNotEmpty == true
          ? order['customer_name']!.toString()
          : customer;

      for (final team in _documentChildRows(document['sales_team'])) {
        final salesPerson = team['sales_person']?.toString() ?? '';
        if (salesPerson.isEmpty) continue;
        if (explicitSalesPersons != null &&
            !explicitSalesPersons.contains(salesPerson)) {
          continue;
        }
        if (scopedSalesPerson != null && salesPerson != scopedSalesPerson) {
          continue;
        }
        final percentage = NumParse.asDouble(team['allocated_percentage']);
        final ratio = percentage > 0 ? percentage / 100 : 1.0;
        final key = '$salesPerson\t$customer';
        final previous = totals[key];
        totals[key] = _CustomerSalesTotal(
          salesPerson: salesPerson,
          customer: customer,
          customerName: customerName,
          amount: (previous?.amount ?? 0) + amount * ratio,
          orderCount: (previous?.orderCount ?? 0) + 1,
        );
      }
    }

    final sorted = totals.values.toList()
      ..sort((a, b) {
        final amountComparison = b.amount.compareTo(a.amount);
        if (amountComparison != 0) return amountComparison;
        final salesComparison = a.salesPerson.compareTo(b.salesPerson);
        if (salesComparison != 0) return salesComparison;
        return a.customerName.compareTo(b.customerName);
      });

    return [
      for (var index = 0; index < sorted.take(limit).length; index++)
        SalesPersonCustomerRanking(
          salesPerson: sorted[index].salesPerson,
          customer: sorted[index].customer,
          customerName: sorted[index].customerName,
          amount: sorted[index].amount,
          orderCount: sorted[index].orderCount,
          rank: index + 1,
        ),
    ];
  }

  Future<DailySalesReport> fetchDailySalesReport({
    required String doctype,
    DateTime? date,
    DateTime? from,
    DateTime? to,
    String? salesPerson,
    List<String>? salesPersons,
    String? parentSalesPerson,
    String? company,
  }) async {
    final normalizedDoctype = switch (doctype.trim().toLowerCase()) {
      'delivery note' || 'dn' => 'Delivery Note',
      'sales invoice' || 'si' => 'Sales Invoice',
      _ => 'Sales Order',
    };
    final dateField = normalizedDoctype == 'Sales Order'
        ? 'transaction_date'
        : 'posting_date';
    final selectedDate = date ?? DateTime.now();
    final selectedFrom = from ?? selectedDate;
    final selectedTo = to ?? selectedDate;
    final scopeFilters = await _salesDocumentScopeFilters(normalizedDoctype);
    final explicitSalesPerson = salesPerson?.trim() ?? '';
    final explicitSalesPersons = salesPersons
        ?.map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final scopedSalesPerson = explicitSalesPerson.isNotEmpty
        ? explicitSalesPerson
        : (explicitSalesPersons == null && _shouldScopeSalesData
              ? await _salesPersonScopeName()
              : null);
    final selectedParentSalesPerson = parentSalesPerson?.trim() ?? '';
    final selectedCompany = company?.trim() ?? '';
    final rows = await _fetchAllResourcePages(
      doctype: normalizedDoctype,
      fields: [
        'name',
        'customer',
        'customer_name',
        'company',
        'grand_total',
        'net_total',
        dateField,
      ],
      filters: [
        ['docstatus', '!=', 2],
        [dateField, '>=', DateRangePresets.toFrappeDate(selectedFrom)],
        [dateField, '<=', DateRangePresets.toFrappeDate(selectedTo)],
        if (selectedCompany.isNotEmpty) ['company', '=', selectedCompany],
        if (selectedParentSalesPerson.isNotEmpty)
          ['parent_sales_person', '=', selectedParentSalesPerson],
        ...?scopeFilters,
      ],
      orderBy: '$dateField desc, name desc',
      maxRows: null,
    );
    if (rows.isEmpty) return const DailySalesReport();

    final documentIds = rows
        .map((row) => row['name']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (documentIds.isEmpty) return const DailySalesReport();

    final documents = await _fetchDocumentsInBatches(
      normalizedDoctype,
      documentIds,
    );
    final itemTotals = <String, _DailySalesMutable>{};
    final customerTotals = <String, _DailyCustomerMutable>{};

    for (final id in documentIds) {
      final document = documents[id];
      if (document == null) continue;
      if (scopedSalesPerson != null) {
        final belongsToSales = _documentChildRows(
          document['sales_team'],
        ).any((row) => row['sales_person']?.toString() == scopedSalesPerson);
        if (!belongsToSales) continue;
      }
      if (explicitSalesPersons != null) {
        final belongsToGroup = _documentChildRows(document['sales_team']).any(
          (row) => explicitSalesPersons.contains(
            row['sales_person']?.toString() ?? '',
          ),
        );
        if (!belongsToGroup) continue;
      }

      final customer =
          document['customer_name']?.toString().trim().isNotEmpty == true
          ? document['customer_name']!.toString()
          : (document['customer']?.toString() ?? 'Unknown Customer');
      final customerBucket = customerTotals.putIfAbsent(
        customer,
        () => _DailyCustomerMutable(customer),
      );

      for (final item in _documentChildRows(document['items'])) {
        final label = _dailySalesItemLabel(item);
        if (label.isEmpty) continue;
        final itemGroup = _cleanDailyItemLabel(item['item_group']);
        final qty = NumParse.asDouble(item['qty'] ?? item['stock_qty']);
        if (qty == 0) continue;
        final amount = _dailySalesItemAmount(item, qty);

        itemTotals
            .putIfAbsent(
              label,
              () => _DailySalesMutable(label, itemGroup: itemGroup),
            )
            .add(qty: qty, amount: amount);
        customerBucket.add(
          label: label,
          itemGroup: itemGroup,
          qty: qty,
          amount: amount,
        );
      }
    }

    final itemRows = itemTotals.values.map((row) => row.toSummary()).toList()
      ..sort((a, b) {
        final amountComparison = b.amount.compareTo(a.amount);
        if (amountComparison != 0) return amountComparison;
        return a.itemLabel.compareTo(b.itemLabel);
      });
    final customerRows =
        customerTotals.values.map((row) => row.toSummary()).toList()
          ..sort((a, b) {
            final amountComparison = b.totalAmount.compareTo(a.totalAmount);
            if (amountComparison != 0) return amountComparison;
            return a.customer.compareTo(b.customer);
          });
    final totalQty = itemRows.fold<double>(0, (sum, row) => sum + row.qty);
    final totalAmount = itemRows.fold<double>(
      0,
      (sum, row) => sum + row.amount,
    );

    return DailySalesReport(
      items: itemRows,
      customers: customerRows,
      totalQty: totalQty,
      totalAmount: totalAmount,
    );
  }

  double _dailySalesItemAmount(Map<String, dynamic> item, double qty) {
    final amount = NumParse.asDouble(item['net_amount'] ?? item['amount']);
    if (amount != 0) return amount;
    final rate = NumParse.asDouble(item['net_rate'] ?? item['rate']);
    return qty * rate;
  }

  String _dailySalesItemLabel(Map<String, dynamic> item) {
    final itemName = _cleanDailyItemLabel(item['item_name']);
    if (itemName.isNotEmpty) return itemName;

    final itemCode = _cleanDailyItemLabel(item['item_code']);
    if (itemCode.isNotEmpty) return itemCode;

    return 'Item Lainnya';
  }

  String _cleanDailyItemLabel(Object? value) {
    return (value?.toString() ?? '')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<CollectionRanking> _collectionRankingRows(
    Map<String, double> totals,
  ) {
    final sorted = totals.entries.toList()
      ..sort((a, b) {
        final valueComparison = b.value.compareTo(a.value);
        return valueComparison != 0 ? valueComparison : a.key.compareTo(b.key);
      });
    return [
      for (var index = 0; index < sorted.length; index++)
        CollectionRanking(
          salesPerson: sorted[index].key,
          amount: sorted[index].value,
          rank: index + 1,
        ),
    ];
  }

  Future<List<CollectionPayment>> fetchCollectionPayments({
    DateTime? from,
    DateTime? to,
    bool scopeToCurrentSales = true,
  }) async {
    final key = _collectionPaymentsCacheKey(
      from: from,
      to: to,
      scopeToCurrentSales: scopeToCurrentSales,
    );
    final cachedRows = await _readDbRowList(key);
    if (cachedRows != null) {
      return cachedRows.map(_collectionPaymentFromCacheJson).toList();
    }
    final inFlight = _collectionPaymentInFlight[key];
    if (inFlight != null) return inFlight;
    final request = _fetchCollectionPaymentsFromErp(
      from: from,
      to: to,
      scopeToCurrentSales: scopeToCurrentSales,
    );
    _collectionPaymentInFlight[key] = request;
    try {
      final payments = await request;
      await _writeDbRowList(
        key,
        payments.map(_collectionPaymentToCacheJson).toList(),
        ttl: _collectionCacheTtl,
      );
      return payments;
    } finally {
      if (identical(_collectionPaymentInFlight[key], request)) {
        _collectionPaymentInFlight.remove(key);
      }
    }
  }

  Future<List<CollectionPayment>> _fetchCollectionPaymentsFromErp({
    DateTime? from,
    DateTime? to,
    bool scopeToCurrentSales = true,
  }) async {
    Set<String>? permittedCustomers;
    if (_shouldScopeSalesData && scopeToCurrentSales) {
      final customers = await fetchSalesCustomers();
      permittedCustomers = customers.map((customer) => customer.id).toSet();
      if (permittedCustomers.isEmpty) return const [];
    }
    final company = _sellingCompanyFilter.trim();

    final rows = await _fetchAllResourcePages(
      doctype: 'Payment Entry',
      fields: const [
        'name',
        'party',
        'party_name',
        'company',
        'posting_date',
        'paid_amount',
        'received_amount',
        'reference_no',
        'remarks',
      ],
      filters: [
        ['docstatus', '=', 1],
        ['payment_type', '=', 'Receive'],
        ['party_type', '=', 'Customer'],
        if (company.isNotEmpty) ['company', '=', company],
        if (from != null)
          ['posting_date', '>=', DateRangePresets.toFrappeDate(from)],
        if (to != null)
          ['posting_date', '<=', DateRangePresets.toFrappeDate(to)],
      ],
      orderBy: 'posting_date desc, name desc',
      maxRows: null,
    );
    final payments = rows
        .where(
          (row) =>
              permittedCustomers == null ||
              permittedCustomers.contains(row['party']?.toString() ?? ''),
        )
        .map(CollectionPayment.fromJson)
        .where((payment) => payment.id.isNotEmpty)
        .toList();
    if (payments.isEmpty) return payments;

    final documents = await _fetchDocumentsInBatches(
      'Payment Entry',
      payments.map((payment) => payment.id),
    );
    return payments.map((payment) {
      final document = documents[payment.id];
      if (document != null) {
        final references = _documentChildRows(
          document['references'],
        ).map(CollectionPaymentReference.fromJson).toList();
        return payment.copyWithReferences(references);
      }
      return payment;
    }).toList();
  }

  Map<String, dynamic> _collectionPaymentToCacheJson(
    CollectionPayment payment,
  ) => {
    'name': payment.id,
    'party': payment.customer,
    'party_name': payment.customerName,
    'posting_date': payment.postingDate,
    'received_amount': payment.amount,
    'reference_no': payment.referenceNo,
    'remarks': payment.remarks,
    'references': payment.references
        .map(
          (reference) => {
            'reference_doctype': reference.doctype,
            'reference_name': reference.documentName,
            'allocated_amount': reference.allocatedAmount,
          },
        )
        .toList(),
  };

  CollectionPayment _collectionPaymentFromCacheJson(Map<String, dynamic> json) {
    return CollectionPayment.fromJson(json);
  }

  String _collectionPaymentsCacheKey({
    DateTime? from,
    DateTime? to,
    required bool scopeToCurrentSales,
  }) {
    return [
      _collectionDbCachePrefix,
      selectedSiteBaseUrl.trim(),
      _currentUser?.trim() ?? '',
      'payments',
      _sellingCompanyFilter.trim(),
      scopeToCurrentSales,
      _shouldScopeSalesData,
      _currentSalesPerson?.trim() ?? '',
      from == null ? '' : DateRangePresets.toFrappeDate(from),
      to == null ? '' : DateRangePresets.toFrappeDate(to),
    ].join('|');
  }

  Future<Map<String, List<SalesInvoicePaymentAllocation>>>
  fetchSalesInvoicePaymentAllocations(Iterable<String> invoiceIds) async {
    final ids = invoiceIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const {};
    final key = _collectionAllocationsCacheKey(ids);
    final cachedRows = await _readDbRowList(key);
    if (cachedRows != null) {
      return _groupCollectionAllocations(cachedRows);
    }
    final inFlight = _collectionAllocationInFlight[key];
    if (inFlight != null) return inFlight;
    final request = _fetchSalesInvoicePaymentAllocationsFromErp(ids);
    _collectionAllocationInFlight[key] = request;
    try {
      final allocations = await request;
      await _writeDbRowList(key, [
        for (final entries in allocations.values)
          ...entries.map(_collectionAllocationToCacheJson),
      ], ttl: _collectionCacheTtl);
      return allocations;
    } finally {
      if (identical(_collectionAllocationInFlight[key], request)) {
        _collectionAllocationInFlight.remove(key);
      }
    }
  }

  Future<Map<String, List<SalesInvoicePaymentAllocation>>>
  _fetchSalesInvoicePaymentAllocationsFromErp(List<String> ids) async {
    try {
      final references = await _fetchAllResourcePages(
        doctype: 'Payment Entry Reference',
        fields: const [
          'parent',
          'reference_doctype',
          'reference_name',
          'allocated_amount',
        ],
        filters: [
          ['reference_doctype', '=', 'Sales Invoice'],
          ['reference_name', 'in', ids],
          ['allocated_amount', '>', 0],
        ],
        maxRows: null,
      );
      if (references.isEmpty) return const {};

      final paymentIds = references
          .map((row) => row['parent']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final paymentRows = paymentIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _fetchAllResourcePages(
              doctype: 'Payment Entry',
              fields: const [
                'name',
                'posting_date',
                'mode_of_payment',
                'reference_no',
                'docstatus',
              ],
              filters: [
                ['name', 'in', paymentIds],
                ['docstatus', '=', 1],
              ],
              maxRows: null,
            );
      final paymentById = {
        for (final payment in paymentRows)
          payment['name']?.toString() ?? '': payment,
      };

      final grouped = <String, List<SalesInvoicePaymentAllocation>>{};
      for (final row in references) {
        final parent = row['parent']?.toString() ?? '';
        final payment = paymentById[parent];
        if (payment == null) continue;
        final allocation = SalesInvoicePaymentAllocation.fromJson(
          row,
          paymentEntry: payment,
        );
        if (allocation.invoice.isEmpty || allocation.allocatedAmount <= 0) {
          continue;
        }
        grouped.putIfAbsent(allocation.invoice, () => []).add(allocation);
      }
      for (final rows in grouped.values) {
        rows.sort((a, b) {
          final dateComparison = b.postingDate.compareTo(a.postingDate);
          if (dateComparison != 0) return dateComparison;
          return b.paymentEntry.compareTo(a.paymentEntry);
        });
      }
      return grouped;
    } catch (_) {
      return const {};
    }
  }

  Map<String, dynamic> _collectionAllocationToCacheJson(
    SalesInvoicePaymentAllocation allocation,
  ) => {
    'parent': allocation.paymentEntry,
    'reference_name': allocation.invoice,
    'allocated_amount': allocation.allocatedAmount,
    'posting_date': allocation.postingDate,
    'mode_of_payment': allocation.modeOfPayment,
    'reference_no': allocation.referenceNo,
  };

  Map<String, List<SalesInvoicePaymentAllocation>> _groupCollectionAllocations(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, List<SalesInvoicePaymentAllocation>>{};
    for (final row in rows) {
      final allocation = SalesInvoicePaymentAllocation.fromJson(
        row,
        paymentEntry: row,
      );
      if (allocation.invoice.isEmpty || allocation.allocatedAmount <= 0) {
        continue;
      }
      grouped.putIfAbsent(allocation.invoice, () => []).add(allocation);
    }
    return grouped;
  }

  String _collectionAllocationsCacheKey(List<String> ids) {
    final sorted = [...ids]..sort();
    return [
      _collectionDbCachePrefix,
      selectedSiteBaseUrl.trim(),
      _currentUser?.trim() ?? '',
      'allocations',
      sorted.join(','),
    ].join('|');
  }

  bool get _isSalesVisitCacheFresh {
    final cachedAt = _salesVisitCacheAt;
    if (cachedAt == null) return false;
    return DateTime.now().difference(cachedAt) < _salesVisitCacheTtl;
  }

  Future<List<SalesVisit>> fetchSalesVisits({bool forceRefresh = false}) async {
    if (!forceRefresh && _isSalesVisitCacheFresh) {
      return List<SalesVisit>.unmodifiable(_salesVisitCache);
    }
    final inFlight = _salesVisitFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchSalesVisitsFromErp();
    _salesVisitFetchInFlight = request;
    try {
      final visits = await request;
      _salesVisitCache = List<SalesVisit>.unmodifiable(visits);
      _salesVisitCacheAt = DateTime.now();
      return _salesVisitCache;
    } finally {
      if (identical(_salesVisitFetchInFlight, request)) {
        _salesVisitFetchInFlight = null;
      }
    }
  }

  Future<List<SalesVisit>> _fetchSalesVisitsFromErp() async {
    final filters = _shouldScopeSalesData
        ? [
            ['owner', '=', _currentUser ?? '__unmapped_sales_user__'],
          ]
        : null;
    final rows = await _fetchSalesVisitRows(
      filters: filters,
      limit: 300,
      orderBy: 'modified desc, name desc',
    );
    final visits = await _hydrateSalesVisitCheckins(
      rows.map(SalesVisit.fromJson).toList(),
    );
    if (_shouldScopeSalesData) {
      _activeSalesVisit = null;
      for (final visit in visits) {
        if (visit.isActive) {
          _activeSalesVisit = visit;
          break;
        }
      }
    }
    return visits;
  }

  void _invalidateSalesVisitCache() {
    _salesVisitCacheAt = null;
    _salesVisitFetchInFlight = null;
  }

  Future<List<Map<String, dynamic>>> _fetchSalesVisitRows({
    required List<List<dynamic>>? filters,
    required int limit,
    required String orderBy,
  }) async {
    Object? lastError;
    for (final fieldSet in <List<String>>[
      const [
        'name',
        'customer',
        'customer_name',
        'employee',
        'employee_checkin_in',
        'employee_checkin_out',
        'check_in_time',
        'check_out_time',
        'status',
        'notes',
        'sales_person',
        'journey_start_time',
        'address',
        'target_latitude',
        'target_longitude',
        'check_in_latitude',
        'check_in_longitude',
        'check_out_latitude',
        'check_out_longitude',
        'check_in_distance',
      ],
      const [
        'name',
        'customer',
        'customer_name',
        'employee',
        'employee_checkin_in',
        'employee_checkin_out',
        'check_in_time',
        'check_out_time',
        'status',
        'sales_person',
      ],
      const [
        'name',
        'customer',
        'address',
        'sales_person',
        'employee',
        'employee_checkin_in',
        'employee_checkin_out',
        'modified',
      ],
      const ['name', 'customer', 'customer_name', 'status', 'modified'],
      const ['name', 'modified'],
      const ['name'],
    ]) {
      for (final candidateOrderBy in <String>[
        orderBy,
        'modified desc, name desc',
        'name desc',
      ]) {
        for (final scopedFilters in <List<List<dynamic>>?>[filters, null]) {
          try {
            return await _fetchSalesVisitRowsWithFallback(
              fieldSet,
              filters: scopedFilters,
              limit: limit,
              orderBy: candidateOrderBy,
            );
          } catch (error) {
            lastError = error;
            if (!_looksLikeVisitListIssue(error)) rethrow;
          }
        }
      }
    }
    throw lastError ?? Exception('Gagal membaca Sales Visit.');
  }

  Future<List<SalesVisit>> _hydrateSalesVisitCheckins(
    List<SalesVisit> visits,
  ) async {
    final checkinIds = <String>{
      for (final visit in visits) ...[
        if (visit.employeeCheckinIn.trim().isNotEmpty)
          visit.employeeCheckinIn.trim(),
        if (visit.employeeCheckinOut.trim().isNotEmpty)
          visit.employeeCheckinOut.trim(),
      ],
    }.toList();
    if (checkinIds.isEmpty) return visits;
    try {
      List<Map<String, dynamic>> rows;
      try {
        rows = await _fetchAllResourcePages(
          doctype: 'Employee Checkin',
          fields: const [
            'name',
            'time',
            'log_type',
            'device_id',
            'latitude',
            'longitude',
          ],
          filters: [
            ['name', 'in', checkinIds],
          ],
          orderBy: 'time desc, name desc',
          maxRows: checkinIds.length,
        );
      } catch (_) {
        rows = await _fetchAllResourcePages(
          doctype: 'Employee Checkin',
          fields: const ['name', 'time', 'log_type', 'device_id'],
          filters: [
            ['name', 'in', checkinIds],
          ],
          orderBy: 'time desc, name desc',
          maxRows: checkinIds.length,
        );
      }
      final byName = {
        for (final row in rows) row['name']?.toString() ?? '': row,
      };
      return visits.map((visit) {
        final checkIn = byName[visit.employeeCheckinIn];
        final checkOut = byName[visit.employeeCheckinOut];
        return visit.copyWith(
          checkInTime: checkIn?['time']?.toString(),
          checkOutTime: checkOut?['time']?.toString(),
          checkInLatitude: NumParse.asDouble(checkIn?['latitude']),
          checkInLongitude: NumParse.asDouble(checkIn?['longitude']),
          checkOutLatitude: NumParse.asDouble(checkOut?['latitude']),
          checkOutLongitude: NumParse.asDouble(checkOut?['longitude']),
        );
      }).toList();
    } catch (_) {
      return visits;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSalesVisitRowsWithFallback(
    List<String> fields, {
    required List<List<dynamic>>? filters,
    required int limit,
    required String orderBy,
  }) async {
    Object? resourceError;
    try {
      return await _fetchAllResourcePages(
        doctype: 'Sales Visit',
        fields: fields,
        filters: filters,
        orderBy: orderBy,
        maxRows: limit,
      );
    } catch (error) {
      resourceError = error;
      if (!_looksLikeVisitListIssue(error)) rethrow;
    }

    try {
      return await _frappeService.fetchReportView(
        'Sales Visit',
        fields: fields,
        filters: filters,
        orderBy: orderBy,
        limit: limit,
        limitStart: 0,
      );
    } catch (reportError) {
      throw Exception(
        'Resource: ${_cleanShortFrappeError(resourceError)}. '
        'ReportView: ${_cleanShortFrappeError(reportError)}',
      );
    }
  }

  bool _looksLikeVisitListIssue(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('akses erpnext tidak diizinkan') ||
        message.contains('permissionerror') ||
        message.contains('not permitted') ||
        message.contains('field not permitted') ||
        message.contains('no permitted fields') ||
        message.contains('unknown column') ||
        message.contains('order_by') ||
        message.contains('does not exist');
  }

  Future<CustomerVisitLocation> fetchCustomerVisitLocation(String customer) {
    return _customerService.fetchVisitLocation(customer);
  }

  Future<VisitLocationPoint> getCurrentVisitLocation() async {
    final point = await _visitLocationService.currentPosition();
    _latestVisitLocation = point;
    notifyListeners();
    return point;
  }

  double visitDistanceTo(
    CustomerVisitLocation target,
    VisitLocationPoint from,
  ) {
    return _visitLocationService.distanceMeters(
      fromLatitude: from.latitude,
      fromLongitude: from.longitude,
      toLatitude: target.latitude,
      toLongitude: target.longitude,
    );
  }

  Future<SalesVisit> checkInSalesCustomer({
    required String customer,
    required CustomerVisitLocation target,
    required String photoPath,
  }) async {
    if (_activeSalesVisit != null) {
      throw Exception('Selesaikan check-in aktif sebelum memulai yang baru.');
    }
    final point = await getCurrentVisitLocation();
    final distance = visitDistanceTo(target, point);
    if (point.accuracy > 50) {
      throw Exception(
        'Akurasi GPS ${point.accuracy.toStringAsFixed(0)} meter terlalu rendah.',
      );
    }
    if (distance > target.geofenceRadius) {
      throw Exception(
        'Anda masih ${distance.toStringAsFixed(0)} meter dari customer. '
        'Check-in maksimal ${target.geofenceRadius.toStringAsFixed(0)} meter.',
      );
    }
    final employee = _currentEmployee?.trim() ?? '';
    if (employee.isEmpty) {
      throw Exception(
        'User belum terhubung ke Employee. Isi Employee.user_id di ERPNext.',
      );
    }
    final now = _formatFrappeDateTime(DateTime.now());
    final created = await _frappeService.createDocument('Sales Visit', {
      'customer': customer,
      'address': target.addressId,
      if (_currentSalesPerson?.isNotEmpty == true)
        'sales_person': _currentSalesPerson,
      'employee': employee,
    });
    final visit = SalesVisit.fromJson(created);
    final checkin = await _createEmployeeCheckin(
      employee: employee,
      logType: 'IN',
      time: now,
      point: point,
      target: target,
      distance: distance,
      photoPath: photoPath,
    );
    await _frappeService.updateDocument('Sales Visit', visit.id, {
      'employee_checkin_in': checkin['name']?.toString() ?? '',
    });
    final updated = SalesVisit.fromJson(
      await _frappeService.fetchDocument('Sales Visit', visit.id),
    ).copyWith(checkInTime: checkin['time']?.toString() ?? now);
    _activeSalesVisit = updated;
    _salesVisitCache = List<SalesVisit>.unmodifiable([
      updated,
      ..._salesVisitCache.where((visit) => visit.id != updated.id),
    ]);
    _salesVisitCacheAt = DateTime.now();
    notifyListeners();
    return updated;
  }

  Future<void> checkOutSalesVisit(String visitId) async {
    final point = await getCurrentVisitLocation();
    SalesVisit? activeVisit = _activeSalesVisit?.id == visitId
        ? _activeSalesVisit
        : null;
    if (activeVisit == null) {
      for (final visit in _salesVisitCache) {
        if (visit.id == visitId) {
          activeVisit = visit;
          break;
        }
      }
    }
    final employee = activeVisit?.employee.trim().isNotEmpty == true
        ? activeVisit!.employee.trim()
        : (_currentEmployee?.trim() ?? '');
    if (employee.isEmpty) {
      throw Exception(
        'User belum terhubung ke Employee. Isi Employee.user_id di ERPNext.',
      );
    }
    final checkout = await _createEmployeeCheckin(
      employee: employee,
      logType: 'OUT',
      time: _formatFrappeDateTime(DateTime.now()),
      point: point,
      target: null,
      distance: null,
    );
    await _frappeService.updateDocument('Sales Visit', visitId, {
      'employee_checkin_out': checkout['name']?.toString() ?? '',
    });
    await _visitLocationService.stopTracking();
    _activeSalesVisit = null;
    _invalidateSalesVisitCache();
    notifyListeners();
  }

  Future<List<SalesVisit>> fetchSpgVisits({bool forceRefresh = false}) async {
    final filters = mobileAccess.isSpg
        ? [
            ['owner', '=', _currentUser ?? '__unmapped_spg_user__'],
          ]
        : null;
    final rows = await _fetchVisitRows(
      doctype: 'SPG Visit',
      filters: filters,
      limit: 300,
      orderBy: 'modified desc, name desc',
      fieldSets: const [
        [
          'name',
          'customer',
          'address',
          'employee',
          'employee_checkin_in',
          'employee_checkin_out',
          'modified',
        ],
        [
          'name',
          'customer',
          'employee',
          'employee_checkin_in',
          'employee_checkin_out',
          'modified',
        ],
        ['name', 'customer', 'employee', 'modified'],
        ['name', 'modified'],
        ['name'],
      ],
    );
    final visits = await _hydrateSalesVisitCheckins(
      rows
          .map(
            (row) => SalesVisit.fromJson({
              ...row,
              'customer_name':
                  row['customer_name'] ?? row['customer'] ?? row['name'] ?? '',
            }),
          )
          .toList(),
    );
    _activeSpgVisit = null;
    for (final visit in visits) {
      if (visit.isActive) {
        _activeSpgVisit = visit;
        break;
      }
    }
    return visits;
  }

  Future<SalesVisit> checkInSpgCustomer({
    required String customer,
    required CustomerVisitLocation target,
    required String photoPath,
  }) async {
    if (_activeSpgVisit != null) {
      throw Exception(
        'Selesaikan check-in SPG aktif sebelum memulai yang baru.',
      );
    }
    final point = await getCurrentVisitLocation();
    final distance = visitDistanceTo(target, point);
    if (point.accuracy > 50) {
      throw Exception(
        'Akurasi GPS ${point.accuracy.toStringAsFixed(0)} meter terlalu rendah.',
      );
    }
    if (distance > target.geofenceRadius) {
      throw Exception(
        'Anda masih ${distance.toStringAsFixed(0)} meter dari customer. '
        'Check-in maksimal ${target.geofenceRadius.toStringAsFixed(0)} meter.',
      );
    }
    await _ensureCurrentEmployee();
    final employee = _currentEmployee?.trim() ?? '';
    await _ensureSpgCustomerAssigned(
      customer: customer.trim(),
      employee: employee,
    );
    final now = _formatFrappeDateTime(DateTime.now());
    final created = await _frappeService.createDocument('SPG Visit', {
      'customer': customer,
      'address': target.addressId,
      'employee': employee,
    });
    final visit = SalesVisit.fromJson({
      ...created,
      'customer_name': created['customer'] ?? customer,
    });
    final checkin = await _createEmployeeCheckin(
      employee: employee,
      logType: 'IN',
      time: now,
      point: point,
      target: target,
      distance: distance,
      photoPath: photoPath,
    );
    await _frappeService.updateDocument('SPG Visit', visit.id, {
      'employee_checkin_in': checkin['name']?.toString() ?? '',
    });
    final updated = SalesVisit.fromJson({
      ...await _frappeService.fetchDocument('SPG Visit', visit.id),
      'customer_name': customer,
    }).copyWith(checkInTime: checkin['time']?.toString() ?? now);
    _activeSpgVisit = updated;
    notifyListeners();
    return updated;
  }

  Future<void> checkOutSpgVisit(String visitId) async {
    final point = await getCurrentVisitLocation();
    final activeVisit = _activeSpgVisit?.id == visitId ? _activeSpgVisit : null;
    var employee = activeVisit?.employee.trim().isNotEmpty == true
        ? activeVisit!.employee.trim()
        : (_currentEmployee?.trim() ?? '');
    if (employee.isEmpty) {
      await _ensureCurrentEmployee();
      employee = _currentEmployee?.trim() ?? '';
    }
    if (employee.isEmpty) {
      throw Exception(
        'User belum terhubung ke Employee melalui field User ID.',
      );
    }
    final checkout = await _createEmployeeCheckin(
      employee: employee,
      logType: 'OUT',
      time: _formatFrappeDateTime(DateTime.now()),
      point: point,
      target: null,
      distance: null,
    );
    await _frappeService.updateDocument('SPG Visit', visitId, {
      'employee_checkin_out': checkout['name']?.toString() ?? '',
    });
    await _visitLocationService.stopTracking();
    _activeSpgVisit = null;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> fetchSpgDailyActivities({
    bool forceRefresh = false,
  }) async {
    final filters = <List<dynamic>>[
      if (mobileAccess.isSpg)
        ['owner', '=', _currentUser ?? '__unmapped_spg_user__'],
    ];
    return _fetchVisitRows(
      doctype: 'SPG Daily Activity',
      fieldSets: const [
        ['name', 'employee', 'customer', 'activity_date', 'notes', 'modified'],
        ['name', 'employee', 'customer', 'activity_date', 'modified'],
        ['name', 'modified'],
        ['name'],
      ],
      filters: filters.isEmpty ? null : filters,
      orderBy: 'activity_date desc, modified desc',
      limit: 100,
    );
  }

  Future<Map<String, dynamic>> fetchSpgDailyActivityDetail(String name) {
    return _frappeService.fetchDocument('SPG Daily Activity', name);
  }

  Future<List<Map<String, dynamic>>> fetchEmployeeOptions({
    String query = '',
  }) async {
    if (_isSampleMode) {
      return const [
        {'name': 'EMP-SAMPLE-001', 'employee_name': 'Sample SPG'},
        {'name': 'EMP-SAMPLE-002', 'employee_name': 'Sample Sales'},
      ];
    }
    final normalized = query.trim();
    return _fetchResourceWithFieldFallback(
      doctype: 'Employee',
      fields: const ['name', 'employee_name', 'user_id', 'status'],
      filters: [
        if (normalized.isNotEmpty) ['employee_name', 'like', '%$normalized%'],
      ],
      orderBy: 'employee_name asc, name asc',
      limit: 100,
    ).then(
      (rows) => rows
          .where(
            (row) =>
                row['status']?.toString().trim().isEmpty != false ||
                row['status']?.toString() == 'Active',
          )
          .toList(),
    );
  }

  Future<List<SpgCustomerOption>> fetchSpgCustomers({String query = ''}) async {
    if (_isSampleMode) {
      return const [
        SpgCustomerOption(id: 'CUST-SAMPLE-001', name: 'Sample Customer'),
        SpgCustomerOption(id: 'CUST-SAMPLE-002', name: 'Sample Outlet'),
      ];
    }
    final normalized = query.trim();
    final rows = await _fetchResourceWithFieldFallback(
      doctype: 'Customer',
      fields: const ['name', 'customer_name', 'primary_address'],
      filters: [
        if (normalized.isNotEmpty) ['customer_name', 'like', '%$normalized%'],
      ],
      orderBy: 'customer_name asc, name asc',
      limit: 200,
    );
    return rows
        .map((row) => SpgCustomerOption.fromJson(row))
        .where((customer) => customer.id.trim().isNotEmpty)
        .toList();
  }

  Future<List<SpgCustomerOption>> fetchScheduledSpgCustomers({
    String query = '',
    String? employee,
  }) async {
    if (_isSampleMode) {
      return fetchSpgCustomers(query: query);
    }

    var selectedEmployee = employee?.trim() ?? '';
    if (selectedEmployee.isEmpty && !mobileAccess.canSelectAnyEmployee) {
      await _ensureCurrentEmployee();
      selectedEmployee = _currentEmployee?.trim() ?? '';
    }
    if (selectedEmployee.isEmpty) return const [];

    final today = _formatFrappeDate(DateTime.now());
    final docs = await _fetchActiveSpgScheduleDocuments(today);
    if (docs.isEmpty) return const [];

    final customerIds = <String>{};
    for (final doc in docs) {
      if (!_spgScheduleHasEmployee(doc, selectedEmployee)) continue;
      for (final row in _spgScheduleCustomerRows(doc)) {
        final customer = _firstString(row, const [
          'customer',
          'customer_name',
          'customer_id',
        ]);
        if (customer.isNotEmpty) customerIds.add(customer);
      }
    }
    if (customerIds.isEmpty) return const [];

    final normalized = query.trim();
    final rows = await _fetchResourceWithFieldFallback(
      doctype: 'Customer',
      fields: const ['name', 'customer_name', 'primary_address'],
      filters: [
        ['name', 'in', customerIds.toList()],
      ],
      orFilters: normalized.isEmpty
          ? null
          : [
              ['name', 'like', '%$normalized%'],
              ['customer_name', 'like', '%$normalized%'],
            ],
      orderBy: 'customer_name asc, name asc',
      limit: customerIds.length,
    );

    final options =
        rows
            .map((row) => SpgCustomerOption.fromJson(row))
            .where((customer) => customer.id.trim().isNotEmpty)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return options;
  }

  Future<List<Map<String, dynamic>>> _fetchActiveSpgScheduleDocuments(
    String today,
  ) async {
    Future<List<Map<String, dynamic>>> fetchScheduleRows({
      List<List<dynamic>>? filters,
    }) {
      return _fetchResourceWithFieldFallback(
        doctype: 'SPG Schedule',
        fields: const ['name', 'start_date', 'end_date', 'modified'],
        filters: filters,
        orderBy: 'modified desc',
        limit: 100,
      );
    }

    var schedules = await fetchScheduleRows(
      filters: [
        ['start_date', '<=', today],
        ['end_date', '>=', today],
      ],
    );
    if (schedules.isEmpty) {
      schedules = await fetchScheduleRows();
    }

    final scheduleNames = schedules
        .where((row) => _spgScheduleDateMatches(row, today))
        .map((row) => row['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    if (scheduleNames.isEmpty) return const [];

    final docs = await Future.wait(
      scheduleNames.map((name) async {
        try {
          return await _frappeService.fetchDocument('SPG Schedule', name);
        } catch (_) {
          return const <String, dynamic>{};
        }
      }),
    );
    return docs
        .where((doc) => doc.isNotEmpty && _spgScheduleDateMatches(doc, today))
        .toList();
  }

  bool _spgScheduleDateMatches(Map<String, dynamic> doc, String today) {
    final todayDate = _parseLooseDate(today);
    final start = _parseLooseDate(doc['start_date']?.toString() ?? '');
    final end = _parseLooseDate(doc['end_date']?.toString() ?? '');
    if (todayDate == null) return true;
    if (start != null && todayDate.isBefore(start)) return false;
    if (end != null && todayDate.isAfter(end)) return false;
    return true;
  }

  DateTime? _parseLooseDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(trimmed);
    if (iso != null) {
      return DateTime(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
      );
    }
    final local = RegExp(r'^(\d{2})-(\d{2})-(\d{4})').firstMatch(trimmed);
    if (local != null) {
      return DateTime(
        int.parse(local.group(3)!),
        int.parse(local.group(2)!),
        int.parse(local.group(1)!),
      );
    }
    return null;
  }

  Future<void> _ensureSpgCustomerAssigned({
    required String customer,
    required String employee,
  }) async {
    final assignedCustomers = await fetchScheduledSpgCustomers(
      employee: employee,
    );
    final exists = assignedCustomers.any((option) => option.id == customer);
    if (!exists) {
      throw Exception(
        'Customer tidak ada di SPG Schedule aktif untuk employee ini.',
      );
    }
  }

  bool _spgScheduleHasEmployee(Map<String, dynamic> doc, String employee) {
    for (final row in _spgScheduleEmployeeRows(doc)) {
      final rowEmployee = _firstString(row, const [
        'employee',
        'employe',
        'employe_name',
        'employee_name',
        'spg',
        'employee_id',
      ]);
      if (rowEmployee == employee) return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _spgScheduleCustomerRows(
    Map<String, dynamic> doc,
  ) {
    return _firstTable(doc, const [
      'table_bffa',
      'customer_detail',
      'customer_details',
      'customers',
      'customer_list',
      'customer_table',
    ]);
  }

  List<Map<String, dynamic>> _spgScheduleEmployeeRows(
    Map<String, dynamic> doc,
  ) {
    return _firstTable(doc, const [
      'table_cylv',
      'spg',
      'employee',
      'employees',
      'employee_detail',
      'employee_details',
      'spg_detail',
      'spg_details',
    ]);
  }

  List<Map<String, dynamic>> _firstTable(
    Map<String, dynamic> doc,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = doc[key];
      if (value is! List) continue;
      final rows = value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (rows.isNotEmpty) return rows;
    }
    return const [];
  }

  String _firstString(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<Map<String, dynamic>> createSpgDailyActivity({
    required String customer,
    required List<String> photoPaths,
    String? employee,
    String notes = '',
  }) async {
    var selectedEmployee = employee?.trim() ?? _currentEmployee?.trim() ?? '';
    if (selectedEmployee.isEmpty && !mobileAccess.canSelectAnyEmployee) {
      await _ensureCurrentEmployee();
      selectedEmployee = _currentEmployee?.trim() ?? '';
    }
    if (selectedEmployee.isEmpty) {
      throw Exception(
        mobileAccess.canSelectAnyEmployee
            ? 'Employee wajib dipilih.'
            : 'User belum terhubung ke Employee melalui field User ID.',
      );
    }
    if (customer.trim().isEmpty) {
      throw Exception('Customer wajib dipilih.');
    }
    if (photoPaths.isEmpty) {
      throw Exception('Minimal 1 foto aktivitas wajib diambil.');
    }
    await _ensureSpgCustomerAssigned(
      customer: customer.trim(),
      employee: selectedEmployee,
    );
    final today = _formatFrappeDate(DateTime.now());
    final created = await _frappeService.createDocument('SPG Daily Activity', {
      'employee': selectedEmployee,
      'customer': customer.trim(),
      'activity_date': today,
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    final name = created['name']?.toString() ?? '';
    if (name.isEmpty) return created;

    final rows = <Map<String, dynamic>>[];
    for (final path in photoPaths) {
      final uploaded = await _frappeService.uploadFile(
        filePath: path,
        doctype: 'SPG Daily Activity',
        documentName: name,
      );
      final fileUrl = uploaded['file_url']?.toString() ?? '';
      if (fileUrl.trim().isEmpty) continue;
      rows.add({
        'photo': fileUrl,
        'description': notes.trim(),
        'photo_time': _formatFrappeDateTime(DateTime.now()),
      });
    }
    if (rows.isNotEmpty) {
      await _frappeService.updateDocument('SPG Daily Activity', name, {
        'activity_photos': rows,
      });
    }
    return _frappeService.fetchDocument('SPG Daily Activity', name);
  }

  Future<List<Map<String, dynamic>>> fetchSpgDailyReports() {
    final filters = <List<dynamic>>[
      if (mobileAccess.isSpg)
        ['owner', '=', _currentUser ?? '__unmapped_spg_user__'],
    ];
    return _fetchVisitRows(
      doctype: 'SPG Daily Report',
      fieldSets: const [
        ['name', 'employee', 'customer', 'report_date', 'notes', 'modified'],
        ['name', 'employee', 'customer', 'report_date', 'modified'],
        ['name', 'modified'],
        ['name'],
      ],
      filters: filters.isEmpty ? null : filters,
      orderBy: 'report_date desc, modified desc',
      limit: 100,
    );
  }

  Future<Map<String, dynamic>> fetchSpgDailyReportDetail(String name) {
    return _frappeService.fetchDocument('SPG Daily Report', name);
  }

  Future<List<Map<String, dynamic>>> fetchSpgSellingItems(String query) {
    return fetchSellableItems(query: query);
  }

  Future<Map<String, dynamic>> createSpgDailyReport({
    required String customer,
    required List<Map<String, dynamic>> sellingItems,
    String? employee,
    String notes = '',
  }) async {
    var selectedEmployee = employee?.trim() ?? _currentEmployee?.trim() ?? '';
    if (selectedEmployee.isEmpty && !mobileAccess.canSelectAnyEmployee) {
      await _ensureCurrentEmployee();
      selectedEmployee = _currentEmployee?.trim() ?? '';
    }
    if (selectedEmployee.isEmpty) {
      throw Exception(
        mobileAccess.canSelectAnyEmployee
            ? 'Employee wajib dipilih.'
            : 'User belum terhubung ke Employee melalui field User ID.',
      );
    }
    if (customer.trim().isEmpty) {
      throw Exception('Customer wajib dipilih.');
    }
    await _ensureSpgCustomerAssigned(
      customer: customer.trim(),
      employee: selectedEmployee,
    );
    final rows = sellingItems
        .where((row) => row['item']?.toString().trim().isNotEmpty == true)
        .map(
          (row) => {
            'item': row['item']?.toString().trim() ?? '',
            'uom': row['uom']?.toString().trim() ?? '',
            'opening_stock': NumParse.asDouble(row['opening_stock']),
            'closing_stock': NumParse.asDouble(row['closing_stock']),
            'sell_out': NumParse.asDouble(row['sell_out']),
          },
        )
        .toList();
    if (rows.isEmpty) {
      throw Exception('Minimal 1 item selling wajib diisi.');
    }
    final payload = {
      'employee': selectedEmployee,
      'customer': customer.trim(),
      'report_date': _formatFrappeDate(DateTime.now()),
      'selling_items': rows,
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
    };
    return _frappeService.createDocument('SPG Daily Report', payload);
  }

  Future<List<Map<String, dynamic>>> _fetchVisitRows({
    required String doctype,
    required List<List<dynamic>>? filters,
    required int limit,
    required String orderBy,
    required List<List<String>> fieldSets,
  }) async {
    Object? lastError;
    for (final fieldSet in fieldSets) {
      for (final candidateOrderBy in <String>[
        orderBy,
        'modified desc, name desc',
        'name desc',
      ]) {
        for (final scopedFilters in <List<List<dynamic>>?>[filters, null]) {
          try {
            return await _fetchAllResourcePages(
              doctype: doctype,
              fields: fieldSet,
              filters: scopedFilters,
              orderBy: candidateOrderBy,
              maxRows: limit,
            );
          } catch (error) {
            lastError = error;
            if (!_looksLikeVisitListIssue(error)) rethrow;
          }
        }
      }
    }
    throw lastError ?? Exception('Gagal membaca $doctype.');
  }

  Future<Map<String, dynamic>> _createEmployeeCheckin({
    required String employee,
    required String logType,
    required String time,
    required VisitLocationPoint point,
    required CustomerVisitLocation? target,
    required double? distance,
    String? photoPath,
  }) async {
    final locationText = [
      point.latitude.toStringAsFixed(6),
      point.longitude.toStringAsFixed(6),
      'accuracy ${point.accuracy.toStringAsFixed(0)}m',
      if (target != null && distance != null)
        'distance ${distance.toStringAsFixed(0)}m',
    ].join(', ');
    final created = await _frappeService.createDocument('Employee Checkin', {
      'employee': employee,
      'time': time,
      'log_type': logType,
      'device_id': locationText,
      'skip_auto_attendance': 0,
    });
    final name = created['name']?.toString() ?? '';
    if (name.isNotEmpty && photoPath?.trim().isNotEmpty == true) {
      await uploadAttachment(
        doctype: 'Employee Checkin',
        documentName: name,
        filePath: photoPath!,
      );
    }
    return created;
  }

  String _formatFrappeDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _formatFrappeDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  Future<CustomerSalesInsight> fetchCustomerSalesInsight(
    String customer, {
    String? company,
  }) {
    if (_isSampleMode) {
      return Future.value(
        const CustomerSalesInsight(
          creditLimit: 5000000,
          outstanding: 1250000,
          depositBalance: 250000,
          company: 'Sample Company',
          currency: 'IDR',
          priceList: 'Standard Selling',
          priceListCurrency: 'IDR',
          customerGroup: 'Retail',
        ),
      );
    }
    return _customerService.fetchSalesInsight(customer, company: company);
  }

  Future<List<CustomerItemPrice>> fetchCustomerItemPrices({
    required String customer,
    String? company,
    String? query,
    int limit = 100,
  }) async {
    if (_isSampleMode) {
      final rows = [
        const CustomerItemPrice(
          itemCode: 'ITEM-SAMPLE-001',
          itemName: 'Pisang Cavendish CL',
          itemGroup: 'Fresh Produce',
          priceList: 'Standard Selling',
          currency: 'IDR',
          rate: 246500,
          uom: 'Box',
        ),
        const CustomerItemPrice(
          itemCode: 'ITEM-SAMPLE-002',
          itemName: 'Fresh Pack 1 Kg',
          itemGroup: 'Packaging',
          priceList: 'Standard Selling',
          currency: 'IDR',
          rate: 62500,
          uom: 'Pcs',
        ),
        const CustomerItemPrice(
          itemCode: 'ITEM-SAMPLE-003',
          itemName: 'Display Rack Mini',
          itemGroup: 'Merchandising',
          priceList: 'Standard Selling',
          currency: 'IDR',
          rate: 185000,
          uom: 'Unit',
        ),
      ];
      final normalized = query?.trim().toLowerCase() ?? '';
      if (normalized.isEmpty) return rows;
      return rows.where((row) {
        return row.itemCode.toLowerCase().contains(normalized) ||
            row.itemName.toLowerCase().contains(normalized);
      }).toList();
    }
    await _frappeService.ensureLoggedIn();
    final insight = await fetchCustomerSalesInsight(customer, company: company);
    final priceList = insight.priceList.trim();
    final filters = <List<dynamic>>[
      ['selling', '=', 1],
      ['price_list_rate', '>', 0],
      if (priceList.isNotEmpty) ['price_list', '=', priceList],
    ];
    final normalizedQuery = query?.trim() ?? '';
    Set<String>? candidateItemCodes;
    if (normalizedQuery.isNotEmpty) {
      candidateItemCodes = await _fetchCustomerPriceItemCandidates(
        normalizedQuery,
        limit: limit,
      );
      if (candidateItemCodes.isNotEmpty) {
        filters.add(['item_code', 'in', candidateItemCodes.toList()]);
      } else {
        filters.add(['item_code', 'like', '%$normalizedQuery%']);
      }
    }

    List<Map<String, dynamic>> rows;
    try {
      rows = await _fetchResourceWithFieldFallback(
        doctype: 'Item Price',
        fields: const [
          'name',
          'item_code',
          'item_name',
          'price_list',
          'price_list_rate',
          'currency',
          'uom',
          'valid_from',
        ],
        filters: filters,
        orderBy: 'item_code asc, valid_from desc, modified desc',
        limit: limit,
      );
    } catch (_) {
      rows = await _fetchResourceWithFieldFallback(
        doctype: 'Item Price',
        fields: const [
          'name',
          'item_code',
          'price_list',
          'price_list_rate',
          'currency',
          'uom',
          'valid_from',
        ],
        filters: filters,
        orderBy: 'item_code asc, modified desc',
        limit: limit,
      );
    }

    final itemCodes = rows
        .map((row) => row['item_code']?.toString().trim() ?? '')
        .where((code) => code.isNotEmpty)
        .toSet();
    final itemMeta = <String, Map<String, dynamic>>{};
    if (itemCodes.isNotEmpty) {
      try {
        final items = await _fetchResourceWithFieldFallback(
          doctype: 'Item',
          fields: const ['name', 'item_name', 'item_group', 'stock_uom'],
          filters: [
            ['name', 'in', itemCodes.toList()],
          ],
          limit: itemCodes.length,
          orderBy: 'item_name asc',
        );
        for (final item in items) {
          final name = item['name']?.toString() ?? '';
          if (name.isNotEmpty) itemMeta[name] = item;
        }
      } catch (_) {}
    }

    final mapped = rows
        .map(
          (row) => CustomerItemPrice.fromJson(
            row,
            itemMeta: itemMeta[row['item_code']?.toString() ?? ''] ?? const {},
          ),
        )
        .where((row) {
          if (normalizedQuery.isEmpty) return row.itemCode.isNotEmpty;
          final lower = normalizedQuery.toLowerCase();
          return row.itemCode.toLowerCase().contains(lower) ||
              row.itemName.toLowerCase().contains(lower);
        })
        .toList();
    mapped.sort((a, b) {
      final nameCompare = a.itemName.compareTo(b.itemName);
      return nameCompare != 0 ? nameCompare : a.itemCode.compareTo(b.itemCode);
    });
    return mapped;
  }

  Future<Set<String>> _fetchCustomerPriceItemCandidates(
    String query, {
    required int limit,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const {};
    try {
      final rows = await _fetchResourceWithFieldFallback(
        doctype: 'Item',
        fields: const ['name', 'item_name'],
        filters: const [
          ['disabled', '=', 0],
        ],
        orFilters: [
          ['name', 'like', '%$normalizedQuery%'],
          ['item_code', 'like', '%$normalizedQuery%'],
          ['item_name', 'like', '%$normalizedQuery%'],
        ],
        orderBy: 'item_name asc',
        limit: limit * 3,
      );
      return rows
          .map((row) => row['name']?.toString().trim() ?? '')
          .where((code) => code.isNotEmpty)
          .toSet();
    } catch (_) {
      try {
        final rows = await _fetchResourceWithFieldFallback(
          doctype: 'Item',
          fields: const ['name'],
          orFilters: [
            ['name', 'like', '%$normalizedQuery%'],
            ['item_name', 'like', '%$normalizedQuery%'],
          ],
          orderBy: 'name asc',
          limit: limit * 3,
        );
        return rows
            .map((row) => row['name']?.toString().trim() ?? '')
            .where((code) => code.isNotEmpty)
            .toSet();
      } catch (_) {
        return const {};
      }
    }
  }

  Future<Map<String, dynamic>> createNooRequest(NooRequestDraft draft) {
    final payload = draft.toFrappeJson();
    final salesPerson = _currentSalesPerson?.trim();
    if (salesPerson != null &&
        salesPerson.isNotEmpty &&
        (payload['sales_person'] as String?)?.trim().isNotEmpty != true) {
      payload['sales_person'] = salesPerson;
    }
    return _frappeService.createDocument('NOO Request', payload);
  }

  Future<void> updateNooRequest(String name, NooRequestDraft draft) {
    final payload = draft.toFrappeJson();
    payload.remove('request_date');
    payload.remove('status');
    final salesPerson = _currentSalesPerson?.trim();
    if (salesPerson != null &&
        salesPerson.isNotEmpty &&
        (payload['sales_person'] as String?)?.trim().isNotEmpty != true) {
      payload['sales_person'] = salesPerson;
    }
    return _frappeService.updateDocument('NOO Request', name, payload);
  }

  Future<List<Map<String, dynamic>>> fetchNooRequestRows({
    required List<String> fields,
    List<List<dynamic>>? filters,
    int limit = 50,
    int limitStart = 0,
    String? orderBy = 'modified desc',
  }) async {
    Object? lastError;
    for (final fieldSet in <List<String>>[
      fields,
      const [
        'name',
        'request_date',
        'company',
        'sales_person',
        'customer_name',
        'customer_category',
        'default_payment_terms_template',
        'status',
        'modified',
      ],
      const ['name', 'customer_name', 'status', 'modified'],
      const ['name', 'status', 'modified'],
    ]) {
      try {
        return await _fetchResourceWithFieldFallback(
          doctype: 'NOO Request',
          fields: fieldSet,
          limit: limit,
          limitStart: limitStart,
          orderBy: orderBy,
          filters: filters,
        );
      } catch (error) {
        lastError = error;
        if (!_looksLikeNooListPermissionIssue(error)) rethrow;
      }
    }
    throw lastError ?? Exception('Gagal membaca NOO Request.');
  }

  bool _looksLikeNooListPermissionIssue(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('akses erpnext tidak diizinkan') ||
        message.contains('permissionerror') ||
        message.contains('not permitted') ||
        message.contains('field not permitted') ||
        message.contains('no permitted fields');
  }

  Future<Map<String, dynamic>> createPromoRequest(PromoRequestDraft draft) {
    final payload = draft.toFrappeJson();
    return _frappeService.createDocument('Promo Request', payload);
  }

  Future<List<Map<String, dynamic>>> fetchPromoRequestRows({
    required List<String> fields,
    List<List<dynamic>>? filters,
    int limit = 50,
    int limitStart = 0,
    String? orderBy = 'modified desc',
  }) async {
    Object? lastError;
    for (final fieldSet in <List<String>>[
      fields,
      const [
        'name',
        'request_date',
        'company',
        'customer_group',
        'customer',
        'valid_from',
        'valid_upto',
        'status',
        'modified',
      ],
      const ['name', 'customer_group', 'customer', 'status', 'modified'],
      const ['name', 'status', 'modified'],
      const ['name', 'modified'],
      const ['name'],
    ]) {
      try {
        return await _fetchPromoRequestRowsWithFallback(
          fieldSet,
          filters: filters,
          limit: limit,
          limitStart: limitStart,
          orderBy: orderBy,
        );
      } catch (error) {
        lastError = error;
        if (!_looksLikePromoListPermissionIssue(error)) rethrow;
      }
    }
    throw lastError ?? Exception('Gagal membaca Promo Request.');
  }

  Future<List<Map<String, dynamic>>> _fetchPromoRequestRowsWithFallback(
    List<String> fields, {
    List<List<dynamic>>? filters,
    required int limit,
    required int limitStart,
    String? orderBy,
  }) async {
    Object? resourceError;
    try {
      return await _fetchResourceWithFieldFallback(
        doctype: 'Promo Request',
        fields: fields,
        limit: limit,
        limitStart: limitStart,
        orderBy: orderBy,
        filters: filters,
      );
    } catch (error) {
      resourceError = error;
      if (!_looksLikePromoListPermissionIssue(error)) rethrow;
    }

    try {
      return await _frappeService.fetchReportView(
        'Promo Request',
        fields: fields,
        limit: limit,
        limitStart: limitStart,
        orderBy: orderBy,
        filters: filters,
      );
    } catch (reportError) {
      throw Exception(
        'Resource: ${_cleanShortFrappeError(resourceError)}. '
        'ReportView: ${_cleanShortFrappeError(reportError)}',
      );
    }
  }

  String _cleanShortFrappeError(Object? error) {
    if (error == null) return '-';
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.length > 140 ? '${text.substring(0, 140)}...' : text;
  }

  bool _looksLikePromoListPermissionIssue(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('akses erpnext tidak diizinkan') ||
        message.contains('permissionerror') ||
        message.contains('not permitted') ||
        message.contains('field not permitted') ||
        message.contains('no permitted fields') ||
        message.contains('unknown column') ||
        message.contains('does not exist');
  }

  Future<ItemSalesInsight> fetchItemSalesInsight(
    String itemCode, {
    String? customer,
    String? company,
    String? priceList,
    String? currency,
    String? warehouse,
    String? customerGroup,
    DateTime? transactionDate,
    double qty = 1,
    bool ignorePricingRule = false,
  }) async {
    await _frappeService.ensureLoggedIn();
    Map<String, dynamic> pricing = const {};
    if (customer != null &&
        customer.isNotEmpty &&
        company != null &&
        company.isNotEmpty) {
      try {
        pricing = await _frappeService.fetchSalesItemPricing(
          itemCode: itemCode,
          customer: customer,
          company: company,
          transactionDate: (transactionDate ?? DateTime.now())
              .toIso8601String()
              .split('T')
              .first,
          qty: qty,
          warehouse: warehouse,
          priceList: priceList,
          currency: currency,
          customerGroup: customerGroup,
          ignorePricingRule: ignorePricingRule,
        );
      } catch (_) {}
    }
    final priceFilters = <List<dynamic>>[
      ['item_code', '=', itemCode],
      ['selling', '=', 1],
      if (priceList != null && priceList.isNotEmpty)
        ['price_list', '=', priceList],
    ];
    List<Map<String, dynamic>> prices;
    try {
      prices = await _fetchResourceWithFieldFallback(
        doctype: 'Item Price',
        fields: const ['name', 'price_list', 'price_list_rate', 'currency'],
        limit: 1,
        orderBy: 'valid_from desc, modified desc',
        filters: priceFilters,
      );
    } catch (_) {
      prices = await _fetchResourceWithFieldFallback(
        doctype: 'Item Price',
        fields: const ['name', 'price_list', 'price_list_rate', 'currency'],
        limit: 1,
        orderBy: 'modified desc',
        filters: [
          ['item_code', '=', itemCode],
          if (priceList != null && priceList.isNotEmpty)
            ['price_list', '=', priceList],
        ],
      );
    }
    final price = prices.isEmpty ? const <String, dynamic>{} : prices.first;
    final resolvedPriceListRate = NumParse.asDouble(
      pricing['price_list_rate'] ?? price['price_list_rate'],
    );
    final resolvedRate = NumParse.asDouble(
      pricing['rate'] ?? pricing['net_rate'] ?? resolvedPriceListRate,
    );
    var discountAmount = NumParse.asDouble(pricing['discount_amount']);
    var discountPercentage = NumParse.asDouble(pricing['discount_percentage']);
    var pricingRule = pricing['pricing_rule']?.toString() ?? '';

    if (discountAmount <= 0 && discountPercentage <= 0) {
      final promoPricing = await _fetchPromotionalSchemeItemPricing(
        itemCode: itemCode,
        company: company,
        currency: currency,
        customerGroup: customerGroup,
        transactionDate: transactionDate ?? DateTime.now(),
        priceListRate: resolvedPriceListRate,
      );
      if (promoPricing != null) {
        discountAmount = NumParse.asDouble(promoPricing['discount_amount']);
        discountPercentage = NumParse.asDouble(
          promoPricing['discount_percentage'],
        );
        pricingRule = promoPricing['pricing_rule']?.toString() ?? pricingRule;
      }
    }

    final bins = await _fetchAllResourcePages(
      doctype: 'Bin',
      fields: const [
        'name',
        'warehouse',
        'actual_qty',
        'reserved_qty',
        'projected_qty',
      ],
      filters: [
        ['item_code', '=', itemCode],
        if (warehouse != null && warehouse.isNotEmpty)
          ['warehouse', '=', warehouse],
      ],
      maxRows: null,
    );
    final stocks =
        bins
            .map(
              (row) => WarehouseStockInsight(
                warehouse: row['warehouse']?.toString() ?? '',
                actualQty: NumParse.asDouble(row['actual_qty']),
                reservedQty: NumParse.asDouble(row['reserved_qty']),
                projectedQty: NumParse.asDouble(row['projected_qty']),
              ),
            )
            .where((row) => row.warehouse.isNotEmpty)
            .toList()
          ..sort((a, b) => a.warehouse.compareTo(b.warehouse));

    return ItemSalesInsight(
      itemCode: itemCode,
      priceList:
          pricing['price_list']?.toString() ??
          price['price_list']?.toString() ??
          priceList ??
          '',
      priceListRate: resolvedPriceListRate,
      price: resolvedRate,
      currency:
          pricing['price_list_currency']?.toString() ??
          pricing['currency']?.toString() ??
          price['currency']?.toString() ??
          currency ??
          '',
      discountAmount: discountAmount,
      discountPercentage: discountPercentage,
      pricingRule: pricingRule,
      stocks: stocks,
    );
  }

  Future<Map<String, dynamic>?> _fetchPromotionalSchemeItemPricing({
    required String itemCode,
    required String? company,
    required String? currency,
    required String? customerGroup,
    required DateTime transactionDate,
    required double priceListRate,
  }) async {
    if (priceListRate <= 0) return null;
    try {
      final schemes = await _fetchResourceWithFieldFallback(
        doctype: 'Promotional Scheme',
        fields: const [
          'name',
          'disable',
          'selling',
          'company',
          'currency',
          'valid_from',
          'valid_upto',
        ],
        filters: const [
          ['selling', '=', 1],
          ['disable', '=', 0],
        ],
        orderBy: 'modified desc',
        limit: 50,
      );

      for (final scheme in schemes) {
        final name = scheme['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        if (!_isActiveSellingPromotion(
          scheme,
          company: company,
          currency: currency,
          transactionDate: transactionDate,
        )) {
          continue;
        }
        final doc = await _frappeService.fetchDocument(
          'Promotional Scheme',
          name,
        );
        if (!_isActiveSellingPromotion(
          doc,
          company: company,
          currency: currency,
          transactionDate: transactionDate,
        )) {
          continue;
        }
        if (!_promotionMatchesCustomerGroup(doc, customerGroup)) continue;
        if (!_promotionMatchesItem(doc, itemCode)) continue;

        final discount = _promotionalSchemeDiscount(doc, priceListRate);
        if (discount > 0) {
          return {'discount_amount': discount, 'pricing_rule': name};
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  bool _isActiveSellingPromotion(
    Map<String, dynamic> doc, {
    required String? company,
    required String? currency,
    required DateTime transactionDate,
  }) {
    if (_truthy(doc['disable'])) return false;
    if (doc.containsKey('selling') && !_truthy(doc['selling'])) return false;
    final promoCompany = doc['company']?.toString().trim() ?? '';
    if (promoCompany.isNotEmpty &&
        company?.trim().isNotEmpty == true &&
        promoCompany != company!.trim()) {
      return false;
    }
    final promoCurrency = doc['currency']?.toString().trim() ?? '';
    if (promoCurrency.isNotEmpty &&
        currency?.trim().isNotEmpty == true &&
        promoCurrency != currency!.trim()) {
      return false;
    }
    final validFrom = _parseFrappeDate(doc['valid_from']);
    if (validFrom != null &&
        DateTime(
          transactionDate.year,
          transactionDate.month,
          transactionDate.day,
        ).isBefore(DateTime(validFrom.year, validFrom.month, validFrom.day))) {
      return false;
    }
    final validUpto = _parseFrappeDate(doc['valid_upto']);
    if (validUpto != null &&
        DateTime(
          transactionDate.year,
          transactionDate.month,
          transactionDate.day,
        ).isAfter(DateTime(validUpto.year, validUpto.month, validUpto.day))) {
      return false;
    }
    return true;
  }

  bool _promotionMatchesCustomerGroup(
    Map<String, dynamic> doc,
    String? customerGroup,
  ) {
    final group = customerGroup?.trim() ?? '';
    final applicableFor = doc['applicable_for']?.toString().trim() ?? '';
    if (applicableFor.isEmpty || applicableFor == 'Customer') return true;
    if (applicableFor != 'Customer Group') return true;
    if (group.isEmpty) return false;

    final rows = _childRows(doc);
    final groupRows = rows.where((row) {
      final rowGroup =
          row['customer_group']?.toString().trim() ??
          row['party']?.toString().trim() ??
          row['customer_group_name']?.toString().trim() ??
          '';
      return rowGroup.isNotEmpty;
    }).toList();
    if (groupRows.isEmpty) return true;
    return groupRows.any((row) {
      final rowGroup =
          row['customer_group']?.toString().trim() ??
          row['party']?.toString().trim() ??
          row['customer_group_name']?.toString().trim() ??
          '';
      return rowGroup == group;
    });
  }

  bool _promotionMatchesItem(Map<String, dynamic> doc, String itemCode) {
    final rows = _childRows(doc);
    final itemRows = rows.where((row) {
      final code =
          row['item_code']?.toString().trim() ??
          row['pricing_rule_item_code']?.toString().trim() ??
          '';
      return code.isNotEmpty;
    }).toList();
    if (itemRows.isEmpty) return true;
    return itemRows.any((row) {
      final code =
          row['item_code']?.toString().trim() ??
          row['pricing_rule_item_code']?.toString().trim() ??
          '';
      return code == itemCode;
    });
  }

  double _promotionalSchemeDiscount(
    Map<String, dynamic> doc,
    double priceListRate,
  ) {
    for (final row in _childRows(doc)) {
      final discountType = row['discount_type']?.toString().trim() ?? '';
      if (discountType == 'Discount Amount') {
        final discount = NumParse.asDouble(row['discount_amount']);
        if (discount > 0) return discount;
      }
      if (discountType == 'Rate') {
        final promoRate = NumParse.asDouble(row['rate']);
        if (promoRate > 0 && promoRate < priceListRate) {
          return priceListRate - promoRate;
        }
      }
      if (discountType == 'Discount Percentage') {
        final percent = NumParse.asDouble(
          row['discount_percentage'] ?? row['discount'],
        );
        if (percent > 0) return priceListRate * percent / 100;
      }
    }
    return 0;
  }

  List<Map<String, dynamic>> _childRows(Map<String, dynamic> doc) {
    final rows = <Map<String, dynamic>>[];
    for (final value in doc.values) {
      if (value is! List) continue;
      for (final raw in value) {
        if (raw is Map) rows.add(Map<String, dynamic>.from(raw));
      }
    }
    return rows;
  }

  bool _truthy(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == '1' || text == 'true' || text == 'yes';
  }

  Future<SupplierPriceComparison> fetchSupplierPriceComparison({
    required String itemCode,
    String itemName = '',
  }) async {
    await _frappeService.ensureLoggedIn();
    final options = <SupplierPriceOption>[];

    try {
      final rows = await _fetchResourceWithFieldFallback(
        doctype: 'Item Price',
        fields: const [
          'name',
          'item_code',
          'price_list',
          'price_list_rate',
          'currency',
          'supplier',
          'supplier_name',
          'valid_from',
        ],
        limit: 30,
        orderBy: 'price_list_rate asc, valid_from desc, modified desc',
        filters: [
          ['item_code', '=', itemCode],
          ['buying', '=', 1],
          ['price_list_rate', '>', 0],
        ],
      );
      options.addAll(rows.map(SupplierPriceOption.fromItemPrice));
    } catch (_) {
      // Item Price is helpful but not mandatory for comparison.
    }

    try {
      final rows = await _fetchResourceWithFieldFallback(
        doctype: 'Purchase Order Item',
        fields: const [
          'parent',
          'item_code',
          'item_name',
          'rate',
          'base_rate',
          'schedule_date',
        ],
        limit: 30,
        orderBy: 'modified desc',
        filters: [
          ['item_code', '=', itemCode],
        ],
      );
      final parents = await _fetchDocumentsInBatches(
        'Purchase Order',
        rows.map((row) => row['parent']?.toString() ?? ''),
      );
      for (final row in rows) {
        final parentName = row['parent']?.toString() ?? '';
        final parent = parents[parentName];
        if (parent == null) continue;
        if (NumParse.asInt(parent['docstatus']) != 1) continue;
        options.add(
          SupplierPriceOption.fromPurchaseHistory(row: row, parent: parent),
        );
      }
    } catch (_) {
      // Some roles do not expose Purchase Order Item. Item Price data still works.
    }

    final deduped = <String, SupplierPriceOption>{};
    for (final option in options.where((option) => option.rate > 0)) {
      final key = [
        option.supplier,
        option.supplierName,
        option.source,
        option.reference,
        option.priceList,
        option.rate.toStringAsFixed(4),
      ].join('|');
      deduped.putIfAbsent(key, () => option);
    }

    final sorted = deduped.values.toList()
      ..sort((a, b) => a.rate.compareTo(b.rate));

    return SupplierPriceComparison(
      itemCode: itemCode,
      itemName: itemName.trim().isNotEmpty ? itemName : itemCode,
      options: sorted,
    );
  }

  Future<List<CustomerPurchaseHistory>> fetchCustomerPurchaseHistory({
    required String customer,
    required String doctype,
    String? company,
    int offset = 0,
    int limit = 20,
  }) => _customerService.fetchPurchaseHistory(
    customer: customer,
    doctype: doctype,
    company: company,
    offset: offset,
    limit: limit,
  );

  Future<Map<String, dynamic>> loadSalesHistoryDetail(
    String doctype,
    String name,
  ) {
    return _frappeService.fetchDocument(doctype, name);
  }

  Future<void> uploadSalesOrderAttachment(String orderId, String filePath) {
    return _salesOrderService.uploadAttachment(orderId, filePath);
  }

  Future<void> uploadAttachment({
    required String doctype,
    required String documentName,
    required String filePath,
  }) {
    return _frappeService
        .uploadFile(
          filePath: filePath,
          doctype: doctype,
          documentName: documentName,
        )
        .then((_) {});
  }

  Future<void> uploadDeliveryNoteProof({
    required String deliveryNoteId,
    required String filePath,
  }) {
    return uploadAttachment(
      doctype: 'Delivery Note',
      documentName: deliveryNoteId,
      filePath: filePath,
    );
  }

  Future<VisitLocationPoint> recordDeliveryDriverLocation(
    DeliveryNote deliveryNote,
  ) async {
    final point = await _visitLocationService.currentPosition();
    await _saveDeliveryTrackingPoint(deliveryNote, point);
    _latestDeliveryTrackingNote = deliveryNote.id;
    _latestDeliveryDriverLocation = point;
    notifyListeners();
    return point;
  }

  Future<VisitLocationPoint> startDeliveryDriverTracking(
    DeliveryNote deliveryNote,
  ) async {
    if (_activeSalesVisit != null || _activeSpgVisit != null) {
      throw Exception('Selesaikan check-in aktif sebelum tracking driver.');
    }
    if (_activeDeliveryTrackingNote != null &&
        _activeDeliveryTrackingNote != deliveryNote.id) {
      throw Exception(
        'Selesaikan tracking ${_activeDeliveryTrackingNote!} sebelum memulai yang baru.',
      );
    }

    final firstPoint = await recordDeliveryDriverLocation(deliveryNote);
    _activeDeliveryTrackingNote = deliveryNote.id;
    notifyListeners();
    await _visitLocationService.startTracking(
      (point) async {
        _latestDeliveryTrackingNote = deliveryNote.id;
        _latestDeliveryDriverLocation = point;
        notifyListeners();
        await _saveDeliveryTrackingPoint(deliveryNote, point);
      },
      notificationTitle: 'Tracking driver aktif',
      notificationText: '$appDisplayName mencatat lokasi driver tiap 5 menit.',
      queueFailedPoints: false,
      queueScope: '${_frappeService.baseUrl.trim()}::${_currentUser ?? ''}',
    );
    return firstPoint;
  }

  Future<void> stopDeliveryDriverTracking() async {
    await _visitLocationService.stopTracking();
    _activeDeliveryTrackingNote = null;
    notifyListeners();
  }

  Future<void> _saveDeliveryTrackingPoint(
    DeliveryNote deliveryNote,
    VisitLocationPoint point,
  ) async {
    await _frappeService.createDocument('Delivery Tracking Point', {
      'delivery_note': deliveryNote.id,
      'customer': deliveryNote.customer,
      if (_currentUser?.isNotEmpty == true) 'driver': _currentUser,
      'captured_at': point.capturedAt.toIso8601String(),
      'latitude': point.latitude,
      'longitude': point.longitude,
      'accuracy': point.accuracy,
    });
  }

  Future<List<DeliveryActivityLog>> fetchDeliveryActivityLogs(
    String deliveryNoteId,
  ) async {
    final rows = await _fetchResourceWithFieldFallback(
      doctype: 'Delivery Activity Log',
      fields: const [
        'name',
        'delivery_note',
        'customer',
        'driver',
        'activity_status',
        'notes',
        'captured_at',
        'latitude',
        'longitude',
        'accuracy',
      ],
      filters: [
        ['delivery_note', '=', deliveryNoteId],
      ],
      orderBy: 'captured_at desc, creation desc',
      limit: 100,
    );
    return rows.map(DeliveryActivityLog.fromJson).toList();
  }

  Future<void> recordDeliveryActivity({
    required DeliveryNote deliveryNote,
    required String activityStatus,
    String notes = '',
  }) async {
    VisitLocationPoint? point;
    try {
      point = await _visitLocationService.currentPosition();
    } catch (_) {
      point = null;
    }

    final trimmedNotes = notes.trim();
    await _frappeService.createDocument('Delivery Activity Log', {
      'delivery_note': deliveryNote.id,
      'customer': deliveryNote.customer,
      if (_currentUser?.isNotEmpty == true) 'driver': _currentUser,
      'activity_status': activityStatus,
      if (trimmedNotes.isNotEmpty) 'notes': trimmedNotes,
      'captured_at': (point?.capturedAt ?? DateTime.now()).toIso8601String(),
      if (point != null) 'latitude': point.latitude.toStringAsFixed(7),
      if (point != null) 'longitude': point.longitude.toStringAsFixed(7),
      if (point != null) 'accuracy': point.accuracy,
    });
  }

  Future<List<Map<String, dynamic>>> fetchDocumentAttachments({
    required String doctype,
    required String documentName,
  }) async {
    return _frappeService.fetchResource(
      'File',
      fields: const ['name', 'file_name', 'file_url', 'creation'],
      filters: [
        ['attached_to_doctype', '=', doctype],
        ['attached_to_name', '=', documentName],
      ],
      orderBy: 'creation desc',
      limit: 50,
    );
  }

  Future<SalesOrder> createSalesOrder({
    required String customer,
    String? itemCode,
    double? qty,
    List<Map<String, dynamic>>? items,
    String? warehouse,
    double? rate,
    String? series,
    String? costCenter,
    String? company,
    String? currency,
    String? sellingPriceList,
    String? priceListCurrency,
    bool ignorePricingRule = false,
    String? salesPerson,
    List<Map<String, dynamic>>? salesTeam,
    String? noted,
    DateTime? transactionDate,
    DateTime? deliveryDate,
    bool refreshAfterSave = true,
  }) async {
    await _frappeService.ensureLoggedIn();
    final orderItems =
        items ??
        [
          {
            'item_code': itemCode,
            'qty': qty,
            'delivery_date': (deliveryDate ?? transactionDate ?? DateTime.now())
                .toIso8601String()
                .split('T')
                .first,
            if (rate != null && rate > 0) 'rate': rate,
            if (warehouse != null && warehouse.trim().isNotEmpty)
              'warehouse': warehouse.trim(),
            if (costCenter != null && costCenter.trim().isNotEmpty)
              'cost_center': costCenter.trim(),
          },
        ];
    if (orderItems.isEmpty ||
        orderItems.any(
          (item) =>
              item['item_code']?.toString().trim().isEmpty != false ||
              NumParse.asDouble(item['qty']) <= 0,
        )) {
      throw Exception(
        'Sales Order wajib memiliki minimal satu item yang valid.',
      );
    }

    final payload = <String, dynamic>{
      'customer': customer,
      if (company != null && company.trim().isNotEmpty)
        'company': company.trim(),
      if (currency != null && currency.trim().isNotEmpty)
        'currency': currency.trim(),
      if (sellingPriceList != null && sellingPriceList.trim().isNotEmpty)
        'selling_price_list': sellingPriceList.trim(),
      if (priceListCurrency != null && priceListCurrency.trim().isNotEmpty)
        'price_list_currency': priceListCurrency.trim(),
      'ignore_pricing_rule': ignorePricingRule ? 1 : 0,
      'transaction_date': (transactionDate ?? DateTime.now())
          .toIso8601String()
          .split('T')
          .first,
      'delivery_date': (deliveryDate ?? transactionDate ?? DateTime.now())
          .toIso8601String()
          .split('T')
          .first,
      if (series != null && series.trim().isNotEmpty)
        'naming_series': series.trim(),
      if (costCenter != null && costCenter.trim().isNotEmpty)
        'cost_center': costCenter.trim(),
      if (salesTeam?.isNotEmpty == true)
        'sales_team': salesTeam
      else if (salesPerson?.trim().isNotEmpty == true)
        'sales_team': [
          {'sales_person': salesPerson!.trim(), 'allocated_percentage': 100},
        ],
      if (noted?.trim().isNotEmpty == true) 'noted': noted!.trim(),
      'items': orderItems,
      if (warehouse != null && warehouse.trim().isNotEmpty)
        'set_warehouse': warehouse.trim(),
    };

    final order = await _salesOrderService.create(payload);
    _salesOrders = [order, ..._salesOrders];
    notifyListeners();
    if (refreshAfterSave) {
      await refreshSalesOrders();
    } else {
      unawaited(refreshSalesOrders().catchError((_) {}));
    }
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
    return order;
  }

  Future<Map<String, dynamic>> createCustomer({
    required String customerName,
    required String customerType,
    required String namingSeries,
    required String paymentTerms,
    required String company,
    String? customerGroup,
    String? territory,
  }) async {
    await _frappeService.ensureLoggedIn();

    final payload = <String, dynamic>{
      'naming_series': namingSeries.trim(),
      'customer_name': customerName.trim(),
      'customer_type': customerType.trim(),
      'payment_terms': paymentTerms.trim(),
      if (customerGroup != null && customerGroup.trim().isNotEmpty)
        'customer_group': customerGroup.trim(),
      if (territory != null && territory.trim().isNotEmpty)
        'territory': territory.trim(),
      if (company.trim().isNotEmpty)
        'accounts': [
          {'company': company.trim()},
        ],
    };

    return _frappeService.createDocument('Customer', payload);
  }

  Future<SalesOrder> updateSalesOrder({
    required String orderId,
    String? customer,
    String? itemCode,
    double? qty,
    List<Map<String, dynamic>>? items,
    String? warehouse,
    double? rate,
    String? costCenter,
    String? company,
    String? currency,
    String? sellingPriceList,
    String? priceListCurrency,
    bool? ignorePricingRule,
    String? salesPerson,
    List<Map<String, dynamic>>? salesTeam,
    String? noted,
    DateTime? transactionDate,
    DateTime? deliveryDate,
    String? status,
    bool refreshAfterSave = true,
  }) async {
    await _frappeService.ensureLoggedIn();
    final normalizedCustomer = customer?.trim() ?? '';
    if (items != null &&
        (items.isEmpty ||
            items.any(
              (item) =>
                  item['item_code']?.toString().trim().isEmpty != false ||
                  NumParse.asDouble(item['qty']) <= 0,
            ))) {
      throw Exception(
        'Sales Order wajib memiliki minimal satu item yang valid.',
      );
    }

    final updates = <String, dynamic>{
      if (normalizedCustomer.isNotEmpty) 'customer': normalizedCustomer,
      if (company != null && company.trim().isNotEmpty)
        'company': company.trim(),
      if (currency != null && currency.trim().isNotEmpty)
        'currency': currency.trim(),
      if (sellingPriceList != null && sellingPriceList.trim().isNotEmpty)
        'selling_price_list': sellingPriceList.trim(),
      if (priceListCurrency != null && priceListCurrency.trim().isNotEmpty)
        'price_list_currency': priceListCurrency.trim(),
      if (ignorePricingRule != null)
        'ignore_pricing_rule': ignorePricingRule ? 1 : 0,
      if (transactionDate != null)
        'transaction_date': transactionDate.toIso8601String().split('T').first,
      if (deliveryDate != null)
        'delivery_date': deliveryDate.toIso8601String().split('T').first,
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
      if (costCenter != null && costCenter.trim().isNotEmpty)
        'cost_center': costCenter.trim(),
      if (salesTeam?.isNotEmpty == true)
        'sales_team': salesTeam
      else if (salesPerson != null && salesPerson.trim().isNotEmpty)
        'sales_team': [
          {'sales_person': salesPerson.trim(), 'allocated_percentage': 100},
        ],
      if (noted != null) 'noted': noted.trim(),
      if (warehouse != null && warehouse.trim().isNotEmpty)
        'set_warehouse': warehouse.trim(),
      if (items != null)
        'items': items
      else if (itemCode != null && itemCode.trim().isNotEmpty && qty != null)
        'items': [
          {
            'item_code': itemCode.trim(),
            'qty': qty,
            if (deliveryDate != null)
              'delivery_date': deliveryDate.toIso8601String().split('T').first,
            if (rate != null && rate > 0) 'rate': rate,
            if (warehouse != null && warehouse.trim().isNotEmpty)
              'warehouse': warehouse.trim(),
            if (costCenter != null && costCenter.trim().isNotEmpty)
              'cost_center': costCenter.trim(),
          },
        ],
    };

    if (normalizedCustomer.isNotEmpty) {
      try {
        final currentDoc = await _frappeService.fetchDocument(
          'Sales Order',
          orderId,
        );
        final currentCustomer = currentDoc['customer']?.toString().trim() ?? '';
        final hasMismatchedCustomer =
            currentCustomer.isNotEmpty && currentCustomer != normalizedCustomer;
        final hasInvalidAddress = await _salesOrderHasAddressMismatch(
          currentDoc,
          normalizedCustomer,
        );
        if (hasMismatchedCustomer || hasInvalidAddress) {
          updates.addAll(const {
            'customer_address': '',
            'address_display': '',
            'shipping_address_name': '',
            'shipping_address': '',
            'contact_person': '',
            'contact_display': '',
            'contact_mobile': '',
            'contact_email': '',
          });
        }
      } catch (_) {
        // If the current document cannot be read, keep the intended update and
        // let ERPNext return the authoritative validation message.
      }
    }

    if (updates.isEmpty) {
      throw Exception('No fields to update.');
    }

    final updatedOrder = await _salesOrderService.update(orderId, updates);
    _salesOrders = _salesOrders
        .map((o) => o.id == orderId ? updatedOrder : o)
        .toList();
    notifyListeners();
    if (refreshAfterSave) {
      await refreshSalesOrders();
    } else {
      unawaited(refreshSalesOrders().catchError((_) {}));
    }
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
    return updatedOrder;
  }

  Future<bool> _salesOrderHasAddressMismatch(
    Map<String, dynamic> order,
    String customer,
  ) async {
    for (final field in const ['customer_address', 'shipping_address_name']) {
      final addressName = order[field]?.toString().trim() ?? '';
      if (addressName.isEmpty) continue;
      try {
        final address = await _frappeService.fetchDocument(
          'Address',
          addressName,
        );
        final links = address['links'];
        if (links is! List) return true;
        final belongsToCustomer = links.any((rawLink) {
          if (rawLink is! Map) return false;
          final link = Map<String, dynamic>.from(rawLink);
          final doctype = link['link_doctype']?.toString().trim() ?? '';
          final name = link['link_name']?.toString().trim() ?? '';
          return doctype == 'Customer' && name == customer;
        });
        if (!belongsToCustomer) return true;
      } catch (_) {
        return true;
      }
    }
    return false;
  }

  Future<void> deleteSalesOrder(String orderId) async {
    await _frappeService.ensureLoggedIn();
    await _salesOrderService.delete(orderId);
    _salesOrders.removeWhere((o) => o.id == orderId);
    notifyListeners();
    await refreshSalesOrders();
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
  }

  Future<PurchaseOrder> loadPurchaseOrderDetail(String orderId) async {
    return _purchaseOrderService.load(orderId);
  }

  Future<DeliveryNote> loadDeliveryNoteDetail(String id) async {
    await _frappeService.ensureLoggedIn();
    final doc = await _frappeService.fetchDocument('Delivery Note', id);
    final deliveryNote = DeliveryNote.fromJson(doc);
    _replaceDeliveryNoteSnapshot(deliveryNote);
    return deliveryNote;
  }

  Future<SalesInvoice> loadSalesInvoiceDetail(String id) async {
    final invoice = await _salesInvoiceService.load(id);
    _replaceSalesInvoiceSnapshot(invoice);
    return invoice;
  }

  void _replaceDeliveryNoteSnapshot(DeliveryNote deliveryNote) {
    final index = _deliveryNotes.indexWhere(
      (item) => item.id == deliveryNote.id,
    );
    if (index < 0) return;
    _deliveryNotes = List<DeliveryNote>.from(_deliveryNotes)
      ..[index] = deliveryNote;
    notifyListeners();
  }

  void _replaceSalesInvoiceSnapshot(SalesInvoice invoice) {
    final index = _salesInvoices.indexWhere((item) => item.id == invoice.id);
    if (index < 0) return;
    _salesInvoices = List<SalesInvoice>.from(_salesInvoices)..[index] = invoice;
    notifyListeners();
  }

  Future<PurchaseReceipt> loadPurchaseReceiptDetail(String id) async {
    await _frappeService.ensureLoggedIn();
    final doc = await _frappeService.fetchDocument('Purchase Receipt', id);
    return PurchaseReceipt.fromJson(doc);
  }

  Future<PurchaseInvoice> loadPurchaseInvoiceDetail(String id) async {
    return _purchaseInvoiceService.load(id);
  }

  Future<MaterialRequest> loadMaterialRequestDetail(String id) async {
    await _frappeService.ensureLoggedIn();
    final doc = await _frappeService.fetchDocument('Material Request', id);
    return MaterialRequest.fromJson(doc);
  }

  Future<MaterialRequest> createMaterialRequest({
    required String materialRequestType,
    String? itemCode,
    double? qty,
    List<Map<String, dynamic>>? items,
    required DateTime transactionDate,
    required DateTime scheduleDate,
    String? company,
    String? warehouse,
  }) async {
    await _frappeService.ensureLoggedIn();
    final date = DateRangePresets.toFrappeDate(transactionDate);
    final requiredBy = DateRangePresets.toFrappeDate(scheduleDate);
    final requestItems =
        items ??
        [
          {
            'item_code': itemCode?.trim(),
            'qty': qty,
            'schedule_date': requiredBy,
            if (warehouse?.trim().isNotEmpty == true)
              'warehouse': warehouse!.trim(),
          },
        ];
    if (requestItems.isEmpty) {
      throw Exception('Minimal satu item wajib diisi.');
    }

    final payload = <String, dynamic>{
      'material_request_type': materialRequestType,
      'transaction_date': date,
      'schedule_date': requiredBy,
      if (company?.trim().isNotEmpty == true) 'company': company!.trim(),
      'items': requestItems,
    };

    final created = await _frappeService.createDocument(
      'Material Request',
      payload,
    );
    final request = MaterialRequest.fromJson(created);
    await refreshMaterialRequests();
    return request;
  }

  Future<PurchaseInvoice> createPurchaseInvoice({
    required String supplier,
    String? itemCode,
    double? qty,
    List<Map<String, dynamic>>? items,
    required String namingSeries,
    required DateTime postingDate,
    required DateTime dueDate,
    required bool updateStock,
    String? warehouse,
    double? rate,
    String? company,
  }) async {
    await _frappeService.ensureLoggedIn();
    final warehouseName = warehouse?.trim() ?? '';
    if (updateStock && warehouseName.isEmpty) {
      throw Exception('Warehouse wajib dipilih saat Update Stock aktif.');
    }

    final invoiceItems =
        items ??
        [
          {
            'item_code': itemCode?.trim(),
            'qty': qty,
            if (rate != null && rate >= 0) 'rate': rate,
            if (updateStock) 'warehouse': warehouseName,
          },
        ];
    if (invoiceItems.isEmpty) {
      throw Exception('Minimal satu item wajib diisi.');
    }

    final payload = <String, dynamic>{
      'supplier': supplier.trim(),
      'naming_series': namingSeries.trim(),
      'posting_date': postingDate.toIso8601String().split('T').first,
      'due_date': dueDate.toIso8601String().split('T').first,
      'update_stock': updateStock ? 1 : 0,
      if (company != null && company.trim().isNotEmpty)
        'company': company.trim(),
      if (updateStock) 'set_warehouse': warehouseName,
      'items': invoiceItems,
    };

    final invoice = await _purchaseInvoiceService.create(payload);
    await refreshPurchaseInvoices();
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
    return invoice;
  }

  Future<PurchaseOrder> createPurchaseOrder({
    required String supplier,
    String? itemCode,
    double? qty,
    List<Map<String, dynamic>>? items,
    required String namingSeries,
    required DateTime requiredBy,
    String? warehouse,
    String? company,
    double? rate,
    DateTime? transactionDate,
    String? noted,
  }) async {
    await _frappeService.ensureLoggedIn();

    final scheduleDate = requiredBy.toIso8601String().split('T').first;
    final orderItems =
        items ??
        [
          {
            'item_code': itemCode,
            'qty': qty,
            'schedule_date': scheduleDate,
            if (rate != null && rate > 0) 'rate': rate,
            if (warehouse != null && warehouse.trim().isNotEmpty)
              'warehouse': warehouse.trim(),
          },
        ];
    if (orderItems.isEmpty) {
      throw Exception('Minimal satu item wajib diisi.');
    }

    final payload = <String, dynamic>{
      'supplier': supplier,
      'naming_series': namingSeries.trim(),
      'transaction_date': (transactionDate ?? DateTime.now())
          .toIso8601String()
          .split('T')
          .first,
      'schedule_date': scheduleDate,
      if (company != null && company.trim().isNotEmpty)
        'company': company.trim(),
      if (noted != null && noted.trim().isNotEmpty) 'noted': noted.trim(),
      if (warehouse != null && warehouse.trim().isNotEmpty)
        'set_warehouse': warehouse.trim(),
      'items': orderItems,
    };

    final order = await _purchaseOrderService.create(payload);
    _purchaseOrders = [order, ..._purchaseOrders];
    notifyListeners();
    await refreshPurchaseOrders();
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
    return order;
  }

  Future<PurchaseOrder> updatePurchaseOrder({
    required String orderId,
    String? supplier,
    String? itemCode,
    double? qty,
    String? warehouse,
    String? company,
    double? rate,
    List<Map<String, dynamic>>? items,
    DateTime? transactionDate,
    DateTime? requiredBy,
    String? noted,
  }) async {
    await _frappeService.ensureLoggedIn();

    final updates = <String, dynamic>{
      if (supplier != null && supplier.trim().isNotEmpty)
        'supplier': supplier.trim(),
      if (transactionDate != null)
        'transaction_date': transactionDate.toIso8601String().split('T').first,
      if (requiredBy != null)
        'schedule_date': requiredBy.toIso8601String().split('T').first,
      if (company != null && company.trim().isNotEmpty)
        'company': company.trim(),
      if (noted != null) 'noted': noted.trim(),
      if (warehouse != null && warehouse.trim().isNotEmpty)
        'set_warehouse': warehouse.trim(),
      if (items != null)
        'items': items
      else if (itemCode != null && itemCode.trim().isNotEmpty && qty != null)
        'items': [
          {
            'item_code': itemCode.trim(),
            'qty': qty,
            if (requiredBy != null)
              'schedule_date': requiredBy.toIso8601String().split('T').first,
            if (rate != null && rate > 0) 'rate': rate,
            if (warehouse != null && warehouse.trim().isNotEmpty)
              'warehouse': warehouse.trim(),
          },
        ],
    };

    if (updates.isEmpty) {
      throw Exception('No fields to update.');
    }

    final updatedOrder = await _purchaseOrderService.update(orderId, updates);
    _purchaseOrders = _purchaseOrders
        .map((o) => o.id == orderId ? updatedOrder : o)
        .toList();
    notifyListeners();
    await refreshPurchaseOrders();
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
    return updatedOrder;
  }

  Future<void> createPurchaseReceipt({
    required String supplier,
    String? itemCode,
    double? qty,
    List<Map<String, dynamic>>? items,
    required String namingSeries,
    required String warehouse,
    required DateTime postingDate,
    double? rate,
    String? company,
  }) async {
    final warehouseName = warehouse.trim();
    final receiptItems =
        items ??
        [
          {
            'item_code': itemCode?.trim(),
            'qty': qty,
            'warehouse': warehouseName,
            if (rate != null && rate >= 0) 'rate': rate,
          },
        ];
    if (receiptItems.isEmpty) {
      throw Exception('Minimal satu item wajib diisi.');
    }

    final payload = <String, dynamic>{
      'supplier': supplier.trim(),
      'naming_series': namingSeries.trim(),
      'posting_date': postingDate.toIso8601String().split('T').first,
      'set_warehouse': warehouseName,
      if (company != null && company.trim().isNotEmpty)
        'company': company.trim(),
      'items': receiptItems,
    };
    await _frappeService.createDocument('Purchase Receipt', payload);
    await refreshPurchaseReceipts();
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
  }

  Future<void> deletePurchaseOrder(String orderId) async {
    await _frappeService.ensureLoggedIn();
    await _purchaseOrderService.delete(orderId);
    _purchaseOrders.removeWhere((o) => o.id == orderId);
    notifyListeners();
    await refreshPurchaseOrders();
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
  }

  Future<StockEntry> createStockEntry({
    required String stockEntryType,
    required List<Map<String, dynamic>> items,
    DateTime? postingDate,
  }) async {
    await _frappeService.ensureLoggedIn();

    final payload = <String, dynamic>{
      'stock_entry_type': stockEntryType,
      'posting_date': (postingDate ?? DateTime.now())
          .toIso8601String()
          .split('T')
          .first,
      'items': items,
    };

    final created = await _frappeService.createDocument('Stock Entry', payload);
    final entry = StockEntry.fromJson(created);
    _stockEntries = [entry, ..._stockEntries];
    notifyListeners();
    await refreshStockEntries();
    return entry;
  }

  Future<Map<String, dynamic>> createStockReconciliation({
    required String company,
    required String warehouse,
    required List<Map<String, dynamic>> items,
    DateTime? postingDate,
  }) async {
    await _frappeService.ensureLoggedIn();
    if (company.trim().isEmpty) {
      throw Exception('Company gudang belum tersedia.');
    }
    if (warehouse.trim().isEmpty) {
      throw Exception('Warehouse wajib dipilih.');
    }
    if (items.isEmpty) {
      throw Exception('Tambahkan minimal satu item stock opname.');
    }
    return _frappeService.createDocument('Stock Reconciliation', {
      'company': company.trim(),
      'purpose': 'Stock Reconciliation',
      'posting_date': (postingDate ?? DateTime.now())
          .toIso8601String()
          .split('T')
          .first,
      'items': [
        for (final item in items) {...item, 'warehouse': warehouse.trim()},
      ],
    });
  }

  Future<void> fetchSalesOrdersFromFrappe({
    String? baseUrl,
    String? username,
    String? password,
  }) async {
    final canReuseInFlight =
        baseUrl == null && username == null && password == null;
    if (canReuseInFlight && _salesOrdersFetchInFlight != null) {
      return _salesOrdersFetchInFlight;
    }
    final request = _fetchSalesOrdersFromFrappe(
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
    if (canReuseInFlight) _salesOrdersFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_salesOrdersFetchInFlight, request)) {
        _salesOrdersFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchSalesOrdersFromFrappe({
    String? baseUrl,
    String? username,
    String? password,
  }) async {
    if (_isSampleMode) {
      notifyListeners();
      return;
    }
    _isSalesOrdersLoading = true;
    _salesOrdersError = null;
    _hasMoreSalesOrders = true;
    _isMoreSalesOrdersLoading = false;
    final version = ++_salesOrderQueryVersion;
    notifyListeners();

    try {
      _frappeService.baseUrl = _activeFrappeBaseUrl(baseUrl);
      if (username != null && password != null) {
        await _frappeService.login(username, password);
      } else {
        await _frappeService.ensureLoggedIn();
      }

      final orders = await _fetchSalesOrderPage(limitStart: 0);
      if (version != _salesOrderQueryVersion) return;
      _salesOrders = orders;
      _hasMoreSalesOrders = orders.isNotEmpty;
    } catch (error) {
      if (version != _salesOrderQueryVersion) return;
      _salesOrdersError = error.toString();
    } finally {
      if (version == _salesOrderQueryVersion) {
        _isSalesOrdersLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> fetchPurchaseOrdersFromFrappe({
    String? baseUrl,
    String? username,
    String? password,
  }) async {
    final canReuseInFlight =
        baseUrl == null && username == null && password == null;
    if (canReuseInFlight && _purchaseOrdersFetchInFlight != null) {
      return _purchaseOrdersFetchInFlight;
    }
    final request = _fetchPurchaseOrdersFromFrappe(
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
    if (canReuseInFlight) _purchaseOrdersFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_purchaseOrdersFetchInFlight, request)) {
        _purchaseOrdersFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchPurchaseOrdersFromFrappe({
    String? baseUrl,
    String? username,
    String? password,
  }) async {
    if (_isSampleMode) {
      notifyListeners();
      return;
    }
    _frappeService.baseUrl = _activeFrappeBaseUrl(baseUrl);
    _isPurchaseOrdersLoading = true;
    _purchaseOrdersError = null;
    _hasMorePurchaseOrders = true;
    _isMorePurchaseOrdersLoading = false;
    final version = ++_purchaseOrderQueryVersion;
    notifyListeners();

    try {
      if (username != null && password != null) {
        await _frappeService.login(username, password);
      } else {
        await _frappeService.ensureLoggedIn();
      }

      final orders = await _fetchPurchaseOrderPage(limitStart: 0);
      if (version != _purchaseOrderQueryVersion) return;
      _purchaseOrders = orders;
      _hasMorePurchaseOrders = orders.isNotEmpty;

      _purchaseOrdersError = null;
    } catch (err) {
      if (version != _purchaseOrderQueryVersion) return;
      _purchaseOrdersError = err.toString();
    } finally {
      if (version == _purchaseOrderQueryVersion) {
        _isPurchaseOrdersLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreSalesOrders() async {
    if (_isSalesOrdersLoading ||
        _isMoreSalesOrdersLoading ||
        !_hasMoreSalesOrders) {
      return;
    }

    _isMoreSalesOrdersLoading = true;
    final version = _salesOrderQueryVersion;
    notifyListeners();

    try {
      await _frappeService.ensureLoggedIn();
      final nextPage = await _fetchSalesOrderPage(
        limitStart: _salesOrders.length,
      );
      if (version != _salesOrderQueryVersion) return;
      final existingIds = _salesOrders.map((order) => order.id).toSet();
      _salesOrders = [
        ..._salesOrders,
        ...nextPage.where((order) => existingIds.add(order.id)),
      ];
      _hasMoreSalesOrders = nextPage.isNotEmpty;
      _salesOrdersError = null;
    } catch (err) {
      if (version != _salesOrderQueryVersion) return;
      _salesOrdersError = err.toString();
    } finally {
      if (version == _salesOrderQueryVersion) {
        _isMoreSalesOrdersLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMorePurchaseOrders() async {
    if (_isPurchaseOrdersLoading ||
        _isMorePurchaseOrdersLoading ||
        !_hasMorePurchaseOrders) {
      return;
    }

    _isMorePurchaseOrdersLoading = true;
    final version = _purchaseOrderQueryVersion;
    notifyListeners();

    try {
      await _frappeService.ensureLoggedIn();
      final nextPage = await _fetchPurchaseOrderPage(
        limitStart: _purchaseOrders.length,
      );
      if (version != _purchaseOrderQueryVersion) return;
      final existingIds = _purchaseOrders.map((order) => order.id).toSet();
      _purchaseOrders = [
        ..._purchaseOrders,
        ...nextPage.where((order) => existingIds.add(order.id)),
      ];
      _hasMorePurchaseOrders = nextPage.isNotEmpty;
      _purchaseOrdersError = null;
    } catch (err) {
      if (version != _purchaseOrderQueryVersion) return;
      _purchaseOrdersError = err.toString();
    } finally {
      if (version == _purchaseOrderQueryVersion) {
        _isMorePurchaseOrdersLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshOrderSummaries({bool silent = false}) {
    return refreshAllSummaries(silent: silent);
  }

  Future<void> refreshDashboardSummaryForCurrentAccess({
    bool silent = false,
  }) async {
    if (_isSampleMode) {
      notifyListeners();
      return;
    }
    if (MobileRoleRegistry.isFullAccessRole(_userRole)) {
      await refreshAllSummaries(silent: silent);
      return;
    }

    _isOrderSummaryLoading = true;
    _summarySyncStatus = SummarySyncStatus.syncing;
    _orderSummaryError = null;
    if (!silent) notifyListeners();

    try {
      await Future.wait([
        if (canUseSales) refreshSalesOrders(),
        if (canUseSales) refreshSalesInvoices(),
        if (canUsePurchase) refreshPurchaseOrders(),
        if (canUsePurchase) refreshPurchaseInvoices(),
        if (canUseStock || canUseWarehouse) refreshInventory(),
      ]);

      var salesTotal = 0.0;
      var salesOpen = 0.0;
      var salesCompleted = 0.0;
      var salesDraftCount = 0;
      var salesOpenCount = 0;
      var salesCompletedCount = 0;
      var unpaidSalesInvoices = 0;

      if (canUseSales) {
        for (final order in _salesOrders) {
          salesTotal += order.value;
          if (order.docStatus == 0) salesDraftCount++;
          if (order.statusKey == SalesOrderStatusKey.completed) {
            salesCompleted += order.value;
            salesCompletedCount++;
          } else if (order.statusKey != SalesOrderStatusKey.cancelled &&
              order.statusKey != SalesOrderStatusKey.closed) {
            salesOpen += order.value;
            salesOpenCount++;
          }
        }
        for (final invoice in _salesInvoices) {
          if (invoice.statusKey == InvoiceStatusKey.unpaid ||
              invoice.statusKey == InvoiceStatusKey.overdue ||
              invoice.statusKey == InvoiceStatusKey.partlyPaid) {
            unpaidSalesInvoices++;
          }
        }
      }

      var purchaseTotal = 0.0;
      var purchasePending = 0.0;
      var purchaseDelayed = 0.0;
      var purchaseDraftCount = 0;
      var purchasePendingCount = 0;
      var purchaseCompletedCount = 0;
      var overduePurchaseInvoices = 0;

      if (canUsePurchase) {
        for (final order in _purchaseOrders) {
          purchaseTotal += order.totalValue;
          if (order.docStatus == 0) purchaseDraftCount++;
          if (order.statusKey == PurchaseOrderStatusKey.completed) {
            purchaseCompletedCount++;
          } else if (order.statusKey != PurchaseOrderStatusKey.cancelled &&
              order.statusKey != PurchaseOrderStatusKey.closed) {
            purchasePending += order.totalValue;
            purchasePendingCount++;
          }
          if (order.isDelayed) purchaseDelayed += order.totalValue;
        }
        for (final invoice in _purchaseInvoices) {
          if (invoice.statusKey == InvoiceStatusKey.overdue) {
            overduePurchaseInvoices++;
          }
        }
      }

      final stockAlerts = canUseStock || canUseWarehouse
          ? _inventory
                .where(
                  (item) =>
                      item.status == StockStatus.lowStock ||
                      item.status == StockStatus.urgent,
                )
                .length
          : 0;

      _dashboardSummary = DashboardSummary(
        salesTotal: salesTotal,
        salesOpen: salesOpen,
        salesCompleted: salesCompleted,
        salesDraftCount: salesDraftCount,
        salesOpenCount: salesOpenCount,
        salesCompletedCount: salesCompletedCount,
        purchaseTotal: purchaseTotal,
        purchasePending: purchasePending,
        purchaseDelayed: purchaseDelayed,
        purchaseDraftCount: purchaseDraftCount,
        purchasePendingCount: purchasePendingCount,
        purchaseCompletedCount: purchaseCompletedCount,
        unpaidSalesInvoices: unpaidSalesInvoices,
        overduePurchaseInvoices: overduePurchaseInvoices,
        stockAlerts: stockAlerts,
      );
      _summarySyncStatus = SummarySyncStatus.completed;
      _orderSummaryError = null;
    } catch (err) {
      _summarySyncStatus = SummarySyncStatus.error;
      _orderSummaryError = err.toString();
    } finally {
      _isOrderSummaryLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshSellingSummaries({
    bool forceRemote = false,
    String? documentType,
  }) async {
    final requestKey = _sellingSummaryRequestKey(documentType: documentType);
    final runningJob = _sellingSummaryJob;
    if (!forceRemote &&
        runningJob != null &&
        _sellingSummaryJobKey == requestKey) {
      return runningJob;
    }

    final token = ++_sellingSummaryRequestToken;
    final job = _refreshSellingSummaries(
      token,
      forceRemote: forceRemote,
      documentType: documentType,
    );
    _sellingSummaryJob = job;
    _sellingSummaryJobKey = requestKey;
    try {
      await job;
    } finally {
      if (identical(_sellingSummaryJob, job) &&
          token == _sellingSummaryRequestToken) {
        _sellingSummaryJob = null;
        _sellingSummaryJobKey = null;
      }
    }
  }

  String _sellingSummaryRequestKey({String? documentType}) {
    final salesScope = _shouldScopeSalesData
        ? (_currentSalesPerson?.trim() ?? '')
        : _sellingCustomerTypeFilter.trim();
    return [
      _sellingPeriodYear,
      _sellingPeriodMonth,
      _sellingCompanyFilter.trim(),
      salesScope,
      documentType?.trim() ?? 'all',
    ].join('|');
  }

  bool _isCurrentSellingSummaryRequest(int token) {
    return token == _sellingSummaryRequestToken;
  }

  Future<void> _refreshSellingSummaries(
    int token, {
    required bool forceRemote,
    String? documentType,
  }) async {
    if (!forceRemote &&
        await _tryApplyCachedSellingAnalyticsSections(token, documentType)) {
      _isOrderSummaryLoading = false;
      _orderSummaryError = null;
      notifyListeners();
      return;
    }

    _isOrderSummaryLoading = true;
    _orderSummaryError = null;
    notifyListeners();

    try {
      await _frappeService.ensureLoggedIn();
      if (!_isCurrentSellingSummaryRequest(token)) return;
      if (await _refreshSellingSummariesFromMobileAnalytics(
        token,
        forceRemote: forceRemote,
        documentType: documentType,
      )) {
        _orderSummaryError = null;
        return;
      }
      if (!_isCurrentSellingSummaryRequest(token)) return;
      if (documentType?.trim().isNotEmpty == true) {
        final type = documentType!.trim();
        final fallbackSection = await _fallbackSellingAnalyticsSection(
          doctype: type,
          dateField: _sellingAnalyticsDateField(type),
        );
        if (!_isCurrentSellingSummaryRequest(token)) return;
        _applySellingAnalyticsSection(type, fallbackSection);
        _orderSummaryError = null;
        return;
      }
      final salesScopeFilters = await _salesDocumentScopeFilters('Sales Order');
      final deliveryScopeFilters = await _salesDocumentScopeFilters(
        'Delivery Note',
      );
      final invoiceScopeFilters = await _salesDocumentScopeFilters(
        'Sales Invoice',
      );
      final salesFilters = [
        ...await _sellingDocumentFilters(
          'transaction_date',
          doctype: 'Sales Order',
        ),
        ...?salesScopeFilters,
      ];
      final deliveryFilters = [
        ...await _sellingDocumentFilters(
          'posting_date',
          doctype: 'Delivery Note',
        ),
        ...?deliveryScopeFilters,
      ];
      final invoiceFilters = [
        ...await _sellingDocumentFilters(
          'posting_date',
          doctype: 'Sales Invoice',
        ),
        ...?invoiceScopeFilters,
      ];
      final salesTrend = _emptySellingTrendPoints();
      final deliveryTrend = _emptySellingTrendPoints();
      final invoiceTrend = _emptySellingTrendPoints();
      var salesTotal = 0.0;
      var salesDocumentCount = 0;
      await _forEachResourcePage(
        doctype: 'Sales Order',
        fields: const [
          'name',
          'base_net_total',
          'net_total',
          'grand_total',
          'transaction_date',
          'customer',
          'status',
          'docstatus',
        ],
        filters: salesFilters,
        onRow: (row) async {
          if (!_isActiveSellingTrendRow(row)) return;
          if (salesScopeFilters == null &&
              !await _salesDocumentBelongsToCurrentSalesPerson(
                doctype: 'Sales Order',
                name: row['name']?.toString() ?? '',
              )) {
            return;
          }
          final value = _sellingAnalyticsValue(row);
          salesTotal += value;
          salesDocumentCount++;
          _addSellingTrendPoint(
            salesTrend,
            dateRaw: row['transaction_date'],
            amount: value,
          );
        },
      );

      var deliveryTotal = 0.0;
      var deliveryCount = 0;
      await _forEachResourcePage(
        doctype: 'Delivery Note',
        fields: const [
          'name',
          'base_net_total',
          'net_total',
          'grand_total',
          'posting_date',
          'customer',
          'status',
          'docstatus',
        ],
        filters: deliveryFilters,
        onRow: (row) async {
          if (!_isActiveSellingTrendRow(row)) return;
          if (deliveryScopeFilters == null &&
              !await _salesDocumentBelongsToCurrentSalesPerson(
                doctype: 'Delivery Note',
                name: row['name']?.toString() ?? '',
              )) {
            return;
          }
          final value = _sellingAnalyticsValue(row);
          deliveryTotal += value;
          deliveryCount++;
          _addSellingTrendPoint(
            deliveryTrend,
            dateRaw: row['posting_date'],
            amount: value,
          );
        },
      );

      var invoiceTotal = 0.0;
      var invoiceCount = 0;
      await _forEachResourcePage(
        doctype: 'Sales Invoice',
        fields: const [
          'name',
          'base_net_total',
          'net_total',
          'grand_total',
          'posting_date',
          'customer',
          'status',
          'docstatus',
        ],
        filters: invoiceFilters,
        onRow: (row) async {
          if (!_isActiveSellingTrendRow(row)) return;
          if (invoiceScopeFilters == null &&
              !await _salesDocumentBelongsToCurrentSalesPerson(
                doctype: 'Sales Invoice',
                name: row['name']?.toString() ?? '',
              )) {
            return;
          }
          final value = _sellingAnalyticsValue(row);
          invoiceTotal += value;
          invoiceCount++;
          _addSellingTrendPoint(
            invoiceTrend,
            dateRaw: row['posting_date'],
            amount: value,
          );
        },
      );

      if (!_isCurrentSellingSummaryRequest(token)) return;
      _salesOrderSummary = DocumentSummary(
        totalValue: salesTotal,
        documentCount: salesDocumentCount,
      );
      _salesOrderTrendPoints = salesTrend;
      _deliveryNoteTrendPoints = deliveryTrend;
      _salesInvoiceTrendPoints = invoiceTrend;
      _deliveryNoteSummary = DocumentSummary(
        totalValue: deliveryTotal,
        documentCount: deliveryCount,
      );
      _salesInvoiceSummary = DocumentSummary(
        totalValue: invoiceTotal,
        documentCount: invoiceCount,
      );
      _orderSummaryError = null;
    } catch (err) {
      if (!_isCurrentSellingSummaryRequest(token)) return;
      _orderSummaryError = err.toString();
    } finally {
      if (_isCurrentSellingSummaryRequest(token)) {
        _isOrderSummaryLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _refreshSellingSummariesFromMobileAnalytics(
    int token, {
    required bool forceRemote,
    String? documentType,
  }) async {
    try {
      final documentTypes = _sellingAnalyticsDocumentTypes(documentType);
      final missingDocumentTypes = <String>[];

      if (!forceRemote) {
        for (final type in documentTypes) {
          final cached = await _readSellingAnalyticsSectionFromDb(type);
          if (!_isCurrentSellingSummaryRequest(token)) return true;
          if (cached == null) {
            missingDocumentTypes.add(type);
            continue;
          }
          _applySellingAnalyticsSection(type, cached);
        }
        if (missingDocumentTypes.length != documentTypes.length) {
          notifyListeners();
        }
        if (missingDocumentTypes.isEmpty) return true;
      } else {
        missingDocumentTypes.addAll(documentTypes);
      }

      final fetchedSections = await Future.wait(
        missingDocumentTypes.map(
          (type) =>
              _sellingAnalyticsBySalesPersonSection(
                doctype: type,
                dateField: _sellingAnalyticsDateField(type),
              ).timeout(
                _sellingTrendRemoteTimeout,
                onTimeout: () => throw _SellingAnalyticsTimeoutException(type),
              ),
        ),
      );

      if (!_isCurrentSellingSummaryRequest(token)) return true;
      for (var index = 0; index < missingDocumentTypes.length; index++) {
        final type = missingDocumentTypes[index];
        final section = fetchedSections[index];
        _applySellingAnalyticsSection(type, section);
        await _writeSellingAnalyticsSectionToDb(type, section);
      }
      return true;
    } on _SellingAnalyticsTimeoutException catch (err) {
      if (_isCurrentSellingSummaryRequest(token)) {
        _orderSummaryError =
            'Sales Analytics ${err.documentType} masih berat diproses ERPNext. '
            'Data lokal tetap digunakan jika tersedia, tarik ulang untuk coba refresh.';
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _tryApplyCachedSellingAnalyticsSections(
    int token,
    String? documentType,
  ) async {
    final documentTypes = _sellingAnalyticsDocumentTypes(documentType);
    var hasAllCached = true;
    var appliedAny = false;
    for (final type in documentTypes) {
      final cached = await _readSellingAnalyticsSectionFromDb(type);
      if (!_isCurrentSellingSummaryRequest(token)) return true;
      if (cached == null) {
        hasAllCached = false;
        continue;
      }
      _applySellingAnalyticsSection(type, cached);
      appliedAny = true;
    }
    if (appliedAny) notifyListeners();
    return hasAllCached;
  }

  List<String> _sellingAnalyticsDocumentTypes(String? documentType) {
    final normalized = documentType?.trim();
    const supported = ['Sales Order', 'Delivery Note', 'Sales Invoice'];
    if (normalized == null || normalized.isEmpty) return supported;
    return supported.contains(normalized) ? [normalized] : supported;
  }

  String _sellingAnalyticsDateField(String documentType) {
    return documentType == 'Sales Order' ? 'transaction_date' : 'posting_date';
  }

  void _applySellingAnalyticsSection(
    String documentType,
    _MobileAnalyticsSection section,
  ) {
    switch (documentType) {
      case 'Delivery Note':
        _deliveryNoteSummary = section.summary;
        _deliveryNoteTrendPoints = section.trend;
        break;
      case 'Sales Invoice':
        _salesInvoiceSummary = section.summary;
        _salesInvoiceTrendPoints = section.trend;
        break;
      case 'Sales Order':
      default:
        _salesOrderSummary = section.summary;
        _salesOrderTrendPoints = section.trend;
        break;
    }
  }

  Future<_MobileAnalyticsSection?> _readSellingAnalyticsSectionFromDb(
    String documentType,
  ) async {
    final json = await LocalAppDatabase.instance.readJson(
      _sellingAnalyticsSectionCacheKey(documentType),
    );
    if (json == null) return null;
    try {
      return _mobileAnalyticsSectionFromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSellingAnalyticsSectionToDb(
    String documentType,
    _MobileAnalyticsSection section,
  ) async {
    await LocalAppDatabase.instance.writeJson(
      _sellingAnalyticsSectionCacheKey(documentType),
      _mobileAnalyticsSectionToJson(section),
      ttl: _sellingTrendCacheTtl,
    );
  }

  String _sellingAnalyticsSectionCacheKey(String documentType) {
    final site = _frappeService.baseUrl.trim();
    final user = _currentUser?.trim() ?? _frappeService.username?.trim() ?? '';
    return [
      _sellingTrendCachePrefix,
      'section',
      site,
      user,
      _sellingPeriodYear,
      _sellingPeriodMonth,
      _sellingCompanyFilter.trim(),
      _shouldScopeSalesData
          ? (_currentSalesPerson?.trim() ?? '')
          : _sellingCustomerTypeFilter.trim(),
      documentType.trim(),
    ].join('|');
  }

  Map<String, dynamic> _mobileAnalyticsSectionToJson(
    _MobileAnalyticsSection section,
  ) {
    return {
      'summary': section.summary.toJson(),
      'trend': section.trend
          .map(
            (point) => {
              'label': point.label,
              'value': point.value,
              'documentCount': point.documentCount,
            },
          )
          .toList(),
    };
  }

  _MobileAnalyticsSection _mobileAnalyticsSectionFromJson(Object? value) {
    final json = value is Map<String, dynamic>
        ? value
        : Map<String, dynamic>.from(value as Map);
    final summaryRaw = json['summary'];
    final summary = summaryRaw is Map<String, dynamic>
        ? DocumentSummary.fromJson(summaryRaw)
        : DocumentSummary.fromJson(
            Map<String, dynamic>.from(summaryRaw as Map),
          );
    final trendRaw = json['trend'];
    final trend = trendRaw is List
        ? trendRaw
              .whereType<Map>()
              .map((raw) => Map<String, dynamic>.from(raw))
              .map(
                (point) => DocumentTrendPoint(
                  label: point['label']?.toString() ?? '',
                  value: (point['value'] as num?)?.toDouble() ?? 0,
                  documentCount: (point['documentCount'] as num?)?.toInt() ?? 0,
                ),
              )
              .toList()
        : const <DocumentTrendPoint>[];
    return _MobileAnalyticsSection(summary: summary, trend: trend);
  }

  Future<_MobileAnalyticsSection> _sellingAnalyticsBySalesPersonSection({
    required String doctype,
    required String dateField,
  }) async {
    try {
      final selectedSalesGroup = _selectedSellingParentSalesPerson();
      final scopedSalesPerson = _shouldScopeSalesData
          ? await _salesPersonScopeName()
          : null;
      final analytics = await _fetchSalesAnalyticsBySalesPersonSection(
        basedOn: doctype,
        year: _sellingPeriodYear,
        month: _sellingPeriodMonth,
        company: _sellingCompanyFilter,
        salesPerson: scopedSalesPerson ?? selectedSalesGroup ?? '',
      );
      if (analytics != null) return analytics;
    } catch (_) {
      // Fall back to document API when the custom report is not installed.
    }

    return _fallbackSellingAnalyticsSection(
      doctype: doctype,
      dateField: dateField,
    );
  }

  Future<_MobileAnalyticsSection> _fallbackSellingAnalyticsSection({
    required String doctype,
    required String dateField,
  }) async {
    final scopeFilters = await _salesDocumentScopeFilters(doctype);
    final filters = [
      ...await _sellingDocumentFilters(dateField, doctype: doctype),
      ...?scopeFilters,
    ];
    final trend = _emptySellingTrendPoints();
    var total = 0.0;
    var count = 0;

    await _forEachResourcePage(
      doctype: doctype,
      fields: [
        'name',
        'base_net_total',
        'net_total',
        'grand_total',
        dateField,
        'customer',
        'status',
        'docstatus',
      ],
      filters: filters,
      onRow: (row) async {
        if (!_isActiveSellingTrendRow(row)) return;
        if (scopeFilters == null &&
            !await _salesDocumentBelongsToCurrentSalesPerson(
              doctype: doctype,
              name: row['name']?.toString() ?? '',
            )) {
          return;
        }
        final value = _sellingAnalyticsValue(row);
        total += value;
        count++;
        _addSellingTrendPoint(trend, dateRaw: row[dateField], amount: value);
      },
    );

    return _MobileAnalyticsSection(
      summary: DocumentSummary(totalValue: total, documentCount: count),
      trend: trend,
    );
  }

  Future<void> setSellingPeriod({
    required int year,
    required int month,
    String? company,
    String? customerType,
    String? documentType,
  }) async {
    final nextCompany = company ?? _sellingCompanyFilter;
    final nextCustomerType = customerType ?? _sellingCustomerTypeFilter;
    if (_sellingPeriodYear == year &&
        _sellingPeriodMonth == month &&
        _sellingCompanyFilter == nextCompany &&
        _sellingCustomerTypeFilter == nextCustomerType) {
      return;
    }
    _sellingPeriodYear = year;
    _sellingPeriodMonth = month;
    _sellingCompanyFilter = nextCompany;
    _sellingCustomerTypeFilter = nextCustomerType;
    _salesOrderSummary = const DocumentSummary();
    _deliveryNoteSummary = const DocumentSummary();
    _salesInvoiceSummary = const DocumentSummary();
    _salesOrderTrendPoints = _emptySellingTrendPoints();
    _deliveryNoteTrendPoints = _emptySellingTrendPoints();
    _salesInvoiceTrendPoints = _emptySellingTrendPoints();
    notifyListeners();
    await Future.wait([
      switch (documentType) {
        'Delivery Note' => fetchDeliveryNotesFromFrappe(),
        'Sales Invoice' => fetchSalesInvoicesFromFrappe(),
        _ => fetchSalesOrdersFromFrappe(),
      },
      refreshSellingSummaries(documentType: documentType),
    ]);
  }

  void updateSellingFilterSnapshot({
    required int year,
    required int month,
    String? company,
    String? customerType,
  }) {
    final nextCompany = company ?? _sellingCompanyFilter;
    final nextCustomerType = customerType ?? _sellingCustomerTypeFilter;
    if (_sellingPeriodYear == year &&
        _sellingPeriodMonth == month &&
        _sellingCompanyFilter == nextCompany &&
        _sellingCustomerTypeFilter == nextCustomerType) {
      return;
    }
    _sellingPeriodYear = year;
    _sellingPeriodMonth = month;
    _sellingCompanyFilter = nextCompany;
    _sellingCustomerTypeFilter = nextCustomerType;
    notifyListeners();
  }

  Future<void> loadSellingFilterOptions() async {
    if (!_isAuthenticated) return;
    try {
      await _frappeService.ensureLoggedIn();
      final companyRows = await _fetchAllResourcePages(
        doctype: 'Company',
        fields: const ['name'],
        orderBy: 'name asc',
        maxRows: 500,
      );
      final companies =
          companyRows
              .map((row) => row['name']?.toString() ?? '')
              .where((name) => name.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      _sellingCompanies = companies;
    } catch (_) {
      _sellingCompanies = const [];
    }

    try {
      final rows = await _fetchAllResourcePages(
        doctype: 'Sales Person',
        fields: const ['name', 'parent_sales_person', 'is_group', 'lft'],
        filters: const [
          ['is_group', '=', 1],
        ],
        orderBy: 'lft asc, name asc',
        maxRows: null,
      );
      final roots = rows
          .where(
            (row) =>
                (row['parent_sales_person']?.toString().trim() ?? '').isEmpty,
          )
          .map((row) => row['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toSet();
      final groups =
          rows
              .where(
                (row) => roots.contains(
                  row['parent_sales_person']?.toString() ?? '',
                ),
              )
              .map((row) => row['name']?.toString() ?? '')
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      _sellingSalesGroups = groups;
      if (_sellingCustomerTypeFilter != 'all' &&
          !groups.contains(_sellingCustomerTypeFilter)) {
        _sellingCustomerTypeFilter = 'all';
      }
    } catch (_) {
      _sellingSalesGroups = const [];
      _sellingCustomerTypeFilter = 'all';
    }
    notifyListeners();
  }

  List<DocumentTrendPoint> _emptySellingTrendPoints() {
    if (_sellingPeriodMonth == 0) {
      const labels = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Mei',
        'Jun',
        'Jul',
        'Agu',
        'Sep',
        'Okt',
        'Nov',
        'Des',
      ];
      return [for (final label in labels) DocumentTrendPoint(label: label)];
    }

    return _emptyWeeklyTrendPoints(_sellingPeriodYear, _sellingPeriodMonth);
  }

  void _addSellingTrendPoint(
    List<DocumentTrendPoint> points, {
    required dynamic dateRaw,
    required double amount,
  }) {
    final date = DateTime.tryParse(dateRaw?.toString() ?? '');
    if (date == null || date.year != _sellingPeriodYear) return;

    final index = _sellingPeriodMonth == 0
        ? date.month - 1
        : _weeklyTrendIndex(points, date);
    if (index < 0 || index >= points.length) return;
    points[index] = points[index].add(amount);
  }

  Future<void> refreshBuyingSummaries() async {
    _isOrderSummaryLoading = true;
    _orderSummaryError = null;
    notifyListeners();

    try {
      await _frappeService.ensureLoggedIn();
      if (await _refreshBuyingSummariesFromMobileAnalytics()) {
        _orderSummaryError = null;
        return;
      }
      final buyingSupplierTypeIds = await _buyingSupplierTypeSupplierIds();
      final purchaseTrend = _emptyBuyingTrendPoints();
      final receiptTrend = _emptyBuyingTrendPoints();
      final invoiceTrend = _emptyBuyingTrendPoints();
      final materialRequestTrend = _emptyBuyingTrendPoints();
      var purchaseTotal = 0.0;
      var purchaseDocumentCount = 0;
      await _forEachResourcePage(
        doctype: 'Purchase Order',
        fields: const [
          'name',
          'base_net_total',
          'net_total',
          'grand_total',
          'status',
          'docstatus',
          'transaction_date',
          'supplier',
        ],
        filters: [
          ..._buyingPeriodFilters('transaction_date'),
          ['docstatus', '!=', 2],
        ],
        onRow: (row) {
          if (!_matchesBuyingSupplierType(row, buyingSupplierTypeIds)) return;
          if (!_isActivePurchaseOrderTrendRow(row)) return;
          final value = _buyingAnalyticsValue(row);
          purchaseTotal += value;
          purchaseDocumentCount++;
          _addBuyingTrendPoint(
            purchaseTrend,
            dateRaw: row['transaction_date'],
            amount: value,
          );
        },
      );

      var receiptTotal = 0.0;
      var receiptCount = 0;
      await _forEachResourcePage(
        doctype: 'Purchase Receipt',
        fields: const [
          'name',
          'supplier',
          'grand_total',
          'status',
          'docstatus',
          'posting_date',
        ],
        filters: [
          ..._buyingPeriodFilters('posting_date'),
          ['docstatus', '!=', 2],
        ],
        onRow: (row) {
          if (!_matchesBuyingSupplierType(row, buyingSupplierTypeIds)) return;
          if (!_isActiveBuyingTrendRow(row)) return;
          final value = NumParse.asDouble(row['grand_total']);
          receiptTotal += value;
          receiptCount++;
          _addBuyingTrendPoint(
            receiptTrend,
            dateRaw: row['posting_date'],
            amount: value,
          );
        },
      );

      var invoiceTotal = 0.0;
      var invoiceCount = 0;
      await _forEachResourcePage(
        doctype: 'Purchase Invoice',
        fields: const [
          'name',
          'supplier',
          'grand_total',
          'status',
          'docstatus',
          'posting_date',
        ],
        filters: [
          ..._buyingPeriodFilters('posting_date'),
          ['docstatus', '!=', 2],
        ],
        onRow: (row) {
          if (!_matchesBuyingSupplierType(row, buyingSupplierTypeIds)) return;
          if (!_isActiveBuyingTrendRow(row)) return;
          final value = NumParse.asDouble(row['grand_total']);
          invoiceTotal += value;
          invoiceCount++;
          _addBuyingTrendPoint(
            invoiceTrend,
            dateRaw: row['posting_date'],
            amount: value,
          );
        },
      );

      await _forEachResourcePage(
        doctype: 'Material Request',
        fields: const [
          'name',
          'total_qty',
          'status',
          'docstatus',
          'transaction_date',
        ],
        filters: [
          ..._buyingPeriodFilters('transaction_date'),
          ['docstatus', '!=', 2],
        ],
        onRow: (row) {
          if (!_isActiveBuyingTrendRow(row)) return;
          final qty = NumParse.asDouble(row['total_qty']);
          _addBuyingTrendPoint(
            materialRequestTrend,
            dateRaw: row['transaction_date'],
            amount: qty <= 0 ? 1 : qty,
          );
        },
      );

      _purchaseOrderSummary = DocumentSummary(
        totalValue: purchaseTotal,
        documentCount: purchaseDocumentCount,
      );
      _purchaseReceiptSummary = DocumentSummary(
        totalValue: receiptTotal,
        documentCount: receiptCount,
      );
      _purchaseInvoiceSummary = DocumentSummary(
        totalValue: invoiceTotal,
        documentCount: invoiceCount,
      );
      _purchaseOrderTrendPoints = purchaseTrend;
      _purchaseReceiptTrendPoints = receiptTrend;
      _purchaseInvoiceTrendPoints = invoiceTrend;
      _materialRequestTrendPoints = materialRequestTrend;
      _orderSummaryError = null;
    } catch (err) {
      _orderSummaryError = err.toString();
    } finally {
      _isOrderSummaryLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _refreshBuyingSummariesFromMobileAnalytics() async {
    if (_buyingSupplierTypeFilter.trim().isNotEmpty &&
        _buyingSupplierTypeFilter.trim().toLowerCase() != 'all') {
      return false;
    }

    try {
      final purchaseOrder = await _fetchErpNextAnalyticsSection(
        reportName: 'Purchase Analytics',
        treeType: 'Supplier',
        docType: 'Purchase Order',
        year: _buyingPeriodYear,
        month: _buyingPeriodMonth,
        company: _buyingCompanyFilter,
      );
      final purchaseReceipt = await _fetchErpNextAnalyticsSection(
        reportName: 'Purchase Analytics',
        treeType: 'Supplier',
        docType: 'Purchase Receipt',
        year: _buyingPeriodYear,
        month: _buyingPeriodMonth,
        company: _buyingCompanyFilter,
      );
      final purchaseInvoice = await _fetchErpNextAnalyticsSection(
        reportName: 'Purchase Analytics',
        treeType: 'Supplier',
        docType: 'Purchase Invoice',
        year: _buyingPeriodYear,
        month: _buyingPeriodMonth,
        company: _buyingCompanyFilter,
      );
      final materialRequest = await _fetchMaterialRequestAnalyticsSection();
      if (purchaseOrder == null ||
          purchaseReceipt == null ||
          purchaseInvoice == null ||
          materialRequest == null) {
        return false;
      }

      _purchaseOrderSummary = purchaseOrder.summary;
      _purchaseOrderTrendPoints = purchaseOrder.trend;
      _purchaseReceiptSummary = purchaseReceipt.summary;
      _purchaseReceiptTrendPoints = purchaseReceipt.trend;
      _purchaseInvoiceSummary = purchaseInvoice.summary;
      _purchaseInvoiceTrendPoints = purchaseInvoice.trend;
      _materialRequestTrendPoints = materialRequest.trend;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<_MobileAnalyticsSection?>
  _fetchMaterialRequestAnalyticsSection() async {
    final trend = _emptyBuyingTrendPoints();
    var totalValue = 0.0;
    var documentCount = 0;
    await _forEachResourcePage(
      doctype: 'Material Request',
      fields: const [
        'name',
        'total_qty',
        'status',
        'docstatus',
        'transaction_date',
      ],
      filters: [
        ..._buyingPeriodFilters('transaction_date'),
        ['docstatus', '!=', 2],
      ],
      onRow: (row) {
        if (!_isActiveBuyingTrendRow(row)) return;
        final qty = NumParse.asDouble(row['total_qty']);
        final value = qty <= 0 ? 1.0 : qty;
        totalValue += value;
        documentCount++;
        _addBuyingTrendPoint(
          trend,
          dateRaw: row['transaction_date'],
          amount: value,
        );
      },
    );
    return _MobileAnalyticsSection(
      summary: DocumentSummary(
        totalValue: totalValue,
        documentCount: documentCount,
      ),
      trend: trend,
    );
  }

  Future<void> loadBuyingFilterOptions() async {
    if (!_isAuthenticated) return;
    try {
      await _frappeService.ensureLoggedIn();
      final rows = await _fetchAllResourcePages(
        doctype: 'Company',
        fields: const ['name'],
        orderBy: 'name asc',
        maxRows: 500,
      );
      _buyingCompanies =
          rows
              .map((row) => row['name']?.toString() ?? '')
              .where((name) => name.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      notifyListeners();
    } catch (_) {
      _buyingCompanies = const [];
      notifyListeners();
      // Filter options are helpful, but should not block buying data.
    }
  }

  Future<void> setBuyingPeriod({
    required int year,
    required int month,
    String? company,
    String? supplierType,
  }) async {
    final nextCompany = company ?? _buyingCompanyFilter;
    final nextSupplierType = supplierType ?? _buyingSupplierTypeFilter;
    if (_buyingPeriodYear == year &&
        _buyingPeriodMonth == month &&
        _buyingCompanyFilter == nextCompany &&
        _buyingSupplierTypeFilter == nextSupplierType) {
      return;
    }
    _buyingPeriodYear = year;
    _buyingPeriodMonth = month;
    _buyingCompanyFilter = nextCompany;
    if (_buyingSupplierTypeFilter != nextSupplierType) {
      _buyingSupplierTypeIdsCacheKey = null;
      _buyingSupplierTypeIdsCache = null;
    }
    _buyingSupplierTypeFilter = nextSupplierType;
    notifyListeners();
    await Future.wait([
      fetchPurchaseOrdersFromFrappe(),
      fetchPurchaseReceiptsFromFrappe(),
      fetchPurchaseInvoicesFromFrappe(),
      fetchMaterialRequestsFromFrappe(),
      refreshBuyingSummaries(),
    ]);
  }

  void updateBuyingFilterSnapshot({
    required int year,
    required int month,
    String? company,
    String? supplierType,
  }) {
    final nextCompany = company ?? _buyingCompanyFilter;
    final nextSupplierType = supplierType ?? _buyingSupplierTypeFilter;
    if (_buyingPeriodYear == year &&
        _buyingPeriodMonth == month &&
        _buyingCompanyFilter == nextCompany &&
        _buyingSupplierTypeFilter == nextSupplierType) {
      return;
    }
    _buyingPeriodYear = year;
    _buyingPeriodMonth = month;
    _buyingCompanyFilter = nextCompany;
    if (_buyingSupplierTypeFilter != nextSupplierType) {
      _buyingSupplierTypeIdsCacheKey = null;
      _buyingSupplierTypeIdsCache = null;
    }
    _buyingSupplierTypeFilter = nextSupplierType;
    notifyListeners();
  }

  List<DocumentTrendPoint> _emptyBuyingTrendPoints() {
    if (_buyingPeriodMonth == 0) {
      const labels = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Mei',
        'Jun',
        'Jul',
        'Agu',
        'Sep',
        'Okt',
        'Nov',
        'Des',
      ];
      return [for (final label in labels) DocumentTrendPoint(label: label)];
    }

    return _emptyWeeklyTrendPoints(_buyingPeriodYear, _buyingPeriodMonth);
  }

  void _addBuyingTrendPoint(
    List<DocumentTrendPoint> points, {
    required dynamic dateRaw,
    required double amount,
  }) {
    final date = DateTime.tryParse(dateRaw?.toString() ?? '');
    if (date == null || date.year != _buyingPeriodYear) return;

    final index = _buyingPeriodMonth == 0
        ? date.month - 1
        : _weeklyTrendIndex(points, date);
    if (index < 0 || index >= points.length) return;
    points[index] = points[index].add(amount);
  }

  Future<_MobileAnalyticsSection?> _fetchErpNextAnalyticsSection({
    required String reportName,
    required String treeType,
    required String docType,
    required int year,
    required int month,
    required String company,
  }) async {
    final range = month == 0 ? 'Monthly' : 'Weekly';
    final reportMonth = month;
    final from = reportMonth == 0
        ? DateTime(year)
        : DateTime(year, reportMonth);
    final to = reportMonth == 0
        ? DateTime(year, 12, 31)
        : DateTime(year, reportMonth + 1, 0);
    final response = await _frappeService.callMethod(
      'frappe.desk.query_report.run',
      args: {
        'report_name': reportName,
        'filters': {
          'tree_type': treeType,
          'doc_type': docType,
          'value_quantity': 'Value',
          'range': range,
          'from_date': DateRangePresets.toFrappeDate(from),
          'to_date': DateRangePresets.toFrappeDate(to),
          if (company.trim().isNotEmpty) 'company': company.trim(),
          'show_aggregate_value_from_subsidiary_companies': 0,
        },
        'ignore_prepared_report': true,
        'are_default_filters': false,
      },
    );
    return _analyticsSectionFromQueryReport(response, year, reportMonth);
  }

  Future<_MobileAnalyticsSection?> _fetchSalesAnalyticsBySalesPersonSection({
    required String basedOn,
    required int year,
    required int month,
    required String company,
    required String salesPerson,
  }) async {
    final range = month == 0 ? 'Monthly' : 'Weekly';
    final reportMonth = month;
    final from = reportMonth == 0
        ? DateTime(year)
        : DateTime(year, reportMonth);
    final to = reportMonth == 0
        ? DateTime(year, 12, 31)
        : DateTime(year, reportMonth + 1, 0);
    final response = await _frappeService.callMethod(
      'frappe.desk.query_report.run',
      args: {
        'report_name': 'Sales Analytics by Sales Person',
        'filters': {
          'tree_type': 'Customer',
          if (company.trim().isNotEmpty) 'company': company.trim(),
          'document_type': basedOn,
          'doc_type': basedOn,
          'based_on': basedOn,
          'from_date': DateRangePresets.toFrappeDate(from),
          'to_date': DateRangePresets.toFrappeDate(to),
          if (salesPerson.trim().isNotEmpty) 'sales_person': salesPerson.trim(),
          'range': range,
          'value_quantity': 'Value',
        },
        'ignore_prepared_report': true,
        'are_default_filters': false,
      },
    );
    return _analyticsSectionFromQueryReport(response, year, reportMonth);
  }

  Future<void> refreshInactiveCustomers({
    int daysSinceLastOrder = 60,
    List<String> doctypes = const ['Sales Order'],
    bool forceRemote = false,
  }) async {
    if (_isInactiveCustomersLoading && !forceRemote) return;
    final selectedDoctypes = doctypes
        .map((doctype) => doctype.trim())
        .where(
          (doctype) => doctype == 'Sales Order' || doctype == 'Sales Invoice',
        )
        .toSet()
        .toList();
    if (selectedDoctypes.isEmpty) {
      selectedDoctypes.add('Sales Order');
    }
    _inactiveCustomersDays = daysSinceLastOrder;
    _inactiveCustomerDoctypes = List.unmodifiable(selectedDoctypes);
    _isInactiveCustomersLoading = true;
    _inactiveCustomersError = null;
    notifyListeners();

    try {
      if (_shouldScopeSalesData) {
        _inactiveCustomers = await _fetchScopedInactiveCustomers(
          daysSinceLastOrder: daysSinceLastOrder,
          doctypes: selectedDoctypes,
        );
        return;
      }

      final customers = <InactiveCustomer>[];
      for (final doctype in selectedDoctypes) {
        final response = await _frappeService.callMethod(
          'frappe.desk.query_report.run',
          args: {
            'report_name': 'Inactive Customers',
            'filters': {
              'days_since_last_order': daysSinceLastOrder,
              'doctype': doctype,
            },
            'ignore_prepared_report': true,
            'are_default_filters': false,
          },
        );
        final report = _queryReportPayload(response);
        if (report == null) {
          throw Exception('Response report Inactive Customers tidak valid.');
        }
        final columns = _queryReportColumns(report['columns']);
        final rows = _queryReportRows(report['result'] ?? report['data']);
        customers.addAll(
          rows
              .map((row) => _queryReportRowMap(row, columns))
              .where((row) => row.isNotEmpty && !_isQueryReportTotalRow(row))
              .map(
                (row) =>
                    InactiveCustomer.fromReportRow(row, documentType: doctype),
              )
              .where(
                (customer) =>
                    customer.customer.isNotEmpty ||
                    customer.customerName.isNotEmpty,
              ),
        );
      }

      customers.sort((a, b) {
        final daysCompare = b.daysSinceLastOrder.compareTo(
          a.daysSinceLastOrder,
        );
        if (daysCompare != 0) return daysCompare;
        return a.displayName.compareTo(b.displayName);
      });

      _inactiveCustomers = customers;
    } catch (error, stackTrace) {
      developer.log(
        'Failed to load inactive customers',
        error: error,
        stackTrace: stackTrace,
      );
      _inactiveCustomersError = error.toString().replaceFirst(
        'Exception: ',
        '',
      );
    } finally {
      _isInactiveCustomersLoading = false;
      notifyListeners();
    }
  }

  Future<List<InactiveCustomer>> _fetchScopedInactiveCustomers({
    required int daysSinceLastOrder,
    required List<String> doctypes,
  }) async {
    if (_currentSalesPerson == null || _currentSalesPerson!.isEmpty) {
      await resolveCurrentSalesIdentity();
    }
    final scopedCustomers = await fetchSalesCustomers();
    final customerIds = scopedCustomers
        .map((customer) => customer.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (customerIds.isEmpty) return const [];

    final customerMeta = {
      for (final customer in scopedCustomers)
        customer.id.trim(): (
          name: customer.name.trim().isNotEmpty
              ? customer.name.trim()
              : customer.id.trim(),
          address: customer.address.trim(),
        ),
    };
    final today = DateTime.now();
    final results = <InactiveCustomer>[];

    for (final doctype in doctypes) {
      final spec = _inactiveDocumentSpec(doctype);
      final buckets = {
        for (final customerId in customerIds)
          customerId: _InactiveCustomerAccumulator(
            doctype: spec.doctype,
            customer: customerId,
            customerName: customerMeta[customerId]?.name ?? customerId,
          ),
      };

      for (var start = 0; start < customerIds.length; start += 80) {
        final end = start + 80 > customerIds.length
            ? customerIds.length
            : start + 80;
        final chunk = customerIds.sublist(start, end);
        try {
          final rows = await _fetchAllResourcePages(
            doctype: spec.doctype,
            fields: [
              'name',
              'customer',
              'customer_name',
              'grand_total',
              spec.dateField,
            ],
            filters: [
              ['docstatus', '!=', 2],
              ['customer', 'in', chunk],
            ],
            orderBy: '${spec.dateField} desc, modified desc',
            maxRows: null,
          );
          for (final row in rows) {
            final customer = row['customer']?.toString().trim() ?? '';
            final bucket = buckets[customer];
            if (bucket == null) continue;
            bucket.addDocument(
              name: row['name']?.toString().trim() ?? '',
              date: _parseFrappeDate(row[spec.dateField]),
              amount: NumParse.asDouble(row['grand_total']),
              customerName: row['customer_name']?.toString().trim() ?? '',
            );
          }
        } catch (error, stackTrace) {
          developer.log(
            'Failed to load scoped inactive ${spec.doctype} rows',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }

      results.addAll(
        buckets.values.map((bucket) {
          final lastDate = bucket.lastOrderDate;
          final days = lastDate == null
              ? daysSinceLastOrder
              : _daysSince(lastDate, today);
          if (lastDate != null && days < daysSinceLastOrder) return null;
          return bucket.toInactiveCustomer(daysSinceLastOrder: days);
        }).whereType<InactiveCustomer>(),
      );
    }

    results.sort((a, b) {
      final daysCompare = b.daysSinceLastOrder.compareTo(a.daysSinceLastOrder);
      if (daysCompare != 0) return daysCompare;
      return a.displayName.compareTo(b.displayName);
    });
    return results;
  }

  _InactiveDocumentSpec _inactiveDocumentSpec(String doctype) {
    return doctype == 'Sales Invoice'
        ? const _InactiveDocumentSpec(
            doctype: 'Sales Invoice',
            dateField: 'posting_date',
          )
        : const _InactiveDocumentSpec(
            doctype: 'Sales Order',
            dateField: 'transaction_date',
          );
  }

  DateTime? _parseFrappeDate(dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return DateTime.tryParse(text.length > 10 ? text.substring(0, 10) : text);
  }

  int _daysSince(DateTime date, DateTime today) {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(today.year, today.month, today.day);
    return end.difference(start).inDays;
  }

  _MobileAnalyticsSection? _analyticsSectionFromQueryReport(
    dynamic response,
    int year,
    int month,
  ) {
    final report = _queryReportPayload(response);
    if (report == null) return null;
    final columns = _queryReportColumns(report['columns']);
    final rows = _queryReportRows(report['result'] ?? report['data']);
    var periodColumns = _queryReportPeriodColumns(columns, month);
    if (periodColumns.isEmpty) {
      periodColumns = _queryReportPeriodColumnsFromRows(rows, month);
    }
    if (periodColumns.isEmpty) return null;

    final trend = _emptyAnalyticsTrend(
      year,
      month,
      periodColumns: periodColumns,
    );
    final totalRowTrend = _emptyAnalyticsTrend(
      year,
      month,
      periodColumns: periodColumns,
    );
    var totalValue = 0.0;
    var totalRowValue = 0.0;
    var hasTotalRow = false;
    var rowCount = 0;
    for (final row in rows) {
      final mapped = _queryReportRowMap(row, columns);
      final isTotalRow = _isQueryReportTotalRow(mapped);
      var hasValue = false;
      for (final entry in periodColumns.entries) {
        final value = NumParse.asDouble(
          mapped[_queryReportPeriodColumnField(entry.value)],
        );
        if (isTotalRow) {
          hasTotalRow = true;
          totalRowValue += value;
          totalRowTrend[entry.key] = DocumentTrendPoint(
            label: totalRowTrend[entry.key].label,
            value: value,
            documentCount: value == 0 ? 0 : 1,
          );
          continue;
        }
        if (value == 0) continue;
        totalValue += value;
        hasValue = true;
        trend[entry.key] = trend[entry.key].add(value);
      }
      if (!isTotalRow && hasValue) rowCount++;
    }

    return _MobileAnalyticsSection(
      summary: DocumentSummary(
        totalValue: hasTotalRow ? totalRowValue : totalValue,
        documentCount: rowCount,
      ),
      trend: hasTotalRow ? totalRowTrend : trend,
    );
  }

  Map<String, dynamic>? _queryReportPayload(dynamic response) {
    if (response is! Map) return null;
    final map = Map<String, dynamic>.from(response);
    final message = map['message'];
    if (message is Map) return Map<String, dynamic>.from(message);
    return map;
  }

  List<Map<String, dynamic>> _queryReportColumns(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map((column) {
      if (column is String) {
        return {'label': column, 'fieldname': column};
      }
      if (column is Map) return Map<String, dynamic>.from(column);
      return <String, dynamic>{};
    }).toList();
  }

  List<dynamic> _queryReportRows(dynamic raw) => raw is List ? raw : const [];

  Map<String, dynamic> _queryReportRowMap(
    dynamic row,
    List<Map<String, dynamic>> columns,
  ) {
    if (row is Map) return Map<String, dynamic>.from(row);
    if (row is! List) return const {};
    final mapped = <String, dynamic>{};
    for (var i = 0; i < row.length && i < columns.length; i++) {
      final fieldname =
          columns[i]['fieldname']?.toString() ??
          columns[i]['field']?.toString() ??
          columns[i]['label']?.toString() ??
          '';
      if (fieldname.isEmpty) continue;
      mapped[fieldname] = row[i];
    }
    return mapped;
  }

  Map<int, String> _queryReportPeriodColumns(
    List<Map<String, dynamic>> columns,
    int month,
  ) {
    final result = <int, String>{};
    for (final column in columns) {
      final fieldname =
          column['fieldname']?.toString() ??
          column['field']?.toString() ??
          column['label']?.toString() ??
          '';
      if (fieldname.isEmpty) continue;
      final rawLabel = column['label']?.toString() ?? fieldname;
      final label = rawLabel.toLowerCase();
      final index = month > 0 && RegExp(r'(week|minggu)\s*\d+').hasMatch(label)
          ? result.length
          : _queryReportPeriodIndex(label, month);
      if (index == null) continue;
      result[index] = _queryReportPeriodColumnKey(fieldname, rawLabel);
    }
    return result;
  }

  Map<int, String> _queryReportPeriodColumnsFromRows(
    List<dynamic> rows,
    int month,
  ) {
    final result = <int, String>{};
    for (final row in rows) {
      if (row is! Map) continue;
      for (final key in row.keys) {
        final fieldname = key.toString();
        if (fieldname.trim().isEmpty) continue;
        final label = fieldname.toLowerCase();
        final index =
            month > 0 && RegExp(r'(week|minggu)\s*\d+').hasMatch(label)
            ? result.length
            : _queryReportPeriodIndex(label, month);
        if (index == null) continue;
        result[index] = _queryReportPeriodColumnKey(fieldname, fieldname);
      }
      if (result.isNotEmpty) break;
    }
    return result;
  }

  String _queryReportPeriodColumnKey(String fieldname, String label) {
    return '$fieldname\u001f$label';
  }

  String _queryReportPeriodColumnField(String value) {
    return value.split('\u001f').first;
  }

  String _queryReportPeriodColumnLabel(String value) {
    final parts = value.split('\u001f');
    return parts.length > 1 ? parts.sublist(1).join('\u001f') : value;
  }

  int? _queryReportPeriodIndex(String label, int month) {
    if (month == 0) {
      const aliases = [
        ['jan'],
        ['feb'],
        ['mar'],
        ['apr'],
        ['may', 'mei'],
        ['jun'],
        ['jul'],
        ['aug', 'agu'],
        ['sep'],
        ['oct', 'okt'],
        ['nov'],
        ['dec', 'des'],
      ];
      for (var i = 0; i < aliases.length; i++) {
        if (aliases[i].any(label.contains)) return i;
      }
      return null;
    }

    final match = RegExp(r'(week|minggu)\s*(\d+)').firstMatch(label);
    if (match != null) {
      final week = int.tryParse(match.group(2) ?? '');
      if (week != null) return (week - 1).clamp(0, 3);
    }

    final date = _queryReportPeriodDate(label);
    if (date != null && date.month == month) {
      return ((date.day - 1) ~/ 7).clamp(0, 3);
    }
    return null;
  }

  DateTime? _queryReportPeriodDate(String label) {
    final normalized = label
        .toLowerCase()
        .replaceAll(RegExp(r'[_]+'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final iso = RegExp(
      r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})',
    ).firstMatch(normalized);
    if (iso != null) {
      return DateTime.tryParse(
        '${iso.group(1)!}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}',
      );
    }

    final numeric = RegExp(
      r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})',
    ).firstMatch(normalized);
    if (numeric != null) {
      return DateTime.tryParse(
        '${numeric.group(3)!}-${numeric.group(2)!.padLeft(2, '0')}-${numeric.group(1)!.padLeft(2, '0')}',
      );
    }

    final named = RegExp(
      r'(\d{1,2})\s+(jan|feb|mar|apr|may|mei|jun|jul|aug|agu|sep|oct|okt|nov|dec|des)\w*\s+(\d{4})',
    ).firstMatch(normalized);
    if (named == null) return null;
    final month = _monthAliasNumber(named.group(2)!);
    if (month == null) return null;
    return DateTime.tryParse(
      '${named.group(3)!}-${month.toString().padLeft(2, '0')}-${named.group(1)!.padLeft(2, '0')}',
    );
  }

  int? _monthAliasNumber(String raw) {
    final value = raw.toLowerCase();
    const aliases = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'mei': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'agu': 8,
      'sep': 9,
      'oct': 10,
      'okt': 10,
      'nov': 11,
      'dec': 12,
      'des': 12,
    };
    final key = value.length <= 3 ? value : value.substring(0, 3);
    return aliases[key];
  }

  List<DocumentTrendPoint> _emptyAnalyticsTrend(
    int year,
    int month, {
    Map<int, String>? periodColumns,
  }) {
    if (month > 0 && periodColumns != null && periodColumns.isNotEmpty) {
      final entries = periodColumns.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return [
        for (var i = 0; i < entries.length; i++)
          DocumentTrendPoint(
            label: _weeklyReportLabel(
              _queryReportPeriodColumnLabel(entries[i].value),
              i,
            ),
          ),
      ];
    }

    if (month == 0) {
      const labels = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Mei',
        'Jun',
        'Jul',
        'Agu',
        'Sep',
        'Okt',
        'Nov',
        'Des',
      ];
      return [for (final label in labels) DocumentTrendPoint(label: label)];
    }
    return _emptyWeeklyTrendPoints(year, month);
  }

  List<DocumentTrendPoint> _emptyWeeklyTrendPoints(int year, int month) {
    if (month <= 0) return const [];
    final lastDay = DateTime(year, month + 1, 0).day;
    final weeks = <int>{};
    for (var day = 1; day <= lastDay; day++) {
      weeks.add(_isoWeekNumber(DateTime(year, month, day)));
    }
    final sortedWeeks = weeks.toList()..sort();
    return [
      for (final week in sortedWeeks) DocumentTrendPoint(label: 'Minggu $week'),
    ];
  }

  int _weeklyTrendIndex(List<DocumentTrendPoint> points, DateTime date) {
    final label = 'Minggu ${_isoWeekNumber(date)}';
    final index = points.indexWhere(
      (point) => point.label.toLowerCase() == label.toLowerCase(),
    );
    if (index >= 0) return index;
    return ((date.day - 1) ~/ 7).clamp(0, points.length - 1);
  }

  String _weeklyReportLabel(String rawLabel, int fallbackIndex) {
    final normalized = rawLabel
        .toLowerCase()
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final match = RegExp(r'(week|minggu)\s*(\d+)').firstMatch(normalized);
    final week = match == null ? null : int.tryParse(match.group(2) ?? '');
    return 'Minggu ${week ?? fallbackIndex + 1}';
  }

  int _isoWeekNumber(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    final thursday = normalized.add(Duration(days: 4 - normalized.weekday));
    final firstThursdayBase = DateTime(thursday.year, 1, 4);
    final firstThursday = firstThursdayBase.add(
      Duration(days: 4 - firstThursdayBase.weekday),
    );
    return 1 + thursday.difference(firstThursday).inDays ~/ 7;
  }

  bool _isQueryReportTotalRow(Map<String, dynamic> row) {
    const knownTotalFields = {
      'customer',
      'customer_name',
      'supplier',
      'supplier_name',
      'item',
      'item_name',
      'name',
      'account',
      'section',
    };

    for (final entry in row.entries) {
      final key = entry.key.toString().trim().toLowerCase();
      final value = entry.value?.toString().trim().toLowerCase();
      if (value != 'total') continue;
      if (knownTotalFields.contains(key)) return true;
    }

    return row.values.any(
      (value) => value?.toString().trim().toLowerCase() == 'total',
    );
  }

  Future<void> refreshAllSummaries({bool silent = false}) {
    if (!_isAuthenticated) return Future.value();

    final activeJob = _orderSummaryJob;
    if (activeJob != null) return activeJob;

    final job = _refreshAllSummaries(silent: silent);
    _orderSummaryJob = job.whenComplete(() {
      _orderSummaryJob = null;
    });
    return _orderSummaryJob!;
  }

  Future<void> _refreshAllSummaries({required bool silent}) async {
    _isOrderSummaryLoading = true;
    _summarySyncStatus = SummarySyncStatus.syncing;
    _summaryProcessedRows = 0;
    _orderSummaryError = null;
    notifyListeners();

    try {
      await _frappeService.ensureLoggedIn();
      final salesOrderFilters = await _sellingDocumentFilters(
        'transaction_date',
        doctype: 'Sales Order',
      );
      final deliveryFilters = await _sellingDocumentFilters(
        'posting_date',
        doctype: 'Delivery Note',
      );
      final invoiceFilters = await _sellingDocumentFilters(
        'posting_date',
        doctype: 'Sales Invoice',
      );
      var salesTotal = 0.0;
      var salesOpen = 0.0;
      var salesCompleted = 0.0;
      var salesDraftCount = 0;
      var salesOpenCount = 0;
      var salesCompletedCount = 0;
      var salesDocumentCount = 0;
      await _forEachResourcePage(
        doctype: 'Sales Order',
        fields: const [
          'name',
          'grand_total',
          'status',
          'docstatus',
          'delivery_date',
        ],
        filters: [
          ...salesOrderFilters,
          ['docstatus', '!=', 2],
        ],
        onRow: (row) {
          final order = SalesOrder.fromJson(row);
          salesDocumentCount++;
          salesTotal += order.value;
          if (order.docStatus == 0) salesDraftCount++;
          if (order.statusKey == SalesOrderStatusKey.completed) {
            salesCompleted += order.value;
            salesCompletedCount++;
          } else if (order.statusKey != SalesOrderStatusKey.cancelled &&
              order.statusKey != SalesOrderStatusKey.closed) {
            salesOpen += order.value;
            salesOpenCount++;
          }
        },
      );

      var deliveryTotal = 0.0;
      var deliveryCount = 0;
      await _forEachResourcePage(
        doctype: 'Delivery Note',
        fields: const ['name', 'grand_total'],
        filters: [
          ...deliveryFilters,
          ['docstatus', '!=', 2],
        ],
        onRow: (row) {
          deliveryTotal += NumParse.asDouble(row['grand_total']);
          deliveryCount++;
        },
      );

      var invoiceTotal = 0.0;
      var invoiceCount = 0;
      var unpaidSalesInvoices = 0;
      await _forEachResourcePage(
        doctype: 'Sales Invoice',
        fields: const ['name', 'grand_total', 'status', 'docstatus'],
        filters: [
          ...invoiceFilters,
          ['docstatus', '!=', 2],
        ],
        onRow: (row) {
          final invoice = SalesInvoice.fromJson(row);
          invoiceTotal += invoice.value;
          invoiceCount++;
          if (invoice.statusKey == InvoiceStatusKey.unpaid ||
              invoice.statusKey == InvoiceStatusKey.overdue ||
              invoice.statusKey == InvoiceStatusKey.partlyPaid) {
            unpaidSalesInvoices++;
          }
        },
      );

      var purchaseTotal = 0.0;
      var purchasePending = 0.0;
      var purchaseDelayed = 0.0;
      var purchaseDraftCount = 0;
      var purchasePendingCount = 0;
      var purchaseCompletedCount = 0;
      var purchaseDocumentCount = 0;
      await _forEachResourcePage(
        doctype: 'Purchase Order',
        fields: const [
          'name',
          'grand_total',
          'status',
          'docstatus',
          'transaction_date',
          'schedule_date',
        ],
        filters: [
          ..._buyingPeriodFilters('transaction_date'),
          ['docstatus', '!=', 2],
        ],
        onRow: (row) {
          final order = PurchaseOrder.fromJson(row);
          purchaseDocumentCount++;
          purchaseTotal += order.totalValue;
          if (order.docStatus == 0) purchaseDraftCount++;
          if (order.statusKey == PurchaseOrderStatusKey.completed) {
            purchaseCompletedCount++;
          } else if (order.statusKey != PurchaseOrderStatusKey.cancelled &&
              order.statusKey != PurchaseOrderStatusKey.closed) {
            purchasePending += order.totalValue;
            purchasePendingCount++;
          }
          if (order.isDelayed) purchaseDelayed += order.totalValue;
        },
      );

      var purchaseReceiptTotal = 0.0;
      var purchaseReceiptCount = 0;
      await _forEachResourcePage(
        doctype: 'Purchase Receipt',
        fields: const ['name', 'grand_total'],
        filters: [
          ..._buyingPeriodFilters('posting_date'),
          ['docstatus', '!=', 2],
        ],
        onRow: (row) {
          purchaseReceiptTotal += NumParse.asDouble(row['grand_total']);
          purchaseReceiptCount++;
        },
      );

      var purchaseInvoiceTotal = 0.0;
      var purchaseInvoiceCount = 0;
      var overduePurchaseInvoices = 0;
      await _forEachResourcePage(
        doctype: 'Purchase Invoice',
        fields: const ['name', 'grand_total', 'status', 'docstatus'],
        filters: [
          ..._buyingPeriodFilters('posting_date'),
          ['docstatus', '!=', 2],
        ],
        onRow: (row) {
          final invoice = PurchaseInvoice.fromJson(row);
          purchaseInvoiceTotal += invoice.value;
          purchaseInvoiceCount++;
          if (invoice.statusKey == InvoiceStatusKey.overdue) {
            overduePurchaseInvoices++;
          }
        },
      );

      final stockRows = <({String itemCode, int quantity})>[];
      await _forEachResourcePage(
        doctype: 'Bin',
        fields: const ['name', 'item_code', 'actual_qty'],
        filters: _warehouseScopeFilters(),
        onRow: (row) {
          final itemCode = row['item_code']?.toString() ?? '';
          if (itemCode.isEmpty) return;
          stockRows.add((
            itemCode: itemCode,
            quantity: NumParse.asInt(row['actual_qty']),
          ));
        },
      );
      final stockMeta = await _fetchItemMeta(
        stockRows.map((row) => row.itemCode).toSet(),
      );
      final stockAlerts = stockRows.where((row) {
        final reorderLevel = stockMeta[row.itemCode]?.reorderLevel ?? 0;
        return reorderLevel > 0
            ? row.quantity <= reorderLevel
            : row.quantity <= 0;
      }).length;

      _salesOrderSummary = DocumentSummary(
        totalValue: salesTotal,
        documentCount: salesDocumentCount,
      );
      _deliveryNoteSummary = DocumentSummary(
        totalValue: deliveryTotal,
        documentCount: deliveryCount,
      );
      _salesInvoiceSummary = DocumentSummary(
        totalValue: invoiceTotal,
        documentCount: invoiceCount,
      );
      _purchaseOrderSummary = DocumentSummary(
        totalValue: purchaseTotal,
        documentCount: purchaseDocumentCount,
      );
      _purchaseReceiptSummary = DocumentSummary(
        totalValue: purchaseReceiptTotal,
        documentCount: purchaseReceiptCount,
      );
      _purchaseInvoiceSummary = DocumentSummary(
        totalValue: purchaseInvoiceTotal,
        documentCount: purchaseInvoiceCount,
      );
      _dashboardSummary = DashboardSummary(
        salesTotal: salesTotal,
        salesOpen: salesOpen,
        salesCompleted: salesCompleted,
        salesDraftCount: salesDraftCount,
        salesOpenCount: salesOpenCount,
        salesCompletedCount: salesCompletedCount,
        purchaseTotal: purchaseTotal,
        purchasePending: purchasePending,
        purchaseDelayed: purchaseDelayed,
        purchaseDraftCount: purchaseDraftCount,
        purchasePendingCount: purchasePendingCount,
        purchaseCompletedCount: purchaseCompletedCount,
        unpaidSalesInvoices: unpaidSalesInvoices,
        overduePurchaseInvoices: overduePurchaseInvoices,
        stockAlerts: stockAlerts,
      );
      await _saveSummaryCache();
      _orderSummaryError = null;
      _summarySyncStatus = SummarySyncStatus.completed;
    } catch (err) {
      _orderSummaryError = err.toString();
      _summarySyncStatus = SummarySyncStatus.error;
    } finally {
      _isOrderSummaryLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchDeliveryNotesFromFrappe() async {
    final inFlight = _deliveryNotesFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchDeliveryNotesFromFrappe();
    _deliveryNotesFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_deliveryNotesFetchInFlight, request)) {
        _deliveryNotesFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchDeliveryNotesFromFrappe() async {
    if (_isSampleMode) {
      notifyListeners();
      return;
    }
    _isDeliveryNotesLoading = true;
    _deliveryNotesError = null;
    _hasMoreDeliveryNotes = true;
    _isMoreDeliveryNotesLoading = false;
    final version = ++_deliveryNoteQueryVersion;
    notifyListeners();

    try {
      await _frappeService.ensureLoggedIn();
      final docs = await _fetchDeliveryNotePage(limitStart: 0);
      if (version != _deliveryNoteQueryVersion) return;
      _deliveryNotes = docs;
      _hasMoreDeliveryNotes = docs.isNotEmpty;
      _deliveryNotesError = null;
    } catch (err) {
      if (version != _deliveryNoteQueryVersion) return;
      _deliveryNotesError = err.toString();
    } finally {
      if (version == _deliveryNoteQueryVersion) {
        _isDeliveryNotesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> fetchSalesInvoicesFromFrappe() async {
    final inFlight = _salesInvoicesFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchSalesInvoicesFromFrappe();
    _salesInvoicesFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_salesInvoicesFetchInFlight, request)) {
        _salesInvoicesFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchSalesInvoicesFromFrappe() async {
    if (_isSampleMode) {
      notifyListeners();
      return;
    }
    _isSalesInvoicesLoading = true;
    _salesInvoicesError = null;
    _hasMoreSalesInvoices = true;
    _isMoreSalesInvoicesLoading = false;
    final version = ++_salesInvoiceQueryVersion;
    notifyListeners();

    try {
      await _frappeService.ensureLoggedIn();
      final docs = await _fetchSalesInvoicePage(limitStart: 0);
      if (version != _salesInvoiceQueryVersion) return;
      _salesInvoices = docs;
      _hasMoreSalesInvoices = docs.isNotEmpty;
      _salesInvoicesError = null;
    } catch (err) {
      if (version != _salesInvoiceQueryVersion) return;
      _salesInvoicesError = err.toString();
    } finally {
      if (version == _salesInvoiceQueryVersion) {
        _isSalesInvoicesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> fetchPurchaseReceiptsFromFrappe() async {
    final inFlight = _purchaseReceiptsFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchPurchaseReceiptsFromFrappe();
    _purchaseReceiptsFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_purchaseReceiptsFetchInFlight, request)) {
        _purchaseReceiptsFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchPurchaseReceiptsFromFrappe() async {
    _isPurchaseReceiptsLoading = true;
    _purchaseReceiptsError = null;
    _hasMorePurchaseReceipts = true;
    _isMorePurchaseReceiptsLoading = false;
    final version = ++_purchaseReceiptQueryVersion;
    notifyListeners();

    try {
      await _frappeService.ensureLoggedIn();
      final docs = await _fetchPurchaseReceiptPage(limitStart: 0);
      if (version != _purchaseReceiptQueryVersion) return;
      _purchaseReceipts = docs;
      _hasMorePurchaseReceipts = docs.isNotEmpty;
      _purchaseReceiptsError = null;
    } catch (err) {
      if (version != _purchaseReceiptQueryVersion) return;
      _purchaseReceiptsError = err.toString();
    } finally {
      if (version == _purchaseReceiptQueryVersion) {
        _isPurchaseReceiptsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> fetchPurchaseInvoicesFromFrappe() async {
    final inFlight = _purchaseInvoicesFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchPurchaseInvoicesFromFrappe();
    _purchaseInvoicesFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_purchaseInvoicesFetchInFlight, request)) {
        _purchaseInvoicesFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchPurchaseInvoicesFromFrappe() async {
    _isPurchaseInvoicesLoading = true;
    _purchaseInvoicesError = null;
    _hasMorePurchaseInvoices = true;
    _isMorePurchaseInvoicesLoading = false;
    final version = ++_purchaseInvoiceQueryVersion;
    notifyListeners();

    try {
      await _frappeService.ensureLoggedIn();
      final docs = await _fetchPurchaseInvoicePage(limitStart: 0);
      if (version != _purchaseInvoiceQueryVersion) return;
      _purchaseInvoices = docs;
      _hasMorePurchaseInvoices = docs.isNotEmpty;
      _purchaseInvoicesError = null;
    } catch (err) {
      if (version != _purchaseInvoiceQueryVersion) return;
      _purchaseInvoicesError = err.toString();
    } finally {
      if (version == _purchaseInvoiceQueryVersion) {
        _isPurchaseInvoicesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> fetchMaterialRequestsFromFrappe() async {
    final inFlight = _materialRequestsFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchMaterialRequestsFromFrappe();
    _materialRequestsFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_materialRequestsFetchInFlight, request)) {
        _materialRequestsFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchMaterialRequestsFromFrappe() async {
    _isMaterialRequestsLoading = true;
    _materialRequestsError = null;
    _hasMoreMaterialRequests = true;
    _isMoreMaterialRequestsLoading = false;
    final version = ++_materialRequestQueryVersion;
    notifyListeners();

    try {
      await _frappeService.ensureLoggedIn();
      final docs = await _fetchMaterialRequestPage(limitStart: 0);
      if (version != _materialRequestQueryVersion) return;
      _materialRequests = docs;
      _hasMoreMaterialRequests = docs.isNotEmpty;
      _materialRequestsError = null;
    } catch (err) {
      if (version != _materialRequestQueryVersion) return;
      _hasMoreMaterialRequests = false;
      _materialRequestsError = err.toString();
    } finally {
      if (version == _materialRequestQueryVersion) {
        _isMaterialRequestsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshDeliveryNotes() => fetchDeliveryNotesFromFrappe();
  Future<void> refreshSalesInvoices() => fetchSalesInvoicesFromFrappe();

  Future<void> setSalesOrderQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _salesOrderSearch;
    final nextStatus = status;
    if (_salesOrderSearch == nextSearch && _salesOrderStatus == nextStatus) {
      return;
    }
    _salesOrderSearch = nextSearch;
    _salesOrderStatus = nextStatus;
    _salesOrdersFetchInFlight = null;
    await fetchSalesOrdersFromFrappe();
  }

  Future<void> setDeliveryNoteQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _deliveryNoteSearch;
    final nextStatus = status;
    if (_deliveryNoteSearch == nextSearch &&
        _deliveryNoteStatus == nextStatus) {
      return;
    }
    _deliveryNoteSearch = nextSearch;
    _deliveryNoteStatus = nextStatus;
    _deliveryNotesFetchInFlight = null;
    await fetchDeliveryNotesFromFrappe();
  }

  Future<void> setSalesInvoiceQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _salesInvoiceSearch;
    final nextStatus = status;
    if (_salesInvoiceSearch == nextSearch &&
        _salesInvoiceStatus == nextStatus) {
      return;
    }
    _salesInvoiceSearch = nextSearch;
    _salesInvoiceStatus = nextStatus;
    _salesInvoicesFetchInFlight = null;
    await fetchSalesInvoicesFromFrappe();
  }

  Future<void> loadMoreDeliveryNotes() async {
    if (_isDeliveryNotesLoading ||
        _isMoreDeliveryNotesLoading ||
        !_hasMoreDeliveryNotes) {
      return;
    }
    _isMoreDeliveryNotesLoading = true;
    final version = _deliveryNoteQueryVersion;
    notifyListeners();
    try {
      final page = await _fetchDeliveryNotePage(
        limitStart: _deliveryNotes.length,
      );
      if (version != _deliveryNoteQueryVersion) return;
      final ids = _deliveryNotes.map((e) => e.id).toSet();
      _deliveryNotes = [..._deliveryNotes, ...page.where((e) => ids.add(e.id))];
      _hasMoreDeliveryNotes = page.isNotEmpty;
    } catch (err) {
      if (version != _deliveryNoteQueryVersion) return;
      _deliveryNotesError = err.toString();
    } finally {
      if (version == _deliveryNoteQueryVersion) {
        _isMoreDeliveryNotesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreSalesInvoices() async {
    if (_isSalesInvoicesLoading ||
        _isMoreSalesInvoicesLoading ||
        !_hasMoreSalesInvoices) {
      return;
    }
    _isMoreSalesInvoicesLoading = true;
    final version = _salesInvoiceQueryVersion;
    notifyListeners();
    try {
      final page = await _fetchSalesInvoicePage(
        limitStart: _salesInvoices.length,
      );
      if (version != _salesInvoiceQueryVersion) return;
      final ids = _salesInvoices.map((e) => e.id).toSet();
      _salesInvoices = [..._salesInvoices, ...page.where((e) => ids.add(e.id))];
      _hasMoreSalesInvoices = page.isNotEmpty;
    } catch (err) {
      if (version != _salesInvoiceQueryVersion) return;
      _salesInvoicesError = err.toString();
    } finally {
      if (version == _salesInvoiceQueryVersion) {
        _isMoreSalesInvoicesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshPurchaseReceipts() => fetchPurchaseReceiptsFromFrappe();
  Future<void> refreshPurchaseInvoices() => fetchPurchaseInvoicesFromFrappe();
  Future<void> refreshMaterialRequests() => fetchMaterialRequestsFromFrappe();

  Future<void> setPurchaseOrderQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _purchaseOrderSearch;
    final nextStatus = status;
    if (_purchaseOrderSearch == nextSearch &&
        _purchaseOrderStatus == nextStatus) {
      return;
    }
    _purchaseOrderSearch = nextSearch;
    _purchaseOrderStatus = nextStatus;
    _purchaseOrdersFetchInFlight = null;
    await fetchPurchaseOrdersFromFrappe();
  }

  Future<void> setPurchaseReceiptQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _purchaseReceiptSearch;
    final nextStatus = status;
    if (_purchaseReceiptSearch == nextSearch &&
        _purchaseReceiptStatus == nextStatus) {
      return;
    }
    _purchaseReceiptSearch = nextSearch;
    _purchaseReceiptStatus = nextStatus;
    _purchaseReceiptsFetchInFlight = null;
    await fetchPurchaseReceiptsFromFrappe();
  }

  Future<void> setPurchaseInvoiceQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _purchaseInvoiceSearch;
    final nextStatus = status;
    if (_purchaseInvoiceSearch == nextSearch &&
        _purchaseInvoiceStatus == nextStatus) {
      return;
    }
    _purchaseInvoiceSearch = nextSearch;
    _purchaseInvoiceStatus = nextStatus;
    _purchaseInvoicesFetchInFlight = null;
    await fetchPurchaseInvoicesFromFrappe();
  }

  Future<void> setMaterialRequestQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _materialRequestSearch;
    final nextStatus = status;
    if (_materialRequestSearch == nextSearch &&
        _materialRequestStatus == nextStatus) {
      return;
    }
    _materialRequestSearch = nextSearch;
    _materialRequestStatus = nextStatus;
    _materialRequestsFetchInFlight = null;
    await fetchMaterialRequestsFromFrappe();
  }

  Future<void> loadMorePurchaseReceipts() async {
    if (_isPurchaseReceiptsLoading ||
        _isMorePurchaseReceiptsLoading ||
        !_hasMorePurchaseReceipts) {
      return;
    }
    _isMorePurchaseReceiptsLoading = true;
    final version = _purchaseReceiptQueryVersion;
    notifyListeners();
    try {
      final page = await _fetchPurchaseReceiptPage(
        limitStart: _purchaseReceipts.length,
      );
      if (version != _purchaseReceiptQueryVersion) return;
      final ids = _purchaseReceipts.map((e) => e.id).toSet();
      _purchaseReceipts = [
        ..._purchaseReceipts,
        ...page.where((e) => ids.add(e.id)),
      ];
      _hasMorePurchaseReceipts = page.isNotEmpty;
    } catch (err) {
      if (version != _purchaseReceiptQueryVersion) return;
      _purchaseReceiptsError = err.toString();
    } finally {
      if (version == _purchaseReceiptQueryVersion) {
        _isMorePurchaseReceiptsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreMaterialRequests() async {
    if (_isMaterialRequestsLoading ||
        _isMoreMaterialRequestsLoading ||
        !_hasMoreMaterialRequests) {
      return;
    }
    _isMoreMaterialRequestsLoading = true;
    final version = _materialRequestQueryVersion;
    notifyListeners();
    try {
      final page = await _fetchMaterialRequestPage(
        limitStart: _materialRequests.length,
      );
      if (version != _materialRequestQueryVersion) return;
      final ids = _materialRequests.map((e) => e.id).toSet();
      _materialRequests = [
        ..._materialRequests,
        ...page.where((e) => ids.add(e.id)),
      ];
      _hasMoreMaterialRequests = page.isNotEmpty;
      _materialRequestsError = null;
    } catch (err) {
      if (version != _materialRequestQueryVersion) return;
      _hasMoreMaterialRequests = false;
      if (_materialRequests.isEmpty) {
        _materialRequestsError = err.toString();
      }
    } finally {
      if (version == _materialRequestQueryVersion) {
        _isMoreMaterialRequestsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMorePurchaseInvoices() async {
    if (_isPurchaseInvoicesLoading ||
        _isMorePurchaseInvoicesLoading ||
        !_hasMorePurchaseInvoices) {
      return;
    }
    _isMorePurchaseInvoicesLoading = true;
    final version = _purchaseInvoiceQueryVersion;
    notifyListeners();
    try {
      final page = await _fetchPurchaseInvoicePage(
        limitStart: _purchaseInvoices.length,
      );
      if (version != _purchaseInvoiceQueryVersion) return;
      final ids = _purchaseInvoices.map((e) => e.id).toSet();
      _purchaseInvoices = [
        ..._purchaseInvoices,
        ...page.where((e) => ids.add(e.id)),
      ];
      _hasMorePurchaseInvoices = page.isNotEmpty;
    } catch (err) {
      if (version != _purchaseInvoiceQueryVersion) return;
      _purchaseInvoicesError = err.toString();
    } finally {
      if (version == _purchaseInvoiceQueryVersion) {
        _isMorePurchaseInvoicesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> fetchStockEntriesFromFrappe() async {
    _isStockEntriesLoading = true;
    _stockEntriesError = null;
    notifyListeners();

    try {
      await _frappeService.ensureLoggedIn();
      final filters = _companyScopeFilters('');
      List<Map<String, dynamic>> data;
      try {
        data = await _fetchAllResourcePages(
          doctype: 'Stock Entry',
          fields: const [
            'name',
            'stock_entry_type',
            'status',
            'docstatus',
            'posting_date',
            'total_qty',
            'from_warehouse',
            'to_warehouse',
          ],
          orderBy: 'posting_date desc',
          filters: filters,
          maxRows: _defaultFetchRowLimit,
        );
      } catch (_) {
        data = await _fetchStockEntriesViaReportView(filters);
      }
      _stockEntries = data.map((e) => StockEntry.fromJson(e)).toList();
      _stockEntriesError = null;
    } catch (err) {
      _stockEntriesError = err.toString();
    } finally {
      _isStockEntriesLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshStockEntries() => fetchStockEntriesFromFrappe();

  Future<List<Map<String, dynamic>>> _fetchStockEntriesViaReportView(
    List<List<dynamic>> filters,
  ) {
    return walkFrappePages(
      pageSize: _frappePageSize,
      maxRows: _defaultFetchRowLimit,
      fetchPage: (start, limit) => _frappeService.fetchReportView(
        'Stock Entry',
        fields: const [
          'name',
          'stock_entry_type',
          'status',
          'docstatus',
          'posting_date',
        ],
        limit: limit,
        limitStart: start,
        orderBy: 'posting_date desc',
        filters: filters,
      ),
    );
  }

  Future<void> refreshStockReconciliations() async {
    final rows = await _fetchAllResourcePages(
      doctype: 'Stock Reconciliation',
      fields: const [
        'name',
        'company',
        'posting_date',
        'status',
        'docstatus',
        'difference_amount',
      ],
      orderBy: 'posting_date desc, name desc',
      maxRows: _defaultFetchRowLimit,
    );
    _stockReconciliations = rows
        .map(StockReconciliationSummary.fromJson)
        .toList();
    notifyListeners();
  }

  Future<void> fetchWarehousesFromFrappe({
    String? baseUrl,
    String? username,
    String? password,
  }) async {
    final canReuseInFlight =
        baseUrl == null && username == null && password == null;
    if (canReuseInFlight && _warehousesFetchInFlight != null) {
      return _warehousesFetchInFlight;
    }
    final request = _fetchWarehousesFromFrappe(
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
    if (canReuseInFlight) _warehousesFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_warehousesFetchInFlight, request)) {
        _warehousesFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchWarehousesFromFrappe({
    String? baseUrl,
    String? username,
    String? password,
  }) async {
    final version = ++_warehouseQueryVersion;
    _frappeService.baseUrl = _activeFrappeBaseUrl(baseUrl);

    try {
      if (username != null && password != null) {
        await _frappeService.login(username, password);
      } else {
        await _frappeService.ensureLoggedIn();
      }

      List<Map<String, dynamic>> data;
      try {
        data = await _fetchAllResourcePages(
          doctype: 'Warehouse',
          fields: const [
            'name',
            'warehouse_name',
            'company',
            'parent_warehouse',
            'is_group',
            'disabled',
          ],
          orderBy: 'name asc',
          filters: [
            ['is_group', '=', 0],
            ['disabled', '=', 0],
            ..._companyScopeFilters(''),
          ],
          maxRows: null,
        );
      } catch (_) {
        data = await _fetchAllResourcePages(
          doctype: 'Warehouse',
          fields: const [
            'name',
            'warehouse_name',
            'company',
            'parent_warehouse',
            'is_group',
            'disabled',
          ],
          orderBy: 'name asc',
          filters: _companyScopeFilters(''),
          maxRows: null,
        );
      }

      if (version != _warehouseQueryVersion || !_isAuthenticated) return;
      _warehouses = data
          .map((row) => WarehouseInfo.fromJson(row))
          .where((w) => w.name.isNotEmpty && !w.isGroup && w.isDisabled != true)
          .toList();
    } catch (_) {
      // Warehouse list is optional; stock can fall back to name filters.
    } finally {
      if (version == _warehouseQueryVersion) notifyListeners();
    }
  }

  List<MapEntry<String, String>> get stockCompanies {
    final labels = <String, String>{};
    for (final w in _warehouses) {
      if (w.company.isEmpty) continue;
      labels.putIfAbsent(w.company, () => w.company);
    }
    final allowed = _mobileBoot?.companies ?? const <String>[];
    final allowedSet = allowed
        .map((company) => company.trim())
        .where((company) => company.isNotEmpty)
        .toSet();
    final source = allowedSet.isEmpty
        ? labels
        : {
            for (final entry in labels.entries)
              if (allowedSet.contains(entry.key)) entry.key: entry.value,
            for (final company in allowedSet)
              if (!labels.containsKey(company)) company: company,
          };
    final entries = source.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return entries;
  }

  bool _warehouseBelongsToCompany(WarehouseInfo warehouse, String company) {
    return warehouse.company == company;
  }

  int _compareWarehouseNames(String a, String b) {
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  List<StockAreaOption> stockWarehousesForCompany(String company) {
    final seen = <String>{};
    final areas = <StockAreaOption>[];

    for (final w in _warehouses.where(
      (w) => _warehouseBelongsToCompany(w, company),
    )) {
      final areaId = w.name;
      if (areaId.isEmpty || seen.contains(areaId)) continue;
      seen.add(areaId);
      areas.add(
        StockAreaOption(
          areaId: areaId,
          title: w.name,
          subtitle: w.displayName == w.name ? '' : w.displayName,
          icon: Icons.inventory_2_outlined,
        ),
      );
    }

    areas.sort((a, b) => _compareWarehouseNames(a.title, b.title));
    return areas;
  }

  List<String> erpWarehouseNamesForCompany(String company) {
    if (_warehouses.isEmpty) return [];
    final names = _warehouses
        .where((w) => _warehouseBelongsToCompany(w, company))
        .map((w) => w.name)
        .toList();
    names.sort(_compareWarehouseNames);
    return names;
  }

  List<String> get currentInventoryScopeWarehouses =>
      _inventoryScopeWarehouseNames();

  Future<void> refreshInventoryForCurrentRoleScope() {
    return fetchInventoryFromFrappe(
      filters: _inventoryScopeFiltersForCurrentRole(),
    );
  }

  List<String> _inventoryScopeWarehouseNames() {
    final bootWarehouseNames = (_mobileBoot?.warehouses ?? const <String>[])
        .map((warehouse) => warehouse.trim())
        .where((warehouse) => warehouse.isNotEmpty)
        .toSet()
        .toList();
    if (bootWarehouseNames.isNotEmpty) {
      bootWarehouseNames.sort(_compareWarehouseNames);
      return bootWarehouseNames;
    }

    if (!_shouldScopeSalesData) {
      final names = _warehouses
          .where((w) => w.name.isNotEmpty)
          .map((w) => w.name)
          .toList();
      names.sort(_compareWarehouseNames);
      return names;
    }

    final employeeCompany =
        _currentEmployeeProfile['company']?.toString().trim() ?? '';
    final companyWarehouses = employeeCompany.isEmpty
        ? const <String>[]
        : erpWarehouseNamesForCompany(employeeCompany);
    final names = companyWarehouses.isNotEmpty
        ? companyWarehouses
        : _warehouses
              .where((w) => w.name.isNotEmpty)
              .map((w) => w.name)
              .toList();
    names.sort(_compareWarehouseNames);
    return names;
  }

  List<List<dynamic>>? _inventoryScopeFiltersForCurrentRole() {
    final bootFilters = _warehouseScopeFilters();
    if (bootFilters != null) return bootFilters;
    if (!_shouldScopeSalesData) return null;
    final warehouseNames = _inventoryScopeWarehouseNames();

    if (warehouseNames.isEmpty) return null;
    if (warehouseNames.length == 1) {
      return [
        ['warehouse', '=', warehouseNames.first],
      ];
    }
    return [
      ['warehouse', 'in', warehouseNames],
    ];
  }

  List<List<dynamic>>? _warehouseScopeFilters() {
    final warehouses = _mobileBoot?.warehouses ?? const <String>[];
    final names =
        warehouses
            .map((warehouse) => warehouse.trim())
            .where((warehouse) => warehouse.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (names.isEmpty) return null;
    if (names.length == 1) {
      return [
        ['warehouse', '=', names.first],
      ];
    }
    return [
      ['warehouse', 'in', names],
    ];
  }

  Future<void> fetchInventoryFromFrappe({
    String? baseUrl,
    String? username,
    String? password,
    List<List<dynamic>>? filters,
  }) async {
    final canReuseInFlight =
        baseUrl == null &&
        username == null &&
        password == null &&
        filters == null;
    if (canReuseInFlight && _inventoryFetchInFlight != null) {
      return _inventoryFetchInFlight;
    }
    final request = _fetchInventoryFromFrappe(
      baseUrl: baseUrl,
      username: username,
      password: password,
      filters: filters,
    );
    if (canReuseInFlight) _inventoryFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_inventoryFetchInFlight, request)) {
        _inventoryFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchInventoryFromFrappe({
    String? baseUrl,
    String? username,
    String? password,
    List<List<dynamic>>? filters,
  }) async {
    final version = ++_inventoryQueryVersion;
    if (_isSampleMode) {
      notifyListeners();
      return;
    }
    _frappeService.baseUrl = _activeFrappeBaseUrl(baseUrl);
    _isInventoryLoading = true;
    _inventoryError = null;
    notifyListeners();

    try {
      if (username != null && password != null) {
        await _frappeService.login(username, password);
      } else {
        await _frappeService.ensureLoggedIn();
      }

      if (_warehouses.isEmpty) {
        await fetchWarehousesFromFrappe(
          baseUrl: _activeFrappeBaseUrl(baseUrl),
          username: username,
          password: password,
        );
      }

      final maxRows = filters == null ? _defaultFetchRowLimit : null;
      List<Map<String, dynamic>> data;
      try {
        data = await _fetchAllResourcePages(
          doctype: 'Bin',
          fields: const [
            'item_code',
            'warehouse',
            'actual_qty',
            'reserved_qty',
            'projected_qty',
            'valuation_rate',
            'stock_value',
          ],
          filters: filters,
          maxRows: maxRows,
        );
      } catch (_) {
        data = await _fetchAllResourcePages(
          doctype: 'Bin',
          fields: const ['item_code', 'warehouse', 'actual_qty'],
          filters: filters,
          maxRows: maxRows,
        );
      }

      final List<InventoryItem> items = [];
      for (final rawItem in data) {
        final rawWarehouse =
            rawItem['warehouse']?.toString() ??
            rawItem['warehouse_id']?.toString() ??
            '';

        final inv = InventoryItem.fromJson(rawItem);
        if (rawWarehouse.isEmpty) continue;
        items.add(inv.copyWith(warehouseId: rawWarehouse));
      }

      final itemMeta = await _fetchItemMeta(
        items.map((i) => i.sku).where((s) => s.isNotEmpty).toSet(),
      );
      final itemBuyingRates = await _fetchItemBuyingRates(
        items.map((i) => i.sku).where((s) => s.isNotEmpty).toSet(),
      );

      if (version != _inventoryQueryVersion || !_isAuthenticated) return;
      _inventory = items.map((inv) {
        final meta = itemMeta[inv.sku];

        var updated = inv;
        if (meta != null && meta.name.isNotEmpty && meta.name != inv.sku) {
          updated = updated.copyWith(name: meta.name);
        }
        if (meta != null && meta.reorderLevel > 0) {
          updated = updated.copyWith(minStockThreshold: meta.reorderLevel);
        }
        if (meta != null && meta.itemGroup.trim().isNotEmpty) {
          updated = updated.copyWith(category: meta.itemGroup.trim());
        }
        if (meta != null && meta.valuationRate > 0) {
          updated = updated.copyWith(unitValue: meta.valuationRate);
        }
        if (updated.unitValue <= 0) {
          final buyingRate = itemBuyingRates[inv.sku] ?? 0;
          if (buyingRate > 0) {
            updated = updated.copyWith(unitValue: buyingRate);
          }
        }
        return updated.withRecalculatedStatus();
      }).toList();
      _inventoryError = null;
    } catch (err) {
      if (version != _inventoryQueryVersion) return;
      _inventoryError = err.toString();
    } finally {
      if (version == _inventoryQueryVersion) {
        _isInventoryLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> submitDocument(String doctype, String name) async {
    await _frappeService.submitDocument(doctype, name);
    await _refreshAfterDocChange(doctype);
  }

  Future<List<int>> downloadSalesOrderPdf(String name) {
    return _frappeService.downloadPrintPdf(doctype: 'Sales Order', name: name);
  }

  Future<List<String>> fetchNamingSeries(String doctype) {
    return _frappeService.fetchNamingSeries(doctype);
  }

  Future<void> cancelDocument(String doctype, String name) async {
    await _frappeService.cancelDocument(doctype, name);
    await _refreshAfterDocChange(doctype);
  }

  Future<void> _refreshAfterDocChange(String doctype) async {
    switch (doctype) {
      case 'Sales Order':
        await refreshSalesOrders();
      case 'Delivery Note':
        await refreshDeliveryNotes();
      case 'Sales Invoice':
        await refreshSalesInvoices();
      case 'Purchase Order':
        await refreshPurchaseOrders();
      case 'Purchase Receipt':
        await refreshPurchaseReceipts();
      case 'Purchase Invoice':
        await refreshPurchaseInvoices();
    }
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
    notifyListeners();
  }

  Future<DeliveryNote> createDeliveryNoteFromSalesOrder(
    String soId, {
    required String namingSeries,
  }) async {
    final so = await _frappeService.fetchDocument('Sales Order', soId);
    final items = buildDeliveryNoteItemsFromSalesOrder(so);
    if (items.isEmpty) {
      throw Exception('No pending items to deliver for this Sales Order.');
    }

    final payload = <String, dynamic>{
      'naming_series': namingSeries.trim(),
      'customer': so['customer'],
      'company': so['company'],
      'posting_date': DateTime.now().toIso8601String().split('T').first,
      'items': items,
    };

    final created = await _frappeService.createDocument(
      'Delivery Note',
      payload,
    );
    await refreshDeliveryNotes();
    await refreshSalesOrders();
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
    return DeliveryNote.fromJson(created);
  }

  Future<SalesInvoice> createSalesInvoiceFromSalesOrder(
    String soId, {
    required String namingSeries,
  }) async {
    final so = await _frappeService.fetchDocument('Sales Order', soId);
    final items = buildSalesInvoiceItemsFromSalesOrder(so);
    if (items.isEmpty) {
      throw Exception('No pending items to bill for this Sales Order.');
    }

    final payload = <String, dynamic>{
      'naming_series': namingSeries.trim(),
      'customer': so['customer'],
      'company': so['company'],
      'posting_date': DateTime.now().toIso8601String().split('T').first,
      'items': items,
    };

    final created = await _frappeService.createDocument(
      'Sales Invoice',
      payload,
    );
    await refreshSalesInvoices();
    await refreshSalesOrders();
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
    return SalesInvoice.fromJson(created);
  }

  Future<PurchaseReceipt> createPurchaseReceiptFromPurchaseOrder(
    String poId,
  ) async {
    final po = await _frappeService.fetchDocument('Purchase Order', poId);
    final items = buildPurchaseReceiptItemsFromPurchaseOrder(po);
    if (items.isEmpty) {
      throw Exception('No pending items to receive for this Purchase Order.');
    }

    final payload = <String, dynamic>{
      'supplier': po['supplier'],
      'company': po['company'],
      'posting_date': DateTime.now().toIso8601String().split('T').first,
      'items': items,
    };

    final created = await _frappeService.createDocument(
      'Purchase Receipt',
      payload,
    );
    await refreshPurchaseReceipts();
    await refreshPurchaseOrders();
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
    return PurchaseReceipt.fromJson(created);
  }

  Future<PurchaseInvoice> createPurchaseInvoiceFromPurchaseOrder(
    String poId,
  ) async {
    final po = await _frappeService.fetchDocument('Purchase Order', poId);
    final items = buildPurchaseInvoiceItemsFromPurchaseOrder(po);
    if (items.isEmpty) {
      throw Exception('No pending items to bill for this Purchase Order.');
    }

    final payload = <String, dynamic>{
      'supplier': po['supplier'],
      'company': po['company'],
      'posting_date': DateTime.now().toIso8601String().split('T').first,
      'items': items,
    };

    final created = await _frappeService.createDocument(
      'Purchase Invoice',
      payload,
    );
    await refreshPurchaseInvoices();
    await refreshPurchaseOrders();
    unawaited(refreshDashboardSummaryForCurrentAccess(silent: true));
    return PurchaseInvoice.fromJson(created);
  }

  Future<List<DeliveryNote>> fetchDeliveryNotesForSalesOrder(
    String soId,
  ) async {
    await _frappeService.ensureLoggedIn();
    final data = await _fetchAllResourcePages(
      doctype: 'Delivery Note',
      fields: const [
        'name',
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
      filters: [
        ['Delivery Note Item', 'against_sales_order', '=', soId],
      ],
      maxRows: null,
    );
    return data.map((e) => DeliveryNote.fromJson(e)).toList();
  }

  Future<List<SalesInvoice>> fetchSalesInvoicesForSalesOrder(
    String soId,
  ) async {
    await _frappeService.ensureLoggedIn();
    try {
      final data = await _fetchAllResourcePages(
        doctype: 'Sales Invoice',
        fields: const [
          'name',
          'customer',
          'customer_name',
          'status',
          'docstatus',
          'posting_date',
          'grand_total',
          'outstanding_amount',
          'due_date',
        ],
        filters: [
          ['Sales Invoice Item', 'sales_order', '=', soId],
        ],
        maxRows: null,
      );
      return data.map((e) => SalesInvoice.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  int get unpaidSalesInvoicesCount => _salesInvoices
      .where(
        (i) =>
            i.statusKey == InvoiceStatusKey.unpaid ||
            i.statusKey == InvoiceStatusKey.overdue ||
            i.statusKey == InvoiceStatusKey.partlyPaid,
      )
      .length;

  int get overduePurchaseInvoicesCount => _purchaseInvoices
      .where((i) => i.statusKey == InvoiceStatusKey.overdue)
      .length;

  Future<StockLedgerResult> fetchStockLedgerForItem({
    required String itemCode,
    required DateTime from,
    required DateTime to,
  }) async {
    await _frappeService.ensureLoggedIn();

    final fromDate = DateRangePresets.toFrappeDate(from);
    final toDate = DateRangePresets.toFrappeDate(to);

    final data = await _fetchAllResourcePages(
      doctype: 'Stock Ledger Entry',
      fields: const [
        'posting_date',
        'posting_time',
        'item_code',
        'warehouse',
        'actual_qty',
        'qty_after_transaction',
        'voucher_type',
        'voucher_no',
        'stock_value_difference',
      ],
      orderBy: 'posting_date desc, posting_time desc',
      filters: [
        ['item_code', '=', itemCode],
        ['posting_date', '>=', fromDate],
        ['posting_date', '<=', toDate],
        ...?_warehouseScopeFilters(),
      ],
      maxRows: null,
    );

    final movements = data.map((e) => StockLedgerMovement.fromJson(e)).toList();
    return StockLedgerResult.fromMovements(movements);
  }

  Future<List<StockAgingItem>> fetchStockAging({
    int lookbackDays = 365,
    bool forceRefresh = false,
  }) async {
    final key = _stockReportCacheKey('aging', '$lookbackDays');
    if (!forceRefresh) {
      final cachedRows = await _readDbRowList(key);
      if (cachedRows != null) {
        return cachedRows.map(_stockAgingFromCacheJson).toList();
      }
    }
    final inFlight = _stockAgingInFlight[key];
    if (inFlight != null) return inFlight;
    final request = _fetchStockAgingFromErp(lookbackDays: lookbackDays);
    _stockAgingInFlight[key] = request;
    try {
      final rows = await request;
      await _writeDbRowList(
        key,
        rows.map(_stockAgingToCacheJson).toList(),
        ttl: _stockReportCacheTtl,
      );
      return rows;
    } finally {
      if (identical(_stockAgingInFlight[key], request)) {
        _stockAgingInFlight.remove(key);
      }
    }
  }

  Future<List<StockAgingItem>> _fetchStockAgingFromErp({
    required int lookbackDays,
  }) async {
    await _frappeService.ensureLoggedIn();
    if (_inventory.isEmpty) await refreshInventory();
    final today = DateTime.now();
    final from = today.subtract(Duration(days: lookbackDays));
    final rows = await _fetchAllResourcePages(
      doctype: 'Stock Ledger Entry',
      fields: const [
        'name',
        'posting_date',
        'item_code',
        'warehouse',
        'actual_qty',
      ],
      filters: [
        ['posting_date', '>=', DateRangePresets.toFrappeDate(from)],
        ['actual_qty', '>', 0],
        ...?_warehouseScopeFilters(),
      ],
      orderBy: 'posting_date desc, posting_time desc',
      maxRows: 5000,
    );
    final latestIncoming = <String, DateTime>{};
    for (final row in rows) {
      final item = row['item_code']?.toString() ?? '';
      final warehouse = row['warehouse']?.toString() ?? '';
      final date = DateTime.tryParse(row['posting_date']?.toString() ?? '');
      if (item.isEmpty || warehouse.isEmpty || date == null) continue;
      latestIncoming.putIfAbsent('$item|$warehouse', () => date);
    }
    return [
      for (final item in _inventory)
        if (item.quantity > 0)
          StockAgingItem(
            itemCode: item.sku,
            itemName: item.name,
            warehouse: item.warehouseId,
            quantity: item.quantity,
            valuationRate: item.unitValue,
            lastIncomingDate: latestIncoming['${item.sku}|${item.warehouseId}'],
            ageDays: latestIncoming['${item.sku}|${item.warehouseId}'] == null
                ? lookbackDays + 1
                : today
                      .difference(
                        latestIncoming['${item.sku}|${item.warehouseId}']!,
                      )
                      .inDays,
          ),
    ];
  }

  Future<List<DeadStockItem>> fetchDeadStock({
    int lookbackDays = 365,
    bool forceRefresh = false,
  }) async {
    final key = _stockReportCacheKey('dead', '$lookbackDays');
    if (!forceRefresh) {
      final cachedRows = await _readDbRowList(key);
      if (cachedRows != null) {
        return cachedRows.map(_deadStockFromCacheJson).toList();
      }
    }
    final inFlight = _deadStockInFlight[key];
    if (inFlight != null) return inFlight;
    final request = _fetchDeadStockFromErp(lookbackDays: lookbackDays);
    _deadStockInFlight[key] = request;
    try {
      final rows = await request;
      await _writeDbRowList(
        key,
        rows.map(_deadStockToCacheJson).toList(),
        ttl: _stockReportCacheTtl,
      );
      return rows;
    } finally {
      if (identical(_deadStockInFlight[key], request)) {
        _deadStockInFlight.remove(key);
      }
    }
  }

  Future<List<DeadStockItem>> _fetchDeadStockFromErp({
    required int lookbackDays,
  }) async {
    await _frappeService.ensureLoggedIn();
    if (_inventory.isEmpty) await refreshInventory();
    final today = DateTime.now();
    final from = today.subtract(Duration(days: lookbackDays));
    final rows = await _fetchAllResourcePages(
      doctype: 'Stock Ledger Entry',
      fields: const [
        'name',
        'posting_date',
        'item_code',
        'warehouse',
        'actual_qty',
      ],
      filters: [
        ['posting_date', '>=', DateRangePresets.toFrappeDate(from)],
        ...?_warehouseScopeFilters(),
      ],
      orderBy: 'posting_date desc, posting_time desc',
      maxRows: 5000,
    );
    final latestMovement = <String, DateTime>{};
    for (final row in rows) {
      final item = row['item_code']?.toString() ?? '';
      final warehouse = row['warehouse']?.toString() ?? '';
      final date = DateTime.tryParse(row['posting_date']?.toString() ?? '');
      if (item.isEmpty || warehouse.isEmpty || date == null) continue;
      latestMovement.putIfAbsent('$item|$warehouse', () => date);
    }
    return [
      for (final item in _inventory)
        if (item.quantity > 0)
          DeadStockItem(
            itemCode: item.sku,
            itemName: item.name,
            warehouse: item.warehouseId,
            quantity: item.quantity,
            valuationRate: item.unitValue,
            lastMovementDate: latestMovement['${item.sku}|${item.warehouseId}'],
            inactiveDays:
                latestMovement['${item.sku}|${item.warehouseId}'] == null
                ? lookbackDays + 1
                : today
                      .difference(
                        latestMovement['${item.sku}|${item.warehouseId}']!,
                      )
                      .inDays,
          ),
    ];
  }

  Future<List<StockMovementVelocityItem>> fetchStockMovementVelocity({
    int periodDays = 30,
    bool forceRefresh = false,
  }) async {
    final key = _stockReportCacheKey('velocity', '$periodDays');
    if (!forceRefresh) {
      final cachedRows = await _readDbRowList(key);
      if (cachedRows != null) {
        return cachedRows.map(_stockVelocityFromCacheJson).toList();
      }
    }
    final inFlight = _stockVelocityInFlight[key];
    if (inFlight != null) return inFlight;
    final request = _fetchStockMovementVelocityFromErp(periodDays: periodDays);
    _stockVelocityInFlight[key] = request;
    try {
      final rows = await request;
      await _writeDbRowList(
        key,
        rows.map(_stockVelocityToCacheJson).toList(),
        ttl: _stockReportCacheTtl,
      );
      return rows;
    } finally {
      if (identical(_stockVelocityInFlight[key], request)) {
        _stockVelocityInFlight.remove(key);
      }
    }
  }

  Future<List<StockMovementVelocityItem>> _fetchStockMovementVelocityFromErp({
    required int periodDays,
  }) async {
    await _frappeService.ensureLoggedIn();
    if (_inventory.isEmpty) await refreshInventory();
    final from = DateTime.now().subtract(Duration(days: periodDays));
    final rows = await _fetchAllResourcePages(
      doctype: 'Stock Ledger Entry',
      fields: const ['name', 'item_code', 'warehouse', 'actual_qty'],
      filters: [
        ['posting_date', '>=', DateRangePresets.toFrappeDate(from)],
        ['actual_qty', '<', 0],
        ...?_warehouseScopeFilters(),
      ],
      orderBy: 'posting_date desc, posting_time desc',
      maxRows: 5000,
    );
    final outgoingQuantity = <String, double>{};
    final transactionCount = <String, int>{};
    for (final row in rows) {
      final item = row['item_code']?.toString() ?? '';
      final warehouse = row['warehouse']?.toString() ?? '';
      if (item.isEmpty || warehouse.isEmpty) continue;
      final key = '$item|$warehouse';
      outgoingQuantity[key] =
          (outgoingQuantity[key] ?? 0) +
          NumParse.asDouble(row['actual_qty']).abs();
      transactionCount[key] = (transactionCount[key] ?? 0) + 1;
    }
    return [
      for (final item in _inventory)
        if (item.quantity > 0)
          StockMovementVelocityItem(
            itemCode: item.sku,
            itemName: item.name,
            warehouse: item.warehouseId,
            currentQuantity: item.quantity,
            outgoingQuantity:
                outgoingQuantity['${item.sku}|${item.warehouseId}'] ?? 0,
            transactionCount:
                transactionCount['${item.sku}|${item.warehouseId}'] ?? 0,
          ),
    ];
  }

  String _stockReportCacheKey(String report, String parameter) {
    final warehouses =
        (_mobileBoot?.warehouses ?? const <String>[])
            .map((warehouse) => warehouse.trim())
            .where((warehouse) => warehouse.isNotEmpty)
            .toList()
          ..sort();
    return [
      _stockReportDbCachePrefix,
      selectedSiteBaseUrl.trim(),
      _currentUser?.trim() ?? '',
      report,
      parameter,
      warehouses.join(','),
      _inventory.length,
    ].join('|');
  }

  Map<String, dynamic> _stockAgingToCacheJson(StockAgingItem item) => {
    'item_code': item.itemCode,
    'item_name': item.itemName,
    'warehouse': item.warehouse,
    'quantity': item.quantity,
    'valuation_rate': item.valuationRate,
    'last_incoming_date': item.lastIncomingDate?.toIso8601String(),
    'age_days': item.ageDays,
  };

  StockAgingItem _stockAgingFromCacheJson(Map<String, dynamic> json) {
    return StockAgingItem(
      itemCode: json['item_code']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? '',
      warehouse: json['warehouse']?.toString() ?? '',
      quantity: NumParse.asInt(json['quantity']),
      valuationRate: NumParse.asDouble(json['valuation_rate']),
      lastIncomingDate: DateTime.tryParse(
        json['last_incoming_date']?.toString() ?? '',
      ),
      ageDays: NumParse.asInt(json['age_days']),
    );
  }

  Map<String, dynamic> _deadStockToCacheJson(DeadStockItem item) => {
    'item_code': item.itemCode,
    'item_name': item.itemName,
    'warehouse': item.warehouse,
    'quantity': item.quantity,
    'valuation_rate': item.valuationRate,
    'last_movement_date': item.lastMovementDate?.toIso8601String(),
    'inactive_days': item.inactiveDays,
  };

  DeadStockItem _deadStockFromCacheJson(Map<String, dynamic> json) {
    return DeadStockItem(
      itemCode: json['item_code']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? '',
      warehouse: json['warehouse']?.toString() ?? '',
      quantity: NumParse.asInt(json['quantity']),
      valuationRate: NumParse.asDouble(json['valuation_rate']),
      lastMovementDate: DateTime.tryParse(
        json['last_movement_date']?.toString() ?? '',
      ),
      inactiveDays: NumParse.asInt(json['inactive_days']),
    );
  }

  Map<String, dynamic> _stockVelocityToCacheJson(
    StockMovementVelocityItem item,
  ) => {
    'item_code': item.itemCode,
    'item_name': item.itemName,
    'warehouse': item.warehouse,
    'current_quantity': item.currentQuantity,
    'outgoing_quantity': item.outgoingQuantity,
    'transaction_count': item.transactionCount,
  };

  StockMovementVelocityItem _stockVelocityFromCacheJson(
    Map<String, dynamic> json,
  ) {
    return StockMovementVelocityItem(
      itemCode: json['item_code']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? '',
      warehouse: json['warehouse']?.toString() ?? '',
      currentQuantity: NumParse.asInt(json['current_quantity']),
      outgoingQuantity: NumParse.asDouble(json['outgoing_quantity']),
      transactionCount: NumParse.asInt(json['transaction_count']),
    );
  }

  Future<List<WarehouseBatchRecord>> fetchWarehouseBatches({
    bool forceRefresh = false,
  }) async {
    final key = _warehouseTrackingCacheKey('batch');
    if (!forceRefresh) {
      final cachedRows = await _readDbRowList(key);
      if (cachedRows != null) {
        return cachedRows.map(WarehouseBatchRecord.fromJson).toList();
      }
    }
    final inFlight = _warehouseBatchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchWarehouseBatchesFromErp();
    _warehouseBatchInFlight = request;
    return request
        .then((rows) async {
          await _writeDbRowList(
            key,
            rows.map(_warehouseBatchToCacheJson).toList(),
            ttl: _warehouseTrackingCacheTtl,
          );
          return rows;
        })
        .whenComplete(() {
          if (identical(_warehouseBatchInFlight, request)) {
            _warehouseBatchInFlight = null;
          }
        });
  }

  Future<List<WarehouseBatchRecord>> _fetchWarehouseBatchesFromErp() async {
    await _frappeService.ensureLoggedIn();
    final rows = await _fetchAllResourcePages(
      doctype: 'Batch',
      fields: const [
        'name',
        'item',
        'manufacturing_date',
        'expiry_date',
        'disabled',
      ],
      orderBy: 'expiry_date asc, name asc',
      maxRows: 1000,
    );
    return rows.map(WarehouseBatchRecord.fromJson).toList();
  }

  Future<List<WarehouseSerialRecord>> fetchWarehouseSerialNumbers({
    bool forceRefresh = false,
  }) async {
    final key = _warehouseTrackingCacheKey('serial');
    if (!forceRefresh) {
      final cachedRows = await _readDbRowList(key);
      if (cachedRows != null) {
        return cachedRows.map(WarehouseSerialRecord.fromJson).toList();
      }
    }
    final inFlight = _warehouseSerialInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchWarehouseSerialNumbersFromErp();
    _warehouseSerialInFlight = request;
    return request
        .then((rows) async {
          await _writeDbRowList(
            key,
            rows.map(_warehouseSerialToCacheJson).toList(),
            ttl: _warehouseTrackingCacheTtl,
          );
          return rows;
        })
        .whenComplete(() {
          if (identical(_warehouseSerialInFlight, request)) {
            _warehouseSerialInFlight = null;
          }
        });
  }

  Future<List<WarehouseSerialRecord>>
  _fetchWarehouseSerialNumbersFromErp() async {
    await _frappeService.ensureLoggedIn();
    final rows = await _fetchAllResourcePages(
      doctype: 'Serial No',
      fields: const ['name', 'item_code', 'warehouse', 'status', 'batch_no'],
      filters: _warehouseScopeFilters(),
      orderBy: 'modified desc',
      maxRows: 1000,
    );
    return rows.map(WarehouseSerialRecord.fromJson).toList();
  }

  String _warehouseTrackingCacheKey(String type) {
    return [
      _warehouseTrackingDbCachePrefix,
      selectedSiteBaseUrl.trim(),
      _currentUser?.trim() ?? '',
      type,
    ].join('|');
  }

  Map<String, dynamic> _warehouseBatchToCacheJson(WarehouseBatchRecord row) => {
    'name': row.name,
    'item': row.itemCode,
    'manufacturing_date': row.manufacturingDate?.toIso8601String(),
    'expiry_date': row.expiryDate?.toIso8601String(),
    'disabled': row.disabled,
  };

  Map<String, dynamic> _warehouseSerialToCacheJson(WarehouseSerialRecord row) =>
      {
        'name': row.name,
        'item_code': row.itemCode,
        'warehouse': row.warehouse,
        'status': row.status,
        'batch_no': row.batchNo,
      };

  Future<List<QualityInspectionRecord>> fetchRejectedQualityInspections({
    int periodDays = 30,
    bool forceRefresh = false,
  }) async {
    return _fetchCachedQualityInspections(
      key: 'rejected:$periodDays',
      periodDays: periodDays,
      forceRefresh: forceRefresh,
      filtersBuilder: (from) => [
        ['status', '=', 'Rejected'],
        ['report_date', '>=', DateRangePresets.toFrappeDate(from)],
      ],
    );
  }

  Future<List<QualityInspectionRecord>> fetchProductionQualityInspections({
    int periodDays = 30,
    bool forceRefresh = false,
  }) async {
    return _fetchCachedQualityInspections(
      key: 'production:$periodDays',
      periodDays: periodDays,
      forceRefresh: forceRefresh,
      filtersBuilder: (from) => [
        ['inspection_type', '=', 'In Process'],
        ['report_date', '>=', DateRangePresets.toFrappeDate(from)],
      ],
    );
  }

  Future<List<QualityInspectionRecord>> fetchIncomingQualityInspections({
    int periodDays = 30,
    bool forceRefresh = false,
  }) async {
    return _fetchCachedQualityInspections(
      key: 'incoming:$periodDays',
      periodDays: periodDays,
      forceRefresh: forceRefresh,
      filtersBuilder: (from) => [
        ['inspection_type', '=', 'Incoming'],
        ['report_date', '>=', DateRangePresets.toFrappeDate(from)],
      ],
    );
  }

  Future<List<QualityInspectionRecord>> _fetchCachedQualityInspections({
    required String key,
    required int periodDays,
    required bool forceRefresh,
    required List<List<dynamic>> Function(DateTime from) filtersBuilder,
  }) async {
    final cacheKey = [
      _qualityInspectionDbCachePrefix,
      selectedSiteBaseUrl.trim(),
      _currentUser?.trim() ?? '',
      key,
    ].join('|');
    if (!forceRefresh) {
      final cachedRows = await _readDbRowList(cacheKey);
      if (cachedRows != null) {
        return cachedRows.map(QualityInspectionRecord.fromJson).toList();
      }
    }
    final inFlight = _qualityInspectionInFlight[cacheKey];
    if (inFlight != null) return inFlight;
    final request = _fetchQualityInspectionsFromErp(
      periodDays: periodDays,
      filtersBuilder: filtersBuilder,
    );
    _qualityInspectionInFlight[cacheKey] = request;
    try {
      final rows = await request;
      await _writeDbRowList(
        cacheKey,
        rows.map(_qualityInspectionToCacheJson).toList(),
        ttl: _qualityInspectionCacheTtl,
      );
      return rows;
    } finally {
      if (identical(_qualityInspectionInFlight[cacheKey], request)) {
        _qualityInspectionInFlight.remove(cacheKey);
      }
    }
  }

  Future<List<QualityInspectionRecord>> _fetchQualityInspectionsFromErp({
    required int periodDays,
    required List<List<dynamic>> Function(DateTime from) filtersBuilder,
  }) async {
    await _frappeService.ensureLoggedIn();
    final from = DateTime.now().subtract(Duration(days: periodDays));
    final rows = await _fetchAllResourcePages(
      doctype: 'Quality Inspection',
      fields: const [
        'name',
        'item_code',
        'item_name',
        'inspection_type',
        'reference_type',
        'reference_name',
        'inspected_by',
        'status',
        'remarks',
        'report_date',
        'docstatus',
      ],
      filters: filtersBuilder(from),
      orderBy: 'report_date desc, modified desc',
      maxRows: 1000,
    );
    return rows.map(QualityInspectionRecord.fromJson).toList();
  }

  Map<String, dynamic> _qualityInspectionToCacheJson(
    QualityInspectionRecord row,
  ) => {
    'name': row.name,
    'item_code': row.itemCode,
    'item_name': row.itemName,
    'inspection_type': row.inspectionType,
    'reference_type': row.referenceType,
    'reference_name': row.referenceName,
    'inspected_by': row.inspectedBy,
    'status': row.status,
    'remarks': row.remarks,
    'report_date': row.reportDate?.toIso8601String(),
    'docstatus': row.docstatus,
  };

  Future<List<QualityInspectionRecord>> fetchQualityInspectionsForReceipt(
    String purchaseReceiptId,
  ) async {
    await _frappeService.ensureLoggedIn();
    final rows = await _fetchAllResourcePages(
      doctype: 'Quality Inspection',
      fields: const [
        'name',
        'item_code',
        'item_name',
        'inspection_type',
        'reference_type',
        'reference_name',
        'inspected_by',
        'status',
        'remarks',
        'report_date',
        'docstatus',
      ],
      filters: [
        ['inspection_type', '=', 'Incoming'],
        ['reference_type', '=', 'Purchase Receipt'],
        ['reference_name', '=', purchaseReceiptId],
      ],
      orderBy: 'report_date desc, modified desc',
      maxRows: 200,
    );
    return rows.map(QualityInspectionRecord.fromJson).toList();
  }

  Future<QualityInspectionRecord> createIncomingQualityInspection({
    required String purchaseReceiptId,
    required String itemCode,
    required String status,
    String remarks = '',
    String? inspectedBy,
    DateTime? reportDate,
  }) async {
    await _frappeService.ensureLoggedIn();
    final payload = <String, dynamic>{
      'inspection_type': 'Incoming',
      'reference_type': 'Purchase Receipt',
      'reference_name': purchaseReceiptId,
      'item_code': itemCode,
      'status': status,
      'report_date': DateRangePresets.toFrappeDate(
        reportDate ?? DateTime.now(),
      ),
      if (inspectedBy?.trim().isNotEmpty == true)
        'inspected_by': inspectedBy!.trim(),
      if (remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
    };

    final created = await _frappeService.createDocument(
      'Quality Inspection',
      payload,
    );
    return QualityInspectionRecord.fromJson(created);
  }

  Future<List<QualityInspectionRecord>> fetchQualityInspections({
    int periodDays = 30,
  }) async {
    await _frappeService.ensureLoggedIn();
    final from = DateTime.now().subtract(Duration(days: periodDays));
    final rows = await _fetchAllResourcePages(
      doctype: 'Quality Inspection',
      fields: const [
        'name',
        'item_code',
        'item_name',
        'inspection_type',
        'reference_type',
        'reference_name',
        'inspected_by',
        'status',
        'remarks',
        'report_date',
        'docstatus',
      ],
      filters: [
        ['report_date', '>=', DateRangePresets.toFrappeDate(from)],
      ],
      orderBy: 'report_date desc, modified desc',
      maxRows: 1000,
    );
    return rows.map(QualityInspectionRecord.fromJson).toList();
  }

  Future<List<QualityInspectionRecord>> fetchQualityInspectionsForApproval({
    int periodDays = 30,
  }) async {
    await _frappeService.ensureLoggedIn();
    final from = DateTime.now().subtract(Duration(days: periodDays));
    final rows = await _fetchAllResourcePages(
      doctype: 'Quality Inspection',
      fields: const [
        'name',
        'item_code',
        'item_name',
        'inspection_type',
        'reference_type',
        'reference_name',
        'inspected_by',
        'status',
        'remarks',
        'report_date',
        'docstatus',
      ],
      filters: [
        ['docstatus', '=', 0],
        ['report_date', '>=', DateRangePresets.toFrappeDate(from)],
      ],
      orderBy: 'report_date desc, modified desc',
      maxRows: 1000,
    );
    return rows.map(QualityInspectionRecord.fromJson).toList();
  }

  bool _isApprovalCandidateRow(Map<String, dynamic> row) {
    final docstatus = int.tryParse(row['docstatus']?.toString() ?? '') ?? 0;
    if (docstatus >= 2) return false;
    final state = [
      row['workflow_state'],
      row['status'],
    ].map((value) => value?.toString().trim().toLowerCase() ?? '').join(' ');
    if (state.isEmpty) return true;
    const terminalWords = [
      'approved',
      'completed',
      'cancelled',
      'canceled',
      'closed',
      'rejected',
      'stopped',
    ];
    return !terminalWords.any(state.contains);
  }

  Future<List<SalesOrderApproval>> fetchSalesOrderApprovals() async {
    await _frappeService.ensureLoggedIn();
    final rows = await _fetchAllResourcePages(
      doctype: 'Sales Order',
      fields: const [
        'name',
        'customer',
        'customer_name',
        'workflow_state',
        'status',
        'owner',
        'transaction_date',
        'grand_total',
        'docstatus',
      ],
      filters: [
        ['docstatus', '<', 2],
      ],
      orderBy: 'modified desc',
      maxRows: 200,
    );
    final approvals = <SalesOrderApproval>[];
    final candidateRows = rows.where(_isApprovalCandidateRow).toList();
    final actionsByName = await _fetchWorkflowActionsForRows(
      doctype: 'Sales Order',
      rows: candidateRows,
    );
    for (final row in candidateRows) {
      final name = row['name']?.toString() ?? '';
      final actions = actionsByName[name] ?? const <String>[];
      if (actions.isNotEmpty) {
        approvals.add(SalesOrderApproval.fromJson(row, actions: actions));
      }
    }
    if (_salesOrderApprovalTodoCount != approvals.length) {
      _salesOrderApprovalTodoCount = approvals.length;
      notifyListeners();
    }
    return approvals;
  }

  String _approvalTodoCacheKey() {
    final site = _frappeService.baseUrl.trim();
    final user = _currentUser?.trim() ?? _frappeService.username?.trim() ?? '';
    return [_approvalTodoDbCachePrefix, site, user].join('|');
  }

  void _setApprovalTodoSnapshot(List<ErpApprovalTodo> todos) {
    final snapshot = List<ErpApprovalTodo>.unmodifiable(todos);
    final purchaseCount = snapshot
        .where((todo) => purchaseApprovalDoctypes.contains(todo.doctype))
        .length;
    final changed =
        !_isSameApprovalTodoSnapshot(_approvalTodoSnapshot, snapshot) ||
        _salesOrderApprovalTodoCount != snapshot.length ||
        _purchaseApprovalTodoCount != purchaseCount;
    _approvalTodoSnapshot = snapshot;
    _salesOrderApprovalTodoCount = snapshot.length;
    _purchaseApprovalTodoCount = purchaseCount;
    if (changed) notifyListeners();
  }

  bool _isSameApprovalTodoSnapshot(
    List<ErpApprovalTodo> current,
    List<ErpApprovalTodo> next,
  ) {
    if (current.length != next.length) return false;
    for (var i = 0; i < current.length; i++) {
      final a = current[i];
      final b = next[i];
      if (a.doctype != b.doctype ||
          a.name != b.name ||
          a.workflowState != b.workflowState ||
          a.status != b.status ||
          a.docStatus != b.docStatus ||
          a.actions.join('|') != b.actions.join('|')) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> _approvalTodoToCacheJson(ErpApprovalTodo todo) {
    return {
      'doctype': todo.doctype,
      'name': todo.name,
      'party': todo.party,
      'party_name': todo.partyName,
      'workflow_state': todo.workflowState,
      'status': todo.status,
      'owner': todo.owner,
      'date': todo.date,
      'amount': todo.amount,
      'secondary_amount': todo.secondaryAmount,
      'docstatus': todo.docStatus,
      'actions': todo.actions,
    };
  }

  ErpApprovalTodo _approvalTodoFromCacheJson(Map<String, dynamic> json) {
    final actionsSource = json['actions'];
    final actions = actionsSource is List
        ? actionsSource
              .map((action) => action.toString().trim())
              .where((action) => action.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return ErpApprovalTodo(
      doctype: json['doctype']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      party: json['party']?.toString() ?? '',
      partyName: json['party_name']?.toString() ?? '',
      workflowState: json['workflow_state']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      owner: json['owner']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      amount: NumParse.asDouble(json['amount']),
      secondaryAmount: NumParse.asDouble(json['secondary_amount']),
      docStatus: NumParse.asInt(json['docstatus']),
      actions: actions,
    );
  }

  Future<List<ErpApprovalTodo>> fetchApprovalTodos({
    bool forceRefresh = false,
  }) async {
    if (_isSampleMode) {
      return _sampleApprovalTodos;
    }
    final key = _approvalTodoCacheKey();
    if (!forceRefresh) {
      final cachedRows = await _readDbRowList(key);
      if (cachedRows != null) {
        final todos = cachedRows
            .map(_approvalTodoFromCacheJson)
            .where((todo) => todo.doctype.isNotEmpty && todo.name.isNotEmpty)
            .toList(growable: false);
        _setApprovalTodoSnapshot(todos);
        return cachedApprovalTodos;
      }
    }
    final inFlight = _approvalTodoFetchInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final request = _fetchApprovalTodosFromErp();
    _approvalTodoFetchInFlight = request;
    try {
      final todos = await request;
      _setApprovalTodoSnapshot(todos);
      await _writeDbRowList(
        key,
        todos.map(_approvalTodoToCacheJson).toList(growable: false),
        ttl: _approvalTodoCacheTtl,
      );
      return cachedApprovalTodos;
    } finally {
      if (identical(_approvalTodoFetchInFlight, request)) {
        _approvalTodoFetchInFlight = null;
      }
    }
  }

  Future<List<ErpApprovalTodo>> _fetchApprovalTodosFromErp() async {
    await _frappeService.ensureLoggedIn();
    const configs = [
      (
        doctype: 'Sales Order',
        fields: [
          'name',
          'customer',
          'customer_name',
          'workflow_state',
          'status',
          'owner',
          'transaction_date',
          'grand_total',
          'docstatus',
        ],
      ),
      (
        doctype: 'Purchase Order',
        fields: [
          'name',
          'supplier',
          'supplier_name',
          'workflow_state',
          'status',
          'owner',
          'transaction_date',
          'grand_total',
          'docstatus',
        ],
      ),
      (
        doctype: 'Purchase Invoice',
        fields: [
          'name',
          'supplier',
          'supplier_name',
          'workflow_state',
          'status',
          'owner',
          'posting_date',
          'due_date',
          'grand_total',
          'outstanding_amount',
          'docstatus',
        ],
      ),
      (
        doctype: 'Material Request',
        fields: [
          'name',
          'material_request_type',
          'workflow_state',
          'status',
          'owner',
          'company',
          'transaction_date',
          'schedule_date',
          'total_qty',
          'docstatus',
        ],
      ),
      (
        doctype: 'Journal Entry',
        fields: [
          'name',
          'title',
          'workflow_state',
          'owner',
          'company',
          'posting_date',
          'total_debit',
          'total_credit',
          'docstatus',
        ],
      ),
    ];

    final todos = <ErpApprovalTodo>[];
    for (final config in configs) {
      final List<Map<String, dynamic>> rows;
      try {
        rows = await _fetchAllResourcePages(
          doctype: config.doctype,
          fields: config.fields,
          filters: [
            ['docstatus', '<', 2],
          ],
          orderBy: 'modified desc',
          maxRows: 200,
        );
      } catch (_) {
        // Approval Todo is an aggregate screen. If the current role cannot read
        // one document type, keep showing approval items from the allowed types.
        continue;
      }
      final candidateRows = rows.where(_isApprovalCandidateRow).toList();
      if (candidateRows.isEmpty) continue;
      final actionsByName = await _fetchWorkflowActionsForRows(
        doctype: config.doctype,
        rows: candidateRows,
      );
      for (final row in candidateRows) {
        final name = row['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final actions = actionsByName[name] ?? const <String>[];
        if (actions.isEmpty) continue;
        todos.add(
          ErpApprovalTodo.fromJson(config.doctype, row, actions: actions),
        );
      }
    }

    todos.sort((a, b) => b.date.compareTo(a.date));
    return todos;
  }

  Future<List<ErpApprovalTodo>> fetchPurchaseApprovalTodos() async {
    final todos = await fetchApprovalTodos();
    return todos
        .where((todo) => purchaseApprovalDoctypes.contains(todo.doctype))
        .toList();
  }

  void _removeApprovalTodoCacheItem(String doctype, String name) {
    if (_approvalTodoSnapshot.isEmpty) return;
    final filtered = _approvalTodoSnapshot
        .where((todo) => todo.doctype != doctype || todo.name != name)
        .toList(growable: false);
    if (filtered.length == _approvalTodoSnapshot.length) return;
    _setApprovalTodoSnapshot(filtered);
    unawaited(
      _writeDbRowList(
        _approvalTodoCacheKey(),
        filtered.map(_approvalTodoToCacheJson).toList(growable: false),
        ttl: _approvalTodoCacheTtl,
      ).catchError((_) {}),
    );
  }

  Future<List<SalesOrderApprovalHistory>>
  fetchSalesOrderApprovalHistory() async {
    await _frappeService.ensureLoggedIn();
    final currentUser = (_currentUser ?? _frappeService.username ?? '')
        .trim()
        .toLowerCase();
    if (currentUser.isEmpty) return const [];
    const doctypes = [
      'Sales Order',
      'Purchase Order',
      'Purchase Invoice',
      'Material Request',
      'Journal Entry',
    ];
    final rows = await _fetchAllResourcePages(
      doctype: 'Comment',
      fields: const [
        'name',
        'reference_doctype',
        'reference_name',
        'content',
        'comment_type',
        'comment_by',
        'owner',
        'creation',
      ],
      filters: [
        ['reference_doctype', 'in', doctypes],
      ],
      orFilters: [
        ['owner', '=', currentUser],
        ['comment_by', '=', currentUser],
      ],
      orderBy: 'creation desc',
      maxRows: 5000,
    );
    final history = rows
        .where((row) {
          final owner = (row['owner'] ?? '').toString().trim().toLowerCase();
          final commentBy = (row['comment_by'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final actorMatches = owner == currentUser || commentBy == currentUser;
          if (!actorMatches) return false;
          return _isApprovalHistoryComment(row);
        })
        .map(SalesOrderApprovalHistory.fromJson)
        .toList();
    try {
      final versions = await _fetchAllResourcePages(
        doctype: 'Version',
        fields: const [
          'name',
          'ref_doctype',
          'docname',
          'data',
          'owner',
          'creation',
        ],
        filters: [
          ['ref_doctype', 'in', doctypes],
          ['owner', '=', currentUser],
        ],
        orderBy: 'creation desc',
        maxRows: 5000,
      );
      history.addAll(
        versions
            .map(
              (row) => _approvalVersionHistoryFromJson(
                row,
                fallbackDoctype: row['ref_doctype']?.toString() ?? '',
                fallbackName: row['docname']?.toString() ?? '',
              ),
            )
            .where((row) => _isApprovalHistoryContent(row.content)),
      );
    } catch (_) {
      // Version access is optional; comments remain usable for history.
    }
    final byId = <String, SalesOrderApprovalHistory>{};
    for (final row in history) {
      final key = row.id.trim().isEmpty
          ? '${row.doctype}|${row.salesOrder}|${row.content}|${row.createdAt}'
          : row.id;
      byId[key] = row;
    }
    final result = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<List<SalesOrderApprovalHistory>> fetchApprovalDocumentActivity({
    required String doctype,
    required String name,
  }) async {
    final normalizedDoctype = doctype.trim();
    final normalizedName = name.trim();
    if (normalizedDoctype.isEmpty || normalizedName.isEmpty) return const [];
    await _frappeService.ensureLoggedIn();
    final comments = await _fetchAllResourcePages(
      doctype: 'Comment',
      fields: const [
        'name',
        'reference_doctype',
        'reference_name',
        'content',
        'comment_type',
        'comment_by',
        'owner',
        'creation',
      ],
      filters: [
        ['reference_doctype', '=', normalizedDoctype],
        ['reference_name', '=', normalizedName],
      ],
      orderBy: 'creation desc',
      maxRows: 500,
    );
    final activity = comments.map(SalesOrderApprovalHistory.fromJson).toList();
    try {
      final versions = await _fetchAllResourcePages(
        doctype: 'Version',
        fields: const [
          'name',
          'ref_doctype',
          'docname',
          'data',
          'owner',
          'creation',
        ],
        filters: [
          ['ref_doctype', '=', normalizedDoctype],
          ['docname', '=', normalizedName],
        ],
        orderBy: 'creation desc',
        maxRows: 500,
      );
      activity.addAll(
        versions
            .map(
              (row) => _approvalVersionHistoryFromJson(
                row,
                fallbackDoctype: normalizedDoctype,
                fallbackName: normalizedName,
              ),
            )
            .where((row) => row.content.trim().isNotEmpty),
      );
    } catch (_) {
      // Some roles can read comments but not Version. Keep the visible workflow
      // activity instead of failing the whole detail page.
    }
    try {
      final document = await _fetchCachedDocument(
        normalizedDoctype,
        normalizedName,
      );
      activity.addAll(
        _approvalDocumentAuditHistory(
          document,
          doctype: normalizedDoctype,
          name: normalizedName,
          existing: activity,
        ),
      );
    } catch (_) {
      // Audit fields are useful but not critical for the approval detail page.
    }
    activity.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return activity;
  }

  List<SalesOrderApprovalHistory> _approvalDocumentAuditHistory(
    Map<String, dynamic> document, {
    required String doctype,
    required String name,
    required List<SalesOrderApprovalHistory> existing,
  }) {
    final rows = <SalesOrderApprovalHistory>[];
    final hasCreated = existing.any(
      (row) => row.content.toLowerCase().contains('created this'),
    );
    final owner = document['owner']?.toString().trim() ?? '';
    final creation = document['creation']?.toString().trim() ?? '';
    if (!hasCreated && (owner.isNotEmpty || creation.isNotEmpty)) {
      rows.add(
        SalesOrderApprovalHistory(
          id: '$doctype::$name::created',
          doctype: doctype,
          salesOrder: name,
          content: 'created this',
          actor: owner,
          createdAt: creation,
        ),
      );
    }

    final hasEdited = existing.any((row) {
      final content = row.content.toLowerCase();
      return content.contains('last edited this') ||
          content.contains('changed ');
    });
    final modifiedBy = (document['modified_by'] ?? document['owner'])
        .toString()
        .trim();
    final modified = document['modified']?.toString().trim() ?? '';
    final sameTimestamp = creation.isNotEmpty && creation == modified;
    if (!hasEdited &&
        !sameTimestamp &&
        (modifiedBy.isNotEmpty || modified.isNotEmpty)) {
      rows.add(
        SalesOrderApprovalHistory(
          id: '$doctype::$name::modified',
          doctype: doctype,
          salesOrder: name,
          content: 'last edited this',
          actor: modifiedBy,
          createdAt: modified,
        ),
      );
    }
    return rows;
  }

  SalesOrderApprovalHistory _approvalVersionHistoryFromJson(
    Map<String, dynamic> row, {
    required String fallbackDoctype,
    required String fallbackName,
  }) {
    final data = _versionDataMap(row['data']);
    return SalesOrderApprovalHistory(
      id: row['name']?.toString() ?? '',
      doctype: row['ref_doctype']?.toString() ?? fallbackDoctype,
      salesOrder: row['docname']?.toString() ?? fallbackName,
      content: _approvalVersionContent(data),
      actor: row['owner']?.toString() ?? '',
      createdAt: row['creation']?.toString() ?? '',
    );
  }

  Map<String, dynamic> _versionDataMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }

  String _approvalVersionContent(Map<String, dynamic> data) {
    final lines = <String>[];
    final changed = data['changed'];
    if (changed is List) {
      for (final raw in changed.take(8)) {
        if (raw is! List || raw.isEmpty) continue;
        final field = _activityFieldLabel(raw[0]);
        final oldValue = raw.length > 1 ? _activityValue(raw[1]) : '';
        final newValue = raw.length > 2 ? _activityValue(raw[2]) : '';
        if (oldValue.isEmpty && newValue.isEmpty) {
          lines.add('Changed $field');
        } else {
          lines.add('Changed $field from $oldValue to $newValue');
        }
      }
    }

    final rowChanged = data['row_changed'];
    if (rowChanged is List) {
      for (final raw in rowChanged.take(4)) {
        if (raw is! List || raw.isEmpty) continue;
        final table = _activityFieldLabel(raw[0]);
        final changes = raw.length > 2 && raw[2] is List ? raw[2] as List : [];
        final details = <String>[];
        for (final change in changes.take(4)) {
          if (change is! List || change.isEmpty) continue;
          final field = _activityFieldLabel(change[0]);
          final oldValue = change.length > 1 ? _activityValue(change[1]) : '';
          final newValue = change.length > 2 ? _activityValue(change[2]) : '';
          details.add('$field from $oldValue to $newValue');
        }
        lines.add(
          details.isEmpty
              ? 'Changed row in $table'
              : 'Changed row in $table: ${details.join(', ')}',
        );
      }
    }

    final added = data['added'];
    if (added is List && added.isNotEmpty) {
      lines.add('Added ${added.length} row${added.length == 1 ? '' : 's'}');
    }
    final removed = data['removed'];
    if (removed is List && removed.isNotEmpty) {
      lines.add(
        'Removed ${removed.length} row${removed.length == 1 ? '' : 's'}',
      );
    }

    if (lines.isEmpty) return 'last edited this';
    return lines.join('\n');
  }

  String _activityFieldLabel(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return 'Field';
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  String _activityValue(dynamic raw) {
    if (raw == null) return '-';
    final value = raw.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.isEmpty) return '-';
    return value.length > 90 ? '${value.substring(0, 87)}...' : value;
  }

  bool _isApprovalHistoryComment(Map<String, dynamic> row) {
    final commentType = row['comment_type']?.toString().trim().toLowerCase();
    if (commentType == 'workflow') return true;

    final content = row['content']?.toString() ?? '';
    return _isApprovalHistoryContent(content);
  }

  bool _isApprovalHistoryContent(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    const approvalKeywords = [
      'via tmsx',
      'approved',
      'approve',
      'rejected',
      'reject',
      'submitted',
      'submit',
      'pending approval',
      'to deliver and bill',
      'cancelled',
      'canceled',
      'cancel',
      'workflow',
      'status',
    ];
    return approvalKeywords.any(normalized.contains);
  }

  Future<Map<String, dynamic>> fetchSalesOrderApprovalDetail(String name) {
    return _fetchCachedDocument('Sales Order', name);
  }

  Future<Map<String, dynamic>> fetchApprovalDocument({
    required String doctype,
    required String name,
    bool forceRefresh = false,
  }) {
    if (forceRefresh) {
      return _frappeService.fetchDocument(doctype, name).then((document) async {
        await _storeCachedDocument(doctype, name, document);
        return document;
      });
    }
    return _fetchCachedDocument(doctype, name);
  }

  Future<List<Map<String, dynamic>>> fetchEnabledUsersForApproval() async {
    await _frappeService.ensureLoggedIn();
    final rows = await _frappeService.fetchResource(
      'User',
      fields: const ['name', 'full_name', 'user_image', 'enabled', 'user_type'],
      filters: const [
        ['enabled', '=', 1],
        ['user_type', '=', 'System User'],
      ],
      orderBy: 'full_name asc, name asc',
      limit: 500,
    );
    return rows
        .where((row) => (row['name']?.toString().trim() ?? '').isNotEmpty)
        .toList();
  }

  Future<void> addSalesOrderAdditionalApprover({
    required String salesOrder,
    required String approver,
    required String reason,
  }) async {
    await _frappeService.callMethod(
      'tmsx_mobile.api.approval.add_sales_order_approver',
      args: {
        'sales_order': salesOrder,
        'approver': approver,
        'approval_type': 'Additional',
        'reason': reason.trim(),
        'note': reason.trim(),
      },
    );
    await _deleteCachedDocument('Sales Order', salesOrder);
    _removeApprovalTodoCacheItem('Sales Order', salesOrder);
    unawaited(
      fetchApprovalTodos(
        forceRefresh: true,
      ).catchError((_) => const <ErpApprovalTodo>[]),
    );
    unawaited(refreshNotifications(silent: true).catchError((_) {}));
  }

  Future<void> decideSalesOrderAdditionalApproval({
    required String salesOrder,
    Map<String, dynamic>? approverRow,
    required bool approved,
    String reason = '',
  }) async {
    final rowName = approverRow?['name']?.toString().trim() ?? '';
    try {
      await _callSalesOrderApproverServerScript(
        salesOrder: salesOrder,
        rowName: rowName,
        approved: approved,
        note: reason,
      );
    } catch (error) {
      if (!_shouldFallbackAdditionalApproval(error)) {
        rethrow;
      }
      try {
        await _frappeService.callMethod(
          'tmsx_mobile.api.approval.decide_sales_order_additional_approval',
          args: {
            'sales_order': salesOrder,
            'decision': approved ? 'approve' : 'reject',
            'reason': reason.trim(),
          },
        );
      } catch (fallbackError) {
        if (!_shouldFallbackAdditionalApproval(fallbackError)) rethrow;
        await _directUpdateSalesOrderAdditionalApproval(
          salesOrder: salesOrder,
          approverRow: approverRow,
          approved: approved,
          reason: reason,
        );
      }
    }
    await _deleteCachedDocument('Sales Order', salesOrder);
    _removeApprovalTodoCacheItem('Sales Order', salesOrder);
    unawaited(
      fetchApprovalTodos(
        forceRefresh: true,
      ).catchError((_) => const <ErpApprovalTodo>[]),
    );
    unawaited(refreshNotifications(silent: true).catchError((_) {}));
  }

  Future<void> _callSalesOrderApproverServerScript({
    required String salesOrder,
    required String rowName,
    required bool approved,
    required String note,
  }) async {
    if (rowName.isEmpty) {
      throw Exception(
        'Approval Row kosong. Refresh detail approval lalu coba lagi.',
      );
    }
    await _frappeService.callMethod(
      approved ? 'approve_sales_order_approver' : 'reject_sales_order_approver',
      args: {
        'sales_order': salesOrder,
        'row_name': rowName,
        'note': note.trim(),
      },
    );
  }

  bool _shouldFallbackAdditionalApproval(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('failed to get method') ||
        message.contains('not installed') ||
        message.contains('additional approval pending');
  }

  Future<void> _directUpdateSalesOrderAdditionalApproval({
    required String salesOrder,
    required Map<String, dynamic>? approverRow,
    required bool approved,
    required String reason,
  }) async {
    final row = approverRow ?? const <String, dynamic>{};
    final childDoctype = row['doctype']?.toString().trim() ?? '';
    final childName = row['name']?.toString().trim() ?? '';
    if (childDoctype.isEmpty || childName.isEmpty) {
      throw Exception(
        'Row Additional Approval tidak lengkap. Refresh detail lalu coba lagi.',
      );
    }

    final status = approved ? 'Approved' : 'Rejected';
    await _frappeService.updateDocument(childDoctype, childName, {
      'status': status,
    });

    final decision = approved ? 'APPROVE ADDITIONAL' : 'REJECT ADDITIONAL';
    final content = [
      '$decision via $appDisplayName',
      'Sales Order: $salesOrder',
      if (reason.trim().isNotEmpty) 'Alasan: ${reason.trim()}',
    ].join('\n');
    unawaited(
      _frappeService
          .callMethod(
            'frappe.desk.form.utils.add_comment',
            args: {
              'reference_doctype': 'Sales Order',
              'reference_name': salesOrder,
              'content': content,
              'comment_email': _currentUser ?? '',
              'comment_by': _currentUser ?? '',
            },
          )
          .then<void>((_) {})
          .catchError((_) {}),
    );
  }

  Future<void> applySalesOrderWorkflow({
    required SalesOrderApproval approval,
    required String action,
    String reason = '',
    bool refreshAfterApply = true,
    bool waitForComment = true,
    Map<String, dynamic>? currentDocument,
  }) async {
    await _frappeService.ensureLoggedIn();
    final normalizedAction = action.trim();
    final actionLower = normalizedAction.toLowerCase();
    final isReject =
        actionLower.contains('reject') ||
        actionLower.contains('tolak') ||
        actionLower.contains('decline');
    if (isReject && reason.trim().isEmpty) {
      throw Exception('Alasan reject wajib diisi.');
    }
    final doc =
        currentDocument ??
        await _frappeService.fetchDocument('Sales Order', approval.name);
    await _frappeService.callMethod(
      'frappe.model.workflow.apply_workflow',
      args: {'doc': doc, 'action': normalizedAction},
    );
    final decision = isReject ? 'REJECT' : 'APPROVE';
    final content = [
      '$decision via $appDisplayName',
      'Action: $normalizedAction',
      if (reason.trim().isNotEmpty) 'Alasan: ${reason.trim()}',
    ].join('\n');
    final commentRequest = _frappeService.callMethod(
      'frappe.desk.form.utils.add_comment',
      args: {
        'reference_doctype': 'Sales Order',
        'reference_name': approval.name,
        'content': content,
        'comment_email': _currentUser ?? '',
        'comment_by': _currentUser ?? '',
      },
    );
    if (waitForComment) {
      await commentRequest;
    } else {
      unawaited(commentRequest.then<void>((_) {}).catchError((_) {}));
    }
    await _deleteCachedDocument('Sales Order', approval.name);
    _removeApprovalTodoCacheItem('Sales Order', approval.name);
    final refresh = Future.wait([
      refreshSalesOrders(),
      refreshNotifications(silent: true),
    ]);
    if (refreshAfterApply) {
      await refresh;
    } else {
      unawaited(refresh.then<void>((_) {}).catchError((_) {}));
    }
  }

  Future<List<String>> fetchDocumentWorkflowActions({
    required String doctype,
    required String name,
  }) async {
    await _frappeService.ensureLoggedIn();
    final doc = await _fetchCachedDocument(doctype, name);
    return _fetchWorkflowActionsForDocument(doc);
  }

  Future<Map<String, List<String>>> _fetchWorkflowActionsForRows({
    required String doctype,
    required List<Map<String, dynamic>> rows,
    int batchSize = 8,
  }) async {
    final names = rows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
    final documents = await _fetchDocumentsInBatches(
      doctype,
      names,
      batchSize: batchSize,
    );
    final entries = documents.entries.toList();
    final actionsByName = <String, List<String>>{};
    for (var start = 0; start < entries.length; start += batchSize) {
      final end = start + batchSize > entries.length
          ? entries.length
          : start + batchSize;
      final batch = entries.sublist(start, end);
      final results = await Future.wait(
        batch.map((entry) async {
          try {
            return (
              name: entry.key,
              actions: await _fetchWorkflowActionsForDocument(entry.value),
            );
          } catch (_) {
            return (name: entry.key, actions: const <String>[]);
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

  Future<List<String>> _fetchWorkflowActionsForDocument(
    Map<String, dynamic> doc,
  ) async {
    final rawTransitions = await _frappeService.callMethod(
      'frappe.model.workflow.get_transitions',
      args: {'doc': doc},
    );
    return _parseWorkflowActions(rawTransitions);
  }

  static List<String> _parseWorkflowActions(dynamic rawTransitions) {
    return rawTransitions is List
        ? rawTransitions
              .whereType<Map>()
              .map((transition) => transition['action']?.toString() ?? '')
              .where((action) => action.trim().isNotEmpty)
              .toSet()
              .toList()
        : <String>[];
  }

  Future<void> applyDocumentWorkflow({
    required String doctype,
    required String name,
    required String action,
    String reason = '',
    bool refreshAfterApply = true,
    bool waitForComment = true,
    Map<String, dynamic>? currentDocument,
  }) async {
    await _frappeService.ensureLoggedIn();
    final normalizedAction = action.trim();
    final actionLower = normalizedAction.toLowerCase();
    final isReject =
        actionLower.contains('reject') ||
        actionLower.contains('tolak') ||
        actionLower.contains('decline') ||
        actionLower.contains('return');
    if (isReject && reason.trim().isEmpty) {
      throw Exception('Alasan reject/return wajib diisi.');
    }
    final doc =
        currentDocument ?? await _frappeService.fetchDocument(doctype, name);
    await _frappeService.callMethod(
      'frappe.model.workflow.apply_workflow',
      args: {'doc': doc, 'action': normalizedAction},
    );
    final decision = isReject ? 'REJECT' : 'APPROVE';
    final content = [
      '$decision via $appDisplayName',
      'Action: $normalizedAction',
      if (reason.trim().isNotEmpty) 'Alasan: ${reason.trim()}',
    ].join('\n');
    final commentRequest = _frappeService.callMethod(
      'frappe.desk.form.utils.add_comment',
      args: {
        'reference_doctype': doctype,
        'reference_name': name,
        'content': content,
        'comment_email': _currentUser ?? '',
        'comment_by': _currentUser ?? '',
      },
    );
    if (waitForComment) {
      await commentRequest;
    } else {
      unawaited(commentRequest.then<void>((_) {}).catchError((_) {}));
    }
    await _deleteCachedDocument(doctype, name);
    _removeApprovalTodoCacheItem(doctype, name);
    final refresh = Future.wait([
      switch (doctype) {
        'Purchase Order' => refreshPurchaseOrders(),
        'Purchase Receipt' => refreshPurchaseReceipts(),
        'Purchase Invoice' => refreshPurchaseInvoices(),
        'Material Request' => refreshMaterialRequests(),
        'Sales Order' => refreshSalesOrders(),
        _ => Future<void>.value(),
      },
      refreshNotifications(silent: true),
    ]);
    if (refreshAfterApply) {
      await refresh;
    } else {
      unawaited(refresh.then<void>((_) {}).catchError((_) {}));
    }
  }

  Future<void> refreshSalesOrders() => fetchSalesOrdersFromFrappe();
  Future<void> refreshPurchaseOrders() => fetchPurchaseOrdersFromFrappe();
  Future<void> refreshInventory() =>
      fetchInventoryFromFrappe(filters: _inventoryScopeFiltersForCurrentRole());

  Future<void> refreshWarehouses() => fetchWarehousesFromFrappe();

  Future<void> refreshItemGroups() async {
    if (_isSampleMode) {
      _itemGroups =
          _inventory
              .map((item) => item.category?.trim() ?? '')
              .where((group) => group.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      notifyListeners();
      return;
    }

    try {
      await _frappeService.ensureLoggedIn();
      final rows = await _fetchAllResourcePages(
        doctype: 'Item Group',
        fields: const ['name'],
        orderBy: 'name asc',
        maxRows: _defaultFetchRowLimit,
      );
      _itemGroups =
          rows
              .map((row) => row['name']?.toString().trim() ?? '')
              .where((group) => group.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      notifyListeners();
    } catch (_) {
      final fallback =
          _inventory
              .map((item) => item.category?.trim() ?? '')
              .where((group) => group.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (fallback.isNotEmpty) {
        _itemGroups = fallback;
        notifyListeners();
      }
    }
  }

  Future<List<Map<String, dynamic>>> fetchSellableItems({
    String query = '',
    int limit = FrappeService.maxPageLength,
  }) async {
    return _fetchItemOptionsByFlag(
      flagField: 'is_sales_item',
      query: query,
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> fetchPurchasableItems({
    String query = '',
    int limit = FrappeService.maxPageLength,
  }) async {
    return _fetchItemOptionsByFlag(
      flagField: 'is_purchase_item',
      query: query,
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchItemOptionsByFlag({
    required String flagField,
    String query = '',
    int limit = FrappeService.maxPageLength,
  }) async {
    final normalized = query.trim();
    if (_isSampleMode) {
      final needle = normalized.toLowerCase();
      return _inventory
          .where((item) {
            if (needle.isEmpty) return true;
            return item.sku.toLowerCase().contains(needle) ||
                item.name.toLowerCase().contains(needle) ||
                (item.category ?? '').toLowerCase().contains(needle);
          })
          .take(limit)
          .map(
            (item) => {
              'name': item.sku,
              'item_code': item.sku,
              'item_name': item.name,
              'item_group': item.category,
            },
          )
          .toList();
    }

    final fetchLimit = normalized.isEmpty
        ? limit
        : (limit < FrappeService.maxPageLength
              ? FrappeService.maxPageLength
              : limit);
    final rows = await _fetchResourceWithFieldFallback(
      doctype: 'Item',
      fields: const [
        'name',
        'item_code',
        'item_name',
        'item_group',
        'purchase_uom',
        'stock_uom',
      ],
      filters: [
        ['disabled', '=', 0],
        [flagField, '=', 1],
      ],
      orFilters: normalized.isEmpty
          ? null
          : [
              ['name', 'like', '%$normalized%'],
              ['item_code', 'like', '%$normalized%'],
              ['item_name', 'like', '%$normalized%'],
            ],
      orderBy: 'item_name asc, name asc',
      limit: fetchLimit,
    );
    if (normalized.isEmpty) return rows.take(limit).toList();

    final needle = normalized.toLowerCase();
    return rows
        .where((row) {
          return (row['name']?.toString().toLowerCase().contains(needle) ??
                  false) ||
              (row['item_code']?.toString().toLowerCase().contains(needle) ??
                  false) ||
              (row['item_name']?.toString().toLowerCase().contains(needle) ??
                  false);
        })
        .take(limit)
        .toList();
  }

  Future<void> refreshInventoryForCompany(String company) async {
    if (_warehouses.isEmpty) {
      await fetchWarehousesFromFrappe();
    }

    final erpNames = erpWarehouseNamesForCompany(company);
    if (erpNames.isNotEmpty) {
      await fetchInventoryFromFrappe(
        filters: [
          ['warehouse', 'in', erpNames],
        ],
      );
      return;
    }

    _inventory = [];
    notifyListeners();
  }

  Future<void> saveFrappeConfig({
    required String username,
    String? password,
    bool savePassword = true,
    String? baseUrl,
    String? siteCode,
    String? siteName,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final shouldSavePassword =
        savePassword || _rememberDevice || password != null;
    final resolvedBaseUrl = _normalizeBaseUrl(
      baseUrl?.trim().isNotEmpty == true ? baseUrl! : _frappeService.baseUrl,
    );
    if (resolvedBaseUrl.isEmpty) {
      throw Exception('Frappe site belum dipilih.');
    }
    final cfg = {
      'username': username,
      'baseUrl': resolvedBaseUrl,
      if ((siteCode ?? _selectedSiteCode).trim().isNotEmpty)
        'siteCode': (siteCode ?? _selectedSiteCode).trim().toUpperCase(),
      'siteName': _publicSiteName(
        baseUrl: resolvedBaseUrl,
        storedName: siteName?.trim().isNotEmpty == true
            ? siteName!.trim()
            : _selectedSiteName,
      ),
      if (shouldSavePassword && password != null) 'password': password,
    };
    await sp.setString(_prefsFrappeConfigKey, jsonEncode(cfg));
    await _saveFrappeSiteHistory(
      baseUrl: resolvedBaseUrl,
      siteCode: cfg['siteCode'] ?? _selectedSiteCode,
      siteName: cfg['siteName']!,
    );

    _frappeService.baseUrl = resolvedBaseUrl;
    _frappeService.username = username;
    _selectedSiteCode = cfg['siteCode'] ?? _selectedSiteCode;
    _selectedSiteName = cfg['siteName']!;
    if (shouldSavePassword && password != null) {
      _frappeService.password = password;
    }
  }

  Future<Map<String, String>?> _loadFrappeConfig() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_prefsFrappeConfigKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (error) {
      throw Exception('Gagal membaca konfigurasi site tersimpan: $error');
    }
  }

  Future<List<SalesOrder>> _fetchSalesOrderPage({
    required int limitStart,
  }) async {
    final scopeFilters = await _salesDocumentScopeFilters('Sales Order');
    final filters = <List<dynamic>>[
      ...await _sellingDocumentFilters(
        'transaction_date',
        doctype: 'Sales Order',
      ),
      ...?_salesOrderFilters(_salesOrderStatus),
      ...?scopeFilters,
    ];
    final data = await _fetchResourceWithFieldFallback(
      doctype: 'Sales Order',
      fields: const [
        'name',
        'owner',
        'customer',
        'customer_name',
        'grand_total',
        'status',
        'workflow_state',
        'docstatus',
        'transaction_date',
        'delivery_date',
        'total_qty',
        'per_delivered',
        'per_billed',
      ],
      limit: _documentPageSize,
      limitStart: limitStart,
      orderBy: 'transaction_date desc, name desc',
      filters: filters.isEmpty ? null : filters,
      orFilters: _searchFilters(_salesOrderSearch, const [
        'name',
        'customer',
        'customer_name',
      ]),
    );

    var orders = data.map((item) => SalesOrder.fromJson(item)).toList();
    if (scopeFilters == null) {
      orders = await _filterSalesDocumentsByCurrentSalesPerson(
        doctype: 'Sales Order',
        docs: orders,
        idOf: (order) => order.id,
      );
    }
    orders = await _attachSalesOrderItems(orders);
    return orders;
  }

  Future<List<DeliveryNote>> _fetchDeliveryNotePage({
    required int limitStart,
  }) async {
    final scopeFilters = await _salesDocumentScopeFilters('Delivery Note');
    final filters = <List<dynamic>>[
      ...await _sellingDocumentFilters(
        'posting_date',
        doctype: 'Delivery Note',
      ),
      ...?_statusFilters(_deliveryNoteStatus),
      ...?scopeFilters,
    ];
    final data = await _fetchResourceWithFieldFallback(
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
      limit: _documentPageSize,
      limitStart: limitStart,
      orderBy: 'posting_date desc, name desc',
      filters: filters,
      orFilters: _searchFilters(_deliveryNoteSearch, const [
        'name',
        'customer',
        'customer_name',
      ]),
    );
    var docs = data.map(DeliveryNote.fromJson).toList();
    if (scopeFilters == null) {
      docs = await _filterSalesDocumentsByCurrentSalesPerson(
        doctype: 'Delivery Note',
        docs: docs,
        idOf: (doc) => doc.id,
      );
    }
    return docs;
  }

  Future<List<SalesInvoice>> _fetchSalesInvoicePage({
    required int limitStart,
  }) async {
    final scopeFilters = await _salesDocumentScopeFilters('Sales Invoice');
    final filters = <List<dynamic>>[
      ...await _sellingDocumentFilters(
        'posting_date',
        doctype: 'Sales Invoice',
      ),
      ...?_statusFilters(_salesInvoiceStatus),
      ...?scopeFilters,
    ];
    final data = await _fetchResourceWithFieldFallback(
      doctype: 'Sales Invoice',
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
        'outstanding_amount',
        'due_date',
      ],
      limit: _documentPageSize,
      limitStart: limitStart,
      orderBy: 'posting_date desc, name desc',
      filters: filters.isEmpty ? null : filters,
      orFilters: _searchFilters(_salesInvoiceSearch, const [
        'name',
        'customer',
        'customer_name',
      ]),
    );
    var docs = data.map(SalesInvoice.fromJson).toList();
    if (scopeFilters == null) {
      docs = await _filterSalesDocumentsByCurrentSalesPerson(
        doctype: 'Sales Invoice',
        docs: docs,
        idOf: (doc) => doc.id,
      );
    }
    return docs;
  }

  List<List<dynamic>>? _statusFilters(String? status) {
    if (status == null || status.isEmpty) return null;
    return [
      ['status', '=', status],
    ];
  }

  List<List<dynamic>> _sellingPeriodFilters(String dateField) {
    return [
      [dateField, '>=', DateRangePresets.toFrappeDate(sellingPeriodFrom)],
      [dateField, '<=', DateRangePresets.toFrappeDate(sellingPeriodTo)],
    ];
  }

  Future<List<List<dynamic>>> _sellingDocumentFilters(
    String dateField, {
    String? doctype,
  }) async {
    final filters = <List<dynamic>>[
      ..._sellingPeriodFilters(dateField),
      ..._companyScopeFilters(_sellingCompanyFilter),
    ];
    final parentSalesPerson = _selectedSellingParentSalesPerson();
    if (parentSalesPerson != null) {
      filters.add(['parent_sales_person', '=', parentSalesPerson]);
    }

    return filters;
  }

  String? _selectedSellingParentSalesPerson() {
    if (_shouldScopeSalesData) return null;
    final group = _sellingCustomerTypeFilter.trim();
    if (group.isEmpty || group.toLowerCase() == 'all') return null;
    return group;
  }

  double _sellingAnalyticsValue(Map<String, dynamic> row) {
    final baseNetTotal = NumParse.asDouble(row['base_net_total']);
    if (baseNetTotal != 0) return baseNetTotal;
    final netTotal = NumParse.asDouble(row['net_total']);
    if (netTotal != 0) return netTotal;
    return NumParse.asDouble(row['grand_total']);
  }

  bool _isActiveSellingTrendRow(Map<String, dynamic> row) {
    final docstatus = NumParse.asInt(row['docstatus']);
    if (docstatus != 1) return false;

    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    if (status == 'draft' || status == 'cancelled') return false;
    if (status == 'return') return false;

    return true;
  }

  bool _isActivePurchaseOrderTrendRow(Map<String, dynamic> row) {
    final docstatus = NumParse.asInt(row['docstatus']);
    if (docstatus != 1) return false;

    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    return status == 'to receive and bill' ||
        status == 'to receive and to bill' ||
        status == 'to bill' ||
        status == 'to receive' ||
        status == 'completed';
  }

  bool _isActiveBuyingTrendRow(Map<String, dynamic> row) {
    final docstatus = NumParse.asInt(row['docstatus']);
    if (docstatus != 1) return false;

    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    if (status == 'draft' || status == 'cancelled') return false;
    if (status.contains('return')) return false;

    return true;
  }

  double _buyingAnalyticsValue(Map<String, dynamic> row) {
    final baseNetTotal = NumParse.asDouble(row['base_net_total']);
    if (baseNetTotal != 0) return baseNetTotal;
    final netTotal = NumParse.asDouble(row['net_total']);
    if (netTotal != 0) return netTotal;
    return NumParse.asDouble(row['grand_total']);
  }

  List<List<dynamic>> _buyingPeriodFilters(String dateField) {
    return [
      [dateField, '>=', DateRangePresets.toFrappeDate(buyingPeriodFrom)],
      [dateField, '<=', DateRangePresets.toFrappeDate(buyingPeriodTo)],
      ..._companyScopeFilters(_buyingCompanyFilter),
    ];
  }

  List<List<dynamic>> _companyScopeFilters(String selectedCompany) {
    final selected = selectedCompany.trim();
    if (selected.isNotEmpty) {
      return [
        ['company', '=', selected],
      ];
    }
    return const [];
  }

  bool _matchesBuyingSupplierType(
    Map<String, dynamic> row,
    List<String>? supplierIds,
  ) {
    if (supplierIds == null) return true;
    if (supplierIds.isEmpty) return false;
    return supplierIds.contains(row['supplier']?.toString() ?? '');
  }

  Future<List<String>?> _buyingSupplierTypeSupplierIds() async {
    final type = _buyingSupplierTypeFilter.trim().toLowerCase();
    if (type.isEmpty || type == 'all') return null;
    if (_buyingSupplierTypeIdsCacheKey == type &&
        _buyingSupplierTypeIdsCache != null) {
      return _buyingSupplierTypeIdsCache;
    }

    final internal = type == 'internal';
    List<Map<String, dynamic>> rows;
    try {
      rows = await _fetchAllResourcePages(
        doctype: 'Supplier',
        fields: const ['name', 'is_internal_supplier'],
        maxRows: null,
      );
    } catch (_) {
      return null;
    }

    final ids = rows
        .where(
          (row) =>
              NumParse.asInt(row['is_internal_supplier']) == (internal ? 1 : 0),
        )
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList();
    _buyingSupplierTypeIdsCacheKey = type;
    _buyingSupplierTypeIdsCache = ids;
    return ids;
  }

  List<List<dynamic>>? _salesOrderFilters(String? status) {
    return _statusFilters(status);
  }

  List<List<dynamic>>? _searchFilters(String search, List<String> fields) {
    final query = search.trim();
    if (query.isEmpty) return null;
    return fields
        .map<List<dynamic>>((field) => [field, 'like', '%$query%'])
        .toList();
  }

  Future<List<PurchaseOrder>> _fetchPurchaseOrderPage({
    required int limitStart,
  }) async {
    final filters = <List<dynamic>>[
      ..._buyingPeriodFilters('transaction_date'),
      ...?_purchaseOrderFilters(_purchaseOrderStatus),
    ];
    final supplierTypeIds = await _buyingSupplierTypeSupplierIds();
    final data = await _fetchResourceWithFieldFallback(
      doctype: 'Purchase Order',
      fields: const [
        'name',
        'supplier',
        'supplier_name',
        'status',
        'docstatus',
        'transaction_date',
        'schedule_date',
        'total_qty',
        'base_net_total',
        'net_total',
        'grand_total',
        'creation',
        'modified',
      ],
      limit: _documentPageSize,
      limitStart: limitStart,
      orderBy: 'modified desc, name desc',
      filters: filters,
      orFilters: _searchFilters(_purchaseOrderSearch, const [
        'name',
        'supplier',
        'supplier_name',
      ]),
    );

    var orders = data
        .where((item) => _matchesBuyingSupplierType(item, supplierTypeIds))
        .map((item) => PurchaseOrder.fromJson(item))
        .toList();
    orders = await _attachPurchaseOrderItems(orders);
    return orders;
  }

  Future<List<PurchaseReceipt>> _fetchPurchaseReceiptPage({
    required int limitStart,
  }) async {
    final filters = <List<dynamic>>[
      ..._buyingPeriodFilters('posting_date'),
      ...?_statusFilters(_purchaseReceiptStatus),
    ];
    final supplierTypeIds = await _buyingSupplierTypeSupplierIds();
    final data = await _fetchResourceWithFieldFallback(
      doctype: 'Purchase Receipt',
      fields: const [
        'name',
        'supplier',
        'supplier_name',
        'status',
        'docstatus',
        'posting_date',
        'grand_total',
        'total_qty',
      ],
      limit: _documentPageSize,
      limitStart: limitStart,
      orderBy: 'posting_date desc, name desc',
      filters: filters,
      orFilters: _searchFilters(_purchaseReceiptSearch, const [
        'name',
        'supplier',
        'supplier_name',
      ]),
    );
    return data
        .where((item) => _matchesBuyingSupplierType(item, supplierTypeIds))
        .map(PurchaseReceipt.fromJson)
        .toList();
  }

  Future<List<PurchaseInvoice>> _fetchPurchaseInvoicePage({
    required int limitStart,
  }) async {
    final filters = <List<dynamic>>[
      ..._buyingPeriodFilters('posting_date'),
      ...?_statusFilters(_purchaseInvoiceStatus),
    ];
    final supplierTypeIds = await _buyingSupplierTypeSupplierIds();
    final data = await _fetchResourceWithFieldFallback(
      doctype: 'Purchase Invoice',
      fields: const [
        'name',
        'supplier',
        'supplier_name',
        'status',
        'docstatus',
        'posting_date',
        'grand_total',
        'outstanding_amount',
        'due_date',
      ],
      limit: _documentPageSize,
      limitStart: limitStart,
      orderBy: 'posting_date desc, name desc',
      filters: filters,
      orFilters: _searchFilters(_purchaseInvoiceSearch, const [
        'name',
        'supplier',
        'supplier_name',
      ]),
    );
    return data
        .where((item) => _matchesBuyingSupplierType(item, supplierTypeIds))
        .map(PurchaseInvoice.fromJson)
        .toList();
  }

  Future<List<MaterialRequest>> _fetchMaterialRequestPage({
    required int limitStart,
  }) async {
    final filters = <List<dynamic>>[
      ..._buyingPeriodFilters('transaction_date'),
      ...?_statusFilters(_materialRequestStatus),
    ];
    final data = await _fetchResourceWithFieldFallback(
      doctype: 'Material Request',
      fields: const [
        'name',
        'material_request_type',
        'status',
        'docstatus',
        'transaction_date',
        'schedule_date',
        'company',
        'total_qty',
      ],
      limit: _documentPageSize,
      limitStart: limitStart,
      orderBy: 'transaction_date desc, name desc',
      filters: filters,
      orFilters: _searchFilters(_materialRequestSearch, const [
        'name',
        'material_request_type',
        'company',
      ]),
    );

    var requests = data.map(MaterialRequest.fromJson).toList();
    requests = await _attachMaterialRequestItems(requests);
    return requests;
  }

  List<List<dynamic>>? _purchaseOrderFilters(String? status) {
    if (status == 'To Receive and To Bill') {
      return [
        [
          'status',
          'in',
          ['To Receive and Bill', 'To Receive and To Bill'],
        ],
      ];
    }
    return _statusFilters(status);
  }

  Future<List<SalesOrder>> _attachSalesOrderItems(
    List<SalesOrder> orders,
  ) async {
    if (orders.isEmpty) return orders;
    try {
      final rows = await _fetchAllResourcePages(
        doctype: 'Sales Order Item',
        fields: const [
          'parent',
          'item_code',
          'item_name',
          'qty',
          'rate',
          'warehouse',
        ],
        filters: [
          ['parent', 'in', orders.map((order) => order.id).toList()],
        ],
        maxRows: 2000,
      );
      final grouped = <String, List<SalesOrderItem>>{};
      for (final row in rows) {
        final parent = row['parent']?.toString() ?? '';
        if (parent.isEmpty) continue;
        grouped.putIfAbsent(parent, () => []).add(SalesOrderItem.fromJson(row));
      }
      return orders
          .map(
            (order) => order.copyWith(items: grouped[order.id] ?? order.items),
          )
          .toList();
    } catch (_) {
      return orders;
    }
  }

  Future<List<PurchaseOrder>> _attachPurchaseOrderItems(
    List<PurchaseOrder> orders,
  ) async {
    if (orders.isEmpty) return orders;
    try {
      final rows = await _fetchAllResourcePages(
        doctype: 'Purchase Order Item',
        fields: const [
          'parent',
          'item_code',
          'item_name',
          'qty',
          'rate',
          'warehouse',
        ],
        filters: [
          ['parent', 'in', orders.map((order) => order.id).toList()],
        ],
        maxRows: 2000,
      );
      final grouped = <String, List<PurchaseOrderItem>>{};
      for (final row in rows) {
        final parent = row['parent']?.toString() ?? '';
        if (parent.isEmpty) continue;
        grouped
            .putIfAbsent(parent, () => [])
            .add(PurchaseOrderItem.fromJson(row));
      }
      return orders
          .map(
            (order) => order.copyWith(items: grouped[order.id] ?? order.items),
          )
          .toList();
    } catch (_) {
      return orders;
    }
  }

  Future<List<MaterialRequest>> _attachMaterialRequestItems(
    List<MaterialRequest> requests,
  ) async {
    if (requests.isEmpty) return requests;
    try {
      final rows = await _fetchAllResourcePages(
        doctype: 'Material Request Item',
        fields: const [
          'parent',
          'item_code',
          'item_name',
          'qty',
          'ordered_qty',
          'stock_uom',
          'warehouse',
          'schedule_date',
        ],
        filters: [
          ['parent', 'in', requests.map((request) => request.id).toList()],
        ],
        maxRows: 2000,
      );
      final grouped = <String, List<MaterialRequestItem>>{};
      for (final row in rows) {
        final parent = row['parent']?.toString() ?? '';
        if (parent.isEmpty) continue;
        grouped
            .putIfAbsent(parent, () => [])
            .add(MaterialRequestItem.fromJson(row));
      }
      return requests
          .map(
            (request) =>
                request.copyWith(items: grouped[request.id] ?? request.items),
          )
          .toList();
    } catch (_) {
      return requests;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAllResourcePages({
    required String doctype,
    required List<String> fields,
    String? orderBy,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
    required int? maxRows,
  }) async {
    return walkFrappePages(
      pageSize: _frappePageSize,
      maxRows: maxRows,
      fetchPage: (start, limit) => _fetchResourceWithFieldFallback(
        doctype: doctype,
        fields: fields,
        limit: limit,
        limitStart: start,
        orderBy: orderBy,
        filters: filters,
        orFilters: orFilters,
      ),
    );
  }

  static List<Map<String, dynamic>> _documentChildRows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, dynamic>> _fetchCachedDocument(
    String doctype,
    String name,
  ) async {
    final key = _documentCacheKey(doctype, name);
    final cached = _documentCache[key];
    if (cached != null && cached.isFresh) return cached.document;

    final stored = await LocalAppDatabase.instance.readJson(key);
    if (stored != null) {
      _documentCache[key] = _CachedDocument(
        storedAt: DateTime.now(),
        document: stored,
      );
      return stored;
    }

    final document = await _frappeService.fetchDocument(doctype, name);
    await _storeCachedDocument(doctype, name, document);
    return document;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchDocumentsInBatches(
    String doctype,
    Iterable<String> names, {
    int batchSize = 8,
  }) async {
    final uniqueNames = names.where((name) => name.isNotEmpty).toSet().toList();
    final documents = <String, Map<String, dynamic>>{};
    final missingNames = <String>[];
    for (final name in uniqueNames) {
      final key = _documentCacheKey(doctype, name);
      final cached = _documentCache[key];
      if (cached != null && cached.isFresh) {
        documents[name] = cached.document;
      } else {
        final stored = await LocalAppDatabase.instance.readJson(key);
        if (stored != null) {
          documents[name] = stored;
          _documentCache[key] = _CachedDocument(
            storedAt: DateTime.now(),
            document: stored,
          );
        } else {
          missingNames.add(name);
        }
      }
    }
    for (var start = 0; start < missingNames.length; start += batchSize) {
      final end = start + batchSize > missingNames.length
          ? missingNames.length
          : start + batchSize;
      final batch = missingNames.sublist(start, end);
      final results = await Future.wait(
        batch.map((name) async {
          try {
            return (
              name: name,
              document: await _frappeService.fetchDocument(doctype, name),
            );
          } catch (_) {
            return (name: name, document: null);
          }
        }),
      );
      for (final result in results) {
        final document = result.document;
        if (document != null) {
          documents[result.name] = document;
          await _storeCachedDocument(doctype, result.name, document);
        }
      }
    }
    return documents;
  }

  Future<void> _storeCachedDocument(
    String doctype,
    String name,
    Map<String, dynamic> document,
  ) async {
    final key = _documentCacheKey(doctype, name);
    _documentCache[key] = _CachedDocument(
      storedAt: DateTime.now(),
      document: document,
    );
    await LocalAppDatabase.instance.writeJson(
      key,
      document,
      ttl: _documentCacheTtl,
    );
  }

  Future<void> _deleteCachedDocument(String doctype, String name) async {
    final key = _documentCacheKey(doctype, name);
    _documentCache.remove(key);
    await LocalAppDatabase.instance.delete(key);
  }

  Future<List<Map<String, dynamic>>?> _readDbRowList(String key) async {
    final json = await LocalAppDatabase.instance.readJson(key);
    final rows = json?['rows'];
    if (rows is! List) return null;
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _writeDbRowList(
    String key,
    List<Map<String, dynamic>> rows, {
    required Duration ttl,
  }) {
    return LocalAppDatabase.instance.writeJson(key, {'rows': rows}, ttl: ttl);
  }

  String _documentCacheKey(String doctype, String name) {
    final site = _frappeService.baseUrl.trim();
    final user = _currentUser?.trim() ?? _frappeService.username?.trim() ?? '';
    return [
      _documentDbCachePrefix,
      site,
      user,
      doctype.trim(),
      name.trim(),
    ].join('|');
  }

  Future<void> _forEachResourcePage({
    required String doctype,
    required List<String> fields,
    required void Function(Map<String, dynamic> row) onRow,
    String? orderBy,
    List<List<dynamic>>? filters,
  }) async {
    final progressBase = _summaryProcessedRows;
    await walkFrappePages(
      pageSize: _frappePageSize,
      onRow: onRow,
      onProgress: (processed) {
        _summaryProcessedRows = progressBase + processed;
        notifyListeners();
      },
      fetchPage: (start, limit) => _fetchResourceWithFieldFallback(
        doctype: doctype,
        fields: fields,
        limit: limit,
        limitStart: start,
        orderBy: orderBy ?? 'name asc',
        filters: filters,
      ),
    );
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
      if (_supportsSalesTeamParentFilter(doctype) &&
          _usesSalesTeamChildFilter(filters)) {
        return _frappeService.fetchReportView(
          doctype,
          fields: remainingFields,
          limit: limit,
          limitStart: limitStart,
          orderBy: currentOrderBy,
          filters: _salesTeamReportViewFilters(filters),
          orFilters: orFilters,
        );
      }

      try {
        return await _frappeService.fetchResource(
          doctype,
          fields: remainingFields,
          limit: limit,
          limitStart: limitStart,
          orderBy: currentOrderBy,
          filters: filters,
          orFilters: orFilters,
        );
      } catch (err) {
        final errStr = err.toString();

        final fieldReg = RegExp(
          r'Field not permitted in query:\s*([a-zA-Z0-9_]+)',
        );
        final fieldMatch = fieldReg.firstMatch(errStr);

        if (fieldMatch != null) {
          final badField = fieldMatch.group(1);
          if (badField != null && remainingFields.contains(badField)) {
            remainingFields.remove(badField);
            continue;
          }
        }

        if (currentOrderBy != null &&
            (errStr.contains('order_by') || errStr.contains('Order By'))) {
          currentOrderBy = null;
          continue;
        }

        rethrow;
      }
    }

    throw Exception('No permitted fields available for $doctype.');
  }

  bool _supportsSalesTeamParentFilter(String doctype) {
    return doctype == 'Sales Order' ||
        doctype == 'Delivery Note' ||
        doctype == 'Sales Invoice';
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

  Future<
    Map<
      String,
      ({String name, String itemGroup, int reorderLevel, double valuationRate})
    >
  >
  _fetchItemMeta(Set<String> itemCodes) async {
    if (itemCodes.isEmpty) return {};

    final codes = itemCodes.toList();
    final meta =
        <
          String,
          ({
            String name,
            String itemGroup,
            int reorderLevel,
            double valuationRate,
          })
        >{};

    for (var i = 0; i < codes.length; i += 80) {
      final chunk = codes.sublist(
        i,
        i + 80 > codes.length ? codes.length : i + 80,
      );
      try {
        final data = await _fetchResourceWithFieldFallback(
          doctype: 'Item',
          fields: const [
            'name',
            'item_name',
            'item_group',
            'reorder_level',
            'valuation_rate',
          ],
          limit: chunk.length,
          filters: [
            ['name', 'in', chunk],
          ],
        );
        for (final row in data) {
          final code = row['name']?.toString() ?? '';
          if (code.isEmpty) continue;
          meta[code] = (
            name: row['item_name']?.toString() ?? code,
            itemGroup: row['item_group']?.toString() ?? '',
            reorderLevel: NumParse.asInt(row['reorder_level']),
            valuationRate: NumParse.asDouble(row['valuation_rate']),
          );
        }
      } catch (_) {
        try {
          final data = await _fetchResourceWithFieldFallback(
            doctype: 'Item',
            fields: const ['name', 'item_name', 'item_group'],
            limit: chunk.length,
            filters: [
              ['name', 'in', chunk],
            ],
          );
          for (final row in data) {
            final code = row['name']?.toString() ?? '';
            if (code.isEmpty) continue;
            meta[code] = (
              name: row['item_name']?.toString() ?? code,
              itemGroup: row['item_group']?.toString() ?? '',
              reorderLevel: 0,
              valuationRate: 0,
            );
          }
        } catch (_) {}
      }
    }

    return meta;
  }

  Future<Map<String, double>> _fetchItemBuyingRates(
    Set<String> itemCodes,
  ) async {
    if (itemCodes.isEmpty) return {};

    final codes = itemCodes.toList();
    final rates = <String, double>{};

    for (var i = 0; i < codes.length; i += 80) {
      final chunk = codes.sublist(
        i,
        i + 80 > codes.length ? codes.length : i + 80,
      );

      try {
        final data = await _fetchResourceWithFieldFallback(
          doctype: 'Item Price',
          fields: const [
            'name',
            'item_code',
            'price_list',
            'price_list_rate',
            'currency',
          ],
          limit: chunk.length * 3,
          orderBy: 'valid_from desc, modified desc',
          filters: [
            ['item_code', 'in', chunk],
            ['buying', '=', 1],
            ['price_list_rate', '>', 0],
          ],
        );
        _addItemPriceRates(rates, data);
      } catch (_) {
        try {
          final data = await _fetchResourceWithFieldFallback(
            doctype: 'Item Price',
            fields: const ['name', 'item_code', 'price_list_rate'],
            limit: chunk.length * 3,
            orderBy: 'modified desc',
            filters: [
              ['item_code', 'in', chunk],
              ['price_list_rate', '>', 0],
            ],
          );
          _addItemPriceRates(rates, data);
        } catch (_) {}
      }
    }

    return rates;
  }

  Future<List<Map<String, dynamic>>> fetchSupplierPriceRowsForItems(
    Set<String> itemCodes,
  ) async {
    if (itemCodes.isEmpty) return const [];

    final codes = itemCodes.where((code) => code.trim().isNotEmpty).toList();
    final rows = <Map<String, dynamic>>[];

    for (var i = 0; i < codes.length; i += 50) {
      final chunk = codes.sublist(
        i,
        i + 50 > codes.length ? codes.length : i + 50,
      );

      try {
        final data = await _fetchResourceWithFieldFallback(
          doctype: 'Item Price',
          fields: const [
            'name',
            'item_code',
            'supplier',
            'price_list',
            'price_list_rate',
            'currency',
          ],
          limit: chunk.length * 8,
          orderBy: 'price_list_rate asc, modified desc',
          filters: [
            ['item_code', 'in', chunk],
            ['buying', '=', 1],
            ['price_list_rate', '>', 0],
          ],
        );
        rows.addAll(data);
      } catch (_) {
        final data = await _fetchResourceWithFieldFallback(
          doctype: 'Item Price',
          fields: const ['name', 'item_code', 'price_list', 'price_list_rate'],
          limit: chunk.length * 8,
          orderBy: 'price_list_rate asc, modified desc',
          filters: [
            ['item_code', 'in', chunk],
            ['price_list_rate', '>', 0],
          ],
        );
        rows.addAll(data);
      }
    }

    return rows;
  }

  void _addItemPriceRates(
    Map<String, double> rates,
    List<Map<String, dynamic>> rows,
  ) {
    for (final row in rows) {
      final code = row['item_code']?.toString() ?? '';
      final rate = NumParse.asDouble(row['price_list_rate']);
      if (code.isEmpty || rate <= 0) continue;
      rates.putIfAbsent(code, () => rate);
    }
  }
}

class _SalesCustomerDocumentSpec {
  final String doctype;
  final String dateField;

  const _SalesCustomerDocumentSpec({
    required this.doctype,
    required this.dateField,
  });
}

class _InactiveDocumentSpec {
  final String doctype;
  final String dateField;

  const _InactiveDocumentSpec({required this.doctype, required this.dateField});
}

class _InactiveCustomerAccumulator {
  final String doctype;
  final String customer;
  String customerName;
  String lastOrder = '';
  DateTime? lastOrderDate;
  double totalOrderValue = 0;

  _InactiveCustomerAccumulator({
    required this.doctype,
    required this.customer,
    required this.customerName,
  });

  void addDocument({
    required String name,
    required DateTime? date,
    required double amount,
    required String customerName,
  }) {
    if (customerName.trim().isNotEmpty) {
      this.customerName = customerName.trim();
    }
    totalOrderValue += amount;
    if (date == null) return;
    final current = lastOrderDate;
    if (current == null || date.isAfter(current)) {
      lastOrderDate = date;
      lastOrder = name;
    }
  }

  InactiveCustomer toInactiveCustomer({required int daysSinceLastOrder}) {
    return InactiveCustomer(
      documentType: doctype,
      customer: customer,
      customerName: customerName,
      customerGroup: '',
      territory: '',
      lastOrder: lastOrder,
      lastOrderDate: lastOrderDate == null
          ? ''
          : DateRangePresets.toFrappeDate(lastOrderDate!),
      daysSinceLastOrder: daysSinceLastOrder,
      totalOrderValue: totalOrderValue,
    );
  }
}

class _MobileAnalyticsSection {
  final DocumentSummary summary;
  final List<DocumentTrendPoint> trend;

  const _MobileAnalyticsSection({required this.summary, required this.trend});
}

class _SellingAnalyticsTimeoutException implements Exception {
  final String documentType;

  const _SellingAnalyticsTimeoutException(this.documentType);
}

class _CustomerSalesTotal {
  final String salesPerson;
  final String customer;
  final String customerName;
  final double amount;
  final int orderCount;

  const _CustomerSalesTotal({
    required this.salesPerson,
    required this.customer,
    required this.customerName,
    required this.amount,
    required this.orderCount,
  });
}

class _DailySalesMutable {
  final String label;
  final String itemGroup;
  double qty = 0;
  double amount = 0;

  _DailySalesMutable(this.label, {this.itemGroup = ''});

  void add({required double qty, required double amount}) {
    this.qty += qty;
    this.amount += amount;
  }

  DailySalesItemSummary toSummary() {
    return DailySalesItemSummary(
      itemLabel: label,
      itemGroup: itemGroup,
      qty: qty,
      amount: amount,
    );
  }
}

class _DailyCustomerMutable {
  final String customer;
  final Map<String, _DailySalesMutable> _items = {};

  _DailyCustomerMutable(this.customer);

  void add({
    required String label,
    required String itemGroup,
    required double qty,
    required double amount,
  }) {
    _items
        .putIfAbsent(
          label,
          () => _DailySalesMutable(label, itemGroup: itemGroup),
        )
        .add(qty: qty, amount: amount);
  }

  DailySalesCustomerSummary toSummary() {
    final items = _items.values.map((row) => row.toSummary()).toList()
      ..sort((a, b) {
        final labelComparison = a.itemLabel.compareTo(b.itemLabel);
        if (labelComparison != 0) return labelComparison;
        return b.amount.compareTo(a.amount);
      });
    final total = items.fold<double>(0, (sum, row) => sum + row.amount);
    return DailySalesCustomerSummary(
      customer: customer,
      items: items,
      totalAmount: total,
    );
  }
}
