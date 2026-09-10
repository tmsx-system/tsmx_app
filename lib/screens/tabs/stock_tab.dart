import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/warehouse/warehouse_stock_state.dart';
import '../../theme/app_colors.dart';
import '../../models/inventory_item.dart';
import '../../models/stock_area_option.dart';
import '../stock/item_stock_detail_screen.dart';

enum _StockStatusFilter { all, urgent, lowStock, inStock }

enum _StockSortOption { urgentFirst, quantityLow, quantityHigh, name }

class StockTab extends StatefulWidget {
  const StockTab({super.key});

  @override
  State<StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<StockTab> {
  String? _selectedCompany;
  String? _selectedWarehouse;
  final TextEditingController _stockSearchController = TextEditingController();
  _StockStatusFilter _stockStatusFilter = _StockStatusFilter.all;
  _StockSortOption _stockSortOption = _StockSortOption.urgentFirst;
  String? _selectedItemGroup;
  bool _selectionInitialized = false;
  bool _stockEntriesRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _stockSearchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final appState = context.read<WarehouseStockState>();
    if (appState.warehouses.isEmpty) {
      await appState.refreshWarehouses();
    }
    await appState.refreshItemGroups();
    if (!mounted) return;

    _applyDefaultSelection(appState);

    if (appState.inventory.isEmpty && _selectedCompany != null) {
      await appState.refreshInventoryForCompany(_selectedCompany!);
    }

    _requestStockEntries(appState);
  }

  void _applyDefaultSelection(WarehouseStockState appState) {
    final companies = appState.stockCompanies;
    if (companies.isEmpty) return;

    final company =
        _selectedCompany ??
        appState.preferredCompany(companies.map((entry) => entry.key)) ??
        companies.first.key;
    setState(() {
      _selectedCompany = company;
      _selectionInitialized = true;
    });
  }

  Future<void> _onPullRefresh() async {
    final appState = context.read<WarehouseStockState>();
    await appState.refreshWarehouses();
    await appState.refreshItemGroups();
    if (!mounted) return;
    _applyDefaultSelection(appState);
    if (_selectedCompany != null) {
      await appState.refreshInventoryForCompany(_selectedCompany!);
    }
    _stockEntriesRequested = false;
    _requestStockEntries(appState);
  }

