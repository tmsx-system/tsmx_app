import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/pos_profile.dart';
import '../../../state/pos/pos_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_document_card.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/pos_ui.dart';

class PosProfilePanel extends StatefulWidget {
  const PosProfilePanel({super.key});

  @override
  State<PosProfilePanel> createState() => _PosProfilePanelState();
}

class _PosProfilePanelState extends State<PosProfilePanel> {
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
      context.read<PosState>().setProfileSearch(value);
    });
  }

  Future<void> _openDetail(PosProfile profile) async {
    final state = context.read<PosState>();
    try {
      final detail = await state.loadProfileDetail(profile.id);
      if (!mounted) return;
      await showPosDocumentDetailSheet(
        context: context,
        title: detail.id,
        subtitle: 'POS Profile',
        children: [
          PosSectionCard(
            title: 'Ringkasan',
            children: [
              PosDetailRow(label: 'Company', value: detail.company),
              PosDetailRow(label: 'Warehouse', value: detail.warehouse),
              PosDetailRow(label: 'Customer', value: detail.customer),
              PosDetailRow(
                label: 'Price List',
                value: detail.sellingPriceList,
              ),
              PosDetailRow(label: 'Currency', value: detail.currency),
              PosDetailRow(
                label: 'Status',
                value: detail.isDisabled ? 'Disabled' : 'Active',
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
    final rows = state.profiles;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: state.refreshProfiles,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: TmsxResponsive.pagePadding(context, top: 14, bottom: 110),
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearch,
            decoration: posFieldDecoration('Cari POS Profile').copyWith(
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 14),
          if (state.profilesLoading && rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (state.profilesError != null && rows.isEmpty)
            ErpErrorBox(message: state.profilesError!)
          else if (rows.isEmpty)
            const ErpEmptyState(
              title: 'Belum ada POS Profile',
              message: 'Profile kasir dari ERPNext akan muncul di sini.',
            )
          else
            TmsxResponsiveCardGrid(
              children: [
                for (final profile in rows)
                  ErpDocumentCard(
                    id: profile.id,
                    party: profile.company.isEmpty
                        ? profile.warehouse
                        : profile.company,
                    statusText: profile.isDisabled ? 'Disabled' : 'Active',
                    date: profile.modified,
                    value: 0,
                    trailing: profile.warehouse,
                    onTap: () => _openDetail(profile),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
