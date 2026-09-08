import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/delivery_activity_log.dart';
import '../../models/delivery_note.dart';
import '../../state/logistics/logistics_tracking_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/erp_format.dart';
import '../../widgets/erp/erp_empty_state.dart';
import 'logistics_widgets.dart';

class LogisticsTrackingTab extends StatefulWidget {
  const LogisticsTrackingTab({super.key});

  @override
  State<LogisticsTrackingTab> createState() => _LogisticsTrackingTabState();
}

class _LogisticsTrackingTabState extends State<LogisticsTrackingTab> {
  final _search = TextEditingController();
  _TrackingScope _scope = _TrackingScope.all;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh(BuildContext context) {
    return context.read<LogisticsTrackingState>().refreshDeliveryNotes();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<LogisticsTrackingState>();
    final docs = state.deliveryNotes;
    final visibleDocs = docs.where(_matchesFilter).toList();
    final toBill = docs
        .where((doc) => doc.statusKey == DeliveryNoteStatusKey.toBill)
        .length;
    final completed = docs
        .where((doc) => doc.statusKey == DeliveryNoteStatusKey.completed)
        .length;
    final returns = docs
        .where(
          (doc) =>
              doc.statusKey == DeliveryNoteStatusKey.returnIssued ||
              doc.statusKey == DeliveryNoteStatusKey.returnDoc,
        )
        .length;

    return RefreshIndicator(
      onRefresh: () => _refresh(context),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: logisticsPagePaddingOf(context),
        children: [
          LogisticsHeroSummaryCard(
            title: 'Tracking Armada',
            subtitle: 'Pantau status delivery dan bukti pengiriman',
            icon: Icons.route_rounded,
            stats: [
              LogisticsHeroStat(
                label: 'Outstanding',
                value: '${docs.where(_isOutstanding).length}',
              ),
              LogisticsHeroStat(label: 'To Bill', value: '$toBill'),
              LogisticsHeroStat(label: 'Completed', value: '$completed'),
              LogisticsHeroStat(label: 'Return', value: '$returns'),
            ],
          ),
          const SizedBox(height: 14),
          LogisticsMetricGrid(
            items: [
              LogisticsMetricItem(
                label: 'Outstanding',
                value: '${docs.where(_isOutstanding).length}',
                icon: Icons.pending_actions_rounded,
                color: AppColors.warning,
              ),
              LogisticsMetricItem(
                label: 'To Bill',
                value: '$toBill',
                icon: Icons.receipt_long_outlined,
                color: AppColors.primary,
              ),
              LogisticsMetricItem(
                label: 'Completed',
                value: '$completed',
                icon: Icons.task_alt_rounded,
                color: AppColors.success,
              ),
              LogisticsMetricItem(
                label: 'Return',
                value: '$returns',
                icon: Icons.undo_rounded,
                color: AppColors.warning,
              ),
            ],
          ),
          if (state.isDeliveryNotesLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (state.deliveryNotesError != null) ...[
            const SizedBox(height: 12),
            LogisticsInfoPanel(
              message: _friendlyError(state.deliveryNotesError!),
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
            ),
          ],
          const SizedBox(height: 16),
          LogisticsSectionHeader(
            title: 'Monitoring Perjalanan',
            subtitle: '${visibleDocs.length} dari ${docs.length} Delivery Note',
            icon: Icons.map_outlined,
          ),
          const SizedBox(height: 12),
          _TrackingScopeSelector(
            selected: _scope,
            onChanged: (scope) => setState(() => _scope = scope),
          ),
          const SizedBox(height: 12),
          LogisticsSearchField(
            controller: _search,
            hintText: 'Cari Delivery Note atau customer',
          ),
          const SizedBox(height: 12),
          if (visibleDocs.isEmpty && !state.isDeliveryNotesLoading)
            const ErpEmptyState(
              title: 'Belum ada Delivery Note',
              message: 'Ubah filter atau tarik layar untuk refresh.',
            )
          else
            ...visibleDocs.map((doc) => _trackingCard(context, doc)),
        ],
      ),
    );
  }

