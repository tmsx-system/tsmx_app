import 'package:flutter/material.dart';

class MobileModule {
  MobileModule._();

  static const dashboard = 'dashboard';
  static const sales = 'sales';
  static const spg = 'spg';
  static const collection = 'collection';
  static const purchase = 'purchase';
  static const pos = 'pos';
  static const stock = 'stock';
  static const warehouse = 'warehouse';
  static const qualityControl = 'quality_control';
  static const logistics = 'logistics';
  static const approvals = 'approvals';
  static const finance = 'finance';
  static const accounting = 'accounting';
  static const plantation = 'plantation';

  static const all = [
    dashboard,
    sales,
    spg,
    collection,
    purchase,
    pos,
    stock,
    warehouse,
    qualityControl,
    logistics,
    approvals,
    finance,
    accounting,
    plantation,
  ];

  static const implemented = [
    dashboard,
    sales,
    spg,
    collection,
    purchase,
    pos,
    stock,
    warehouse,
    qualityControl,
    logistics,
    approvals,
    finance,
    accounting,
  ];

  static const planned = [plantation];
}

class MobileRole {
  MobileRole._();

  static const administrator = 'Administrator';
  static const companyAdministrator = 'Company Administrator';
  static const developer = 'Developer';
  static const sales = 'Sales';
  static const salesManager = 'Sales Manager';
  static const spg = 'SPG';
  static const collection = 'Collection';
  static const warehouse = 'Warehouse';
  static const qualityControl = 'Quality Control';
  static const purchase = 'Purchase';
  static const purchaseManager = 'Purchase Manager';
  static const logistics = 'Logistics';
  static const driver = 'Driver';
  static const finance = 'Finance';
  static const accounting = 'Accounting';
  static const plantationSupervisor = 'Plantation Supervisor';
  static const director = 'Director';
  static const unassigned = 'Unassigned';

  static const fullAccessRoles = {administrator};

  /// Temporary: Finance/Accounting app modules are admin/developer only.
  static const financeAccountingRoles = {administrator, developer};
}

class MobileModuleMeta {
  final String key;
  final String groupKey;
  final String defaultLabel;
  final String defaultSubtitle;
  final IconData icon;
  final int menuOrder;
  final bool isPlanned;

  const MobileModuleMeta({
    required this.key,
    required this.groupKey,
    required this.defaultLabel,
    required this.defaultSubtitle,
    required this.icon,
    required this.menuOrder,
    this.isPlanned = false,
  });
}

class MobileModuleGroupMeta {
  final String key;
  final String title;
  final int order;

  const MobileModuleGroupMeta({
    required this.key,
    required this.title,
    required this.order,
  });
}

class MobileModuleAccessRule {
  final String module;
  final List<String> readDoctypes;

  const MobileModuleAccessRule({
    required this.module,
    required this.readDoctypes,
  });
}

class MobileRoleRegistry {
  MobileRoleRegistry._();

  static const defaultAppName = 'TMSX Hub';
  static const defaultAppTagline = 'Mobile ERP';

  static const moduleGroups = [
    MobileModuleGroupMeta(key: 'sales', title: 'Penjualan', order: 10),
    MobileModuleGroupMeta(key: 'purchase', title: 'Pembelian', order: 20),
    MobileModuleGroupMeta(key: 'warehouse', title: 'Gudang & Stok', order: 30),
    MobileModuleGroupMeta(key: 'logistics', title: 'Logistik', order: 40),
    MobileModuleGroupMeta(key: 'finance', title: 'Keuangan', order: 50),
    MobileModuleGroupMeta(key: 'plantation', title: 'Plantation', order: 60),
  ];

