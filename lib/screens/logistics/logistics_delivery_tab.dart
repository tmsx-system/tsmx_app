import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/delivery_note.dart';
import '../../services/sales_visit_location_service.dart';
import '../../state/logistics/logistics_delivery_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/erp_doc_utils.dart';
import '../../utils/erp_format.dart';
import '../../widgets/erp/erp_empty_state.dart';
import 'logistics_widgets.dart';

class LogisticsDeliveryTab extends StatefulWidget {
  const LogisticsDeliveryTab({super.key});

  @override
  State<LogisticsDeliveryTab> createState() => _LogisticsDeliveryTabState();
}

class _LogisticsDeliveryTabState extends State<LogisticsDeliveryTab> {
  final _search = TextEditingController();
  final _picker = ImagePicker();
  Timer? _debounce;
  _DeliveryScope _scope = _DeliveryScope.all;
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() =>
      context.read<LogisticsDeliveryState>().refreshDeliveryNotes();

  void _searchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      context.read<LogisticsDeliveryState>().setDeliveryNoteQuery(
        search: value,
      );
    });
  }

  List<DeliveryNote> _filter(List<DeliveryNote> rows) {
    final query = _search.text.trim().toLowerCase();
    return rows.where((row) {
      if (!_matchesScope(row)) return false;
      return query.isEmpty ||
          row.id.toLowerCase().contains(query) ||
          row.customer.toLowerCase().contains(query) ||
          row.statusText.toLowerCase().contains(query);
    }).toList();
  }

  bool _matchesScope(DeliveryNote row) {
    return switch (_scope) {
      _DeliveryScope.all => true,
      _DeliveryScope.draft => row.statusKey == DeliveryNoteStatusKey.draft,
      _DeliveryScope.toBill => row.statusKey == DeliveryNoteStatusKey.toBill,
      _DeliveryScope.completed =>
        row.statusKey == DeliveryNoteStatusKey.completed,
      _DeliveryScope.returnIssued =>
        row.statusKey == DeliveryNoteStatusKey.returnIssued ||
            row.statusKey == DeliveryNoteStatusKey.returnDoc,
      _DeliveryScope.cancelled =>
        row.statusKey == DeliveryNoteStatusKey.cancelled,
      _DeliveryScope.closed => row.statusKey == DeliveryNoteStatusKey.closed,
    };
  }

  bool _isOutstanding(DeliveryNote row) {
    return row.statusKey != DeliveryNoteStatusKey.completed &&
        row.statusKey != DeliveryNoteStatusKey.cancelled &&
        row.statusKey != DeliveryNoteStatusKey.closed;
  }

  Future<void> _chooseProofPhoto(DeliveryNote row) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tambah bukti pengiriman ${row.id}',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Ambil foto dengan kamera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Pilih foto dari galeri'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    final photo = await _picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (photo == null || !mounted) return;

    setState(() {
      _busyId = row.id;
      _error = null;
    });
    try {
      await context.read<LogisticsDeliveryState>().uploadDeliveryNoteProof(
        deliveryNoteId: row.id,
        filePath: photo.path,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Foto bukti terpasang ke ${row.id}.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _captureCustomerSignature(DeliveryNote row) async {
    final filePath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _DeliverySignatureDocumentScreen(initialRow: row),
      ),
    );
    if (filePath == null || !mounted) return;

    setState(() {
      _busyId = row.id;
      _error = null;
    });
    try {
      await context.read<LogisticsDeliveryState>().uploadDeliveryNoteProof(
        deliveryNoteId: row.id,
        filePath: filePath,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tanda tangan customer terpasang ke ${row.id}.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busyId = null);
      File(filePath).delete().ignore();
    }
  }

  void _openDetail(DeliveryNote row) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LogisticsDeliveryDetailScreen(
          row: row,
          onUploadPhoto: _chooseProofPhoto,
          onCaptureSignature: _captureCustomerSignature,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<LogisticsDeliveryState>();
    final rows = _filter(appState.deliveryNotes);
    final allRows = appState.deliveryNotes;
    final outstandingRows = allRows.where(_isOutstanding).toList();
    final outstanding = outstandingRows.length;
    final completed = allRows
        .where((row) => row.statusKey == DeliveryNoteStatusKey.completed)
        .length;
    final draft = allRows.where((row) => row.docStatus == 0).length;
    final outstandingValue = outstandingRows.fold<double>(
      0,
      (total, row) => total + row.value,
    );

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: logisticsPagePaddingOf(context),
        children: [
          LogisticsSectionHeader(
            title: 'Delivery Monitoring',
            subtitle: '$outstanding outstanding delivery perlu dicek',
            icon: Icons.assignment_turned_in_rounded,
          ),
          const SizedBox(height: 14),
          LogisticsMetricGrid(
            footer: '${allRows.length} dokumen pengiriman dimuat',
            items: [
              LogisticsMetricItem(
                label: 'Outstanding',
                value: '$outstanding',
                icon: Icons.pending_actions_rounded,
                color: AppColors.warning,
              ),
              LogisticsMetricItem(
                label: 'Completed',
                value: '$completed',
                icon: Icons.task_alt_rounded,
                color: AppColors.success,
              ),
              LogisticsMetricItem(
                label: 'Draft',
                value: '$draft',
                icon: Icons.edit_note_rounded,
                color: AppColors.slate,
              ),
              LogisticsMetricItem(
                label: 'Nilai Outstanding',
                value: 'Rp ${formatErpCurrency(outstandingValue)}',
                icon: Icons.payments_outlined,
                color: AppColors.primary,
                compactValue: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          LogisticsSearchField(
            controller: _search,
            onChanged: _searchChanged,
            hintText: 'Cari Delivery Note atau customer',
          ),
          const SizedBox(height: 10),
          _DeliveryScopeSelector(
            selected: _scope,
            onChanged: (scope) => setState(() => _scope = scope),
          ),
          if (appState.isDeliveryNotesLoading) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(),
          ],
          if (appState.deliveryNotesError != null) ...[
            const SizedBox(height: 10),
            LogisticsInfoPanel(
              message: _friendlyError(appState.deliveryNotesError!),
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            LogisticsInfoPanel(
              message: _error!,
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
            ),
          ],
          logisticsSectionGap,
          LogisticsSectionHeader(
            title: 'Delivery Notes Mobile',
            subtitle: '${rows.length} dokumen ditampilkan',
            icon: Icons.description_outlined,
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty && !appState.isDeliveryNotesLoading)
            const ErpEmptyState(
              title: 'Delivery Note tidak ditemukan',
              message: 'Ubah filter/pencarian atau tarik untuk refresh.',
            )
          else
            ...rows.map(_deliveryCard),
          if (appState.hasMoreDeliveryNotes ||
              appState.isMoreDeliveryNotesLoading) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: appState.isMoreDeliveryNotesLoading
                    ? null
                    : () => context
                          .read<LogisticsDeliveryState>()
                          .loadMoreDeliveryNotes(),
                icon: appState.isMoreDeliveryNotesLoading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(
                  appState.isMoreDeliveryNotesLoading
                      ? 'Loading delivery...'
                      : 'Load more delivery notes',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deliveryCard(DeliveryNote row) {
    final busy = _busyId == row.id;
    final statusColor = _deliveryStatusColor(row);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () => _openDetail(row),
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
                CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.1),
                  foregroundColor: statusColor,
                  child: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.local_shipping_outlined),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.id,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        row.customer,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          LogisticsStatusChip(
                            label: row.statusText,
                            color: statusColor,
                          ),
                          _ProofStatusChip(deliveryNoteId: row.id),
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
                      'Rp ${formatErpCurrency(row.value)}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.slate,
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

  Color _deliveryStatusColor(DeliveryNote row) {
    if (row.statusKey == DeliveryNoteStatusKey.completed) {
      return AppColors.success;
    }
    if (row.statusKey == DeliveryNoteStatusKey.cancelled ||
        row.statusKey == DeliveryNoteStatusKey.closed) {
      return AppColors.slate;
    }
    if (!isDocSubmitted(row.docStatus)) return AppColors.warning;
    return AppColors.primary;
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _LogisticsDeliveryDetailScreen extends StatefulWidget {
  final DeliveryNote row;
  final Future<void> Function(DeliveryNote row) onUploadPhoto;
  final Future<void> Function(DeliveryNote row) onCaptureSignature;

  const _LogisticsDeliveryDetailScreen({
    required this.row,
    required this.onUploadPhoto,
    required this.onCaptureSignature,
  });

  @override
  State<_LogisticsDeliveryDetailScreen> createState() =>
      _LogisticsDeliveryDetailScreenState();
}

class _LogisticsDeliveryDetailScreenState
    extends State<_LogisticsDeliveryDetailScreen> {
  var _busy = false;
  var _trackingBusy = false;
  var _proofRefresh = 0;
  String? _trackingError;

  Future<void> _run(Future<void> Function(DeliveryNote row) action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action(widget.row);
      if (mounted) setState(() => _proofRefresh++);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startTracking() async {
    if (_trackingBusy) return;
    setState(() {
      _trackingBusy = true;
      _trackingError = null;
    });
    try {
      final point = await context
          .read<LogisticsDeliveryState>()
          .startDeliveryDriverTracking(widget.row);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tracking driver dimulai. Akurasi ${point.accuracy.toStringAsFixed(0)} m.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _trackingError = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _trackingBusy = false);
    }
  }

  Future<void> _updateLocation() async {
    if (_trackingBusy) return;
    setState(() {
      _trackingBusy = true;
      _trackingError = null;
    });
    try {
      final point = await context
          .read<LogisticsDeliveryState>()
          .recordDeliveryDriverLocation(widget.row);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lokasi driver tersimpan. Akurasi ${point.accuracy.toStringAsFixed(0)} m.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _trackingError = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _trackingBusy = false);
    }
  }

  Future<void> _stopTracking() async {
    if (_trackingBusy) return;
    setState(() {
      _trackingBusy = true;
      _trackingError = null;
    });
    try {
      await context.read<LogisticsDeliveryState>().stopDeliveryDriverTracking();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tracking driver dihentikan.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _trackingError = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _trackingBusy = false);
    }
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final appState = context.watch<LogisticsDeliveryState>();
    final trackingThisNote = appState.activeDeliveryTrackingNote == row.id;
    final latestPoint = appState.latestDeliveryTrackingNote == row.id
        ? appState.latestDeliveryDriverLocation
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'Detail Delivery',
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppColors.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.local_shipping_rounded,
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.id,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              row.customer,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFE3F2EA),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      LogisticsStatusChip(
                        label: row.statusText,
                        color: AppColors.white,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _DetailMetricPill(
                          label: 'Posting Date',
                          value: row.date.isEmpty ? '-' : row.date,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DetailMetricPill(
                          label: 'Total',
                          value: 'Rp ${formatErpCurrency(row.value)}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DetailMetricPill(
                          label: 'Qty',
                          value: '${row.itemsCount}',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DetailMetricPill(
                          label: 'Status',
                          value: row.statusText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(widget.onUploadPhoto),
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Foto POD'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(widget.onCaptureSignature),
                    icon: const Icon(Icons.draw_rounded),
                    label: const Text('Tanda Tangan'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DriverTrackingCard(
              active: trackingThisNote,
              busy: _trackingBusy,
              latestPoint: latestPoint,
              error: _trackingError,
              onStart: _startTracking,
              onUpdate: _updateLocation,
              onStop: _stopTracking,
            ),
            const SizedBox(height: 16),
            _DeliveryProofSection(
              key: ValueKey('${row.id}-$_proofRefresh'),
              deliveryNoteId: row.id,
            ),
            const SizedBox(height: 16),
            _DeliveryItemsSection(initialRow: row),
          ],
        ),
      ),
    );
  }
}

class _DriverTrackingCard extends StatelessWidget {
  final bool active;
  final bool busy;
  final VisitLocationPoint? latestPoint;
  final String? error;
  final VoidCallback onStart;
  final VoidCallback onUpdate;
  final VoidCallback onStop;

  const _DriverTrackingCard({
    required this.active,
    required this.busy,
    required this.latestPoint,
    required this.error,
    required this.onStart,
    required this.onUpdate,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final point = latestPoint;
    final capturedAt = point == null
        ? '-'
        : '${point.capturedAt.year.toString().padLeft(4, '0')}-'
              '${point.capturedAt.month.toString().padLeft(2, '0')}-'
              '${point.capturedAt.day.toString().padLeft(2, '0')} '
              '${point.capturedAt.hour.toString().padLeft(2, '0')}:'
              '${point.capturedAt.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? AppColors.primary.withValues(alpha: 0.22)
              : AppColors.border,
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.softGreen,
                foregroundColor: AppColors.primary,
                child: Icon(
                  active
                      ? Icons.location_searching_rounded
                      : Icons.location_on_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GPS Tracking Driver',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      active
                          ? 'Aktif, lokasi dikirim tiap 5 menit'
                          : 'Mulai tracking saat driver berangkat',
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              LogisticsStatusChip(
                label: active ? 'Aktif' : 'Standby',
                color: active ? AppColors.success : AppColors.slate,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                _trackingRow('Update terakhir', capturedAt),
                const SizedBox(height: 8),
                _trackingRow(
                  'Koordinat',
                  point == null
                      ? '-'
                      : '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
                ),
                const SizedBox(height: 8),
                _trackingRow(
                  'Akurasi',
                  point == null
                      ? '-'
                      : '${point.accuracy.toStringAsFixed(0)} m',
                ),
              ],
            ),
          ),
          if (error?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : (active ? onStop : onStart),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          active
                              ? Icons.stop_rounded
                              : Icons.play_arrow_rounded,
                        ),
                  label: Text(active ? 'Stop' : 'Mulai'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onUpdate,
                  icon: const Icon(Icons.my_location_rounded),
                  label: const Text('Update'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _trackingRow(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 105,
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.slate,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ],
  );
}

class _DetailMetricPill extends StatelessWidget {
  const _DetailMetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.white.withValues(alpha: 0.12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFE3F2EA),
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _DeliverySignatureDocumentScreen extends StatefulWidget {
  const _DeliverySignatureDocumentScreen({required this.initialRow});

  final DeliveryNote initialRow;

  @override
  State<_DeliverySignatureDocumentScreen> createState() =>
      _DeliverySignatureDocumentScreenState();
}

class _DeliverySignatureDocumentScreenState
    extends State<_DeliverySignatureDocumentScreen> {
  final _strokes = <List<Offset>>[];
  late Future<DeliveryNote> _future;
  Size _canvasSize = Size.zero;
  bool _saving = false;

  bool get _hasSignature => _strokes.any((stroke) => stroke.length > 1);

  @override
  void initState() {
    super.initState();
    _future = context.read<LogisticsDeliveryState>().loadDeliveryNoteDetail(
      widget.initialRow.id,
    );
  }

  void _startStroke(Offset point, Size canvasSize) {
    setState(() {
      _canvasSize = canvasSize;
      _strokes.add([_clampPoint(point, canvasSize)]);
    });
  }

  void _appendStroke(Offset point, Size canvasSize) {
    if (_strokes.isEmpty) return;
    setState(() {
      _canvasSize = canvasSize;
      _strokes.last.add(_clampPoint(point, canvasSize));
    });
  }

  Offset _clampPoint(Offset point, Size size) => Offset(
    point.dx.clamp(0, size.width).toDouble(),
    point.dy.clamp(0, size.height).toDouble(),
  );

  Future<void> _saveSignature() async {
    if (!_hasSignature || _canvasSize == Size.zero || _saving) return;
    setState(() => _saving = true);
    try {
      final safeName = widget.initialRow.id.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]+'),
        '_',
      );
      final file = File(
        '${Directory.systemTemp.path}/delivery_note_signature_$safeName'
        '_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      final data = await _renderSignaturePng();
      await file.writeAsBytes(data, flush: true);
      if (mounted) Navigator.pop(context, file.path);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<List<int>> _renderSignaturePng() async {
    const outputWidth = 1200;
    const outputHeight = 520;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = AppColors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
      paint,
    );
    canvas.scale(
      outputWidth / _canvasSize.width,
      outputHeight / _canvasSize.height,
    );
    _SignaturePainter(
      strokes: _strokes,
      showGuide: false,
    ).paint(canvas, _canvasSize);
    final picture = recorder.endRecording();
    final image = await picture.toImage(outputWidth, outputHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Tanda tangan gagal dibuat. Coba ulangi.');
    }
    return byteData.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'Tanda Tangan Dokumen',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving || _strokes.isEmpty
                      ? null
                      : () => setState(_strokes.clear),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Ulangi'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving || !_hasSignature ? null : _saveSignature,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt_rounded),
                  label: Text(_saving ? 'Menyimpan...' : 'Simpan TTD'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<DeliveryNote>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final detail = snapshot.data ?? widget.initialRow;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.softGreen,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.zoom_out_map_rounded,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Cubit untuk zoom dokumen, geser untuk melihat area lain, lalu tanda tangan di kotak penerima.',
                          style: TextStyle(
                            color: AppColors.slate,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.7,
                    maxScale: 3.5,
                    boundaryMargin: const EdgeInsets.all(180),
                    child: Center(
                      child: _DeliverySignatureDocument(
                        detail: detail,
                        strokes: _strokes,
                        onStartStroke: _startStroke,
                        onAppendStroke: _appendStroke,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DeliverySignatureDocument extends StatelessWidget {
  const _DeliverySignatureDocument({
    required this.detail,
    required this.strokes,
    required this.onStartStroke,
    required this.onAppendStroke,
  });

  final DeliveryNote detail;
  final List<List<Offset>> strokes;
  final void Function(Offset point, Size canvasSize) onStartStroke;
  final void Function(Offset point, Size canvasSize) onAppendStroke;

  @override
  Widget build(BuildContext context) {
    final items = detail.items;
    return Container(
      width: 780,
      margin: const EdgeInsets.all(18),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: AppColors.navy, fontSize: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DELIVERY NOTE',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        detail.id,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                _DocumentInfoBlock(
                  rows: [
                    ('Posting Date', detail.date.isEmpty ? '-' : detail.date),
                    ('Status', detail.statusText),
                    ('Total Qty', '${detail.itemsCount}'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _DocumentSection(
                    title: 'Customer',
                    lines: [detail.customer],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _DocumentSection(
                    title: 'Delivery Summary',
                    lines: [
                      'Total: Rp ${formatErpCurrency(detail.value)}',
                      'Items: ${items.isEmpty ? detail.itemsCount : items.length}',
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Items',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 8),
            _DocumentItemsTable(items: items),
            const SizedBox(height: 28),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _DocumentSignatureBox(
                    title: 'Diserahkan Oleh',
                    subtitle: 'Driver / Warehouse',
                    enabled: false,
                    strokes: const [],
                    onStartStroke: (_, _) {},
                    onAppendStroke: (_, _) {},
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _DocumentSignatureBox(
                    title: 'Diterima Oleh',
                    subtitle: 'Tanda tangan customer',
                    enabled: true,
                    strokes: strokes,
                    onStartStroke: onStartStroke,
                    onAppendStroke: onAppendStroke,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentInfoBlock extends StatelessWidget {
  const _DocumentInfoBlock({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: rows
            .map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        row.$1,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        row.$2,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DocumentSection extends StatelessWidget {
  const _DocumentSection({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Text(
              line,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentItemsTable extends StatelessWidget {
  const _DocumentItemsTable({required this.items});

  final List<DeliveryNoteItem> items;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(12).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _row(
            values: const ['No', 'Item', 'Qty', 'UOM', 'Warehouse'],
            header: true,
          ),
          if (visibleItems.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Item detail belum tersedia.',
                style: TextStyle(color: AppColors.slate),
              ),
            )
          else
            ...visibleItems.indexed.map(
              (entry) => _row(
                values: [
                  '${entry.$1 + 1}',
                  entry.$2.itemName,
                  _formatQty(entry.$2.qty),
                  entry.$2.uom.isEmpty ? '-' : entry.$2.uom,
                  entry.$2.warehouse.isEmpty ? '-' : entry.$2.warehouse,
                ],
              ),
            ),
          if (items.length > visibleItems.length)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                '+${items.length - visibleItems.length} item lainnya',
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatQty(num value) {
    final fixed = value.toStringAsFixed(
      value.truncateToDouble() == value ? 0 : 2,
    );
    return fixed.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  }

  Widget _row({required List<String> values, bool header = false}) {
    final weights = [0.7, 4.0, 1.2, 1.0, 2.4];
    return Container(
      decoration: BoxDecoration(
        color: header ? AppColors.background : AppColors.white,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              flex: (weights[i] * 10).round(),
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Text(
                  values[i],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: header ? AppColors.slate : AppColors.navy,
                    fontSize: 11,
                    fontWeight: header ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DocumentSignatureBox extends StatelessWidget {
  const _DocumentSignatureBox({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.strokes,
    required this.onStartStroke,
    required this.onAppendStroke,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final List<List<Offset>> strokes;
  final void Function(Offset point, Size canvasSize) onStartStroke;
  final void Function(Offset point, Size canvasSize) onAppendStroke;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, 150);
            return Container(
              height: size.height,
              decoration: BoxDecoration(
                color: enabled ? AppColors.background : AppColors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: enabled ? AppColors.primary : AppColors.border,
                  width: enabled ? 1.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: enabled
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) =>
                            onStartStroke(details.localPosition, size),
                        onPanUpdate: (details) =>
                            onAppendStroke(details.localPosition, size),
                        child: CustomPaint(
                          painter: _SignaturePainter(strokes: strokes),
                          size: size,
                        ),
                      )
                    : const Center(
                        child: Text(
                          'TTD / Nama',
                          style: TextStyle(
                            color: AppColors.slate,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.slate,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SignatureCaptureSheet extends StatefulWidget {
  const _SignatureCaptureSheet({required this.deliveryNoteId});

  final String deliveryNoteId;

  @override
  State<_SignatureCaptureSheet> createState() => _SignatureCaptureSheetState();
}

class _SignatureCaptureSheetState extends State<_SignatureCaptureSheet> {
  final List<List<Offset>> _strokes = [];
  Size _canvasSize = Size.zero;
  bool _saving = false;

  bool get _hasSignature => _strokes.any((stroke) => stroke.length > 1);

  void _startStroke(Offset point, Size canvasSize) {
    setState(() {
      _canvasSize = canvasSize;
      _strokes.add([_clampPoint(point, canvasSize)]);
    });
  }

  void _appendStroke(Offset point, Size canvasSize) {
    if (_strokes.isEmpty) return;
    setState(() {
      _canvasSize = canvasSize;
      _strokes.last.add(_clampPoint(point, canvasSize));
    });
  }

  Offset _clampPoint(Offset point, Size size) => Offset(
    point.dx.clamp(0, size.width).toDouble(),
    point.dy.clamp(0, size.height).toDouble(),
  );

  Future<void> _saveSignature() async {
    if (!_hasSignature || _canvasSize == Size.zero) return;
    setState(() => _saving = true);
    try {
      final safeName = widget.deliveryNoteId.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]+'),
        '_',
      );
      final file = File(
        '${Directory.systemTemp.path}/signature_$safeName'
        '_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      final data = await _renderSignaturePng();
      await file.writeAsBytes(data, flush: true);
      if (mounted) Navigator.pop(context, file.path);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<List<int>> _renderSignaturePng() async {
    const outputWidth = 1200;
    const outputHeight = 520;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = AppColors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
      paint,
    );
    canvas.scale(
      outputWidth / _canvasSize.width,
      outputHeight / _canvasSize.height,
    );
    _SignaturePainter(
      strokes: _strokes,
      showGuide: false,
    ).paint(canvas, _canvasSize);
    final picture = recorder.endRecording();
    final image = await picture.toImage(outputWidth, outputHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Tanda tangan gagal dibuat. Coba ulangi.');
    }
    return byteData.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          16,
          18,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.softGreen,
                  foregroundColor: AppColors.primary,
                  child: Icon(Icons.draw_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tanda Tangan Customer',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.deliveryNoteId,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Minta customer tanda tangan di area bawah ini. Hasilnya akan disimpan sebagai attachment Delivery Note.',
              style: TextStyle(color: AppColors.slate, fontSize: 12),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final canvasSize = Size(constraints.maxWidth, 230);
                return Container(
                  height: canvasSize.height,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) =>
                          _startStroke(details.localPosition, canvasSize),
                      onPanUpdate: (details) =>
                          _appendStroke(details.localPosition, canvasSize),
                      child: CustomPaint(
                        painter: _SignaturePainter(strokes: _strokes),
                        size: canvasSize,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving || _strokes.isEmpty
                        ? null
                        : () => setState(_strokes.clear),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Ulangi'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving || !_hasSignature
                        ? null
                        : _saveSignature,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt_rounded),
                    label: Text(_saving ? 'Menyimpan...' : 'Simpan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryItemsSection extends StatefulWidget {
  const _DeliveryItemsSection({required this.initialRow});

  final DeliveryNote initialRow;

  @override
  State<_DeliveryItemsSection> createState() => _DeliveryItemsSectionState();
}

class _DeliveryItemsSectionState extends State<_DeliveryItemsSection> {
  late Future<DeliveryNote> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<LogisticsDeliveryState>().loadDeliveryNoteDetail(
      widget.initialRow.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DeliveryNote>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _ItemsLoadingCard();
        }

        if (snapshot.hasError) {
          return LogisticsInfoPanel(
            message:
                'Item Delivery Note belum bisa dimuat. ${_friendlyError(snapshot.error!)}',
            icon: Icons.error_outline_rounded,
            color: AppColors.danger,
          );
        }

        final detail = snapshot.data ?? widget.initialRow;
        if (detail.items.isEmpty) {
          return const LogisticsInfoPanel(
            message:
                'Item detail belum tersedia. Tarik untuk refresh atau cek kembali dokumen pengiriman.',
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
                    'Item Dikirim',
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
            ...detail.items.map(_DeliveryItemCard.new),
          ],
        );
      },
    );
  }

  static String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _DeliveryProofSection extends StatefulWidget {
  const _DeliveryProofSection({super.key, required this.deliveryNoteId});

  final String deliveryNoteId;

  @override
  State<_DeliveryProofSection> createState() => _DeliveryProofSectionState();
}

class _DeliveryProofSectionState extends State<_DeliveryProofSection> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadProofs();
  }

  Future<List<Map<String, dynamic>>> _loadProofs() {
    return context.read<LogisticsDeliveryState>().fetchDocumentAttachments(
      doctype: 'Delivery Note',
      documentName: widget.deliveryNoteId,
    );
  }

  void _refresh() {
    setState(() => _future = _loadProofs());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.attach_file_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bukti Pengiriman',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          loading
                              ? 'Memuat attachment...'
                              : '${rows.length} attachment tersimpan',
                          style: const TextStyle(
                            color: AppColors.slate,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: loading ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                    color: AppColors.primary,
                  ),
                ],
              ),
              if (loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ] else if (snapshot.hasError) ...[
                const SizedBox(height: 10),
                Text(
                  _friendlyError(snapshot.error!),
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ] else if (rows.isEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Belum ada foto POD atau tanda tangan. Upload bukti dari tombol di atas.',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                ...rows.take(5).map(_ProofFileTile.new),
                if (rows.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '+${rows.length - 5} attachment lainnya',
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class _ProofStatusChip extends StatefulWidget {
  const _ProofStatusChip({required this.deliveryNoteId});

  final String deliveryNoteId;

  @override
  State<_ProofStatusChip> createState() => _ProofStatusChipState();
}

class _ProofStatusChipState extends State<_ProofStatusChip> {
  late Future<int> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadCount();
  }

  Future<int> _loadCount() async {
    final files = await context
        .read<LogisticsDeliveryState>()
        .fetchDocumentAttachments(
          doctype: 'Delivery Note',
          documentName: widget.deliveryNoteId,
        );
    return files.length;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LogisticsStatusChip(
            label: 'Cek bukti...',
            color: AppColors.slate,
          );
        }

        if (snapshot.hasError) {
          return const LogisticsStatusChip(
            label: 'Bukti ?',
            color: AppColors.slate,
          );
        }

        final count = snapshot.data ?? 0;
        return LogisticsStatusChip(
          label: count > 0 ? 'Bukti $count' : 'Belum ada bukti',
          color: count > 0 ? AppColors.success : AppColors.warning,
        );
      },
    );
  }
}

class _ProofFileTile extends StatelessWidget {
  const _ProofFileTile(this.file);

  final Map<String, dynamic> file;

  @override
  Widget build(BuildContext context) {
    final name =
        file['file_name']?.toString() ??
        file['name']?.toString() ??
        'Attachment';
    final creation = file['creation']?.toString() ?? '';
    final url = file['file_url']?.toString() ?? '';
    final imageUrl = _isImage(name, url) && url.isNotEmpty
        ? _absoluteUrl(context, url)
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  imageUrl,
                  cacheWidth: 900,
                  filterQuality: FilterQuality.medium,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: AppColors.background,
                    alignment: Alignment.center,
                    child: const Text(
                      'Preview foto belum bisa dimuat',
                      style: TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 9),
          ],
          Row(
            children: [
              Icon(
                imageUrl.isNotEmpty
                    ? Icons.image_outlined
                    : Icons.insert_drive_file_outlined,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (creation.isNotEmpty)
                      Text(
                        creation,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.slate,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _isImage(String name, String url) {
    final value = '$name $url'.toLowerCase();
    return value.contains('.jpg') ||
        value.contains('.jpeg') ||
        value.contains('.png') ||
        value.contains('.webp') ||
        value.contains('.gif');
  }

  static String _absoluteUrl(BuildContext context, String url) {
    final appState = context.read<LogisticsDeliveryState>();
    return Uri.parse(appState.frappeService.baseUrl).resolve(url).toString();
  }
}

class _ItemsLoadingCard extends StatelessWidget {
  const _ItemsLoadingCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: const Row(
      children: [
        SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Memuat item Delivery Note...',
            style: TextStyle(
              color: AppColors.slate,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DeliveryItemCard extends StatelessWidget {
  const _DeliveryItemCard(this.item);

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
              child: _ItemMiniStat(
                label: 'Qty',
                value:
                    '${formatErpCurrency(item.qty)}${item.uom.isEmpty ? '' : ' ${item.uom}'}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ItemMiniStat(
                label: 'Rate',
                value: 'Rp ${formatErpCurrency(item.rate)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ItemMiniStat(
                label: 'Amount',
                value: 'Rp ${formatErpCurrency(item.amount)}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ItemMiniStat(
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

class _ItemMiniStat extends StatelessWidget {
  const _ItemMiniStat({required this.label, required this.value});

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

enum _DeliveryScope {
  all,
  draft,
  toBill,
  completed,
  returnIssued,
  cancelled,
  closed,
}

class _DeliveryScopeSelector extends StatelessWidget {
  const _DeliveryScopeSelector({
    required this.selected,
    required this.onChanged,
  });

  final _DeliveryScope selected;
  final ValueChanged<_DeliveryScope> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [
      (_DeliveryScope.all, 'Semua'),
      (_DeliveryScope.draft, 'Draft'),
      (_DeliveryScope.toBill, 'To Bill'),
      (_DeliveryScope.completed, 'Completed'),
      (_DeliveryScope.returnIssued, 'Return Issued'),
      (_DeliveryScope.cancelled, 'Cancelled'),
      (_DeliveryScope.closed, 'Closed'),
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

class _SignaturePainter extends CustomPainter {
  const _SignaturePainter({required this.strokes, this.showGuide = true});

  final List<List<Offset>> strokes;
  final bool showGuide;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGuide) {
      final guidePaint = Paint()
        ..color = AppColors.slate.withValues(alpha: 0.18)
        ..strokeWidth = 1.4;
      canvas.drawLine(
        Offset(22, size.height - 46),
        Offset(size.width - 22, size.height - 46),
        guidePaint,
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'Tanda tangan di sini',
          style: TextStyle(
            color: AppColors.slate.withValues(alpha: 0.45),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(24, size.height - 36));
    }

    final signaturePaint = Paint()
      ..color = AppColors.navy
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.4
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, signaturePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) {
    return oldDelegate.strokes != strokes || oldDelegate.showGuide != showGuide;
  }
}
