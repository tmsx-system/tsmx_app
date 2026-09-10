import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/logistics/logistics_delivery_state.dart';
import '../../state/logistics/logistics_overview_state.dart';
import '../../state/logistics/logistics_tracking_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/responsive/responsive_layout.dart';
import '../shared/role_main_screen.dart';
import 'logistics_delivery_tab.dart';
import 'logistics_overview_tab.dart';
import 'logistics_tracking_tab.dart';

class LogisticsMainScreen extends StatefulWidget {
  final bool trackingOnly;
  final bool deliveryOnly;

  const LogisticsMainScreen({
    super.key,
    this.trackingOnly = false,
    this.deliveryOnly = false,
  });

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
    if (!permissions.canReadDeliveryNote || !_loadedTabs.add(key)) return;
    switch (key) {
      case 'home':
        await context.read<LogisticsOverviewState>().refreshDeliveryNotes();
        break;
      case 'tracking':
        await context.read<LogisticsTrackingState>().refreshDeliveryNotes();
        break;
      case 'delivery':
        await context.read<LogisticsDeliveryState>().refreshDeliveryNotes();
        break;
    }
  }

  List<_LogisticsMenuEntry> _buildMenuEntries(
    _LogisticsDoctypePermissions permissions,
  ) {
    if (!permissions.canReadDeliveryNote) return const [];

    final entries = <_LogisticsMenuEntry>[];
    if (!widget.trackingOnly && !widget.deliveryOnly) {
      entries.add(
        _LogisticsMenuEntry(
          key: 'home',
          destination: const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Beranda',
          ),
          builder: (onMenuSelected) =>
              LogisticsOverviewTab(onMenuSelected: onMenuSelected),
        ),
      );
    }
    if (!widget.deliveryOnly) {
      entries.add(
        const _LogisticsMenuEntry(
          key: 'tracking',
          destination: NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route_rounded),
            label: 'Armada',
          ),
          builder: _trackingTab,
        ),
      );
    }
    if (!widget.trackingOnly) {
      entries.add(
        const _LogisticsMenuEntry(
          key: 'delivery',
          destination: NavigationDestination(
            icon: Icon(Icons.assignment_turned_in_outlined),
            selectedIcon: Icon(Icons.assignment_turned_in_rounded),
            label: 'Delivery',
          ),
          builder: _deliveryTab,
        ),
      );
    }
    return entries;
  }

  Future<_LogisticsDoctypePermissions> _loadPermissions() async {
    final state = context.read<LogisticsOverviewState>();
    final access = state.appState.mobileAccess;
    if (access.isAdministrator ||
        access.isDeveloper ||
        access.isCompanyAdministrator ||
        access.isDirector) {
      return _LogisticsDoctypePermissions.fullAccess();
    }
    final results = await Future.wait([
      state.canReadDoctype('Delivery Note'),
      state.canWriteDoctype('Delivery Note'),
      state.canReadDoctype('File'),
      state.canCreateDoctype('File'),
    ]);
    final permissions = _LogisticsDoctypePermissions(
      canReadDeliveryNote: results[0],
      canWriteDeliveryNote: results[1],
      canReadFile: results[2],
      canCreateFile: results[3],
    );
    if (!permissions.hasAnyAccess && state.appState.canUseLogistics) {
      return _LogisticsDoctypePermissions.legacyModuleAccess();
    }
    return permissions;
  }
}

Widget _trackingTab(ValueChanged<int> _) => const LogisticsTrackingTab();
Widget _deliveryTab(ValueChanged<int> _) => const LogisticsDeliveryTab();

class _LogisticsDoctypePermissions {
  final bool canReadDeliveryNote;
  final bool canWriteDeliveryNote;
  final bool canReadFile;
  final bool canCreateFile;

  const _LogisticsDoctypePermissions({
    required this.canReadDeliveryNote,
    required this.canWriteDeliveryNote,
    required this.canReadFile,
    required this.canCreateFile,
  });

  factory _LogisticsDoctypePermissions.fullAccess() {
    return const _LogisticsDoctypePermissions(
      canReadDeliveryNote: true,
      canWriteDeliveryNote: true,
      canReadFile: true,
      canCreateFile: true,
    );
  }

  factory _LogisticsDoctypePermissions.legacyModuleAccess() {
    return _LogisticsDoctypePermissions.fullAccess();
  }

  bool get hasAnyAccess => canReadDeliveryNote;
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
