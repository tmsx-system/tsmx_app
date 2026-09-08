import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/noo_request.dart';
import '../../../state/selling/noo_state.dart';
import '../../../theme/app_colors.dart';
import '../shared/sales_ui.dart';

class CreateNooRequestScreen extends StatefulWidget {
  final Map<String, dynamic>? initial;

  const CreateNooRequestScreen({super.key, this.initial});

  bool get isEditMode => initial != null;

  @override
  State<CreateNooRequestScreen> createState() => _CreateNooRequestScreenState();
}

class _CreateNooRequestScreenState extends State<CreateNooRequestScreen> {
  static const _customerCategoryOptions = ['GT', 'MT'];

  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _mobileNoController = TextEditingController();
  final _addressController = TextEditingController();

  String? _selectedCompany;
  String? _selectedSalesPerson;
  String? _customerCategory;
  List<String> _salesPersonOptions = const [];
  bool _salesPersonOptionsRequested = false;
  bool _isLoadingSalesPersons = false;
  String? _salesPersonLoadError;
  List<String> _paymentTermsOptions = const [];
  bool _paymentTermsOptionsRequested = false;
  bool _isLoadingPaymentTerms = false;
  String? _paymentTermsLoadError;
  String? _defaultPaymentTermsTemplate;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _selectedCompany = _text(initial['company']);
    _selectedSalesPerson = _text(initial['sales_person']);
    _customerCategory = _text(initial['customer_category']);
    _defaultPaymentTermsTemplate = _text(
      initial['default_payment_terms_template'],
    );
    _customerNameController.text = _text(initial['customer_name']);
    _mobileNoController.text = _text(initial['mobile_no']);
    _addressController.text = _text(initial['address_line1']);
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _mobileNoController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<NooState>();
    final companies = state.sellingCompanies;
    final preferredCompany = state.preferredCompany(companies);
    if (_selectedCompany == null && preferredCompany != null) {
      _selectedCompany = preferredCompany;
    }
    final currentSalesPerson = state.currentSalesPerson?.trim() ?? '';
    if (state.isSalesUserRole && currentSalesPerson.isNotEmpty) {
      _selectedSalesPerson = currentSalesPerson;
    }
    if (!state.isSalesUserRole && !_salesPersonOptionsRequested) {
      _salesPersonOptionsRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadSalesPersonOptions(context.read<NooState>());
      });
    }
    if (!_paymentTermsOptionsRequested) {
      _paymentTermsOptionsRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPaymentTermsOptions(context.read<NooState>());
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Pengajuan NOO',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: SalesUi.compactScreenPaddingOf(context),
          children: [
            SalesHeroCard(
              title: widget.isEditMode ? 'Edit NOO' : 'Pengajuan NOO',
              subtitle: widget.isEditMode
                  ? 'Perbarui data pengajuan outlet sebelum diproses.'
                  : 'Ajukan outlet baru sebelum dibuatkan master Customer.',
              icon: Icons.person_add_alt_1_rounded,
              trailing: _statusChip(),
            ),
            SalesUi.gap(),
            SalesInfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SalesSectionTitle(
                    title: 'Data Pengajuan',
                    subtitle:
                        'Sales user terkunci ke akun login, admin bisa memilih.',
                  ),
                  SalesUi.gap(),
                  _companyField(companies),
                  SalesUi.gap(),
                  state.isSalesUserRole
                      ? _readonlyValue(
                          label: 'Sales Person',
                          value: currentSalesPerson.isNotEmpty
                              ? currentSalesPerson
                              : '-',
                          icon: Icons.person_rounded,
                        )
                      : _salesPersonField(),
                  if (_salesPersonLoadError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _salesPersonLoadError!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SalesUi.gap(),
            SalesInfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SalesSectionTitle(
                    title: 'Data Customer',
                    subtitle:
                        'Nama calon customer, kategori, payment terms, nomor HP, dan alamat.',
                  ),
                  SalesUi.gap(),
                  _textField(
                    controller: _customerNameController,
                    label: 'Nama Outlet / Customer',
                    icon: Icons.store_mall_directory_rounded,
                    isRequired: true,
                  ),
                  SalesUi.gap(),
                  DropdownButtonFormField<String>(
                    initialValue: _validCustomerCategory(_customerCategory),
                    decoration: _decoration(
                      'Customer Category',
                      Icons.category_rounded,
                    ),
                    isExpanded: true,
                    items: _customerCategoryOptions
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ),
                        )
                        .toList(),
                    hint: const Text('Pilih kategori'),
                    onChanged: (value) =>
                        setState(() => _customerCategory = value),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Customer Category wajib dipilih'
                        : null,
                  ),
                  SalesUi.gap(),
                  DropdownButtonFormField<String>(
                    initialValue:
                        _paymentTermsOptions.contains(
                          _defaultPaymentTermsTemplate,
                        )
                        ? _defaultPaymentTermsTemplate
                        : null,
                    decoration: _decoration(
                      'Default Payment Terms Template',
                      Icons.payments_rounded,
                    ),
                    isExpanded: true,
                    items: _paymentTermsOptions
                        .map(
                          (template) => DropdownMenuItem(
                            value: template,
                            child: Text(
                              template,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    hint: Text(
                      _isLoadingPaymentTerms
                          ? 'Memuat payment terms...'
                          : 'Pilih payment terms',
                    ),
                    onChanged: _isLoadingPaymentTerms
                        ? null
                        : (value) => setState(
                            () => _defaultPaymentTermsTemplate = value,
                          ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Default Payment Terms Template wajib dipilih'
                        : null,
                  ),
                  if (_paymentTermsLoadError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _paymentTermsLoadError!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  _textField(
                    controller: _mobileNoController,
                    label: 'No. HP',
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                    isRequired: true,
                  ),
                  SalesUi.gap(),
                  _textField(
                    controller: _addressController,
                    label: 'Alamat Utama',
                    icon: Icons.location_on_rounded,
                    isRequired: true,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            SalesUi.gap(16),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                disabledBackgroundColor: AppColors.primary.withValues(
                  alpha: 0.35,
                ),
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                _isSubmitting
                    ? (widget.isEditMode ? 'Menyimpan...' : 'Mengirim...')
                    : (widget.isEditMode
                          ? 'Simpan Perubahan'
                          : 'Kirim Pengajuan NOO'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Pending Approval',
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _companyField(List<String> companies) {
    if (companies.isEmpty) {
      return _readonlyValue(
        label: 'Company',
        value: _selectedCompany ?? '-',
        icon: Icons.business_rounded,
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedCompany,
      decoration: _decoration('Company', Icons.business_rounded),
      isExpanded: true,
      items: companies
          .map(
            (company) => DropdownMenuItem(
              value: company,
              child: Text(
                company,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _selectedCompany = value),
      validator: (value) => value == null || value.trim().isEmpty
          ? 'Company wajib dipilih'
          : null,
    );
  }

  Widget _salesPersonField() {
    final selected = _salesPersonOptions.contains(_selectedSalesPerson)
        ? _selectedSalesPerson
        : null;
    return DropdownButtonFormField<String>(
      initialValue: selected,
      decoration: _decoration('Sales Person', Icons.person_rounded).copyWith(
        suffixIcon: _isLoadingSalesPersons
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      isExpanded: true,
      items: _salesPersonOptions
          .map(
            (salesPerson) => DropdownMenuItem(
              value: salesPerson,
              child: Text(
                salesPerson,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _isLoadingSalesPersons
          ? null
          : (value) => setState(() => _selectedSalesPerson = value),
      validator: (value) => value == null || value.trim().isEmpty
          ? 'Sales Person wajib dipilih'
          : null,
    );
  }

  Widget _readonlyValue({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return InputDecorator(
      decoration: _decoration(label, icon),
      child: Text(
        value,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isRequired = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction: maxLines > 1 ? TextInputAction.newline : null,
      decoration: _decoration(label, icon),
      validator:
          validator ??
          (value) {
            if (!isRequired) return null;
            return value?.trim().isNotEmpty == true
                ? null
                : '$label wajib diisi';
          },
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    );
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final company = _selectedCompany?.trim();
    if (company == null || company.isEmpty) return;
    final state = context.read<NooState>();
    final salesPerson =
        (state.isSalesUserRole
                ? state.currentSalesPerson
                : _selectedSalesPerson)
            ?.trim();
    if (salesPerson == null || salesPerson.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sales Person wajib dipilih.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final draft = NooRequestDraft(
        requestDate: DateTime.now(),
        company: company,
        salesPerson: salesPerson,
        customerName: _customerNameController.text,
        customerCategory: _customerCategory,
        defaultPaymentTermsTemplate: _defaultPaymentTermsTemplate,
        mobileNo: _mobileNoController.text,
        addressLine1: _addressController.text,
      );
      final name = _text(widget.initial?['name']);
      if (widget.isEditMode && name.isNotEmpty) {
        await state.updateNooRequest(name, draft);
      } else {
        await state.createNooRequest(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal kirim NOO: $error')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _loadSalesPersonOptions(NooState state) async {
    setState(() {
      _isLoadingSalesPersons = true;
      _salesPersonLoadError = null;
    });
    try {
      Future<List<Map<String, dynamic>>> fetch(List<List<dynamic>> filters) {
        return state.frappeService.fetchResource(
          'Sales Person',
          fields: const ['name'],
          filters: filters,
          orderBy: 'name asc',
        );
      }

      List<Map<String, dynamic>> rows;
      try {
        rows = await fetch(const [
          ['is_group', '=', 0],
          ['enabled', '=', 1],
        ]);
      } catch (_) {
        rows = await fetch(const [
          ['is_group', '=', 0],
        ]);
      }

      final options =
          rows
              .map((row) => row['name']?.toString().trim() ?? '')
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (!mounted) return;
      setState(() {
        _salesPersonOptions = options;
        final current = state.currentSalesPerson?.trim();
        _selectedSalesPerson = options.contains(_selectedSalesPerson)
            ? _selectedSalesPerson
            : (current != null && options.contains(current) ? current : null);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _salesPersonLoadError =
            'Sales Person gagal dimuat. Pastikan role punya Read Sales Person.';
      });
    } finally {
      if (mounted) setState(() => _isLoadingSalesPersons = false);
    }
  }

  Future<void> _loadPaymentTermsOptions(NooState state) async {
    setState(() {
      _isLoadingPaymentTerms = true;
      _paymentTermsLoadError = null;
    });
    try {
      final rows = await state.frappeService.fetchResource(
        'Payment Terms Template',
        fields: const ['name'],
        orderBy: 'name asc',
        limit: 100,
      );
      final options =
          rows
              .map((row) => row['name']?.toString().trim() ?? '')
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (!mounted) return;
      setState(() {
        _paymentTermsOptions = options;
        _defaultPaymentTermsTemplate =
            options.contains(_defaultPaymentTermsTemplate)
            ? _defaultPaymentTermsTemplate
            : null;
        if (options.isEmpty) {
          _paymentTermsLoadError =
              'Payment Terms Template kosong atau belum tersedia di ERPNext.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _paymentTermsOptions = const [];
        _defaultPaymentTermsTemplate = null;
        _paymentTermsLoadError =
            'Payment Terms Template gagal dimuat. Pastikan role punya Read Payment Terms Template.';
      });
    } finally {
      if (mounted) setState(() => _isLoadingPaymentTerms = false);
    }
  }

  String _text(Object? value) => value?.toString().trim() ?? '';

  String? _validCustomerCategory(String? value) {
    final normalized = value?.trim().toUpperCase() ?? '';
    return _customerCategoryOptions.contains(normalized) ? normalized : null;
  }
}
