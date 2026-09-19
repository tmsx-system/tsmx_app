import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class FrappeStatusStyle {
  final String label;
  final Color color;
  final IconData icon;

  const FrappeStatusStyle({
    required this.label,
    required this.color,
    required this.icon,
  });
}

String normalizeStatusText(String? status, {int? docstatus}) {
  final trimmed = status?.trim() ?? '';
  if (trimmed.isNotEmpty) return trimmed;
  if (docstatus == 0) return 'Draft';
  if (docstatus == 1) return 'Submitted';
  if (docstatus == 2) return 'Cancelled';
  return 'Unknown';
}

bool _eq(String a, String b) => a.toLowerCase() == b.toLowerCase();

bool _contains(String haystack, String needle) =>
    haystack.toLowerCase().contains(needle.toLowerCase());

FrappeStatusStyle styleForStatusText(String statusText) {
  final s = statusText.toLowerCase();

  if (_eq(s, 'draft') || s.isEmpty) {
    return const FrappeStatusStyle(
      label: 'DRAFT',
      color: AppColors.slate,
      icon: Icons.edit_rounded,
    );
  }
  if (_contains(s, 'submit')) {
    return const FrappeStatusStyle(
      label: 'SUBMITTED',
      color: Color(0xFF2563EB),
      icon: Icons.check_circle_outline_rounded,
    );
  }
  if (_contains(s, 'on hold')) {
    return const FrappeStatusStyle(
      label: 'ON HOLD',
      color: Color(0xFF6366F1),
      icon: Icons.pause_circle_outline_rounded,
    );
  }
  if (_contains(s, 'cancel')) {
    return const FrappeStatusStyle(
      label: 'CANCELLED',
      color: Color(0xFF64748B),
      icon: Icons.cancel_rounded,
    );
  }
  if (_contains(s, 'closed')) {
    return const FrappeStatusStyle(
      label: 'CLOSED',
      color: Color(0xFF4F46E5),
      icon: Icons.lock_rounded,
    );
  }
  if (_contains(s, 'completed')) {
    return const FrappeStatusStyle(
      label: 'COMPLETED',
      color: Color(0xFF0F766E),
      icon: Icons.done_all_rounded,
    );
  }
  if (_contains(s, 'partly paid') || _contains(s, 'partially paid')) {
    return const FrappeStatusStyle(
      label: 'PARTLY PAID',
      color: Color(0xFFCA8A04),
      icon: Icons.payments_outlined,
    );
  }
  if (_contains(s, 'paid') && !_contains(s, 'unpaid')) {
    return const FrappeStatusStyle(
      label: 'PAID',
      color: Color(0xFF059669),
      icon: Icons.check_circle_outline_rounded,
    );
  }
  if (_contains(s, 'overdue')) {
    return const FrappeStatusStyle(
      label: 'OVERDUE',
      color: Color(0xFFDC2626),
      icon: Icons.error_outline_rounded,
    );
  }
  if (_contains(s, 'unpaid')) {
    return const FrappeStatusStyle(
      label: 'UNPAID',
      color: Color(0xFFF59E0B),
      icon: Icons.schedule_rounded,
    );
  }
  if (_contains(s, 'credit note')) {
    return const FrappeStatusStyle(
      label: 'CREDIT NOTE ISSUED',
      color: Color(0xFF64748B),
      icon: Icons.receipt_long_outlined,
    );
  }
  if (_contains(s, 'return issued')) {
    return const FrappeStatusStyle(
      label: 'RETURN ISSUED',
      color: Color(0xFF64748B),
      icon: Icons.undo_rounded,
    );
  }
  if (_contains(s, 'return')) {
    return const FrappeStatusStyle(
      label: 'RETURN',
      color: Color(0xFF64748B),
      icon: Icons.undo_rounded,
    );
  }
  if (_contains(s, 'to deliver and bill')) {
    return const FrappeStatusStyle(
      label: 'TO DELIVER & BILL',
      color: Color(0xFF2563EB),
      icon: Icons.local_shipping_outlined,
    );
  }
  if (_contains(s, 'to receive and bill')) {
    return const FrappeStatusStyle(
      label: 'TO RECEIVE & BILL',
      color: Color(0xFFDB2777),
      icon: Icons.playlist_add_check_rounded,
    );
  }
  if (_contains(s, 'partially billed') || _contains(s, 'partly billed')) {
    return const FrappeStatusStyle(
      label: 'PARTLY BILLED',
      color: Color(0xFFCA8A04),
      icon: Icons.receipt_outlined,
    );
  }
  if (_contains(s, 'to bill')) {
    return const FrappeStatusStyle(
      label: 'TO BILL',
      color: Color.fromARGB(255, 183, 141, 15),
      icon: Icons.receipt_rounded,
    );
  }
  if (_contains(s, 'to deliver')) {
    return const FrappeStatusStyle(
      label: 'TO DELIVER',
      color: Color(0xFF2563EB),
      icon: Icons.local_shipping_outlined,
    );
  }
  if (_contains(s, 'to receive')) {
    return const FrappeStatusStyle(
      label: 'TO RECEIVE',
      color: Color(0xFF6366F1),
      icon: Icons.inbox_rounded,
    );
  }
  if (_contains(s, 'to pay')) {
    return const FrappeStatusStyle(
      label: 'TO PAY',
      color: Color(0xFF7C3AED),
      icon: Icons.account_balance_wallet_outlined,
    );
  }
  if (_contains(s, 'delivered')) {
    return const FrappeStatusStyle(
      label: 'DELIVERED',
      color: Color(0xFF059669),
      icon: Icons.check_circle_outline_rounded,
    );
  }

  return FrappeStatusStyle(
    label: statusText.toUpperCase(),
    color: AppColors.primary,
    icon: Icons.info_outline_rounded,
  );
}

