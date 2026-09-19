import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/inventory_item.dart';
import '../../models/quality_inspection_record.dart';
import '../../models/stock_area_option.dart';
import '../../models/stock_entry.dart';
import '../../models/stock_ledger_movement.dart';
import '../../models/warehouse_info.dart';
import '../../models/warehouse_tracking_record.dart';
import '../../services/frappe_service.dart';
import '../../services/local_app_database.dart';
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
  static const int _inventoryPageSize = 50;
  static const int _inventorySnapshotLimit = 500;
  static const Duration _masterCacheTtl = Duration(hours: 12);
  static const String _warehouseCachePrefix = 'warehouse_master_cache';
  static const String _itemGroupCachePrefix = 'item_group_master_cache';

  List<WarehouseInfo> _warehouses = const [];
  List<InventoryItem> _inventory = const [];
  List<String> _itemGroups = const [];
  List<StockEntry> _stockEntries = const [];
  List<StockEntryType> _stockEntryTypes = const [];
  List<StockReconciliationSummary> _stockReconciliations = const [];
  bool _isInventoryLoading = false;
  bool _isMoreInventoryLoading = false;
  bool _hasMoreInventory = true;
  bool _isStockEntriesLoading = false;
  String? _inventoryError;
  String? _stockEntriesError;
  int _inventoryQueryVersion = 0;
  int _inventoryNextStart = 0;
  String? _inventoryCompanyFilter;
  String? _inventoryWarehouseFilter;
  String? _inventoryItemGroupFilter;
  String _inventorySearch = '';
  String _inventoryStatusFilter = 'all';
  String _inventorySort = 'urgent_first';
  Map<String, _WarehouseItemMeta> _inventorySearchItemMeta = const {};
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
    appState.currentUser,
  ];

  List<WarehouseInfo> get warehouses => _warehouses;
  List<InventoryItem> get inventory => _inventory;
  List<String> get itemGroups => _itemGroups;
  List<StockEntry> get stockEntries => _stockEntries;
  List<StockEntryType> get stockEntryTypes => _stockEntryTypes;
  List<StockReconciliationSummary> get stockReconciliations =>
      _stockReconciliations;
  bool get isInventoryLoading => _isInventoryLoading;
  bool get isMoreInventoryLoading => _isMoreInventoryLoading;
  bool get hasMoreInventory => _hasMoreInventory;
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

  Future<bool> canWriteDoctype(String doctype) {
    return appState.canWriteDoctype(doctype);
  }

  Future<bool> canSubmitDoctype(String doctype) {
    return appState.canSubmitDoctype(doctype);
  }

  Future<bool> canPrintDoctype(String doctype) {
    return appState.canPrintDoctype(doctype);
  }

  Future<List<int>> downloadStockEntryPdf(String name) {
    return appState.frappeService.downloadPrintPdf(
      doctype: 'Stock Entry',
      name: name,
    );
  }

  @override
  void handleWatchedFieldsChanged(List<Object?> previous, List<Object?> next) {
    if (didAuthScopeChange(
      previous,
      next,
      authIndex: 0,
      siteIndex: 4,
      userIndex: 5,
    )) {
      _resetLocalStockData();
    }
  }

  void _resetLocalStockData() {
    _warehouses = const [];
    _inventory = const [];
    _itemGroups = const [];
    _stockEntries = const [];
    _stockReconciliations = const [];
    _isInventoryLoading = false;
    _isMoreInventoryLoading = false;
    _hasMoreInventory = true;
    _isStockEntriesLoading = false;
    _inventoryError = null;
    _stockEntriesError = null;
    _inventoryQueryVersion++;
    _inventoryNextStart = 0;
    _inventorySearchItemMeta = const {};
    _warehousesFetchInFlight = null;
    _inventoryFetchInFlight = null;
    _warehouseBatchInFlight = null;
    _warehouseSerialInFlight = null;
    _qualityInspectionInFlight.clear();
    _warehouseBatchCache = null;
    _warehouseSerialCache = null;
    _qualityInspectionCache.clear();
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

    final cacheKey = _cacheKey(_warehouseCachePrefix);
    if (_warehouses.isEmpty) {
      final cachedRows = await _readCachedRows(cacheKey);
      if (cachedRows != null) {
        _warehouses = cachedRows
            .map(WarehouseInfo.fromJson)
            .where((row) => row.name.isNotEmpty && !row.isGroup)
            .toList();
        notifyListeners();
      }
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
      await _writeCachedRows(
        cacheKey,
        _warehouses.map(_warehouseToJson).toList(),
      );
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

    final cacheKey = _cacheKey(_itemGroupCachePrefix);
    if (_itemGroups.isEmpty) {
      final cachedRows = await _readCachedRows(cacheKey);
      if (cachedRows != null) {
        _itemGroups =
            cachedRows
                .map((row) => row['name']?.toString().trim() ?? '')
                .where((group) => group.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        notifyListeners();
      }
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
      await _writeCachedRows(
        cacheKey,
        _itemGroups.map((name) => {'name': name}).toList(),
      );
    } catch (_) {
      final fallback = _groupsFromInventory();
      if (fallback.isNotEmpty) _itemGroups = fallback;
    } finally {
      notifyListeners();
    }
  }

  String _cacheKey(String prefix) {
    return [
      prefix,
      appState.selectedSiteBaseUrl.trim(),
      appState.currentUser?.trim() ?? '',
    ].join('|');
  }

  Future<List<Map<String, dynamic>>?> _readCachedRows(String key) async {
    final json = await LocalAppDatabase.instance.readJson(key);
    final rows = json?['rows'];
    if (rows is! List) return null;
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _writeCachedRows(String key, List<Map<String, dynamic>> rows) {
    return LocalAppDatabase.instance.writeJson(key, {
      'rows': rows,
    }, ttl: _masterCacheTtl);
  }

  Map<String, dynamic> _warehouseToJson(WarehouseInfo warehouse) {
    return {
      'name': warehouse.name,
      'warehouse_name': warehouse.displayName,
      'company': warehouse.company,
      if (warehouse.parentWarehouse != null)
        'parent_warehouse': warehouse.parentWarehouse,
      'is_group': warehouse.isGroup ? 1 : 0,
      'disabled': warehouse.isDisabled == true ? 1 : 0,
    };
  }

  Future<void> refreshInventory() {
    return setInventoryQuery();
  }

  Future<void> refreshInventoryForCompany(String company) async {
    return setInventoryQuery(company: company);
  }

  Future<List<InventoryItem>> fetchInventorySnapshot({
    int maxRows = _inventorySnapshotLimit,
    List<List<dynamic>>? filters,
    String? orderBy,
  }) async {
    if (appState.isSampleMode) return appState.inventory;

    await appState.frappeService.ensureLoggedIn();
    if (_warehouses.isEmpty) {
      await refreshWarehouses();
    }

    final rows = await _fetchInventoryRows(
      filters: filters ?? _inventoryScopeFiltersForCurrentRole(),
      limit: maxRows,
      limitStart: 0,
      orderBy: orderBy ?? 'modified desc',
    );
    return _inventoryItemsFromRows(rows);
  }

  Future<void> setInventoryQuery({
    String? company,
    String? warehouse,
    String? itemGroup,
    String? search,
    String? status,
    String? sort,
  }) async {
    _inventoryCompanyFilter = company?.trim().isEmpty == true
        ? null
        : company?.trim();
    _inventoryWarehouseFilter = warehouse?.trim().isEmpty == true
        ? null
        : warehouse?.trim();
    _inventoryItemGroupFilter = itemGroup?.trim().isEmpty == true
        ? null
        : itemGroup?.trim();
    _inventorySearch = search?.trim() ?? '';
    _inventoryStatusFilter = status?.trim().isEmpty == true
        ? 'all'
        : status?.trim() ?? 'all';
    _inventorySort = sort?.trim().isEmpty == true
        ? 'urgent_first'
        : sort?.trim() ?? 'urgent_first';
    _inventoryFetchInFlight = null;
    await _refreshInventoryPage(reset: true);
  }

  Future<void> loadMoreInventory() async {
    if (_isInventoryLoading || _isMoreInventoryLoading || !_hasMoreInventory) {
      return;
    }
    await _refreshInventoryPage(reset: false);
  }

  Future<void> _refreshInventoryPage({required bool reset}) {
    final canReuseInFlight = reset;
    final inFlight = _inventoryFetchInFlight;
    if (canReuseInFlight && inFlight != null) return inFlight;
    final request = _fetchInventoryPage(reset: reset);
    if (canReuseInFlight) _inventoryFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_inventoryFetchInFlight, request)) {
        _inventoryFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchInventoryPage({required bool reset}) async {
    if (appState.isSampleMode) {
      _inventory = appState.inventory;
      _inventoryError = null;
      notifyListeners();
      return;
    }

    final version = reset ? ++_inventoryQueryVersion : _inventoryQueryVersion;
    if (reset) {
      _isInventoryLoading = true;
      _inventoryError = null;
      _hasMoreInventory = true;
      _isMoreInventoryLoading = false;
      _inventoryNextStart = 0;
    } else {
      _isMoreInventoryLoading = true;
    }
    notifyListeners();

    try {
      await appState.frappeService.ensureLoggedIn();
      if (_warehouses.isEmpty) await refreshWarehouses();

      final result = await _fetchInventoryResultPage(
        limitStart: reset ? 0 : _inventoryNextStart,
      );
      if (version != _inventoryQueryVersion) return;

      final nextItems = _applyInventoryClientFilters(result.items);
      if (reset) {
        _inventory = nextItems;
      } else {
        final keys = _inventory
            .map((item) => '${item.sku}|${item.warehouseId}')
            .toSet();
        _inventory = [
          ..._inventory,
          ...nextItems.where(
            (item) => keys.add('${item.sku}|${item.warehouseId}'),
          ),
        ];
      }
      _inventoryNextStart += result.rawCount;
      _hasMoreInventory = result.rawCount >= _inventoryPageSize;
      _inventoryError = null;
      if (_itemGroups.isEmpty) _itemGroups = _groupsFromInventory();
    } catch (error) {
      if (version != _inventoryQueryVersion) return;
      _inventoryError = error.toString();
      if (!reset) _hasMoreInventory = false;
    } finally {
      if (version == _inventoryQueryVersion) {
        _isInventoryLoading = false;
        _isMoreInventoryLoading = false;
        notifyListeners();
      }
    }
  }

  Future<({List<InventoryItem> items, int rawCount})>
  _fetchInventoryResultPage({required int limitStart}) async {
    if (_warehouses.isEmpty) await refreshWarehouses();
    final filters = <List<dynamic>>[...?_inventoryServerFilters()];
    final itemCodes = await _inventoryItemCodeFilters();
    if (itemCodes != null) {
      if (itemCodes.isEmpty) {
        return (items: <InventoryItem>[], rawCount: 0);
      }
      filters.add(['item_code', 'in', itemCodes]);
    }

    final rows = await _fetchInventoryRows(
      filters: filters.isEmpty ? null : filters,
      limit: _inventoryPageSize,
      limitStart: limitStart,
      orderBy: _inventoryOrderBy(),
    );
    final items = await _inventoryItemsFromRows(rows);
    return (items: items, rawCount: rows.length);
  }

  Future<List<Map<String, dynamic>>> _fetchInventoryRows({
    required int limit,
    int limitStart = 0,
    String? orderBy,
    List<List<dynamic>>? filters,
  }) async {
    try {
      return await _fetchResourceWithFieldFallback(
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
        limit: limit,
        limitStart: limitStart,
        orderBy: orderBy,
      );
    } catch (_) {
      return _fetchResourceWithFieldFallback(
        doctype: 'Bin',
        fields: const ['item_code', 'warehouse', 'actual_qty'],
        filters: filters,
        limit: limit,
        limitStart: limitStart,
        orderBy: orderBy,
      );
    }
  }

  Future<List<InventoryItem>> _inventoryItemsFromRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final items = <InventoryItem>[];
    for (final row in rows) {
      final warehouse = row['warehouse']?.toString() ?? '';
      if (warehouse.isEmpty) continue;
      items.add(InventoryItem.fromJson(row).copyWith(warehouseId: warehouse));
    }

    final fetchedItemMeta = await _fetchItemMeta(
      items.map((item) => item.sku).where((sku) => sku.isNotEmpty).toSet(),
    );
    final itemMeta = {...fetchedItemMeta, ..._inventorySearchItemMeta};
    return [
      for (final item in items)
        (itemMeta[item.sku]?.applyTo(item) ?? item).withRecalculatedStatus(),
    ];
  }

  List<List<dynamic>>? _inventoryServerFilters() {
    final warehouse = _inventoryWarehouseFilter;
    if (warehouse != null && warehouse.isNotEmpty) {
      return [
        ['warehouse', '=', warehouse],
      ];
    }

    final company = _inventoryCompanyFilter;
    if (company != null && company.isNotEmpty) {
      final names = erpWarehouseNamesForCompany(company);
      if (names.isEmpty) {
        return [
          ['warehouse', '=', '__no_matching_warehouse__'],
        ];
      }
      if (names.length == 1) {
        return [
          ['warehouse', '=', names.first],
        ];
      }
      return [
        ['warehouse', 'in', names],
      ];
    }

    return _inventoryScopeFiltersForCurrentRole();
  }

  Future<List<String>?> _inventoryItemCodeFilters() async {
    final query = _inventorySearch.trim();
    final group = _inventoryItemGroupFilter?.trim() ?? '';
    if (query.isEmpty && group.isEmpty) {
      _inventorySearchItemMeta = const {};
      return null;
    }

    final filters = <List<dynamic>>[];
    if (group.isNotEmpty) filters.add(['item_group', '=', group]);

    final rows = await _fetchResourceWithFieldFallback(
      doctype: 'Item',
      fields: const ['name', 'item_code', 'item_name', 'item_group'],
      filters: filters.isEmpty ? null : filters,
      limit: _listLimit,
      orderBy: 'name asc',
      orFilters: query.isEmpty
          ? null
          : [
              ['name', 'like', '%$query%'],
              ['item_code', 'like', '%$query%'],
              ['item_name', 'like', '%$query%'],
            ],
    );
    _inventorySearchItemMeta = {
      for (final row in rows)
        if (_itemCodeFromMetaRow(row).isNotEmpty)
          _itemCodeFromMetaRow(row): _WarehouseItemMeta(
            itemName: row['item_name']?.toString(),
            itemGroup: row['item_group']?.toString(),
            reorderLevel: NumParse.asInt(row['reorder_level']),
          ),
    };

    return rows
        .map((row) {
          return _itemCodeFromMetaRow(row);
        })
        .where((code) => code.isNotEmpty)
        .toSet()
        .toList();
  }

  String _itemCodeFromMetaRow(Map<String, dynamic> row) {
    final itemCode = row['item_code']?.toString().trim() ?? '';
    if (itemCode.isNotEmpty) return itemCode;
    return row['name']?.toString().trim() ?? '';
  }

  List<InventoryItem> _applyInventoryClientFilters(List<InventoryItem> items) {
    final status = _inventoryStatusFilter;
    final filtered = status == 'all'
        ? List<InventoryItem>.from(items)
        : items.where((item) {
            return switch (status) {
              'urgent' => item.status == StockStatus.urgent,
              'low_stock' => item.status == StockStatus.lowStock,
              'in_stock' => item.status == StockStatus.inStock,
              _ => true,
            };
          }).toList();
    filtered.sort((a, b) {
      return switch (_inventorySort) {
        'quantity_low' => a.quantity.compareTo(b.quantity),
        'quantity_high' => b.quantity.compareTo(a.quantity),
        'name' => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        _ => _inventoryStatusRank(
          a.status,
        ).compareTo(_inventoryStatusRank(b.status)),
      };
    });
    return filtered;
  }

  int _inventoryStatusRank(StockStatus status) {
    return switch (status) {
      StockStatus.urgent => 0,
      StockStatus.lowStock => 1,
      StockStatus.inStock => 2,
    };
  }

  String? _inventoryOrderBy() {
    return switch (_inventorySort) {
      'quantity_low' => 'actual_qty asc, item_code asc',
      'quantity_high' => 'actual_qty desc, item_code asc',
      'name' => 'item_code asc',
      _ => 'actual_qty asc, item_code asc',
    };
  }

  Future<void> refreshStockEntries({
    String? stockEntryType,
    String? company,
    String? fromWarehouse,
    String? toWarehouse,
    String? name,
  }) async {
    _isStockEntriesLoading = true;
    _stockEntriesError = null;
    notifyListeners();

    final filters = _stockEntryListFilters(
      stockEntryType: stockEntryType,
      company: company,
      fromWarehouse: fromWarehouse,
      toWarehouse: toWarehouse,
      name: name,
    );

    try {
      await appState.frappeService.ensureLoggedIn();
      List<Map<String, dynamic>> rows;
      try {
        rows = await _fetchAllResourcePages(
          doctype: 'Stock Entry',
          fields: const [
            'name',
            'stock_entry_type',
            'company',
            'docstatus',
            'posting_date',
            'posting_time',
            'total_qty',
            'from_warehouse',
            'to_warehouse',
          ],
          orderBy: 'posting_date desc, posting_time desc',
          filters: filters,
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
              'company',
              'docstatus',
              'posting_date',
              'posting_time',
              'from_warehouse',
              'to_warehouse',
            ],
            limit: limit,
            limitStart: start,
            orderBy: 'posting_date desc, posting_time desc',
            filters: filters,
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

  List<List<dynamic>> _stockEntryListFilters({
    String? stockEntryType,
    String? company,
    String? fromWarehouse,
    String? toWarehouse,
    String? name,
  }) {
    final filters = <List<dynamic>>[];
    final type = stockEntryType?.trim() ?? '';
    if (type.isNotEmpty) {
      filters.add(['stock_entry_type', '=', type]);
    }
    final selectedCompany = company?.trim() ?? '';
    if (selectedCompany.isNotEmpty) {
      filters.add(['company', '=', selectedCompany]);
    } else {
      filters.addAll(_companyScopeFilters(''));
    }
    final source = fromWarehouse?.trim() ?? '';
    if (source.isNotEmpty) {
      filters.add(['from_warehouse', '=', source]);
    }
    final target = toWarehouse?.trim() ?? '';
    if (target.isNotEmpty) {
      filters.add(['to_warehouse', '=', target]);
    }
    final query = name?.trim() ?? '';
    if (query.isNotEmpty) {
      filters.add(['name', 'like', '%$query%']);
    }
    return filters;
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

  Future<List<StockEntryType>> fetchStockEntryTypes({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _stockEntryTypes.isNotEmpty) {
      return _stockEntryTypes;
    }
    await appState.frappeService.ensureLoggedIn();
    final rows = await _fetchAllResourcePages(
      doctype: 'Stock Entry Type',
      fields: const ['name', 'purpose'],
      orderBy: 'name asc',
      maxRows: 200,
    );
    final types = rows
        .map(StockEntryType.fromJson)
        .where((row) => row.name.isNotEmpty)
        .toList(growable: false);
    _stockEntryTypes = types;
    notifyListeners();
    return types;
  }

  Future<Map<String, dynamic>> fetchStockEntryItemDetails({
    required String itemCode,
    String? company,
    String? sourceWarehouse,
    String? targetWarehouse,
    DateTime? postingDate,
    double qty = 1,
  }) async {
    await appState.frappeService.ensureLoggedIn();
    final code = itemCode.trim();
    if (code.isEmpty) return const {};

    final selectedSource = (sourceWarehouse ?? '').trim();
    final selectedTarget = (targetWarehouse ?? '').trim();
    final warehouse = selectedSource.isNotEmpty
        ? selectedSource
        : selectedTarget;
    final args = <String, dynamic>{
      'item_code': code,
      'qty': qty,
      'transfer_qty': qty,
      'conversion_factor': 1,
      'doctype': 'Stock Entry',
      'posting_date': DateRangePresets.toFrappeDate(
        postingDate ?? DateTime.now(),
      ),
      if ((company ?? '').trim().isNotEmpty) 'company': company!.trim(),
      if (selectedSource.isNotEmpty) 's_warehouse': selectedSource,
      if (selectedTarget.isNotEmpty) 't_warehouse': selectedTarget,
      if (warehouse.isNotEmpty) 'warehouse': warehouse,
    };

    try {
      final result = await appState.frappeService.callMethod(
        'erpnext.stock.doctype.stock_entry.stock_entry.get_item_details',
        args: {'args': jsonEncode(args)},
      );
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    } catch (_) {}

    try {
      final result = await appState.frappeService.callMethod(
        'erpnext.stock.utils.get_incoming_rate',
        args: {'args': jsonEncode(args)},
      );
      if (result is num) {
        return {'basic_rate': result};
      }
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    } catch (_) {}

    return _fetchStockEntryRateFallback(
      itemCode: code,
      company: company,
      warehouse: sourceWarehouse ?? targetWarehouse,
    );
  }

  Future<Map<String, dynamic>> _fetchStockEntryRateFallback({
    required String itemCode,
    String? company,
    String? warehouse,
  }) async {
    final binFilters = <List<dynamic>>[
      ['item_code', '=', itemCode],
    ];
    if ((warehouse ?? '').trim().isNotEmpty) {
      binFilters.add(['warehouse', '=', warehouse!.trim()]);
    } else if ((company ?? '').trim().isNotEmpty) {
      final names = erpWarehouseNamesForCompany(company!.trim());
      if (names.isNotEmpty) {
        binFilters.add(['warehouse', 'in', names]);
      }
    }

    try {
      final bins = await appState.frappeService.fetchResource(
        'Bin',
        fields: const ['valuation_rate', 'actual_qty', 'warehouse'],
        filters: binFilters,
        orderBy: 'modified desc',
        limit: 50,
      );
      Map<String, dynamic>? best;
      for (final row in bins) {
        final rate = NumParse.asDouble(row['valuation_rate']);
        final qty = NumParse.asDouble(row['actual_qty']);
        if (rate <= 0) continue;
        best = row;
        if (qty > 0) break;
      }
      if (best != null) {
        return {
          'basic_rate': NumParse.asDouble(best['valuation_rate']),
          'valuation_rate': NumParse.asDouble(best['valuation_rate']),
        };
      }
    } catch (_) {}

    try {
      final items = await appState.frappeService.fetchResource(
        'Item',
        fields: const [
          'item_name',
          'stock_uom',
          'valuation_rate',
          'standard_rate',
          'last_purchase_rate',
        ],
        filters: [
          ['name', '=', itemCode],
        ],
        limit: 1,
      );
      if (items.isNotEmpty) {
        final row = items.first;
        final rate = NumParse.asDouble(
          row['last_purchase_rate'] ??
              row['valuation_rate'] ??
              row['standard_rate'],
        );
        return {
          'item_name': row['item_name'],
          'uom': row['stock_uom'],
          'stock_uom': row['stock_uom'],
          'basic_rate': rate,
          'valuation_rate': rate,
        };
      }
    } catch (_) {}

    return const {};
  }

  Future<StockEntry> createStockEntry({
    required String stockEntryType,
    required List<Map<String, dynamic>> items,
    String? company,
    DateTime? postingDate,
    String? purpose,
    String? fromWarehouse,
    String? toWarehouse,
    String? namingSeries,
  }) async {
    await appState.frappeService.ensureLoggedIn();

    final payload = <String, dynamic>{
      'stock_entry_type': stockEntryType,
      'purpose': (purpose ?? stockEntryType).trim(),
      if (company?.trim().isNotEmpty == true) 'company': company!.trim(),
      'posting_date': DateRangePresets.toFrappeDate(
        postingDate ?? DateTime.now(),
      ),
      if (fromWarehouse?.trim().isNotEmpty == true)
        'from_warehouse': fromWarehouse!.trim(),
      if (toWarehouse?.trim().isNotEmpty == true)
        'to_warehouse': toWarehouse!.trim(),
      if (namingSeries?.trim().isNotEmpty == true)
        'naming_series': namingSeries!.trim(),
      'items': items,
    };
    final created = await appState.frappeService.createDocument(
      'Stock Entry',
      payload,
    );
    final entry = StockEntry.fromJson(created);
    _stockEntries = [entry, ..._stockEntries];
    notifyListeners();
    await refreshStockEntries();
    return entry;
  }

  Future<void> updateStockEntry({
    required String name,
    required String stockEntryType,
    required List<Map<String, dynamic>> items,
    String? company,
    DateTime? postingDate,
    String? purpose,
    String? fromWarehouse,
    String? toWarehouse,
  }) async {
    await appState.frappeService.ensureLoggedIn();
    final id = name.trim();
    if (id.isEmpty) {
      throw Exception('Stock Entry tidak valid.');
    }
    await appState.frappeService.updateDocument('Stock Entry', id, {
      'stock_entry_type': stockEntryType,
      'purpose': (purpose ?? stockEntryType).trim(),
      if (company?.trim().isNotEmpty == true) 'company': company!.trim(),
      'posting_date': DateRangePresets.toFrappeDate(
        postingDate ?? DateTime.now(),
      ),
      if (fromWarehouse?.trim().isNotEmpty == true)
        'from_warehouse': fromWarehouse!.trim()
      else
        'from_warehouse': '',
      if (toWarehouse?.trim().isNotEmpty == true)
        'to_warehouse': toWarehouse!.trim()
      else
        'to_warehouse': '',
      'items': items,
    });
    await refreshStockEntries();
  }

  Future<StockEntryDetail> fetchStockEntryDetail(String name) async {
    await appState.frappeService.ensureLoggedIn();
    final id = name.trim();
    if (id.isEmpty) {
      throw Exception('Stock Entry tidak valid.');
    }
    final doc = await appState.frappeService.fetchDocument('Stock Entry', id);
    return StockEntryDetail.fromJson(doc);
  }

  Future<Map<String, dynamic>> createStockReconciliation({
    required String company,
    required List<Map<String, dynamic>> items,
    String purpose = 'Stock Reconciliation',
    String? warehouse,
    String? expenseAccount,
    String? costCenter,
    DateTime? postingDate,
    String? postingTime,
    String? namingSeries,
  }) async {
    await appState.frappeService.ensureLoggedIn();
    if (company.trim().isEmpty) {
      throw Exception('Company wajib dipilih.');
    }
    if (items.isEmpty) {
      throw Exception('Tambahkan minimal satu item.');
    }

    final created = await appState.frappeService.createDocument(
      'Stock Reconciliation',
      {
        'company': company.trim(),
        'purpose': purpose.trim().isEmpty ? 'Stock Reconciliation' : purpose.trim(),
        if (namingSeries?.trim().isNotEmpty == true)
          'naming_series': namingSeries!.trim(),
        'posting_date': DateRangePresets.toFrappeDate(
          postingDate ?? DateTime.now(),
        ),
        if ((postingTime ?? '').trim().isNotEmpty)
          'posting_time': postingTime!.trim(),
        if (warehouse?.trim().isNotEmpty == true)
          'set_warehouse': warehouse!.trim(),
        if (expenseAccount?.trim().isNotEmpty == true)
          'expense_account': expenseAccount!.trim(),
        if (costCenter?.trim().isNotEmpty == true)
          'cost_center': costCenter!.trim(),
        'items': items,
      },
    );
    await refreshStockReconciliations(company: company);
    return created;
  }

  Future<void> refreshStockReconciliations({
    String? company,
    String? expenseAccount,
    String? costCenter,
    String? name,
  }) async {
    await appState.frappeService.ensureLoggedIn();
    final filters = <List<dynamic>>[];
    final selectedCompany = company?.trim() ?? '';
    if (selectedCompany.isNotEmpty) {
      filters.add(['company', '=', selectedCompany]);
    } else {
      filters.addAll(_companyScopeFilters(''));
    }
    if ((expenseAccount ?? '').trim().isNotEmpty) {
      filters.add(['expense_account', '=', expenseAccount!.trim()]);
    }
    if ((costCenter ?? '').trim().isNotEmpty) {
      filters.add(['cost_center', '=', costCenter!.trim()]);
    }
    if ((name ?? '').trim().isNotEmpty) {
      filters.add(['name', 'like', '%${name!.trim()}%']);
    }

    List<Map<String, dynamic>> rows;
    try {
      rows = await _fetchAllResourcePages(
        doctype: 'Stock Reconciliation',
        fields: const [
          'name',
          'company',
          'posting_date',
          'posting_time',
          'docstatus',
          'difference_amount',
          'expense_account',
          'cost_center',
        ],
        orderBy: 'posting_date desc, posting_time desc',
        filters: filters,
        maxRows: _listLimit,
      );
    } catch (_) {
      rows = await _fetchAllResourcePages(
        doctype: 'Stock Reconciliation',
        fields: const [
          'name',
          'company',
          'posting_date',
          'docstatus',
          'difference_amount',
        ],
        orderBy: 'posting_date desc, name desc',
        filters: filters
            .where(
              (filter) =>
                  filter.isNotEmpty &&
                  filter.first != 'expense_account' &&
                  filter.first != 'cost_center',
            )
            .toList(),
        maxRows: _listLimit,
      );
    }
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
    List<List<dynamic>>? orFilters,
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
      final rows = await _fetchItemMetaRows(batch);
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

  Future<List<Map<String, dynamic>>> _fetchItemMetaRows(
    List<String> batch,
  ) async {
    const baseFields = ['name', 'item_code', 'item_name', 'item_group'];
    const extendedFields = [...baseFields, 'reorder_level'];

    for (final fieldSet in const [extendedFields, baseFields]) {
      for (final keyField in const ['item_code', 'name']) {
        try {
          return await _fetchResourceWithFieldFallback(
            doctype: 'Item',
            fields: fieldSet,
            filters: [
              [keyField, 'in', batch],
            ],
            limit: batch.length,
          );
        } catch (_) {
          continue;
        }
      }
    }
    return const [];
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
