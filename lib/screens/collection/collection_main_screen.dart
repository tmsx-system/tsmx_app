import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth/auth_state.dart';
import '../../state/selling/selling_filter_state.dart';
import '../../theme/app_colors.dart';
import '../sales/collection/sales_collection_tab.dart';
import '../shared/role_main_screen.dart';

class CollectionMainScreen extends StatefulWidget {
  const CollectionMainScreen({super.key});

  @override
  State<CollectionMainScreen> createState() => _CollectionMainScreenState();
}

class _CollectionMainScreenState extends State<CollectionMainScreen> {
  Future<bool>? _accessFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _accessFuture ??= _loadAccess();
  }

  Future<bool> _loadAccess() async {
    final state = context.read<AuthState>();
    if (state.mobileAccess.isAdministrator ||
        state.mobileAccess.isDeveloper ||
        state.mobileAccess.isCompanyAdministrator ||
        state.mobileAccess.isDirector ||
        state.mobileAccess.isCollectionUser) {
      return true;
    }
    return state.canReadDoctype('Sales Invoice');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _accessFuture,
      builder: (context, snapshot) {
        final canAccess = snapshot.data;
        if (canAccess == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        if (!canAccess) return const _NoCollectionAccessScreen();
        return RoleMainScreen(
          title: 'Collection',
          fallbackUsername: 'Collection',
          onInitialize: (context) =>
              context.read<SellingFilterState>().loadSellingFilterOptions(),
          screensBuilder: (_) => const [SalesCollectionTab()],
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Koleksi',
            ),
          ],
        );
      },
    );
  }
}

class _NoCollectionAccessScreen extends StatelessWidget {
  const _NoCollectionAccessScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Text(
          'Tidak ada akses Collection',
          style: TextStyle(color: AppColors.slate, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