  static const moduleCatalog = {
    MobileModule.dashboard: MobileModuleMeta(
      key: MobileModule.dashboard,
      groupKey: 'sales',
      defaultLabel: 'Beranda',
      defaultSubtitle: 'Ringkasan operasional',
      icon: Icons.dashboard_rounded,
      menuOrder: 1,
    ),
    MobileModule.sales: MobileModuleMeta(
      key: MobileModule.sales,
      groupKey: 'sales',
      defaultLabel: 'Penjualan',
      defaultSubtitle: 'Order, customer, stock, visit',
      icon: Icons.point_of_sale_rounded,
      menuOrder: 2,
    ),
    MobileModule.collection: MobileModuleMeta(
      key: MobileModule.collection,
      groupKey: 'sales',
      defaultLabel: 'Collection',
      defaultSubtitle: 'AR aging, invoice, dan janji bayar',
      icon: Icons.account_balance_wallet_rounded,
      menuOrder: 5,
    ),
    MobileModule.spg: MobileModuleMeta(
      key: MobileModule.spg,
      groupKey: 'sales',
      defaultLabel: 'SPG',
      defaultSubtitle: 'Visit, report foto, dan selling',
      icon: Icons.storefront_rounded,
      menuOrder: 4,
    ),
    MobileModule.purchase: MobileModuleMeta(
      key: MobileModule.purchase,
      groupKey: 'purchase',
      defaultLabel: 'Pembelian',
      defaultSubtitle: 'PO, receipt, invoice, material request',
      icon: Icons.shopping_bag_rounded,
      menuOrder: 3,
    ),
    MobileModule.pos: MobileModuleMeta(
      key: MobileModule.pos,
      groupKey: 'sales',
      defaultLabel: 'POS',
      defaultSubtitle: 'Dashboard, profile, opening, invoice, closing',
      icon: Icons.receipt_long_rounded,
      menuOrder: 3,
    ),
    MobileModule.stock: MobileModuleMeta(
      key: MobileModule.stock,
      groupKey: 'warehouse',
      defaultLabel: 'Stok',
      defaultSubtitle: 'Cek stok, alert, dan detail item',
      icon: Icons.inventory_2_rounded,
      menuOrder: 7,
    ),
    MobileModule.warehouse: MobileModuleMeta(
      key: MobileModule.warehouse,
      groupKey: 'warehouse',
      defaultLabel: 'Gudang',
      defaultSubtitle: 'Operasi, transfer, QC gudang',
      icon: Icons.warehouse_rounded,
      menuOrder: 6,
    ),
    MobileModule.qualityControl: MobileModuleMeta(
      key: MobileModule.qualityControl,
      groupKey: 'warehouse',
      defaultLabel: 'Quality Control',
      defaultSubtitle: 'Incoming, production, reject, approval QC',
      icon: Icons.fact_check_rounded,
      menuOrder: 46,
    ),
    MobileModule.logistics: MobileModuleMeta(
      key: MobileModule.logistics,
      groupKey: 'logistics',
      defaultLabel: 'Logistik',
      defaultSubtitle: 'Delivery, trip, armada',
      icon: Icons.local_shipping_rounded,
      menuOrder: 50,
    ),
    MobileModule.approvals: MobileModuleMeta(
      key: MobileModule.approvals,
      groupKey: 'purchase',
      defaultLabel: 'Todo',
      defaultSubtitle: 'Approval dokumen',
      icon: Icons.checklist_rounded,
      menuOrder: 55,
    ),
    MobileModule.finance: MobileModuleMeta(
      key: MobileModule.finance,
      groupKey: 'finance',
      defaultLabel: 'Finance',
      defaultSubtitle: 'Cash flow, bank, AR/AP monitoring',
      icon: Icons.payments_rounded,
      menuOrder: 60,
    ),
    MobileModule.accounting: MobileModuleMeta(
      key: MobileModule.accounting,
      groupKey: 'finance',
      defaultLabel: 'Accounting',
      defaultSubtitle: 'GL, journal, laporan keuangan',
      icon: Icons.calculate_rounded,
      menuOrder: 65,
    ),
    MobileModule.plantation: MobileModuleMeta(
      key: MobileModule.plantation,
      groupKey: 'plantation',
      defaultLabel: 'Plantation',
      defaultSubtitle: 'Farm, harvest, ripening, distribusi',
      icon: Icons.agriculture_rounded,
      menuOrder: 70,
      isPlanned: true,
    ),
  };

