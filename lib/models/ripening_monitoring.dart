class RipeningSummary {
  final String name;
  final String company;
  final String tanggalGassing;
  final String tanggalSampling;
  final int docstatus;

  const RipeningSummary({
    required this.name,
    this.company = '',
    this.tanggalGassing = '',
    this.tanggalSampling = '',
    this.docstatus = 0,
  });

  bool get isDraft => docstatus == 0;

  String get statusLabel {
    if (docstatus == 1) return 'Submitted';
    if (docstatus == 2) return 'Cancelled';
    return 'Draft';
  }
}

class RipeningLine {
  final String itemCode;
  final String itemName;
  final String posisi;
  final double gasEthylene;
  final double qtySampel;
  final double rh;
  final double suhuPulp;
  final String ruang;
  final double hijau;
  final double normal;
  final double kuning;
  final double blonteng;

  const RipeningLine({
    required this.itemCode,
    this.itemName = '',
    this.posisi = '',
    this.gasEthylene = 0,
    this.qtySampel = 0,
    this.rh = 0,
    this.suhuPulp = 0,
    this.ruang = '',
    this.hijau = 0,
    this.normal = 0,
    this.kuning = 0,
    this.blonteng = 0,
  });

  double get colorTotal => hijau + normal + kuning + blonteng;

  bool get hasObservation =>
      qtySampel > 0 ||
      hijau > 0 ||
      normal > 0 ||
      kuning > 0 ||
      blonteng > 0;

  bool get colorsMatchSample {
    bool whole(double value) => value >= -0.001 && (value - value.round()).abs() < 0.001;
    if (!whole(qtySampel) ||
        !whole(hijau) ||
        !whole(normal) ||
        !whole(kuning) ||
        !whole(blonteng)) {
      return false;
    }
    return colorTotal <= qtySampel + 0.001;
  }
}

class RipeningDraft {
  final String? namingSeries;
  final String company;
  final DateTime tanggalGassing;
  final DateTime tanggalSampling;
  final bool isGroup;
  final String oldParent;
  final String parentMonitoring;
  final List<RipeningLine> lines;

  const RipeningDraft({
    this.namingSeries,
    required this.company,
    required this.tanggalGassing,
    required this.tanggalSampling,
    this.isGroup = false,
    this.oldParent = '',
    this.parentMonitoring = '',
    required this.lines,
  });
}

class RipeningFieldMap {
  final String seriesField;
  final String companyField;
  final String gassingField;
  final String samplingField;
  final String detailTable;
  final String detailDoctype;
  final String hasilTable;
  final String hasilDoctype;
  final String totalSampelField;
  final String totalNormalField;
  final String totalBlontengField;
  final String persenNormalField;
  final String persenBlontengField;
  final String itemCodeField;
  final String itemNameField;
  final String posisiField;
  final String gasField;
  final String gasLabel;
  final String qtyField;
  final String rhField;
  final String suhuField;
  final String ruangField;
  final String ruangType;
  final List<String> ruangOptions;
  final String hasilItemField;
  final String hijauField;
  final String persenHijauField;
  final String normalField;
  final String persenNormalRowField;
  final String kuningField;
  final String persenKuningField;
  final String blontengField;
  final String persenBlontengRowField;

  const RipeningFieldMap({
    this.seriesField = 'naming_series',
    this.companyField = 'company',
    this.gassingField = 'gassing_date',
    this.samplingField = 'sampling_date',
    this.detailTable = 'sampling_details',
    this.detailDoctype = 'Ripening Monitoring Detail',
    this.hasilTable = 'sampling_results',
    this.hasilDoctype = 'Ripening Monitoring Result',
    this.totalSampelField = 'total_sample',
    this.totalNormalField = 'total_normal',
    this.totalBlontengField = 'total_blonteng',
    this.persenNormalField = 'normal_percentage',
    this.persenBlontengField = 'blonteng_percentage',
    this.itemCodeField = 'item_code',
    this.itemNameField = 'item_name',
    this.posisiField = 'position',
    this.gasField = 'penggunaan_gas_ethylene_gram',
    this.gasLabel = 'Gas Ethylene (Gram)',
    this.qtyField = 'qty_sample',
    this.rhField = 'rh',
    this.suhuField = 'pulp_temperature',
    this.ruangField = 'ruang',
    this.ruangType = 'Data',
    this.ruangOptions = const [],
    this.hasilItemField = 'item_code',
    this.hijauField = 'green',
    this.persenHijauField = 'green_percentage',
    this.normalField = 'normal',
    this.persenNormalRowField = 'normal_percentage',
    this.kuningField = 'yellow',
    this.persenKuningField = 'yellow_percentage',
    this.blontengField = 'blonteng',
    this.persenBlontengRowField = 'blonteng_percentage',
  });
}

double ripeningPercent(double part, double total) {
  if (total <= 0 || part <= 0) return 0;
  return (part / total) * 100;
}

class RipeningTotals {
  final double sampel;
  final double normal;
  final double blonteng;
  final bool valid;

  const RipeningTotals({
    required this.sampel,
    required this.normal,
    required this.blonteng,
    required this.valid,
  });

  double get persenNormal => ripeningPercent(normal, sampel);
  double get persenBlonteng => ripeningPercent(blonteng, sampel);

  static RipeningTotals fromLines(List<RipeningLine> lines) {
    final observed = lines.where((line) => line.itemCode.trim().isNotEmpty);
    var sampel = 0.0;
    var normal = 0.0;
    var blonteng = 0.0;
    for (final line in observed) {
      sampel += line.qtySampel;
      normal += line.normal;
      blonteng += line.blonteng;
    }
    return RipeningTotals(
      sampel: sampel,
      normal: normal,
      blonteng: blonteng,
      valid: observed.isNotEmpty && observed.every((line) => line.colorsMatchSample),
    );
  }
}
