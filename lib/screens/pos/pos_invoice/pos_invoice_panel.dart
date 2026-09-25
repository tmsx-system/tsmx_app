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
import '../shared/pos_document_actions.dart';
import '../../../widgets/print/erp_bluetooth_print.dart';
import '../shared/pos_list_filters.dart';
import '../shared/pos_ui.dart';
import 'create_pos_invoice_screen.dart';

class PosInvoicePanel extends StatefulWidget {
  const PosInvoicePanel({super.key});

  @override
  State<PosInvoicePanel> createState() => _PosInvoicePanelState();
}

class _PosInvoicePanelState extends State<PosInvoicePanel> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _didLoadPermissions = false;
  bool _didLoadProfiles = false;
  bool _didLoadInvoices = false;
  List<String> _profiles = const [];
  PosDoctypeActionPermissions _permissions =
      const PosDoctypeActionPermissions();

  static const _doctype = 'POS Invoice';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didLoadPermissions) {
      _didLoadPermissions = true;
      unawaited(_loadPermissions());
    }
    if (!_didLoadProfiles) {
      _didLoadProfiles = true;
      unawaited(_loadProfiles());
    }
    if (!_didLoadInvoices) {
      _didLoadInvoices = true;
      unawaited(context.read<PosState>().refreshInvoices());
    }
  }

  Future<void> _loadPermissions() async {
    final permissions = await PosDoctypeActionPermissions.load(
      context.read<PosState>(),
      _doctype,
      includePrint: true,
    );
    if (!mounted) return;
    setState(() => _permissions = permissions);
  }

  Future<void> _loadProfiles() async {
    try {
      final profiles = await context
          .read<PosState>()
          .fetchSelectableProfileNames();
      if (!mounted) return;
      setState(() => _profiles = profiles);
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      context.read<PosState>().setInvoiceSearch(value);
    });
  }

  bool get _hasActiveFilters {
    final state = context.read<PosState>();
    return _searchController.text.trim().isNotEmpty ||
        state.invoiceProfileFilter != null ||
        state.invoiceStatusFilter != null;
  }

  Future<void> _resetFilters() async {
    _searchController.clear();
    setState(() {});
    await context.read<PosState>().clearInvoiceListFilters();
  }

  Future<void> _openEdit(String name) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreatePosInvoiceScreen(editName: name),
      ),
    );
    if (updated == true && mounted) {
      await context.read<PosState>().refreshInvoices();
    }
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
          Builder(
            builder: (context) {
              final actions = buildPosDocumentActionButtons(
                context: context,
                doctype: _doctype,
                name: detail.id,
                docStatus: detail.docStatus,
                permissions: _permissions,
                onChanged: () => state.refreshInvoices(),
                onEdit: () => _openEdit(detail.id),
                enablePrint: true,
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
    final rows = state.invoices;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: state.refreshInvoices,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: TmsxResponsive.pagePadding(context, top: 14, bottom: 110),
        children: [
          PosListFilterBar(
            searchController: _searchController,
            searchHint: 'Cari POS Invoice',
            onSearchChanged: _onSearch,
            profiles: _profiles,
            selectedProfile: state.invoiceProfileFilter,
            onProfileChanged: (value) =>
                context.read<PosState>().setInvoiceProfileFilter(value),
            statusChips: posInvoiceStatusChips(),
            selectedStatus: state.invoiceStatusFilter,
            onStatusChanged: (value) =>
                context.read<PosState>().setInvoiceStatusFilter(value),
            hasActiveFilters: _hasActiveFilters,
            onReset: _resetFilters,
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
              title: 'Tidak ada POS Invoice',
              message: 'Coba ubah filter POS Profile / Status, atau buat transaksi baru.',
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
                    onEdit: _permissions.canWrite && invoice.docStatus == 0
                        ? () => _openEdit(invoice.id)
                        : null,
                    onDownload: _permissions.canPrint
                        ? () => downloadAndSharePosPdf(
                              context,
                              _doctype,
                              invoice.id,
                            )
                        : null,
                    onPrint: _permissions.canPrint
                        ? () async {
                            final format = await showPosPrintFormatPicker(
                              context: context,
                              doctype: _doctype,
                            );
                            if (format == null || !context.mounted) return;
                            await printErpPdfViaBluetooth(
                              context,
                              downloadPdf: () => context
                                  .read<PosState>()
                                  .downloadPosPdf(
                                    _doctype,
                                    invoice.id,
                                    printFormat: format,
                                  ),
                              title: 'POS Invoice ${invoice.id}',
                            );
                          }
                        : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