  void _requestStockEntries(WarehouseStockState appState) {
    if (_stockEntriesRequested ||
        appState.stockEntries.isNotEmpty ||
        appState.isStockEntriesLoading) {
      return;
    }
    _stockEntriesRequested = true;
    unawaited(appState.refreshStockEntries());
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<WarehouseStockState>(context);
    final companies = appState.stockCompanies;

    if (!_selectionInitialized && companies.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyDefaultSelection(appState);
      });
    }

    final selectedCompany = _selectedCompany;
    final areas = selectedCompany != null
        ? appState.stockWarehousesForCompany(selectedCompany)
        : <StockAreaOption>[];

    if (selectedCompany != null &&
        areas.isNotEmpty &&
        _selectedWarehouse != null &&
        !areas.any((a) => a.areaId == _selectedWarehouse)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedWarehouse = null);
      });
    }

    final selectedWarehouse = _selectedWarehouse;
    final selectedAreas = selectedWarehouse == null
        ? areas
        : areas.where((area) => area.areaId == selectedWarehouse).toList();
    final selectedAreaIds = selectedAreas.map((area) => area.areaId).toSet();

    final areaInventory = selectedAreaIds.isEmpty
        ? <InventoryItem>[]
        : appState.inventory
              .where((item) => selectedAreaIds.contains(item.warehouseId))
              .toList();

    final filteredInventory = _filterAndSortInventory(areaInventory);

    const double extraBottomSpace = 140;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: true,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _onPullRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, extraBottomSpace),
            children: [
              _buildStockFilterBar(
                companies,
                currentItems: areaInventory,
                itemGroupOptions: appState.itemGroups,
              ),

              if (areas.isEmpty && !appState.isInventoryLoading) ...[
                const SizedBox(height: 8),
                const Text(
                  'No warehouses loaded from ERP. Pull down to refresh.',
                  style: TextStyle(fontSize: 12, color: AppColors.slate),
                ),
              ],

              const SizedBox(height: 14),

              if (appState.isInventoryLoading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              if (appState.inventoryError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    'Unable to load stock data: ${appState.inventoryError}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 8),
              _buildSectionHeader(
                'Stock Inventory',
                _inventoryCountLabel(
                  filteredInventory.length,
                  areaInventory.length,
                ),
              ),
              const SizedBox(height: 8),
              _buildInventoryControls(
                resultCount: filteredInventory.length,
                totalCount: areaInventory.length,
              ),
              const SizedBox(height: 10),

              if (filteredInventory.isEmpty && !appState.isInventoryLoading)
                _StockEmptyState(hasActiveFilters: _hasActiveStockFilters)
              else
                ...filteredInventory.map(
                  (item) => _buildInventoryCard(
                    item,
                    companyLabel: _companyTitle(companies, selectedCompany),
                    areaLabel: _selectedAreaTitle(),
                  ),
                ),

              const SizedBox(height: 22),
              _buildStockEntriesSection(appState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String detail) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'HankenGrotesk',
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        Text(
          detail,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.slate,
          ),
        ),
      ],
    );
  }

  bool get _hasActiveStockFilters {
    return _stockSearchController.text.trim().isNotEmpty ||
        _stockStatusFilter != _StockStatusFilter.all ||
        _stockSortOption != _StockSortOption.urgentFirst ||
        _selectedItemGroup != null;
  }

  List<InventoryItem> _filterAndSortInventory(List<InventoryItem> items) {
    final query = _stockSearchController.text.trim().toLowerCase();

    final filtered = items.where((item) {
      final matchesSearch =
          query.isEmpty ||
          item.sku.toLowerCase().contains(query) ||
          item.name.toLowerCase().contains(query) ||
          (item.category?.toLowerCase().contains(query) ?? false);

      final matchesStatus = switch (_stockStatusFilter) {
        _StockStatusFilter.all => true,
        _StockStatusFilter.urgent => item.status == StockStatus.urgent,
        _StockStatusFilter.lowStock => item.status == StockStatus.lowStock,
        _StockStatusFilter.inStock => item.status == StockStatus.inStock,
      };

      final matchesItemGroup =
          _selectedItemGroup == null || item.category == _selectedItemGroup;

      return matchesSearch && matchesStatus && matchesItemGroup;
    }).toList();

    filtered.sort((a, b) {
      return switch (_stockSortOption) {
        _StockSortOption.urgentFirst => _statusRank(
          a.status,
        ).compareTo(_statusRank(b.status)),
        _StockSortOption.quantityLow => a.quantity.compareTo(b.quantity),
        _StockSortOption.quantityHigh => b.quantity.compareTo(a.quantity),
        _StockSortOption.name => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
      };
    });

    return filtered;
  }

  int _statusRank(StockStatus status) {
    return switch (status) {
      StockStatus.urgent => 0,
      StockStatus.lowStock => 1,
      StockStatus.inStock => 2,
    };
  }

  String _inventoryCountLabel(int filteredCount, int totalCount) {
    if (_hasActiveStockFilters) {
      return '$filteredCount of $totalCount items';
    }
    return '$totalCount items';
  }

  Widget _buildInventoryControls({
    required int resultCount,
    required int totalCount,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _stockSearchController,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            style: const TextStyle(
              fontFamily: 'HankenGrotesk',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search SKU or item name',
              hintStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.slate,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                size: 19,
                color: AppColors.slate,
              ),
              suffixIcon: _stockSearchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: AppColors.slate,
                      onPressed: () {
                        _stockSearchController.clear();
                        setState(() {});
                      },
                    ),
              filled: true,
              fillColor: AppColors.background,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _StockStatusFilter.values.map((filter) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildStatusFilterChip(filter),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildSortMenu(),
            ],
          ),
          if (_hasActiveStockFilters) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$resultCount result${resultCount == 1 ? '' : 's'} from $totalCount items',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _stockSearchController.clear();
                    setState(() {
                      _stockStatusFilter = _StockStatusFilter.all;
                      _stockSortOption = _StockSortOption.urgentFirst;
                      _selectedItemGroup = null;
                    });
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Reset',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip(_StockStatusFilter filter) {
    final isSelected = _stockStatusFilter == filter;
    final color = _statusFilterColor(filter);

    return ChoiceChip(
      label: Text(_statusFilterLabel(filter)),
      selected: isSelected,
      onSelected: (_) => setState(() => _stockStatusFilter = filter),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: isSelected ? AppColors.white : color,
      ),
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.09),
      side: BorderSide(
        color: isSelected ? color : color.withValues(alpha: 0.16),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    );
  }

  Widget _buildSortMenu() {
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.06)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_StockSortOption>(
          value: _stockSortOption,
          isDense: true,
          dropdownColor: AppColors.white,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.primary,
            size: 18,
          ),
          style: const TextStyle(
            fontFamily: 'HankenGrotesk',
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
          items: _StockSortOption.values.map((option) {
            return DropdownMenuItem<_StockSortOption>(
              value: option,
              child: Text(_sortLabel(option)),
            );
          }).toList(),
          onChanged: (option) {
            if (option == null) return;
            setState(() => _stockSortOption = option);
          },
        ),
      ),
    );
  }

  String _sortLabel(_StockSortOption option) {
    return switch (option) {
      _StockSortOption.urgentFirst => 'Urgent first',
      _StockSortOption.quantityLow => 'Qty low-high',
      _StockSortOption.quantityHigh => 'Qty high-low',
      _StockSortOption.name => 'Name A-Z',
    };
  }

  String _statusFilterLabel(_StockStatusFilter filter) {
    return switch (filter) {
      _StockStatusFilter.all => 'All',
      _StockStatusFilter.urgent => 'Urgent',
      _StockStatusFilter.lowStock => 'Low',
      _StockStatusFilter.inStock => 'Healthy',
    };
  }

  Color _statusFilterColor(_StockStatusFilter filter) {
    return switch (filter) {
      _StockStatusFilter.all => AppColors.primary,
      _StockStatusFilter.urgent => Colors.red,
      _StockStatusFilter.lowStock => Colors.orange,
      _StockStatusFilter.inStock => Colors.green,
    };
  }

  Widget _buildStockEntriesSection(WarehouseStockState appState) {
    _requestStockEntries(appState);
    final entries = appState.stockEntries.take(8).toList();

    if (appState.isStockEntriesLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Recent Stock Entries', 'Loading'),
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
      );
    }

    if (appState.stockEntriesError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Recent Stock Entries', 'Error'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
            ),
            child: Text(
              appState.stockEntriesError!,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
        ],
      );
    }

    if (entries.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Recent Stock Entries', '0 entries'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.06),
              ),
            ),
            child: const Text(
              'No stock entries loaded.',
              style: TextStyle(fontSize: 12, color: AppColors.slate),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Recent Stock Entries', '${entries.length} latest'),
        const SizedBox(height: 8),
        ...entries.map((e) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.id,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${e.stockEntryType} - ${e.date}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.slate,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  e.statusText,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStockFilterBar(
    List<MapEntry<String, String>> companies, {
    required List<InventoryItem> currentItems,
    required List<String> itemGroupOptions,
  }) {
    final companyLabel =
        _companyTitle(companies, _selectedCompany) ?? 'Semua Company';
    final warehouseLabel = _selectedWarehouse == null
        ? 'Semua area'
        : _selectedWarehouse!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.softGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.inventory_2_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$companyLabel | $warehouseLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Cek stok realtime sesuai akses gudang',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _onPullRefresh,
            icon: const Icon(Icons.refresh_rounded),
            color: AppColors.primary,
          ),
          FilledButton.icon(
            onPressed: companies.isEmpty
                ? null
                : () => _openStockFilterSheet(
                    companies,
                    currentItems: currentItems,
                    itemGroupOptions: itemGroupOptions,
                  ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.softGreen,
              foregroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.background,
              disabledForegroundColor: AppColors.slate,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.filter_alt_outlined, size: 15),
            label: const Text(
              'Filter',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openStockFilterSheet(
    List<MapEntry<String, String>> companies, {
    required List<InventoryItem> currentItems,
    required List<String> itemGroupOptions,
  }) async {
    final appState = context.read<WarehouseStockState>();
    final result = await showModalBottomSheet<_StockFilterValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StockFilterSheet(
        companies: companies,
        areasForCompany: appState.stockWarehousesForCompany,
        currentItems: currentItems,
        itemGroupOptions: itemGroupOptions,
        selectedCompany: _selectedCompany,
        selectedWarehouse: _selectedWarehouse,
        selectedItemGroup: _selectedItemGroup,
      ),
    );
    if (result == null) return;
    if (result.company != _selectedCompany) {
      setState(() {
        _selectedCompany = result.company;
        _selectedWarehouse = result.warehouse;
        _selectedItemGroup = result.itemGroup;
      });
      appState.refreshInventoryForCompany(result.company);
      return;
    }
    setState(() {
      _selectedWarehouse = result.warehouse;
      _selectedItemGroup = result.itemGroup;
    });
  }

  String? _companyTitle(
    List<MapEntry<String, String>> companies,
    String? company,
  ) {
    if (company == null) return null;
    for (final entry in companies) {
      if (entry.key == company) return entry.value;
    }
    return company;
  }

  void _openItemDetail(
    InventoryItem item, {
    String? companyLabel,
    String? areaLabel,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ItemStockDetailScreen(
          item: item,
          companyLabel: companyLabel,
          areaLabel: areaLabel,
        ),
      ),
    );
  }

  Widget _buildInventoryCard(
    InventoryItem item, {
    String? companyLabel,
    String? areaLabel,
  }) {
    Color badgeColor = Colors.green;
    String badgeLabel = 'IN STOCK';

    if (item.status == StockStatus.lowStock) {
      badgeColor = Colors.orange;
      badgeLabel = 'LOW STOCK';
    } else if (item.status == StockStatus.urgent) {
      badgeColor = Colors.red;
      badgeLabel = 'URGENT';
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openItemDetail(
          item,
          companyLabel: companyLabel,
          areaLabel: areaLabel,
        ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _smallBadge(item.sku, AppColors.slate),
                        const SizedBox(width: 6),
                        _smallBadge(badgeLabel, badgeColor),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontFamily: 'HankenGrotesk',
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.minStockThreshold > 0
                          ? 'Reorder level: ${item.minStockThreshold} units'
                          : 'Reorder level not set',
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.slate,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${item.quantity}',
                style: TextStyle(
                  fontFamily: 'HankenGrotesk',
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: item.status == StockStatus.urgent
                      ? Colors.red
                      : AppColors.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 7,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  String _selectedAreaTitle() {
    return _selectedWarehouse ?? 'Semua Warehouse';
  }
}

class _StockFilterValue {
  const _StockFilterValue({
    required this.company,
    required this.warehouse,
    required this.itemGroup,
  });

  final String company;
  final String? warehouse;
  final String? itemGroup;
}

class _StockFilterSheet extends StatefulWidget {
  const _StockFilterSheet({
    required this.companies,
    required this.areasForCompany,
    required this.currentItems,
    required this.itemGroupOptions,
    required this.selectedCompany,
    required this.selectedWarehouse,
    required this.selectedItemGroup,
  });

  final List<MapEntry<String, String>> companies;
  final List<StockAreaOption> Function(String company) areasForCompany;
  final List<InventoryItem> currentItems;
  final List<String> itemGroupOptions;
  final String? selectedCompany;
  final String? selectedWarehouse;
  final String? selectedItemGroup;

  @override
  State<_StockFilterSheet> createState() => _StockFilterSheetState();
}

class _StockFilterSheetState extends State<_StockFilterSheet> {
  late String _company =
      widget.selectedCompany ??
      (widget.companies.isEmpty ? '' : widget.companies.first.key);
  late String? _warehouse = widget.selectedWarehouse;
  late String? _itemGroup = widget.selectedItemGroup;

  @override
  Widget build(BuildContext context) {
    final areas = _company.isEmpty
        ? const <StockAreaOption>[]
        : widget.areasForCompany(_company);
    if (_warehouse != null && !areas.any((area) => area.areaId == _warehouse)) {
      _warehouse = null;
    }
    final itemGroups = _itemGroups();
    if (_itemGroup != null && !itemGroups.contains(_itemGroup)) {
      _itemGroup = null;
    }

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppColors.cardShadow,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filter Stock',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _company,
                isExpanded: true,
                decoration: _sheetInputDecoration(
                  label: 'Company',
                  icon: Icons.business_rounded,
                ),
                items: widget.companies
                    .map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(
                          entry.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _company = value;
                    _warehouse = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              _buildWarehousePickerField(areas),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _itemGroup,
                isExpanded: true,
                decoration: _sheetInputDecoration(
                  label: 'Item Group',
                  icon: Icons.category_outlined,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua item group'),
                  ),
                  ...itemGroups.map(
                    (group) => DropdownMenuItem<String?>(
                      value: group,
                      child: Text(
                        group,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _itemGroup = value),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _company = widget.companies.isEmpty
                            ? ''
                            : widget.companies.first.key;
                        _warehouse = null;
                        _itemGroup = null;
                      }),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _company.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(
                              _StockFilterValue(
                                company: _company,
                                warehouse: _warehouse,
                                itemGroup: _itemGroup,
                              ),
                            ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Terapkan Filter'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _itemGroups() {
    final groups = {
      ...widget.itemGroupOptions
          .map((group) => group.trim())
          .where((group) => group.isNotEmpty),
      ...widget.currentItems
          .map((item) => item.category?.trim() ?? '')
          .where((group) => group.isNotEmpty),
    }.toList();
    groups.sort();
    return groups;
  }

  Widget _buildWarehousePickerField(List<StockAreaOption> areas) {
    final selectedLabel = _warehouseTitle(areas, _warehouse);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openWarehousePicker(areas),
      child: InputDecorator(
        decoration: _sheetInputDecoration(
          label: 'Warehouse',
          icon: Icons.warehouse_rounded,
        ).copyWith(suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded)),
        child: Text(
          selectedLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Future<void> _openWarehousePicker(List<StockAreaOption> areas) async {
    final result = await showModalBottomSheet<_WarehousePickerValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _WarehousePickerSheet(areas: areas, selectedWarehouse: _warehouse),
    );
    if (!mounted || result == null || result.warehouse == _warehouse) return;
    setState(() => _warehouse = result.warehouse);
  }

  String _warehouseTitle(List<StockAreaOption> areas, String? warehouse) {
    if (warehouse == null || warehouse.isEmpty) return 'Semua warehouse';
    for (final area in areas) {
      if (area.areaId == warehouse) return area.title;
    }
    return warehouse;
  }

  InputDecoration _sheetInputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _WarehousePickerValue {
  const _WarehousePickerValue(this.warehouse);

  final String? warehouse;
}

class _WarehousePickerSheet extends StatefulWidget {
  const _WarehousePickerSheet({
    required this.areas,
    required this.selectedWarehouse,
  });

  final List<StockAreaOption> areas;
  final String? selectedWarehouse;

  @override
  State<_WarehousePickerSheet> createState() => _WarehousePickerSheetState();
}

class _WarehousePickerSheetState extends State<_WarehousePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filteredAreas = query.isEmpty
        ? widget.areas
        : widget.areas
              .where((area) {
                return area.title.toLowerCase().contains(query) ||
                    area.subtitle.toLowerCase().contains(query) ||
                    area.areaId.toLowerCase().contains(query);
              })
              .toList(growable: false);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Pilih Warehouse',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Cari warehouse...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filteredAreas.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _WarehousePickerTile(
                      title: 'Semua warehouse',
                      selected: widget.selectedWarehouse == null,
                      onTap: () => Navigator.of(
                        context,
                      ).pop(const _WarehousePickerValue(null)),
                    );
                  }
                  final area = filteredAreas[index - 1];
                  return _WarehousePickerTile(
                    title: area.title,
                    subtitle: area.subtitle.isEmpty ? null : area.subtitle,
                    selected: widget.selectedWarehouse == area.areaId,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_WarehousePickerValue(area.areaId)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehousePickerTile extends StatelessWidget {
  const _WarehousePickerTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.softGreen : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? AppColors.primary : AppColors.slate,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppColors.primary : AppColors.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockEmptyState extends StatelessWidget {
  const _StockEmptyState({required this.hasActiveFilters});

  final bool hasActiveFilters;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: AppColors.slate,
          ),
          const SizedBox(height: 12),
          Text(
            hasActiveFilters
                ? 'No stock items match your filters'
                : 'No stock items in this area',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasActiveFilters
                ? 'Try a different keyword or reset the status filter.'
                : 'Try another warehouse area or pull down to refresh.',
            style: TextStyle(color: AppColors.slate, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
