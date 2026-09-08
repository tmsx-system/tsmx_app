import '../../models/delivery_note.dart';
import '../../services/frappe_service.dart';
import '../../services/sales_visit_location_service.dart';
import '../app_state_proxy_notifier.dart';
import 'logistics_delivery_note_query_mixin.dart';

class LogisticsDeliveryState extends AppStateProxyNotifier
    with LogisticsDeliveryNoteQueryMixin {
  LogisticsDeliveryState({required super.appState}) {
    startWatchingAppState();
  }

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
    appState.sellingPeriodYear,
    appState.sellingPeriodMonth,
    appState.sellingCompanyFilter,
    appState.sellingCustomerTypeFilter,
    appState.currentSalesPerson,
    appState.activeDeliveryTrackingNote,
    appState.latestDeliveryTrackingNote,
    appState.latestDeliveryDriverLocation,
    appState.isDeliveryDriverTrackingActive,
  ];

  List<DeliveryNote> get deliveryNotes => _deliveryNotes;
  bool get isDeliveryNotesLoading => _isDeliveryNotesLoading;
  bool get isMoreDeliveryNotesLoading => _isMoreDeliveryNotesLoading;
  bool get hasMoreDeliveryNotes => _hasMoreDeliveryNotes;
  String? get deliveryNotesError => _deliveryNotesError;
  String? get activeDeliveryTrackingNote => appState.activeDeliveryTrackingNote;
  String? get latestDeliveryTrackingNote => appState.latestDeliveryTrackingNote;
  VisitLocationPoint? get latestDeliveryDriverLocation =>
      appState.latestDeliveryDriverLocation;
  bool get isDeliveryDriverTrackingActive =>
      appState.isDeliveryDriverTrackingActive;
  FrappeService get frappeService => appState.frappeService;

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
      final page = await fetchDeliveryNotePage(
        limitStart: _deliveryNotes.length,
        search: _deliveryNoteSearch,
        status: _deliveryNoteStatus,
      );
      if (version != _deliveryNoteQueryVersion) return;
      final ids = _deliveryNotes.map((note) => note.id).toSet();
      _deliveryNotes = [
        ..._deliveryNotes,
        ...page.where((note) => ids.add(note.id)),
      ];
      _hasMoreDeliveryNotes =
          page.length >= LogisticsDeliveryNoteQueryMixin.documentPageSize;
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

  Future<DeliveryNote> loadDeliveryNoteDetail(String id) async {
    final note = await fetchDeliveryNoteDetail(id);
    _replaceDeliveryNoteSnapshot(note);
    return note;
  }

  Future<List<Map<String, dynamic>>> fetchDocumentAttachments({
    required String doctype,
    required String documentName,
  }) {
    return appState.frappeService.fetchResource(
      'File',
      fields: const ['name', 'file_name', 'file_url', 'creation'],
      filters: [
        ['attached_to_doctype', '=', doctype],
        ['attached_to_name', '=', documentName],
      ],
      orderBy: 'creation desc',
      limit: 50,
    );
  }

  Future<void> uploadDeliveryNoteProof({
    required String deliveryNoteId,
    required String filePath,
  }) async {
    await appState.frappeService.uploadFile(
      doctype: 'Delivery Note',
      documentName: deliveryNoteId,
      filePath: filePath,
    );
  }

  Future<VisitLocationPoint> startDeliveryDriverTracking(
    DeliveryNote deliveryNote,
  ) {
    return appState.startDeliveryDriverTracking(deliveryNote);
  }

  Future<VisitLocationPoint> recordDeliveryDriverLocation(
    DeliveryNote deliveryNote,
  ) {
    return appState.recordDeliveryDriverLocation(deliveryNote);
  }

  Future<void> stopDeliveryDriverTracking() {
    return appState.stopDeliveryDriverTracking();
  }

  Future<void> _fetchDeliveryNotes() async {
    if (appState.isSampleMode) {
      _deliveryNotes = appState.deliveryNotes;
      _deliveryNotesError = null;
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
      final docs = await fetchDeliveryNotePage(
        limitStart: 0,
        search: _deliveryNoteSearch,
        status: _deliveryNoteStatus,
      );
      if (version != _deliveryNoteQueryVersion) return;
      _deliveryNotes = docs;
      _hasMoreDeliveryNotes =
          docs.length >= LogisticsDeliveryNoteQueryMixin.documentPageSize;
      _deliveryNotesError = null;
    } catch (error) {
      if (version != _deliveryNoteQueryVersion) return;
      _hasMoreDeliveryNotes = false;
      _deliveryNotesError = error.toString();
    } finally {
      if (version == _deliveryNoteQueryVersion) {
        _isDeliveryNotesLoading = false;
        notifyListeners();
      }
    }
  }

  void _replaceDeliveryNoteSnapshot(DeliveryNote note) {
    final index = _deliveryNotes.indexWhere((item) => item.id == note.id);
    if (index < 0) return;
    _deliveryNotes = List<DeliveryNote>.from(_deliveryNotes)..[index] = note;
    notifyListeners();
  }
}
