import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../models/spg_workspace.dart';
import '../../../state/spg/spg_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_error_box.dart';
import '../../../widgets/erp/erp_item_autocomplete_field.dart';
import '../../../utils/erp_error_message.dart';
import '../../../widgets/responsive/responsive_layout.dart';

class CreateSpgDailyActivityScreen extends StatefulWidget {
  const CreateSpgDailyActivityScreen({super.key});

  @override
  State<CreateSpgDailyActivityScreen> createState() =>
      _CreateSpgDailyActivityScreenState();
}

class _CreateSpgDailyActivityScreenState
    extends State<CreateSpgDailyActivityScreen> {
  final _picker = ImagePicker();
  final _notes = TextEditingController();
  List<SpgCustomerOption> _customers = const [];
  List<Map<String, dynamic>> _employees = const [];
  List<XFile> _photos = const [];
  SpgCustomerOption? _customer;
  Map<String, dynamic>? _employee;
  DateTime _activityDate = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<SpgState>();
      final selectsEmployee = !state.mobileAccess.isSpg;
      final employees = selectsEmployee
          ? await state.fetchSpgEmployeeChoices(onDate: _activityDate)
          : const <Map<String, dynamic>>[];
      final customers = selectsEmployee
          ? const <SpgCustomerOption>[]
          : await _customersFor(state, '');
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _employees = employees;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadScheduledCustomersForEmployee() async {
    final employee = _employee?['name']?.toString().trim() ?? '';
    if (employee.isEmpty) {
      setState(() {
        _customers = const [];
        _customer = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _customer = null;
    });
    try {
      final customers = await _customersFor(
        context.read<SpgState>(),
        '',
        employee: employee,
      );
      if (!mounted) return;
      setState(() => _customers = customers);
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<SpgCustomerOption>> _customersFor(
    SpgState state,
    String query, {
    String? employee,
  }) async {
    final access = state.mobileAccess;
    final assigned = await state.fetchScheduledSpgCustomers(
      query: query,
      employee: employee,
      onDate: _activityDate,
    );
    if (access.isSpg || access.isSalesUser || assigned.isNotEmpty) {
      return assigned;
    }
    return state.fetchSpgCustomers(query: query);
  }

  Future<void> _pickActivityDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _activityDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _activityDate = DateTime(picked.year, picked.month, picked.day);
    });
    final state = context.read<SpgState>();
    if (!state.mobileAccess.isSpg && _employee == null) return;
    final customers = await _customersFor(
      state,
      '',
      employee: _employee?['name']?.toString(),
    );
    if (!mounted) return;
    setState(() {
      _customers = customers;
      if (_customer != null &&
          !customers.any((option) => option.id == _customer!.id)) {
        _customer = null;
      }
    });
  }

  String _activityDateLabel() {
    final day = _activityDate.day.toString().padLeft(2, '0');
    final month = _activityDate.month.toString().padLeft(2, '0');
    return '$day-$month-${_activityDate.year}';
  }

  Future<void> _pickFromCamera() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 72,
      maxWidth: 1280,
    );
    if (image == null || !mounted) return;
    setState(() => _photos = [..._photos, image]);
  }

  Future<void> _pickMultiple() async {
    final images = await _picker.pickMultiImage(
      imageQuality: 72,
      maxWidth: 1280,
    );
    if (images.isEmpty || !mounted) return;
    setState(() => _photos = [..._photos, ...images]);
  }

  Future<void> _save() async {
    final selectsEmployee = !context.read<SpgState>().mobileAccess.isSpg;
    if (selectsEmployee && _employee == null) {
      setState(() => _error = 'Employee wajib dipilih.');
      return;
    }
    if (_customer == null) {
      setState(() => _error = 'Customer wajib dipilih.');
      return;
    }
    if (_photos.isEmpty) {
      setState(() => _error = 'Minimal 1 foto aktivitas wajib diambil.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<SpgState>().createSpgDailyActivity(
        customer: _customer!.id,
        photoPaths: _photos.map((photo) => photo.path).toList(),
        employee: _employee?['name']?.toString(),
        activityDate: _activityDate,
        notes: _notes.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = captureErpError(context, error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Buat Report Foto'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.navy,
      ),
      body: TmsxResponsiveBody(
        child: ListView(
          padding: TmsxResponsive.pagePadding(context, top: 12, bottom: 100),
          children: [
            _headerCard(),
            const SizedBox(height: 12),
            _formCard(),
            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErpErrorBox(message: _error!),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.fromLTRB(
          TmsxResponsive.horizontalPadding(context),
          8,
          TmsxResponsive.horizontalPadding(context),
          16,
        ),
        child: TmsxResponsiveBody(
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_rounded),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_saving ? 'Menyimpan...' : 'Kirim Report Foto'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.photo_camera_outlined,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SPG Daily Activity',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Upload beberapa foto aktivitas customer.',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!context.watch<SpgState>().mobileAccess.isSpg) ...[
            _employeeSearchField(),
            const SizedBox(height: 12),
          ],
          _activityDateField(),
          const SizedBox(height: 12),
          _customerSearchField(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickFromCamera,
                  icon: const Icon(Icons.photo_camera_rounded),
                  label: const Text('Kamera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickMultiple,
                  icon: const Icon(Icons.collections_rounded),
                  label: const Text('Galeri'),
                ),
              ),
            ],
          ),
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            _photoPreviewGrid(),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 5,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Notes',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPreviewGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, index) {
        final photo = _photos[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(photo.path), fit: BoxFit.cover),
              Positioned(
                right: 4,
                top: 4,
                child: Material(
                  color: AppColors.navy.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    onTap: () => setState(() {
                      final next = [..._photos]..removeAt(index);
                      _photos = next;
                    }),
                    borderRadius: BorderRadius.circular(999),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        color: AppColors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _activityDateField() {
    return InkWell(
      onTap: _saving ? null : _pickActivityDate,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: _pickerDecoration(
          'Activity Date',
          hint: 'Tanggal activity',
          icon: Icons.calendar_today_rounded,
        ),
        child: Text(
          _activityDateLabel(),
          style: const TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _customerSearchField() {
    final needsEmployee =
        !context.read<SpgState>().mobileAccess.isSpg && _employee == null;
    return IgnorePointer(
      ignoring: _saving,
      child: ErpItemAutocompleteField(
        label: 'Customer',
        selectedId: _customer?.id,
        options: [for (final customer in _customers) _customerOption(customer)],
        onSearch: needsEmployee ? null : _searchCustomers,
        onSelected: (id) {
          SpgCustomerOption? selected;
          if (id != null && id.isNotEmpty) {
            for (final customer in _customers) {
              if (customer.id == id) {
                selected = customer;
                break;
              }
            }
            selected ??= SpgCustomerOption(id: id, name: id);
          }
          setState(() => _customer = selected);
        },
        decoration: _pickerDecoration(
          'Customer',
          hint: needsEmployee
              ? 'Pilih employee dulu'
              : 'Pilih atau search customer',
          icon: Icons.storefront_outlined,
        ),
      ),
    );
  }

  Widget _employeeSearchField() {
    return IgnorePointer(
      ignoring: _saving,
      child: ErpItemAutocompleteField(
        label: 'Employee',
        selectedId: _employee?['name']?.toString(),
        options: [for (final employee in _employees) _employeeOption(employee)],
        onSearch: _searchEmployees,
        onSelected: (id) {
          Map<String, dynamic>? selected;
          if (id != null && id.isNotEmpty) {
            for (final employee in _employees) {
              if (employee['name']?.toString() == id) {
                selected = employee;
                break;
              }
            }
            selected ??= {'name': id, 'employee_name': id};
          }
          setState(() {
            _employee = selected;
            _customer = null;
            _customers = const [];
          });
          if (selected != null) _loadScheduledCustomersForEmployee();
        },
        decoration: _pickerDecoration(
          'Employee',
          hint: 'Pilih atau search employee',
          icon: Icons.badge_outlined,
        ),
      ),
    );
  }

  ErpItemOption _customerOption(SpgCustomerOption customer) {
    return ErpItemOption(id: customer.id, label: _customerLabel(customer));
  }

  Future<List<ErpItemOption>> _searchCustomers(String query) async {
    final state = context.read<SpgState>();
    final resolved = await _customersFor(
      state,
      query,
      employee: _employee?['name']?.toString(),
    );
    final merged = <String, SpgCustomerOption>{
      for (final customer in _customers) customer.id: customer,
      for (final customer in resolved) customer.id: customer,
    };
    _customers = merged.values.toList();
    return [for (final customer in resolved) _customerOption(customer)];
  }

  ErpItemOption _employeeOption(Map<String, dynamic> employee) {
    return ErpItemOption(
      id: employee['name']?.toString() ?? '',
      label: _employeeLabel(employee),
    );
  }

  Future<List<ErpItemOption>> _searchEmployees(String query) async {
    final rows = await context.read<SpgState>().fetchSpgEmployeeChoices(
      query: query,
      onDate: _activityDate,
    );
    final merged = <String, Map<String, dynamic>>{
      for (final employee in _employees)
        if ((employee['name']?.toString() ?? '').isNotEmpty)
          employee['name'].toString(): employee,
      for (final employee in rows)
        if ((employee['name']?.toString() ?? '').isNotEmpty)
          employee['name'].toString(): employee,
    };
    _employees = merged.values.toList();
    return [for (final employee in rows) _employeeOption(employee)];
  }

  InputDecoration _pickerDecoration(
    String label, {
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.16),
        ),
      ),
    );
  }

  String _customerLabel(SpgCustomerOption customer) {
    if (customer.id.trim().isEmpty) return customer.name;
    return '${customer.name} - ${customer.id}';
  }

  String _employeeLabel(Map<String, dynamic> employee) {
    final name = employee['name']?.toString() ?? '';
    final employeeName = employee['employee_name']?.toString() ?? '';
    if (employeeName.trim().isEmpty) return name;
    if (name.trim().isEmpty) return employeeName;
    return '$employeeName - $name';
  }
}
