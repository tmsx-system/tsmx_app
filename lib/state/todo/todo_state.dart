import 'dart:async';

import '../../models/erp_approval_todo.dart';
import '../../models/sales_order_approval.dart';
import '../../services/domains/approval_service.dart';
import '../app_state_proxy_notifier.dart';

class TodoState extends AppStateProxyNotifier {
  TodoState({required super.appState}) {
    _approvalService = ApprovalService(frappe: appState.frappeService);
    startWatchingAppState();
  }

  late final ApprovalService _approvalService;

  @override
  List<Object?> get watchFields => [
    appState.isAuthenticated,
    appState.isSampleMode,
    appState.mobileAccess,
    appState.currentUser,
  ];

  List<ErpApprovalTodo> _cachedApprovalTodos = const [];
  int _approvalTodoCount = 0;
  int _purchaseApprovalTodoCount = 0;
  Future<List<ErpApprovalTodo>>? _approvalTodoFetchInFlight;

  String? get currentUser => appState.currentUser;
  List<ErpApprovalTodo> get cachedApprovalTodos =>
      List<ErpApprovalTodo>.unmodifiable(_cachedApprovalTodos);
  int get approvalTodoCount => _approvalTodoCount;
  int get purchaseApprovalTodoCount => _purchaseApprovalTodoCount;

  Future<List<ErpApprovalTodo>> fetchApprovalTodos({
    bool forceRefresh = false,
  }) async {
    if (appState.isSampleMode) {
      final todos = appState.cachedApprovalTodos;
      _setApprovalTodoSnapshot(todos);
      return cachedApprovalTodos;
    }

    final inFlight = _approvalTodoFetchInFlight;
    if (inFlight != null && !forceRefresh) return inFlight;

    final request = _approvalService.fetchApprovalTodos(
      currentUser: currentUser,
      forceRefresh: forceRefresh,
    );
    _approvalTodoFetchInFlight = request;
    try {
      final todos = await request;
      _setApprovalTodoSnapshot(todos);
      return cachedApprovalTodos;
    } finally {
      if (identical(_approvalTodoFetchInFlight, request)) {
        _approvalTodoFetchInFlight = null;
      }
    }
  }

  Future<List<ErpApprovalTodo>> fetchPurchaseApprovalTodos() async {
    final todos = _cachedApprovalTodos.isEmpty
        ? await fetchApprovalTodos()
        : _cachedApprovalTodos;
    return todos
        .where(
          (todo) =>
              ApprovalService.purchaseApprovalDoctypes.contains(todo.doctype),
        )
        .toList(growable: false);
  }

  Future<List<SalesOrderApprovalHistory>> fetchSalesOrderApprovalHistory() {
    return _approvalService.fetchSalesOrderApprovalHistory(
      currentUser: currentUser,
    );
  }

  Future<Map<String, dynamic>> fetchApprovalDocument({
    required String doctype,
    required String name,
    bool forceRefresh = false,
  }) {
    return _approvalService.fetchApprovalDocument(
      doctype: doctype,
      name: name,
      forceRefresh: forceRefresh,
    );
  }

  Future<List<SalesOrderApprovalHistory>> fetchApprovalDocumentActivity({
    required String doctype,
    required String name,
  }) {
    return _approvalService.fetchApprovalDocumentActivity(
      doctype: doctype,
      name: name,
    );
  }

  Future<Map<String, dynamic>> fetchSalesOrderApprovalDetail(String name) {
    return _approvalService.fetchSalesOrderApprovalDetail(name);
  }

  Future<List<Map<String, dynamic>>> fetchEnabledUsersForApproval() {
    return _approvalService.fetchEnabledUsersForApproval();
  }

  Future<void> addSalesOrderAdditionalApprover({
    required String salesOrder,
    required String approver,
    required String reason,
  }) async {
    await _approvalService.addSalesOrderAdditionalApprover(
      salesOrder: salesOrder,
      approver: approver,
      reason: reason,
    );
    _removeApprovalTodoCacheItem('Sales Order', salesOrder);
    unawaited(
      fetchApprovalTodos(
        forceRefresh: true,
      ).catchError((_) => const <ErpApprovalTodo>[]),
    );
  }

