import 'package:flutter/foundation.dart';

import '../../models/stock_ledger_movement.dart';
import '../../models/warehouse_info.dart';
import '../../services/local_app_database.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/num_parse.dart';
import 'warehouse_stock_state.dart';

class WarehouseDeadStockState extends ChangeNotifier {
  WarehouseDeadStockState({required WarehouseStockState stockState}) {
    _stockState = stockState;
    _stockState.addListener(notifyListeners);
  }

  static const _cachePrefix = 'warehouse_stock_report';
  static const _cacheTtl = Duration(hours: 12);

  late WarehouseStockState _stockState;
  List<DeadStockItem>? _deadStockCache;
  List<StockMovementVelocityItem>? _velocityCache;
  int? _velocityPeriodDays;
  String? _loadedDeadStockKey;
  String? _loadedVelocityKey;
  Future<List<DeadStockItem>>? _deadStockInFlight;
  Future<List<StockMovementVelocityItem>>? _velocityInFlight;

  void updateStockState(WarehouseStockState value) {
    if (identical(_stockState, value)) return;
    _stockState.removeListener(notifyListeners);
    _stockState = value;
    _stockState.addListener(notifyListeners);
    notifyListeners();
  }

  List<WarehouseInfo> get warehouses => _stockState.warehouses;
  List<DeadStockItem> get deadStockItems => _deadStockCache ?? const [];
  List<StockMovementVelocityItem> get velocityItems =>
      _velocityCache ?? const [];
  bool get hasDeadStockLoaded => _deadStockCache != null;
  bool get hasVelocityLoaded => _velocityCache != null;

  Future<void> refreshWarehouses() => _stockState.refreshWarehouses();

