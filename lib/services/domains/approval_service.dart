import 'dart:async';
import 'dart:convert';

import '../../models/erp_approval_todo.dart';
import '../../models/sales_order_approval.dart';
import '../../utils/erp_doc_utils.dart';
import '../../utils/frappe_page_walker.dart';
import '../../utils/num_parse.dart';
import '../frappe_service.dart';
import '../local_app_database.dart';

class ApprovalService {
  static const _frappePageSize = 500;
  static const _approvalTodoCacheTtl = Duration(minutes: 5);
  static const _documentCacheTtl = Duration(minutes: 2);
  static const _approvalTodoDbCachePrefix = 'approval_todo_cache';
  static const _documentDbCachePrefix = 'document_cache';
  static const _historyCommentLimit = 80;
  static const _historyVersionLimit = 40;

  static const purchaseApprovalDoctypes = {
    'Purchase Order',
    'Purchase Invoice',
    'Material Request',
  };

  static const _approvalDoctypes = [
    'Sales Order',
    'Purchase Order',
    'Purchase Invoice',
    'Material Request',
    'Journal Entry',
  ];

  final FrappeService frappe;
  final Map<String, _CachedDocument> _documentCache = {};
  Future<List<ErpApprovalTodo>>? _approvalTodoFetchInFlight;
  Future<Map<String, int>>? _workflowStateDocStatusInFlight;
  Map<String, int> _workflowStateDocStatus = const {};
  DateTime? _workflowStateDocStatusAt;

  ApprovalService({required this.frappe});

  Future<List<ErpApprovalTodo>> fetchApprovalTodos({
    required String? currentUser,
    bool forceRefresh = false,
    void Function(List<ErpApprovalTodo> rows)? onProgress,
  }) async {
    final key = _approvalTodoCacheKey(currentUser);
    if (!forceRefresh) {
      final cachedRows = await _readDbRowList(key);
      if (cachedRows != null) {
        final workflowStateDocStatus = await _workflowStateDocStatusMap();
        return cachedRows
            .map(_approvalTodoFromCacheJson)
            .where((todo) => todo.doctype.isNotEmpty && todo.name.isNotEmpty)
            .where(
              (todo) => isOpenWorkflowInbox(
                docStatus: todo.docStatus,
                workflowState: todo.workflowState,
                actions: todo.actions,
                workflowStateDocStatus: workflowStateDocStatus,
              ),
            )
            .toList(growable: false);
      }
    }

    final inFlight = _approvalTodoFetchInFlight;
    if (inFlight != null) return inFlight;

    final request = _fetchApprovalTodosFromErp(onProgress: onProgress);
    _approvalTodoFetchInFlight = request;
    try {
      final todos = await request;
      await _writeDbRowList(
        key,
        todos.map(_approvalTodoToCacheJson).toList(growable: false),
        ttl: _approvalTodoCacheTtl,
      );
      return todos;
    } finally {
      if (identical(_approvalTodoFetchInFlight, request)) {
        _approvalTodoFetchInFlight = null;
      }
    }
  }

  Future<List<ErpApprovalTodo>> fetchPurchaseApprovalTodos({
    required String? currentUser,
  }) async {
    final todos = await fetchApprovalTodos(currentUser: currentUser);
    return todos
        .where((todo) => purchaseApprovalDoctypes.contains(todo.doctype))
        .toList(growable: false);
  }

