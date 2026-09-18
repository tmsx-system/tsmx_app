import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/promo_request.dart';
import '../../../state/selling/promo_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/sales_ui.dart';

class CreatePromoRequestScreen extends StatefulWidget {
  const CreatePromoRequestScreen({super.key});

  @override
  State<CreatePromoRequestScreen> createState() =>
      _CreatePromoRequestScreenState();
}

class _CreatePromoRequestScreenState extends State<CreatePromoRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerGroupController = TextEditingController();
  final _customerController = TextEditingController();
  final _noteController = TextEditingController();
  final List<_PromoItemForm> _items = [_PromoItemForm()];

  final DateTime _requestDate = DateTime.now();
  DateTime _validFrom = DateTime.now();
  DateTime _validUpto = DateTime.now().add(const Duration(days: 7));
  String? _selectedCompany;
  String? _selectedSalesPerson;
  String? _selectedPriceList;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _customerGroupController.dispose();
    _customerController.dispose();
    _noteController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PromoState>();
    final companies = state.sellingCompanies;
    final preferredCompany = state.preferredCompany(companies);
    if (_selectedCompany == null && preferredCompany != null) {
      _selectedCompany = preferredCompany;
    }
    final currentSalesPerson = state.currentSalesPerson?.trim() ?? '';
    if (_selectedSalesPerson == null && currentSalesPerson.isNotEmpty) {
      _selectedSalesPerson = currentSalesPerson;
    }
    if (state.isSalesUserRole && currentSalesPerson.isNotEmpty) {
      _selectedSalesPerson = currentSalesPerson;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Buat Promo',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
      body: TmsxResponsiveBody(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: SalesUi.compactScreenPaddingOf(context),
            children: [
              SalesHeroCard(
                title: 'Pengajuan Promo Session',
                subtitle:
                    'Ajukan promo item untuk diproses menjadi Promotional Scheme.',
                icon: Icons.local_offer_rounded,
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
                          'Pilih company, sales, target, dan periode promo.',
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
                        : _valuePickerField(
                            label: 'Sales Person',
                            value: _selectedSalesPerson,
                            placeholder: 'Pilih sales person',
                            icon: Icons.person_rounded,
                            onTap: _pickSalesPerson,
                            onClear: () =>
                                setState(() => _selectedSalesPerson = null),
                          ),
                    SalesUi.gap(),
                    _linkPickerField(
                      controller: _customerGroupController,
                      label: 'Customer Group',
                      placeholder: 'Pilih customer group',
                      icon: Icons.groups_rounded,
                      onTap: _pickCustomerGroup,
                    ),
                    SalesUi.gap(),
                    _linkPickerField(
                      controller: _customerController,
                      label: 'Customer',
                      placeholder: 'Pilih customer',
                      icon: Icons.storefront_rounded,
                      onTap: _pickCustomer,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Isi salah satu: Customer Group atau Customer.',
                      style: TextStyle(
                        color: AppColors.slate,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SalesUi.gap(),
                    Row(
                      children: [
                        Expanded(
                          child: _dateTile(
                            label: 'Valid From',
                            value: _validFrom,
                            onTap: () => _pickDate(
                              current: _validFrom,
                              onPicked: (date) =>
                                  setState(() => _validFrom = date),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _dateTile(
                            label: 'Valid Upto',
                            value: _validUpto,
                            onTap: () => _pickDate(
                              current: _validUpto,
                              onPicked: (date) =>
                                  setState(() => _validUpto = date),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SalesUi.gap(),
              SalesInfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SalesSectionTitle(
                      title: 'Item Promo',
                      subtitle: 'Isi diskon nominal atau harga promo per item.',
                    ),
                    SalesUi.gap(),
                    ...List.generate(_items.length, _itemCard),
                    OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _items.add(_PromoItemForm())),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Tambah Item'),
                    ),
                  ],
                ),
              ),
              SalesUi.gap(),
              SalesInfoCard(
                child: _textField(
                  controller: _noteController,
                  label: 'Catatan Promo',
                  icon: Icons.notes_rounded,
                  maxLines: 4,
                ),
              ),
              const SizedBox(height: 96),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          TmsxResponsive.horizontalPadding(context),
          8,
          TmsxResponsive.horizontalPadding(context),
          16,
        ),
        child: TmsxResponsiveBody(
          child: FilledButton.icon(
            onPressed: _isSubmitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              minimumSize: const Size.fromHeight(52),
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.white,
                      ),
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              _isSubmitting ? 'Mengirim...' : 'Kirim Pengajuan Promo',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ),
    );
  }

  Widget _itemCard(int index) {
    final item = _items[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Item ${index + 1}',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (_items.length > 1)
                IconButton(
                  tooltip: 'Hapus item',
                  onPressed: () {
                    setState(() {
                      final removed = _items.removeAt(index);
                      removed.dispose();
                    });
                  },
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.danger,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FormField<String>(
            validator: (_) =>
                item.itemCode == null ? 'Item wajib dipilih' : null,
            builder: (field) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _pickItem(index),
                  child: InputDecorator(
                    decoration: _decoration(
                      'Item',
                      Icons.inventory_2_rounded,
                    ).copyWith(errorText: field.errorText),
                    child: Text(
                      item.itemCode == null
                          ? 'Pilih item'
                          : '${item.itemName ?? item.itemCode} (${item.itemCode})',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: item.itemCode == null
                            ? AppColors.slate
                            : AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SalesUi.gap(),
          _textField(
            controller: item.uomController,
            label: 'UOM',
            icon: Icons.straighten_rounded,
          ),
          SalesUi.gap(),
          _textField(
            controller: item.discountController,
            label: 'Discount Amount',
            icon: Icons.discount_rounded,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() => _syncPromoRateFromDiscount(item)),
          ),
          SalesUi.gap(),
          _textField(
            controller: item.rateController,
            label: 'Harga Promo / Rate',
            icon: Icons.price_change_rounded,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          SalesUi.gap(),
          _priceListRateInfo(item),
        ],
      ),
    );
  }

  Widget _priceListRateInfo(_PromoItemForm item) {
    final rate = item.priceListRate;
    final priceList = item.priceListName ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.softGreen.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.local_offer_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Harga Price List',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
                Text(
                  priceList.isEmpty
                      ? 'Harga asli dari Item Price'
                      : 'Harga asli dari $priceList',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            rate == null ? '-' : _formatCurrency(rate),
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _companyField(List<String> companies) {
    return DropdownButtonFormField<String>(
      initialValue: companies.contains(_selectedCompany)
          ? _selectedCompany
          : null,
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

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isRequired = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: _decoration(label, icon),
      onChanged: onChanged,
      validator: isRequired
          ? (value) => value == null || value.trim().isEmpty
                ? '$label wajib diisi'
                : null
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _valuePickerField({
    required String label,
    required String? value,
    required String placeholder,
    required IconData icon,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    final text = value?.trim() ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: _decoration(label, icon).copyWith(
          suffixIcon: text.isEmpty
              ? const Icon(Icons.search_rounded)
              : IconButton(
                  tooltip: 'Hapus pilihan',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        child: Text(
          text.isEmpty ? placeholder : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: text.isEmpty ? AppColors.slate : AppColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _linkPickerField({
    required TextEditingController controller,
    required String label,
    required String placeholder,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final value = controller.text.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: _decoration(label, icon).copyWith(
          suffixIcon: value.isEmpty
              ? const Icon(Icons.search_rounded)
              : IconButton(
                  tooltip: 'Hapus pilihan',
                  onPressed: () => setState(controller.clear),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        child: Text(
          value.isEmpty ? placeholder : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: value.isEmpty ? AppColors.slate : AppColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: _decoration(label, Icons.calendar_month_rounded),
        child: Text(
          _formatDate(value),
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _statusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Draft',
        style: TextStyle(
          color: AppColors.warning,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: AppColors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
    );
  }

  Future<void> _pickDate({
    required DateTime current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _pickItem(int index) async {
    final state = context.read<PromoState>();
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ItemSearchSheet(state: context.read<PromoState>()),
    );
    if (picked == null || !mounted) return;
    final itemCode = _text(picked['name']);
    final uom = _text(picked['stock_uom']);
    setState(() {
      final item = _items[index];
      item.itemCode = itemCode;
      item.itemName = _text(picked['item_name'], fallback: itemCode);
      item.uomController.text = uom;
      item.priceListName = null;
      item.priceListRate = null;
    });
    final price = await _loadItemPrice(state, itemCode: itemCode, uom: uom);
    if (!mounted || index >= _items.length) return;
    final currentItem = _items[index];
    if (currentItem.itemCode != itemCode) return;
    setState(() {
      currentItem.priceListName = price?.priceList;
      currentItem.priceListRate = price?.rate;
      _syncPromoRateFromDiscount(currentItem);
    });
  }

  Future<void> _pickSalesPerson() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _LinkSearchSheet(
        state: context.read<PromoState>(),
        title: 'Pilih Sales Person',
        searchHint: 'Cari sales person',
        emptyText: 'Sales Person tidak ditemukan',
        doctype: 'Sales Person',
        fields: const ['name', 'sales_person_name', 'enabled', 'is_group'],
        baseFilters: const [
          ['is_group', '=', 0],
          ['enabled', '=', 1],
        ],
        searchFields: const ['name', 'sales_person_name'],
        orderBy: 'sales_person_name asc',
        icon: Icons.person_rounded,
        titleBuilder: (row) =>
            _text(row['sales_person_name'], fallback: _text(row['name'])),
        subtitleBuilder: (row) => _text(row['name']),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedSalesPerson = _text(picked['name']));
  }

  Future<void> _pickCustomerGroup() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _LinkSearchSheet(
        state: context.read<PromoState>(),
        title: 'Pilih Customer Group',
        searchHint: 'Cari customer group',
        emptyText: 'Customer Group tidak ditemukan',
        doctype: 'Customer Group',
        fields: const ['name', 'is_group'],
        baseFilters: const [
          ['is_group', '=', 0],
        ],
        orderBy: 'name asc',
        icon: Icons.groups_rounded,
        titleBuilder: (row) => _text(row['name']),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _customerGroupController.text = _text(picked['name']));
  }

  Future<void> _pickCustomer() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _LinkSearchSheet(
        state: context.read<PromoState>(),
        title: 'Pilih Customer',
        searchHint: 'Cari nama atau kode customer',
        emptyText: 'Customer tidak ditemukan',
        doctype: 'Customer',
        fields: const ['name', 'customer_name', 'customer_group', 'disabled'],
        baseFilters: const [
          ['disabled', '=', 0],
        ],
        orderBy: 'customer_name asc',
        icon: Icons.storefront_rounded,
        searchFields: const ['name', 'customer_name'],
        titleBuilder: (row) =>
            _text(row['customer_name'], fallback: _text(row['name'])),
        subtitleBuilder: (row) => [
          _text(row['name']),
          _text(row['customer_group']),
        ].where((value) => value.isNotEmpty).join(' - '),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customerController.text = _text(picked['name']);
      final group = _text(picked['customer_group']);
      if (group.isNotEmpty) _customerGroupController.text = group;
      _selectedPriceList = null;
    });
    await _loadCustomerPricingDefaults(_text(picked['name']));
  }

  Future<void> _loadCustomerPricingDefaults(String customer) async {
    final normalizedCustomer = customer.trim();
    if (normalizedCustomer.isEmpty) return;
    try {
      final insight = await context
          .read<PromoState>()
          .fetchCustomerSalesInsight(
            normalizedCustomer,
            company: _selectedCompany?.trim(),
          );
      if (!mounted || _customerController.text.trim() != normalizedCustomer) {
        return;
      }
      setState(() {
        if (insight.priceList.trim().isNotEmpty) {
          _selectedPriceList = insight.priceList.trim();
        }
        if (insight.customerGroup.trim().isNotEmpty &&
            _customerGroupController.text.trim().isEmpty) {
          _customerGroupController.text = insight.customerGroup.trim();
        }
      });
    } catch (_) {}
  }

  Future<_ItemPriceResult?> _loadItemPrice(
    PromoState state, {
    required String itemCode,
    required String uom,
  }) async {
    if (itemCode.trim().isEmpty) return null;
    final customer = _customerController.text.trim();
    final company = _selectedCompany?.trim() ?? '';
    final customerGroup = _customerGroupController.text.trim();

    try {
      final insight = await state.fetchItemSalesInsight(
        itemCode,
        customer: customer,
        company: company,
        priceList: _selectedPriceList,
        customerGroup: customerGroup.isNotEmpty ? customerGroup : null,
        transactionDate: _requestDate,
      );
      final rate = insight.priceListRate > 0
          ? insight.priceListRate
          : insight.price;
      if (rate > 0) {
        _selectedPriceList = insight.priceList.trim().isNotEmpty
            ? insight.priceList.trim()
            : _selectedPriceList;
        return _ItemPriceResult(rate: rate, priceList: insight.priceList);
      }
    } catch (_) {
      // Fallback to Item Price below when pricing API cannot resolve context.
    }

    final rows = await state.frappeService.fetchResource(
      'Item Price',
      fields: const ['price_list_rate', 'price_list', 'uom', 'currency'],
      filters: [
        ['item_code', '=', itemCode],
        ['selling', '=', 1],
        if (_selectedPriceList?.trim().isNotEmpty == true)
          ['price_list', '=', _selectedPriceList!.trim()],
      ],
      orderBy: 'valid_from desc, modified desc',
      limit: 20,
    );
    if (rows.isEmpty && _selectedPriceList?.trim().isNotEmpty == true) {
      final fallbackRows = await state.frappeService.fetchResource(
        'Item Price',
        fields: const ['price_list_rate', 'price_list', 'uom', 'currency'],
        filters: [
          ['item_code', '=', itemCode],
          ['selling', '=', 1],
        ],
        orderBy: 'valid_from desc, modified desc',
        limit: 20,
      );
      return _itemPriceResultFromRows(fallbackRows, uom);
    }
    return _itemPriceResultFromRows(rows, uom);
  }

  _ItemPriceResult? _itemPriceResultFromRows(
    List<Map<String, dynamic>> rows,
    String uom,
  ) {
    if (rows.isEmpty) return null;
    var row = rows.first;
    if (uom.trim().isNotEmpty) {
      row = rows.firstWhere((candidate) {
        final candidateUom = _text(candidate['uom']);
        return candidateUom.isEmpty || candidateUom == uom;
      }, orElse: () => rows.first);
    }
    final rate = _parseApiNumber(row['price_list_rate']);
    if (rate == null) return null;
    final priceList = _text(row['price_list']);
    if (priceList.isNotEmpty) _selectedPriceList = priceList;
    return _ItemPriceResult(rate: rate, priceList: priceList);
  }

  void _syncPromoRateFromDiscount(_PromoItemForm item) {
    final priceListRate = item.priceListRate;
    if (priceListRate == null || priceListRate <= 0) return;

    final discount = _parseNumber(item.discountController.text);
    if (discount == null || discount <= 0) return;

    final promoRate = priceListRate - discount;
    item.rateController.text = _formatAmountInput(
      promoRate > 0 ? promoRate : 0,
    );
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    final salesPerson = _selectedSalesPerson?.trim() ?? '';
    if (salesPerson.isEmpty) {
      _showError('Sales Person wajib dipilih.');
      return;
    }
    final hasTarget =
        _customerGroupController.text.trim().isNotEmpty ||
        _customerController.text.trim().isNotEmpty;
    if (!hasTarget) {
      _showError('Isi minimal Customer Group atau Customer.');
      return;
    }
    if (_validUpto.isBefore(_validFrom)) {
      _showError('Valid Upto tidak boleh sebelum Valid From.');
      return;
    }
    final drafts = <PromoRequestItemDraft>[];
    for (final item in _items) {
      final itemCode = item.itemCode?.trim() ?? '';
      if (itemCode.isEmpty) continue;
      final discount = _parseNumber(item.discountController.text);
      final rate = _parseNumber(item.rateController.text);
      final priceListRate = item.priceListRate;
      final double? resolvedRate =
          rate ??
          (priceListRate == null
              ? null
              : (priceListRate - (discount ?? 0) > 0
                    ? priceListRate - (discount ?? 0)
                    : 0));
      if ((discount == null || discount <= 0) &&
          (resolvedRate == null || resolvedRate <= 0)) {
        _showError('Isi Discount Amount atau Harga Promo untuk setiap item.');
        return;
      }
      drafts.add(
        PromoRequestItemDraft(
          itemCode: itemCode,
          uom: item.uomController.text,
          priceListRate: priceListRate,
          requestedDiscount: discount,
          requestedRate: resolvedRate,
        ),
      );
    }
    if (drafts.isEmpty) {
      _showError('Minimal satu item promo wajib dipilih.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final draft = PromoRequestDraft(
        requestDate: _requestDate,
        company: _selectedCompany ?? '',
        salesPerson: salesPerson,
        customerGroup: _customerGroupController.text,
        customer: _customerController.text,
        validFrom: _validFrom,
        validUpto: _validUpto,
        promoNote: _noteController.text,
        items: drafts,
      );
      await context.read<PromoState>().createPromoRequest(draft);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      _showError(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double? _parseNumber(String value) {
    final cleaned = value
        .replaceAll('Rp', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  double? _parseApiNumber(dynamic value) {
    if (value is num) return value.toDouble();
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final cleaned = raw.replaceAll('Rp', '').replaceAll(' ', '').trim();
    if (cleaned.contains('.') && cleaned.contains(',')) {
      return double.tryParse(cleaned.replaceAll('.', '').replaceAll(',', '.'));
    }
    if (cleaned.contains(',')) {
      return double.tryParse(cleaned.replaceAll('.', '').replaceAll(',', '.'));
    }
    return double.tryParse(cleaned);
  }

  String _formatCurrency(num value) {
    final text = value.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final remaining = text.length - i;
      buffer.write(text[i]);
      if (remaining > 1 && (remaining - 1) % 3 == 0) buffer.write('.');
    }
    return 'Rp ${buffer.toString()}';
  }

  String _formatAmountInput(num value) {
    if (value % 1 == 0) return value.round().toString();
    return value.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}

class _PromoItemForm {
  String? itemCode;
  String? itemName;
  String? priceListName;
  double? priceListRate;
  final uomController = TextEditingController();
  final discountController = TextEditingController();
  final rateController = TextEditingController();

  void dispose() {
    uomController.dispose();
    discountController.dispose();
    rateController.dispose();
  }
}

class _ItemPriceResult {
  const _ItemPriceResult({required this.rate, required this.priceList});

  final double rate;
  final String priceList;
}

class _LinkSearchSheet extends StatefulWidget {
  const _LinkSearchSheet({
    required this.state,
    required this.title,
    required this.searchHint,
    required this.emptyText,
    required this.doctype,
    required this.fields,
    required this.icon,
    required this.titleBuilder,
    this.subtitleBuilder,
    this.baseFilters = const [],
    this.searchFields = const ['name'],
    this.orderBy = 'modified desc',
  });

  final PromoState state;
  final String title;
  final String searchHint;
  final String emptyText;
  final String doctype;
  final List<String> fields;
  final List<List<dynamic>> baseFilters;
  final List<String> searchFields;
  final String orderBy;
  final IconData icon;
  final String Function(Map<String, dynamic> row) titleBuilder;
  final String Function(Map<String, dynamic> row)? subtitleBuilder;

  @override
  State<_LinkSearchSheet> createState() => _LinkSearchSheetState();
}

class _LinkSearchSheetState extends State<_LinkSearchSheet> {
  final _searchController = TextEditingController();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _loadRows();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 10,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => _loadRows(),
              ),
              const SizedBox(height: 12),
              Expanded(child: _content()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.danger,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          widget.emptyText,
          style: const TextStyle(
            color: AppColors.slate,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = _rows[index];
        final title = widget.titleBuilder(row);
        final subtitle = widget.subtitleBuilder?.call(row) ?? '';
        return SalesPickerOptionTile(
          title: title,
          subtitle: subtitle,
          icon: widget.icon,
          onTap: () => Navigator.of(context).pop(row),
        );
      },
    );
  }

  Future<void> _loadRows() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final query = _searchController.text.trim();
      final filters = <List<dynamic>>[
        ...widget.baseFilters,
        if (query.isNotEmpty && widget.searchFields.length == 1)
          [widget.searchFields.first, 'like', '%$query%'],
      ];
      final orFilters = query.isEmpty || widget.searchFields.length <= 1
          ? null
          : widget.searchFields
                .map<List<dynamic>>((field) => [field, 'like', '%$query%'])
                .toList();
      final rows = await widget.state.frappeService.fetchResource(
        widget.doctype,
        fields: widget.fields,
        filters: filters,
        orFilters: orFilters,
        orderBy: widget.orderBy,
        limit: 50,
      );
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (error) {
      try {
        final query = _searchController.text.trim();
        final rows = await widget.state.frappeService.fetchResource(
          widget.doctype,
          fields: const ['name'],
          filters: query.isEmpty
              ? null
              : [
                  ['name', 'like', '%$query%'],
                ],
          orderBy: 'name asc',
          limit: 50,
        );
        if (!mounted) return;
        setState(() => _rows = rows);
      } catch (_) {
        if (!mounted) return;
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _ItemSearchSheet extends StatefulWidget {
  const _ItemSearchSheet({required this.state});

  final PromoState state;

  @override
  State<_ItemSearchSheet> createState() => _ItemSearchSheetState();
}

class _ItemSearchSheetState extends State<_ItemSearchSheet> {
  final _searchController = TextEditingController();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 10,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Pilih Item',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Cari nama atau kode item',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => _loadItems(),
              ),
              const SizedBox(height: 12),
              Expanded(child: _content()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.danger,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'Item tidak ditemukan',
          style: TextStyle(color: AppColors.slate, fontWeight: FontWeight.w700),
        ),
      );
    }
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _items[index];
        final name = _text(item['name']);
        final itemName = _text(item['item_name'], fallback: name);
        final uom = _text(item['stock_uom']);
        return SalesPickerOptionTile(
          title: itemName,
          subtitle: [name, uom].where((value) => value.isNotEmpty).join(' - '),
          icon: Icons.inventory_2_rounded,
          onTap: () => Navigator.of(context).pop(item),
        );
      },
    );
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final query = _searchController.text.trim();
      final filters = <List<dynamic>>[
        ['disabled', '=', 0],
      ];
      Future<List<Map<String, dynamic>>> fetch({
        List<List<dynamic>>? orFilters,
        List<List<dynamic>>? extraFilters,
      }) {
        return widget.state.frappeService.fetchResource(
          'Item',
          fields: const [
            'name',
            'item_name',
            'stock_uom',
            'description',
            'item_group',
          ],
          filters: [...filters, ...?extraFilters],
          orFilters: orFilters,
          orderBy: 'item_name asc',
          limit: 50,
        );
      }

      List<Map<String, dynamic>> rows;
      if (query.isEmpty) {
        rows = await fetch();
      } else {
        try {
          rows = await fetch(
            orFilters: [
              ['name', 'like', '%$query%'],
              ['item_name', 'like', '%$query%'],
            ],
          );
        } catch (_) {
          rows = await fetch(
            extraFilters: [
              ['name', 'like', '%$query%'],
            ],
          );
        }
      }
      if (!mounted) return;
      setState(() => _items = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _text(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}
