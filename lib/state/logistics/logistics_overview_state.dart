import '../../models/delivery_note.dart';
import '../app_state_proxy_notifier.dart';
import 'logistics_delivery_note_query_mixin.dart';

class LogisticsOverviewState extends AppStateProxyNotifier
    with LogisticsDeliveryNoteQueryMixin {
  LogisticsOverviewState({required super.appState}) {
    startWatchingAppState();
  }

  List<DeliveryNote> _deliveryNotes = const [];
  bool _isDeliveryNotesLoading = false;
  String? _deliveryNotesError;
  Future<void>? _deliveryNotesFetchInFlight;

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.canUseLogistics,
    appState.sellingPeriodYear,
    appState.sellingPeriodMonth,
    appState.sellingCompanyFilter,
    appState.sellingCustomerTypeFilter,
    appState.currentSalesPerson,
  ];

  List<DeliveryNote> get deliveryNotes => _deliveryNotes;
  bool get isDeliveryNotesLoading => _isDeliveryNotesLoading;
  String? get deliveryNotesError => _deliveryNotesError;

  Future<bool> canReadDoctype(String doctype) {
    return appState.canReadDoctype(doctype);
  }

  Future<bool> canWriteDoctype(String doctype) {
    return appState.canWriteDoctype(doctype);
  }

  Future<bool> canCreateDoctype(String doctype) {
    return appState.canCreateDoctype(doctype);
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
      _deliveryNotesError = null;
      notifyListeners();
      return;
    }

    _isDeliveryNotesLoading = true;
    _deliveryNotesError = null;
    notifyListeners();

    try {
      await appState.frappeService.ensureLoggedIn();
      _deliveryNotes = await fetchDeliveryNotePage(limitStart: 0);
      _deliveryNotesError = null;
    } catch (error) {
      _deliveryNotesError = error.toString();
    } finally {
      _isDeliveryNotesLoading = false;
      notifyListeners();
    }
  }
}
