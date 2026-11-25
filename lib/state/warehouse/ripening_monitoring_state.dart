import '../../models/ripening_monitoring.dart';
import '../../services/frappe_service.dart';
import '../app_state.dart';

class RipeningMonitoringState {
  RipeningMonitoringState(this.appState);

  final AppState appState;

  static const doctype = 'Ripening Monitoring';

  /// SKU yang sudah tampil sebagai baris awal di form ERP.
  static const defaultItemCodes = [
    'SPF-JKT-029',
    'SPF-JKT-038',
    'SPF-JKT-023',
    'SPF-JKT-052',
    'SPF-JKT-057',
    'SPF-JKT-053',
  ];

  FrappeService get _frappe => appState.frappeService;
  static RipeningFieldMap? _cachedMeta;

  Future<bool> canCreate() => appState.canCreateDoctype(doctype);
  Future<bool> canWrite() => appState.canWriteDoctype(doctype);
  Future<bool> canSubmit() => appState.canSubmitDoctype(doctype);

  Future<RipeningFieldMap> resolveMeta({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedMeta != null) return _cachedMeta!;
    await _frappe.ensureLoggedIn();
    final forms = await _formFields(doctype);
    final parent = forms[doctype] ?? const <Map<String, dynamic>>[];
    var meta = const RipeningFieldMap();
    String? detailTable;
    String? detailDoctype;
    String? hasilTable;
    String? hasilDoctype;
    for (final row in parent) {
      final name = _text(row['fieldname']);
      final type = _text(row['fieldtype']);
      final label = '${row['label'] ?? ''} $name'.toLowerCase();
      final options = _text(row['options']);
      if (name.isEmpty || _isLayout(type)) continue;
      if (type == 'Table') {
        final isDetail = name == 'sampling_details' ||
            (label.contains('detail') &&
                (label.contains('pengamatan') || label.contains('sampling')));
        final isHasil = name == 'sampling_results' ||
            label.contains('hasil') ||
            label.contains('result');
        if (isDetail) {
          detailTable = name;
          detailDoctype = options;
        } else if (isHasil) {
          hasilTable = name;
          hasilDoctype = options;
        }
        continue;
      }
      meta = _applyParentField(meta, name, type, label);
    }
    meta = RipeningFieldMap(
      seriesField: meta.seriesField,
      companyField: meta.companyField,
      gassingField: meta.gassingField,
      samplingField: meta.samplingField,
      detailTable: detailTable ?? meta.detailTable,
      detailDoctype: (detailDoctype ?? '').isEmpty
          ? meta.detailDoctype
          : detailDoctype!,
      hasilTable: hasilTable ?? meta.hasilTable,
      hasilDoctype: (hasilDoctype ?? '').isEmpty
          ? meta.hasilDoctype
          : hasilDoctype!,
      totalSampelField: meta.totalSampelField,
      totalNormalField: meta.totalNormalField,
      totalBlontengField: meta.totalBlontengField,
      persenNormalField: meta.persenNormalField,
      persenBlontengField: meta.persenBlontengField,
    );
    final detailFields =
        forms[meta.detailDoctype] ?? await _schemaFields(meta.detailDoctype);
    meta = _applyChildFields(meta, detailFields, hasil: false);
    if (meta.hasilDoctype.isNotEmpty) {
      final hasilFields =
          forms[meta.hasilDoctype] ?? await _schemaFields(meta.hasilDoctype);
      meta = _applyChildFields(meta, hasilFields, hasil: true);
    }
    _cachedMeta = meta;
    return meta;
  }

