import 'package:flutter/foundation.dart';

import '../../models/stock_ledger_movement.dart';
import '../../models/warehouse_info.dart';
import '../../services/local_app_database.dart';
import '../../utils/date_range_presets.dart';
import 'warehouse_stock_state.dart';

class WarehouseAgingState extends ChangeNotifier {
  WarehouseAgingState({required WarehouseStockState stockState}) {
    _stockState = stockState;
    _stockState.addListener(notifyListeners);
  }

  static const _cachePrefix = 'warehouse_stock_report';
  static const _cacheTtl = Duration(hours: 12);

  late WarehouseStockState _stockState;
  List<StockAgingItem>? _agingCache;
  Future<List<StockAgingItem>>? _inFlight;
  String? _loadedCacheKey;

  void updateStockState(WarehouseStockState value) {
    if (identical(_stockState, value)) return;
    _stockState.removeListener(notifyListeners);
    _stockState = value;
    _stockState.addListener(notifyListeners);
    notifyListeners();
  }

  List<WarehouseInfo> get warehouses => _stockState.warehouses;
  List<StockAgingItem> get items => _agingCache ?? const [];
  bool get hasLoaded => _agingCache != null;

  Future<void> refreshWarehouses() => _stockState.refreshWarehouses();

  Future<List<StockAgingItem>> fetchStockAging({
    int lookbackDays = 365,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _cacheKey('aging', '$lookbackDays');
    if (!forceRefresh) {
      if (_agingCache != null && _loadedCacheKey == cacheKey) {
        return _agingCache!;
      }
      final cached = await _readCachedAging(cacheKey);
      if (cached != null) {
        _agingCache = cached;
        _loadedCacheKey = cacheKey;
        notifyListeners();
        return cached;
      }
    }

    final running = _inFlight;
    if (running != null) return running;
    final request = _fetchStockAgingFromErp(
      lookbackDays: lookbackDays,
      cacheKey: cacheKey,
    );
    _inFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_inFlight, request)) _inFlight = null;
    }
  }

  Future<List<StockAgingItem>> _fetchStockAgingFromErp({
    required int lookbackDays,
    required String cacheKey,
  }) async {
    final inventory = await _stockState.fetchInventorySnapshot();
    final today = DateTime.now();
    final from = today.subtract(Duration(days: lookbackDays));
    final stockKeys = {
      for (final item in inventory)
        if (item.quantity > 0) '${item.sku}|${item.warehouseId}',
    };
    final ledgerRows = await _stockState.fetchStockLedgerRows(
      filters: [
        ['posting_date', '>=', DateRangePresets.toFrappeDate(from)],
        ['actual_qty', '>', 0],
        ...?_warehouseScopeFilters(),
      ],
      stopWhenKeysComplete: stockKeys,
    );

    final latestIncoming = <String, DateTime>{};
    for (final row in ledgerRows) {
      final item = row['item_code']?.toString() ?? '';
      final warehouse = row['warehouse']?.toString() ?? '';
      final date = DateTime.tryParse(row['posting_date']?.toString() ?? '');
      if (item.isEmpty || warehouse.isEmpty || date == null) continue;
      latestIncoming.putIfAbsent('$item|$warehouse', () => date);
    }

    final items = [
      for (final item in inventory)
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
    _agingCache = items;
    _loadedCacheKey = cacheKey;
    await _writeCachedAging(cacheKey, items);
    notifyListeners();
    return items;
  }

  String _cacheKey(String report, String parameter) {
    final warehouses =
        (_stockState.appState.mobileBoot?.warehouses ?? const <String>[])
            .map((warehouse) => warehouse.trim())
            .where((warehouse) => warehouse.isNotEmpty)
            .toList()
          ..sort();
    return [
      _cachePrefix,
      _stockState.appState.selectedSiteBaseUrl.trim(),
      _stockState.appState.currentUser?.trim() ?? '',
      report,
      parameter,
      warehouses.join(','),
    ].join('|');
  }

  Future<List<StockAgingItem>?> _readCachedAging(String cacheKey) async {
    final json = await LocalAppDatabase.instance.readJson(cacheKey);
    final rows = json?['rows'];
    if (rows is! List) return null;
    return rows
        .whereType<Map>()
        .map((row) => StockAgingItem.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> _writeCachedAging(
    String cacheKey,
    List<StockAgingItem> items,
  ) async {
    await LocalAppDatabase.instance.writeJson(cacheKey, {
      'rows': items.map((item) => item.toJson()).toList(),
    }, ttl: _cacheTtl);
  }

  @override
  void dispose() {
    _stockState.removeListener(notifyListeners);
    super.dispose();
  }

  List<List<dynamic>>? _warehouseScopeFilters() {
    final names =
        (_stockState.appState.mobileBoot?.warehouses ?? const [])
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
}
