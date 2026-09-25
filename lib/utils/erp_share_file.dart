import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/native_file_service.dart';

class SavedShareFile {
  final File file;
  final String locationLabel;
  final bool savedToDownloads;

  const SavedShareFile({
    required this.file,
    required this.locationLabel,
    required this.savedToDownloads,
  });
}

Future<SavedShareFile> saveBytesForUser({
  required List<int> bytes,
  required String fileName,
  required String mimeType,
  String appSubfolder = 'exports',
  String downloadsSubdirectory = 'TMSX Hub',
}) async {
  final safeName = fileName
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
      .replaceAll(RegExp(r'\s+'), '_');
  final documents = await getApplicationDocumentsDirectory();
  final folder = Directory('${documents.path}/$appSubfolder');
  if (!await folder.exists()) {
    await folder.create(recursive: true);
  }
  final file = File('${folder.path}/$safeName');
  await file.writeAsBytes(bytes, flush: true);

  if (Platform.isIOS) {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        final publicDir = Directory(
          '${downloads.path}/$downloadsSubdirectory',
        );
        await publicDir.create(recursive: true);
        final publicFile = File('${publicDir.path}/$safeName');
        await publicFile.writeAsBytes(bytes, flush: true);
        return SavedShareFile(
          file: file,
          locationLabel: publicFile.path,
          savedToDownloads: true,
        );
      }
    } catch (_) {}
  }

  final publicPath = await NativeFileService.instance.saveFileToDownloads(
    sourcePath: file.path,
    fileName: safeName,
    mimeType: mimeType,
    subdirectory: downloadsSubdirectory,
  );
  if (publicPath != null && publicPath.trim().isNotEmpty) {
    return SavedShareFile(
      file: file,
      locationLabel: publicPath,
      savedToDownloads: true,
    );
  }
  return SavedShareFile(
    file: file,
    locationLabel: safeName,
    savedToDownloads: false,
  );
}

Future<void> shareSavedFile(
  SavedShareFile saved, {
  required String subject,
  String? text,
}) {
  return SharePlus.instance.share(
    ShareParams(
      files: [XFile(saved.file.path, mimeType: _mimeFromName(saved.file.path))],
      subject: subject,
      text: text ?? subject,
    ),
  );
}

String _mimeFromName(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.csv')) return 'text/csv';
  return 'application/octet-stream';
}
