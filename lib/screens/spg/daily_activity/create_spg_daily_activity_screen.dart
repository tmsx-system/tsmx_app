import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../models/spg_workspace.dart';
import '../../../state/spg/spg_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_error_box.dart';
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
      final employees = state.mobileAccess.canSelectAnyEmployee
          ? await state.fetchEmployeeOptions()
          : const <Map<String, dynamic>>[];
      final customers = state.mobileAccess.canSelectAnyEmployee
          ? const <SpgCustomerOption>[]
          : await state.fetchScheduledSpgCustomers();
      if (!mounted) return;
      setState(() {
        _customers = customers;
        _employees = employees;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
      final customers = await context
          .read<SpgState>()
          .fetchScheduledSpgCustomers(employee: employee);
      if (!mounted) return;
      setState(() => _customers = customers);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    final canSelectEmployee = context
        .read<SpgState>()
        .mobileAccess
        .canSelectAnyEmployee;
    if (canSelectEmployee && _employee == null) {
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
        notes: _notes.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
          if (context.watch<SpgState>().mobileAccess.canSelectAnyEmployee) ...[
            _employeeSearchField(),
            const SizedBox(height: 12),
          ],
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

  Widget _customerSearchField() {
    final needsEmployee =
        context.read<SpgState>().mobileAccess.canSelectAnyEmployee &&
        _employee == null;
    return Autocomplete<SpgCustomerOption>(
      displayStringForOption: _customerLabel,
      optionsMaxHeight: 280,
      optionsBuilder: (value) {
        if (needsEmployee) return const Iterable<SpgCustomerOption>.empty();
        final query = value.text.toLowerCase().trim();
        if (query.isEmpty) return _customers;
        return _customers.where((customer) {
          return customer.id.toLowerCase().contains(query) ||
              customer.name.toLowerCase().contains(query) ||
              customer.address.toLowerCase().contains(query);
        });
      },
      onSelected: (value) => setState(() => _customer = value),
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        final selectedLabel = _customer == null
            ? ''
            : _customerLabel(_customer!);
        if (selectedLabel.isNotEmpty && controller.text.isEmpty) {
          controller.text = selectedLabel;
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: !_saving && !_loading && !needsEmployee,
          decoration: InputDecoration(
            labelText: 'Customer',
            hintText: needsEmployee
                ? 'Pilih employee dulu'
                : 'Cari customer dari schedule',
            prefixIcon: const Icon(Icons.storefront_outlined),
            suffixIcon: const Icon(Icons.search_rounded),
          ),
          onChanged: (text) {
            if (_customer != null && text != selectedLabel) {
              setState(() => _customer = null);
            }
          },
        );
      },
    );
  }

  Widget _employeeSearchField() {
    return Autocomplete<Map<String, dynamic>>(
      displayStringForOption: _employeeLabel,
      optionsMaxHeight: 280,
      optionsBuilder: (value) {
        final query = value.text.toLowerCase().trim();
        if (query.isEmpty) return _employees;
        return _employees.where((employee) {
          final name = employee['name']?.toString().toLowerCase() ?? '';
          final employeeName =
              employee['employee_name']?.toString().toLowerCase() ?? '';
          final userId = employee['user_id']?.toString().toLowerCase() ?? '';
          return name.contains(query) ||
              employeeName.contains(query) ||
              userId.contains(query);
        });
      },
      onSelected: (value) {
        setState(() => _employee = value);
        _loadScheduledCustomersForEmployee();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        final selectedLabel = _employee == null
            ? ''
            : _employeeLabel(_employee!);
        if (selectedLabel.isNotEmpty && controller.text.isEmpty) {
          controller.text = selectedLabel;
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: !_saving && !_loading,
          decoration: const InputDecoration(
            labelText: 'Employee',
            hintText: 'Cari employee',
            prefixIcon: Icon(Icons.badge_outlined),
            suffixIcon: Icon(Icons.search_rounded),
          ),
          onChanged: (text) {
            if (_employee != null && text != selectedLabel) {
              setState(() {
                _employee = null;
                _customer = null;
                _customers = const [];
              });
            }
          },
        );
      },
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