  Future<List<RipeningSummary>> fetchList({
    String? company,
    String? query,
  }) async {
    await _frappe.ensureLoggedIn();
    final selectedCompany = (company ?? '').trim();
    final text = (query ?? '').trim();
    final filters = <List<dynamic>>[
      if (selectedCompany.isNotEmpty) ['company', '=', selectedCompany],
      if (text.isNotEmpty) ['name', 'like', '%$text%'],
    ];
    List<Map<String, dynamic>> rows;
    try {
      rows = await _frappe.fetchResource(
        doctype,
        fields: const [
          'name',
          'company',
          'gassing_date',
          'sampling_date',
          'docstatus',
        ],
        filters: filters,
        orderBy: 'modified desc',
        limit: 30,
      );
    } catch (_) {
      rows = await _frappe.fetchResource(
        doctype,
        fields: const ['name', 'company', 'docstatus'],
        filters: filters,
        orderBy: 'modified desc',
        limit: 30,
      );
    }
    return [
      for (final row in rows)
        if (_text(row['name']).isNotEmpty)
          RipeningSummary(
            name: _text(row['name']),
            company: _text(row['company']),
            tanggalGassing: _text(row['gassing_date']),
            tanggalSampling: _text(row['sampling_date']),
            docstatus: int.tryParse('${row['docstatus']}') ?? 0,
          ),
    ];
  }

  Future<Map<String, dynamic>> fetchDetail(String name) async {
    await _frappe.ensureLoggedIn();
    return _frappe.fetchDocument(doctype, name.trim());
  }

  Future<List<String>> fetchCompanies() async {
    await _frappe.ensureLoggedIn();
    final rows = await _frappe.fetchResource(
      'Company',
      fields: const ['name'],
      orderBy: 'name asc',
      limit: 100,
    );
    return [
      for (final row in rows)
        if (_text(row['name']).isNotEmpty) _text(row['name']),
    ];
  }

  Future<List<String>> fetchNamingSeries() {
    return appState.fetchNamingSeries(doctype);
  }

  Future<List<RipeningLine>> defaultLines() async {
    await _frappe.ensureLoggedIn();
    final rows = await _frappe.fetchResource(
      'Item',
      fields: const ['name', 'item_name'],
      filters: [
        ['name', 'in', defaultItemCodes],
      ],
      limit: defaultItemCodes.length,
    );
    final byCode = <String, String>{
      for (final row in rows)
        if (_text(row['name']).isNotEmpty)
          _text(row['name']): _text(row['item_name']).isEmpty
              ? _text(row['name'])
              : _text(row['item_name']),
    };
    return [
      for (final code in defaultItemCodes)
        if (byCode.containsKey(code))
          RipeningLine(itemCode: code, itemName: byCode[code] ?? code),
    ];
  }

  Future<List<({String code, String name})>> searchItems(String query) async {
    await _frappe.ensureLoggedIn();
    final text = query.trim();
    final rows = await _frappe.fetchResource(
      'Item',
      fields: const ['name', 'item_name'],
      filters: [
        ['disabled', '=', 0],
        if (text.isNotEmpty) ['item_name', 'like', '%$text%'],
      ],
      orderBy: 'item_name asc',
      limit: 30,
    );
    return [
      for (final row in rows)
        if (_text(row['name']).isNotEmpty)
          (
            code: _text(row['name']),
            name: _text(row['item_name']).isEmpty
                ? _text(row['name'])
                : _text(row['item_name']),
          ),
    ];
  }

  Future<List<String>> searchDocuments(String query) async {
    await _frappe.ensureLoggedIn();
    final text = query.trim();
    final rows = await _frappe.fetchResource(
      doctype,
      fields: const ['name'],
      filters: [
        if (text.isNotEmpty) ['name', 'like', '%$text%'],
      ],
      orderBy: 'modified desc',
      limit: 30,
    );
    return [
      for (final row in rows)
        if (_text(row['name']).isNotEmpty) _text(row['name']),
    ];
  }

  Future<List<RipeningLine>> loadLines(Map<String, dynamic> doc) async {
    final meta = await resolveMeta();
    final direct = linesOf(doc, meta);
    if (direct.isNotEmpty) return direct;
    final parent = _text(doc['name']);
    if (parent.isEmpty) return direct;
    final details = await _firstChildren(
      [meta.detailDoctype, 'Ripening Monitoring Detail'],
      parent,
    );
    final hasil = await _firstChildren(
      [
        meta.hasilDoctype,
        'Ripening Monitoring Result',
        'Ripening Monitoring Hasil',
        'Hasil Pengamatan',
      ],
      parent,
    );
    if (details.isEmpty && hasil.isEmpty) return direct;
    return linesOf({
      ...doc,
      if (details.isNotEmpty) meta.detailTable: details,
      if (hasil.isNotEmpty) meta.hasilTable: hasil,
    }, meta);
  }