  bool _matchesFilter(DeliveryNote doc) {
    if (!_matchesScope(doc)) return false;
    final query = _search.text.trim().toLowerCase();
    return query.isEmpty ||
        doc.id.toLowerCase().contains(query) ||
        doc.customer.toLowerCase().contains(query) ||
        doc.statusText.toLowerCase().contains(query) ||
        doc.date.toLowerCase().contains(query);
  }

  bool _matchesScope(DeliveryNote doc) {
    return switch (_scope) {
      _TrackingScope.all => true,
      _TrackingScope.draft => doc.statusKey == DeliveryNoteStatusKey.draft,
      _TrackingScope.toBill => doc.statusKey == DeliveryNoteStatusKey.toBill,
      _TrackingScope.completed =>
        doc.statusKey == DeliveryNoteStatusKey.completed,
      _TrackingScope.returnIssued =>
        doc.statusKey == DeliveryNoteStatusKey.returnIssued ||
            doc.statusKey == DeliveryNoteStatusKey.returnDoc,
      _TrackingScope.cancelled =>
        doc.statusKey == DeliveryNoteStatusKey.cancelled,
      _TrackingScope.closed => doc.statusKey == DeliveryNoteStatusKey.closed,
    };
  }

  static bool _isOutstanding(DeliveryNote doc) {
    return doc.statusKey != DeliveryNoteStatusKey.completed &&
        doc.statusKey != DeliveryNoteStatusKey.cancelled &&
        doc.statusKey != DeliveryNoteStatusKey.closed;
  }

  static Widget _trackingCard(BuildContext context, DeliveryNote doc) {
    final color = _statusColor(doc);
    final statusIcon = doc.statusKey == DeliveryNoteStatusKey.completed
        ? Icons.task_alt_rounded
        : doc.statusKey == DeliveryNoteStatusKey.cancelled ||
              doc.statusKey == DeliveryNoteStatusKey.closed
        ? Icons.block_rounded
        : Icons.local_shipping_outlined;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () => _openTrackingDetail(context, doc),
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.cardShadow,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(statusIcon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.id,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        doc.customer,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          LogisticsStatusChip(
                            label: doc.statusText,
                            color: color,
                          ),
                          LogisticsStatusChip(
                            label: doc.date.isEmpty ? 'No Date' : doc.date,
                            color: AppColors.slate,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Rp ${formatErpCurrency(doc.value)}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.slate,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _openTrackingDetail(BuildContext context, DeliveryNote doc) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LogisticsTrackingDetailScreen(doc: doc),
      ),
    );
  }

