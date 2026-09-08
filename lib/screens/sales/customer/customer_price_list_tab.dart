import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/sales_order_insight.dart';
import '../../../models/sales_workspace.dart';
import '../../../state/selling/customer_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/responsive/responsive_layout.dart';
import '../shared/sales_ui.dart';

const Color _priceTeal = Color(0xFF14B8A6);
const Color _priceBlue = Color(0xFF3B82F6);
const Color _priceGreen = Color(0xFF16A34A);

class CustomerPriceListTab extends StatefulWidget {
  const CustomerPriceListTab({super.key});

  @override
  State<CustomerPriceListTab> createState() => _CustomerPriceListTabState();
}

class _CustomerPriceListTabState extends State<CustomerPriceListTab> {
  final _searchController = TextEditingController();
  final _money = NumberFormat.decimalPattern('id_ID');
  Timer? _searchDebounce;

  List<SalesCustomerOption> _customers = const [];
  List<CustomerItemPrice> _prices = const [];
  SalesCustomerOption? _selectedCustomer;
  CustomerSalesInsight? _customerInsight;
  bool _loadingCustomers = true;
  bool _loadingPrices = false;
  String? _customerError;
  String? _priceError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCustomers();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _loadingCustomers = true;
      _customerError = null;
    });
    try {
      final customers = await context
          .read<CustomerState>()
          .fetchSalesCustomers();
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _selectedCustomer = customers.contains(_selectedCustomer)
            ? _selectedCustomer
            : null;
      });
    } catch (error) {
      if (mounted) setState(() => _customerError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingCustomers = false);
    }
  }

  Future<void> _loadPrices() async {
    final customer = _selectedCustomer;
    if (customer == null) return;
    setState(() {
      _loadingPrices = true;
      _priceError = null;
    });
    try {
      final state = context.read<CustomerState>();
      final insight = await state.fetchCustomerSalesInsight(customer.id);
      final prices = await state.fetchCustomerItemPrices(
        customer: customer.id,
        query: _searchController.text,
        limit: 150,
      );
      if (!mounted) return;
      setState(() {
        _customerInsight = insight;
        _prices = prices;
      });
    } catch (error) {
      if (mounted) setState(() => _priceError = error.toString());
    } finally {
      if (mounted) setState(() => _loadingPrices = false);
    }
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), _loadPrices);
  }

  Future<void> _selectCustomer() async {
    final selected = await showModalBottomSheet<SalesCustomerOption>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _CustomerSelectSheet(
        customers: _customers,
        selected: _selectedCustomer,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedCustomer = selected;
      _prices = const [];
      _customerInsight = null;
      _priceError = null;
    });
    await _loadPrices();
  }

  String _formatMoney(double value, String currency) {
    final amount = _money.format(value.round());
    return currency.trim().isNotEmpty ? '$currency $amount' : 'Rp $amount';
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedCustomer;
    final insight = _customerInsight;
    return RefreshIndicator(
      onRefresh: () async {
        await _loadCustomers();
        if (_selectedCustomer != null) await _loadPrices();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: SalesUi.compactScreenPaddingOf(context),
        children: [
          SalesInfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SalesSectionTitle(
                  title: 'Pilih Customer',
                  subtitle: 'Harga mengikuti default price list customer.',
                ),
                SalesUi.gap(),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _loadingCustomers ? null : _selectCustomer,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Customer',
                      prefixIcon: const Icon(Icons.storefront_rounded),
                      suffixIcon: _loadingCustomers
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : const Icon(Icons.search_rounded),
                    ),
                    child: Text(
                      selected == null
                          ? 'Pilih atau cari customer'
                          : selected.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected == null
                            ? AppColors.slate
                            : AppColors.navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (selected != null && selected.id != selected.name) ...[
                  const SizedBox(height: 6),
                  Text(
                    selected.id,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                SalesUi.gap(),
                TextField(
                  controller: _searchController,
                  enabled: selected != null && !_loadingPrices,
                  onChanged: (_) => _scheduleSearch(),
                  decoration: const InputDecoration(
                    labelText: 'Cari item',
                    hintText: 'Nama atau kode item',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ],
            ),
          ),
          if (_customerError != null) ...[
            SalesUi.gap(14),
            ErpErrorBox(message: _customerError!, onRetry: _loadCustomers),
          ],
          if (insight != null) ...[
            SalesUi.gap(14),
            _PriceListSummary(
              priceList: insight.priceList,
              customerGroup: insight.customerGroup,
              currency: insight.priceListCurrency.isNotEmpty
                  ? insight.priceListCurrency
                  : insight.currency,
              itemCount: _prices.length,
            ),
          ],
          SalesUi.gap(14),
          if (selected == null)
            const ErpEmptyState(
              icon: Icons.storefront_rounded,
              title: 'Pilih customer dulu',
              message:
                  'Setelah customer dipilih, daftar harga item akan tampil.',
            )
          else if (_loadingPrices)
            const _PriceListLoading()
          else if (_priceError != null)
            ErpErrorBox(message: _priceError!, onRetry: _loadPrices)
          else if (_prices.isEmpty)
            const ErpEmptyState(
              icon: Icons.price_change_outlined,
              title: 'Harga item belum tersedia',
              message:
                  'Pastikan Item Price selling tersedia untuk price list customer.',
            )
          else
            ..._prices.map(
              (price) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CustomerItemPriceCard(
                  price: price,
                  priceLabel: _formatMoney(price.rate, price.currency),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PriceListSummary extends StatelessWidget {
  final String priceList;
  final String customerGroup;
  final String currency;
  final int itemCount;

  const _PriceListSummary({
    required this.priceList,
    required this.customerGroup,
    required this.currency,
    required this.itemCount,
  });

  @override
  Widget build(BuildContext context) {
    return SalesInfoCard(
      child: Row(
        children: [
          _SummaryTile(
            icon: Icons.sell_outlined,
            label: 'Price List',
            value: priceList.isEmpty ? '-' : priceList,
            color: _priceTeal,
          ),
          const SizedBox(width: 8),
          _SummaryTile(
            icon: Icons.group_work_rounded,
            label: 'Group',
            value: customerGroup.isEmpty ? '-' : customerGroup,
            color: _priceGreen,
          ),
          const SizedBox(width: 8),
          _SummaryTile(
            icon: Icons.inventory_2_outlined,
            label: 'Item',
            value: itemCount.toString(),
            footer: currency,
            color: _priceBlue,
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String footer;
  final Color color;

  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    this.footer = '',
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              footer.isEmpty ? label : '$label - $footer',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerItemPriceCard extends StatelessWidget {
  final CustomerItemPrice price;
  final String priceLabel;

  const _CustomerItemPriceCard({required this.price, required this.priceLabel});

  @override
  Widget build(BuildContext context) {
    return SalesInfoCard(
      accent: _priceTeal,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _priceTeal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: _priceTeal,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  price.itemName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  price.itemCode,
                  style: const TextStyle(
                    color: AppColors.slate,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (price.itemGroup.isNotEmpty || price.uom.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (price.itemGroup.isNotEmpty)
                        _MiniChip(text: price.itemGroup),
                      if (price.uom.isNotEmpty) _MiniChip(text: price.uom),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                priceLabel,
                style: const TextStyle(
                  color: _priceTeal,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                price.priceList,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.slate,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String text;

  const _MiniChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.slate,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PriceListLoading extends StatelessWidget {
  const _PriceListLoading();

  @override
  Widget build(BuildContext context) {
    return const SalesInfoCard(
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(
            'Memuat harga item customer...',
            style: TextStyle(
              color: AppColors.slate,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerSelectSheet extends StatefulWidget {
  final List<SalesCustomerOption> customers;
  final SalesCustomerOption? selected;

  const _CustomerSelectSheet({required this.customers, required this.selected});

  @override
  State<_CustomerSelectSheet> createState() => _CustomerSelectSheetState();
}

class _CustomerSelectSheetState extends State<_CustomerSelectSheet> {
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  List<SalesCustomerOption> _filtered() {
    final query = _queryController.text.trim().toLowerCase();
    final source = widget.customers;
    if (query.isEmpty) return source.take(40).toList();
    return source
        .where((row) {
          return row.id.toLowerCase().contains(query) ||
              row.name.toLowerCase().contains(query);
        })
        .take(80)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      maxChildSize: 0.95,
      minChildSize: 0.55,
      builder: (context, scrollController) {
        return TmsxResponsiveBody(
          maxWidth: 640,
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              TmsxResponsive.horizontalPadding(context),
              14,
              TmsxResponsive.horizontalPadding(context),
              MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const SalesHeroCard(
                  title: 'Pilih Customer',
                  subtitle: 'Cari berdasarkan nama atau kode customer.',
                  icon: Icons.storefront_rounded,
                  accent: _priceTeal,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _queryController,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Cari customer',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: rows.isEmpty
                      ? const ErpEmptyState(
                          icon: Icons.storefront_rounded,
                          title: 'Customer tidak ditemukan',
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final customer = rows[index];
                            final selected = widget.selected?.id == customer.id;
                            return Material(
                              color: selected
                                  ? _priceTeal.withValues(alpha: 0.10)
                                  : AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(18),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => Navigator.pop(context, customer),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: _priceTeal.withValues(
                                            alpha: selected ? 0.16 : 0.10,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Icon(
                                          selected
                                              ? Icons.check_rounded
                                              : Icons.storefront_rounded,
                                          color: _priceTeal,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              customer.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppColors.navy,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              customer.id,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppColors.slate,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: AppColors.slate,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
