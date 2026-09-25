import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/pos/pos_state.dart';
import '../../theme/app_colors.dart';
import '../shared/role_main_screen.dart';
import 'pos_closing_entry/create_pos_closing_entry_screen.dart';
import 'pos_closing_entry/pos_closing_entry_panel.dart';
import 'pos_invoice/create_pos_invoice_screen.dart';
import 'pos_invoice/pos_invoice_panel.dart';
import 'pos_opening_entry/create_pos_opening_entry_screen.dart';
import 'pos_opening_entry/pos_opening_entry_panel.dart';
import 'pos_overview_tab.dart';
import 'pos_profile/pos_profile_panel.dart';

class PosMainScreen extends StatefulWidget {
  const PosMainScreen({super.key});

  @override
  State<PosMainScreen> createState() => _PosMainScreenState();
}

class _PosMainScreenState extends State<PosMainScreen> {
  Future<_PosDoctypePermissions>? _permissionsFuture;
  final Set<String> _loadedKeys = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _permissionsFuture ??= _loadPermissions();
  }

  Future<_PosDoctypePermissions> _loadPermissions() async {
    final state = context.read<AppState>();
    final results = await Future.wait([
      state.canReadDoctype('POS Profile'),
      state.canReadDoctype('POS Opening Entry'),
      state.canCreateDoctype('POS Opening Entry'),
      state.canReadDoctype('POS Invoice'),
      state.canCreateDoctype('POS Invoice'),
      state.canReadDoctype('POS Closing Entry'),
      state.canCreateDoctype('POS Closing Entry'),
    ]);

    return _PosDoctypePermissions(
      canReadProfile: results[0],
      canReadOpening: results[1],
      canCreateOpening: results[2],
      canReadInvoice: results[3],
      canCreateInvoice: results[4],
      canReadClosing: results[5],
      canCreateClosing: results[6],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PosDoctypePermissions>(
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
        if (!permissions.hasAnyAccess) {
          return const _NoPosAccessScreen();
        }
        return _buildRoleScreen(permissions);
      },
    );
  }

  Widget _buildRoleScreen(_PosDoctypePermissions permissions) {
    final entries = _buildMenuEntries(permissions);
    final indexByKey = {
      for (var index = 0; index < entries.length; index++)
        entries[index].key: index,
    };

    return RoleMainScreen(
      title: 'POS',
      fallbackUsername: 'Kasir',
      onTabChanged: (context, index) =>
          _ensureEntryLoaded(context, entries[index].key),
      screensBuilder: (onMenuSelected) => entries
          .map((entry) {
            if (entry.key == 'home') {
              return PosOverviewTab(
                onMenuSelected: onMenuSelected,
                actions: _buildOverviewActions(onMenuSelected, indexByKey, entries),
              );
            }
            return entry.builder(onMenuSelected);
          })
          .toList(growable: false),
      floatingActionButtonBuilder: (context, currentIndex) =>
          _buildFab(context, currentIndex, entries),
      destinations: entries.map((entry) => entry.destination).toList(),
    );
  }

  Future<void> _ensureEntryLoaded(BuildContext context, String key) async {
    if (!_loadedKeys.add(key)) return;
    final state = context.read<PosState>();
    switch (key) {
      case 'home':
        await Future.wait([
          state.refreshProfiles(),
          state.refreshOpenings(),
          state.refreshInvoices(),
          state.refreshClosings(),
        ]);
      case 'profile':
        await state.refreshProfiles();
      case 'opening':
        await state.refreshOpenings();
      case 'invoice':
        await state.refreshInvoices();
      case 'closing':
        await state.refreshClosings();
    }
  }

  List<PosOverviewAction> _buildOverviewActions(
    ValueChanged<int> onMenuSelected,
    Map<String, int> indexByKey,
    List<_PosMenuEntry> entries,
  ) {
    final byKey = {for (final entry in entries) entry.key: entry};

    PosOverviewAction? actionFor(
      String key,
      String label,
      IconData icon,
      Color color,
    ) {
      final index = indexByKey[key];
      final entry = byKey[key];
      if (index == null || entry == null) return null;
      return PosOverviewAction(
        key: key,
        label: label,
        icon: icon,
        color: color,
        onTap: () => onMenuSelected(index),
      );
    }

    return [
      actionFor(
        'profile',
        'Profile',
        Icons.badge_rounded,
        const Color(0xFF0F766E),
      ),
      actionFor(
        'opening',
        'Opening',
        Icons.login_rounded,
        const Color(0xFF16A34A),
      ),
      actionFor(
        'invoice',
        'Invoice',
        Icons.receipt_long_rounded,
        const Color(0xFFF59E0B),
      ),
      actionFor(
        'closing',
        'Closing',
        Icons.logout_rounded,
        const Color(0xFF7C3AED),
      ),
    ].whereType<PosOverviewAction>().toList(growable: false);
  }

  List<_PosMenuEntry> _buildMenuEntries(_PosDoctypePermissions permissions) {
    final entries = <_PosMenuEntry>[
      _PosMenuEntry(
        key: 'home',
        destination: const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        builder: (onMenuSelected) => PosOverviewTab(onMenuSelected: onMenuSelected),
      ),
    ];

    if (permissions.canReadProfile) {
      entries.add(
        _PosMenuEntry(
          key: 'profile',
          destination: const NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge_rounded),
            label: 'Profile',
          ),
          builder: (_) => const PosProfilePanel(),
        ),
      );
    }
    if (permissions.canReadOpening) {
      entries.add(
        _PosMenuEntry(
          key: 'opening',
          destination: const NavigationDestination(
            icon: Icon(Icons.login_outlined),
            selectedIcon: Icon(Icons.login_rounded),
            label: 'Opening',
          ),
          builder: (_) => const PosOpeningEntryPanel(),
          canCreate: permissions.canCreateOpening,
        ),
      );
    }
    if (permissions.canReadInvoice) {
      entries.add(
        _PosMenuEntry(
          key: 'invoice',
          destination: const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Invoice',
          ),
          builder: (_) => const PosInvoicePanel(),
          canCreate: permissions.canCreateInvoice,
        ),
      );
    }
    if (permissions.canReadClosing) {
      entries.add(
        _PosMenuEntry(
          key: 'closing',
          destination: const NavigationDestination(
            icon: Icon(Icons.logout_outlined),
            selectedIcon: Icon(Icons.logout_rounded),
            label: 'Closing',
          ),
          builder: (_) => const PosClosingEntryPanel(),
          canCreate: permissions.canCreateClosing,
        ),
      );
    }

    return entries;
  }

  Widget? _buildFab(
    BuildContext context,
    int currentIndex,
    List<_PosMenuEntry> entries,
  ) {
    if (currentIndex < 0 || currentIndex >= entries.length) return null;
    final entry = entries[currentIndex];
    if (!entry.canCreate) return null;

    return FloatingActionButton.extended(
      heroTag: 'pos-create-${entry.key}',
      onPressed: () => _openCreate(context, entry.key),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add_rounded),
      label: Text(_fabLabel(entry.key)),
    );
  }

  String _fabLabel(String key) {
    return switch (key) {
      'opening' => 'Opening',
      'invoice' => 'Invoice',
      'closing' => 'Closing',
      _ => 'Buat',
    };
  }

  Future<void> _openCreate(BuildContext context, String key) async {
    final state = context.read<PosState>();
    final screen = switch (key) {
      'opening' => const CreatePosOpeningEntryScreen(),
      'invoice' => const CreatePosInvoiceScreen(),
      'closing' => const CreatePosClosingEntryScreen(),
      _ => null,
    };
    if (screen == null) return;

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => screen),
    );
    if (created != true || !context.mounted) return;

    switch (key) {
      case 'opening':
        await state.refreshOpenings();
      case 'invoice':
        await state.refreshInvoices();
      case 'closing':
        await state.refreshClosings();
    }
  }
}

class _PosMenuEntry {
  final String key;
  final NavigationDestination destination;
  final Widget Function(ValueChanged<int> onMenuSelected) builder;
  final bool canCreate;

  const _PosMenuEntry({
    required this.key,
    required this.destination,
    required this.builder,
    this.canCreate = false,
  });
}

class _PosDoctypePermissions {
  final bool canReadProfile;
  final bool canReadOpening;
  final bool canCreateOpening;
  final bool canReadInvoice;
  final bool canCreateInvoice;
  final bool canReadClosing;
  final bool canCreateClosing;

  const _PosDoctypePermissions({
    required this.canReadProfile,
    required this.canReadOpening,
    required this.canCreateOpening,
    required this.canReadInvoice,
    required this.canCreateInvoice,
    required this.canReadClosing,
    required this.canCreateClosing,
  });

  bool get hasAnyAccess =>
      canReadProfile || canReadOpening || canReadInvoice || canReadClosing;
}

class _NoPosAccessScreen extends StatelessWidget {
  const _NoPosAccessScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('POS'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
        elevation: 0,
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'User ini belum punya permission doctype POS Profile / Opening / Invoice / Closing.',
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
}
