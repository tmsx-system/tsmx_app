import 'dart:async';

import '../../config/mobile_role_registry.dart';
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

  String? _openingProfileFilter;
  String? _openingStatusFilter;
  String? _invoiceProfileFilter;
  String? _invoiceStatusFilter;
  String? _closingProfileFilter;
  String? _closingStatusFilter;

  int _profilesVersion = 0;
  int _openingsVersion = 0;
  int _invoicesVersion = 0;
  int _closingsVersion = 0;

  Future<void>? _profilesInFlight;
  Future<void>? _openingsInFlight;
  Future<void>? _invoicesInFlight;
  Future<void>? _closingsInFlight;
  Future<Set<String>?>? _assignedProfilesInFlight;

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

  String? get openingProfileFilter => _openingProfileFilter;
  String? get openingStatusFilter => _openingStatusFilter;
  String? get invoiceProfileFilter => _invoiceProfileFilter;
  String? get invoiceStatusFilter => _invoiceStatusFilter;
  String? get closingProfileFilter => _closingProfileFilter;
  String? get closingStatusFilter => _closingStatusFilter;

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
    _profileSearch = '';
    _openingSearch = '';
    _invoiceSearch = '';
    _closingSearch = '';
    _openingProfileFilter = null;
    _openingStatusFilter = null;
    _invoiceProfileFilter = null;
    _invoiceStatusFilter = null;
    _closingProfileFilter = null;
    _closingStatusFilter = null;
    _profilesVersion++;
    _openingsVersion++;
    _invoicesVersion++;
    _closingsVersion++;
    _profilesInFlight = null;
    _openingsInFlight = null;
    _invoicesInFlight = null;
    _closingsInFlight = null;
    _assignedProfilesInFlight = null;
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

  Future<void> setOpeningProfileFilter(String? profile) async {
    final next = profile?.trim();
    final normalized = (next == null || next.isEmpty) ? null : next;
    if (_openingProfileFilter == normalized) return;
    _openingProfileFilter = normalized;
    _openingsInFlight = null;
    await refreshOpenings();
  }

  Future<void> setOpeningStatusFilter(String? status) async {
    final next = status?.trim();
    final normalized = (next == null || next.isEmpty) ? null : next;
    if (_openingStatusFilter == normalized) return;
    _openingStatusFilter = normalized;
    _openingsInFlight = null;
    await refreshOpenings();
  }

  Future<void> setInvoiceProfileFilter(String? profile) async {
    final next = profile?.trim();
    final normalized = (next == null || next.isEmpty) ? null : next;
    if (_invoiceProfileFilter == normalized) return;
    _invoiceProfileFilter = normalized;
    _invoicesInFlight = null;
    await refreshInvoices();
  }

  Future<void> setInvoiceStatusFilter(String? status) async {
    final next = status?.trim();
    final normalized = (next == null || next.isEmpty) ? null : next;
    if (_invoiceStatusFilter == normalized) return;
    _invoiceStatusFilter = normalized;
    _invoicesInFlight = null;
    await refreshInvoices();
  }

  Future<void> setClosingProfileFilter(String? profile) async {
    final next = profile?.trim();
    final normalized = (next == null || next.isEmpty) ? null : next;
    if (_closingProfileFilter == normalized) return;
    _closingProfileFilter = normalized;
    _closingsInFlight = null;
    await refreshClosings();
  }

  Future<void> setClosingStatusFilter(String? status) async {
    final next = status?.trim();
    final normalized = (next == null || next.isEmpty) ? null : next;
    if (_closingStatusFilter == normalized) return;
    _closingStatusFilter = normalized;
    _closingsInFlight = null;
    await refreshClosings();
  }

  Future<void> clearOpeningListFilters() async {
    _openingSearch = '';
    _openingProfileFilter = null;
    _openingStatusFilter = null;
    _openingsInFlight = null;
    await refreshOpenings();
  }

  Future<void> clearInvoiceListFilters() async {
    _invoiceSearch = '';
    _invoiceProfileFilter = null;
    _invoiceStatusFilter = null;
    _invoicesInFlight = null;
    await refreshInvoices();
  }

  Future<void> clearClosingListFilters() async {
    _closingSearch = '';
    _closingProfileFilter = null;
    _closingStatusFilter = null;
    _closingsInFlight = null;
    await refreshClosings();
  }

  Future<void> _fetchProfiles() async {
    final version = ++_profilesVersion;
    _profilesLoading = true;
    _profilesError = null;
    notifyListeners();
    try {
      final assigned = await _assignedPosProfileNames();
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
        filters: _profileNameFilters(assigned),
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
      final assigned = await _assignedPosProfileNames();
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
        filters: _mergeFilters([
          _posProfileLinkFilters(assigned),
          _exactProfileFilter(_openingProfileFilter),
          _statusFilter(_openingStatusFilter),
        ]),
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
      final assigned = await _assignedPosProfileNames();
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
        filters: _mergeFilters([
          _posProfileLinkFilters(assigned),
          _exactProfileFilter(_invoiceProfileFilter),
          _statusFilter(_invoiceStatusFilter),
        ]),
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
      final assigned = await _assignedPosProfileNames();
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
        filters: _mergeFilters([
          _posProfileLinkFilters(assigned),
          _exactProfileFilter(_closingProfileFilter),
          _statusFilter(_closingStatusFilter),
        ]),
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

  Future<Map<String, dynamic>> loadProfileDocument(String name) {
    return frappeService.fetchDocument('POS Profile', name);
  }

  List<String> paymentModesFromProfile(Map<String, dynamic> doc) {
    final raw = doc['payments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => row['mode_of_payment']?.toString().trim() ?? '')
        .where((mode) => mode.isNotEmpty)
        .toSet()
        .toList();
  }

  List<String> assignedUsersFromProfile(Map<String, dynamic> doc) {
    final raw = doc['applicable_for_users'] ?? doc['users'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => row['user']?.toString().trim() ?? '')
        .where((user) => user.isNotEmpty)
        .toSet()
        .toList();
  }

  bool isCurrentUserAssignedToProfile(Map<String, dynamic> doc) {
    final user = currentUser?.trim() ?? '';
    if (user.isEmpty) return false;
    final assigned = assignedUsersFromProfile(doc);
    if (assigned.isEmpty) return false;
    return assigned.any((item) => item.toLowerCase() == user.toLowerCase());
  }

  Future<PosOpeningEntry> loadOpeningDetail(String name) async {
    final doc = await frappeService.fetchDocument('POS Opening Entry', name);
    return PosOpeningEntry.fromJson(doc);
  }

  Future<Map<String, dynamic>> loadOpeningDocument(String name) {
    return frappeService.fetchDocument('POS Opening Entry', name);
  }

  Future<Map<String, dynamic>> loadInvoiceDocument(String name) {
    return frappeService.fetchDocument('POS Invoice', name);
  }

  Future<Map<String, dynamic>> loadClosingDocument(String name) {
    return frappeService.fetchDocument('POS Closing Entry', name);
  }

  Future<PosInvoice> loadInvoiceDetail(String name) async {
    final doc = await frappeService.fetchDocument('POS Invoice', name);
    return PosInvoice.fromJson(doc);
  }

  Future<PosClosingEntry> loadClosingDetail(String name) async {
    final doc = await frappeService.fetchDocument('POS Closing Entry', name);
    return PosClosingEntry.fromJson(doc);
  }

  /// Fetch submitted POS Invoices for a closing session (ERPNext v14+ helper).
  Future<List<Map<String, dynamic>>> fetchPosInvoicesForClosing({
    required String start,
    required String end,
    required String posProfile,
    required String user,
  }) async {
    try {
      final result = await frappeService.callMethod(
        'erpnext.accounts.doctype.pos_closing_entry.pos_closing_entry.get_pos_invoices',
        args: {
          'start': start,
          'end': end,
          'pos_profile': posProfile,
          'user': user,
        },
      );
      if (result is List) {
        return [
          for (final row in result)
            if (row is Map) Map<String, dynamic>.from(row),
        ];
      }
    } catch (_) {}

    // Newer ERPNext may expose get_invoices instead.
    try {
      final result = await frappeService.callMethod(
        'erpnext.accounts.doctype.pos_closing_entry.pos_closing_entry.get_invoices',
        args: {
          'start': start,
          'end': end,
          'pos_profile': posProfile,
          'user': user,
        },
      );
      if (result is Map) {
        final invoices = result['invoices'];
        if (invoices is List) {
          return [
            for (final row in invoices)
              if (row is Map)
                {
                  ...Map<String, dynamic>.from(row),
                  'name': row['name'] ?? row['pos_invoice'] ?? row['sales_invoice'],
                },
          ];
        }
      }
    } catch (_) {}

    // Fallback: list POS Invoice via resource API.
    final rows = await frappeService.fetchResource(
      'POS Invoice',
      fields: const [
        'name',
        'customer',
        'posting_date',
        'posting_time',
        'grand_total',
        'net_total',
        'total_qty',
        'pos_profile',
        'owner',
        'consolidated_invoice',
      ],
      filters: [
        ['docstatus', '=', 1],
        ['pos_profile', '=', posProfile],
        ['owner', '=', user],
      ],
      orderBy: 'posting_date asc, posting_time asc',
      limit: 200,
    );

    DateTime? parseStamp(Map<String, dynamic> row) {
      final date = row['posting_date']?.toString() ?? '';
      final time = row['posting_time']?.toString() ?? '00:00:00';
      final normalizedTime = time.length == 5 ? '$time:00' : time;
      return DateTime.tryParse('$date $normalizedTime'.replaceFirst(' ', 'T'));
    }

    final startDt = DateTime.tryParse(start.replaceFirst(' ', 'T'));
    final endDt = DateTime.tryParse(end.replaceFirst(' ', 'T'));
    final filtered = rows.where((row) {
      final consolidated = row['consolidated_invoice']?.toString().trim() ?? '';
      if (consolidated.isNotEmpty) return false;
      final stamp = parseStamp(row);
      if (stamp == null) return true;
      if (startDt != null && stamp.isBefore(startDt)) return false;
      if (endDt != null && stamp.isAfter(endDt)) return false;
      return true;
    }).toList();

    final detailed = <Map<String, dynamic>>[];
    for (final row in filtered) {
      final name = row['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      try {
        detailed.add(await loadInvoiceDocument(name));
      } catch (_) {
        detailed.add(row);
      }
    }
    return detailed;
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

  Future<void> updateOpeningEntry(
    String name,
    Map<String, dynamic> payload,
  ) async {
    await frappeService.updateDocument(
      'POS Opening Entry',
      name,
      payload,
    );
    unawaited(refreshOpenings());
  }

  Future<void> updateInvoice(
    String name,
    Map<String, dynamic> payload,
  ) async {
    await frappeService.updateDocument(
      'POS Invoice',
      name,
      payload,
    );
    unawaited(refreshInvoices());
  }

  Future<void> updateClosingEntry(
    String name,
    Map<String, dynamic> payload,
  ) async {
    await frappeService.updateDocument(
      'POS Closing Entry',
      name,
      payload,
    );
    unawaited(refreshClosings());
  }

  Future<void> submitPosDocument(String doctype, String name) async {
    await frappeService.submitDocument(doctype, name);
    await _refreshDoctype(doctype);
  }

  Future<void> cancelPosDocument(String doctype, String name) async {
    await frappeService.cancelDocument(doctype, name);
    await _refreshDoctype(doctype);
  }

  Future<void> deletePosDocument(String doctype, String name) async {
    await frappeService.deleteDocument(doctype, name);
    await _refreshDoctype(doctype);
  }

  Future<String> amendPosDocument(String doctype, String name) async {
    final source = await frappeService.fetchDocument(doctype, name);
    final payload = Map<String, dynamic>.from(source);
    const dropKeys = {
      'name',
      'owner',
      'creation',
      'modified',
      'modified_by',
      'docstatus',
      'idx',
      '_user_tags',
      '_comments',
      '_assign',
      '_liked_by',
      'status',
    };
    payload.removeWhere((key, _) => dropKeys.contains(key));
    payload['amended_from'] = name;
    payload['docstatus'] = 0;

    void scrubChildren(String key) {
      final raw = payload[key];
      if (raw is! List) return;
      payload[key] = [
        for (final row in raw)
          if (row is Map)
            () {
              final copy = Map<String, dynamic>.from(row);
              copy.remove('name');
              copy.remove('owner');
              copy.remove('creation');
              copy.remove('modified');
              copy.remove('modified_by');
              copy.remove('parent');
              copy.remove('parenttype');
              copy.remove('parentfield');
              copy.remove('docstatus');
              return copy;
            }()
          else
            row,
      ];
    }

    scrubChildren('balance_details');
    scrubChildren('payment_reconciliation');
    scrubChildren('pos_transactions');
    scrubChildren('pos_invoices');
    scrubChildren('payments');
    scrubChildren('items');
    scrubChildren('sales_team');
    scrubChildren('taxes');

    final created = await frappeService.createDocument(doctype, payload);
    await _refreshDoctype(doctype);
    return created['name']?.toString() ?? '';
  }

  Future<List<int>> downloadPosPdf(String doctype, String name) async {
    final format = await frappeService.resolvePrintFormat(
      doctype,
      preferred: doctype == 'POS Invoice' ? 'Struk POS' : null,
    );
    try {
      return await frappeService.downloadPrintPdf(
        doctype: doctype,
        name: name,
        printFormat: format,
        noLetterhead: true,
      );
    } catch (_) {
      return frappeService.downloadPrintPdf(
        doctype: doctype,
        name: name,
        noLetterhead: true,
      );
    }
  }

  Future<bool> canWriteDoctype(String doctype) =>
      appState.canWriteDoctype(doctype);
  Future<bool> canSubmitDoctype(String doctype) =>
      appState.canSubmitDoctype(doctype);
  Future<bool> canDeleteDoctype(String doctype) =>
      appState.canDeleteDoctype(doctype);
  Future<bool> canCancelDoctype(String doctype) =>
      appState.canCancelDoctype(doctype);
  Future<bool> canAmendDoctype(String doctype) =>
      appState.canAmendDoctype(doctype);
  Future<bool> canPrintDoctype(String doctype) =>
      appState.canPrintDoctype(doctype);

  Future<void> _refreshDoctype(String doctype) async {
    switch (doctype) {
      case 'POS Opening Entry':
        await refreshOpenings();
      case 'POS Invoice':
        await refreshInvoices();
      case 'POS Closing Entry':
        await refreshClosings();
    }
  }

  Future<List<String>> fetchSelectableProfileNames() async {
    final assigned = await _assignedPosProfileNames();
    return fetchNames(
      'POS Profile',
      filters: [
        ['disabled', '=', 0],
        ...?_profileNameFilters(assigned),
      ],
    );
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

  Future<List<String>> fetchCompanyOptions({String? preferred}) async {
    final names = <String>{};

    void add(String? value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) names.add(trimmed);
    }

    for (final company in appState.mobileBoot?.companies ?? const <String>[]) {
      add(company);
    }
    add(appState.mobileBoot?.defaultCompany);
    add(appState.currentEmployeeProfile['company']?.toString());
    for (final entry in appState.stockCompanies) {
      add(entry.key);
    }
    for (final company in appState.sellingCompanies) {
      add(company);
    }
    for (final company in appState.buyingCompanies) {
      add(company);
    }
    add(preferred);

    try {
      for (final company in await fetchNames('Company')) {
        add(company);
      }
    } catch (_) {
      // Company doctype may be restricted; local lists above are enough.
    }

    try {
      final profiles = await fetchSelectableProfileNames();
      for (final profileName in profiles.take(20)) {
        try {
          final doc = await loadProfileDocument(profileName);
          add(doc['company']?.toString());
        } catch (_) {}
      }
    } catch (_) {}

    final list = names.toList()..sort();
    return list;
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

  /// Resolve selling rate from POS price list / ERPNext pricing rules.
  Future<({double rate, double discountAmount})> resolveItemSellingRate({
    required String itemCode,
    String? customer,
    String? company,
    String? priceList,
    String? warehouse,
    DateTime? postingDate,
    double qty = 1,
  }) async {
    try {
      final insight = await appState.fetchItemSalesInsight(
        itemCode,
        customer: customer,
        company: company,
        priceList: priceList,
        warehouse: warehouse,
        transactionDate: postingDate,
        qty: qty,
      );
      final rate = insight.priceListRate > 0
          ? insight.priceListRate
          : insight.price;
      return (rate: rate, discountAmount: insight.discountAmount);
    } catch (_) {
      final filters = <List<dynamic>>[
        ['item_code', '=', itemCode],
        ['selling', '=', 1],
        if (priceList != null && priceList.trim().isNotEmpty)
          ['price_list', '=', priceList.trim()],
      ];
      final rows = await fetchLinkOptions(
        'Item Price',
        fields: const ['name', 'price_list_rate'],
        filters: filters,
        orderBy: 'modified desc',
      );
      final rate = rows.isEmpty
          ? 0.0
          : (double.tryParse(rows.first['price_list_rate']?.toString() ?? '') ??
                0);
      return (rate: rate, discountAmount: 0.0);
    }
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

  List<List<dynamic>>? _profileNameFilters(Set<String>? assigned) {
    if (assigned == null || assigned.isEmpty) return null;
    return [
      ['name', 'in', assigned.toList()],
    ];
  }

  List<List<dynamic>>? _posProfileLinkFilters(Set<String>? assigned) {
    if (assigned == null || assigned.isEmpty) return null;
    return [
      ['pos_profile', 'in', assigned.toList()],
    ];
  }

  List<List<dynamic>>? _exactProfileFilter(String? profile) {
    final value = profile?.trim() ?? '';
    if (value.isEmpty) return null;
    return [
      ['pos_profile', '=', value],
    ];
  }

  List<List<dynamic>>? _statusFilter(String? status) {
    final value = status?.trim() ?? '';
    if (value.isEmpty) return null;
    final lower = value.toLowerCase();
    if (lower == 'draft') {
      return [
        ['docstatus', '=', 0],
      ];
    }
    if (lower == 'cancelled') {
      return [
        ['docstatus', '=', 2],
      ];
    }
    return [
      ['status', '=', value],
    ];
  }

  List<List<dynamic>>? _mergeFilters(List<List<List<dynamic>>?> parts) {
    final merged = <List<dynamic>>[
      for (final part in parts)
        if (part != null)
          for (final filter in part) filter,
    ];
    return merged.isEmpty ? null : merged;
  }

  /// Null/empty = user is not assigned anywhere, so all readable POS data is shown.
  Future<Set<String>?> _assignedPosProfileNames() {
    final inFlight = _assignedProfilesInFlight;
    if (inFlight != null) return inFlight;
    final request = _loadAssignedPosProfileNames();
    _assignedProfilesInFlight = request;
    return request;
  }

  Future<Set<String>?> _loadAssignedPosProfileNames() async {
    if (appState.isSampleMode) return null;
    if (MobileRoleRegistry.isFullAccessRole(appState.userRole)) return null;
    final user = currentUser?.trim() ?? '';
    if (user.isEmpty) return null;

    try {
      final fromNested = await frappeService.fetchResource(
        'POS Profile',
        fields: const ['name'],
        filters: [
          ['POS Profile User', 'user', '=', user],
        ],
        limit: 200,
      );
      final nestedNames = {
        for (final row in fromNested)
          if ((row['name']?.toString() ?? '').trim().isNotEmpty)
            row['name'].toString().trim(),
      };
      if (nestedNames.isNotEmpty) return nestedNames;
    } catch (_) {}

    try {
      final fromChild = await frappeService.fetchResource(
        'POS Profile User',
        fields: const ['parent', 'user'],
        filters: [
          ['user', '=', user],
        ],
        limit: 200,
      );
      final names = _parentNamesFromRows(fromChild);
      if (names.isNotEmpty) return names;
    } catch (_) {}

    return null;
  }

  Set<String> _parentNamesFromRows(List<Map<String, dynamic>> rows) {
    return {
      for (final row in rows)
        if ((row['parent']?.toString() ?? '').trim().isNotEmpty)
          row['parent'].toString().trim(),
    };
  }
}
