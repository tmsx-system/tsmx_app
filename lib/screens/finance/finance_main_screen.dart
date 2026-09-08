import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/erp_summary.dart';
import '../../models/finance_accounting.dart';
import '../../state/finance/finance_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/erp_format.dart';
import '../../widgets/erp/erp_empty_state.dart';
import '../../widgets/erp/erp_error_box.dart';
import '../../widgets/erp/erp_detail_sheet.dart';
import '../../widgets/erp/erp_filter_tools.dart';
import '../../widgets/responsive/responsive_layout.dart';
import '../shared/role_main_screen.dart';

part 'shared/finance_widgets.dart';
part 'workspace/finance_workspace_tab.dart';
part 'dashboard/finance_dashboard_tab.dart';
part 'bank/finance_bank_tab.dart';
part 'ar_ap/finance_ar_ap_tab.dart';
part 'ledger/finance_ledger_tab.dart';

const _financeGreen = Color(0xFF0F7A43);
const _financeBlue = Color(0xFF2563EB);
const _financeCyan = Color(0xFF0891B2);
const _financeOrange = Color(0xFFF97316);
const _financePurple = Color(0xFF7C3AED);
const _financeMint = Color(0xFFDCFCE7);

class FinanceMainScreen extends StatefulWidget {
  final int initialTabIndex;
  final bool accountingOnly;

  const FinanceMainScreen({
    super.key,
    this.initialTabIndex = 0,
    this.accountingOnly = false,
  });

  @override
  State<FinanceMainScreen> createState() => _FinanceMainScreenState();
}

class _FinanceMainScreenState extends State<FinanceMainScreen> {
  late Future<_FinanceAccess> _accessFuture;

  @override
  void initState() {
    super.initState();
    _accessFuture = _loadAccess();
  }

  Future<_FinanceAccess> _loadAccess() async {
    final state = context.read<FinanceState>();
    await state.ensureLoggedIn();

    final results = await Future.wait<bool>([
      state.canReadDoctype('Payment Entry'),
      state.canCreateDoctype('Payment Entry'),
      state.canReadDoctype('Sales Invoice'),
      state.canReadDoctype('Purchase Invoice'),
      state.canReadDoctype('Account'),
      state.canReadDoctype('GL Entry'),
      state.canReadDoctype('Journal Entry'),
      state.canCreateDoctype('Journal Entry'),
    ]);

    var access = _FinanceAccess(
      canReadPaymentEntry: results[0],
      canCreatePaymentEntry: results[1],
      canReadSalesInvoice: results[2],
      canReadPurchaseInvoice: results[3],
      canReadAccount: results[4],
      canReadGlEntry: results[5],
      canReadJournalEntry: results[6],
      canCreateJournalEntry: results[7],
    );

    if (!access.hasAnyFinanceAccess) {
      final legacyFinance = state.canUseFinance;
      final legacyAccounting = state.canUseAccounting;
      access = _FinanceAccess(
        canReadPaymentEntry: legacyFinance,
        canCreatePaymentEntry: legacyFinance,
        canReadSalesInvoice: legacyFinance,
        canReadPurchaseInvoice: legacyFinance,
        canReadAccount: legacyFinance || legacyAccounting,
        canReadGlEntry: legacyFinance || legacyAccounting,
        canReadJournalEntry: legacyAccounting,
        canCreateJournalEntry: legacyAccounting,
      );
    }

    return access;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FinanceAccess>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final access = snapshot.data ?? const _FinanceAccess();
        final entries = access.entries(accountingOnly: widget.accountingOnly);
        if (entries.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: TmsxResponsiveBody(
                maxWidth: 520,
                child: Padding(
                  padding: EdgeInsets.all(
                    TmsxResponsive.horizontalPadding(context),
                  ),
                  child: const Text(
                    'Tidak ada akses Keuangan yang tersedia untuk user ini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.slate),
                  ),
                ),
              ),
            ),
          );
        }

        final preferredView = widget.accountingOnly
            ? _FinanceView.accounting
            : _FinanceView.values[widget.initialTabIndex.clamp(
                0,
                _FinanceView.values.length - 1,
              )];
        final initialIndex = entries.indexWhere(
          (entry) => entry.view == preferredView,
        );
        final isAccounting =
            widget.accountingOnly || preferredView == _FinanceView.accounting;

        return RoleMainScreen(
          title: isAccounting ? 'Accounting' : 'Finance',
          fallbackUsername: isAccounting ? 'Accounting' : 'Finance',
          initialTabIndex: initialIndex < 0 ? 0 : initialIndex,
          onInitialize: (context) async =>
              context.read<FinanceState>().ensureLoggedIn(),
          screensBuilder: (_) => [
            for (final entry in entries)
              _FinanceWorkspaceTab(initialView: entry.view, access: access),
          ],
          destinations: [for (final entry in entries) entry.destination],
        );
      },
    );
  }
}