  static const permissionModuleRules = [
    MobileModuleAccessRule(
      module: MobileModule.sales,
      readDoctypes: [
        'Sales Order',
        'Delivery Note',
        'Sales Invoice',
        'Customer',
        'Sales Visit',
      ],
    ),
    MobileModuleAccessRule(
      module: MobileModule.collection,
      readDoctypes: ['Sales Invoice', 'Payment Entry'],
    ),
    MobileModuleAccessRule(
      module: MobileModule.spg,
      readDoctypes: ['SPG Visit', 'SPG Daily Activity', 'SPG Daily Report'],
    ),
    MobileModuleAccessRule(
      module: MobileModule.purchase,
      readDoctypes: [
        'Material Request',
        'Purchase Order',
        'Purchase Receipt',
        'Purchase Invoice',
      ],
    ),
    MobileModuleAccessRule(
      module: MobileModule.pos,
      readDoctypes: [
        'POS Profile',
        'POS Opening Entry',
        'POS Invoice',
        'POS Closing Entry',
      ],
    ),
    MobileModuleAccessRule(
      module: MobileModule.stock,
      readDoctypes: ['Bin', 'Item', 'Stock Ledger Entry'],
    ),
    MobileModuleAccessRule(
      module: MobileModule.warehouse,
      readDoctypes: ['Warehouse', 'Stock Entry', 'Stock Reconciliation'],
    ),
    MobileModuleAccessRule(
      module: MobileModule.qualityControl,
      readDoctypes: ['Quality Inspection'],
    ),
    MobileModuleAccessRule(
      module: MobileModule.logistics,
      readDoctypes: ['Delivery Note', 'Delivery Trip', 'Driver', 'Vehicle'],
    ),
    MobileModuleAccessRule(
      module: MobileModule.approvals,
      readDoctypes: ['ToDo'],
    ),
  ];

  static const _frappeRoleAliases = <String, String>{
    'developer': MobileRole.developer,
    'system manager': MobileRole.administrator,
    'administrator': MobileRole.administrator,
    'company administrator': MobileRole.companyAdministrator,
    'director': MobileRole.director,
    'owner': MobileRole.director,
    'executive': MobileRole.director,
    'sales admin': MobileRole.salesManager,
    'sales manager': MobileRole.salesManager,
    'sales user': MobileRole.sales,
    'selling user': MobileRole.sales,
    'sales': MobileRole.sales,
    'spg': MobileRole.spg,
    'sales promotion': MobileRole.spg,
    'sales promotion girl': MobileRole.spg,
    'collection admin': MobileRole.collection,
    'collection user': MobileRole.collection,
    'collection manager': MobileRole.collection,
    'collection': MobileRole.collection,
    'accounts receivable': MobileRole.collection,
    'purchase admin': MobileRole.purchaseManager,
    'purchase manager': MobileRole.purchaseManager,
    'buying manager': MobileRole.purchaseManager,
    'purchase user': MobileRole.purchase,
    'buying user': MobileRole.purchase,
    'purchase': MobileRole.purchase,
    'quality control admin': MobileRole.qualityControl,
    'quality control manager': MobileRole.qualityControl,
    'quality control user': MobileRole.qualityControl,
    'quality control': MobileRole.qualityControl,
    'quality manager': MobileRole.qualityControl,
    'qc manager': MobileRole.qualityControl,
    'qc user': MobileRole.qualityControl,
    'warehouse admin': MobileRole.warehouse,
    'warehouse manager': MobileRole.warehouse,
    'warehouse user': MobileRole.warehouse,
    'stock manager': MobileRole.warehouse,
    'stock user': MobileRole.warehouse,
    'warehouse': MobileRole.warehouse,
    'logistics admin': MobileRole.logistics,
    'logistics manager': MobileRole.logistics,
    'logistics user': MobileRole.logistics,
    'delivery manager': MobileRole.logistics,
    'logistics': MobileRole.logistics,
    'delivery user': MobileRole.driver,
    'driver': MobileRole.driver,
    'finance admin': MobileRole.finance,
    'finance manager': MobileRole.finance,
    'finance user': MobileRole.finance,
    'finance': MobileRole.finance,
    'accounting admin': MobileRole.accounting,
    'accounting manager': MobileRole.accounting,
    'accounting user': MobileRole.accounting,
    'accounts manager': MobileRole.accounting,
    'accountant': MobileRole.accounting,
    'accounting': MobileRole.accounting,
    'plantation admin': MobileRole.plantationSupervisor,
    'plantation supervisor': MobileRole.plantationSupervisor,
    'plantation manager': MobileRole.plantationSupervisor,
    'plantation': MobileRole.plantationSupervisor,
  };

