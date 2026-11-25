import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/ripening_monitoring.dart';
import '../../../state/warehouse/ripening_monitoring_state.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_error_message.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../widgets/erp/erp_status_badge.dart';
import '../shared/warehouse_widgets.dart';
import 'create_ripening_monitoring_screen.dart';
import 'ripening_monitoring_detail_screen.dart';

class WarehouseQualityTab extends StatelessWidget {
  const WarehouseQualityTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: warehousePagePaddingOf(context),
      children: [
        const WarehouseSectionHeader(
          title: 'Quality Control',
          subtitle: 'Pemeriksaan gudang',
          icon: Icons.fact_check_rounded,
        ),
        warehouseSectionGap,
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 14,
          childAspectRatio: 0.72,
          children: [
            WarehouseActionGridCard(
              title: 'Ripening',
              subtitle: 'Monitoring',
              icon: Icons.eco_rounded,
              color: const Color(0xFF16A34A),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RipeningMonitoringListScreen(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class RipeningMonitoringListScreen extends StatefulWidget {
  const RipeningMonitoringListScreen({super.key});

  @override
  State<RipeningMonitoringListScreen> createState() =>
      _RipeningMonitoringListScreenState();
}

class _RipeningMonitoringListScreenState
    extends State<RipeningMonitoringListScreen> {
  final _search = TextEditingController();
  final _dateFormat = DateFormat('dd MMM yyyy');
  Timer? _debounce;
  bool _loading = true;
  bool _canCreate = false;
  bool _canWrite = false;
  bool _canSubmit = false;
  bool _busy = false;
  int _loadGeneration = 0;
  String? _error;
  String? _company;
  List<String> _companies = const [];
  List<RipeningSummary> _rows = const [];

  RipeningMonitoringState get _api =>
      RipeningMonitoringState(context.read<WarehouseStockState>().appState);

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _bootstrap() async {
    unawaited(_loadCompanies());
    unawaited(_loadAccess());
    await _load();
  }

  Future<void> _loadCompanies() async {
    try {
      final companies = await _api.fetchCompanies();
      if (!mounted) return;
      final selected = companies.length == 1 ? companies.first : _company;
      final changedFilter = selected != _company;
      setState(() {
        _companies = companies;
        if (_company == null || !companies.contains(_company)) {
          _company = companies.length == 1 ? companies.first : null;
        }
      });
      if (changedFilter && _company != null) unawaited(_load());
    } catch (_) {
      final app = context.read<WarehouseStockState>().appState;
      try {
        await app.loadSellingFilterOptions();
        if (!mounted) return;
        final companies = app.sellingCompanies;
        setState(() {
          _companies = companies;
          if (_company == null || !companies.contains(_company)) {
            _company = companies.length == 1 ? companies.first : null;
          }
        });
      } catch (_) {}
    }
  }

  Future<void> _loadAccess() async {
    final access = await Future.wait([
      _api.canCreate(),
      _api.canWrite(),
      _api.canSubmit(),
    ]);
    if (!mounted) return;
    setState(() {
      _canCreate = access[0];
      _canWrite = access[1];
      _canSubmit = access[2];
    });
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _api.fetchList(
        company: _company,
        query: _search.text,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _rows = rows);
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openCreate({String? name}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateRipeningMonitoringScreen(
          company: _company,
          existingName: name,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _openDetail(RipeningSummary row) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RipeningMonitoringDetailScreen(
          name: row.name,
          canEdit: row.isDraft && _canWrite,
          canSubmit: row.isDraft && _canSubmit,
          onChanged: _load,
        ),
      ),
    );
  }

  Future<void> _submit(RipeningSummary row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit Ripening Monitoring?'),
        content: Text(row.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.submit(row.name);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(captureErpError(context, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Ripening Monitoring')),
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _openCreate(),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Buat Monitoring'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: warehousePagePaddingOf(context),
          children: [
            const WarehouseSectionHeader(
              title: 'Ripening Monitoring',
              subtitle: 'Pengamatan gassing, sampling, dan hasil warna',
              icon: Icons.eco_rounded,
            ),
            warehouseSectionGap,
            ErpSearchableFilterField(
              label: 'Company',
              selectedId: _company,
              options: [
                for (final company in _companies)
                  ErpItemOption(id: company, label: company),
              ],
              decoration: _whiteField(),
              allLabel: 'Semua company',
              onSelected: (value) {
                setState(() => _company = value);
                _load();
              },
            ),
            warehouseItemGap,
            TextField(
              controller: _search,
              decoration: _whiteField(
                hint: 'Cari nomor dokumen',
                icon: Icons.search_rounded,
              ),
            ),
            warehouseItemGap,
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_error != null)
              ErpEmptyState(
                title: 'Ripening Monitoring tidak tampil',
                message: _error!,
                icon: Icons.error_outline_rounded,
              )
            else if (_rows.isEmpty)
              const ErpEmptyState(
                title: 'Belum ada Ripening Monitoring',
                message: 'Buat pengamatan baru dari tombol di bawah.',
                icon: Icons.eco_outlined,
              )
            else
              for (final row in _rows) _card(row),
          ],
        ),
      ),
    );
  }

  Widget _card(RipeningSummary row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.white,
        elevation: 0,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openDetail(row),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text('🍌', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.name,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          if (row.company.isNotEmpty)
                            Text(
                              row.company,
                              style: const TextStyle(
                                color: AppColors.slate,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ErpStatusBadge(statusText: row.statusLabel),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: PopupMenuButton<String>(
                        tooltip: 'Actions',
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: AppColors.white,
                        icon: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.more_horiz_rounded,
                            color: AppColors.slate,
                            size: 19,
                          ),
                        ),
                        onSelected: (value) {
                          if (value == 'detail') _openDetail(row);
                          if (value == 'edit') _openCreate(name: row.name);
                          if (value == 'submit') _submit(row);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'detail',
                            child: _RipeningMenuLabel(
                              icon: Icons.visibility_outlined,
                              label: 'Lihat Detail',
                            ),
                          ),
                          if (row.isDraft && _canWrite)
                            const PopupMenuItem(
                              value: 'edit',
                              child: _RipeningMenuLabel(
                                icon: Icons.edit_outlined,
                                label: 'Edit',
                              ),
                            ),
                          if (row.isDraft && _canSubmit)
                            const PopupMenuItem(
                              value: 'submit',
                              child: _RipeningMenuLabel(
                                icon: Icons.send_rounded,
                                label: 'Submit',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _dateTile('Tanggal Gassing', row.tanggalGassing),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dateTile('Tanggal Sampling', row.tanggalSampling),
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

  Widget _dateTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _showDate(value),
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _whiteField({String? hint, IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 20, color: AppColors.navy),
      filled: true,
      fillColor: AppColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
    );
  }

  String _showDate(String value) {
    final parsed = DateTime.tryParse(value.length >= 10 ? value.substring(0, 10) : value);
    if (parsed == null) return value.isEmpty ? '-' : value;
    return _dateFormat.format(parsed);
  }
}

class _RipeningMenuLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RipeningMenuLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.navy),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