  Future<List<SalesOrderApprovalHistory>> fetchSalesOrderApprovalHistory({
    required String? currentUser,
  }) async {
    await frappe.ensureLoggedIn();
    final normalizedUser = (currentUser ?? frappe.username ?? '')
        .trim()
        .toLowerCase();
    if (normalizedUser.isEmpty) return const [];

    final commentsFuture = _fetchAllResourcePages(
      doctype: 'Comment',
      fields: const [
        'name',
        'reference_doctype',
        'reference_name',
        'content',
        'comment_type',
        'comment_by',
        'owner',
        'creation',
      ],
      filters: [
        ['reference_doctype', 'in', _approvalDoctypes],
      ],
      orFilters: [
        ['owner', '=', normalizedUser],
        ['comment_by', '=', normalizedUser],
      ],
      orderBy: 'creation desc',
      maxRows: _historyCommentLimit,
    );
    final versionsFuture = _fetchAllResourcePages(
      doctype: 'Version',
      fields: const [
        'name',
        'ref_doctype',
        'docname',
        'data',
        'owner',
        'creation',
      ],
      filters: [
        ['ref_doctype', 'in', _approvalDoctypes],
        ['owner', '=', normalizedUser],
      ],
      orderBy: 'creation desc',
      maxRows: _historyVersionLimit,
    );

    final rows = await commentsFuture;

    final history = rows
        .where((row) {
          final owner = (row['owner'] ?? '').toString().trim().toLowerCase();
          final commentBy = (row['comment_by'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final actorMatches =
              owner == normalizedUser || commentBy == normalizedUser;
          return actorMatches && _isApprovalHistoryComment(row);
        })
        .map(SalesOrderApprovalHistory.fromJson)
        .toList();

    try {
      final versions = await versionsFuture;
      history.addAll(
        versions
            .map(
              (row) => _approvalVersionHistoryFromJson(
                row,
                fallbackDoctype: row['ref_doctype']?.toString() ?? '',
                fallbackName: row['docname']?.toString() ?? '',
              ),
            )
            .where((row) => _isApprovalHistoryContent(row.content)),
      );
    } catch (_) {
      // Version access is optional; comments remain usable for history.
    }

    final byId = <String, SalesOrderApprovalHistory>{};
    for (final row in history) {
      final key = row.id.trim().isEmpty
          ? '${row.doctype}|${row.salesOrder}|${row.content}|${row.createdAt}'
          : row.id;
      byId[key] = row;
    }
    return byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<SalesOrderApprovalHistory>> fetchApprovalDocumentActivity({
    required String doctype,
    required String name,
  }) async {
    final normalizedDoctype = doctype.trim();
    final normalizedName = name.trim();
    if (normalizedDoctype.isEmpty || normalizedName.isEmpty) return const [];
    await frappe.ensureLoggedIn();

    final activity = <SalesOrderApprovalHistory>[];
    try {
      activity.addAll(
        await _activityFromDocinfo(
          doctype: normalizedDoctype,
          name: normalizedName,
        ),
      );
    } catch (_) {}

    if (activity.isEmpty) {
      try {
        final comments = await _fetchAllResourcePages(
          doctype: 'Comment',
          fields: const [
            'name',
            'reference_doctype',
            'reference_name',
            'content',
            'comment_type',
            'comment_by',
            'owner',
            'creation',
          ],
          filters: [
            ['reference_doctype', '=', normalizedDoctype],
            ['reference_name', '=', normalizedName],
          ],
          orderBy: 'creation desc',
          maxRows: 40,
        );
        activity.addAll(
          comments
              .map(
                (row) => _commentHistoryFromJson(
                  row,
                  fallbackDoctype: normalizedDoctype,
                  fallbackName: normalizedName,
                ),
              )
              .where((row) => row.content.trim().isNotEmpty),
        );
      } catch (_) {}

      try {
        final versions = await _fetchAllResourcePages(
          doctype: 'Version',
          fields: const [
            'name',
            'ref_doctype',
            'docname',
            'data',
            'owner',
            'creation',
          ],
          filters: [
            ['ref_doctype', '=', normalizedDoctype],
            ['docname', '=', normalizedName],
          ],
          orderBy: 'creation desc',
          maxRows: 40,
        );
        activity.addAll(
          versions.map(
            (row) => _approvalVersionHistoryFromJson(
              row,
              fallbackDoctype: normalizedDoctype,
              fallbackName: normalizedName,
            ),
          ),
        );
      } catch (_) {}
    }

    try {
      final document = await _fetchCachedDocument(
        normalizedDoctype,
        normalizedName,
      );
      activity.addAll(
        _approvalDocumentAuditHistory(
          document,
          doctype: normalizedDoctype,
          name: normalizedName,
          existing: activity,
        ),
      );
    } catch (_) {}

    activity.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return activity;
  }

  Future<List<SalesOrderApprovalHistory>> _activityFromDocinfo({
    required String doctype,
    required String name,
  }) async {
    final raw = await frappe.callMethod(
      'frappe.desk.form.load.get_docinfo',
      args: {
        'doctype': doctype,
        'name': name,
        'docname': name,
      },
    );
    if (raw is! Map) return <SalesOrderApprovalHistory>[];
    var info = Map<String, dynamic>.from(raw);
    final nested = info['docinfo'];
    if (nested is Map) {
      info = Map<String, dynamic>.from(nested);
    }
    final activity = <SalesOrderApprovalHistory>[];

    void addCommentLike(dynamic rows) {
      if (rows is! List) return;
      for (final row in rows.whereType<Map>()) {
        final map = Map<String, dynamic>.from(row);
        final item = _commentHistoryFromJson(
          map,
          fallbackDoctype: doctype,
          fallbackName: name,
        );
        if (item.content.trim().isEmpty) continue;
        activity.add(item);
      }
    }

    addCommentLike(info['comments']);
    addCommentLike(info['communications']);

    final versions = info['versions'];
    if (versions is List) {
      for (final row in versions.whereType<Map>()) {
        final map = Map<String, dynamic>.from(row);
        activity.add(
          _approvalVersionHistoryFromJson(
            map,
            fallbackDoctype: doctype,
            fallbackName: name,
          ),
        );
      }
    }

    final byId = <String, SalesOrderApprovalHistory>{};
    for (final row in activity) {
      final key = row.id.trim().isEmpty
          ? '${row.doctype}|${row.salesOrder}|${row.content}|${row.createdAt}'
          : row.id;
      byId[key] = row;
    }
    return byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<Map<String, dynamic>> fetchSalesOrderApprovalDetail(String name) {
    return _fetchCachedDocument('Sales Order', name);
  }

  Future<Map<String, dynamic>> fetchApprovalDocument({
    required String doctype,
    required String name,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) return _fetchCachedDocument(doctype, name);
    final document = await frappe.fetchDocument(doctype, name);
    await _storeCachedDocument(doctype, name, document);
    return document;
  }

  Future<List<Map<String, dynamic>>> fetchEnabledUsersForApproval() async {
    await frappe.ensureLoggedIn();
    final rows = await frappe.fetchResource(
      'User',
      fields: const ['name', 'full_name', 'user_image', 'enabled', 'user_type'],
      filters: const [
        ['enabled', '=', 1],
        ['user_type', '=', 'System User'],
      ],
      orderBy: 'full_name asc, name asc',
      limit: 500,
    );
    return rows
        .where((row) => (row['name']?.toString().trim() ?? '').isNotEmpty)
        .toList(growable: false);
  }

  Future<void> addSalesOrderAdditionalApprover({
    required String salesOrder,
    required String approver,
    required String reason,
  }) async {
    await frappe.callMethod(
      'tmsx_mobile.api.approval.add_sales_order_approver',
      args: {
        'sales_order': salesOrder,
        'approver': approver,
        'approval_type': 'Additional',
        'reason': reason.trim(),
        'note': reason.trim(),
      },
    );
    await _deleteCachedDocument('Sales Order', salesOrder);
  }

  Future<void> decideSalesOrderAdditionalApproval({
    required String salesOrder,
    Map<String, dynamic>? approverRow,
    required bool approved,
    required String appDisplayName,
    required String? currentUser,
    String reason = '',
  }) async {
    final rowName = approverRow?['name']?.toString().trim() ?? '';
    try {
      await _callSalesOrderApproverServerScript(
        salesOrder: salesOrder,
        rowName: rowName,
        approved: approved,
        note: reason,
      );
    } catch (error) {
      if (!_shouldFallbackAdditionalApproval(error)) rethrow;
      try {
        await frappe.callMethod(
          'tmsx_mobile.api.approval.decide_sales_order_additional_approval',
          args: {
            'sales_order': salesOrder,
            'decision': approved ? 'approve' : 'reject',
            'reason': reason.trim(),
          },
        );
      } catch (fallbackError) {
        if (!_shouldFallbackAdditionalApproval(fallbackError)) rethrow;
        await _directUpdateSalesOrderAdditionalApproval(
          salesOrder: salesOrder,
          approverRow: approverRow,
          approved: approved,
          reason: reason,
          appDisplayName: appDisplayName,
          currentUser: currentUser,
        );
      }
    }
    await _deleteCachedDocument('Sales Order', salesOrder);
  }

  Future<void> applySalesOrderWorkflow({
    required SalesOrderApproval approval,
    required String action,
    required String appDisplayName,
    required String? currentUser,
    String reason = '',
    bool waitForComment = false,
    Map<String, dynamic>? currentDocument,
  }) async {
    await applyDocumentWorkflow(
      doctype: 'Sales Order',
      name: approval.name,
      action: action,
      appDisplayName: appDisplayName,
      currentUser: currentUser,
      reason: reason,
      waitForComment: waitForComment,
      currentDocument: currentDocument,
    );
  }

  Future<void> applyDocumentWorkflow({
    required String doctype,
    required String name,
    required String action,
    required String appDisplayName,
    required String? currentUser,
    String reason = '',
    bool waitForComment = false,
    Map<String, dynamic>? currentDocument,
  }) async {
    await frappe.ensureLoggedIn();
    final total = Stopwatch()..start();
    final normalizedAction = action.trim();
    final actionLower = normalizedAction.toLowerCase();
    final isReject =
        actionLower.contains('reject') ||
        actionLower.contains('tolak') ||
        actionLower.contains('decline') ||
        actionLower.contains('return');
    if (isReject && reason.trim().isEmpty) {
      throw Exception('Alasan reject/return wajib diisi.');
    }

    final getWatch = Stopwatch()..start();
    var doc = currentDocument;
    if (doc == null || (doc['name']?.toString() ?? '').trim().isEmpty) {
      doc = await frappe.fetchDocument(doctype, name);
    }
    getWatch.stop();
    FrappeService.logTiming(
      'GET document $doctype $name (apply $normalizedAction)',
      getWatch.elapsedMilliseconds,
    );
    final postWatch = Stopwatch()..start();
    try {
      await frappe.callMethod(
        'frappe.model.workflow.apply_workflow',
        args: {'doc': doc, 'action': normalizedAction},
      );
    } catch (_) {
      if (currentDocument == null) rethrow;
      doc = await frappe.fetchDocument(doctype, name);
      await frappe.callMethod(
        'frappe.model.workflow.apply_workflow',
        args: {'doc': doc, 'action': normalizedAction},
      );
    }
    postWatch.stop();
    FrappeService.logTiming(
      'POST apply_workflow $doctype $name action=$normalizedAction',
      postWatch.elapsedMilliseconds,
    );

    final decision = isReject ? 'REJECT' : 'APPROVE';
    final content = [
      '$decision via $appDisplayName',
      'Action: $normalizedAction',
      if (reason.trim().isNotEmpty) 'Alasan: ${reason.trim()}',
    ].join('\n');
    final commentRequest = frappe.callMethod(
      'frappe.desk.form.utils.add_comment',
      args: {
        'reference_doctype': doctype,
        'reference_name': name,
        'content': content,
        'comment_email': currentUser ?? '',
        'comment_by': currentUser ?? '',
      },
    );
    if (waitForComment) {
      await commentRequest;
    } else {
      unawaited(commentRequest.then<void>((_) {}).catchError((_) {}));
    }
    unawaited(_deleteCachedDocument(doctype, name).catchError((_) {}));
    FrappeService.logTiming(
      'applyDocumentWorkflow total $doctype $name action=$normalizedAction',
      total.elapsedMilliseconds,
    );
  }

  Future<List<ErpApprovalTodo>> _fetchApprovalTodosFromErp({
    void Function(List<ErpApprovalTodo> rows)? onProgress,
  }) async {
    await frappe.ensureLoggedIn();
    const configs = [
      (
        doctype: 'Sales Order',
        fields: [
          'name',
          'customer',
          'customer_name',
          'company',
          'workflow_state',
          'status',
          'owner',
          'transaction_date',
          'grand_total',
          'docstatus',
        ],
      ),
      (
        doctype: 'Purchase Order',
        fields: [
          'name',
          'supplier',
          'supplier_name',
          'company',
          'workflow_state',
          'status',
          'owner',
          'transaction_date',
          'grand_total',
          'docstatus',
        ],
      ),
      (
        doctype: 'Purchase Invoice',
        fields: [
          'name',
          'supplier',
          'supplier_name',
          'company',
          'workflow_state',
          'status',
          'owner',
          'posting_date',
          'due_date',
          'grand_total',
          'outstanding_amount',
          'docstatus',
        ],
      ),
      (
        doctype: 'Material Request',
        fields: [
          'name',
          'material_request_type',
          'workflow_state',
          'status',
          'owner',
          'company',
          'transaction_date',
          'schedule_date',
          'total_qty',
          'docstatus',
        ],
      ),
      (
        doctype: 'Journal Entry',
        fields: [
          'name',
          'title',
          'workflow_state',
          'owner',
          'company',
          'posting_date',
          'total_debit',
          'total_credit',
          'docstatus',
        ],
      ),
    ];

    final todosByKey = <String, ErpApprovalTodo>{};
    final totalWatch = Stopwatch()..start();
    final workflowStateDocStatusFuture = _workflowStateDocStatusMap();

    Future<void> processConfig(
      ({String doctype, List<String> fields}) config,
    ) async {
      final rows = await _fetchInboxRows(
        doctype: config.doctype,
        fields: config.fields,
      );
      final workflowStateDocStatus = await workflowStateDocStatusFuture;
      final candidates = rows
          .where(
            (row) => isApprovalInboxCandidateRow(
              row,
              workflowStateDocStatus: workflowStateDocStatus,
            ),
          )
          .toList(growable: false);
      if (candidates.isEmpty) return;

      final transitionWatch = Stopwatch()..start();
      final actionsByName = await _fetchWorkflowActionsForRows(
        doctype: config.doctype,
        rows: candidates,
        workflowStateDocStatus: workflowStateDocStatus,
      );
      FrappeService.logTiming(
        'Todo transitions ${config.doctype} candidates=${candidates.length}',
        transitionWatch.elapsedMilliseconds,
      );

      var added = false;
      for (final row in candidates) {
        final name = row['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final actions = actionsByName[name] ?? const <String>[];
        if (!isOpenWorkflowInbox(
          docStatus: NumParse.asInt(row['docstatus']),
          workflowState: row['workflow_state']?.toString() ?? '',
          actions: actions,
          workflowStateDocStatus: workflowStateDocStatus,
        )) {
          continue;
        }
        todosByKey['${config.doctype}|$name'] = ErpApprovalTodo.fromJson(
          config.doctype,
          row,
          actions: actions,
        );
        added = true;
      }
      if (added) {
        final snapshot = todosByKey.values.toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        onProgress?.call(snapshot);
      }
    }

    await Future.wait(configs.map(processConfig));

    final todos = todosByKey.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    FrappeService.logTiming(
      'fetchApprovalTodos total items=${todos.length}',
      totalWatch.elapsedMilliseconds,
    );
    return todos;
  }

  Future<List<Map<String, dynamic>>> _fetchInboxRows({
    required String doctype,
    required List<String> fields,
  }) async {
    final listWatch = Stopwatch()..start();
    try {
      final rows = await _fetchAllResourcePages(
        doctype: doctype,
        fields: fields,
        filters: approvalInboxListFilters(),
        orderBy: 'modified desc',
        maxRows: 80,
      );
      FrappeService.logTiming(
        'Todo list $doctype ${rows.length} workflow rows',
        listWatch.elapsedMilliseconds,
      );
      return rows;
    } catch (_) {}
    try {
      final rows = await _fetchAllResourcePages(
        doctype: doctype,
        fields: fields,
        filters: [
          ['docstatus', '=', 0],
        ],
        orderBy: 'modified desc',
        maxRows: 80,
      );
      FrappeService.logTiming(
        'Todo list $doctype fallback ${rows.length} workflow rows',
        listWatch.elapsedMilliseconds,
      );
      return rows;
    } catch (_) {
      FrappeService.logTiming(
        'Todo list $doctype 0 workflow rows',
        listWatch.elapsedMilliseconds,
      );
      return const [];
    }
  }

  Future<List<String>> fetchWorkflowActionsForDocument(
    Map<String, dynamic> doc,
  ) async {
    final workflowStateDocStatus = await _workflowStateDocStatusMap();
    return _fetchWorkflowActionsForDocument(
      doc,
      workflowStateDocStatus: workflowStateDocStatus,
    );
  }

  Future<Map<String, int>> _workflowStateDocStatusMap() async {
    final cachedAt = _workflowStateDocStatusAt;
    if (cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 10) &&
        _workflowStateDocStatus.isNotEmpty) {
      return _workflowStateDocStatus;
    }
    final inFlight = _workflowStateDocStatusInFlight;
    if (inFlight != null) return inFlight;
    final request = () async {
      final mapped = <String, int>{};
      try {
        final rows = await _fetchAllResourcePages(
          doctype: 'Workflow Document State',
          fields: const ['state', 'doc_status'],
          maxRows: 2000,
        );
        mapped.addAll(workflowStateDocStatusByName(rows));
      } catch (_) {}
      try {
        final rows = await _fetchAllResourcePages(
          doctype: 'Workflow State',
          fields: const ['name', 'workflow_state_name', 'doc_status'],
          maxRows: 500,
        );
        for (final entry in workflowStateDocStatusByName(rows).entries) {
          final previous = mapped[entry.key] ?? 0;
          if (entry.value > previous) mapped[entry.key] = entry.value;
        }
      } catch (_) {}
      return mapped;
    }();
    _workflowStateDocStatusInFlight = request;
    try {
      final mapped = await request;
      _workflowStateDocStatus = mapped;
      _workflowStateDocStatusAt = DateTime.now();
      return mapped;
    } finally {
      if (identical(_workflowStateDocStatusInFlight, request)) {
        _workflowStateDocStatusInFlight = null;
      }
    }
  }

  Future<Map<String, List<String>>> _fetchWorkflowActionsForRows({
    required String doctype,
    required List<Map<String, dynamic>> rows,
    required Map<String, int> workflowStateDocStatus,
    int batchSize = 16,
  }) async {
    final actionsByName = <String, List<String>>{};
    for (var start = 0; start < rows.length; start += batchSize) {
      final end = start + batchSize > rows.length
          ? rows.length
          : start + batchSize;
      final batch = rows.sublist(start, end);
      final results = await Future.wait(
        batch.map((row) async {
          final name = row['name']?.toString() ?? '';
          if (name.isEmpty) {
            return (name: name, actions: const <String>[]);
          }
          try {
            final doc = Map<String, dynamic>.from(row);
            doc['doctype'] = doctype;
            final actions = await _fetchWorkflowActionsForDocument(
              doc,
              workflowStateDocStatus: workflowStateDocStatus,
            );
            return (name: name, actions: actions);
          } catch (_) {
            return (name: name, actions: const <String>[]);
          }
        }),
      );
      for (final result in results) {
        if (result.name.isNotEmpty) {
          actionsByName[result.name] = result.actions;
        }
      }
    }
    return actionsByName;
  }

  Future<List<String>> _fetchWorkflowActionsForDocument(
    Map<String, dynamic> doc, {
    required Map<String, int> workflowStateDocStatus,
  }) async {
    try {
      final raw = await frappe.callMethod(
        'frappe.model.workflow.get_transitions',
        args: {'doc': doc},
      );
      return inboxActionsFromWorkflowTransitions(
        raw,
        workflowStateDocStatus: workflowStateDocStatus,
      );
    } catch (_) {
      final raw = await frappe.callMethod(
        'frappe.model.workflow.get_transitions',
        args: {'doc': jsonEncode(doc)},
      );
      return inboxActionsFromWorkflowTransitions(
        raw,
        workflowStateDocStatus: workflowStateDocStatus,
      );
    }
  }

  Future<void> _callSalesOrderApproverServerScript({
    required String salesOrder,
    required String rowName,
    required bool approved,
    required String note,
  }) async {
    if (rowName.isEmpty) {
      throw Exception(
        'Approval Row kosong. Refresh detail approval lalu coba lagi.',
      );
    }
    await frappe.callMethod(
      approved ? 'approve_sales_order_approver' : 'reject_sales_order_approver',
      args: {
        'sales_order': salesOrder,
        'row_name': rowName,
        'note': note.trim(),
      },
    );
  }

  bool _shouldFallbackAdditionalApproval(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('failed to get method') ||
        message.contains('not installed') ||
        message.contains('additional approval pending');
  }

  Future<void> _directUpdateSalesOrderAdditionalApproval({
    required String salesOrder,
    required Map<String, dynamic>? approverRow,
    required bool approved,
    required String reason,
    required String appDisplayName,
    required String? currentUser,
  }) async {
    final row = approverRow ?? const <String, dynamic>{};
    final childDoctype = row['doctype']?.toString().trim() ?? '';
    final childName = row['name']?.toString().trim() ?? '';
    if (childDoctype.isEmpty || childName.isEmpty) {
      throw Exception(
        'Row Additional Approval tidak lengkap. Refresh detail lalu coba lagi.',
      );
    }

    final status = approved ? 'Approved' : 'Rejected';
    await frappe.updateDocument(childDoctype, childName, {'status': status});

    final decision = approved ? 'APPROVE ADDITIONAL' : 'REJECT ADDITIONAL';
    final content = [
      '$decision via $appDisplayName',
      'Sales Order: $salesOrder',
      if (reason.trim().isNotEmpty) 'Alasan: ${reason.trim()}',
    ].join('\n');
    unawaited(
      frappe
          .callMethod(
            'frappe.desk.form.utils.add_comment',
            args: {
              'reference_doctype': 'Sales Order',
              'reference_name': salesOrder,
              'content': content,
              'comment_email': currentUser ?? '',
              'comment_by': currentUser ?? '',
            },
          )
          .then<void>((_) {})
          .catchError((_) {}),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAllResourcePages({
    required String doctype,
    required List<String> fields,
    String? orderBy,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
    required int? maxRows,
  }) {
    return walkFrappePages(
      pageSize: _frappePageSize,
      maxRows: maxRows,
      fetchPage: (start, limit) => _fetchResourceWithFieldFallback(
        doctype: doctype,
        fields: fields,
        limit: limit,
        limitStart: start,
        orderBy: orderBy,
        filters: filters,
        orFilters: orFilters,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchResourceWithFieldFallback({
    required String doctype,
    required List<String> fields,
    required int limit,
    int limitStart = 0,
    String? orderBy,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
  }) async {
    var remainingFields = List<String>.from(fields);
    var currentOrderBy = orderBy;
    while (remainingFields.isNotEmpty) {
      try {
        return await frappe.fetchResource(
          doctype,
          fields: remainingFields,
          limit: limit,
          limitStart: limitStart,
          orderBy: currentOrderBy,
          filters: filters,
          orFilters: orFilters,
        );
      } catch (error) {
        final text = error.toString();
        final badField = RegExp(
          r'Field not permitted in query:\s*([a-zA-Z0-9_]+)',
        ).firstMatch(text)?.group(1);
        if (badField != null && remainingFields.contains(badField)) {
          remainingFields.remove(badField);
          continue;
        }
        if (currentOrderBy != null &&
            (text.contains('order_by') || text.contains('Order By'))) {
          currentOrderBy = null;
          continue;
        }
        rethrow;
      }
    }
    throw Exception('No permitted fields available for $doctype.');
  }

  Future<Map<String, dynamic>> _fetchCachedDocument(
    String doctype,
    String name,
  ) async {
    final key = _documentCacheKey(doctype, name);
    final cached = _documentCache[key];
    if (cached != null && cached.isFresh) return cached.document;

    final stored = await LocalAppDatabase.instance.readJson(key);
    if (stored != null) {
      _documentCache[key] = _CachedDocument(
        storedAt: DateTime.now(),
        document: stored,
      );
      return stored;
    }

    final document = await frappe.fetchDocument(doctype, name);
    await _storeCachedDocument(doctype, name, document);
    return document;
  }

  Future<void> _storeCachedDocument(
    String doctype,
    String name,
    Map<String, dynamic> document,
  ) async {
    final key = _documentCacheKey(doctype, name);
    _documentCache[key] = _CachedDocument(
      storedAt: DateTime.now(),
      document: document,
    );
    await LocalAppDatabase.instance.writeJson(
      key,
      document,
      ttl: _documentCacheTtl,
    );
  }

  Future<void> _deleteCachedDocument(String doctype, String name) async {
    final key = _documentCacheKey(doctype, name);
    _documentCache.remove(key);
    await LocalAppDatabase.instance.delete(key);
  }

  Future<List<Map<String, dynamic>>?> _readDbRowList(String key) async {
    final json = await LocalAppDatabase.instance.readJson(key);
    final rows = json?['rows'];
    if (rows is! List) return null;
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<void> _writeDbRowList(
    String key,
    List<Map<String, dynamic>> rows, {
    required Duration ttl,
  }) {
    return LocalAppDatabase.instance.writeJson(key, {'rows': rows}, ttl: ttl);
  }

  String _approvalTodoCacheKey(String? currentUser) {
    final site = frappe.baseUrl.trim();
    final user = currentUser?.trim() ?? frappe.username?.trim() ?? '';
    return [_approvalTodoDbCachePrefix, site, user].join('|');
  }

  String _documentCacheKey(String doctype, String name) {
    final site = frappe.baseUrl.trim();
    final user = frappe.username?.trim() ?? '';
    return [
      _documentDbCachePrefix,
      site,
      user,
      doctype.trim(),
      name.trim(),
    ].join('|');
  }

  Map<String, dynamic> _approvalTodoToCacheJson(ErpApprovalTodo todo) {
    return {
      'doctype': todo.doctype,
      'name': todo.name,
      'party': todo.party,
      'party_name': todo.partyName,
      'workflow_state': todo.workflowState,
      'status': todo.status,
      'owner': todo.owner,
      'date': todo.date,
      'amount': todo.amount,
      'secondary_amount': todo.secondaryAmount,
      'docstatus': todo.docStatus,
      'actions': todo.actions,
    };
  }

  ErpApprovalTodo _approvalTodoFromCacheJson(Map<String, dynamic> json) {
    final actionsSource = json['actions'];
    final actions = actionsSource is List
        ? actionsSource
              .map((action) => action.toString().trim())
              .where((action) => action.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return ErpApprovalTodo(
      doctype: json['doctype']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      party: json['party']?.toString() ?? '',
      partyName: json['party_name']?.toString() ?? '',
      workflowState: json['workflow_state']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      owner: json['owner']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      amount: _asDouble(json['amount']),
      secondaryAmount: _asDouble(json['secondary_amount']),
      docStatus: _asInt(json['docstatus']),
      actions: actions,
    );
  }

  SalesOrderApprovalHistory _commentHistoryFromJson(
    Map<String, dynamic> row, {
    required String fallbackDoctype,
    required String fallbackName,
  }) {
    final commentType = row['comment_type']?.toString().trim() ?? '';
    var content = row['content']?.toString() ?? '';
    if (content.trim().isEmpty) {
      final type = commentType.toLowerCase();
      if (type == 'created') {
        content = 'created this';
      } else if (type == 'updated' || type == 'edit' || type == 'edited') {
        content = 'last edited this';
      } else if (type == 'workflow') {
        content = 'workflow';
      } else {
        content = commentType;
      }
    }
    return SalesOrderApprovalHistory(
      id: row['name']?.toString() ?? '',
      doctype: row['reference_doctype']?.toString() ?? fallbackDoctype,
      salesOrder: row['reference_name']?.toString() ?? fallbackName,
      content: content,
      actor:
          row['comment_by']?.toString() ??
          row['sender_full_name']?.toString() ??
          row['owner']?.toString() ??
          '',
      createdAt: row['creation']?.toString() ?? '',
    );
  }

  List<SalesOrderApprovalHistory> _approvalDocumentAuditHistory(
    Map<String, dynamic> document, {
    required String doctype,
    required String name,
    required List<SalesOrderApprovalHistory> existing,
  }) {
    final rows = <SalesOrderApprovalHistory>[];
    final hasCreated = existing.any(
      (row) => row.content.toLowerCase().contains('created this'),
    );
    final owner = document['owner']?.toString().trim() ?? '';
    final creation = document['creation']?.toString().trim() ?? '';
    if (!hasCreated && (owner.isNotEmpty || creation.isNotEmpty)) {
      rows.add(
        SalesOrderApprovalHistory(
          id: '$doctype::$name::created',
          doctype: doctype,
          salesOrder: name,
          content: 'created this',
          actor: owner,
          createdAt: creation,
        ),
      );
    }

    final hasEdited = existing.any((row) {
      final content = row.content.toLowerCase();
      return content.contains('last edited this') ||
          content.contains('changed ');
    });
    final modifiedBy = (document['modified_by'] ?? document['owner'])
        .toString()
        .trim();
    final modified = document['modified']?.toString().trim() ?? '';
    if (!hasEdited && (modifiedBy.isNotEmpty || modified.isNotEmpty)) {
      rows.add(
        SalesOrderApprovalHistory(
          id: '$doctype::$name::modified',
          doctype: doctype,
          salesOrder: name,
          content: 'last edited this',
          actor: modifiedBy,
          createdAt: modified,
        ),
      );
    }
    return rows;
  }

  SalesOrderApprovalHistory _approvalVersionHistoryFromJson(
    Map<String, dynamic> row, {
    required String fallbackDoctype,
    required String fallbackName,
  }) {
    final data = _versionDataMap(row['data']);
    return SalesOrderApprovalHistory(
      id: row['name']?.toString() ?? '',
      doctype: row['ref_doctype']?.toString() ?? fallbackDoctype,
      salesOrder: row['docname']?.toString() ?? fallbackName,
      content: _approvalVersionContent(data),
      actor: row['owner']?.toString() ?? '',
      createdAt: row['creation']?.toString() ?? '',
    );
  }

  Map<String, dynamic> _versionDataMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }

  String _approvalVersionContent(Map<String, dynamic> data) {
    final lines = <String>[];
    final changed = data['changed'];
    if (changed is List) {
      for (final raw in changed.take(8)) {
        if (raw is! List || raw.isEmpty) continue;
        final field = _activityFieldLabel(raw[0]);
        final oldValue = raw.length > 1 ? _activityValue(raw[1]) : '';
        final newValue = raw.length > 2 ? _activityValue(raw[2]) : '';
        if (oldValue.isEmpty && newValue.isEmpty) {
          lines.add('Changed $field');
        } else {
          lines.add('Changed $field from $oldValue to $newValue');
        }
      }
    }

    final rowChanged = data['row_changed'];
    if (rowChanged is List) {
      for (final raw in rowChanged.take(4)) {
        if (raw is! List || raw.isEmpty) continue;
        final table = _activityFieldLabel(raw[0]);
        final changes = raw.length > 2 && raw[2] is List ? raw[2] as List : [];
        final details = <String>[];
        for (final change in changes.take(4)) {
          if (change is! List || change.isEmpty) continue;
          final field = _activityFieldLabel(change[0]);
          final oldValue = change.length > 1 ? _activityValue(change[1]) : '';
          final newValue = change.length > 2 ? _activityValue(change[2]) : '';
          details.add('$field from $oldValue to $newValue');
        }
        lines.add(
          details.isEmpty
              ? 'Changed row in $table'
              : 'Changed row in $table: ${details.join(', ')}',
        );
      }
    }

    final added = data['added'];
    if (added is List && added.isNotEmpty) {
      lines.add('Added ${added.length} row${added.length == 1 ? '' : 's'}');
    }
    final removed = data['removed'];
    if (removed is List && removed.isNotEmpty) {
      lines.add(
        'Removed ${removed.length} row${removed.length == 1 ? '' : 's'}',
      );
    }

    if (lines.isEmpty) return 'last edited this';
    return lines.join('\n');
  }

  String _activityFieldLabel(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return 'Field';
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  String _activityValue(dynamic raw) {
    if (raw == null) return '-';
    final value = raw.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.isEmpty) return '-';
    return value.length > 90 ? '${value.substring(0, 87)}...' : value;
  }

  bool _isApprovalHistoryComment(Map<String, dynamic> row) {
    final commentType = row['comment_type']?.toString().trim().toLowerCase();
    if (commentType == 'workflow') return true;
    return _isApprovalHistoryContent(row['content']?.toString() ?? '');
  }

  bool _isApprovalHistoryContent(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    const approvalKeywords = [
      'via tmsx',
      'approved',
      'approve',
      'rejected',
      'reject',
      'submitted',
      'submit',
      'pending approval',
      'to deliver and bill',
      'cancelled',
      'canceled',
      'cancel',
      'workflow',
      'status',
    ];
    return approvalKeywords.any(normalized.contains);
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return 0;
    return double.tryParse(text.replaceAll(',', '')) ?? 0;
  }

  int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }
}

class _CachedDocument {
  final DateTime storedAt;
  final Map<String, dynamic> document;

  const _CachedDocument({required this.storedAt, required this.document});

  bool get isFresh =>
      DateTime.now().difference(storedAt) < ApprovalService._documentCacheTtl;
}
