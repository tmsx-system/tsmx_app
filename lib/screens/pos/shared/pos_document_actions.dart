import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/pos/pos_state.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/erp_doc_utils.dart';
import '../../../utils/erp_share_file.dart';
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
        onPressed: () async {
          final format = await showPosPrintFormatPicker(
            context: context,
            doctype: doctype,
          );
          if (format == null || !context.mounted) return;
          await printErpPdfViaBluetooth(
            context,
            downloadPdf: () => context.read<PosState>().downloadPosPdf(
              doctype,
              name,
              printFormat: format,
            ),
            title: '$doctype $name',
          );
        },
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

Future<String?> showPosPrintFormatPicker({
  required BuildContext context,
  required String doctype,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _PosPrintFormatSheet(doctype: doctype),
  );
}

Future<void> downloadAndSharePosPdf(
  BuildContext context,
  String doctype,
  String name, {
  String? printFormat,
}) async {
  final selectedFormat =
      printFormat ??
      await showPosPrintFormatPicker(context: context, doctype: doctype);
  if (selectedFormat == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(content: Text('Mengunduh PDF $selectedFormat...')),
  );
  try {
    final bytes = await context.read<PosState>().downloadPosPdf(
      doctype,
      name,
      printFormat: selectedFormat,
    );
    final safeName = name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final safeFormat = selectedFormat.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final saved = await saveBytesForUser(
      bytes: bytes,
      fileName: '${safeName}_$safeFormat.pdf',
      mimeType: 'application/pdf',
      appSubfolder: 'pos_pdf',
    );
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          saved.savedToDownloads
              ? 'PDF tersimpan di ${saved.locationLabel}. Bisa dibuka dari Files/Download.'
              : 'PDF siap dibagikan: ${saved.locationLabel}',
        ),
      ),
    );
    await shareSavedFile(
      saved,
      subject: '$doctype $name ($selectedFormat)',
      text: '$doctype $name — $selectedFormat',
    );
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Gagal download PDF: $error')),
    );
  }
}

class _PosPrintFormatSheet extends StatefulWidget {
  final String doctype;

  const _PosPrintFormatSheet({required this.doctype});

  @override
  State<_PosPrintFormatSheet> createState() => _PosPrintFormatSheetState();
}

class _PosPrintFormatSheetState extends State<_PosPrintFormatSheet> {
  List<String> _formats = const [];
  bool _loading = true;
  String? _error;

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
      final formats = await context.read<PosState>().fetchPrintFormats(
        widget.doctype,
      );
      if (!mounted) return;
      setState(() {
        _formats = formats;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.72,
          ),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.16),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Pilih Print Format',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  'Pilih format PDF dari ERPNext, lalu export.',
                  style: TextStyle(
                    color: AppColors.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Flexible(
                child: _loading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.slate,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _load,
                                child: const Text('Coba lagi'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _formats.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: Text(
                            'Tidak ada Print Format PDF untuk dokumen ini.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.slate,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        itemCount: _formats.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, color: AppColors.border),
                        itemBuilder: (context, index) {
                          final format = _formats[index];
                          final isPreferred = format.toLowerCase().contains(
                            'struk',
                          );
                          return ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: isPreferred
                                  ? AppColors.primary
                                  : AppColors.softGreen,
                              foregroundColor: isPreferred
                                  ? AppColors.white
                                  : AppColors.primary,
                              child: const Icon(Icons.picture_as_pdf_outlined),
                            ),
                            title: Text(
                              format,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              isPreferred
                                  ? 'Format struk • Ketuk untuk export PDF'
                                  : 'Ketuk untuk export PDF',
                              style: const TextStyle(
                                color: AppColors.slate,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.slate,
                            ),
                            onTap: () => Navigator.pop(context, format),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
