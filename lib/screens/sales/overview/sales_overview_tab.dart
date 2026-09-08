import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../models/sales_workspace.dart';
import '../../../services/local_app_database.dart';
import '../../../state/selling/sales_overview_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_format.dart';
import '../../../utils/num_parse.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../collection/collection_widgets.dart';
import '../shared/sales_ui.dart';
import '../visit/sales_visit_tab.dart';

enum _DailySalesDocType { salesOrder, deliveryNote, salesInvoice }

enum _DailySalesSort { itemGroup, qty, amount }

const Color _salesGreen = Color(0xFF16A34A);
const Color _salesTeal = Color(0xFF14B8A6);
const Color _salesBlue = Color(0xFF3B82F6);

class SalesOverviewTab extends StatefulWidget {
  final ValueChanged<int> onMenuSelected;
  final ValueChanged<int>? onOrderTabSelected;

  const SalesOverviewTab({
    super.key,
    required this.onMenuSelected,
    this.onOrderTabSelected,
  });

  @override
  State<SalesOverviewTab> createState() => _SalesOverviewTabState();
}

class _SalesOverviewTabState extends State<SalesOverviewTab> {
  DateTime _filterDate = DateTime.now();
  String _selectedCompany = '';
  List<String> _companyOptions = const [];
  String _selectedSalesGroup = 'all';
  List<String> _salesGroupOptions = const [];
  bool _filterLoading = true;
  _DailySalesDocType _dailyDocType = _DailySalesDocType.salesOrder;
  _DailySalesSort _dailySort = _DailySalesSort.amount;
  DailySalesReport _dailyReport = const DailySalesReport();
  bool _dailyReportLoading = true;
  int _dailyRequestVersion = 0;
  String? _dailyReportError;
  List<SalesPersonCustomerRanking> _topCustomers = const [];
  List<CollectionRanking> _ranking = const [];
  bool _topCustomersLoading = true;
  bool _rankingLoading = true;
  bool _visitLoading = true;
  int _rankingRequestVersion = 0;
  String? _topCustomersError;
  String? _rankingError;
  String? _visitError;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadFilterOptions();
      if (!mounted) return;
      _startInitialLoads();
    });
  }

  String get _dailyDoctype => switch (_dailyDocType) {
    _DailySalesDocType.deliveryNote => 'Delivery Note',
    _DailySalesDocType.salesInvoice => 'Sales Invoice',
    _ => 'Sales Order',
  };

  static const Duration _salesOverviewCacheTtl = Duration(hours: 12);
  static const String _salesOverviewCachePrefix = 'sales_overview';

  DateTime get _periodStart =>
      DateTime(_filterDate.year, _filterDate.month, _filterDate.day);

  DateTime get _periodEnd => _periodStart;

  String get _periodKey =>
      '${_filterDate.year}-${_filterDate.month.toString().padLeft(2, '0')}-${_filterDate.day.toString().padLeft(2, '0')}';

  String _scopeKey(SalesOverviewState state) {
    final salesPerson = state.mobileAccess.shouldScopeSalesData
        ? state.currentSalesPerson ?? ''
        : '';
    return [
      state.selectedSiteBaseUrl.trim(),
      state.currentUser?.trim() ?? '',
      _selectedCompany.trim(),
      _selectedSalesGroup.trim(),
      salesPerson,
    ].join('|');
  }

  String _dailyCacheKey(SalesOverviewState state, _DailySalesDocType type) {
    return [
      _salesOverviewCachePrefix,
      'daily',
      _scopeKey(state),
      type.name,
      _periodKey,
    ].join('|');
  }

  String _topCustomersCacheKey(SalesOverviewState state) {
    return [
      _salesOverviewCachePrefix,
      'top_customers',
      _scopeKey(state),
      _periodKey,
    ].join('|');
  }

  String _rankingCacheKey(SalesOverviewState state) {
    return [
      _salesOverviewCachePrefix,
      'collection_ranking',
      _scopeKey(state),
      _periodKey,
    ].join('|');
  }

  void _startInitialLoads() {
    _loadDailyReport();
    _loadVisitSnapshot();
    _loadProfileImage();
    _startDeferredRankingLoad();
  }

  void _startDeferredRankingLoad({bool forceRemote = false}) {
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _loadRanking(forceRemote: forceRemote);
    });
  }

  Future<void> _loadFilterOptions() async {
    final state = context.read<SalesOverviewState>();
    try {
      if (state.mobileAccess.shouldScopeSalesData) {
        await state.loadSellingFilterOptions();
        _companyOptions = state.sellingCompanies;
        _selectedCompany = state.sellingCompanyFilter.trim().isNotEmpty
            ? state.sellingCompanyFilter
            : state.preferredCompany(_companyOptions) ?? '';
        _selectedSalesGroup = state.currentSalesPerson ?? 'all';
        _salesGroupOptions = [
          if (state.currentSalesPerson?.isNotEmpty == true)
            state.currentSalesPerson!,
        ];
      } else {
        await state.loadSellingFilterOptions();
        _companyOptions = state.sellingCompanies;
        _selectedCompany = state.sellingCompanyFilter.trim().isNotEmpty
            ? state.sellingCompanyFilter
            : state.preferredCompany(_companyOptions) ?? '';
        _salesGroupOptions = state.sellingSalesGroups;
        if (_selectedSalesGroup != 'all' &&
            !_salesGroupOptions.contains(_selectedSalesGroup)) {
          _selectedSalesGroup = 'all';
        }
      }
    } catch (_) {
      _companyOptions = const [];
      _salesGroupOptions = [
        if (state.currentSalesPerson?.isNotEmpty == true)
          state.currentSalesPerson!,
      ];
    } finally {
      if (mounted) setState(() => _filterLoading = false);
    }
  }

  Future<void> _loadDailyReport({bool forceRemote = false}) async {
    final requestVersion = ++_dailyRequestVersion;
    final state = context.read<SalesOverviewState>();
    if (!state.canUseSales) {
      if (mounted) {
        setState(() {
          _dailyReport = const DailySalesReport();
          _dailyReportLoading = false;
          _dailyReportError = null;
        });
      }
      return;
    }
    final cacheKey = _dailyCacheKey(state, _dailyDocType);
    if (!forceRemote) {
      final cached = await _readDailyReport(cacheKey);
      if (cached != null && mounted && requestVersion == _dailyRequestVersion) {
        if (!cached.isEmpty) {
          setState(() {
            _dailyReport = cached;
            _dailyReportError = null;
            _dailyReportLoading = false;
          });
          return;
        }
      }
    }
    setState(() {
      _dailyReportLoading = true;
      _dailyReportError = null;
    });
    try {
      final report = await state.fetchDailySalesReport(
        doctype: _dailyDoctype,
        from: _periodStart,
        to: _periodEnd,
        salesPerson: state.mobileAccess.shouldScopeSalesData
            ? state.currentSalesPerson
            : null,
        parentSalesPerson: _selectedParentSalesPerson(state),
        company: _selectedCompany,
      );
      if (mounted && requestVersion == _dailyRequestVersion) {
        await _writeDailyReport(cacheKey, report);
        setState(() => _dailyReport = report);
      }
    } catch (error) {
      if (mounted && requestVersion == _dailyRequestVersion) {
        final message = error.toString();
        setState(() {
          _dailyReport = const DailySalesReport();
          _dailyReportError = message;
        });
      }
    } finally {
      if (mounted && requestVersion == _dailyRequestVersion) {
        setState(() => _dailyReportLoading = false);
      }
    }
  }

  void _setDailyDocType(_DailySalesDocType type) {
    if (_dailyDocType == type) return;
    setState(() => _dailyDocType = type);
    _loadDailyReport();
  }

  Future<void> _openOverviewFilterSheet() async {
    final result = await showModalBottomSheet<_SalesOverviewFilterValue>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => _SalesOverviewFilterSheet(
        initialDate: _filterDate,
        initialCompany: _selectedCompany,
        initialSalesGroup: _selectedSalesGroup,
        companies: _companyOptions,
        salesGroups: _salesGroupOptions,
        lockSalesPerson: context
            .read<SalesOverviewState>()
            .mobileAccess
            .shouldScopeSalesData,
        loading: _filterLoading,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _filterDate = result.date;
      _selectedCompany = result.company;
      _selectedSalesGroup = result.salesGroup;
    });
    await _reloadReports(forceRemote: true);
  }

  Future<void> _loadRanking({bool forceRemote = false}) async {
    final requestVersion = ++_rankingRequestVersion;
    final state = context.read<SalesOverviewState>();
    final canViewTopCustomers = _canViewTopCustomers(state);
    final canViewRanking = _canViewRanking(state);
    if (!canViewTopCustomers && !canViewRanking) {
      if (mounted) {
        setState(() {
          _topCustomers = const [];
          _ranking = const [];
          _topCustomersLoading = false;
          _rankingLoading = false;
          _topCustomersError = null;
          _rankingError = null;
        });
      }
      return;
    }
    setState(() {
      _topCustomersLoading = canViewTopCustomers;
      _rankingLoading = canViewRanking;
      _topCustomersError = null;
      _rankingError = null;
    });
    final parentSalesPerson = _selectedParentSalesPerson(state);
    await Future.wait([
      if (canViewTopCustomers)
        _loadTopCustomers(
          state: state,
          requestVersion: requestVersion,
          parentSalesPerson: parentSalesPerson,
          forceRemote: forceRemote,
        ),
      if (canViewRanking)
        _loadCollectionRanking(
          state: state,
          requestVersion: requestVersion,
          parentSalesPerson: parentSalesPerson,
          forceRemote: forceRemote,
        ),
    ]);
  }

  Future<void> _loadTopCustomers({
    required SalesOverviewState state,
    required int requestVersion,
    required String? parentSalesPerson,
    bool forceRemote = false,
  }) async {
    final cacheKey = _topCustomersCacheKey(state);
    if (!forceRemote) {
      final cached = await _readTopCustomers(cacheKey);
      if (cached != null &&
          mounted &&
          requestVersion == _rankingRequestVersion) {
        if (cached.isNotEmpty) {
          setState(() {
            _topCustomers = cached;
            _topCustomersError = null;
            _topCustomersLoading = false;
          });
          return;
        }
      }
    }
    try {
      final topCustomers = await state.fetchTopCustomersBySalesPerson(
        from: _periodStart,
        to: _periodEnd,
        scopeToCurrentSales: state.mobileAccess.shouldScopeSalesData,
        salesPerson: state.mobileAccess.shouldScopeSalesData
            ? state.currentSalesPerson
            : null,
        parentSalesPerson: parentSalesPerson,
        company: _selectedCompany,
      );
      if (mounted && requestVersion == _rankingRequestVersion) {
        await _writeTopCustomers(cacheKey, topCustomers);
        setState(() => _topCustomers = topCustomers);
      }
    } catch (error) {
      if (mounted && requestVersion == _rankingRequestVersion) {
        setState(() => _topCustomersError = error.toString());
      }
    } finally {
      if (mounted && requestVersion == _rankingRequestVersion) {
        setState(() => _topCustomersLoading = false);
      }
    }
  }

  Future<void> _loadCollectionRanking({
    required SalesOverviewState state,
    required int requestVersion,
    required String? parentSalesPerson,
    bool forceRemote = false,
  }) async {
    final cacheKey = _rankingCacheKey(state);
    if (!forceRemote) {
      final cached = await _readCollectionRanking(cacheKey);
      if (cached != null &&
          mounted &&
          requestVersion == _rankingRequestVersion) {
        if (cached.isNotEmpty) {
          setState(() {
            _ranking = cached;
            _rankingError = null;
            _rankingLoading = false;
          });
          return;
        }
      }
    }
    try {
      final ranking = await state.fetchCollectionRanking(
        from: _periodStart,
        to: _periodEnd,
        filterSalesPerson: state.mobileAccess.shouldScopeSalesData
            ? state.currentSalesPerson
            : null,
        parentSalesPerson: parentSalesPerson,
        company: _selectedCompany,
      );
      if (mounted && requestVersion == _rankingRequestVersion) {
        await _writeCollectionRanking(cacheKey, ranking);
        setState(() => _ranking = ranking);
      }
    } catch (error) {
      if (mounted && requestVersion == _rankingRequestVersion) {
        setState(() => _rankingError = error.toString());
      }
    } finally {
      if (mounted && requestVersion == _rankingRequestVersion) {
        setState(() => _rankingLoading = false);
      }
    }
  }

  Future<void> _reloadReports({
    bool forceRemote = false,
    bool includeVisitSnapshot = false,
  }) async {
    await Future.wait([
      _loadDailyReport(forceRemote: forceRemote),
      if (includeVisitSnapshot) _loadVisitSnapshot(forceRefresh: forceRemote),
    ]);
    _startDeferredRankingLoad(forceRemote: forceRemote);
  }

  Future<void> _loadVisitSnapshot({bool forceRefresh = false}) async {
    final state = context.read<SalesOverviewState>();
    if (!state.canUseSales) {
      if (mounted) {
        setState(() {
          _visitLoading = false;
          _visitError = null;
        });
      }
      return;
    }
    setState(() {
      _visitLoading = true;
      _visitError = null;
    });
    try {
      await state.fetchSalesVisits(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() => _visitError = null);
    } catch (error) {
      if (!mounted) return;
      if (_isSalesVisitPermissionError(error)) {
        setState(() {
          _visitError = null;
        });
      } else {
        setState(() => _visitError = error.toString());
      }
    } finally {
      if (mounted) setState(() => _visitLoading = false);
    }
  }

  Future<void> _loadProfileImage() async {
    final state = context.read<SalesOverviewState>();
    try {
      final profile = await state.fetchCurrentUserProfile();
      final image = profile['user_image']?.toString().trim() ?? '';
      if (!mounted || image.isEmpty) return;
      final imageUrl =
          image.startsWith('http://') || image.startsWith('https://')
          ? image
          : Uri.parse(state.frappeService.baseUrl).resolve(image).toString();
      setState(() => _profileImageUrl = imageUrl);
    } catch (_) {
      if (mounted) setState(() => _profileImageUrl = null);
    }
  }

  bool _isSalesVisitPermissionError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('akses erpnext tidak diizinkan') ||
        message.contains('permissionerror') ||
        message.contains('not permitted') ||
        message.contains('insufficient permission');
  }

  Future<void> _openVisitCheckIn() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SalesVisitCheckInScreen()));
    if (!mounted) return;
    await _loadVisitSnapshot();
  }

  Future<void> _checkOutActiveVisit(SalesVisit visit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Selesaikan absensi?'),
        content: Text('Checkout dari ${visit.customer}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Check-out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _visitLoading = true;
      _visitError = null;
    });
    try {
      await context.read<SalesOverviewState>().checkOutSalesVisit(visit.id);
      await _loadVisitSnapshot();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _visitError = error.toString();
        _visitLoading = false;
      });
    }
  }

  Future<DailySalesReport?> _readDailyReport(String key) async {
    final json = await LocalAppDatabase.instance.readJson(key);
    if (json == null) return null;
    try {
      return _dailyReportFromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDailyReport(String key, DailySalesReport report) {
    return LocalAppDatabase.instance.writeJson(
      key,
      _dailyReportToJson(report),
      ttl: _salesOverviewCacheTtl,
    );
  }

  Future<List<SalesPersonCustomerRanking>?> _readTopCustomers(
    String key,
  ) async {
    final json = await LocalAppDatabase.instance.readJson(key);
    final rows = json?['rows'];
    if (rows is! List) return null;
    try {
      return rows
          .whereType<Map>()
          .map((row) => _topCustomerFromJson(Map<String, dynamic>.from(row)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeTopCustomers(
    String key,
    List<SalesPersonCustomerRanking> rows,
  ) {
    return LocalAppDatabase.instance.writeJson(key, {
      'rows': rows.map(_topCustomerToJson).toList(),
    }, ttl: _salesOverviewCacheTtl);
  }

  Future<List<CollectionRanking>?> _readCollectionRanking(String key) async {
    final json = await LocalAppDatabase.instance.readJson(key);
    final rows = json?['rows'];
    if (rows is! List) return null;
    try {
      return rows
          .whereType<Map>()
          .map(
            (row) => _collectionRankingFromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCollectionRanking(
    String key,
    List<CollectionRanking> rows,
  ) {
    return LocalAppDatabase.instance.writeJson(key, {
      'rows': rows.map(_collectionRankingToJson).toList(),
    }, ttl: _salesOverviewCacheTtl);
  }

  DailySalesReport _dailyReportFromJson(Map<String, dynamic> json) {
    final itemRows = json['items'];
    final customerRows = json['customers'];
    return DailySalesReport(
      items: itemRows is List
          ? itemRows
                .whereType<Map>()
                .map(
                  (row) => _dailyItemFromJson(Map<String, dynamic>.from(row)),
                )
                .toList()
          : const [],
      customers: customerRows is List
          ? customerRows
                .whereType<Map>()
                .map(
                  (row) =>
                      _dailyCustomerFromJson(Map<String, dynamic>.from(row)),
                )
                .toList()
          : const [],
      totalQty: NumParse.asDouble(json['total_qty']),
      totalAmount: NumParse.asDouble(json['total_amount']),
    );
  }

  Map<String, dynamic> _dailyReportToJson(DailySalesReport report) {
    return {
      'items': report.items.map(_dailyItemToJson).toList(),
      'customers': report.customers.map(_dailyCustomerToJson).toList(),
      'total_qty': report.totalQty,
      'total_amount': report.totalAmount,
    };
  }

  DailySalesItemSummary _dailyItemFromJson(Map<String, dynamic> json) {
    return DailySalesItemSummary(
      itemLabel: json['item_label']?.toString() ?? '',
      itemGroup: json['item_group']?.toString() ?? '',
      qty: NumParse.asDouble(json['qty']),
      amount: NumParse.asDouble(json['amount']),
    );
  }

  Map<String, dynamic> _dailyItemToJson(DailySalesItemSummary item) {
    return {
      'item_label': item.itemLabel,
      'item_group': item.itemGroup,
      'qty': item.qty,
      'amount': item.amount,
    };
  }

  DailySalesCustomerSummary _dailyCustomerFromJson(Map<String, dynamic> json) {
    final itemRows = json['items'];
    return DailySalesCustomerSummary(
      customer: json['customer']?.toString() ?? '',
      items: itemRows is List
          ? itemRows
                .whereType<Map>()
                .map(
                  (row) => _dailyItemFromJson(Map<String, dynamic>.from(row)),
                )
                .toList()
          : const [],
      totalAmount: NumParse.asDouble(json['total_amount']),
    );
  }

  Map<String, dynamic> _dailyCustomerToJson(
    DailySalesCustomerSummary customer,
  ) {
    return {
      'customer': customer.customer,
      'items': customer.items.map(_dailyItemToJson).toList(),
      'total_amount': customer.totalAmount,
    };
  }

  SalesPersonCustomerRanking _topCustomerFromJson(Map<String, dynamic> json) {
    return SalesPersonCustomerRanking(
      salesPerson: json['sales_person']?.toString() ?? '',
      customer: json['customer']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      amount: NumParse.asDouble(json['amount']),
      orderCount: NumParse.asInt(json['order_count']),
      rank: NumParse.asInt(json['rank']),
    );
  }

  Map<String, dynamic> _topCustomerToJson(SalesPersonCustomerRanking row) {
    return {
      'sales_person': row.salesPerson,
      'customer': row.customer,
      'customer_name': row.customerName,
      'amount': row.amount,
      'order_count': row.orderCount,
      'rank': row.rank,
    };
  }

  CollectionRanking _collectionRankingFromJson(Map<String, dynamic> json) {
    return CollectionRanking(
      salesPerson: json['sales_person']?.toString() ?? '',
      amount: NumParse.asDouble(json['amount']),
      rank: NumParse.asInt(json['rank']),
    );
  }

  Map<String, dynamic> _collectionRankingToJson(CollectionRanking row) {
    return {
      'sales_person': row.salesPerson,
      'amount': row.amount,
      'rank': row.rank,
    };
  }

  bool _canViewRanking(SalesOverviewState state) {
    return state.isSalesManagerRole ||
        state.mobileAccess.isAdministrator ||
        state.mobileAccess.isDeveloper ||
        state.mobileAccess.isCompanyAdministrator ||
        state.mobileAccess.isDirector;
  }

  bool _canViewTopCustomers(SalesOverviewState state) {
    return state.canUseSales;
  }

  String? _selectedParentSalesPerson(SalesOverviewState state) {
    if (state.mobileAccess.shouldScopeSalesData) return null;
    final group = _selectedSalesGroup.trim();
    if (group.isEmpty || group.toLowerCase() == 'all') return null;
    return group;
  }

  String get _selectedSalesGroupLabel {
    if (_selectedSalesGroup.trim().isEmpty || _selectedSalesGroup == 'all') {
      return 'All';
    }
    return _selectedSalesGroup;
  }

  List<DailySalesItemSummary> _sortedDailyItems() {
    final items = [..._dailyReport.items];
    items.sort((a, b) {
      switch (_dailySort) {
        case _DailySalesSort.itemGroup:
          final groupComparison = a.itemGroup.compareTo(b.itemGroup);
          if (groupComparison != 0) return groupComparison;
          return a.itemLabel.compareTo(b.itemLabel);
        case _DailySalesSort.qty:
          final qtyComparison = b.qty.compareTo(a.qty);
          if (qtyComparison != 0) return qtyComparison;
          return a.itemLabel.compareTo(b.itemLabel);
        case _DailySalesSort.amount:
          final amountComparison = b.amount.compareTo(a.amount);
          if (amountComparison != 0) return amountComparison;
          return a.itemLabel.compareTo(b.itemLabel);
      }
    });
    return items;
  }

  String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }

  Future<void> _shareCsv(String fileName, List<List<Object?>> rows) async {
    if (rows.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada data untuk diexport')),
      );
      return;
    }
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    final csv = rows
        .map((row) => row.map(_csvCell).join(','))
        .join(Platform.lineTerminator);
    await file.writeAsString(csv, flush: true);
    if (!mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: fileName,
      ),
    );
  }

  String get _dateFileLabel => _periodKey;

  List<List<Object?>> _dailyCustomerExportRows() {
    final rows = <List<Object?>>[];
    for (final customer in _dailyReport.customers) {
      final customerQty = customer.items.fold<double>(
        0,
        (total, item) => total + item.qty,
      );
      for (final item in customer.items) {
        rows.add([
          customer.customer,
          item.itemLabel,
          item.qty,
          item.amount,
          '',
        ]);
      }
      rows.add([
        customer.customer,
        'TOTAL CUSTOMER',
        customerQty,
        '',
        customer.totalAmount,
      ]);
      rows.add([]);
    }
    return rows;
  }

  Future<void> _exportDailyReport() {
    return _shareCsv('sales_report_$_dateFileLabel.csv', [
      ['Tipe Dokumen', _dailyDoctype],
      ['Tanggal', _dateFileLabel],
      [
        'Company',
        _selectedCompany.isEmpty ? 'Semua Company' : _selectedCompany,
      ],
      ['Sales Group', _selectedSalesGroupLabel],
      [],
      ['Item Group', 'Item', 'Qty', 'Omzet'],
      ..._sortedDailyItems().map(
        (item) => [item.itemGroup, item.itemLabel, item.qty, item.amount],
      ),
      ['TOTAL SALES', _dailyReport.totalQty, _dailyReport.totalAmount],
      [],
      ['Customer', 'Item', 'Qty', 'Omzet Item', 'Total Customer'],
      ..._dailyCustomerExportRows(),
    ]);
  }

  Future<void> _exportTopCustomers() {
    return _shareCsv('top_10_customer_$_dateFileLabel.csv', [
      [
        'Company',
        _selectedCompany.isEmpty ? 'Semua Company' : _selectedCompany,
      ],
      ['Tanggal', _dateFileLabel],
      ['Sales Group', _selectedSalesGroupLabel],
      [],
      ['Rank', 'Sales Person', 'Customer', 'Jumlah SO', 'Nilai'],
      ..._topCustomers
          .take(10)
          .map(
            (row) => [
              row.rank,
              row.salesPerson,
              row.customerName,
              row.orderCount,
              row.amount,
            ],
          ),
    ]);
  }

  Future<void> _exportCollectionRanking() {
    return _shareCsv('ranking_collection_$_dateFileLabel.csv', [
      [
        'Company',
        _selectedCompany.isEmpty ? 'Semua Company' : _selectedCompany,
      ],
      ['Tanggal', _dateFileLabel],
      ['Sales Group', _selectedSalesGroupLabel],
      [],
      ['Rank', 'Sales Person', 'Nilai'],
      ..._ranking.take(5).map((row) => [row.rank, row.salesPerson, row.amount]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SalesOverviewState>();
    final canViewTopCustomers = _canViewTopCustomers(state);
    final canViewRanking = _canViewRanking(state);
    final topCustomerSubtitle = state.mobileAccess.shouldScopeSalesData
        ? 'Customer terbesar milik Sales Person login'
        : 'Customer terbesar dari nilai Sales Order';
    return RefreshIndicator(
      onRefresh: () async {
        await state.refreshDataForCurrentRole();
        await _reloadReports(forceRemote: true, includeVisitSnapshot: true);
      },
      child: ListView(
        padding: SalesUi.screenPaddingOf(context),
        children: [
          if (state.canUseSales) ...[
            _SalesVisitActionCard(
              active: state.activeSalesVisit,
              profileImageUrl: _profileImageUrl,
              loading: _visitLoading,
              error: _visitError,
              onCheckIn: _openVisitCheckIn,
              onCheckOut: state.activeSalesVisit == null
                  ? null
                  : () => _checkOutActiveVisit(state.activeSalesVisit!),
              onOpenHistory: () => widget.onMenuSelected(4),
            ),
            SalesUi.gap(18),
          ],

          _SalesOverviewFilterCard(
            date: _filterDate,
            selectedCompany: _selectedCompany,
            selectedSalesGroup: _selectedSalesGroup,
            lockSalesPerson: state.mobileAccess.shouldScopeSalesData,
            onOpenFilter: _openOverviewFilterSheet,
          ),

          if (state.canUseSales) ...[
            SalesUi.gap(18),
            _DailySalesReportCard(
              report: _dailyReport,
              loading: _dailyReportLoading,
              error: _dailyReportError,
              selectedType: _dailyDocType,
              selectedSort: _dailySort,
              onTypeChanged: _setDailyDocType,
              onSortChanged: (sort) => setState(() => _dailySort = sort),
              onExport: _exportDailyReport,
            ),
          ],

          if (canViewTopCustomers) ...[
            SalesUi.gap(18),
            SalesInfoCard(
              padding: const EdgeInsets.all(14),
              accent: _salesGreen,
              child: Column(
                children: [
                  CollectionSectionHeader(
                    title: 'Top 10 Customer per Sales Person',
                    subtitle: topCustomerSubtitle,
                    icon: Icons.groups_2_rounded,
                    trailing: IconButton.filledTonal(
                      tooltip: 'Export CSV',
                      onPressed: _topCustomersLoading
                          ? null
                          : _exportTopCustomers,
                      icon: const Icon(Icons.file_download_outlined),
                    ),
                  ),
                  SalesUi.gap(10),
                  if (_topCustomersLoading)
                    const LinearProgressIndicator()
                  else if (_topCustomersError != null)
                    ErpErrorBox(message: _topCustomersError!)
                  else if (_topCustomers.isEmpty)
                    const ErpEmptyState(
                      title: 'Belum ada customer pada periode ini',
                      message:
                          'Top customer dibaca dari Sales Team pada Sales Order sesuai periode.',
                    )
                  else
                    ..._topCustomers
                        .take(10)
                        .map((row) => _TopCustomerCard(row: row)),
                ],
              ),
            ),
          ],

          if (canViewRanking) ...[
            SalesUi.gap(18),
            SalesInfoCard(
              padding: const EdgeInsets.all(14),
              accent: _salesGreen,
              child: Column(
                children: [
                  CollectionSectionHeader(
                    title: 'Ranking Collection',
                    subtitle: 'Berdasarkan nilai Sales Order dari Sales Team',
                    icon: Icons.emoji_events_rounded,
                    trailing: IconButton.filledTonal(
                      tooltip: 'Export CSV',
                      onPressed: _rankingLoading
                          ? null
                          : _exportCollectionRanking,
                      icon: const Icon(Icons.file_download_outlined),
                    ),
                  ),
                  SalesUi.gap(10),
                  if (_rankingLoading)
                    const LinearProgressIndicator()
                  else if (_rankingError != null)
                    ErpErrorBox(message: _rankingError!)
                  else if (_ranking.isEmpty)
                    const ErpEmptyState(
                      title: 'Belum ada Sales Order pada periode ini',
                      message:
                          'Ranking dibaca dari Sales Team pada Sales Order sesuai periode.',
                    )
                  else
                    ..._ranking
                        .take(5)
                        .map((row) => _CollectionRankingRow(row: row)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SalesVisitActionCard extends StatelessWidget {
  const _SalesVisitActionCard({
    required this.active,
    required this.profileImageUrl,
    required this.loading,
    required this.error,
    required this.onCheckIn,
    required this.onCheckOut,
    required this.onOpenHistory,
  });

  final SalesVisit? active;
  final String? profileImageUrl;
  final bool loading;
  final String? error;
  final VoidCallback onCheckIn;
  final VoidCallback? onCheckOut;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final activeVisit = active;
    final now = DateTime.now();
    final greeting = now.hour < 11
        ? 'Good Morning,'
        : now.hour < 15
        ? 'Good Afternoon,'
        : 'Good Evening,';
    final title = activeVisit?.customer.trim().isNotEmpty == true
        ? activeVisit!.customer
        : 'Sales Team!';
    final statusText = activeVisit == null
        ? 'You are not Check-in yet Today.'
        : 'You are checked in today.';
    final timeText = activeVisit == null
        ? ''
        : (activeVisit.checkInTime.isEmpty ? '-' : activeVisit.checkInTime);
    return SalesInfoCard(
      padding: const EdgeInsets.all(12),
      accent: _salesGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (timeText.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            timeText,
                            style: const TextStyle(
                              color: _salesBlue,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onOpenHistory,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: AppColors.softGreen,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.white,
                              width: 2,
                            ),
                          ),
                          child: profileImageUrl == null
                              ? const Icon(
                                  Icons.person_rounded,
                                  color: _salesGreen,
                                  size: 24,
                                )
                              : Image.network(
                                  profileImageUrl!,
                                  cacheWidth: 96,
                                  cacheHeight: 96,
                                  filterQuality: FilterQuality.medium,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(
                                    Icons.person_rounded,
                                    color: _salesGreen,
                                    size: 24,
                                  ),
                                ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: AppColors.softGreen,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.white,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              activeVisit == null
                                  ? Icons.location_on_outlined
                                  : Icons.near_me_rounded,
                              color: _salesGreen,
                              size: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (loading)
                const Positioned(
                  right: 0,
                  top: 0,
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: activeVisit == null ? onCheckIn : onCheckOut,
              style: OutlinedButton.styleFrom(
                foregroundColor: _salesGreen,
                side: BorderSide(color: _salesGreen.withValues(alpha: 0.45)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
              icon: Icon(
                activeVisit == null
                    ? Icons.login_rounded
                    : Icons.logout_rounded,
                size: 17,
              ),
              label: Text(
                activeVisit == null ? 'Check In' : 'Check Out',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesOverviewFilterCard extends StatelessWidget {
  const _SalesOverviewFilterCard({
    required this.date,
    required this.selectedCompany,
    required this.selectedSalesGroup,
    required this.lockSalesPerson,
    required this.onOpenFilter,
  });

  final DateTime date;
  final String selectedCompany;
  final String selectedSalesGroup;
  final bool lockSalesPerson;
  final VoidCallback onOpenFilter;

  @override
  Widget build(BuildContext context) {
    return SalesInfoCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      accent: _salesTeal,
      child: Row(
        children: [
          const Icon(
            Icons.calendar_month_rounded,
            color: AppColors.slate,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_dateLabel(date)}  |  ${selectedCompany.isEmpty ? 'Semua Company' : selectedCompany}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  lockSalesPerson
                      ? 'Sales login'
                      : selectedSalesGroup == 'all'
                      ? 'All Sales Group'
                      : selectedSalesGroup,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onOpenFilter,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.softGreen,
              foregroundColor: AppColors.primary,
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
}

class _SalesOverviewFilterValue {
  final DateTime date;
  final String company;
  final String salesGroup;

  const _SalesOverviewFilterValue({
    required this.date,
    required this.company,
    required this.salesGroup,
  });
}

class _SalesOverviewFilterSheet extends StatefulWidget {
  const _SalesOverviewFilterSheet({
    required this.initialDate,
    required this.initialCompany,
    required this.initialSalesGroup,
    required this.companies,
    required this.salesGroups,
    required this.lockSalesPerson,
    required this.loading,
  });

  final DateTime initialDate;
  final String initialCompany;
  final String initialSalesGroup;
  final List<String> companies;
  final List<String> salesGroups;
  final bool lockSalesPerson;
  final bool loading;

  @override
  State<_SalesOverviewFilterSheet> createState() =>
      _SalesOverviewFilterSheetState();
}

class _SalesOverviewFilterSheetState extends State<_SalesOverviewFilterSheet> {
  late DateTime _date;
  late String _company;
  late String _salesGroup;

  @override
  void initState() {
    super.initState();
    _date = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _company = widget.initialCompany;
    _salesGroup = widget.initialSalesGroup;
  }

  void _reset() {
    final now = DateTime.now();
    setState(() {
      _date = DateTime(now.year, now.month, now.day);
      _company = '';
      _salesGroup = widget.lockSalesPerson ? widget.initialSalesGroup : 'all';
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2, 12, 31),
    );
    if (picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }

  void _apply() {
    Navigator.pop(
      context,
      _SalesOverviewFilterValue(
        date: _date,
        company: _company,
        salesGroup: _salesGroup,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedCompany =
        _company.isEmpty || widget.companies.contains(_company) ? _company : '';
    final selectedSalesGroup =
        _salesGroup == 'all' || widget.salesGroups.contains(_salesGroup)
        ? _salesGroup
        : 'all';

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          14,
          0,
          14,
          MediaQuery.viewInsetsOf(context).bottom + 14,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Filter Tanggal & Lainnya',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: widget.loading ? null : _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Tanggal',
                    prefixIcon: Icon(Icons.calendar_today_rounded),
                    suffixIcon: Icon(Icons.expand_more_rounded),
                  ),
                  child: Text(
                    _dateLabel(_date),
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedCompany,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Company',
                  prefixIcon: Icon(Icons.business_rounded),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Semua Company'),
                  ),
                  ...widget.companies.map(
                    (company) => DropdownMenuItem<String>(
                      value: company,
                      child: Text(company, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: widget.loading
                    ? null
                    : (value) => setState(() => _company = value ?? ''),
              ),
              if (!widget.lockSalesPerson) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedSalesGroup,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sales Group',
                    prefixIcon: Icon(Icons.groups_rounded),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('All'),
                    ),
                    ...widget.salesGroups.map(
                      (salesGroup) => DropdownMenuItem<String>(
                        value: salesGroup,
                        child: Text(
                          salesGroup,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: widget.loading
                      ? null
                      : (value) => setState(() => _salesGroup = value ?? 'all'),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.loading ? null : _reset,
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.loading ? null : _apply,
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
}

String _dateLabel(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')} ${_monthName(date.month)} ${date.year}';
}

String _monthName(int month) {
  const names = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];
  if (month < 1 || month > 12) return '-';
  return names[month - 1];
}

class _DailySalesReportCard extends StatelessWidget {
  const _DailySalesReportCard({
    required this.report,
    required this.loading,
    required this.error,
    required this.selectedType,
    required this.selectedSort,
    required this.onTypeChanged,
    required this.onSortChanged,
    required this.onExport,
  });

  final DailySalesReport report;
  final bool loading;
  final String? error;
  final _DailySalesDocType selectedType;
  final _DailySalesSort selectedSort;
  final ValueChanged<_DailySalesDocType> onTypeChanged;
  final ValueChanged<_DailySalesSort> onSortChanged;
  final VoidCallback onExport;

  String get _docLabel => switch (selectedType) {
    _DailySalesDocType.deliveryNote => 'DN',
    _DailySalesDocType.salesInvoice => 'SI',
    _ => 'SO',
  };

  @override
  Widget build(BuildContext context) {
    return SalesInfoCard(
      padding: const EdgeInsets.all(14),
      accent: _salesBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _salesBlue.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.summarize_rounded, color: _salesBlue),
              ),

              const SizedBox(width: 10),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report Harian Pendapatan',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Ringkasan item dan omzet per customer',
                      style: TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              IconButton.filledTonal(
                tooltip: 'Export CSV',
                onPressed: loading ? null : onExport,
                icon: const Icon(Icons.file_download_outlined),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _DailyDocChip(
                  label: 'SO',
                  selected: selectedType == _DailySalesDocType.salesOrder,
                  onTap: () => onTypeChanged(_DailySalesDocType.salesOrder),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DailyDocChip(
                  label: 'DN',
                  selected: selectedType == _DailySalesDocType.deliveryNote,
                  onTap: () => onTypeChanged(_DailySalesDocType.deliveryNote),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DailyDocChip(
                  label: 'SI',
                  selected: selectedType == _DailySalesDocType.salesInvoice,
                  onTap: () => onTypeChanged(_DailySalesDocType.salesInvoice),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _DailySortSelector(selected: selectedSort, onChanged: onSortChanged),

          const SizedBox(height: 12),

          if (loading)
            const LinearProgressIndicator()
          else if (error != null)
            ErpErrorBox(message: error!)
          else if (report.isEmpty)
            ErpEmptyState(
              title: 'Belum ada data $_docLabel pada periode ini',
              message:
                  'Coba pilih tanggal, sales group, atau tipe dokumen lain.',
            )
          else ...[
            _DailyItemSummaryTable(report: report, sort: selectedSort),
            const SizedBox(height: 12),
            ...report.customers.map(
              (customer) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DailyCustomerSalesCard(customer: customer),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DailyDocChip extends StatelessWidget {
  const _DailyDocChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _salesBlue : _salesBlue.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _salesBlue.withValues(alpha: 0.24)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(
                  Icons.check_rounded,
                  color: AppColors.white,
                  size: 14,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.white : _salesBlue,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailySortSelector extends StatelessWidget {
  const _DailySortSelector({required this.selected, required this.onChanged});

  final _DailySalesSort selected;
  final ValueChanged<_DailySalesSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _salesBlue.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          _DailySortChip(
            label: 'Item Group',
            selected: selected == _DailySalesSort.itemGroup,
            onTap: () => onChanged(_DailySalesSort.itemGroup),
          ),
          _DailySortChip(
            label: 'Qty',
            selected: selected == _DailySalesSort.qty,
            onTap: () => onChanged(_DailySalesSort.qty),
          ),
          _DailySortChip(
            label: 'Omzet',
            selected: selected == _DailySalesSort.amount,
            onTap: () => onChanged(_DailySalesSort.amount),
          ),
        ],
      ),
    );
  }
}

class _DailySortChip extends StatelessWidget {
  const _DailySortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected ? _salesBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            height: 34,
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppColors.white : AppColors.slate,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyItemSummaryTable extends StatelessWidget {
  const _DailyItemSummaryTable({required this.report, required this.sort});

  final DailySalesReport report;
  final _DailySalesSort sort;

  List<DailySalesItemSummary> get _items {
    final items = [...report.items];
    items.sort((a, b) {
      switch (sort) {
        case _DailySalesSort.itemGroup:
          final groupComparison = a.itemGroup.compareTo(b.itemGroup);
          if (groupComparison != 0) return groupComparison;
          return a.itemLabel.compareTo(b.itemLabel);
        case _DailySalesSort.qty:
          final qtyComparison = b.qty.compareTo(a.qty);
          if (qtyComparison != 0) return qtyComparison;
          return a.itemLabel.compareTo(b.itemLabel);
        case _DailySalesSort.amount:
          final amountComparison = b.amount.compareTo(a.amount);
          if (amountComparison != 0) return amountComparison;
          return a.itemLabel.compareTo(b.itemLabel);
      }
    });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _salesBlue.withValues(alpha: 0.14)),
      ),
      child: Column(
        children: [
          const _DailySummaryRow(
            item: 'Item',
            qty: 'Qty',
            amount: 'Omzet',
            header: true,
          ),
          ...items.map(
            (item) => _DailySummaryRow(
              item: item.itemLabel,
              qty: _formatQty(item.qty),
              amount: 'Rp ${formatErpCurrency(item.amount)}',
            ),
          ),
          _DailySummaryRow(
            item: 'TOTAL SALES',
            qty: _formatQty(report.totalQty),
            amount: 'Rp ${formatErpCurrency(report.totalAmount)}',
            total: true,
          ),
        ],
      ),
    );
  }
}

class _DailySummaryRow extends StatelessWidget {
  const _DailySummaryRow({
    required this.item,
    required this.qty,
    required this.amount,
    this.header = false,
    this.total = false,
  });

  final String item;
  final String qty;
  final String amount;
  final bool header;
  final bool total;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: header ? AppColors.slate : AppColors.navy,
      fontSize: 12,
      fontWeight: header || total ? FontWeight.w900 : FontWeight.w700,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: total ? _salesBlue.withValues(alpha: 0.10) : Colors.transparent,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(item, style: style)),
          Expanded(
            child: Text(qty, textAlign: TextAlign.right, style: style),
          ),
          Expanded(
            flex: 2,
            child: Text(amount, textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}

class _DailyCustomerSalesCard extends StatelessWidget {
  const _DailyCustomerSalesCard({required this.customer});

  final DailySalesCustomerSummary customer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _salesBlue.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            customer.customer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Divider(height: 18),
          ...customer.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.itemLabel,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _formatQty(item.qty),
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Total : Rp ${formatErpCurrency(customer.totalAmount)}',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _salesBlue,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatQty(double value) {
  final fixed = value.truncateToDouble() == value
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return fixed.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
}

class _TopCustomerCard extends StatelessWidget {
  const _TopCustomerCard({required this.row});

  final SalesPersonCustomerRanking row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: row.rank <= 3
                ? _salesGreen.withValues(alpha: 0.16)
                : _salesGreen.withValues(alpha: 0.10),
            foregroundColor: _salesGreen,
            child: Text(
              '${row.rank}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${row.salesPerson} | ${row.orderCount} SO',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Rp ${formatErpCurrency(row.amount)}',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _salesGreen,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionRankingRow extends StatelessWidget {
  const _CollectionRankingRow({required this.row});

  final CollectionRanking row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: row.rank <= 3
                ? _salesGreen.withValues(alpha: 0.16)
                : _salesGreen.withValues(alpha: 0.10),
            foregroundColor: _salesGreen,
            child: Text(
              '${row.rank}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              row.salesPerson,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            'Rp ${formatErpCurrency(row.amount)}',
            style: const TextStyle(
              color: _salesGreen,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