  static Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    ),
  );

  static List<_JourneyStep> _journeySteps(DeliveryNote doc) {
    final cancelled =
        doc.statusKey == DeliveryNoteStatusKey.cancelled ||
        doc.statusKey == DeliveryNoteStatusKey.closed;
    final draft = doc.docStatus == 0;
    final toBill = doc.statusKey == DeliveryNoteStatusKey.toBill;
    final completed = doc.statusKey == DeliveryNoteStatusKey.completed;
    final returned =
        doc.statusKey == DeliveryNoteStatusKey.returnIssued ||
        doc.statusKey == DeliveryNoteStatusKey.returnDoc;
    final submitted = doc.docStatus == 1 && !cancelled;

    return [
      _JourneyStep(
        title: 'Status loading barang',
        subtitle: draft
            ? 'Dokumen masih disiapkan.'
            : 'Barang siap diproses untuk pengiriman.',
        icon: Icons.inventory_2_outlined,
        state: cancelled
            ? _JourneyStepState.cancelled
            : draft
            ? _JourneyStepState.active
            : _JourneyStepState.done,
      ),
      _JourneyStep(
        title: 'Armada berangkat',
        subtitle: submitted || completed || toBill || returned
            ? 'Pengiriman sudah berjalan sesuai dokumen.'
            : 'Menunggu dokumen pengiriman disahkan.',
        icon: Icons.local_shipping_outlined,
        state: cancelled
            ? _JourneyStepState.cancelled
            : submitted || completed || toBill || returned
            ? _JourneyStepState.done
            : _JourneyStepState.pending,
      ),
      _JourneyStep(
        title: 'Status sampai tujuan',
        subtitle: completed || toBill
            ? 'Barang sudah sampai tujuan.'
            : returned
            ? 'Pengiriman memiliki retur.'
            : 'Menunggu konfirmasi sampai tujuan.',
        icon: Icons.flag_outlined,
        state: cancelled
            ? _JourneyStepState.cancelled
            : completed || toBill
            ? _JourneyStepState.done
            : returned
            ? _JourneyStepState.cancelled
            : submitted
            ? _JourneyStepState.active
            : _JourneyStepState.pending,
      ),
      _JourneyStep(
        title: 'Status bongkar / POD',
        subtitle: completed
            ? 'Pengiriman selesai. Foto POD dan tanda tangan bisa dicek di attachment.'
            : toBill
            ? 'Pengiriman selesai dan menunggu proses tagihan.'
            : returned
            ? 'Retur sudah tercatat pada dokumen.'
            : 'Upload foto POD dan tanda tangan di menu Delivery Monitoring.',
        icon: Icons.assignment_turned_in_outlined,
        state: cancelled
            ? _JourneyStepState.cancelled
            : completed
            ? _JourneyStepState.done
            : toBill
            ? _JourneyStepState.active
            : returned
            ? _JourneyStepState.cancelled
            : _JourneyStepState.pending,
      ),
    ];
  }

  static Color _statusColor(DeliveryNote doc) {
    if (doc.statusKey == DeliveryNoteStatusKey.completed) {
      return AppColors.success;
    }
    if (doc.statusKey == DeliveryNoteStatusKey.cancelled ||
        doc.statusKey == DeliveryNoteStatusKey.closed) {
      return AppColors.slate;
    }
    if (doc.docStatus == 0) return AppColors.warning;
    return AppColors.primary;
  }

  static String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _LogisticsTrackingDetailScreen extends StatelessWidget {
  final DeliveryNote doc;

  const _LogisticsTrackingDetailScreen({required this.doc});

  @override
  Widget build(BuildContext context) {
    final color = _LogisticsTrackingTabState._statusColor(doc);
    final steps = _LogisticsTrackingTabState._journeySteps(doc);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'Detail Armada',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: logisticsPagePaddingOf(context),
          children: [
            LogisticsModernCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.1),
                    foregroundColor: color,
                    child: const Icon(Icons.route_rounded),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.id,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          doc.customer,
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        LogisticsStatusChip(
                          label: doc.statusText,
                          color: color,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LogisticsModernCard(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderColor: AppColors.primary.withValues(alpha: 0.12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.map_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Ringkasan Armada',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _LogisticsTrackingTabState._detailRow(
                    'Posting Date',
                    doc.date,
                  ),
                  _LogisticsTrackingTabState._detailRow(
                    'Nilai Delivery',
                    'Rp ${formatErpCurrency(doc.value)}',
                  ),
                  _LogisticsTrackingTabState._detailRow(
                    'Total Qty',
                    '${doc.itemsCount}',
                  ),
                  _LogisticsTrackingTabState._detailRow(
                    'Status',
                    doc.statusText,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _TrackingItemsSection(initialRow: doc),
            const SizedBox(height: 16),
            _TrackingProofSummary(deliveryNoteId: doc.id),
            const SizedBox(height: 16),
            _DeliveryActivitySection(deliveryNote: doc),
            const SizedBox(height: 16),
            const Text(
              'Status Delivery Note',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            ...steps.map((step) => _JourneyStepTile(step: step)),
          ],
        ),
      ),
    );
  }
}

enum _TrackingScope {
  all,
  draft,
  toBill,
  completed,
  returnIssued,
  cancelled,
  closed,
}

class _TrackingScopeSelector extends StatelessWidget {
  const _TrackingScopeSelector({
    required this.selected,
    required this.onChanged,
  });