enum SalesOrderStatusKey {
  draft,
  overdue,
  toDeliverAndBill,
  toBill,
  toDeliver,
  completed,
  closed,
  cancelled,
  unknown,
}

SalesOrderStatusKey parseSalesOrderStatus(String statusText, {int? docstatus}) {
  final text = normalizeStatusText(statusText, docstatus: docstatus);
  final s = text.toLowerCase();

  if (_eq(s, 'draft') || docstatus == 0) return SalesOrderStatusKey.draft;
  if (_contains(s, 'cancel') || docstatus == 2) {
    return SalesOrderStatusKey.cancelled;
  }
  if (_contains(s, 'closed')) return SalesOrderStatusKey.closed;
  if (_contains(s, 'completed')) return SalesOrderStatusKey.completed;
  if (_contains(s, 'overdue')) return SalesOrderStatusKey.overdue;
  if (_contains(s, 'to deliver and bill')) {
    return SalesOrderStatusKey.toDeliverAndBill;
  }
  if (_contains(s, 'to bill')) return SalesOrderStatusKey.toBill;
  if (_contains(s, 'to deliver')) return SalesOrderStatusKey.toDeliver;

  return SalesOrderStatusKey.unknown;
}

enum PurchaseOrderStatusKey {
  draft,
  toReceiveAndBill,
  toBill,
  toReceive,
  completed,
  cancelled,
  closed,
  unknown,
}

PurchaseOrderStatusKey parsePurchaseOrderStatus(
  String statusText, {
  int? docstatus,
}) {
  final text = normalizeStatusText(statusText, docstatus: docstatus);
  final s = text.toLowerCase();

  if (_eq(s, 'draft') || docstatus == 0) return PurchaseOrderStatusKey.draft;
  if (_contains(s, 'cancel') || docstatus == 2) {
    return PurchaseOrderStatusKey.cancelled;
  }
  if (_contains(s, 'closed')) return PurchaseOrderStatusKey.closed;
  if (_contains(s, 'completed')) return PurchaseOrderStatusKey.completed;
  if (_contains(s, 'to receive and bill') ||
      _contains(s, 'to receive and to bill')) {
    return PurchaseOrderStatusKey.toReceiveAndBill;
  }
  if (_contains(s, 'to receive')) return PurchaseOrderStatusKey.toReceive;
  if (_contains(s, 'to bill')) return PurchaseOrderStatusKey.toBill;

  return PurchaseOrderStatusKey.unknown;
}

