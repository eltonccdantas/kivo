import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import '../models/models.dart';

String fileBasename(String path) => path.split(Platform.pathSeparator).last;

String fileNameWithoutExtension(String path) {
  final base = fileBasename(path);
  final dot = base.lastIndexOf('.');
  return dot == -1 ? base : base.substring(0, dot);
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  const suffixes = ['KB', 'MB', 'GB', 'TB'];
  final i = (math.log(bytes) / math.log(1024)).floor().clamp(1, suffixes.length);
  final value = bytes / math.pow(1024, i);
  return '${value.toStringAsFixed(1)} ${suffixes[i - 1]}';
}

FileKind inferFileKind(String path) {
  final ext = path.split('.').last.toLowerCase();
  const imageExts = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'};
  const videoExts = {'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm'};
  if (ext == 'pdf') return FileKind.pdf;
  if (ext == 'json') return FileKind.json;
  if (ext == 'xml') return FileKind.xml;
  if (ext == 'yaml' || ext == 'yml') return FileKind.yaml;
  if (imageExts.contains(ext)) return FileKind.image;
  if (videoExts.contains(ext)) return FileKind.video;
  final mime = lookupMimeType(path) ?? '';
  if (mime.startsWith('image/')) return FileKind.image;
  if (mime.startsWith('video/')) return FileKind.video;
  if (mime == 'application/pdf') return FileKind.pdf;
  if (mime == 'application/json') return FileKind.json;
  if (mime == 'application/xml' || mime == 'text/xml') return FileKind.xml;
  if (mime == 'application/yaml' || mime == 'text/yaml') return FileKind.yaml;
  return FileKind.unsupported;
}

String outputExtensionFor(FileKind kind) {
  switch (kind) {
    case FileKind.image:
      return 'jpg';
    case FileKind.video:
      return 'mp4';
    case FileKind.pdf:
      return 'pdf';
    case FileKind.json:
      return 'json';
    case FileKind.xml:
      return 'xml';
    case FileKind.yaml:
      return 'yaml';
    case FileKind.unsupported:
      return 'bin';
  }
}

IconData iconForKind(FileKind kind) {
  switch (kind) {
    case FileKind.image:
      return Icons.image_outlined;
    case FileKind.video:
      return Icons.videocam_outlined;
    case FileKind.pdf:
      return Icons.picture_as_pdf_outlined;
    case FileKind.json:
      return Icons.data_object_outlined;
    case FileKind.xml:
      return Icons.code_outlined;
    case FileKind.yaml:
      return Icons.text_snippet_outlined;
    case FileKind.unsupported:
      return Icons.insert_drive_file_outlined;
  }
}
