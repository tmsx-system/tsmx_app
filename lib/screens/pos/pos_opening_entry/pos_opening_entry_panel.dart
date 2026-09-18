import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/pos_opening_entry.dart';
import '../../../state/pos/pos_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/erp_document_card.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/pos_document_actions.dart';
import '../shared/pos_ui.dart';
import 'create_pos_opening_entry_screen.dart';

class PosOpeningEntryPanel extends StatefulWidget {
  const PosOpeningEntryPanel({super.key});

  @override
  State<PosOpeningEntryPanel> createState() => _PosOpeningEntryPanelState();
}

class _PosOpeningEntryPanelState extends State<PosOpeningEntryPanel> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _didLoadPermissions = false;
  PosDoctypeActionPermissions _permissions =
      const PosDoctypeActionPermissions();

  static const _doctype = 'POS Opening Entry';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadPermissions) return;
    _didLoadPermissions = true;
    unawaited(_loadPermissions());
  }

  Future<void> _loadPermissions() async {
    final permissions = await PosDoctypeActionPermissions.load(
      context.read<PosState>(),
      _doctype,
    );
    if (!mounted) return;
    setState(() => _permissions = permissions);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      context.read<PosState>().setOpeningSearch(value);
    });
  }

  Future<void> _openEdit(String name) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreatePosOpeningEntryScreen(editName: name),
      ),
    );
    if (updated == true && mounted) {
      await context.read<PosState>().refreshOpenings();
    }
  }

  Future<void> _openDetail(PosOpeningEntry entry) async {
    final state = context.read<PosState>();
    try {
      final detail = await state.loadOpeningDetail(entry.id);
      if (!mounted) return;
      await showPosDocumentDetailSheet(
        context: context,
        title: detail.id,
        subtitle: 'POS Opening Entry',
        children: [
          PosSectionCard(
            title: 'Ringkasan',
            children: [
              PosDetailRow(label: 'POS Profile', value: detail.posProfile),
              PosDetailRow(label: 'Company', value: detail.company),
              PosDetailRow(label: 'Cashier', value: detail.user),
              PosDetailRow(
                label: 'Period Start',
                value: detail.periodStartDate,
              ),
              PosDetailRow(label: 'Posting Date', value: detail.postingDate),
              PosDetailRow(label: 'Status', value: detail.statusText),
              PosDetailRow(
                label: 'Opening Total',
                value: 'Rp ${formatErpCurrency(detail.totalOpeningAmount)}',
              ),
            ],
          ),
          if (detail.balanceDetails.isNotEmpty)
            PosSectionCard(
              title: 'Balance Details',
              children: [
                for (final row in detail.balanceDetails)
                  PosDetailRow(
                    label: row.modeOfPayment,
                    value: 'Rp ${formatErpCurrency(row.openingAmount)}',
                  ),
              ],
            ),
          Builder(
            builder: (context) {
              final actions = buildPosDocumentActionButtons(
                context: context,
                doctype: _doctype,
                name: detail.id,
                docStatus: detail.docStatus,
                permissions: _permissions,
                onChanged: () => state.refreshOpenings(),
                onEdit: () => _openEdit(detail.id),
              );
              if (actions.isEmpty) return const SizedBox.shrink();
              return PosSectionCard(title: 'Aksi', children: actions);
            },
          ),
        ],
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PosState>();
    final rows = state.openings;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: state.refreshOpenings,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: TmsxResponsive.pagePadding(context, top: 14, bottom: 110),
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearch,
            decoration: posFieldDecoration('Cari Opening Entry').copyWith(
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 14),
          if (state.openingsLoading && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (state.openingsError != null && rows.isEmpty)
            ErpErrorBox(message: state.openingsError!)
          else if (rows.isEmpty)
            const ErpEmptyState(
              title: 'Belum ada Opening Entry',
              message: 'Buat opening untuk memulai sesi kasir.',
            )
          else
            TmsxResponsiveCardGrid(
              children: [
                for (final entry in rows)
                  ErpDocumentCard(
                    id: entry.id,
                    party: entry.posProfile.isEmpty
                        ? entry.user
                        : entry.posProfile,
                    statusText: entry.statusText,
                    date: entry.periodStartDate.isEmpty
                        ? entry.postingDate
                        : entry.periodStartDate,
                    value: entry.totalOpeningAmount,
                    trailing: entry.user,
                    onTap: () => _openDetail(entry),
                    onEdit: _permissions.canWrite && entry.docStatus == 0
                        ? () => _openEdit(entry.id)
                        : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
