import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../state/pos/pos_state.dart';
import '../../../utils/erp_doc_utils.dart';
import '../../../widgets/erp/erp_workflow_helper.dart';
import '../../../widgets/print/erp_bluetooth_print.dart';

class PosDoctypeActionPermissions {
  final bool canWrite;
  final bool canSubmit;
  final bool canDelete;
  final bool canCancel;
  final bool canAmend;
  final bool canPrint;

  const PosDoctypeActionPermissions({
    this.canWrite = false,
    this.canSubmit = false,
    this.canDelete = false,
    this.canCancel = false,
    this.canAmend = false,
    this.canPrint = false,
  });

  static Future<PosDoctypeActionPermissions> load(
    PosState state,
    String doctype, {
    bool includePrint = false,
  }) async {
    final results = await Future.wait([
      state.canWriteDoctype(doctype),
      state.canSubmitDoctype(doctype),
      state.canDeleteDoctype(doctype),
      state.canCancelDoctype(doctype),
      state.canAmendDoctype(doctype),
      if (includePrint) state.canPrintDoctype(doctype),
    ]);
    return PosDoctypeActionPermissions(
      canWrite: results[0],
      canSubmit: results[1],
      canDelete: results[2],
      canCancel: results[3],
      canAmend: results[4],
      canPrint: includePrint ? results[5] : false,
    );
  }
}

List<Widget> buildPosDocumentActionButtons({
  required BuildContext context,
  required String doctype,
  required String name,
  required int docStatus,
  required PosDoctypeActionPermissions permissions,
  required Future<void> Function() onChanged,
  VoidCallback? onEdit,
  bool enablePrint = false,
}) {
  final canEdit = permissions.canWrite && isDocDraft(docStatus) && onEdit != null;
  final canSubmit = permissions.canSubmit && isDocDraft(docStatus);
  final canDelete = permissions.canDelete && isDocDraft(docStatus);
  final canCancel = permissions.canCancel && isDocSubmitted(docStatus);
  final canAmend = permissions.canAmend && isDocCancelled(docStatus);
  final canPrint = enablePrint && permissions.canPrint;

  Future<void> runAction({
    required String title,
    required String message,
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    final confirmed = await confirmErpAction(
      context,
      title: title,
      message: message,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await runErpWorkflowAction(
      context,
      action: action,
      successMessage: successMessage,
    );
    if (!ok || !context.mounted) return;
    Navigator.of(context).pop();
    await onChanged();
  }

  return [
    if (canEdit)
      erpActionButton(
        label: 'Edit',
        icon: Icons.edit_outlined,
        onPressed: () {
          Navigator.of(context).pop();
          onEdit();
        },
      ),
    if (canSubmit)
      erpActionButton(
        label: 'Submit',
        icon: Icons.check_circle_outline_rounded,
        filled: true,
        onPressed: () => runAction(
          title: 'Submit dokumen?',
          message: 'Submit $doctype $name ke ERPNext.',
          successMessage: '$doctype $name berhasil di-submit.',
          action: () =>
              context.read<PosState>().submitPosDocument(doctype, name),
        ),
      ),
    if (canPrint)
      erpActionButton(
        label: 'Print',
        icon: Icons.print_outlined,
        onPressed: () => printErpPdfViaBluetooth(
          context,
          downloadPdf: () =>
              context.read<PosState>().downloadPosPdf(doctype, name),
          title: '$doctype $name',
        ),
      ),
    if (canPrint)
      erpActionButton(
        label: 'Download PDF / Share',
        icon: Icons.picture_as_pdf_outlined,
        onPressed: () => downloadAndSharePosPdf(context, doctype, name),
      ),
    if (canCancel)
      erpActionButton(
        label: 'Cancel',
        icon: Icons.cancel_outlined,
        onPressed: () => runAction(
          title: 'Cancel dokumen?',
          message: 'Cancel $doctype $name. Dokumen tidak bisa diedit lagi.',
          successMessage: '$doctype $name berhasil di-cancel.',
          action: () =>
              context.read<PosState>().cancelPosDocument(doctype, name),
        ),
      ),
    if (canAmend)
      erpActionButton(
        label: 'Amend',
        icon: Icons.restore_page_outlined,
        onPressed: () => runAction(
          title: 'Amend dokumen?',
          message:
              'Buat draft baru dari $doctype $name yang sudah di-cancel.',
          successMessage: 'Draft amend $doctype berhasil dibuat.',
          action: () async {
            await context.read<PosState>().amendPosDocument(doctype, name);
          },
        ),
      ),
    if (canDelete)
      erpActionButton(
        label: 'Delete',
        icon: Icons.delete_outline_rounded,
        onPressed: () => runAction(
          title: 'Delete dokumen?',
          message: 'Hapus permanen $doctype $name.',
          successMessage: '$doctype $name berhasil dihapus.',
          action: () =>
              context.read<PosState>().deletePosDocument(doctype, name),
        ),
      ),
  ];
}

Future<void> downloadAndSharePosPdf(
  BuildContext context,
  String doctype,
  String name,
) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(content: Text('Mengunduh PDF $doctype $name...')),
  );
  try {
    final bytes = await context.read<PosState>().downloadPosPdf(doctype, name);
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory('${directory.path}/pos_pdf');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final safeName = name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File('${folder.path}/$safeName.pdf');
    await file.writeAsBytes(bytes, flush: true);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('PDF tersimpan: ${file.path.split('/').last}')),
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: '$doctype $name',
        text: '$doctype $name',
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Gagal download PDF: $error')),
    );
  }
}
