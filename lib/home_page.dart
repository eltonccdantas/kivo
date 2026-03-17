import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'models/models.dart';
import 'services/compression_service.dart';
import 'utils/file_utils.dart';
import 'widgets/progress_dialog.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? _selectedFile;
  FileKind _selectedKind = FileKind.unsupported;
  CompressionResult? _lastResult;

  final _compressionService = CompressionService();

  static const _supportedFormats =
      'Images: JPG, JPEG, PNG, WebP, HEIC, HEIF\n'
      'Videos: MP4, MOV, M4V, AVI, MKV, WebM\n'
      'Documents: PDF';

  // ── File selection ────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif',
        'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm',
        'pdf',
      ],
      allowCompression: false,
    );

    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    setState(() {
      _selectedFile = File(path);
      _selectedKind = inferFileKind(path);
      _lastResult = null;
    });
  }

  // ── Compression ───────────────────────────────────────────────────────────

  Future<void> _compress() async {
    final input = _selectedFile;
    if (input == null || _selectedKind == FileKind.unsupported) return;

    final outputPath = await _resolveOutputPath(input, _selectedKind);
    if (outputPath == null) return; // user cancelled save dialog

    final progress = ValueNotifier<double>(0.0);
    final status = ValueNotifier<String>('Starting…');

    // Show progress dialog (non-awaited; dismissed programmatically)
    if (mounted) {
      ProgressDialog.show(
        context,
        progress: progress,
        statusMessage: status,
      );
    }

    try {
      status.value = _statusLabelFor(_selectedKind);
      final result = await _compressionService.compress(
        input,
        _selectedKind,
        outputPath,
        onProgress: (p) {
          progress.value = p;
          status.value =
              '${_statusLabelFor(_selectedKind)} ${(p * 100).toStringAsFixed(0)}%';
        },
      );

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      setState(() => _lastResult = result);

      if (mounted) {
        _showResultSnackBar(result);
      }
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      progress.dispose();
      status.dispose();
    }
  }

  Future<String?> _resolveOutputPath(File input, FileKind kind) async {
    final ext = outputExtensionFor(kind);
    final name = '${fileNameWithoutExtension(input.path)}_compressed.$ext';

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return FilePicker.platform.saveFile(
        dialogTitle: 'Save compressed file',
        fileName: name,
      );
    }

    // Mobile: save to documents directory
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$name';
  }

  String _statusLabelFor(FileKind kind) {
    switch (kind) {
      case FileKind.image:
        return 'Compressing image…';
      case FileKind.video:
        return 'Compressing video…';
      case FileKind.pdf:
        return 'Compressing PDF…';
      case FileKind.unsupported:
        return 'Processing…';
    }
  }

  void _showResultSnackBar(CompressionResult r) {
    final msg = r.improved
        ? 'Saved ${r.reductionPercent.toStringAsFixed(1)}% '
            '(${formatBytes(r.originalBytes)} → ${formatBytes(r.compressedBytes)})'
        : 'File already optimized.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(scheme),
                  const SizedBox(height: 36),
                  _buildFileCard(scheme),
                  const SizedBox(height: 12),
                  if (_lastResult != null) ...[
                    _buildResultCard(_lastResult!, scheme),
                    const SizedBox(height: 12),
                  ],
                  const Spacer(),
                  _buildActions(scheme),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [scheme.primary, scheme.secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'KIVO',
            style: TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -2,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Compress anything. Fast.',
          style: TextStyle(
            fontSize: 14,
            color: scheme.onSurface.withValues(alpha: 0.5),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildFileCard(ColorScheme scheme) {
    final hasFile = _selectedFile != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasFile
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.onSurface.withValues(alpha: 0.08),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: hasFile ? _buildFileInfo(scheme) : _buildEmptyState(scheme),
    );
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return Column(
      children: [
        Icon(
          Icons.upload_file_rounded,
          size: 48,
          color: scheme.onSurface.withValues(alpha: 0.25),
        ),
        const SizedBox(height: 12),
        Text(
          'No file selected',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap "Select File" to get started',
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }

  Widget _buildFileInfo(ColorScheme scheme) {
    final file = _selectedFile!;
    final size = file.existsSync() ? file.lengthSync() : 0;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            iconForKind(_selectedKind),
            size: 28,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fileBasename(file.path),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${formatBytes(size)}  ·  ${_kindLabel(_selectedKind)}',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.close_rounded,
            size: 20,
            color: scheme.onSurface.withValues(alpha: 0.4),
          ),
          onPressed: () => setState(() {
            _selectedFile = null;
            _selectedKind = FileKind.unsupported;
            _lastResult = null;
          }),
        ),
      ],
    );
  }

  Widget _buildResultCard(CompressionResult result, ColorScheme scheme) {
    final color = result.improved ? const Color(0xFF22C55E) : scheme.secondary;

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.improved
                    ? Icons.check_circle_rounded
                    : Icons.info_rounded,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                result.improved ? 'Compression complete' : 'Already optimized',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: color,
                ),
              ),
              if (result.improved) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '-${result.reductionPercent.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${formatBytes(result.originalBytes)}  →  ${formatBytes(result.compressedBytes)}',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            fileBasename(result.outputPath),
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActions(ColorScheme scheme) {
    final canCompress =
        _selectedFile != null && _selectedKind != FileKind.unsupported;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: _supportedFormats,
          preferBelow: false,
          child: OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open_rounded, size: 20),
            label: const Text('Select File'),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: canCompress ? _compress : null,
          icon: const Icon(Icons.compress_rounded, size: 20),
          label: const Text('Compress'),
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: scheme.primary.withValues(alpha: 0.2),
            disabledForegroundColor: scheme.primary.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }

  String _kindLabel(FileKind kind) {
    switch (kind) {
      case FileKind.image:
        return 'Image';
      case FileKind.video:
        return 'Video';
      case FileKind.pdf:
        return 'PDF';
      case FileKind.unsupported:
        return 'Unknown';
    }
  }
}