  Future<void> decideSalesOrderAdditionalApproval({
    required String salesOrder,
    Map<String, dynamic>? approverRow,
    required bool approved,
    String reason = '',
  }) async {
    await _approvalService.decideSalesOrderAdditionalApproval(
      salesOrder: salesOrder,
      approverRow: approverRow,
      approved: approved,
      reason: reason,
      appDisplayName: appState.appDisplayName,
      currentUser: currentUser,
    );
    _removeApprovalTodoCacheItem('Sales Order', salesOrder);
    unawaited(
      fetchApprovalTodos(
        forceRefresh: true,
      ).catchError((_) => const <ErpApprovalTodo>[]),
    );
  }

  Future<void> applyDocumentWorkflow({
    required String doctype,
    required String name,
    required String action,
    String reason = '',
    bool refreshAfterApply = true,
    bool waitForComment = true,
    Map<String, dynamic>? currentDocument,
  }) async {
    await _approvalService.applyDocumentWorkflow(
      doctype: doctype,
      name: name,
      action: action,
      reason: reason,
      waitForComment: waitForComment,
      currentDocument: currentDocument,
      appDisplayName: appState.appDisplayName,
      currentUser: currentUser,
    );
    _removeApprovalTodoCacheItem(doctype, name);
    if (refreshAfterApply) {
      await fetchApprovalTodos(forceRefresh: true);
    } else {
      unawaited(
        fetchApprovalTodos(
          forceRefresh: true,
        ).catchError((_) => const <ErpApprovalTodo>[]),
      );
    }
  }

  Future<void> applySalesOrderWorkflow({
    required SalesOrderApproval approval,
    required String action,
    String reason = '',
    bool refreshAfterApply = true,
    bool waitForComment = true,
    Map<String, dynamic>? currentDocument,
  }) async {
    await _approvalService.applySalesOrderWorkflow(
      approval: approval,
      action: action,
      reason: reason,
      waitForComment: waitForComment,
      currentDocument: currentDocument,
      appDisplayName: appState.appDisplayName,
      currentUser: currentUser,
    );
    _removeApprovalTodoCacheItem('Sales Order', approval.name);
    if (refreshAfterApply) {
      await fetchApprovalTodos(forceRefresh: true);
    } else {
      unawaited(
        fetchApprovalTodos(
          forceRefresh: true,
        ).catchError((_) => const <ErpApprovalTodo>[]),
      );
    }
  }

  void _setApprovalTodoSnapshot(List<ErpApprovalTodo> todos) {
    final snapshot = List<ErpApprovalTodo>.unmodifiable(todos);
    final purchaseCount = snapshot
        .where(
          (todo) =>
              ApprovalService.purchaseApprovalDoctypes.contains(todo.doctype),
        )
        .length;
    final changed =
        !_isSameApprovalTodoSnapshot(_cachedApprovalTodos, snapshot) ||
        _approvalTodoCount != snapshot.length ||
        _purchaseApprovalTodoCount != purchaseCount;
    _cachedApprovalTodos = snapshot;
    _approvalTodoCount = snapshot.length;
    _purchaseApprovalTodoCount = purchaseCount;
    if (changed) notifyListeners();
  }

  void _removeApprovalTodoCacheItem(String doctype, String name) {
    if (_cachedApprovalTodos.isEmpty) return;
    final filtered = _cachedApprovalTodos
        .where((todo) => todo.doctype != doctype || todo.name != name)
        .toList(growable: false);
    if (filtered.length == _cachedApprovalTodos.length) return;
    _setApprovalTodoSnapshot(filtered);
  }

  bool _isSameApprovalTodoSnapshot(
    List<ErpApprovalTodo> current,
    List<ErpApprovalTodo> next,
  ) {
    if (current.length != next.length) return false;
    for (var i = 0; i < current.length; i++) {
      final a = current[i];
      final b = next[i];
      if (a.doctype != b.doctype ||
          a.name != b.name ||
          a.workflowState != b.workflowState ||
          a.status != b.status ||
          a.docStatus != b.docStatus ||
          a.actions.join('|') != b.actions.join('|')) {
        return false;
      }
    }
    return true;
  }
}