enum _FinanceView { dashboard, cashBank, receivablePayable, accounting }

class _FinanceTabEntry {
  final _FinanceView view;
  final NavigationDestination destination;

  const _FinanceTabEntry({required this.view, required this.destination});
}

class _FinanceAccess {
  final bool canReadPaymentEntry;
  final bool canCreatePaymentEntry;
  final bool canReadSalesInvoice;
  final bool canReadPurchaseInvoice;
  final bool canReadAccount;
  final bool canReadGlEntry;
  final bool canReadJournalEntry;
  final bool canCreateJournalEntry;

  const _FinanceAccess({
    this.canReadPaymentEntry = false,
    this.canCreatePaymentEntry = false,
    this.canReadSalesInvoice = false,
    this.canReadPurchaseInvoice = false,
    this.canReadAccount = false,
    this.canReadGlEntry = false,
    this.canReadJournalEntry = false,
    this.canCreateJournalEntry = false,
  });

  bool get canUseCashBank =>
      canReadPaymentEntry || canReadAccount || canReadGlEntry;
  bool get canUseReceivablePayable =>
      canReadSalesInvoice || canReadPurchaseInvoice;
  bool get canUseAccounting => canReadJournalEntry || canReadGlEntry;
  bool get canUseDashboard =>
      canUseCashBank || canUseReceivablePayable || canUseAccounting;
  bool get hasAnyFinanceAccess =>
      canUseDashboard || canCreatePaymentEntry || canCreateJournalEntry;

  FinanceDataAccess toDataAccess() {
    return FinanceDataAccess(
      canReadPaymentEntry: canReadPaymentEntry,
      canReadSalesInvoice: canReadSalesInvoice,
      canReadPurchaseInvoice: canReadPurchaseInvoice,
      canReadAccount: canReadAccount,
      canReadGlEntry: canReadGlEntry,
      canReadJournalEntry: canReadJournalEntry,
    );
  }

  List<_FinanceTabEntry> entries({required bool accountingOnly}) {
    final entries = <_FinanceTabEntry>[];
    if (!accountingOnly && canUseDashboard) {
      entries.add(
        const _FinanceTabEntry(
          view: _FinanceView.dashboard,
          destination: NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
        ),
      );
    }
    if (!accountingOnly && canUseCashBank) {
      entries.add(
        const _FinanceTabEntry(
          view: _FinanceView.cashBank,
          destination: NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon: Icon(Icons.account_balance_rounded),
            label: 'Bank',
          ),
        ),
      );
    }
    if (!accountingOnly && canUseReceivablePayable) {
      entries.add(
        const _FinanceTabEntry(
          view: _FinanceView.receivablePayable,
          destination: NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'AR/AP',
          ),
        ),
      );
    }
    if (canUseAccounting) {
      entries.add(
        const _FinanceTabEntry(
          view: _FinanceView.accounting,
          destination: NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories_rounded),
            label: 'Ledger',
          ),
        ),
      );
    }
    return entries;
  }
}
