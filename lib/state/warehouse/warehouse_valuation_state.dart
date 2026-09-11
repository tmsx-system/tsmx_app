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
  List<InventoryItem> _inventory = const [];
  bool _isInventoryLoading = false;
  String? _inventoryError;

  void updateStockState(WarehouseStockState value) {
    if (identical(_stockState, value)) return;
    _stockState.removeListener(notifyListeners);
    _stockState = value;
    _stockState.addListener(notifyListeners);
    notifyListeners();
  }

  List<WarehouseInfo> get warehouses => _stockState.warehouses;
  List<InventoryItem> get inventory => _inventory;
  bool get isInventoryLoading => _isInventoryLoading;
  String? get inventoryError => _inventoryError;

  Future<void> refreshWarehouses() => _stockState.refreshWarehouses();

  Future<void> refreshInventory() async {
    if (_isInventoryLoading) return;
    _isInventoryLoading = true;
    _inventoryError = null;
    notifyListeners();

    try {
      _inventory = await _stockState.fetchInventorySnapshot();
    } catch (error) {
      _inventoryError = error.toString();
    } finally {
      _isInventoryLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stockState.removeListener(notifyListeners);
    super.dispose();
  }
}