  Future<List<Map<String, dynamic>>> _firstChildren(
    List<String> doctypes,
    String parent,
  ) async {
    final seen = <String>{};
    for (final name in doctypes) {
      final child = name.trim();
      if (child.isEmpty || !seen.add(child)) continue;
      try {
        final rows = await _frappe.fetchResource(
          child,
          fields: const ['*'],
          filters: [
            ['parent', '=', parent],
            ['parenttype', '=', doctype],
          ],
          orderBy: 'idx asc',
          limit: 200,
        );
        if (rows.isNotEmpty) return rows;
      } catch (_) {
        try {
          final names = await _frappe.fetchResource(
            child,
            fields: const ['name', 'idx'],
            filters: [
              ['parent', '=', parent],
              ['parenttype', '=', doctype],
            ],
            orderBy: 'idx asc',
            limit: 200,
          );
          final full = <Map<String, dynamic>>[];
          for (final row in names) {
            final name = _text(row['name']);
            if (name.isEmpty) continue;
            full.add(await _frappe.fetchDocument(child, name));
          }
          if (full.isNotEmpty) return full;
        } catch (_) {}
      }
    }
    return const [];
  }

  List<RipeningLine> linesOf(Map<String, dynamic> doc, RipeningFieldMap meta) {
    final tables = _childTables(doc);
    final details = _rows(doc[meta.detailTable]).isNotEmpty
        ? _rows(doc[meta.detailTable])
        : _tableMatching(
            tables,
            (row) =>
                _hasKey(row, const ['position', 'posisi', 'qty_sample', 'qty_sampel', 'penggunaan_gas', 'ethylene', 'gas']) &&
                !_hasKey(row, const ['green', 'hijau', 'blonteng', 'yellow', 'kuning']),
          );
    final results = _rows(doc[meta.hasilTable]).isNotEmpty
        ? _rows(doc[meta.hasilTable])
        : _tableMatching(
            tables,
            (row) => _hasKey(row, const ['green', 'hijau', 'blonteng', 'yellow', 'kuning']),
          );
    final hasilByItem = <String, Map<String, dynamic>>{};
    for (final row in results) {
      final code = _itemCode(row);
      if (code.isNotEmpty) hasilByItem[code] = row;
    }
    final lines = <RipeningLine>[];
    final count = details.isNotEmpty ? details.length : results.length;
    for (var i = 0; i < count; i++) {
      final row = i < details.length ? details[i] : const <String, dynamic>{};
      final code = _itemCode(row).isNotEmpty
          ? _itemCode(row)
          : (i < results.length ? _itemCode(results[i]) : '');
      final hasil = hasilByItem[code] ?? (i < results.length ? results[i] : null);
      if (code.isEmpty && row.isEmpty) continue;
      lines.add(
        RipeningLine(
          itemCode: code,
          itemName: _text(_field(row, const ['item_name'], const ['item_name', 'nama'])),
          posisi: _text(_field(row, [meta.posisiField, 'position', 'posisi'], const ['position', 'posisi'])),
          gasEthylene: _num(_field(row, [meta.gasField, 'penggunaan_gas_ethylene_gram', 'gas_ethylene'], const ['penggunaan_gas', 'ethylene', 'gas'])),
          qtySampel: _num(_field(row, [meta.qtyField, 'qty_sample', 'qty_sampel', 'qty'], const ['qty_sample', 'qty', 'sampel'])),
          rh: _num(_field(row, [meta.rhField, 'rh'], const ['rh'])),
          suhuPulp: _num(_field(row, [meta.suhuField, 'pulp_temperature', 'suhu_pulp'], const ['pulp_temperature', 'pulp', 'suhu'])),
          ruang: _text(_field(row, [meta.ruangField, 'ruang'], const ['ruang'])),
          hijau: hasil == null ? 0 : _count(hasil, const ['green', 'hijau']),
          normal: hasil == null ? 0 : _count(hasil, const ['normal']),
          kuning: hasil == null ? 0 : _count(hasil, const ['yellow', 'kuning']),
          blonteng: hasil == null ? 0 : _count(hasil, const ['blonteng']),
        ),
      );
    }
    return lines.where((line) => line.itemCode.isNotEmpty).toList();
  }

