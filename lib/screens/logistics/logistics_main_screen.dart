import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/logistics/logistics_delivery_state.dart';
import '../../state/logistics/logistics_overview_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/responsive/responsive_layout.dart';
import '../shared/role_main_screen.dart';
import 'logistics_operations_tab.dart';
import 'logistics_overview_tab.dart';

class LogisticsMainScreen extends StatefulWidget {
  const LogisticsMainScreen({super.key});

  @override
  State<LogisticsMainScreen> createState() => _LogisticsMainScreenState();
}

class _LogisticsMainScreenState extends State<LogisticsMainScreen> {
  Future<_LogisticsDoctypePermissions>? _permissionsFuture;
  final Set<String> _loadedTabs = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _permissionsFuture ??= _loadPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LogisticsDoctypePermissions>(
      future: _permissionsFuture,
      builder: (context, snapshot) {
        final permissions = snapshot.data;
        if (permissions == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        return _buildRoleScreen(permissions);
      },
    );
  }

  Widget _buildRoleScreen(_LogisticsDoctypePermissions permissions) {
    final entries = _buildMenuEntries(permissions);
    if (entries.isEmpty) return const _NoLogisticsAccessScreen();

    return RoleMainScreen(
      title: 'Logistics',
      fallbackUsername: 'Logistics',
      onTabChanged: (context, index) =>
          _ensureLogisticsTabLoaded(context, entries[index].key, permissions),
      screensBuilder: (onMenuSelected) => entries
          .map((entry) => entry.builder(onMenuSelected))
          .toList(growable: false),
      destinations: entries.map((entry) => entry.destination).toList(),
    );
  }

  Future<void> _ensureLogisticsTabLoaded(
    BuildContext context,
    String key,
    _LogisticsDoctypePermissions permissions,
  ) async {
    if (!_loadedTabs.add(key)) return;
    if (key == 'home' && permissions.canReadDeliveryNote) {
      if (!context.mounted) return;
      await context.read<LogisticsOverviewState>().refreshDeliveryNotes();
    }
    if (key == 'ops' && permissions.canReadDeliveryNote) {
      if (!context.mounted) return;
      await context.read<LogisticsDeliveryState>().refreshDeliveryNotes();
    }
  }

  List<_LogisticsMenuEntry> _buildMenuEntries(
    _LogisticsDoctypePermissions permissions,
  ) {
    final entries = <_LogisticsMenuEntry>[];
    if (permissions.canReadDeliveryNote) {
      entries.add(
        _LogisticsMenuEntry(
          key: 'home',
          destination: const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Beranda',
          ),
          builder: (_) => const LogisticsOverviewTab(),
        ),
      );
    }
    if (permissions.canUseOps) {
      entries.add(
        const _LogisticsMenuEntry(
          key: 'ops',
          destination: NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping_rounded),
            label: 'Transaksi',
          ),
          builder: _operationsTab,
        ),
      );
    }
    return entries;
  }

  Future<_LogisticsDoctypePermissions> _loadPermissions() async {
    final state = context.read<LogisticsOverviewState>();
    final results = await Future.wait([
      state.canReadDoctype('Delivery Note'),
      state.canReadDoctype('Delivery Trip'),
      state.canReadDoctype('Driver'),
      state.canReadDoctype('Vehicle'),
    ]);
    return _LogisticsDoctypePermissions(
      canReadDeliveryNote: results[0],
      canReadDeliveryTrip: results[1],
      canReadDriver: results[2],
      canReadVehicle: results[3],
    );
  }
}

Widget _operationsTab(ValueChanged<int> _) => const LogisticsOperationsTab();

class _LogisticsDoctypePermissions {
  final bool canReadDeliveryNote;
  final bool canReadDeliveryTrip;
  final bool canReadDriver;
  final bool canReadVehicle;

  const _LogisticsDoctypePermissions({
    required this.canReadDeliveryNote,
    required this.canReadDeliveryTrip,
    required this.canReadDriver,
    required this.canReadVehicle,
  });

  bool get canUseOps =>
      canReadDeliveryNote ||
      canReadDeliveryTrip ||
      canReadDriver ||
      canReadVehicle;
}

class _LogisticsMenuEntry {
  final String key;
  final NavigationDestination destination;
  final Widget Function(ValueChanged<int> onMenuSelected) builder;

  const _LogisticsMenuEntry({
    required this.key,
    required this.destination,
    required this.builder,
  });
}

class _NoLogisticsAccessScreen extends StatelessWidget {
  const _NoLogisticsAccessScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    body: Center(
      child: TmsxResponsiveBody(
        maxWidth: 520,
        child: Padding(
          padding: EdgeInsets.all(TmsxResponsive.horizontalPadding(context)),
          child: const Text(
            'Tidak ada akses Logistics yang tersedia untuk user ini.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.slate,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
}