enum DeliveryNoteStatusKey {
  draft,
  toBill,
  completed,
  returnDoc,
  returnIssued,
  closed,
  cancelled,
  unknown,
}

DeliveryNoteStatusKey parseDeliveryNoteStatus(
  String statusText, {
  int? docstatus,
}) {
  final text = normalizeStatusText(statusText, docstatus: docstatus);
  final s = text.toLowerCase();

  if (_eq(s, 'draft') || docstatus == 0) return DeliveryNoteStatusKey.draft;
  if (_contains(s, 'cancel') || docstatus == 2) {
    return DeliveryNoteStatusKey.cancelled;
  }
  if (_contains(s, 'closed')) return DeliveryNoteStatusKey.closed;
  if (_contains(s, 'return issued')) return DeliveryNoteStatusKey.returnIssued;
  if (_contains(s, 'return')) return DeliveryNoteStatusKey.returnDoc;
  if (_contains(s, 'completed')) return DeliveryNoteStatusKey.completed;
  if (_contains(s, 'to bill')) return DeliveryNoteStatusKey.toBill;

  return DeliveryNoteStatusKey.unknown;
}

enum InvoiceStatusKey {
  draft,
  returnDoc,
  creditNoteIssued,
  paid,
  partlyPaid,
  unpaid,
  overdue,
  cancelled,
  unknown,
}

InvoiceStatusKey parseInvoiceStatus(String statusText, {int? docstatus}) {
  final text = normalizeStatusText(statusText, docstatus: docstatus);
  final s = text.toLowerCase();

  if (_eq(s, 'draft') || docstatus == 0) return InvoiceStatusKey.draft;
  if (_contains(s, 'cancel') || docstatus == 2) {
    return InvoiceStatusKey.cancelled;
  }
  if (_contains(s, 'credit note')) return InvoiceStatusKey.creditNoteIssued;
  if (_contains(s, 'return')) return InvoiceStatusKey.returnDoc;
  if (_contains(s, 'overdue')) return InvoiceStatusKey.overdue;
  if (_contains(s, 'partly paid') || _contains(s, 'partially paid')) {
    return InvoiceStatusKey.partlyPaid;
  }
  if (_contains(s, 'paid') && !_contains(s, 'unpaid')) {
    return InvoiceStatusKey.paid;
  }
  if (_contains(s, 'unpaid')) return InvoiceStatusKey.unpaid;

  return InvoiceStatusKey.unknown;
}

FrappeStatusStyle styleForSalesOrderKey(SalesOrderStatusKey key) {
  switch (key) {
    case SalesOrderStatusKey.draft:
      return styleForStatusText('Draft');
    case SalesOrderStatusKey.overdue:
      return styleForStatusText('Overdue');
    case SalesOrderStatusKey.toDeliverAndBill:
      return styleForStatusText('To Deliver and Bill');
    case SalesOrderStatusKey.toBill:
      return styleForStatusText('To Bill');
    case SalesOrderStatusKey.toDeliver:
      return styleForStatusText('To Deliver');
    case SalesOrderStatusKey.completed:
      return styleForStatusText('Completed');
    case SalesOrderStatusKey.closed:
      return styleForStatusText('Closed');
    case SalesOrderStatusKey.cancelled:
      return styleForStatusText('Cancelled');
    case SalesOrderStatusKey.unknown:
      return const FrappeStatusStyle(
        label: 'UNKNOWN',
        color: AppColors.slate,
        icon: Icons.help_outline_rounded,
      );
  }
}
