import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/app_state.dart';
import '../../theme/app_colors.dart';

class PosMainScreen extends StatefulWidget {
  const PosMainScreen({super.key});

  @override
  State<PosMainScreen> createState() => _PosMainScreenState();
}

class _PosMainScreenState extends State<PosMainScreen> {
  late Future<List<_PosAccessEntry>> _accessFuture;

  static const _items = [
    _PosItem(
      title: 'Dashboard POS',
      subtitle: 'Ringkasan dan workspace kasir',
      doctype: 'POS Invoice',
      route: '/app/point-of-sale',
      icon: Icons.dashboard_rounded,
      color: Color(0xFF2563EB),
    ),
    _PosItem(
      title: 'POS Profile',
      subtitle: 'Konfigurasi profile kasir',
      doctype: 'POS Profile',
      route: '/app/pos-profile',
      icon: Icons.badge_rounded,
      color: Color(0xFF0F766E),
    ),
    _PosItem(
      title: 'POS Opening Entry',
      subtitle: 'Buka sesi kasir',
      doctype: 'POS Opening Entry',
      route: '/app/pos-opening-entry',
      icon: Icons.login_rounded,
      color: Color(0xFF16A34A),
      needsCreate: true,
    ),
    _PosItem(
      title: 'POS Invoice',
      subtitle: 'Transaksi penjualan POS',
      doctype: 'POS Invoice',
      route: '/app/pos-invoice',
      icon: Icons.receipt_long_rounded,
      color: Color(0xFFF59E0B),
      needsCreate: true,
    ),
    _PosItem(
      title: 'POS Closing Entry',
      subtitle: 'Tutup sesi kasir',
      doctype: 'POS Closing Entry',
      route: '/app/pos-closing-entry/view/list',
      icon: Icons.logout_rounded,
      color: Color(0xFF7C3AED),
      needsCreate: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _accessFuture = _loadAccess();
  }

  Future<List<_PosAccessEntry>> _loadAccess() async {
    final state = context.read<AppState>();
    final entries = <_PosAccessEntry>[];
    for (final item in _items) {
      final canRead = await state.canReadDoctype(item.doctype);
      final canCreate = item.needsCreate
          ? await state.canCreateDoctype(item.doctype)
          : false;
      entries.add(
        _PosAccessEntry(item: item, canRead: canRead, canCreate: canCreate),
      );
    }
    return entries;
  }

  Future<void> _refresh() async {
    final next = _loadAccess();
    setState(() => _accessFuture = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.primary,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'POS',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (state.selectedSiteName.trim().isNotEmpty)
              Text(
                state.selectedSiteName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
      body: FutureBuilder<List<_PosAccessEntry>>(
        future: _accessFuture,
        builder: (context, snapshot) {
          final entries = snapshot.data;
          if (entries == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
              children: [
                _PosHeader(siteName: state.selectedSiteName),
                const SizedBox(height: 14),
                for (final entry in entries) ...[
                  _PosAccessCard(entry: entry, onTap: () => _openEntry(entry)),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEntry(_PosAccessEntry entry) async {
    final state = context.read<AppState>();
    final baseUrl = state.selectedSiteBaseUrl.trim();
    if (baseUrl.isEmpty) {
      _showSnack('Site ERPNext belum dipilih.');
      return;
    }
    if (!entry.canUse) {
      _showSnack('Akses ${entry.item.doctype} belum tersedia untuk user ini.');
      return;
    }

    final uri = Uri.parse(baseUrl).resolve(entry.item.route);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) _showSnack('Halaman POS tidak dapat dibuka.');
    } catch (_) {
      _showSnack('Halaman POS tidak dapat dibuka.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _PosHeader extends StatelessWidget {
  const _PosHeader({required this.siteName});

  final String siteName;

  @override
  Widget build(BuildContext context) {
    final label = siteName.trim().isEmpty ? 'ERPNext POS' : siteName.trim();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.point_of_sale_rounded,
              color: Color(0xFF2563EB),
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Dashboard dan transaksi POS ERPNext',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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
    );
  }
}

class _PosAccessCard extends StatelessWidget {
  const _PosAccessCard({required this.entry, required this.onTap});

  final _PosAccessEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final enabled = entry.canUse;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: enabled
                  ? item.color.withValues(alpha: 0.22)
                  : AppColors.border,
            ),
            boxShadow: AppColors.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: enabled ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  item.icon,
                  color: enabled ? item.color : AppColors.slate,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled ? AppColors.navy : AppColors.slate,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _AccessBadge(entry: entry),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccessBadge extends StatelessWidget {
  const _AccessBadge({required this.entry});

  final _PosAccessEntry entry;

  @override
  Widget build(BuildContext context) {
    final label = entry.canCreate
        ? 'Create'
        : entry.canRead
        ? 'Read'
        : 'No Access';
    final color = entry.canUse ? AppColors.primary : AppColors.slate;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PosItem {
  final String title;
  final String subtitle;
  final String doctype;
  final String route;
  final IconData icon;
  final Color color;
  final bool needsCreate;

  const _PosItem({
    required this.title,
    required this.subtitle,
    required this.doctype,
    required this.route,
    required this.icon,
    required this.color,
    this.needsCreate = false,
  });
}

class _PosAccessEntry {
  final _PosItem item;
  final bool canRead;
  final bool canCreate;

  const _PosAccessEntry({
    required this.item,
    required this.canRead,
    required this.canCreate,
  });

  bool get canUse => item.needsCreate ? canCreate || canRead : canRead;
}
