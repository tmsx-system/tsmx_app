enum ErpErrorKind {
  permission,
  session,
  notFound,
  validation,
  network,
  unexpected,
}

class ErpErrorInfo {
  final ErpErrorKind kind;
  final String title;
  final String message;
  final String? detail;
  final String? doctype;

  const ErpErrorInfo({
    required this.kind,
    required this.title,
    required this.message,
    this.detail,
    this.doctype,
  });
}

class ErpErrorMessage {
  ErpErrorMessage._();

  static const apologyTitle = 'Mohon maaf';

  static ErpErrorInfo parse(
    Object error, {
    int? statusCode,
    String? action,
  }) {
    final raw = _clean(error.toString());
    final lower = raw.toLowerCase();
    final doctype = _extractDoctype(raw);
    final actionText = (action ?? '').trim();

    if (_isNetwork(lower)) {
      return ErpErrorInfo(
        kind: ErpErrorKind.network,
        title: apologyTitle,
        message: actionText.isEmpty
            ? 'Koneksi sedang bermasalah. Periksa internet Anda, lalu coba lagi.'
            : 'Koneksi sedang bermasalah saat $actionText. Periksa internet Anda, lalu coba lagi.',
        detail: raw,
        doctype: doctype,
      );
    }

    if (_isSession(lower, statusCode)) {
      return ErpErrorInfo(
        kind: ErpErrorKind.session,
        title: apologyTitle,
        message:
            'Sesi login sudah berakhir atau belum diizinkan. Silakan masuk kembali.',
        detail: raw,
        doctype: doctype,
      );
    }

    if (_isPermission(lower)) {
      final target = doctype ?? 'data ini';
      return ErpErrorInfo(
        kind: ErpErrorKind.permission,
        title: apologyTitle,
        message: actionText.isEmpty
            ? 'Anda belum memiliki izin untuk $target. Hubungi admin/IT jika seharusnya bisa mengaksesnya.'
            : 'Anda belum memiliki izin untuk $actionText ($target). Hubungi admin/IT jika seharusnya bisa melakukan ini.',
        detail: raw,
        doctype: doctype,
      );
    }

    if (_isMissingFeature(lower) ||
        (lower.contains('doctype') &&
            (lower.contains('not found') ||
                lower.contains('does not exist') ||
                lower.contains('tidak ditemukan')))) {
      return ErpErrorInfo(
        kind: ErpErrorKind.notFound,
        title: apologyTitle,
        message: doctype == null
            ? 'Fitur ini belum aktif di site ERPNext.'
            : 'Fitur $doctype belum aktif di site ERPNext.',
        detail: raw,
        doctype: doctype,
      );
    }

    if (statusCode == 404 || _isNotFound(lower)) {
      return ErpErrorInfo(
        kind: ErpErrorKind.notFound,
        title: apologyTitle,
        message: actionText.isEmpty
            ? 'Data yang diminta tidak ditemukan.'
            : 'Data tidak ditemukan saat $actionText.',
        detail: raw,
        doctype: doctype,
      );
    }

    if (_isValidation(lower)) {
      return ErpErrorInfo(
        kind: ErpErrorKind.validation,
        title: apologyTitle,
        message: _stripExceptionPrefix(raw),
        detail: raw,
        doctype: doctype,
      );
    }

    return ErpErrorInfo(
      kind: ErpErrorKind.unexpected,
      title: apologyTitle,
      message: actionText.isEmpty
          ? 'Terjadi kendala yang belum kami temukan. Silakan coba lagi. Jika berulang, hubungi tim IT.'
          : 'Terjadi kendala saat $actionText. Silakan coba lagi. Jika berulang, hubungi tim IT.',
      detail: _stripExceptionPrefix(raw),
      doctype: doctype,
    );
  }

  static String text(Object error, {String? action, int? statusCode}) {
    return parse(error, action: action, statusCode: statusCode).message;
  }

