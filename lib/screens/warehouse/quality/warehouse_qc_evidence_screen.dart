import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/quality_inspection_record.dart';
import '../../../state/warehouse/warehouse_stock_state.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/erp/erp_empty_state.dart';
import '../shared/warehouse_widgets.dart';

class WarehouseQcEvidenceScreen extends StatefulWidget {
  const WarehouseQcEvidenceScreen({super.key});

  @override
  State<WarehouseQcEvidenceScreen> createState() =>
      _WarehouseQcEvidenceScreenState();
}

class _WarehouseQcEvidenceScreenState extends State<WarehouseQcEvidenceScreen> {
  final _picker = ImagePicker();
  final _search = TextEditingController();
  List<QualityInspectionRecord> _rows = const [];
  int _periodDays = 30;
  String? _uploadingName;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _rows = await context.read<WarehouseStockState>().fetchQualityInspections(
        periodDays: _periodDays,
      );
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _choosePhoto(QualityInspectionRecord inspection) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tambah evidence untuk ${inspection.name}',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Ambil foto dengan kamera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Pilih foto dari galeri'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    final photo = await _picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (photo == null || !mounted) return;
    await _upload(inspection, photo);
  }

  Future<void> _upload(QualityInspectionRecord inspection, XFile photo) async {
    setState(() {
      _uploadingName = inspection.name;
      _error = null;
    });
    try {
      await context.read<WarehouseStockState>().uploadAttachment(
        doctype: 'Quality Inspection',
        documentName: inspection.name,
        filePath: photo.path,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Foto evidence terpasang ke ${inspection.name}.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _uploadingName = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final rows = _rows.where((row) {
      return query.isEmpty ||
          row.name.toLowerCase().contains(query) ||
          row.itemCode.toLowerCase().contains(query) ||
          row.itemName.toLowerCase().contains(query) ||
          row.referenceName.toLowerCase().contains(query);
    }).toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Foto QC Evidence',
          style: TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: warehousePagePaddingOf(context),
          children: [
            const WarehouseSectionHeader(
              title: 'Bukti Foto QC',
              subtitle: 'Lampirkan foto langsung ke Quality Inspection',
              icon: Icons.camera_alt_outlined,
            ),
            warehouseSectionGap,
            const WarehouseInfoPanel(
              icon: Icons.info_outline_rounded,
              message:
                  'Gunakan foto yang jelas dan fokus pada kondisi barang atau hasil pengujian.',
            ),
            warehouseSectionGap,
            WarehouseSearchField(
              controller: _search,
              hintText: 'Cari inspeksi, item, atau referensi',
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _periodDays,
              decoration: const InputDecoration(
                labelText: 'Periode inspeksi',
                prefixIcon: Icon(Icons.date_range_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 30, child: Text('30 hari terakhir')),
                DropdownMenuItem(value: 90, child: Text('90 hari terakhir')),
              ],
              onChanged: (value) {
                if (value == null || value == _periodDays) return;
                setState(() => _periodDays = value);
                _load();
              },
            ),
            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              WarehouseInfoPanel(
                icon: Icons.error_outline_rounded,
                color: AppColors.danger,
                message: _error!,
              ),
            ],
            warehouseSectionGap,
            WarehouseSectionHeader(
              title: 'Pilih Quality Inspection',
              subtitle: '${rows.length} inspeksi ditampilkan',
              icon: Icons.fact_check_outlined,
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty && !_loading)
              const ErpEmptyState(
                title: 'Quality Inspection tidak ditemukan',
                message: 'Ubah periode/pencarian atau tarik untuk refresh.',
              )
            else
              ...rows.map(_inspectionCard),
          ],
        ),
      ),
    );
  }

  Widget _inspectionCard(QualityInspectionRecord row) {
    final uploading = _uploadingName == row.name;
    final color = row.status.toLowerCase() == 'rejected'
        ? AppColors.danger
        : row.status.toLowerCase() == 'accepted'
        ? AppColors.success
        : AppColors.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              foregroundColor: color,
              child: const Icon(Icons.fact_check_outlined),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.itemName.isEmpty ? row.itemCode : row.itemName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    [
                      row.name,
                      if (row.inspectionType.isNotEmpty) row.inspectionType,
                      if (row.reportDate != null)
                        DateFormat('dd MMM yyyy').format(row.reportDate!),
                    ].join(' | '),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Tambah foto evidence',
              onPressed: uploading ? null : () => _choosePhoto(row),
              icon: uploading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_a_photo_outlined),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
