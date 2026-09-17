import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/pos_closing_entry.dart';
import '../../../state/pos/pos_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/erp_document_card.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/pos_ui.dart';

class PosClosingEntryPanel extends StatefulWidget {
  const PosClosingEntryPanel({super.key});

  @override
  State<PosClosingEntryPanel> createState() => _PosClosingEntryPanelState();
}

class _PosClosingEntryPanelState extends State<PosClosingEntryPanel> {
  final _searchController = TextEditingController();
  Timer? _debounce;

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
      context.read<PosState>().setClosingSearch(value);
    });
  }

  Future<void> _openDetail(PosClosingEntry entry) async {
    final state = context.read<PosState>();
    try {
      final detail = await state.loadClosingDetail(entry.id);
      if (!mounted) return;
      await showPosDocumentDetailSheet(
        context: context,
        title: detail.id,
        subtitle: 'POS Closing Entry',
        children: [
          PosSectionCard(
            title: 'Ringkasan',
            children: [
              PosDetailRow(label: 'POS Profile', value: detail.posProfile),
              PosDetailRow(label: 'Opening Entry', value: detail.posOpeningEntry),
              PosDetailRow(label: 'Company', value: detail.company),
              PosDetailRow(label: 'User', value: detail.user),
              PosDetailRow(
                label: 'Period Start',
                value: detail.periodStartDate,
              ),
              PosDetailRow(label: 'Period End', value: detail.periodEndDate),
              PosDetailRow(label: 'Status', value: detail.statusText),
              PosDetailRow(
                label: 'Grand Total',
                value: 'Rp ${formatErpCurrency(detail.grandTotal)}',
              ),
            ],
          ),
          if (detail.paymentReconciliation.isNotEmpty)
            PosSectionCard(
              title: 'Payment Reconciliation',
              children: [
                for (final row in detail.paymentReconciliation)
                  PosDetailRow(
                    label: row.modeOfPayment,
                    value:
                        'Close Rp ${formatErpCurrency(row.closingAmount)} / Exp Rp ${formatErpCurrency(row.expectedAmount)}',
                  ),
              ],
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
    final rows = state.closings;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: state.refreshClosings,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: TmsxResponsive.pagePadding(context, top: 14, bottom: 110),
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearch,
            decoration: posFieldDecoration('Cari Closing Entry').copyWith(
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 14),
          if (state.closingsLoading && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (state.closingsError != null && rows.isEmpty)
            ErpErrorBox(message: state.closingsError!)
          else if (rows.isEmpty)
            const ErpEmptyState(
              title: 'Belum ada Closing Entry',
              message: 'Tutup sesi kasir untuk membuat closing entry.',
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
                    date: entry.periodEndDate.isEmpty
                        ? entry.postingDate
                        : entry.periodEndDate,
                    value: entry.grandTotal,
                    trailing: entry.user,
                    onTap: () => _openDetail(entry),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