  RipeningTotals totalsOf(Map<String, dynamic> doc, List<RipeningLine> lines) {
    final fromLines = RipeningTotals.fromLines(lines);
    final sampel = _headerNum(doc, const ['total_sampel']);
    final normal = _headerNum(doc, const ['total_normal']);
    final blonteng = _headerNum(doc, const ['total_blonteng']);
    if (sampel <= 0) return fromLines;
    return RipeningTotals(
      sampel: sampel,
      normal: normal,
      blonteng: blonteng,
      valid: fromLines.valid,
    );
  }

  static String _itemCode(Map<String, dynamic> row) {
    for (final key in const ['item_code', 'item']) {
      final value = _text(row[key]);
      if (value.isNotEmpty) return value;
    }
    return _text(_field(row, const ['item_code'], const ['item_code']));
  }

  static double _count(Map<String, dynamic> row, List<String> hints) {
    return _num(
      _field(
        row,
        hints,
        hints,
        avoid: const ['persen', 'percent', '%'],
      ),
    );
  }

  static double _headerNum(Map<String, dynamic> doc, List<String> hints) {
    for (final entry in doc.entries) {
      final key = entry.key.toLowerCase();
      if (!hints.any(key.contains)) continue;
      if (key.contains('persen') || key.contains('%')) continue;
      return _num(entry.value);
    }
    return 0;
  }

  static List<Map<String, dynamic>> _tableMatching(
    List<List<Map<String, dynamic>>> tables,
    bool Function(Map<String, dynamic> row) test,
  ) {
    for (final table in tables) {
      if (table.isNotEmpty && test(table.first)) return table;
    }
    return const [];
  }

  static List<List<Map<String, dynamic>>> _childTables(Map<String, dynamic> doc) {
    return [
      for (final value in doc.values)
        if (_rows(value).isNotEmpty) _rows(value),
    ];
  }

  static bool _hasKey(Map<String, dynamic> row, List<String> hints) {
    for (final key in row.keys) {
      final name = key.toLowerCase();
      if (hints.any(name.contains)) return true;
    }
    return false;
  }

  static Object? _field(
    Map<String, dynamic> row,
    List<String> exact,
    List<String> hints, {
    List<String> avoid = const [],
  }) {
    for (final key in exact) {
      if (row.containsKey(key)) return row[key];
    }
    for (final entry in row.entries) {
      final key = entry.key.toLowerCase();
      if (avoid.any(key.contains)) continue;
      if (hints.any(key.contains)) return entry.value;
    }
    return null;
  }

  Future<String> create(RipeningDraft draft) async {
    final meta = await resolveMeta();
    final created = await _frappe.createDocument(
      doctype,
      _payload(draft, meta),
    );
    return _text(created['name']);
  }

  Future<void> update(String name, RipeningDraft draft) async {
    final meta = await resolveMeta();
    await _frappe.updateDocument(doctype, name.trim(), _payload(draft, meta, parentName: name));
  }

  Future<void> submit(String name) async {
    await _frappe.ensureLoggedIn();
    await _frappe.submitDocument(doctype, name.trim());
  }

