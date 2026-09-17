import 'dart:async';

import '../../models/pos_closing_entry.dart';
import '../../models/pos_invoice.dart';
import '../../models/pos_opening_entry.dart';
import '../../models/pos_profile.dart';
import '../../services/frappe_service.dart';
import '../app_state_proxy_notifier.dart';

class PosState extends AppStateProxyNotifier {
  PosState({required super.appState}) {
    startWatchingAppState();
  }

  static const int _pageSize = 50;

  List<PosProfile> _profiles = const [];
  List<PosOpeningEntry> _openings = const [];
  List<PosInvoice> _invoices = const [];
  List<PosClosingEntry> _closings = const [];

  bool _profilesLoading = false;
  bool _openingsLoading = false;
  bool _invoicesLoading = false;
  bool _closingsLoading = false;

  String? _profilesError;
  String? _openingsError;
  String? _invoicesError;
  String? _closingsError;

  String _profileSearch = '';
  String _openingSearch = '';
  String _invoiceSearch = '';
  String _closingSearch = '';

  int _profilesVersion = 0;
  int _openingsVersion = 0;
  int _invoicesVersion = 0;
  int _closingsVersion = 0;

  Future<void>? _profilesInFlight;
  Future<void>? _openingsInFlight;
  Future<void>? _invoicesInFlight;
  Future<void>? _closingsInFlight;

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.selectedSiteBaseUrl,
    appState.currentUser,
  ];

  FrappeService get frappeService => appState.frappeService;
  String? get currentUser => appState.currentUser;

  List<PosProfile> get profiles => _profiles;
  List<PosOpeningEntry> get openings => _openings;
  List<PosInvoice> get invoices => _invoices;
  List<PosClosingEntry> get closings => _closings;

  bool get profilesLoading => _profilesLoading;
  bool get openingsLoading => _openingsLoading;
  bool get invoicesLoading => _invoicesLoading;
  bool get closingsLoading => _closingsLoading;

  String? get profilesError => _profilesError;
  String? get openingsError => _openingsError;
  String? get invoicesError => _invoicesError;
  String? get closingsError => _closingsError;

  @override
  void handleWatchedFieldsChanged(List<Object?> previous, List<Object?> next) {
    if (didAuthScopeChange(
      previous,
      next,
      authIndex: 0,
      siteIndex: 2,
      userIndex: 3,
    )) {
      _resetAll();
    }
  }

  void _resetAll() {
    _profiles = const [];
    _openings = const [];
    _invoices = const [];
    _closings = const [];
    _profilesError = null;
    _openingsError = null;
    _invoicesError = null;
    _closingsError = null;
    _profilesVersion++;
    _openingsVersion++;
    _invoicesVersion++;
    _closingsVersion++;
    _profilesInFlight = null;
    _openingsInFlight = null;
    _invoicesInFlight = null;
    _closingsInFlight = null;
  }

  Future<void> refreshProfiles() {
    final inFlight = _profilesInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchProfiles();
    _profilesInFlight = request;
    return request.whenComplete(() {
      if (identical(_profilesInFlight, request)) _profilesInFlight = null;
    });
  }

  Future<void> refreshOpenings() {
    final inFlight = _openingsInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchOpenings();
    _openingsInFlight = request;
    return request.whenComplete(() {
      if (identical(_openingsInFlight, request)) _openingsInFlight = null;
    });
  }

  Future<void> refreshInvoices() {
    final inFlight = _invoicesInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchInvoices();
    _invoicesInFlight = request;
    return request.whenComplete(() {
      if (identical(_invoicesInFlight, request)) _invoicesInFlight = null;
    });
  }

  Future<void> refreshClosings() {
    final inFlight = _closingsInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchClosings();
    _closingsInFlight = request;
    return request.whenComplete(() {
      if (identical(_closingsInFlight, request)) _closingsInFlight = null;
    });
  }

  Future<void> setProfileSearch(String value) async {
    final next = value.trim();
    if (_profileSearch == next) return;
    _profileSearch = next;
    _profilesInFlight = null;
    await refreshProfiles();
  }

  Future<void> setOpeningSearch(String value) async {
    final next = value.trim();
    if (_openingSearch == next) return;
    _openingSearch = next;
    _openingsInFlight = null;
    await refreshOpenings();
  }

  Future<void> setInvoiceSearch(String value) async {
    final next = value.trim();
    if (_invoiceSearch == next) return;
    _invoiceSearch = next;
    _invoicesInFlight = null;
    await refreshInvoices();
  }

  Future<void> setClosingSearch(String value) async {
    final next = value.trim();
    if (_closingSearch == next) return;
    _closingSearch = next;
    _closingsInFlight = null;
    await refreshClosings();
  }

  Future<void> _fetchProfiles() async {
    final version = ++_profilesVersion;
    _profilesLoading = true;
    _profilesError = null;
    notifyListeners();
    try {
      final rows = await _fetchWithFieldFallback(
        doctype: 'POS Profile',
        fields: const [
          'name',
          'company',
          'warehouse',
          'customer',
          'selling_price_list',
          'currency',
          'disabled',
          'modified',
        ],
        orderBy: 'modified desc',
        orFilters: _searchFilters(_profileSearch, const ['name', 'company']),
      );
      if (version != _profilesVersion) return;
      _profiles = rows.map(PosProfile.fromJson).toList();
    } catch (error) {
      if (version != _profilesVersion) return;
      _profilesError = error.toString();
    } finally {
      if (version == _profilesVersion) {
        _profilesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _fetchOpenings() async {
    final version = ++_openingsVersion;
    _openingsLoading = true;
    _openingsError = null;
    notifyListeners();
    try {
      final rows = await _fetchWithFieldFallback(
        doctype: 'POS Opening Entry',
        fields: const [
          'name',
          'company',
          'pos_profile',
          'user',
          'period_start_date',
          'posting_date',
          'status',
          'docstatus',
          'modified',
        ],
        orderBy: 'period_start_date desc, name desc',
        orFilters: _searchFilters(_openingSearch, const [
          'name',
          'pos_profile',
          'user',
        ]),
      );
      if (version != _openingsVersion) return;
      _openings = rows.map(PosOpeningEntry.fromJson).toList();
    } catch (error) {
      if (version != _openingsVersion) return;
      _openingsError = error.toString();
    } finally {
      if (version == _openingsVersion) {
        _openingsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _fetchInvoices() async {
    final version = ++_invoicesVersion;
    _invoicesLoading = true;
    _invoicesError = null;
    notifyListeners();
    try {
      final rows = await _fetchWithFieldFallback(
        doctype: 'POS Invoice',
        fields: const [
          'name',
          'customer',
          'customer_name',
          'company',
          'pos_profile',
          'posting_date',
          'grand_total',
          'outstanding_amount',
          'status',
          'docstatus',
          'is_pos',
          'owner',
        ],
        orderBy: 'posting_date desc, name desc',
        orFilters: _searchFilters(_invoiceSearch, const [
          'name',
          'customer',
          'customer_name',
          'pos_profile',
        ]),
      );
      if (version != _invoicesVersion) return;
      _invoices = rows.map(PosInvoice.fromJson).toList();
    } catch (error) {
      if (version != _invoicesVersion) return;
      _invoicesError = error.toString();
    } finally {
      if (version == _invoicesVersion) {
        _invoicesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _fetchClosings() async {
    final version = ++_closingsVersion;
    _closingsLoading = true;
    _closingsError = null;
    notifyListeners();
    try {
      final rows = await _fetchWithFieldFallback(
        doctype: 'POS Closing Entry',
        fields: const [
          'name',
          'company',
          'pos_profile',
          'user',
          'pos_opening_entry',
          'period_start_date',
          'period_end_date',
          'posting_date',
          'status',
          'docstatus',
          'grand_total',
          'modified',
        ],
        orderBy: 'period_end_date desc, name desc',
        orFilters: _searchFilters(_closingSearch, const [
          'name',
          'pos_profile',
          'user',
        ]),
      );
      if (version != _closingsVersion) return;
      _closings = rows.map(PosClosingEntry.fromJson).toList();
    } catch (error) {
      if (version != _closingsVersion) return;
      _closingsError = error.toString();
    } finally {
      if (version == _closingsVersion) {
        _closingsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<PosProfile> loadProfileDetail(String name) async {
    final doc = await frappeService.fetchDocument('POS Profile', name);
    return PosProfile.fromJson(doc);
  }

  Future<PosOpeningEntry> loadOpeningDetail(String name) async {
    final doc = await frappeService.fetchDocument('POS Opening Entry', name);
    return PosOpeningEntry.fromJson(doc);
  }

  Future<PosInvoice> loadInvoiceDetail(String name) async {
    final doc = await frappeService.fetchDocument('POS Invoice', name);
    return PosInvoice.fromJson(doc);
  }

  Future<PosClosingEntry> loadClosingDetail(String name) async {
    final doc = await frappeService.fetchDocument('POS Closing Entry', name);
    return PosClosingEntry.fromJson(doc);
  }

  Future<PosOpeningEntry> createOpeningEntry(Map<String, dynamic> payload) async {
    final created = await frappeService.createDocument(
      'POS Opening Entry',
      payload,
    );
    final entry = PosOpeningEntry.fromJson(created);
    _openings = [entry, ..._openings.where((row) => row.id != entry.id)];
    notifyListeners();
    unawaited(refreshOpenings());
    return entry;
  }

  Future<PosInvoice> createInvoice(Map<String, dynamic> payload) async {
    final created = await frappeService.createDocument('POS Invoice', payload);
    final invoice = PosInvoice.fromJson(created);
    _invoices = [invoice, ..._invoices.where((row) => row.id != invoice.id)];
    notifyListeners();
    unawaited(refreshInvoices());
    return invoice;
  }

  Future<PosClosingEntry> createClosingEntry(
    Map<String, dynamic> payload,
  ) async {
    final created = await frappeService.createDocument(
      'POS Closing Entry',
      payload,
    );
    final entry = PosClosingEntry.fromJson(created);
    _closings = [entry, ..._closings.where((row) => row.id != entry.id)];
    notifyListeners();
    unawaited(refreshClosings());
    return entry;
  }

  Future<List<String>> fetchNames(
    String doctype, {
    List<List<dynamic>>? filters,
    String orderBy = 'name asc',
  }) async {
    final rows = await frappeService.fetchResource(
      doctype,
      fields: const ['name'],
      filters: filters,
      orderBy: orderBy,
      limit: 200,
    );
    return rows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchLinkOptions(
    String doctype, {
    List<String> fields = const ['name'],
    List<List<dynamic>>? filters,
    String orderBy = 'name asc',
  }) {
    return frappeService.fetchResource(
      doctype,
      fields: fields,
      filters: filters,
      orderBy: orderBy,
      limit: 200,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchWithFieldFallback({
    required String doctype,
    required List<String> fields,
    String? orderBy,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
  }) async {
    var activeFields = List<String>.from(fields);
    while (true) {
      try {
        return await frappeService.fetchResource(
          doctype,
          fields: activeFields,
          limit: _pageSize,
          orderBy: orderBy,
          filters: filters,
          orFilters: orFilters,
        );
      } catch (error) {
        final message = error.toString();
        final dropped = _dropRejectedField(activeFields, message);
        if (!dropped) rethrow;
      }
    }
  }

  bool _dropRejectedField(List<String> fields, String message) {
    final lower = message.toLowerCase();
    if (!lower.contains('field') && !lower.contains('not permitted')) {
      return false;
    }
    for (var i = fields.length - 1; i >= 0; i--) {
      final field = fields[i];
      if (field == 'name') continue;
      if (lower.contains(field.toLowerCase())) {
        fields.removeAt(i);
        return true;
      }
    }
    if (fields.length > 1) {
      fields.removeLast();
      return true;
    }
    return false;
  }

  List<List<dynamic>>? _searchFilters(String search, List<String> fields) {
    final q = search.trim();
    if (q.isEmpty || fields.isEmpty) return null;
    return [
      for (final field in fields) [field, 'like', '%$q%'],
    ];
  }
}
