import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/logistics/logistics_overview_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/erp_error_message.dart';
import '../../utils/erp_format.dart';
import '../../utils/frappe_status.dart';
import 'logistics_widgets.dart';

class DeliveryTripDetailScreen extends StatefulWidget {
  final String tripName;

  const DeliveryTripDetailScreen({super.key, required this.tripName});

  @override
  State<DeliveryTripDetailScreen> createState() =>
      _DeliveryTripDetailScreenState();
}

class _DeliveryTripDetailScreenState extends State<DeliveryTripDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _doc = const {};
  List<_TripField> _parentFields = const [];
  _TripField? _stopsField;
  List<_TripField> _stopFields = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<LogisticsOverviewState>();
      final doc = await state.fetchDeliveryTrip(widget.tripName);
      final parentMeta = await state.fetchDoctypeFields('Delivery Trip');
      final parentFields = _visibleFields(parentMeta);
      final stopsField = _stopsTable(parentFields, doc);
      var stopFields = const <_TripField>[];
      final childDoctype = stopsField?.options.trim() ?? '';
      if (childDoctype.isNotEmpty) {
        stopFields = _visibleFields(await state.fetchDoctypeFields(childDoctype));
      }
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _parentFields = parentFields;
        _stopsField = stopsField;
        _stopFields = stopFields;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = captureErpError(context, error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusText();
    final stops = _stops();
    final departure = _valueOf(_fieldNamed('departure_time'));
    final distance = _valueOf(_distanceField());
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.primary,
        title: const Text(
          'Detail Delivery Trip',
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
          padding: logisticsPagePaddingOf(context),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              LogisticsInfoPanel(
                icon: Icons.error_outline_rounded,
                color: AppColors.danger,
                message: _error!,
              )
            else ...[
              _header(
                status: status,
                stopCount: stops.length,
                departure: departure,
                distance: distance,
              ),
              const SizedBox(height: 14),
              _section(
                title: 'Delivery Details',
                icon: Icons.route_outlined,
                child: Column(
                  children: [
                    for (final row in _detailRows())
                      _infoRow(row.label, row.value),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _section(
                title: 'Delivery Stop',
                icon: Icons.place_outlined,
                trailing: Text(
                  '${stops.length}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                child: stops.isEmpty
                    ? const Text(
                        'Belum ada Delivery Stop.',
                        style: TextStyle(
                          color: AppColors.slate,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < stops.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            _stopCard(stops[i], i + 1),
                          ],
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header({
    required String status,
    required int stopCount,
    required String departure,
    required String distance,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.route_outlined, color: AppColors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.tripName,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (status.isNotEmpty)
                LogisticsStatusChip(label: status, color: AppColors.white),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _metric('Stop', '$stopCount')),
              const SizedBox(width: 8),
              Expanded(child: _metric('Berangkat', departure)),
              const SizedBox(width: 8),
              Expanded(child: _metric('Jarak', distance)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFE3F2EA),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '-' : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
  }) {
    return LogisticsModernCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.slate,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stopCard(Map<String, dynamic> stop, int index) {
    final rows = _stopRows(stop);
    final title = rows.isEmpty ? 'Stop $index' : rows.first.value;
    final rest = rows.length <= 1 ? const <_LabeledValue>[] : rows.sublist(1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$index. ${title.isEmpty ? '-' : title}',
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (rest.isNotEmpty) const SizedBox(height: 8),
          for (final row in rest) _infoRow(row.label, row.value),
        ],
      ),
    );
  }

  List<_LabeledValue> _detailRows() {
    final ordered = <_TripField?>[
      _fieldNamed('company'),
      _fieldByLabel('pic') ??
          _fieldNamed('pic') ??
          _fieldNamed('custom_pic') ??
          _picFromKeys(),
      _fieldNamed('driver'),
      _fieldNamed('driver_name'),
      _fieldNamed('vehicle'),
      _fieldNamed('departure_time'),
      _distanceField(),
      _emailField(),
      _fieldNamed('status'),
      _fieldNamed('remarks') ?? _fieldByLabel('remarks'),
    ];
    final used = <String>{};
    final rows = <_LabeledValue>[];
    for (final field in ordered) {
      if (field == null || !used.add(field.fieldname)) continue;
      rows.add(_LabeledValue(field.label, _valueOf(field)));
    }
    for (final field in _parentFields) {
      if (!used.add(field.fieldname)) continue;
      if (field.fieldtype == 'Table') continue;
      if (_hiddenParentFields.contains(field.fieldname)) continue;
      final raw = _doc[field.fieldname];
      if (raw == null || raw.toString().trim().isEmpty) continue;
      rows.add(_LabeledValue(field.label, _formatValue(field, raw)));
    }
    if (rows.isEmpty) {
      rows.add(_LabeledValue('Company', _text(_doc['company'])));
      rows.add(_LabeledValue('Status', _statusText()));
    }
    return rows;
  }

  List<_LabeledValue> _stopRows(Map<String, dynamic> stop) {
    final preferred = <_TripField?>[
      _stopField('customer'),
      _stopByLabel('address name') ??
          _stopField('address') ??
          _stopField('address_name') ??
          _stopField('customer_address'),
      _stopField('locked'),
      _stopField('delivery_note'),
      _stopField('grand_total'),
    ];
    final used = <String>{};
    final rows = <_LabeledValue>[];
    for (final field in preferred) {
      if (field == null || !used.add(field.fieldname)) continue;
      rows.add(_LabeledValue(field.label, _formatValue(field, stop[field.fieldname])));
    }
    for (final field in _stopFields) {
      if (!used.add(field.fieldname)) continue;
      final raw = stop[field.fieldname];
      if (raw == null || raw.toString().trim().isEmpty || raw == 0) continue;
      rows.add(_LabeledValue(field.label, _formatValue(field, raw)));
    }
    if (rows.isEmpty) {
      rows.add(_LabeledValue('Customer', _text(stop['customer'])));
      rows.add(_LabeledValue('Address Name', _text(stop['address'])));
      rows.add(_LabeledValue('Delivery Note', _text(stop['delivery_note'])));
      rows.add(_LabeledValue('Grand Total', _money(stop['grand_total'])));
    }
    return rows;
  }

  List<Map<String, dynamic>> _stops() {
    final key = _stopsField?.fieldname ?? 'delivery_stops';
    final raw = _doc[key];
    if (raw is! List) return const [];
    return [
      for (final row in raw)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  String _statusText() {
    final status = _doc['status']?.toString().trim() ?? '';
    final docstatus = int.tryParse(_doc['docstatus']?.toString() ?? '');
    if (status.isEmpty && docstatus == null) return '';
    return normalizeStatusText(status.isEmpty ? null : status, docstatus: docstatus);
  }

  _TripField? _fieldNamed(String fieldname) {
    for (final field in _parentFields) {
      if (field.fieldname == fieldname) return field;
    }
    if (_doc.containsKey(fieldname)) {
      return _TripField(
        fieldname: fieldname,
        label: _fallbackLabel(fieldname),
        fieldtype: _guessType(fieldname),
        options: '',
      );
    }
    return null;
  }

  _TripField? _fieldByLabel(String label) {
    final target = label.trim().toLowerCase();
    for (final field in _parentFields) {
      if (field.label.trim().toLowerCase() == target) return field;
    }
    return null;
  }

  _TripField? _distanceField() {
    for (final field in _parentFields) {
      final label = field.label.toLowerCase();
      if (field.fieldname == 'total_distance' ||
          label.contains('estimated distance') ||
          label == 'total distance') {
        return field;
      }
    }
    return _fieldNamed('total_distance');
  }

  _TripField? _emailField() {
    for (final field in _parentFields) {
      final label = field.label.toLowerCase();
      final name = field.fieldname.toLowerCase();
      if ((label.contains('email') && label.contains('notification')) ||
          name.contains('email_notification')) {
        return field;
      }
    }
    return null;
  }

  _TripField? _picFromKeys() {
    for (final key in _doc.keys) {
      if (key.toLowerCase().contains('pic')) {
        return _TripField(
          fieldname: key,
          label: 'PIC',
          fieldtype: 'Data',
          options: '',
        );
      }
    }
    return null;
  }

  _TripField? _stopField(String fieldname) {
    for (final field in _stopFields) {
      if (field.fieldname == fieldname) return field;
    }
    if (_stopFields.isNotEmpty) return null;
    return _TripField(
      fieldname: fieldname,
      label: _fallbackLabel(fieldname),
      fieldtype: _guessType(fieldname),
      options: '',
    );
  }

  _TripField? _stopByLabel(String label) {
    final target = label.trim().toLowerCase();
    for (final field in _stopFields) {
      if (field.label.trim().toLowerCase() == target) return field;
    }
    return null;
  }

  String _valueOf(_TripField? field) {
    if (field == null) return '-';
    return _formatValue(field, _doc[field.fieldname]);
  }

  String _formatValue(_TripField field, dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) return '-';
    final type = field.fieldtype;
    if (type == 'Check') {
      final text = raw.toString().trim();
      return text == '1' || text.toLowerCase() == 'true' ? 'Ya' : 'Tidak';
    }
    if (type == 'Currency' || field.fieldname == 'grand_total') {
      return _money(raw);
    }
    if (type == 'Datetime' || type == 'Date') return _date(raw.toString(), type);
    if (type == 'Float' && field.fieldname.contains('distance')) {
      return raw.toString();
    }
    return raw.toString().trim();
  }

  String _date(String raw, String type) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    if (type == 'Date') return DateFormat('dd-MM-yyyy').format(local);
    return DateFormat('dd-MM-yyyy HH:mm:ss').format(local);
  }

  String _money(dynamic raw) {
    final number = double.tryParse(raw?.toString() ?? '');
    if (number == null) return '-';
    final negative = number < 0;
    final parts = number.abs().toStringAsFixed(2).split('.');
    final whole = formatErpCurrency(double.parse(parts[0]));
    return '${negative ? '-' : ''}Rp $whole,${parts[1]}';
  }

  String _text(dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  String _fallbackLabel(String fieldname) {
    const labels = {
      'company': 'Company',
      'pic': 'PIC',
      'custom_pic': 'PIC',
      'driver': 'Driver',
      'driver_name': 'Driver Name',
      'vehicle': 'Vehicle',
      'departure_time': 'Departure Time',
      'total_distance': 'Total Estimated Distance',
      'status': 'Status',
      'remarks': 'Remarks',
      'customer': 'Customer',
      'address': 'Address Name',
      'address_name': 'Address Name',
      'customer_address': 'Address Name',
      'locked': 'Locked',
      'delivery_note': 'Delivery Note',
      'grand_total': 'Grand Total',
    };
    return labels[fieldname] ?? fieldname;
  }

  String _guessType(String fieldname) {
    if (fieldname == 'locked') return 'Check';
    if (fieldname == 'departure_time') return 'Datetime';
    if (fieldname == 'grand_total') return 'Currency';
    if (fieldname == 'total_distance') return 'Float';
    return 'Data';
  }
}

class _LabeledValue {
  final String label;
  final String value;

  const _LabeledValue(this.label, this.value);
}

class _TripField {
  final String fieldname;
  final String label;
  final String fieldtype;
  final String options;

  const _TripField({
    required this.fieldname,
    required this.label,
    required this.fieldtype,
    required this.options,
  });
}

const _layoutTypes = {
  'Section Break',
  'Column Break',
  'Tab Break',
  'HTML',
  'Button',
  'Fold',
  'Heading',
};

const _hiddenParentFields = {
  'naming_series',
  'amended_from',
  'letter_head',
};

List<_TripField> _visibleFields(List<Map<String, dynamic>> rows) {
  final fields = <_TripField>[];
  final seen = <String>{};
  for (final row in rows) {
    final fieldname = row['fieldname']?.toString().trim() ?? '';
    final fieldtype = row['fieldtype']?.toString().trim() ?? '';
    if (fieldname.isEmpty || !seen.add(fieldname)) continue;
    if (_layoutTypes.contains(fieldtype)) continue;
    final label = row['label']?.toString().trim() ?? '';
    fields.add(
      _TripField(
        fieldname: fieldname,
        label: label.isEmpty ? fieldname : label,
        fieldtype: fieldtype,
        options: row['options']?.toString().trim() ?? '',
      ),
    );
  }
  return fields;
}

_TripField? _stopsTable(List<_TripField> fields, Map<String, dynamic> doc) {
  for (final field in fields) {
    if (field.fieldtype != 'Table') continue;
    final label = field.label.toLowerCase();
    if (field.fieldname == 'delivery_stops' ||
        field.options == 'Delivery Stop' ||
        label.contains('delivery stop')) {
      return field;
    }
  }
  if (doc['delivery_stops'] is List) {
    return const _TripField(
      fieldname: 'delivery_stops',
      label: 'Delivery Stop',
      fieldtype: 'Table',
      options: 'Delivery Stop',
    );
  }
  return null;
}
