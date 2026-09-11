import 'package:flutter/foundation.dart';

import '../../models/stock_ledger_movement.dart';
import '../../models/warehouse_info.dart';
import '../../utils/date_range_presets.dart';
import '../../utils/frappe_page_walker.dart';
import 'warehouse_stock_state.dart';

class WarehouseAgingState extends ChangeNotifier {
  WarehouseAgingState({required WarehouseStockState stockState}) {
    _stockState = stockState;
    _stockState.addListener(notifyListeners);
  }

  late WarehouseStockState _stockState;

  void updateStockState(WarehouseStockState value) {
    if (identical(_stockState, value)) return;
    _stockState.removeListener(notifyListeners);
    _stockState = value;
    _stockState.addListener(notifyListeners);
    notifyListeners();
  }

  List<WarehouseInfo> get warehouses => _stockState.warehouses;

  Future<void> refreshWarehouses() => _stockState.refreshWarehouses();

  Future<List<StockAgingItem>> fetchStockAging({
    int lookbackDays = 365,
    bool forceRefresh = false,
  }) async {
    final inventory = await _stockState.fetchInventorySnapshot();
    await _stockState.appState.frappeService.ensureLoggedIn();

    final today = DateTime.now();
    final from = today.subtract(Duration(days: lookbackDays));
    final rows = await walkFrappePages(
      pageSize: 500,
      maxRows: 5000,
      fetchPage: (start, limit) =>
          _stockState.appState.frappeService.fetchResource(
            'Stock Ledger Entry',
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
            limit: limit,
            limitStart: start,
            orderBy: 'posting_date desc, posting_time desc',
          ),
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
