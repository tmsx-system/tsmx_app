import 'package:flutter/material.dart';

import '../../models/inventory_item.dart';
import '../../models/quality_inspection_record.dart';
import '../../models/stock_area_option.dart';
import '../../models/stock_entry.dart';
import '../../models/stock_ledger_movement.dart';
import '../../models/warehouse_info.dart';
import '../../models/warehouse_tracking_record.dart';
import '../../services/frappe_service.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/frappe_page_walker.dart';
import '../../utils/num_parse.dart';
import '../app_state_proxy_notifier.dart';

class WarehouseStockState extends AppStateProxyNotifier {
  WarehouseStockState({required super.appState}) {
    startWatchingAppState();
  }

  static const int _pageSize = 500;
  static const int _listLimit = 500;

  List<WarehouseInfo> _warehouses = const [];
  List<InventoryItem> _inventory = const [];
  List<String> _itemGroups = const [];
  List<StockEntry> _stockEntries = const [];
  List<StockReconciliationSummary> _stockReconciliations = const [];
  bool _isInventoryLoading = false;
  bool _isStockEntriesLoading = false;
  String? _inventoryError;
  String? _stockEntriesError;
  Future<void>? _warehousesFetchInFlight;
  Future<void>? _inventoryFetchInFlight;
  Future<List<WarehouseBatchRecord>>? _warehouseBatchInFlight;
  Future<List<WarehouseSerialRecord>>? _warehouseSerialInFlight;
  final Map<String, Future<List<QualityInspectionRecord>>>
  _qualityInspectionInFlight = {};
  _CacheEntry<List<WarehouseBatchRecord>>? _warehouseBatchCache;
  _CacheEntry<List<WarehouseSerialRecord>>? _warehouseSerialCache;
  final Map<String, _CacheEntry<List<QualityInspectionRecord>>>
  _qualityInspectionCache = {};