  Future<List<DeadStockItem>> fetchDeadStock({
    int lookbackDays = 365,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _cacheKey('dead', '$lookbackDays');
    if (!forceRefresh) {
      if (_deadStockCache != null && _loadedDeadStockKey == cacheKey) {
        return _deadStockCache!;
      }
      final cached = await _readCachedDeadStock(cacheKey);
      if (cached != null) {
        _deadStockCache = cached;
        _loadedDeadStockKey = cacheKey;
        notifyListeners();
        return cached;
      }
    }

    final running = _deadStockInFlight;
    if (running != null) return running;
    final request = _fetchDeadStockFromErp(
      lookbackDays: lookbackDays,
      cacheKey: cacheKey,
    );
    _deadStockInFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_deadStockInFlight, request)) _deadStockInFlight = null;
    }
  }

  Future<List<StockMovementVelocityItem>> fetchStockMovementVelocity({
    int periodDays = 30,
    bool forceRefresh = false,
  }) async {
    final cacheKey = _cacheKey('velocity', '$periodDays');
    if (!forceRefresh) {
      if (_velocityCache != null &&
          _velocityPeriodDays == periodDays &&
          _loadedVelocityKey == cacheKey) {
        return _velocityCache!;
      }
      final cached = await _readCachedVelocity(cacheKey);
      if (cached != null) {
        _velocityCache = cached;
        _velocityPeriodDays = periodDays;
        _loadedVelocityKey = cacheKey;
        notifyListeners();
        return cached;
      }
    }

    final running = _velocityInFlight;
    if (running != null) return running;
    final request = _fetchVelocityFromErp(
      periodDays: periodDays,
      cacheKey: cacheKey,
    );
    _velocityInFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_velocityInFlight, request)) _velocityInFlight = null;
    }
  }

  Future<List<DeadStockItem>> _fetchDeadStockFromErp({
    required int lookbackDays,
    required String cacheKey,
  }) async {
    final inventory = await _stockState.fetchInventorySnapshot();
    final latestMovement = await _latestMovementDates(
      lookbackDays,
      inventoryKeys: {
        for (final item in inventory)
          if (item.quantity > 0) '${item.sku}|${item.warehouseId}',
      },
    );
    final today = DateTime.now();
    final rows = [
      for (final item in inventory)
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
    _deadStockCache = rows;
    _loadedDeadStockKey = cacheKey;
    await _writeCachedDeadStock(cacheKey, rows);
    notifyListeners();
    return rows;
  }

  Future<List<StockMovementVelocityItem>> _fetchVelocityFromErp({
    required int periodDays,
    required String cacheKey,
  }) async {
    final inventory = await _stockState.fetchInventorySnapshot();
    final today = DateTime.now();
    final from = today.subtract(Duration(days: periodDays));
    final rows = await _stockState.fetchStockLedgerRows(
      filters: [
        ['posting_date', '>=', DateRangePresets.toFrappeDate(from)],
        ['actual_qty', '<', 0],
        ...?_warehouseScopeFilters(),
      ],
    );

    final outgoingByStockKey = <String, int>{};
    for (final row in rows) {
      final item = row['item_code']?.toString() ?? '';
      final warehouse = row['warehouse']?.toString() ?? '';
      if (item.isEmpty || warehouse.isEmpty) continue;
      final key = '$item|$warehouse';
      outgoingByStockKey[key] =
          (outgoingByStockKey[key] ?? 0) +
          NumParse.asDouble(row['actual_qty']).abs().round();
    }

    final items = [
      for (final item in inventory)
        if (item.quantity > 0)
          StockMovementVelocityItem(
            itemCode: item.sku,
            itemName: item.name,
            warehouse: item.warehouseId,
            currentQuantity: item.quantity,
            outgoingQuantity:
                (outgoingByStockKey['${item.sku}|${item.warehouseId}'] ?? 0)
                    .toDouble(),
            transactionCount:
                outgoingByStockKey.containsKey(
                  '${item.sku}|${item.warehouseId}',
                )
                ? 1
                : 0,
          ),
    ];
    _velocityCache = items;
    _velocityPeriodDays = periodDays;
    _loadedVelocityKey = cacheKey;
    await _writeCachedVelocity(cacheKey, items);
    notifyListeners();
    return items;
  }

  Future<Map<String, DateTime>> _latestMovementDates(
    int lookbackDays, {
    required Set<String> inventoryKeys,
  }) async {
    final today = DateTime.now();
    final from = today.subtract(Duration(days: lookbackDays));
    final rows = await _stockState.fetchStockLedgerRows(
      filters: [
        ['posting_date', '>=', DateRangePresets.toFrappeDate(from)],
        ...?_warehouseScopeFilters(),
      ],
      stopWhenKeysComplete: inventoryKeys,
    );

    final latestMovement = <String, DateTime>{};
    for (final row in rows) {
      final item = row['item_code']?.toString() ?? '';
      final warehouse = row['warehouse']?.toString() ?? '';
      final date = DateTime.tryParse(row['posting_date']?.toString() ?? '');
      if (item.isEmpty || warehouse.isEmpty || date == null) continue;
      latestMovement.putIfAbsent('$item|$warehouse', () => date);
    }
    return latestMovement;
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

  Future<List<DeadStockItem>?> _readCachedDeadStock(String cacheKey) async {
    final json = await LocalAppDatabase.instance.readJson(cacheKey);
    final rows = json?['rows'];
    if (rows is! List) return null;
    return rows
        .whereType<Map>()
        .map((row) => DeadStockItem.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<void> _writeCachedDeadStock(
    String cacheKey,
    List<DeadStockItem> items,
  ) async {
    await LocalAppDatabase.instance.writeJson(cacheKey, {
      'rows': items.map((item) => item.toJson()).toList(),
    }, ttl: _cacheTtl);
  }

  Future<List<StockMovementVelocityItem>?> _readCachedVelocity(
    String cacheKey,
  ) async {
    final json = await LocalAppDatabase.instance.readJson(cacheKey);
    final rows = json?['rows'];
    if (rows is! List) return null;
    return rows
        .whereType<Map>()
        .map(
          (row) => StockMovementVelocityItem.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();
  }

  Future<void> _writeCachedVelocity(
    String cacheKey,
    List<StockMovementVelocityItem> items,
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