  static const _priorityRoleOrder = [
    MobileRole.administrator,
    MobileRole.developer,
    MobileRole.companyAdministrator,
    MobileRole.director,
    MobileRole.finance,
    MobileRole.accounting,
    MobileRole.plantationSupervisor,
    MobileRole.purchaseManager,
    MobileRole.salesManager,
    MobileRole.spg,
    MobileRole.qualityControl,
    MobileRole.logistics,
    MobileRole.collection,
    MobileRole.purchase,
    MobileRole.sales,
    MobileRole.warehouse,
    MobileRole.driver,
  ];

  static const knownRoles = [
    MobileRole.administrator,
    MobileRole.companyAdministrator,
    MobileRole.developer,
    MobileRole.sales,
    MobileRole.salesManager,
    MobileRole.spg,
    MobileRole.collection,
    MobileRole.warehouse,
    MobileRole.qualityControl,
    MobileRole.purchase,
    MobileRole.purchaseManager,
    MobileRole.logistics,
    MobileRole.driver,
    MobileRole.finance,
    MobileRole.accounting,
    MobileRole.plantationSupervisor,
    MobileRole.director,
    MobileRole.unassigned,
  ];

  static String normalizeRoleProfile(String roleProfile) {
    final normalized = roleProfile.trim();
    if (normalized.isEmpty) return MobileRole.unassigned;

    final lower = normalized.toLowerCase();
    if (lower == 'null' || lower == 'none' || lower == 'undefined') {
      return MobileRole.unassigned;
    }

    final aliasMatch = _frappeRoleAliases[lower];
    if (aliasMatch != null) return aliasMatch;

    for (final role in knownRoles) {
      if (role.toLowerCase() == lower) return role;
    }

    return normalized;
  }

  static String fromFrappeRoles(Iterable<String> roles) {
    final normalizedRoles = <String>{};
    for (final role in roles) {
      final alias = _frappeRoleAliases[role.trim().toLowerCase()];
      if (alias != null) normalizedRoles.add(alias);
    }

    for (final role in _priorityRoleOrder) {
      if (normalizedRoles.contains(role)) return role;
    }

    return MobileRole.unassigned;
  }

  static Set<String> gateDoctypes() {
    final doctypes = <String>{};
    for (final rule in permissionModuleRules) {
      for (final doctype in rule.readDoctypes) {
        final trimmed = doctype.trim();
        if (trimmed.isNotEmpty) doctypes.add(trimmed);
      }
    }
    return doctypes;
  }

  static Set<String> modulesForReadableDoctypes(Iterable<String> readable) {
    final readableSet = {
      for (final doctype in readable)
        if (doctype.trim().isNotEmpty) doctype.trim(),
    };
    final enabled = <String>{MobileModule.dashboard};
    for (final rule in permissionModuleRules) {
      final granted = rule.readDoctypes.any(readableSet.contains);
      if (granted) enabled.add(rule.module);
    }
    // Stock and QC stay inside Warehouse; dashboard only shows Gudang.
    if (enabled.contains(MobileModule.stock) ||
        enabled.contains(MobileModule.qualityControl)) {
      enabled.add(MobileModule.warehouse);
    }
    return enabled;
  }

  static Set<String> fullAccessModules() {
    return {
      MobileModule.dashboard,
      ...MobileModule.implemented,
      ...MobileModule.planned,
    };
  }

  static bool isFullAccessRole(String role) {
    return MobileRole.fullAccessRoles.contains(normalizeRoleProfile(role));
  }

  static bool canUseFinanceAccounting(String role) {
    return MobileRole.financeAccountingRoles.contains(
      normalizeRoleProfile(role),
    );
  }

  static MobileModuleMeta? metaFor(String module) {
    return moduleCatalog[module.trim().toLowerCase()];
  }

  static String moduleLabel(
    String module, {
    Iterable<({String module, String label})> bootMenus = const [],
    String? fallback,
  }) {
    final key = module.trim().toLowerCase();
    for (final menu in bootMenus) {
      if (menu.module == key && menu.label.trim().isNotEmpty) {
        return menu.label;
      }
    }
    return fallback ?? metaFor(key)?.defaultLabel ?? module;
  }

  static List<MobileModuleGroupMeta> sortedGroups() {
    final groups = List<MobileModuleGroupMeta>.from(moduleGroups)
      ..sort((a, b) => a.order.compareTo(b.order));
    return groups;
  }
}