  static const Duration _trackingCacheTtl = Duration(minutes: 2);
  static const Duration _qualityInspectionCacheTtl = Duration(minutes: 2);

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.mobileBoot,
    appState.selectedSiteBaseUrl,
  ];

  List<WarehouseInfo> get warehouses => _warehouses;
  List<InventoryItem> get inventory => _inventory;
  List<String> get itemGroups => _itemGroups;
  List<StockEntry> get stockEntries => _stockEntries;
  List<StockReconciliationSummary> get stockReconciliations =>
      _stockReconciliations;
  bool get isInventoryLoading => _isInventoryLoading;
  String? get inventoryError => _inventoryError;
  bool get isStockEntriesLoading => _isStockEntriesLoading;
  String? get stockEntriesError => _stockEntriesError;
  FrappeService get frappeService => appState.frappeService;

  List<MapEntry<String, String>> get stockCompanies {
    final labels = <String, String>{};
    for (final warehouse in _warehouses) {
      if (warehouse.company.isEmpty) continue;
      labels.putIfAbsent(warehouse.company, () => warehouse.company);
    }
    final allowedSet = (appState.mobileBoot?.companies ?? const <String>[])
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
    return source.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  }

  Future<bool> canReadDoctype(String doctype) {
    return appState.canReadDoctype(doctype);
  }

  Future<bool> canCreateDoctype(String doctype) {
    return appState.canCreateDoctype(doctype);
  }

  Future<void> refreshWarehouses() {
    final inFlight = _warehousesFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _refreshWarehouses();
    _warehousesFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_warehousesFetchInFlight, request)) {
        _warehousesFetchInFlight = null;
      }
    });
  }

  Future<void> _refreshWarehouses() async {
    if (appState.isSampleMode) {
      _warehouses = appState.warehouses;
      notifyListeners();
      return;
    }

    try {
      await appState.frappeService.ensureLoggedIn();
      List<Map<String, dynamic>> rows;
      try {
        rows = await _fetchAllResourcePages(
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
        rows = await _fetchAllResourcePages(
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
      _warehouses = rows
          .map(WarehouseInfo.fromJson)
          .where((row) => row.name.isNotEmpty && !row.isGroup)
          .toList();
    } catch (_) {
      if (_warehouses.isEmpty) _warehouses = appState.warehouses;
    } finally {
      notifyListeners();
    }
  }

  Future<void> refreshItemGroups() async {
    if (appState.isSampleMode) {
      _itemGroups = _groupsFromInventory();
      notifyListeners();
      return;
    }

    try {
      await appState.frappeService.ensureLoggedIn();
      final rows = await _fetchAllResourcePages(
        doctype: 'Item Group',
        fields: const ['name'],
        orderBy: 'name asc',
        maxRows: _listLimit,
      );
      _itemGroups =
          rows
              .map((row) => row['name']?.toString().trim() ?? '')
              .where((group) => group.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
    } catch (_) {
      final fallback = _groupsFromInventory();
      if (fallback.isNotEmpty) _itemGroups = fallback;
    } finally {
      notifyListeners();
    }
  }

  Future<void> refreshInventory() {
    return _refreshInventory(filters: _inventoryScopeFiltersForCurrentRole());
  }

  Future<void> refreshInventoryForCompany(String company) async {
    if (_warehouses.isEmpty) await refreshWarehouses();
    final names = erpWarehouseNamesForCompany(company);
    if (names.isEmpty) {
      _inventory = const [];
      notifyListeners();
      return;
    }
    await _refreshInventory(
      filters: [
        ['warehouse', 'in', names],
      ],
    );
  }

  Future<void> _refreshInventory({List<List<dynamic>>? filters}) {
    final canReuseInFlight = filters == null;
    final inFlight = _inventoryFetchInFlight;
    if (canReuseInFlight && inFlight != null) return inFlight;
    final request = _fetchInventory(filters: filters);
    if (canReuseInFlight) _inventoryFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_inventoryFetchInFlight, request)) {
        _inventoryFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchInventory({List<List<dynamic>>? filters}) async {
    if (appState.isSampleMode) {
      _inventory = appState.inventory;
      _inventoryError = null;
      notifyListeners();
      return;
    }

    _isInventoryLoading = true;
    _inventoryError = null;
    notifyListeners();

    try {
      await appState.frappeService.ensureLoggedIn();
      if (_warehouses.isEmpty) await refreshWarehouses();

      final maxRows = filters == null ? _listLimit : null;
      List<Map<String, dynamic>> rows;
      try {
        rows = await _fetchAllResourcePages(
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
        rows = await _fetchAllResourcePages(
          doctype: 'Bin',
          fields: const ['item_code', 'warehouse', 'actual_qty'],
          filters: filters,
          maxRows: maxRows,
        );
      }

      final items = <InventoryItem>[];
      for (final row in rows) {
        final warehouse = row['warehouse']?.toString() ?? '';
        if (warehouse.isEmpty) continue;
        items.add(InventoryItem.fromJson(row).copyWith(warehouseId: warehouse));
      }

      final itemMeta = await _fetchItemMeta(
        items.map((item) => item.sku).where((sku) => sku.isNotEmpty).toSet(),
      );
      _inventory = [
        for (final item in items)
          (itemMeta[item.sku]?.applyTo(item) ?? item).withRecalculatedStatus(),
      ];
      _inventoryError = null;
      if (_itemGroups.isEmpty) _itemGroups = _groupsFromInventory();
    } catch (error) {
      _inventoryError = error.toString();
    } finally {
      _isInventoryLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshStockEntries() async {
    _isStockEntriesLoading = true;
    _stockEntriesError = null;
    notifyListeners();

    try {
      await appState.frappeService.ensureLoggedIn();
      List<Map<String, dynamic>> rows;
      try {
        rows = await _fetchAllResourcePages(
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
          filters: _companyScopeFilters(''),
          maxRows: _listLimit,
        );
      } catch (_) {
        rows = await walkFrappePages(
          pageSize: _pageSize,
          maxRows: _listLimit,
          fetchPage: (start, limit) => appState.frappeService.fetchReportView(
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
            filters: _companyScopeFilters(''),
          ),
        );
      }
      _stockEntries = rows.map(StockEntry.fromJson).toList();
      _stockEntriesError = null;
    } catch (error) {
      _stockEntriesError = error.toString();
    } finally {
      _isStockEntriesLoading = false;
      notifyListeners();
    }
  }

  String? preferredCompany(Iterable<String> options) {
    return appState.preferredCompany(options);
  }

  String? preferredWarehouse(Iterable<WarehouseInfo> options) {
    return appState.preferredWarehouse(options);
  }

  List<StockAreaOption> stockWarehousesForCompany(String company) {
    final areas = <StockAreaOption>[];
    final seen = <String>{};
    for (final warehouse in _warehouses.where((w) => w.company == company)) {
      if (warehouse.name.isEmpty || !seen.add(warehouse.name)) continue;
      areas.add(
        StockAreaOption(
          areaId: warehouse.name,
          title: warehouse.name,
          subtitle: warehouse.displayName == warehouse.name
              ? ''
              : warehouse.displayName,
          icon: Icons.inventory_2_outlined,
        ),
      );
    }
    areas.sort((a, b) => _compareWarehouseNames(a.title, b.title));
    return areas;
  }

  Future<StockLedgerResult> fetchStockLedgerForItem({
    required String itemCode,
    required DateTime from,
    required DateTime to,
  }) async {
    await appState.frappeService.ensureLoggedIn();
    final rows = await _fetchAllResourcePages(
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
        ['posting_date', '>=', DateRangePresets.toFrappeDate(from)],
        ['posting_date', '<=', DateRangePresets.toFrappeDate(to)],
        ...?_warehouseScopeFilters(),
      ],
      maxRows: null,
    );
    return StockLedgerResult.fromMovements(
      rows.map(StockLedgerMovement.fromJson).toList(),
    );
  }

  Future<StockEntry> createStockEntry({
    required String stockEntryType,
    required List<Map<String, dynamic>> items,
    DateTime? postingDate,
  }) async {
    await appState.frappeService.ensureLoggedIn();

    final created = await appState.frappeService.createDocument('Stock Entry', {
      'stock_entry_type': stockEntryType,
      'posting_date': DateRangePresets.toFrappeDate(
        postingDate ?? DateTime.now(),
      ),
      'items': items,
    });
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
    await appState.frappeService.ensureLoggedIn();
    if (company.trim().isEmpty) {
      throw Exception('Company gudang belum tersedia.');
    }
    if (warehouse.trim().isEmpty) {
      throw Exception('Warehouse wajib dipilih.');
    }
    if (items.isEmpty) {
      throw Exception('Tambahkan minimal satu item stock opname.');
    }

    final created = await appState.frappeService.createDocument(
      'Stock Reconciliation',
      {
        'company': company.trim(),
        'purpose': 'Stock Reconciliation',
        'posting_date': DateRangePresets.toFrappeDate(
          postingDate ?? DateTime.now(),
        ),
        'items': [
          for (final item in items) {...item, 'warehouse': warehouse.trim()},
        ],
      },
    );
    await refreshStockReconciliations();
    return created;
  }

  Future<void> refreshStockReconciliations() async {
    await appState.frappeService.ensureLoggedIn();
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
      maxRows: _listLimit,
    );
    _stockReconciliations = rows
        .map(StockReconciliationSummary.fromJson)
        .toList();
    notifyListeners();
  }

  Future<List<WarehouseBatchRecord>> fetchWarehouseBatches({
    bool forceRefresh = false,
  }) async {
    final cache = _warehouseBatchCache;
    if (!forceRefresh && cache != null && !cache.isExpired) return cache.value;

    final inFlight = _warehouseBatchInFlight;
    if (inFlight != null) return inFlight;

    final request = _fetchWarehouseBatchesFromErp();
    _warehouseBatchInFlight = request;
    return request
        .then((rows) {
          _warehouseBatchCache = _CacheEntry(rows, _trackingCacheTtl);
          return rows;
        })
        .whenComplete(() {
          if (identical(_warehouseBatchInFlight, request)) {
            _warehouseBatchInFlight = null;
          }
        });
  }

  Future<List<WarehouseSerialRecord>> fetchWarehouseSerialNumbers({
    bool forceRefresh = false,
  }) async {
    final cache = _warehouseSerialCache;
    if (!forceRefresh && cache != null && !cache.isExpired) return cache.value;

    final inFlight = _warehouseSerialInFlight;
    if (inFlight != null) return inFlight;

    final request = _fetchWarehouseSerialNumbersFromErp();
    _warehouseSerialInFlight = request;
    return request
        .then((rows) {
          _warehouseSerialCache = _CacheEntry(rows, _trackingCacheTtl);
          return rows;
        })
        .whenComplete(() {
          if (identical(_warehouseSerialInFlight, request)) {
            _warehouseSerialInFlight = null;
          }
        });
  }

  Future<List<QualityInspectionRecord>> fetchQualityInspections({
    int periodDays = 30,
    bool forceRefresh = false,
  }) {
    return _fetchCachedQualityInspections(
      key: 'all:$periodDays',
      periodDays: periodDays,
      forceRefresh: forceRefresh,
      filtersBuilder: (from) => [
        ['report_date', '>=', DateRangePresets.toFrappeDate(from)],
      ],
    );
  }

  Future<List<QualityInspectionRecord>> fetchQualityInspectionsForApproval({
    int periodDays = 30,
    bool forceRefresh = false,
  }) {
    return _fetchCachedQualityInspections(
      key: 'approval:$periodDays',
      periodDays: periodDays,
      forceRefresh: forceRefresh,
      filtersBuilder: (from) => [
        ['docstatus', '=', 0],
        ['report_date', '>=', DateRangePresets.toFrappeDate(from)],
      ],
    );
  }

  Future<List<QualityInspectionRecord>> fetchIncomingQualityInspections({
    int periodDays = 30,
    bool forceRefresh = false,
  }) {
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

  Future<List<QualityInspectionRecord>> fetchProductionQualityInspections({
    int periodDays = 30,
    bool forceRefresh = false,
  }) {
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

  Future<List<QualityInspectionRecord>> fetchRejectedQualityInspections({
    int periodDays = 30,
    bool forceRefresh = false,
  }) {
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

  Future<void> uploadAttachment({
    required String doctype,
    required String documentName,
    required String filePath,
  }) async {
    await appState.frappeService.uploadFile(
      doctype: doctype,
      documentName: documentName,
      filePath: filePath,
    );
  }

  Future<void> submitDocument(String doctype, String name) async {
    await appState.frappeService.submitDocument(doctype, name);
    if (doctype == 'Stock Entry') {
      await refreshStockEntries();
    } else if (doctype == 'Stock Reconciliation') {
      await refreshStockReconciliations();
    }
  }

  Future<List<WarehouseBatchRecord>> _fetchWarehouseBatchesFromErp() async {
    await appState.frappeService.ensureLoggedIn();
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

  Future<List<WarehouseSerialRecord>>
  _fetchWarehouseSerialNumbersFromErp() async {
    await appState.frappeService.ensureLoggedIn();
    final rows = await _fetchAllResourcePages(
      doctype: 'Serial No',
      fields: const ['name', 'item_code', 'warehouse', 'status', 'batch_no'],
      filters: _warehouseScopeFilters(),
      orderBy: 'modified desc',
      maxRows: 1000,
    );
    return rows.map(WarehouseSerialRecord.fromJson).toList();
  }

  Future<List<QualityInspectionRecord>> _fetchCachedQualityInspections({
    required String key,
    required int periodDays,
    required bool forceRefresh,
    required List<List<dynamic>> Function(DateTime from) filtersBuilder,
  }) async {
    final cacheKey = [
      appState.selectedSiteBaseUrl.trim(),
      appState.currentUser?.trim() ?? '',
      key,
    ].join('|');
    final cached = _qualityInspectionCache[cacheKey];
    if (!forceRefresh && cached != null && !cached.isExpired) {
      return cached.value;
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
      _qualityInspectionCache[cacheKey] = _CacheEntry(
        rows,
        _qualityInspectionCacheTtl,
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
    await appState.frappeService.ensureLoggedIn();
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

  List<String> erpWarehouseNamesForCompany(String company) {
    final names = _warehouses
        .where((warehouse) => warehouse.company == company)
        .map((warehouse) => warehouse.name)
        .where((name) => name.isNotEmpty)
        .toList();
    names.sort(_compareWarehouseNames);
    return names;
  }

  List<String> _groupsFromInventory() {
    return _inventory
        .map((item) => item.category?.trim() ?? '')
        .where((group) => group.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<List<dynamic>>? _inventoryScopeFiltersForCurrentRole() {
    final bootFilters = _warehouseScopeFilters();
    if (bootFilters != null) return bootFilters;
    if (!appState.mobileAccess.shouldScopeSalesData) return null;
    final names = _inventoryScopeWarehouseNames();
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

  List<String> _inventoryScopeWarehouseNames() {
    final bootWarehouseNames = (appState.mobileBoot?.warehouses ?? const [])
        .map((warehouse) => warehouse.trim())
        .where((warehouse) => warehouse.isNotEmpty)
        .toSet()
        .toList();
    if (bootWarehouseNames.isNotEmpty) {
      bootWarehouseNames.sort(_compareWarehouseNames);
      return bootWarehouseNames;
    }

    if (!appState.mobileAccess.shouldScopeSalesData) {
      final names = _warehouses.map((warehouse) => warehouse.name).toList();
      names.sort(_compareWarehouseNames);
      return names;
    }

    final employeeCompany =
        appState.currentEmployeeProfile['company']?.toString().trim() ?? '';
    final names = employeeCompany.isEmpty
        ? _warehouses.map((warehouse) => warehouse.name).toList()
        : erpWarehouseNamesForCompany(employeeCompany);
    names.sort(_compareWarehouseNames);
    return names;
  }

  List<List<dynamic>>? _warehouseScopeFilters() {
    final names =
        (appState.mobileBoot?.warehouses ?? const <String>[])
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

  List<List<dynamic>> _companyScopeFilters(String selectedCompany) {
    final selected = selectedCompany.trim();
    if (selected.isNotEmpty) {
      return [
        ['company', '=', selected],
      ];
    }

    final companies = (appState.mobileBoot?.companies ?? const <String>[])
        .map((company) => company.trim())
        .where((company) => company.isNotEmpty)
        .toSet()
        .toList();
    if (companies.isEmpty) return const [];
    if (companies.length == 1) {
      return [
        ['company', '=', companies.first],
      ];
    }
    return [
      ['company', 'in', companies],
    ];
  }

  Future<List<Map<String, dynamic>>> _fetchAllResourcePages({
    required String doctype,
    required List<String> fields,
    String? orderBy,
    List<List<dynamic>>? filters,
    required int? maxRows,
  }) {
    return walkFrappePages(
      pageSize: _pageSize,
      maxRows: maxRows,
      fetchPage: (start, limit) => _fetchResourceWithFieldFallback(
        doctype: doctype,
        fields: fields,
        limit: limit,
        limitStart: start,
        orderBy: orderBy,
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
  }) async {
    var remainingFields = List<String>.from(fields);
    var currentOrderBy = orderBy;

    while (remainingFields.isNotEmpty) {
      try {
        return await appState.frappeService.fetchResource(
          doctype,
          fields: remainingFields,
          limit: limit,
          limitStart: limitStart,
          orderBy: currentOrderBy,
          filters: filters,
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

  Future<Map<String, _WarehouseItemMeta>> _fetchItemMeta(
    Set<String> itemCodes,
  ) async {
    if (itemCodes.isEmpty) return const {};
    final result = <String, _WarehouseItemMeta>{};
    final codes = itemCodes.toList();
    const batchSize = 80;

    for (var start = 0; start < codes.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, codes.length);
      final batch = codes.sublist(start, end);
      List<Map<String, dynamic>> rows;
      try {
        rows = await _fetchResourceWithFieldFallback(
          doctype: 'Item',
          fields: const [
            'name',
            'item_code',
            'item_name',
            'item_group',
            'reorder_level',
          ],
          filters: [
            ['name', 'in', batch],
          ],
          limit: batch.length,
        );
      } catch (_) {
        rows = const [];
      }
      for (final row in rows) {
        final code = row['item_code']?.toString().trim().isNotEmpty == true
            ? row['item_code']!.toString().trim()
            : row['name']?.toString().trim() ?? '';
        if (code.isEmpty) continue;
        result[code] = _WarehouseItemMeta(
          itemName: row['item_name']?.toString(),
          itemGroup: row['item_group']?.toString(),
          reorderLevel: NumParse.asInt(row['reorder_level']),
        );
      }
    }
    return result;
  }

  int _compareWarehouseNames(String a, String b) {
    return a.toLowerCase().compareTo(b.toLowerCase());
  }
}

class _WarehouseItemMeta {
  final String? itemName;
  final String? itemGroup;
  final int reorderLevel;

  const _WarehouseItemMeta({
    this.itemName,
    this.itemGroup,
    required this.reorderLevel,
  });

  InventoryItem applyTo(InventoryItem item) {
    return item.copyWith(
      name: itemName?.trim().isNotEmpty == true ? itemName!.trim() : item.name,
      category: itemGroup?.trim().isNotEmpty == true
          ? itemGroup!.trim()
          : item.category,
      minStockThreshold: reorderLevel > 0
          ? reorderLevel
          : item.minStockThreshold,
    );
  }
}

class _CacheEntry<T> {
  final T value;
  final DateTime expiresAt;

  _CacheEntry(this.value, Duration ttl) : expiresAt = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
