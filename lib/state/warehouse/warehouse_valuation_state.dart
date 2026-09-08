import 'package:flutter/foundation.dart';

import '../../models/inventory_item.dart';
import '../../models/warehouse_info.dart';
import 'warehouse_stock_state.dart';

class WarehouseValuationState extends ChangeNotifier {
  WarehouseValuationState({required WarehouseStockState stockState}) {
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
  List<InventoryItem> get inventory => _stockState.inventory;
  bool get isInventoryLoading => _stockState.isInventoryLoading;
  String? get inventoryError => _stockState.inventoryError;

  Future<void> refreshWarehouses() => _stockState.refreshWarehouses();
  Future<void> refreshInventory() => _stockState.refreshInventory();

  @override
  void dispose() {
    _stockState.removeListener(notifyListeners);
    super.dispose();
  }
}
