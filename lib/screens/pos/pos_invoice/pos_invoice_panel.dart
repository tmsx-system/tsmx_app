import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/pos_invoice.dart';
import '../../../state/pos/pos_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_format.dart';
import '../../../widgets/erp/erp_document_card.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/pos_ui.dart';

class PosInvoicePanel extends StatefulWidget {
  const PosInvoicePanel({super.key});

  @override
  State<PosInvoicePanel> createState() => _PosInvoicePanelState();
}

class _PosInvoicePanelState extends State<PosInvoicePanel> {
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
      context.read<PosState>().setInvoiceSearch(value);
    });
  }

  Future<void> _openDetail(PosInvoice invoice) async {
    final state = context.read<PosState>();
    try {
      final detail = await state.loadInvoiceDetail(invoice.id);
      if (!mounted) return;
      await showPosDocumentDetailSheet(
        context: context,
        title: detail.id,
        subtitle: 'POS Invoice',
        children: [
          PosSectionCard(
            title: 'Ringkasan',
            children: [
              PosDetailRow(label: 'Customer', value: detail.party),
              PosDetailRow(label: 'POS Profile', value: detail.posProfile),
              PosDetailRow(label: 'Company', value: detail.company),
              PosDetailRow(label: 'Posting Date', value: detail.postingDate),
              PosDetailRow(label: 'Status', value: detail.statusText),
              PosDetailRow(
                label: 'Grand Total',
                value: 'Rp ${formatErpCurrency(detail.value)}',
              ),
              PosDetailRow(
                label: 'Outstanding',
                value: 'Rp ${formatErpCurrency(detail.outstandingAmount)}',
              ),
            ],
          ),
          if (detail.items.isNotEmpty)
            PosSectionCard(
              title: 'Items',
              children: [
                for (final item in detail.items)
                  PosDetailRow(
                    label: item.itemCode,
                    value:
                        '${item.qty} x Rp ${formatErpCurrency(item.rate)} = Rp ${formatErpCurrency(item.amount)}',
                  ),
              ],
            ),
          if (detail.payments.isNotEmpty)
            PosSectionCard(
              title: 'Payments',
              children: [
                for (final payment in detail.payments)
                  PosDetailRow(
                    label: payment.modeOfPayment,
                    value: 'Rp ${formatErpCurrency(payment.amount)}',
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
    final rows = state.invoices;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: state.refreshInvoices,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: TmsxResponsive.pagePadding(context, top: 14, bottom: 110),
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearch,
            decoration: posFieldDecoration('Cari POS Invoice').copyWith(
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 14),
          if (state.invoicesLoading && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (state.invoicesError != null && rows.isEmpty)
            ErpErrorBox(message: state.invoicesError!)
          else if (rows.isEmpty)
            const ErpEmptyState(
              title: 'Belum ada POS Invoice',
              message: 'Transaksi kasir akan muncul di sini.',
            )
          else
            TmsxResponsiveCardGrid(
              children: [
                for (final invoice in rows)
                  ErpDocumentCard(
                    id: invoice.id,
                    party: invoice.party,
                    statusText: invoice.statusText,
                    date: invoice.postingDate,
                    value: invoice.value,
                    trailing: invoice.posProfile,
                    onTap: () => _openDetail(invoice),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
