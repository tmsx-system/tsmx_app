import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/selling/promo_state.dart';
import '../../../theme/app_colors.dart';
import 'create_promo_request_screen.dart';
import '../shared/sales_ui.dart';

const Color _promoOrange = Color(0xFFEA580C);
const Color _promoTeal = Color(0xFF14B8A6);
const Color _promoGreen = Color(0xFF16A34A);

class PromoSessionTab extends StatefulWidget {
  const PromoSessionTab({super.key});

  @override
  State<PromoSessionTab> createState() => _PromoSessionTabState();
}

class _PromoSessionTabState extends State<PromoSessionTab> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _requests = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRequests());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadRequests,
          child: ListView.builder(
            padding: SalesUi.compactScreenPaddingOf(context),
            itemCount: 3 + _requestBodyCount,
            itemBuilder: (context, index) => _buildListItem(index),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'create-promo-session',
            backgroundColor: _promoOrange,
            foregroundColor: AppColors.white,
            elevation: 12,
            onPressed: _openCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Buat Promo',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  int get _requestBodyCount {
    if (_error != null || _isLoading || _requests.isEmpty) return 1;
    return _requests.length;
  }

  Widget _buildListItem(int index) {
    switch (index) {
      case 0:
        return SalesHeroCard(
          title: 'Pengajuan Promo Session',
          subtitle: 'Pantau promo sebelum diproses menjadi Promotional Scheme.',
          icon: Icons.local_offer_rounded,
          accent: _promoOrange,
          trailing: IconButton.filledTonal(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadRequests,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        );
      case 1:
        return SalesUi.gap();
    }

    final bodyIndex = index - 2;
    if (bodyIndex >= _requestBodyCount) return const SizedBox(height: 84);
    if (_error != null) return _errorCard(_error!);
    if (_isLoading) return _loadingCard();
    if (_requests.isEmpty) return _emptyCard();
    return _requestCard(_requests[bodyIndex]);
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CreatePromoRequestScreen()),
    );
    if (created != true || !mounted) return;
    await _loadRequests();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pengajuan promo berhasil dikirim.')),
    );
  }

  Future<void> _loadRequests() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final state = context.read<PromoState>();
      final rows = await state.fetchPromoRequestRows(
        fields: const [
          'name',
          'request_date',
          'company',
          'customer_group',
          'customer',
          'valid_from',
          'valid_upto',
          'status',
          'promo_note',
          'modified',
        ],
        filters: null,
      );
      if (!mounted) return;
      setState(() => _requests = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _loadingCard() {
    return const SalesInfoCard(
      child: SizedBox(
        height: 150,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }

  Widget _emptyCard() {
    return SalesInfoCard(
      child: SizedBox(
        height: 170,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _EmptyIcon(),
            SizedBox(height: 14),
            Text(
              'Belum ada pengajuan promo',
              style: TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Tekan tombol Buat Promo untuk membuat pengajuan baru.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return SalesInfoCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: AppColors.danger,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gagal memuat data',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Coba lagi',
            onPressed: _loadRequests,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.danger),
          ),
        ],
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> row) {
    final name = _text(row['name']);
    final status = _text(row['status'], fallback: 'Pending Approval');
    final company = _text(row['company'], fallback: '-');
    final target = _target(row, fallback: name);
    final period =
        '${_formatDate(row['valid_from'])} s/d ${_formatDate(row['valid_upto'])}';
    final note = _text(row['promo_note']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SalesInfoCard(
        accent: _promoOrange,
        onTap: () => _showDetail(row),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _promoOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.local_offer_rounded, color: _promoOrange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    target,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _miniChip(Icons.date_range_rounded, period),
                      _miniChip(Icons.business_rounded, company),
                    ],
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _statusChip(status),
          ],
        ),
      ),
    );
  }

  Widget _miniChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final normalized = status.toLowerCase();
    final isRejected =
        normalized.contains('reject') || normalized.contains('cancel');
    final isApproved =
        normalized.contains('approve') || normalized.contains('submit');
    final color = isRejected
        ? AppColors.danger
        : isApproved
        ? _promoGreen
        : _promoOrange;
    final bg = color.withValues(alpha: 0.12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final name = _text(row['name']);
        final status = _text(row['status'], fallback: 'Pending Approval');
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            builder: (context, controller) {
              return ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SalesHeroCard(
                    title: _target(row, fallback: name),
                    subtitle: name,
                    icon: Icons.local_offer_rounded,
                    accent: _promoOrange,
                    trailing: _statusChip(status),
                  ),
                  SalesUi.gap(),
                  SalesInfoCard(
                    accent: _promoTeal,
                    child: Column(
                      children: [
                        _detailRow('Tanggal', _formatDate(row['request_date'])),
                        _detailRow(
                          'Periode',
                          '${_formatDate(row['valid_from'])} s/d ${_formatDate(row['valid_upto'])}',
                        ),
                        _detailRow('Company', _text(row['company'])),
                        _detailRow(
                          'Customer Group',
                          _text(row['customer_group'], fallback: '-'),
                        ),
                        _detailRow(
                          'Customer',
                          _text(row['customer'], fallback: '-'),
                        ),
                        _detailRow(
                          'Catatan',
                          _text(row['promo_note'], fallback: '-'),
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value, {bool isLast = false}) {
    return Container(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12, top: isLast ? 12 : 0),
      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : AppColors.border,
          ),
        ),
      ),
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
              value,
              textAlign: TextAlign.right,
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
  }

  String _target(Map<String, dynamic> row, {required String fallback}) {
    final customer = _text(row['customer']);
    if (customer.isNotEmpty) return customer;
    final customerGroup = _text(row['customer_group']);
    if (customerGroup.isNotEmpty) return customerGroup;
    return fallback;
  }

  String _formatDate(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}

class _EmptyIcon extends StatelessWidget {
  const _EmptyIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(Icons.local_offer_outlined, color: AppColors.primary),
    );
  }
}
