import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/auth/auth_state.dart';
import '../../../theme/app_colors.dart';
import 'customer_price_list_tab.dart';
import 'inactive_customer_tab.dart';
import '../noo/noo_request_tab.dart';
import '../promo/promo_session_tab.dart';
import '../shared/sales_ui.dart';

class CustomerRequestTab extends StatefulWidget {
  const CustomerRequestTab({super.key});

  @override
  State<CustomerRequestTab> createState() => _CustomerRequestTabState();
}

class _CustomerRequestTabState extends State<CustomerRequestTab> {
  late final Future<_CustomerSectionAccess> _accessFuture = _loadAccess();

  Future<_CustomerSectionAccess> _loadAccess() async {
    final auth = context.read<AuthState>();
    final results = await Future.wait([
      auth.canReadReport('Inactive Customers'),
      auth.canReadDoctype('Item Price'),
      auth.canReadDoctype('NOO Request'),
      auth.canReadDoctype('Promo Request'),
    ]);
    return _CustomerSectionAccess(
      inactive: results[0],
      price: results[1],
      noo: results[2],
      promo: results[3],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CustomerSectionAccess>(
      future: _accessFuture,
      builder: (context, snapshot) {
        final access = snapshot.data;
        if (access == null) {
          return const ColoredBox(
            color: AppColors.background,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        final sections = access.sections;
        if (sections.isEmpty) {
          return const ColoredBox(
            color: AppColors.background,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Tidak ada akses Inactive, Price, NOO, atau Promo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }
        return DefaultTabController(
          length: sections.length,
          child: ColoredBox(
            color: AppColors.background,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 2),
                  child: SalesPillTabBar(
                    tabs: [for (final section in sections) Tab(text: section.label)],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [for (final section in sections) section.child],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CustomerSectionAccess {
  final bool inactive;
  final bool price;
  final bool noo;
  final bool promo;

  const _CustomerSectionAccess({
    required this.inactive,
    required this.price,
    required this.noo,
    required this.promo,
  });

  List<_CustomerSection> get sections => [
    if (inactive)
      const _CustomerSection('Inactive', InactiveCustomerTab()),
    if (price) const _CustomerSection('Price', CustomerPriceListTab()),
    if (noo) const _CustomerSection('NOO', NooRequestTab()),
    if (promo) const _CustomerSection('Promo Session', PromoSessionTab()),
  ];
}

class _CustomerSection {
  final String label;
  final Widget child;

  const _CustomerSection(this.label, this.child);
}
