import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../../theme/app_colors.dart';

class ErpAttachmentPhotos extends StatelessWidget {
  final List<Map<String, dynamic>> files;
  final String baseUrl;
  final String? cookie;

  const ErpAttachmentPhotos({
    super.key,
    required this.files,
    required this.baseUrl,
    this.cookie,
  });

  @override
  Widget build(BuildContext context) {
    final images = [
      for (final file in files)
        if (_isImage(file) && _url(file).isNotEmpty) file,
    ];
    final pdfs = [
      for (final file in files)
        if (_isPdf(file) && _url(file).isNotEmpty) file,
    ];
    if (images.isEmpty && pdfs.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Lampiran',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${images.length + pdfs.length}',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (images.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: images.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final file = images[index];
              final url = _url(file);
              final name = file['file_name']?.toString().trim().isNotEmpty == true
                  ? file['file_name'].toString()
                  : 'Foto ${index + 1}';
              return InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _ErpAttachmentPhotoPage(
                      title: name,
                      imageUrl: url,
                      cookie: cookie,
                    ),
                  ),
                ),
                borderRadius: BorderRadius.circular(14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    url,
                    headers: cookie == null || cookie!.isEmpty
                        ? null
                        : {'cookie': cookie!},
                    fit: BoxFit.cover,
                    cacheWidth: 480,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: AppColors.background,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.slate,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (pdfs.isNotEmpty) ...[
            if (images.isNotEmpty) const SizedBox(height: 10),
            ...pdfs.map((file) {
              final name = file['file_name']?.toString().trim().isNotEmpty == true
                  ? file['file_name'].toString()
                  : 'Dokumen.pdf';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _ErpAttachmentPdfPage(
                          title: name,
                          url: _url(file),
                          cookie: cookie,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.picture_as_pdf_outlined,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.slate,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  bool _isPdf(Map<String, dynamic> file) {
    final name = (file['file_name'] ?? file['file_url'] ?? '')
        .toString()
        .toLowerCase();
    return name.endsWith('.pdf');
  }

  bool _isImage(Map<String, dynamic> file) {
    final name = (file['file_name'] ?? file['file_url'] ?? '')
        .toString()
        .toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif');
  }

  String _url(Map<String, dynamic> file) {
    final raw = file['file_url']?.toString().trim() ?? '';
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final root = baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (raw.startsWith('/')) return '$root$raw';
    return '$root/$raw';
  }
}

class _ErpAttachmentPhotoPage extends StatelessWidget {
  final String title;
  final String imageUrl;
  final String? cookie;

  const _ErpAttachmentPhotoPage({
    required this.title,
    required this.imageUrl,
    required this.cookie,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Image.network(
            imageUrl,
            headers: cookie == null || cookie!.isEmpty
                ? null
                : {'cookie': cookie!},
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Foto tidak bisa ditampilkan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErpAttachmentPdfPage extends StatefulWidget {
  final String title;
  final String url;
  final String? cookie;

  const _ErpAttachmentPdfPage({
    required this.title,
    required this.url,
    required this.cookie,
  });

  @override
  State<_ErpAttachmentPdfPage> createState() => _ErpAttachmentPdfPageState();
}

class _ErpAttachmentPdfPageState extends State<_ErpAttachmentPdfPage> {
  late final Future<Uint8List> _bytes = _load();

  Future<Uint8List> _load() async {
    final response = await http.get(
      Uri.parse(widget.url),
      headers: widget.cookie == null || widget.cookie!.isEmpty
          ? null
          : {'cookie': widget.cookie!},
    );
    if (response.statusCode >= 400 || response.bodyBytes.isEmpty) {
      throw Exception('PDF tidak bisa dibuka');
    }
    return response.bodyBytes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.navy,
        surfaceTintColor: Colors.transparent,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
      body: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'PDF tidak bisa ditampilkan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.slate,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return PdfPreview(
            build: (_) async => snapshot.data!,
            canChangePageFormat: false,
            canDebug: false,
            pdfFileName: widget.title,
          );
        },
      ),
    );
  }
}