  final _TrackingScope selected;
  final ValueChanged<_TrackingScope> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      (_TrackingScope.all, 'Semua'),
      (_TrackingScope.draft, 'Draft'),
      (_TrackingScope.toBill, 'To Bill'),
      (_TrackingScope.completed, 'Completed'),
      (_TrackingScope.returnIssued, 'Return Issued'),
      (_TrackingScope.cancelled, 'Cancelled'),
      (_TrackingScope.closed, 'Closed'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((option) {
          final scope = option.$1;
          final active = selected == scope;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: active,
              label: Text(option.$2),
              onSelected: (_) => onChanged(scope),
              selectedColor: AppColors.softGreen,
              backgroundColor: AppColors.white,
              labelStyle: TextStyle(
                color: active ? AppColors.primary : AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
              side: BorderSide(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.28)
                    : AppColors.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

enum _JourneyStepState { done, active, pending, cancelled }

class _TrackingProofSummary extends StatefulWidget {
  const _TrackingProofSummary({required this.deliveryNoteId});

  final String deliveryNoteId;

  @override
  State<_TrackingProofSummary> createState() => _TrackingProofSummaryState();
}

class _TrackingProofSummaryState extends State<_TrackingProofSummary> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<LogisticsTrackingState>().fetchDocumentAttachments(
      doctype: 'Delivery Note',
      documentName: widget.deliveryNoteId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        final hasProof = rows.isNotEmpty;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: hasProof
                ? AppColors.success.withValues(alpha: 0.08)
                : AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (hasProof ? AppColors.success : AppColors.warning)
                  .withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (hasProof ? AppColors.success : AppColors.warning)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hasProof ? Icons.verified_rounded : Icons.attach_file_rounded,
                  color: hasProof ? AppColors.success : AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bukti POD / Tanda Tangan',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      loading
                          ? 'Memuat bukti...'
                          : hasProof
                          ? '${rows.length} attachment sudah tersimpan'
                          : 'Belum ada attachment bukti pengiriman',
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (snapshot.hasError)
                      Text(
                        _LogisticsTrackingTabState._friendlyError(
                          snapshot.error!,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                LogisticsStatusChip(
                  label: hasProof ? 'Ada Bukti' : 'Perlu Bukti',
                  color: hasProof ? AppColors.success : AppColors.warning,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DeliveryActivitySection extends StatefulWidget {
  const _DeliveryActivitySection({required this.deliveryNote});

  final DeliveryNote deliveryNote;

  @override
  State<_DeliveryActivitySection> createState() =>
      _DeliveryActivitySectionState();
}

class _DeliveryActivitySectionState extends State<_DeliveryActivitySection> {
  static const _statuses = [
    'Loading Barang',
    'Armada Berangkat',
    'Sampai Tujuan',
    'Bongkar',
    'Selesai',
  ];

  late Future<List<DeliveryActivityLog>> _future;
  var _busyStatus = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DeliveryActivityLog>> _load() {
    return context.read<LogisticsTrackingState>().fetchDeliveryActivityLogs(
      widget.deliveryNote.id,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
      _error = null;
    });
  }

  Future<void> _record(String status) async {
    if (_busyStatus.isNotEmpty) return;
    final notes = await _askNotes(status);
    if (notes == null || !mounted) return;

    setState(() {
      _busyStatus = status;
      _error = null;
    });
    try {
      await context.read<LogisticsTrackingState>().recordDeliveryActivity(
        deliveryNote: widget.deliveryNote,
        activityStatus: status,
        notes: notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status "$status" tersimpan.'),
          backgroundColor: AppColors.success,
        ),
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _LogisticsTrackingTabState._friendlyError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busyStatus = '');
    }
  }

  Future<String?> _askNotes(String status) {
    return showDialog<String>(
      context: context,
      builder: (_) => _DeliveryActivityNotesDialog(status: status),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aktivitas Armada',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Update status manual driver',
                      style: TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                color: AppColors.primary,
                tooltip: 'Refresh aktivitas',
              ),
            ],
          ),
          if (_error?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FutureBuilder<List<DeliveryActivityLog>>(
            future: _future,
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <DeliveryActivityLog>[];
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              final nextStatus = _nextStatus(rows);
              final alternateStatuses = _statuses
                  .where((status) => status != nextStatus)
                  .toList(growable: false);

              final actionPanel = _DeliveryActivityActionPanel(
                loading: loading,
                busyStatus: _busyStatus,
                nextStatus: nextStatus,
                statuses: alternateStatuses,
                onRecord: _record,
                iconFor: _statusIcon,
              );

              if (snapshot.connectionState == ConnectionState.waiting) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    actionPanel,
                    const SizedBox(height: 14),
                    const LogisticsInfoPanel(
                      message: 'Memuat aktivitas armada...',
                      icon: Icons.timeline_rounded,
                    ),
                  ],
                );
              }

              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    actionPanel,
                    const SizedBox(height: 14),
                    LogisticsInfoPanel(
                      message:
                          'Aktivitas belum bisa dimuat. ${_LogisticsTrackingTabState._friendlyError(snapshot.error!)}',
                      icon: Icons.error_outline_rounded,
                      color: AppColors.danger,
                    ),
                  ],
                );
              }

              if (rows.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    actionPanel,
                    const SizedBox(height: 14),
                    const LogisticsInfoPanel(
                      message:
                          'Belum ada aktivitas manual. Driver bisa mulai dari Loading Barang.',
                      icon: Icons.timeline_rounded,
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  actionPanel,
                  const SizedBox(height: 16),
                  const Text(
                    'Riwayat Aktivitas',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...rows.map(_DeliveryActivityTile.new),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static IconData _statusIcon(String status) {
    final text = status.toLowerCase();
    if (text.contains('loading')) return Icons.inventory_2_outlined;
    if (text.contains('berangkat')) return Icons.local_shipping_outlined;
    if (text.contains('tujuan')) return Icons.flag_outlined;
    if (text.contains('bongkar')) return Icons.move_down_rounded;
    return Icons.check_circle_outline_rounded;
  }

  static String _nextStatus(List<DeliveryActivityLog> rows) {
    if (rows.isEmpty) return _statuses.first;
    final latest = rows.first.activityStatus.trim().toLowerCase();
    final currentIndex = _statuses.indexWhere(
      (status) => status.toLowerCase() == latest,
    );
    if (currentIndex < 0) return _statuses.first;
    final nextIndex = currentIndex + 1;
    if (nextIndex >= _statuses.length) return _statuses.last;
    return _statuses[nextIndex];
  }
}

class _DeliveryActivityNotesDialog extends StatefulWidget {
  const _DeliveryActivityNotesDialog({required this.status});

  final String status;

  @override
  State<_DeliveryActivityNotesDialog> createState() =>
      _DeliveryActivityNotesDialogState();
}

class _DeliveryActivityNotesDialogState
    extends State<_DeliveryActivityNotesDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.status),
      content: TextField(
        controller: _controller,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'Catatan opsional',
          hintText: 'Contoh: barang sudah dimuat lengkap',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _DeliveryActivityActionPanel extends StatelessWidget {
  const _DeliveryActivityActionPanel({
    required this.loading,
    required this.busyStatus,
    required this.nextStatus,
    required this.statuses,
    required this.onRecord,
    required this.iconFor,
  });

  final bool loading;
  final String busyStatus;
  final String nextStatus;
  final List<String> statuses;
  final ValueChanged<String> onRecord;
  final IconData Function(String status) iconFor;

  @override
  Widget build(BuildContext context) {
    final savingNext = busyStatus == nextStatus;
    final disabled = loading || busyStatus.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Langkah berikutnya',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: disabled ? null : () => onRecord(nextStatus),
                icon: savingNext
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(iconFor(nextStatus)),
                label: Text(nextStatus),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ikuti tombol ini sesuai urutan kerja driver di lapangan.',
                style: TextStyle(
                  color: AppColors.slate,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Ubah status lain jika diperlukan',
          style: TextStyle(
            color: AppColors.slate,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: statuses.map((status) {
            final busy = busyStatus == status;
            return OutlinedButton.icon(
              onPressed: disabled ? null : () => onRecord(status),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(iconFor(status), size: 18),
              label: Text(status),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _DeliveryActivityTile extends StatelessWidget {
  const _DeliveryActivityTile(this.log);

  final DeliveryActivityLog log;

  @override
  Widget build(BuildContext context) {
    final color = _color(log.activityStatus);
    final coordinates = log.latitude.isEmpty || log.longitude.isEmpty
        ? ''
        : '${log.latitude}, ${log.longitude}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.1),
            foregroundColor: color,
            child: Icon(_icon(log.activityStatus), size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        log.activityStatus.isEmpty
                            ? 'Aktivitas'
                            : log.activityStatus,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      _shortDateTime(log.capturedAt),
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  log.driver.isEmpty ? 'Driver belum tercatat' : log.driver,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (log.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    log.notes.trim(),
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (coordinates.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    log.accuracy > 0
                        ? '$coordinates | Akurasi ${log.accuracy.toStringAsFixed(0)} m'
                        : coordinates,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Color _color(String status) {
    final text = status.toLowerCase();
    if (text.contains('selesai')) return AppColors.success;
    if (text.contains('tujuan') || text.contains('bongkar')) {
      return AppColors.primary;
    }
    if (text.contains('berangkat')) return AppColors.primary;
    return AppColors.warning;
  }

  static IconData _icon(String status) {
    final text = status.toLowerCase();
    if (text.contains('loading')) return Icons.inventory_2_outlined;
    if (text.contains('berangkat')) return Icons.local_shipping_outlined;
    if (text.contains('tujuan')) return Icons.flag_outlined;
    if (text.contains('bongkar')) return Icons.move_down_rounded;
    return Icons.check_circle_outline_rounded;
  }

  static String _shortDateTime(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value.isEmpty ? '-' : value;
    return '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')} '
        '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }
}

class _TrackingItemsSection extends StatefulWidget {
  const _TrackingItemsSection({required this.initialRow});

  final DeliveryNote initialRow;

  @override
  State<_TrackingItemsSection> createState() => _TrackingItemsSectionState();
}

class _TrackingItemsSectionState extends State<_TrackingItemsSection> {
  late Future<DeliveryNote> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<LogisticsTrackingState>().loadDeliveryNoteDetail(
      widget.initialRow.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DeliveryNote>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LogisticsInfoPanel(
            message: 'Memuat item barang dari Delivery Note...',
            icon: Icons.inventory_2_outlined,
          );
        }

        if (snapshot.hasError) {
          return LogisticsInfoPanel(
            message:
                'Item barang belum bisa dimuat. ${_LogisticsTrackingTabState._friendlyError(snapshot.error!)}',
            icon: Icons.error_outline_rounded,
            color: AppColors.danger,
          );
        }

        final detail = snapshot.data ?? widget.initialRow;
        if (detail.items.isEmpty) {
          return const LogisticsInfoPanel(
            message:
                'Item barang belum tersedia. Tarik untuk refresh atau cek kembali dokumen pengiriman.',
            icon: Icons.inventory_2_outlined,
            color: AppColors.warning,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Barang Dalam Pengiriman',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                LogisticsStatusChip(
                  label: '${detail.items.length} item',
                  color: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...detail.items.take(6).map(_TrackingItemCard.new),
            if (detail.items.length > 6)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '+${detail.items.length - 6} item lainnya',
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TrackingItemCard extends StatelessWidget {
  const _TrackingItemCard(this.item);

  final DeliveryNoteItem item;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.itemName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          item.itemCode,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.slate,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _TrackingItemStat(
                label: 'Qty',
                value:
                    '${formatErpCurrency(item.qty)}${item.uom.isEmpty ? '' : ' ${item.uom}'}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TrackingItemStat(
                label: 'Gudang',
                value: item.warehouse.isEmpty ? '-' : item.warehouse,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _TrackingItemStat extends StatelessWidget {
  const _TrackingItemStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.slate,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _JourneyStep {
  final String title;
  final String subtitle;
  final IconData icon;
  final _JourneyStepState state;

  const _JourneyStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.state,
  });
}

class _JourneyStepTile extends StatelessWidget {
  final _JourneyStep step;

  const _JourneyStepTile({required this.step});

  Color get _color {
    return switch (step.state) {
      _JourneyStepState.done => AppColors.success,
      _JourneyStepState.active => AppColors.primary,
      _JourneyStepState.cancelled => AppColors.danger,
      _JourneyStepState.pending => AppColors.slate,
    };
  }

  IconData get _stateIcon {
    return switch (step.state) {
      _JourneyStepState.done => Icons.check_rounded,
      _JourneyStepState.active => step.icon,
      _JourneyStepState.cancelled => Icons.close_rounded,
      _JourneyStepState.pending => Icons.more_horiz_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(_stateIcon, color: color, size: 19),
              ),
              Container(width: 2, height: 42, color: AppColors.border),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      LogisticsStatusChip(
                        label: _labelForState(step.state),
                        color: color,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    step.subtitle,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _labelForState(_JourneyStepState state) {
    return switch (state) {
      _JourneyStepState.done => 'Done',
      _JourneyStepState.active => 'Aktif',
      _JourneyStepState.pending => 'Pending',
      _JourneyStepState.cancelled => 'Batal',
    };
  }
}
