import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/logistics/logistics_overview_state.dart';
import '../../theme/app_colors.dart';
import 'logistics_delivery_tab.dart';
import 'logistics_doctype_list_panel.dart';
import 'logistics_widgets.dart';

class LogisticsOperationsTab extends StatefulWidget {
  const LogisticsOperationsTab({super.key});

  @override
  State<LogisticsOperationsTab> createState() => _LogisticsOperationsTabState();
}

class _LogisticsOperationsTabState extends State<LogisticsOperationsTab> {
  bool _loading = true;
  bool _deliveryNote = false;
  bool _deliveryTrip = false;
  bool _driver = false;
  bool _vehicle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPermissions());
  }

  Future<void> _loadPermissions() async {
    final state = context.read<LogisticsOverviewState>();
    final results = await Future.wait([
      state.canReadDoctype('Delivery Note'),
      state.canCreateDoctype('Delivery Note'),
      state.canReadDoctype('Delivery Trip'),
      state.canCreateDoctype('Delivery Trip'),
      state.canReadDoctype('Driver'),
      state.canCreateDoctype('Driver'),
      state.canReadDoctype('Vehicle'),
      state.canCreateDoctype('Vehicle'),
    ]);
    if (!mounted) return;
    setState(() {
      _deliveryNote = results[0] || results[1];
      _deliveryTrip = results[2] || results[3];
      _driver = results[4] || results[5];
      _vehicle = results[6] || results[7];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final actions = <_LogisticsDoctypeAction>[
      if (_deliveryNote)
        _LogisticsDoctypeAction(
          icon: Icons.assignment_turned_in_outlined,
          title: 'Delivery Note',
          subtitle: 'Pengiriman customer ERPNext',
          color: logisticsGreen,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DeliveryNoteListScreen()),
          ),
        ),
      if (_deliveryTrip)
        _LogisticsDoctypeAction(
          icon: Icons.route_outlined,
          title: 'Delivery Trip',
          subtitle: 'Trip armada ERPNext',
          color: logisticsOrange,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LogisticsDoctypeListPanel(
                doctype: 'Delivery Trip',
                title: 'Delivery Trip',
                icon: Icons.route_outlined,
                fields: const [
                  'name',
                  'driver',
                  'driver_name',
                  'vehicle',
                  'departure_time',
                  'status',
                  'company',
                  'docstatus',
                ],
                titleOf: (row) => row['name']?.toString() ?? '',
                subtitleOf: (row) => [
                  if ((row['driver_name'] ?? row['driver'] ?? '')
                      .toString()
                      .trim()
                      .isNotEmpty)
                    (row['driver_name'] ?? row['driver']).toString(),
                  if ((row['vehicle'] ?? '').toString().trim().isNotEmpty)
                    row['vehicle'].toString(),
                  if ((row['departure_time'] ?? '').toString().trim().isNotEmpty)
                    row['departure_time'].toString(),
                ].join(' · '),
              ),
            ),
          ),
        ),
      if (_driver)
        _LogisticsDoctypeAction(
          icon: Icons.badge_outlined,
          title: 'Driver',
          subtitle: 'Master driver ERPNext',
          color: logisticsBlue,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LogisticsDoctypeListPanel(
                doctype: 'Driver',
                title: 'Driver',
                icon: Icons.badge_outlined,
                fields: const [
                  'name',
                  'full_name',
                  'status',
                  'cell_number',
                  'employee',
                  'license_number',
                ],
                titleOf: (row) =>
                    (row['full_name'] ?? row['name'])?.toString() ?? '',
                subtitleOf: (row) => [
                  if ((row['name'] ?? '').toString().trim().isNotEmpty)
                    row['name'].toString(),
                  if ((row['cell_number'] ?? '').toString().trim().isNotEmpty)
                    row['cell_number'].toString(),
                  if ((row['employee'] ?? '').toString().trim().isNotEmpty)
                    row['employee'].toString(),
                ].join(' · '),
              ),
            ),
          ),
        ),
      if (_vehicle)
        _LogisticsDoctypeAction(
          icon: Icons.local_shipping_outlined,
          title: 'Vehicle',
          subtitle: 'Master kendaraan ERPNext',
          color: logisticsCyan,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LogisticsDoctypeListPanel(
                doctype: 'Vehicle',
                title: 'Vehicle',
                icon: Icons.local_shipping_outlined,
                fields: const [
                  'name',
                  'license_plate',
                  'make',
                  'model',
                  'vehicle_type',
                  'last_odometer',
                  'company',
                  'disabled',
                ],
                titleOf: (row) =>
                    (row['license_plate'] ?? row['name'])?.toString() ?? '',
                subtitleOf: (row) => [
                  if ((row['make'] ?? '').toString().trim().isNotEmpty)
                    row['make'].toString(),
                  if ((row['model'] ?? '').toString().trim().isNotEmpty)
                    row['model'].toString(),
                  if ((row['vehicle_type'] ?? '').toString().trim().isNotEmpty)
                    row['vehicle_type'].toString(),
                  if ((row['company'] ?? '').toString().trim().isNotEmpty)
                    row['company'].toString(),
                ].join(' · '),
              ),
            ),
          ),
        ),
    ];

    return ListView(
      padding: logisticsPagePaddingOf(context),
      children: [
        const LogisticsSectionHeader(
          title: 'Transaksi Logistik',
          subtitle: 'Doctype ERPNext sesuai role permission',
          icon: Icons.local_shipping_outlined,
        ),
        logisticsSectionGap,
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (actions.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Tidak ada doctype logistik yang bisa diakses.',
              style: TextStyle(
                color: AppColors.slate,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          ...actions.map(
            (action) => LogisticsActionCard(
              onTap: action.onTap,
              icon: action.icon,
              title: action.title,
              subtitle: action.subtitle,
              color: action.color,
              status: 'ERPNext',
            ),
          ),
      ],
    );
  }
}

class DeliveryNoteListScreen extends StatelessWidget {
  const DeliveryNoteListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Delivery Note',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: const LogisticsDeliveryTab(),
    );
  }
}

class _LogisticsDoctypeAction {
  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _LogisticsDoctypeAction({
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}
