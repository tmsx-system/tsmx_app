import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import 'customer_price_list_tab.dart';
import 'inactive_customer_tab.dart';
import '../noo/noo_request_tab.dart';
import '../promo/promo_session_tab.dart';
import '../shared/sales_ui.dart';

class CustomerRequestTab extends StatelessWidget {
  const CustomerRequestTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: ColoredBox(
        color: AppColors.background,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 2),
              child: SalesPillTabBar(
                tabs: const [
                  Tab(text: 'Inactive'),
                  Tab(text: 'Price'),
                  Tab(text: 'NOO'),
                  Tab(text: 'Promo Session'),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  InactiveCustomerTab(),
                  CustomerPriceListTab(),
                  NooRequestTab(),
                  PromoSessionTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
