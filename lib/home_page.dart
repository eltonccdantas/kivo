import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'models/models.dart';
import 'services/compression_service.dart';
import 'utils/cancellation_token.dart';
import 'utils/error_utils.dart';
import 'utils/file_utils.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<QueueItem> _queue = [];
  bool _isProcessing = false;
  bool _isDragging = false;
  CancellationToken? _currentToken;
  String _appVersion = '';

  final _compressionService = CompressionService();

  static const _supportedFormats = 'Images: JPG, JPEG, PNG, WebP, HEIC, HEIF\n'
      'Videos: MP4, MOV, M4V, AVI, MKV, WebM\n'
      'Documents: PDF';

  static bool get _isDesktop =>
      !Platform.isAndroid && !Platform.isIOS;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = 'v${info.version}');
    });
  }

  // ── File selection ────────────────────────────────────────────────────────

  Future<void> _pickFiles() async {
    final useCustomFilter = Platform.isIOS;

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: useCustomFilter ? FileType.custom : FileType.any,
        allowMultiple: true,
        allowedExtensions: useCustomFilter
            ? [
                'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif',
                'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm',
                'pdf',
              ]
            : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening file picker: $e')),
        );
      }
      return;
    }

    if (result == null || result.files.isEmpty) return;
    _addFilePaths(result.files.map((f) => f.path).whereType<String>().toList());
  }

  void _addFilePaths(List<String> paths) {
    final useCustomFilter = Platform.isIOS;
    final newItems = <QueueItem>[];
    int skipped = 0;

    for (final path in paths) {
      final kind = inferFileKind(path);
      if (!useCustomFilter && kind == FileKind.unsupported) {
        skipped++;
        continue;
      }
      // Skip duplicates that are already waiting
      final alreadyQueued = _queue.any(
        (item) => item.file.path == path && item.status == QueueStatus.waiting,
      );
      if (!alreadyQueued) {
        newItems.add(QueueItem(file: File(path), kind: kind));
      }
    }

    if (newItems.isNotEmpty) {
      setState(() => _queue.addAll(newItems));
    }

    if (skipped > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$skipped unsupported file(s) skipped.'),
        ),
      );
    }
  }

  void _removeItem(QueueItem item) {
    setState(() => _queue.remove(item));
  }

  void _clearCompleted() {
    setState(() => _queue.removeWhere(
          (i) =>
              i.status == QueueStatus.done ||
              i.status == QueueStatus.error ||
              i.status == QueueStatus.cancelled,
        ));
  }

  // ── Compression queue ─────────────────────────────────────────────────────

  Future<void> _compressQueue() async {
    if (_isProcessing) return;

    final waitingItems =
        _queue.where((i) => i.status == QueueStatus.waiting).toList();
    if (waitingItems.isEmpty) return;

    setState(() => _isProcessing = true);

    for (final item in waitingItems) {
      if (!mounted) break;
      final token = CancellationToken();
      setState(() => _currentToken = token);
      await _compressItem(item, token);
      if (token.isCancelled) break;
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _currentToken = null;
      });
    }
  }

  Future<void> _compressItem(QueueItem item, CancellationToken token) async {
    final ext = outputExtensionFor(item.kind);
    final name = '${fileNameWithoutExtension(item.file.path)}_compressed.$ext';

    // Ensure the temp directory exists before use — getTemporaryDirectory()
    // returns a path that may not yet exist on macOS/desktop builds.
    final tmpDir = await getTemporaryDirectory();
    await tmpDir.create(recursive: true);
    final compressToPath = '${tmpDir.path}/$name';

    setState(() {
      item.status = QueueStatus.compressing;
      item.progress = 0.0;
      item.statusMessage = _statusLabelFor(item.kind);
    });

    try {
      final result = await _compressionService.compress(
        item.file,
        item.kind,
        compressToPath,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              item.progress = p;
              item.statusMessage =
                  '${_statusLabelFor(item.kind)} ${(p * 100).toStringAsFixed(0)}%';
            });
          }
        },
        cancellationToken: token,
      );

      // Show success dialog before asking where to save.
      if (!mounted) return;
      final confirmed = await _showSuccessDialog(result);
      if (!confirmed) {
        try { await File(compressToPath).delete(); } catch (_) {}
        if (mounted) setState(() => item.status = QueueStatus.cancelled);
        token.cancel();
        return;
      }

      final String? savedPath;
      if (_isDesktop) {
        // Desktop: save dialog returns path only — write the file manually.
        final destPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save compressed file',
          fileName: name,
        );
        if (destPath == null) {
          try { await File(compressToPath).delete(); } catch (_) {}
          if (mounted) setState(() => item.status = QueueStatus.cancelled);
          token.cancel();
          return;
        }
        await File(compressToPath).copy(destPath);
        try { await File(compressToPath).delete(); } catch (_) {}
        savedPath = destPath;
      } else {
        // Mobile: pass bytes directly so the OS handles the write.
        final bytes = await File(compressToPath).readAsBytes();
        try { await File(compressToPath).delete(); } catch (_) {}
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save compressed file',
          fileName: name,
          bytes: bytes,
        );
        if (savedPath == null) {
          if (mounted) setState(() => item.status = QueueStatus.cancelled);
          token.cancel();
          return;
        }
      }

      if (!mounted) return;
      setState(() {
        item.status = QueueStatus.done;
        item.progress = 1.0;
        item.result = CompressionResult(
          outputPath: savedPath!,
          originalBytes: result.originalBytes,
          compressedBytes: result.compressedBytes,
          improved: result.improved,
          note: result.note,
        );
      });
    } on CompressionCancelledException {
      try { await File(compressToPath).delete(); } catch (_) {}
      if (mounted) setState(() => item.status = QueueStatus.cancelled);
      token.cancel();
    } catch (e) {
      try { await File(compressToPath).delete(); } catch (_) {}
      debugPrint('[KIVO] Compression error for ${item.file.path}:\n$e');
      if (mounted) {
        setState(() {
          item.status = QueueStatus.error;
          item.errorMessage = friendlyCompressionError(e);
        });
      }
    }
  }

  void _cancelQueue() => _currentToken?.cancel();

  Future<bool> _showSuccessDialog(CompressionResult result) async {
    final scheme = Theme.of(context).colorScheme;
    final color =
        result.improved ? const Color(0xFF22C55E) : scheme.primary;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    result.improved
                        ? Icons.check_circle_rounded
                        : Icons.info_rounded,
                    color: color,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  result.improved ? 'Compression complete!' : 'File ready',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  result.improved
                      ? '${result.reductionPercent.toStringAsFixed(1)}% smaller\n'
                          '${formatBytes(result.originalBytes)} → ${formatBytes(result.compressedBytes)}'
                      : 'The file is already well-compressed.\nNo significant reduction was possible.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Discard',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ) ??
        false;
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.of(context).size.width;
    final isMobileDevice = Platform.isAndroid || Platform.isIOS;
    final isWide = isMobileDevice && width >= 600;

    Widget body = isWide
        ? _buildWideLayout(scheme)
        : _buildNarrowLayout(scheme);

    if (_isDesktop) {
      body = DropTarget(
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (detail) {
          setState(() => _isDragging = false);
          _addFilePaths(detail.files.map((f) => f.path).toList());
        },
        child: body,
      );
    }

    return Scaffold(body: SafeArea(child: body));
  }

  Widget _buildWideLayout(ColorScheme scheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 24, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(scheme, compact: true),
                    const SizedBox(height: 20),
                    _buildQueueArea(scheme),
                  ],
                ),
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: scheme.onSurface.withValues(alpha: 0.08),
            ),
            SizedBox(
              width: 268,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 28, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    _buildActions(scheme),
                    const SizedBox(height: 20),
                    _buildFooter(scheme),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNarrowLayout(ColorScheme scheme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(scheme),
                    const SizedBox(height: 28),
                    _buildQueueArea(scheme),
                    const Spacer(),
                    _buildActions(scheme),
                    const SizedBox(height: 20),
                    _buildFooter(scheme),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Queue area ────────────────────────────────────────────────────────────

  Widget _buildQueueArea(ColorScheme scheme) {
    if (_queue.isEmpty) return _buildDropZone(scheme);

    final hasCompleted = _queue.any(
      (i) =>
          i.status == QueueStatus.done ||
          i.status == QueueStatus.error ||
          i.status == QueueStatus.cancelled,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isDragging) _buildDragOverlay(scheme),
        ..._queue.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildQueueItemCard(item, scheme),
          ),
        ),
        if (hasCompleted) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _clearCompleted,
            icon: const Icon(Icons.clear_all_rounded, size: 18),
            label: const Text('Clear completed'),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDropZone(ColorScheme scheme) {
    final isDragging = _isDragging;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isDragging
            ? scheme.primary.withValues(alpha: 0.06)
            : scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDragging
              ? scheme.primary.withValues(alpha: 0.6)
              : scheme.onSurface.withValues(alpha: 0.08),
          width: isDragging ? 2 : 1.5,
        ),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            isDragging
                ? Icons.file_download_rounded
                : (_isDesktop
                    ? Icons.file_upload_outlined
                    : Icons.upload_file_rounded),
            size: 48,
            color: isDragging
                ? scheme.primary.withValues(alpha: 0.7)
                : scheme.onSurface.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 12),
          Text(
            isDragging
                ? 'Release to add files'
                : (_isDesktop ? 'Drop files here' : 'No files selected'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDragging
                  ? scheme.primary.withValues(alpha: 0.8)
                  : scheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 4),
          if (!isDragging)
            Text(
              _isDesktop
                  ? 'or tap "Add Files" to browse'
                  : 'Tap "Add Files" to get started',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDragOverlay(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.file_download_rounded,
              size: 16, color: scheme.primary.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Text(
            'Release to add to queue',
            style: TextStyle(
              fontSize: 13,
              color: scheme.primary.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueItemCard(QueueItem item, ColorScheme scheme) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _borderColorFor(item, scheme),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _iconBgColorFor(item, scheme),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  iconForKind(item.kind),
                  size: 20,
                  color: _iconColorFor(item, scheme),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileBasename(item.file.path),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitleFor(item),
                      style: TextStyle(
                        fontSize: 12,
                        color: _subtitleColorFor(item, scheme),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildItemTrailing(item, scheme),
            ],
          ),
          if (item.status == QueueStatus.compressing) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: item.progress > 0 ? item.progress : null,
                backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemTrailing(QueueItem item, ColorScheme scheme) {
    switch (item.status) {
      case QueueStatus.waiting:
        return IconButton(
          icon: Icon(
            Icons.close_rounded,
            size: 18,
            color: scheme.onSurface.withValues(alpha: 0.4),
          ),
          onPressed: _isProcessing ? null : () => _removeItem(item),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        );
      case QueueStatus.compressing:
        return const SizedBox.shrink();
      case QueueStatus.done:
        final result = item.result;
        if (result != null && result.improved) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '-${result.reductionPercent.toStringAsFixed(1)}%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF22C55E),
              ),
            ),
          );
        }
        return const Icon(Icons.check_circle_rounded,
            size: 20, color: Color(0xFF22C55E));
      case QueueStatus.error:
        return Icon(Icons.error_outline_rounded,
            size: 20, color: scheme.error);
      case QueueStatus.cancelled:
        return Icon(Icons.cancel_outlined,
            size: 20, color: scheme.onSurface.withValues(alpha: 0.35));
    }
  }

  Color _borderColorFor(QueueItem item, ColorScheme scheme) {
    switch (item.status) {
      case QueueStatus.waiting:
        return scheme.onSurface.withValues(alpha: 0.08);
      case QueueStatus.compressing:
        return scheme.primary.withValues(alpha: 0.5);
      case QueueStatus.done:
        return const Color(0xFF22C55E).withValues(alpha: 0.4);
      case QueueStatus.error:
        return scheme.error.withValues(alpha: 0.4);
      case QueueStatus.cancelled:
        return scheme.onSurface.withValues(alpha: 0.06);
    }
  }

  Color _iconBgColorFor(QueueItem item, ColorScheme scheme) {
    switch (item.status) {
      case QueueStatus.waiting:
        return scheme.onSurface.withValues(alpha: 0.07);
      case QueueStatus.compressing:
        return scheme.primary.withValues(alpha: 0.12);
      case QueueStatus.done:
        return const Color(0xFF22C55E).withValues(alpha: 0.12);
      case QueueStatus.error:
        return scheme.error.withValues(alpha: 0.12);
      case QueueStatus.cancelled:
        return scheme.onSurface.withValues(alpha: 0.05);
    }
  }

  Color _iconColorFor(QueueItem item, ColorScheme scheme) {
    switch (item.status) {
      case QueueStatus.waiting:
        return scheme.onSurface.withValues(alpha: 0.5);
      case QueueStatus.compressing:
        return scheme.primary;
      case QueueStatus.done:
        return const Color(0xFF22C55E);
      case QueueStatus.error:
        return scheme.error;
      case QueueStatus.cancelled:
        return scheme.onSurface.withValues(alpha: 0.35);
    }
  }

  String _subtitleFor(QueueItem item) {
    final size = item.file.existsSync() ? item.file.lengthSync() : 0;
    switch (item.status) {
      case QueueStatus.waiting:
        return '${formatBytes(size)}  ·  ${_kindLabel(item.kind)}';
      case QueueStatus.compressing:
        final pct = (item.progress * 100).toStringAsFixed(0);
        return '${_statusLabelFor(item.kind)}  ·  $pct%';
      case QueueStatus.done:
        final result = item.result;
        if (result != null && result.improved) {
          return '${formatBytes(result.originalBytes)} → ${formatBytes(result.compressedBytes)}';
        }
        return 'Saved · already well-compressed';
      case QueueStatus.error:
        return item.errorMessage ?? 'Compression failed';
      case QueueStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color _subtitleColorFor(QueueItem item, ColorScheme scheme) {
    switch (item.status) {
      case QueueStatus.waiting:
        return scheme.onSurface.withValues(alpha: 0.5);
      case QueueStatus.compressing:
        return scheme.primary.withValues(alpha: 0.8);
      case QueueStatus.done:
        return const Color(0xFF22C55E).withValues(alpha: 0.8);
      case QueueStatus.error:
        return scheme.error;
      case QueueStatus.cancelled:
        return scheme.onSurface.withValues(alpha: 0.35);
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Widget _buildActions(ColorScheme scheme) {
    final waitingCount =
        _queue.where((i) => i.status == QueueStatus.waiting).length;
    final compressLabel = waitingCount > 1
        ? 'Compress All ($waitingCount)'
        : 'Compress';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: _supportedFormats,
          preferBelow: false,
          child: OutlinedButton.icon(
            onPressed: _isProcessing ? null : _pickFiles,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add Files'),
          ),
        ),
        const SizedBox(height: 12),
        if (_isProcessing)
          OutlinedButton.icon(
            onPressed: _cancelQueue,
            icon: const Icon(Icons.stop_rounded, size: 20),
            label: const Text('Cancel'),
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: waitingCount > 0 ? _compressQueue : null,
            icon: const Icon(Icons.compress_rounded, size: 20),
            label: Text(compressLabel),
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

  // ── Header / Footer ───────────────────────────────────────────────────────

  Widget _buildHeader(ColorScheme scheme, {bool compact = false}) {
    final logoSize = compact ? 64.0 : 100.0;
    final titleSize = compact ? 32.0 : 42.0;

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
          child: Image.asset(
            'assets/images/logo.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'KIVO',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.5,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Offline. Safe.',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _showInfoModal(context, scheme),
          icon: Icon(
            Icons.help_outline_rounded,
            color: scheme.onSurface.withValues(alpha: 0.45),
            size: 24,
          ),
          tooltip: 'About KIVO',
        ),
      ],
    );
  }

  void _showInfoModal(BuildContext ctx, ColorScheme scheme) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InfoSheet(scheme: scheme),
    );
  }

  Widget _buildFooter(ColorScheme scheme) {
    return Column(
      children: [
        Text(
          'eltondantas.com =)',
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.35),
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          _appVersion,
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurface.withValues(alpha: 0.22),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ── Info modal ────────────────────────────────────────────────────────────────

class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.info_outline_rounded,
                            color: scheme.primary, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'About KIVO',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _Section(
                    scheme: scheme,
                    icon: Icons.lock_outline_rounded,
                    iconColor: const Color(0xFF22C55E),
                    title: 'Your files never leave your device',
                    body: 'Everything happens locally. KIVO does not upload, '
                        'send, or store your files anywhere. No internet '
                        'connection is needed — not even for setup.',
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    scheme: scheme,
                    icon: Icons.auto_fix_high_rounded,
                    iconColor: scheme.primary,
                    title: 'Smart compression',
                    body: 'KIVO analyses each file and applies the best '
                        'algorithm for its type:\n\n'
                        '• Images — re-encoded at a slightly lower quality '
                        'that is imperceptible to the eye.\n'
                        '• Videos — transcoded to HEVC (H.265), the same '
                        'standard used by modern phones.\n'
                        '• PDFs — images inside the document are optimised '
                        'without affecting text or layout.',
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    scheme: scheme,
                    icon: Icons.folder_open_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    title: 'Supported formats',
                    body: '',
                    child: _FormatsGrid(scheme: scheme),
                  ),
                  const SizedBox(height: 16),
                  _Section(
                    scheme: scheme,
                    icon: Icons.lightbulb_outline_rounded,
                    iconColor: const Color(0xFF818CF8),
                    title: 'Good to know',
                    body: '• Results vary by file — a heavily compressed video '
                        'may not shrink much further.\n'
                        '• The original file is never modified or deleted.\n'
                        '• Video compression can take a minute or two for '
                        'large files.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.scheme,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.child,
  });

  final ColorScheme scheme;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.onSurface.withValues(alpha: 0.07),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              body,
              style: TextStyle(
                fontSize: 14,
                height: 1.55,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
          if (child != null) ...[
            const SizedBox(height: 12),
            child!,
          ],
        ],
      ),
    );
  }
}

class _FormatsGrid extends StatelessWidget {
  const _FormatsGrid({required this.scheme});
  final ColorScheme scheme;

  static const _groups = [
    (Icons.image_outlined, 'Images', 'JPG · JPEG · PNG\nWebP · HEIC · HEIF'),
    (Icons.videocam_outlined, 'Videos', 'MP4 · MOV · M4V\nAVI · MKV · WebM'),
    (Icons.picture_as_pdf_outlined, 'Documents', 'PDF'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _groups
          .map(
            (g) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(g.$1,
                      size: 18,
                      color: scheme.onSurface.withValues(alpha: 0.45)),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.$2,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                      Text(
                        g.$3,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}