  Map<String, dynamic> _payload(
    RipeningDraft draft,
    RipeningFieldMap meta, {
    String? parentName,
  }) {
    if (meta.hasilDoctype.trim().isEmpty) {
      throw Exception(
        'Tabel Hasil Pengamatan belum terbaca dari DocType Ripening Monitoring.',
      );
    }
    final parent = (parentName ?? '').trim();
    final totals = RipeningTotals.fromLines(draft.lines);
    final active = draft.lines.where((line) => line.itemCode.trim().isNotEmpty);
    final hijau = active.fold<double>(0, (sum, line) => sum + line.hijau);
    final kuning = active.fold<double>(0, (sum, line) => sum + line.kuning);
    return {
      'doctype': doctype,
      if (parent.isNotEmpty) 'name': parent,
      if (parent.isEmpty && (draft.namingSeries ?? '').trim().isNotEmpty)
        meta.seriesField: draft.namingSeries!.trim(),
      meta.companyField: draft.company.trim(),
      meta.gassingField: _date(draft.tanggalGassing),
      meta.samplingField: _date(draft.tanggalSampling),
      meta.totalSampelField: totals.sampel,
      'total_green': hijau,
      meta.totalNormalField: totals.normal,
      'total_yellow': kuning,
      meta.totalBlontengField: totals.blonteng,
      'green_percentage': _round2(ripeningPercent(hijau, totals.sampel)),
      meta.persenNormalField: _round2(totals.persenNormal),
      'yellow_percentage': _round2(ripeningPercent(kuning, totals.sampel)),
      meta.persenBlontengField: _round2(totals.persenBlonteng),
      'is_group': draft.isGroup ? 1 : 0,
      'old_parent': draft.oldParent.trim(),
      'parent_ripening_monitoring': draft.parentMonitoring.trim(),
      meta.detailTable: [
        for (final line in active) _detailRow(line, meta, parent),
      ],
      meta.hasilTable: [
        for (final line in active) _hasilRow(line, meta, parent),
      ],
    };
  }

  Map<String, dynamic> _detailRow(
    RipeningLine line,
    RipeningFieldMap meta,
    String parent,
  ) {
    return {
      'doctype': meta.detailDoctype,
      'parenttype': doctype,
      'parentfield': meta.detailTable,
      if (parent.isNotEmpty) 'parent': parent,
      meta.itemCodeField: line.itemCode.trim(),
      if (line.itemName.trim().isNotEmpty) meta.itemNameField: line.itemName.trim(),
      'position': line.posisi.trim(),
      'penggunaan_gas_ethylene_gram': line.gasEthylene,
      meta.qtyField: line.qtySampel,
      meta.rhField: line.rh,
      'pulp_temperature': line.suhuPulp,
    };
  }

  Map<String, dynamic> _hasilRow(
    RipeningLine line,
    RipeningFieldMap meta,
    String parent,
  ) {
    final qty = line.qtySampel;
    return {
      'doctype': meta.hasilDoctype,
      'parenttype': doctype,
      'parentfield': meta.hasilTable,
      if (parent.isNotEmpty) 'parent': parent,
      meta.hasilItemField: line.itemCode.trim(),
      meta.hijauField: line.hijau,
      meta.persenHijauField: _round2(ripeningPercent(line.hijau, qty)),
      meta.normalField: line.normal,
      meta.persenNormalRowField: _round2(ripeningPercent(line.normal, qty)),
      meta.kuningField: line.kuning,
      meta.persenKuningField: _round2(ripeningPercent(line.kuning, qty)),
      meta.blontengField: line.blonteng,
      meta.persenBlontengRowField: _round2(ripeningPercent(line.blonteng, qty)),
    };
  }

  RipeningFieldMap _applyParentField(
    RipeningFieldMap meta,
    String name,
    String type,
    String label,
  ) {
    if (name == 'naming_series' || label.contains('series')) {
      return _copy(meta, seriesField: name);
    }
    if (name == 'company' || (type == 'Link' && label.contains('company'))) {
      return _copy(meta, companyField: name);
    }
    if (name == 'gassing_date' || label.contains('gassing')) {
      return _copy(meta, gassingField: name);
    }
    if (name == 'sampling_date' ||
        (label.contains('sampling') && !label.contains('result'))) {
      return _copy(meta, samplingField: name);
    }
    if (name == 'total_sample' ||
        (label.contains('total') &&
            (label.contains('sampel') || label.contains('sample')))) {
      return _copy(meta, totalSampelField: name);
    }
    if (label.contains('total') && label.contains('normal')) {
      return _copy(meta, totalNormalField: name);
    }
    if (label.contains('total') && label.contains('blonteng')) {
      return _copy(meta, totalBlontengField: name);
    }
    if (name == 'normal_percentage' ||
        ((label.contains('persen') ||
                label.contains('%') ||
                name.endsWith('_percentage')) &&
            label.contains('normal') &&
            !label.contains('blonteng'))) {
      return _copy(meta, persenNormalField: name);
    }
    if (name == 'blonteng_percentage' ||
        ((label.contains('persen') ||
                label.contains('%') ||
                name.endsWith('_percentage')) &&
            label.contains('blonteng'))) {
      return _copy(meta, persenBlontengField: name);
    }
    return meta;
  }

