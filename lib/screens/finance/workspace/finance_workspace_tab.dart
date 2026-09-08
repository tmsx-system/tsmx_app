part of '../finance_main_screen.dart';

final _financeFilterStore = _FinanceFilterStore();

class _FinanceFilterStore extends ChangeNotifier {
  _FinanceFilterStore() {
    final now = DateTime.now();
    year = now.year;
    month = now.month;
  }

  late int year;
  late int month;
  String company = '';

  void update({int? year, int? month, String? company}) {
    var changed = false;
    if (year != null && year != this.year) {
      this.year = year;
      changed = true;
    }
    if (month != null && month != this.month) {
      this.month = month;
      changed = true;
    }
    if (company != null && company != this.company) {
      this.company = company;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}

class _FinanceWorkspaceTab extends StatefulWidget {
  final _FinanceView initialView;
  final _FinanceAccess access;

  const _FinanceWorkspaceTab({required this.initialView, required this.access});

  @override
  State<_FinanceWorkspaceTab> createState() => _FinanceWorkspaceTabState();
}

class _FinanceWorkspaceTabState extends State<_FinanceWorkspaceTab> {
  late int _year;
  late int _month;
  String _company = '';
  List<String> _companies = const [];
  FinanceDashboardData _data = const FinanceDashboardData();
  bool _loading = true;
  String? _error;

  DateTime get _from =>
      _month == 0 ? DateTime(_year) : DateTime(_year, _month, 1);
  DateTime get _to =>
      _month == 0 ? DateTime(_year, 12, 31) : DateTime(_year, _month + 1, 0);

  @override
  void initState() {
    super.initState();
    _year = _financeFilterStore.year;
    _month = _financeFilterStore.month;
    _company = _financeFilterStore.company;
    _financeFilterStore.addListener(_syncSharedFilters);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _financeFilterStore.removeListener(_syncSharedFilters);
    super.dispose();
  }

  void _syncSharedFilters() {
    if (!mounted) return;
    if (_year == _financeFilterStore.year &&
        _month == _financeFilterStore.month &&
        _company == _financeFilterStore.company) {
      return;
    }
    setState(() {
      _year = _financeFilterStore.year;
      _month = _financeFilterStore.month;
      _company = _financeFilterStore.company;
    });
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!mounted) return;
    _year = _financeFilterStore.year;
    _month = _financeFilterStore.month;
    _company = _financeFilterStore.company;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<FinanceState>();
      final companies = await state.loadCompanies();
      var selectedCompany = _company;
      if (selectedCompany.isEmpty && companies.isNotEmpty) {
        selectedCompany = state.preferredCompany(companies) ?? companies.first;
      }
      final data = await state.fetchDashboardData(
        access: widget.access.toDataAccess(),
        from: _from,
        to: _to,
        company: selectedCompany,
        year: _year,
        month: _month,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _companies = companies;
        _company = selectedCompany;
        _data = data;
      });
      _financeFilterStore.update(company: selectedCompany);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setPeriod(int year, int month) {
    _financeFilterStore.update(year: year, month: month);
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.initialView) {
      _FinanceView.dashboard => 'Finance Dashboard',
      _FinanceView.cashBank => 'Cash & Bank',
      _FinanceView.receivablePayable => 'Outstanding AR/AP',
      _FinanceView.accounting => 'Accounting',
    };
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _load(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: TmsxResponsive.pagePadding(context, top: 18, bottom: 96),
        children: [
          _FinancePeriodCard(
            title: title,
            subtitle: 'Data mengikuti periode dan company aktif ERPNext',
            icon: Icons.account_balance_wallet_rounded,
            selectedYear: _year,
            selectedMonth: _month,
            loading: _loading,
            companyOptions: _companies,
            selectedCompany: _company,
            onChanged: _setPeriod,
            onCompanyChanged: (company) {
              _financeFilterStore.update(company: company);
            },
          ),
          const SizedBox(height: 14),
          if (_error != null)
            ErpErrorBox(message: _error!, onRetry: _load)
          else if (_loading)
            const SizedBox.shrink()
          else
            switch (widget.initialView) {
              _FinanceView.dashboard => _DashboardView(data: _data),
              _FinanceView.cashBank => _CashBankView(data: _data),
              _FinanceView.receivablePayable => _ReceivablePayableView(
                data: _data,
              ),
              _FinanceView.accounting => _AccountingView(data: _data),
            },
        ],
      ),
    );
  }
}
