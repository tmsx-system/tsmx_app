import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_status_chip_bar.dart';
import 'pos_ui.dart';

class PosListFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final List<String> profiles;
  final String? selectedProfile;
  final ValueChanged<String?> onProfileChanged;
  final List<ErpStatusChip<String?>> statusChips;
  final String? selectedStatus;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback? onReset;
  final bool hasActiveFilters;

  const PosListFilterBar({
    super.key,
    required this.searchController,
    required this.searchHint,
    required this.onSearchChanged,
    required this.profiles,
    required this.selectedProfile,
    required this.onProfileChanged,
    required this.statusChips,
    required this.selectedStatus,
    required this.onStatusChanged,
    this.onReset,
    this.hasActiveFilters = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: posFieldDecoration(searchHint).copyWith(
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: searchController.text.trim().isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                key: ValueKey('profile-filter-${selectedProfile ?? 'all'}'),
                initialValue: selectedProfile,
                isExpanded: true,
                decoration: posFieldDecoration('POS Profile').copyWith(
                  prefixIcon: const Icon(Icons.storefront_outlined, size: 20),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Semua Profile'),
                  ),
                  for (final profile in profiles)
                    DropdownMenuItem<String?>(
                      value: profile,
                      child: Text(profile, overflow: TextOverflow.ellipsis),
                    ),
                  if (selectedProfile != null &&
                      selectedProfile!.isNotEmpty &&
                      !profiles.contains(selectedProfile))
                    DropdownMenuItem<String?>(
                      value: selectedProfile,
                      child: Text(
                        selectedProfile!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onProfileChanged,
              ),
            ),
            if (onReset != null && hasActiveFilters) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Reset filter',
                onPressed: onReset,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.softGreen,
                  foregroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.filter_alt_off_rounded),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        ErpStatusChipBar<String?>(
          chips: statusChips,
          selected: selectedStatus,
          onSelected: onStatusChanged,
        ),
      ],
    );
  }
}

List<ErpStatusChip<String?>> posOpeningStatusChips() => const [
  ErpStatusChip(label: 'Semua', value: null),
  ErpStatusChip(label: 'Draft', value: 'Draft'),
  ErpStatusChip(label: 'Open', value: 'Open'),
  ErpStatusChip(label: 'Closed', value: 'Closed'),
  ErpStatusChip(label: 'Cancelled', value: 'Cancelled'),
];

List<ErpStatusChip<String?>> posInvoiceStatusChips() => const [
  ErpStatusChip(label: 'Semua', value: null),
  ErpStatusChip(label: 'Draft', value: 'Draft'),
  ErpStatusChip(label: 'Paid', value: 'Paid'),
  ErpStatusChip(label: 'Unpaid', value: 'Unpaid'),
  ErpStatusChip(label: 'Return', value: 'Return'),
  ErpStatusChip(label: 'Cancelled', value: 'Cancelled'),
];

List<ErpStatusChip<String?>> posClosingStatusChips() => const [
  ErpStatusChip(label: 'Semua', value: null),
  ErpStatusChip(label: 'Draft', value: 'Draft'),
  ErpStatusChip(label: 'Submitted', value: 'Submitted'),
  ErpStatusChip(label: 'Queued', value: 'Queued'),
  ErpStatusChip(label: 'Failed', value: 'Failed'),
  ErpStatusChip(label: 'Cancelled', value: 'Cancelled'),
];