  RipeningFieldMap _applyChildFields(
    RipeningFieldMap meta,
    List<Map<String, dynamic>> rows, {
    required bool hasil,
  }) {
    var next = meta;
    for (final row in rows) {
      final name = _text(row['fieldname']);
      final type = _text(row['fieldtype']);
      final label = '${row['label'] ?? ''} $name'.toLowerCase();
      final options = _text(row['options']);
      if (name.isEmpty || _isLayout(type)) continue;
      if (!hasil) {
        if (name == 'item_code' || (type == 'Link' && options == 'Item' && label.contains('code'))) {
          next = _copy(next, itemCodeField: name);
        } else if (name == 'item_name' || label.contains('item name')) {
          next = _copy(next, itemNameField: name);
        } else if (name == 'position' ||
            label.contains('position') ||
            label.contains('posisi')) {
          next = _copy(next, posisiField: name);
        } else if (name == 'penggunaan_gas_ethylene_gram' ||
            label.contains('ethylene') ||
            label.contains('gas')) {
          next = _copy(next, gasField: name, gasLabel: _text(row['label']).isEmpty ? next.gasLabel : _text(row['label']));
        } else if (label.contains('qty') || label.contains('sampel')) {
          next = _copy(next, qtyField: name);
        } else if (label.trim() == 'rh' || name == 'rh') {
          next = _copy(next, rhField: name);
        } else if (name == 'pulp_temperature' ||
            label.contains('pulp') ||
            label.contains('suhu')) {
          next = _copy(next, suhuField: name);
        } else if (label.contains('ruang')) {
          next = _copy(
            next,
            ruangField: name,
            ruangType: type,
            ruangOptions: type == 'Select' ? _selectOptions(options) : next.ruangOptions,
          );
        }
        continue;
      }
      final percent = label.contains('%') ||
          label.contains('persen') ||
          name.endsWith('_percentage');
      if (name == 'item_code' || (type == 'Link' && options == 'Item')) {
        next = _copy(next, hasilItemField: name);
      } else if (name == 'green' || label.contains('hijau')) {
        next = percent
            ? _copy(next, persenHijauField: name)
            : _copy(next, hijauField: name);
      } else if (name == 'yellow' || label.contains('kuning')) {
        next = percent
            ? _copy(next, persenKuningField: name)
            : _copy(next, kuningField: name);
      } else if (label.contains('blonteng')) {
        next = percent
            ? _copy(next, persenBlontengRowField: name)
            : _copy(next, blontengField: name);
      } else if (label.contains('normal')) {
        next = percent
            ? _copy(next, persenNormalRowField: name)
            : _copy(next, normalField: name);
      }
    }
    return next;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _formFields(String parent) async {
    try {
      final message = await _frappe.callMethod(
        'frappe.desk.form.load.getdoctype',
        args: {'doctype': parent},
      );
      if (message is Map && message['docs'] is List) {
        final forms = <String, List<Map<String, dynamic>>>{};
        for (final doc in (message['docs'] as List).whereType<Map>()) {
          final name = _text(doc['name']);
          final fields = doc['fields'];
          if (name.isEmpty || fields is! List) continue;
          forms[name] = [
            for (final field in fields.whereType<Map>())
              Map<String, dynamic>.from(field),
          ];
        }
        if (forms.containsKey(parent)) return forms;
      }
    } catch (_) {}
    return {parent: await _schemaFields(parent)};
  }

  Future<List<Map<String, dynamic>>> _schemaFields(String parent) async {
    if (parent.trim().isEmpty) return const [];
    final rows = <Map<String, dynamic>>[];
    try {
      rows.addAll(
        await _frappe.fetchResource(
          'DocField',
          fields: const ['fieldname', 'fieldtype', 'options', 'label', 'parent'],
          filters: [
            ['parent', '=', parent],
          ],
          limit: 200,
        ),
      );
    } catch (_) {}
    return rows;
  }

  static List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List) return const [];
    return [
      for (final row in value.whereType<Map>()) Map<String, dynamic>.from(row),
    ];
  }

  static List<String> _selectOptions(String raw) {
    return [
      for (final part in raw.split('\n'))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  static bool _isLayout(String type) {
    return type == 'Section Break' ||
        type == 'Column Break' ||
        type == 'Tab Break' ||
        type == 'HTML' ||
        type == 'Button';
  }

  static String _text(Object? value) => value?.toString().trim() ?? '';

  static double _num(Object? value) =>
      double.tryParse('${value ?? ''}'.replaceAll(',', '')) ?? 0;

  static double _round2(double value) => (value * 100).round() / 100;

  static String _date(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static RipeningFieldMap _copy(
    RipeningFieldMap meta, {
    String? seriesField,
    String? companyField,
    String? gassingField,
    String? samplingField,
    String? totalSampelField,
    String? totalNormalField,
    String? totalBlontengField,
    String? persenNormalField,
    String? persenBlontengField,
    String? itemCodeField,
    String? itemNameField,
    String? posisiField,
    String? gasField,
    String? gasLabel,
    String? qtyField,
    String? rhField,
    String? suhuField,
    String? ruangField,
    String? ruangType,
    List<String>? ruangOptions,
    String? hasilItemField,
    String? hijauField,
    String? persenHijauField,
    String? normalField,
    String? persenNormalRowField,
    String? kuningField,
    String? persenKuningField,
    String? blontengField,
    String? persenBlontengRowField,
  }) {
    return RipeningFieldMap(
      seriesField: seriesField ?? meta.seriesField,
      companyField: companyField ?? meta.companyField,
      gassingField: gassingField ?? meta.gassingField,
      samplingField: samplingField ?? meta.samplingField,
      detailTable: meta.detailTable,
      detailDoctype: meta.detailDoctype,
      hasilTable: meta.hasilTable,
      hasilDoctype: meta.hasilDoctype,
      totalSampelField: totalSampelField ?? meta.totalSampelField,
      totalNormalField: totalNormalField ?? meta.totalNormalField,
      totalBlontengField: totalBlontengField ?? meta.totalBlontengField,
      persenNormalField: persenNormalField ?? meta.persenNormalField,
      persenBlontengField: persenBlontengField ?? meta.persenBlontengField,
      itemCodeField: itemCodeField ?? meta.itemCodeField,
      itemNameField: itemNameField ?? meta.itemNameField,
      posisiField: posisiField ?? meta.posisiField,
      gasField: gasField ?? meta.gasField,
      gasLabel: gasLabel ?? meta.gasLabel,
      qtyField: qtyField ?? meta.qtyField,
      rhField: rhField ?? meta.rhField,
      suhuField: suhuField ?? meta.suhuField,
      ruangField: ruangField ?? meta.ruangField,
      ruangType: ruangType ?? meta.ruangType,
      ruangOptions: ruangOptions ?? meta.ruangOptions,
      hasilItemField: hasilItemField ?? meta.hasilItemField,
      hijauField: hijauField ?? meta.hijauField,
      persenHijauField: persenHijauField ?? meta.persenHijauField,
      normalField: normalField ?? meta.normalField,
      persenNormalRowField: persenNormalRowField ?? meta.persenNormalRowField,
      kuningField: kuningField ?? meta.kuningField,
      persenKuningField: persenKuningField ?? meta.persenKuningField,
      blontengField: blontengField ?? meta.blontengField,
      persenBlontengRowField:
          persenBlontengRowField ?? meta.persenBlontengRowField,
    );
  }
}
