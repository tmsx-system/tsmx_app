import 'dart:io';

import 'package:flutter/services.dart';

class NativeFileService {
  NativeFileService._();

  static final NativeFileService instance = NativeFileService._();
  static const _channel = MethodChannel('com.tmsxhub/files');

  Future<String?> saveFileToDownloads({
    required String sourcePath,
    required String fileName,
    required String mimeType,
    String subdirectory = 'TMSX Hub',
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('saveFileToDownloads', {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'mimeType': mimeType,
        'subdirectory': subdirectory,
      });
    } catch (_) {
      return null;
    }
  }
}
