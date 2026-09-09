import '../../models/delivery_note.dart';
import '../app_state_proxy_notifier.dart';
import 'selling_document_query_mixin.dart';
import 'selling_filter_state.dart';

class DeliveryNoteState extends AppStateProxyNotifier
    with SellingDocumentQueryMixin {
  DeliveryNoteState({required super.appState, required this.filterState}) {
    startWatchingAppState();
  }

  SellingFilterState filterState;

  @override
  SellingFilterState get sellingFilterState => filterState;

  List<DeliveryNote> _deliveryNotes = const [];
  bool _isDeliveryNotesLoading = false;
  bool _isMoreDeliveryNotesLoading = false;
  bool _hasMoreDeliveryNotes = true;
  String? _deliveryNotesError;
  String _deliveryNoteSearch = '';
  String? _deliveryNoteStatus;
  int _deliveryNoteQueryVersion = 0;
  Future<void>? _deliveryNotesFetchInFlight;

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.mobileBoot,
    appState.currentSalesPerson,
  ];

  int get sellingPeriodYear => filterState.sellingPeriodYear;
  int get sellingPeriodMonth => filterState.sellingPeriodMonth;

  List<DeliveryNote> get deliveryNotes => _deliveryNotes;
  bool get isDeliveryNotesLoading => _isDeliveryNotesLoading;
  bool get isMoreDeliveryNotesLoading => _isMoreDeliveryNotesLoading;
  bool get hasMoreDeliveryNotes => _hasMoreDeliveryNotes;
  String? get deliveryNotesError => _deliveryNotesError;

  void updateFilterState(SellingFilterState value) {
    filterState = value;
  }

  Future<void> refreshDeliveryNotes() {
    final inFlight = _deliveryNotesFetchInFlight;
    if (inFlight != null) return inFlight;
    final request = _fetchDeliveryNotes();
    _deliveryNotesFetchInFlight = request;
    return request.whenComplete(() {
      if (identical(_deliveryNotesFetchInFlight, request)) {
        _deliveryNotesFetchInFlight = null;
      }
    });
  }

  Future<void> _fetchDeliveryNotes() async {
    if (appState.isSampleMode) {
      _deliveryNotes = appState.deliveryNotes;
      notifyListeners();
      return;
    }

    _isDeliveryNotesLoading = true;
    _deliveryNotesError = null;
    _hasMoreDeliveryNotes = true;
    _isMoreDeliveryNotesLoading = false;
    final version = ++_deliveryNoteQueryVersion;
    notifyListeners();

    try {
      await appState.frappeService.ensureLoggedIn();
      final docs = await _fetchDeliveryNotePage(limitStart: 0);
      if (version != _deliveryNoteQueryVersion) return;
      _deliveryNotes = docs;
      _hasMoreDeliveryNotes =
          docs.length >= SellingDocumentQueryMixin.documentPageSize;
      _deliveryNotesError = null;
    } catch (error) {
      if (version != _deliveryNoteQueryVersion) return;
      _deliveryNotesError = error.toString();
    } finally {
      if (version == _deliveryNoteQueryVersion) {
        _isDeliveryNotesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreDeliveryNotes() async {
    if (_isDeliveryNotesLoading ||
        _isMoreDeliveryNotesLoading ||
        !_hasMoreDeliveryNotes) {
      return;
    }
    _isMoreDeliveryNotesLoading = true;
    final version = _deliveryNoteQueryVersion;
    notifyListeners();
    try {
      final page = await _fetchDeliveryNotePage(
        limitStart: _deliveryNotes.length,
      );
      if (version != _deliveryNoteQueryVersion) return;
      final ids = _deliveryNotes.map((note) => note.id).toSet();
      _deliveryNotes = [
        ..._deliveryNotes,
        ...page.where((note) => ids.add(note.id)),
      ];
      _hasMoreDeliveryNotes =
          page.length >= SellingDocumentQueryMixin.documentPageSize;
      _deliveryNotesError = null;
    } catch (error) {
      if (version != _deliveryNoteQueryVersion) return;
      _deliveryNotesError = error.toString();
    } finally {
      if (version == _deliveryNoteQueryVersion) {
        _isMoreDeliveryNotesLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setDeliveryNoteQuery({String? search, String? status}) async {
    final nextSearch = search?.trim() ?? _deliveryNoteSearch;
    final nextStatus = status;
    if (_deliveryNoteSearch == nextSearch &&
        _deliveryNoteStatus == nextStatus) {
      return;
    }
    _deliveryNoteSearch = nextSearch;
    _deliveryNoteStatus = nextStatus;
    _deliveryNotesFetchInFlight = null;
    await refreshDeliveryNotes();
  }

  Future<List<DeliveryNote>> _fetchDeliveryNotePage({
    required int limitStart,
  }) async {
    final filters = <List<dynamic>>[
      ...sellingPeriodFilters('posting_date'),
      ...?statusFilters(_deliveryNoteStatus),
      ...?await salesDocumentScopeFilters(),
    ];
    final rows = await fetchResourceWithFieldFallback(
      doctype: 'Delivery Note',
      fields: const [
        'name',
        'owner',
        'customer',
        'customer_name',
        'status',
        'docstatus',
        'posting_date',
        'base_net_total',
        'net_total',
        'grand_total',
        'total_qty',
      ],
      limit: SellingDocumentQueryMixin.documentPageSize,
      limitStart: limitStart,
      orderBy: 'posting_date desc, name desc',
      filters: filters,
      orFilters: searchFilters(_deliveryNoteSearch, const [
        'name',
        'customer',
        'customer_name',
      ]),
    );
    return rows.map(DeliveryNote.fromJson).toList();
  }

  Future<DeliveryNote> loadDeliveryNoteDetail(String id) async {
    await appState.frappeService.ensureLoggedIn();
    final doc = await appState.frappeService.fetchDocument('Delivery Note', id);
    final note = DeliveryNote.fromJson(doc);
    final index = _deliveryNotes.indexWhere((item) => item.id == note.id);
    if (index >= 0) {
      _deliveryNotes = List<DeliveryNote>.from(_deliveryNotes)..[index] = note;
      notifyListeners();
    }
    return note;
  }

  Future<void> submitDocument(String doctype, String name) async {
    await appState.frappeService.submitDocument(doctype, name);
    await refreshDeliveryNotes();
  }
}