  /// Thrown by [FrappeService] so UI can still classify the original error.
  static String fromFrappe(String raw, {required int statusCode}) {
    final info = parse(raw, statusCode: statusCode);
    if (info.kind == ErpErrorKind.permission) {
      final doctype = info.doctype;
      if (doctype != null && doctype.isNotEmpty) {
        return 'PermissionError: $doctype';
      }
      return 'PermissionError: ${_stripExceptionPrefix(_clean(raw))}';
    }
    if (info.kind == ErpErrorKind.session) {
      return 'SessionError: ${info.message}';
    }
    if (info.kind == ErpErrorKind.notFound && info.doctype != null) {
      return info.message;
    }
    return _stripExceptionPrefix(_clean(raw));
  }

  static bool isIgnorableFrameworkNoise(Object error) {
    final lower = error.toString().toLowerCase();
    return lower.contains('overflowed') ||
        lower.contains('renderflex') ||
        lower.contains('mouse_tracker') ||
        lower.contains('setstate() called after dispose') ||
        lower.contains('looking up a deactivated widget') ||
        lower.contains('duplicate globalkey') ||
        lower.contains('semantics') ||
        lower.contains('ignored pointer') ||
        lower.contains('listtile background color or ink splashes') ||
        lower.contains('ink splashes may be invisible') ||
        lower.contains('wrap the listtile in its own material') ||
        lower.contains('setstate() or markneedsbuild() called during build') ||
        lower.contains('cannot be marked as needing to build');
  }

  static String _clean(String raw) {
    return raw
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
  }

  static String _stripExceptionPrefix(String message) {
    final cleaned = message
        .replaceFirst(RegExp(r'^frappe\.exceptions\.[A-Za-z]+:\s*'), '')
        .replaceFirst(RegExp(r'^[A-Za-z]*Error:\s*'), '')
        .trim();
    return cleaned.isEmpty ? message.trim() : cleaned;
  }

  static bool _isPermission(String lower) {
    return lower.contains('permissionerror') ||
        lower.contains('not permitted') ||
        lower.contains('insufficient permission') ||
        lower.contains('tidak diizinkan') ||
        lower.contains("don't have enough permission") ||
        lower.contains('dont have enough permission');
  }

  static bool _isSession(String lower, int? statusCode) {
    return statusCode == 401 ||
        lower.contains('sessionerror') ||
        lower.contains('not logged in') ||
        lower.contains('login failed') ||
        lower.contains('authentication failed') ||
        lower.contains('csrf');
  }

  static bool _isNetwork(String lower) {
    return lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection refused') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('connection reset');
  }

  static bool _isNotFound(String lower) {
    return lower.contains('does not exist') ||
        lower.contains('not found') ||
        lower.contains('tidak ditemukan');
  }

  static bool _isMissingFeature(String lower) {
    return lower.contains('fitur belum aktif') ||
        (lower.contains('fitur ') && lower.contains('belum aktif'));
  }

  static bool _isValidation(String lower) {
    return lower.contains('validationerror') ||
        lower.contains('mandatoryerror') ||
        (lower.contains('mandatory') && lower.contains('missing')) ||
        lower.contains('cannot be empty') ||
        lower.contains('value missing');
  }

  static String? _extractDoctype(String message) {
    final patterns = [
      RegExp(r'PermissionError:\s*([A-Za-z][A-Za-z0-9 ]+)'),
      RegExp(r'for doctype\s+([A-Za-z][A-Za-z0-9 ]+)', caseSensitive: false),
      RegExp(r'doctype\s+([A-Za-z][A-Za-z0-9 ]+)', caseSensitive: false),
      RegExp(
        r'DocType\s+(.+?)\s+(?:tidak ditemukan|not found|does not exist)',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(message);
      var value = match?.group(1)?.trim();
      if (value == null || value.isEmpty) continue;
      value = value.replaceAll(RegExp(r'["`.:]'), '').trim();
      if (value.length > 40) continue;
      return value;
    }
    return null;
  }
}
