import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_colors.dart';
import '../../utils/app_navigator.dart';
import '../../utils/erp_error_message.dart';

class ErpErrorDialog {
  ErpErrorDialog._();

  static bool _open = false;
  static DateTime? _lastShownAt;
  static String? _lastFingerprint;

  static Future<void> show(
    BuildContext? context, {
    required Object error,
    String? action,
    int? statusCode,
  }) {
    return showInfo(
      context,
      ErpErrorMessage.parse(error, action: action, statusCode: statusCode),
    );
  }

  static Future<void> showUnexpected(Object error, {String? action}) {
    if (ErpErrorMessage.isIgnorableFrameworkNoise(error)) {
      return Future.value();
    }
    return showInfo(
      AppNavigator.context,
      ErpErrorMessage.parse(error, action: action),
    );
  }

  static Future<void> showInfo(BuildContext? context, ErpErrorInfo info) async {
    final fingerprint = '${info.kind}|${info.message}|${info.detail}';
    final now = DateTime.now();
    if (_open) return;
    if (_lastFingerprint == fingerprint &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < const Duration(seconds: 2)) {
      return;
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      final done = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        done.complete(showInfo(context, info));
      });
      return done.future;
    }

    final resolved = context ?? AppNavigator.context;
    if (resolved == null || !resolved.mounted) return;

    _open = true;
    _lastShownAt = now;
    _lastFingerprint = fingerprint;
    try {
      await showGeneralDialog<void>(
        context: resolved,
        barrierDismissible: true,
        barrierLabel: 'Tutup pesan error',
        barrierColor: Colors.black.withValues(alpha: 0.45),
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return const SizedBox.shrink();
        },
        transitionBuilder: (dialogContext, animation, secondary, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
              child: _ErpSorryDialog(info: info),
            ),
          );
        },
      );
    } finally {
      _open = false;
    }
  }
}

Future<void> showErpError(
  BuildContext? context, {
  required Object error,
  String? action,
  int? statusCode,
}) {
  return ErpErrorDialog.show(
    context,
    error: error,
    action: action,
    statusCode: statusCode,
  );
}

/// Formats a user-facing error and optionally shows the apology popup.
String captureErpError(
  BuildContext? context,
  Object error, {
  String? action,
  bool popup = true,
}) {
  if (popup) {
    unawaited(showErpError(context, error: error, action: action));
  }
  return ErpErrorMessage.parse(error, action: action).message;
}

class _ErpSorryDialog extends StatelessWidget {
  final ErpErrorInfo info;

  const _ErpSorryDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final detail = info.detail?.trim();
    final showDetail =
        detail != null &&
        detail.isNotEmpty &&
        detail.toLowerCase() != info.message.toLowerCase();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: AppColors.white,
          elevation: 8,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      info.kind == ErpErrorKind.permission
                          ? Icons.lock_outline_rounded
                          : Icons.sentiment_dissatisfied_rounded,
                      color: AppColors.danger,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    info.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    info.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.slate,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  if (showDetail) ...[
                    const SizedBox(height: 12),
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 4),
                        title: const Text(
                          'Detail teknis',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navy,
                          ),
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              detail,
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.35,
                                color: AppColors.slate,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Mengerti',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
