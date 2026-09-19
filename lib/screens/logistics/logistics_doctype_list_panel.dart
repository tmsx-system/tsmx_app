import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/logistics/logistics_overview_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/frappe_status.dart';
import '../../widgets/erp/erp_empty_state.dart';
import '../../widgets/erp/erp_status_badge.dart';
import 'logistics_widgets.dart';

class LogisticsDoctypeListPanel extends StatefulWidget {
  final String doctype;
  final String title;
  final IconData icon;
  final List<String> fields;
  final String Function(Map<String, dynamic> row) titleOf;
  final String Function(Map<String, dynamic> row) subtitleOf;

  const LogisticsDoctypeListPanel({
    super.key,
    required this.doctype,
    required this.title,
    required this.icon,
    required this.fields,
    required this.titleOf,
    required this.subtitleOf,
  });

  @override
  State<LogisticsDoctypeListPanel> createState() =>
      _LogisticsDoctypeListPanelState();
}

class _LogisticsDoctypeListPanelState extends State<LogisticsDoctypeListPanel> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await context
          .read<LogisticsOverviewState>()
          .fetchLogisticsDocuments(
            doctype: widget.doctype,
            fields: widget.fields,
            search: _search.text,
          );
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (error) {
      _error = error
          .toString()
          .replaceFirst(RegExp(r'^Exception:\s*'), '')
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.title,
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: logisticsPagePaddingOf(context),
          children: [
            LogisticsSectionHeader(
              title: widget.title,
              subtitle: '${widget.doctype} · ERPNext 15',
              icon: widget.icon,
            ),
            const SizedBox(height: 14),
            LogisticsSearchField(
              controller: _search,
              hintText: 'Cari ${widget.doctype}',
              onChanged: (_) {},
            ),
            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              LogisticsInfoPanel(
                icon: Icons.error_outline_rounded,
                color: AppColors.danger,
                message: _error!,
              ),
            ],
            logisticsSectionGap,
            if (_rows.isEmpty && !_loading)
              ErpEmptyState(
                title: 'Belum ada ${widget.doctype}',
                message: 'Ubah pencarian atau pastikan role permission aktif.',
              )
            else
              ..._rows.map(_card),
          ],
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> row) {
    final rawStatus = row['status']?.toString().trim() ?? '';
    final docstatus = int.tryParse(row['docstatus']?.toString() ?? '');
    final status = rawStatus.isEmpty && docstatus == null
        ? ''
        : normalizeStatusText(rawStatus.isEmpty ? null : rawStatus, docstatus: docstatus);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LogisticsModernCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AppColors.softGreen,
              foregroundColor: AppColors.primary,
              child: Icon(widget.icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.titleOf(row),
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitleOf(row),
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (status.isNotEmpty) ErpStatusBadge(statusText: status),
          ],
        ),
      ),
    );
  }
}
