import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/models/models.dart';
import 'package:kivo/utils/file_utils.dart';

void main() {
  group('formatBytes', () {
    test('0 bytes', () => expect(formatBytes(0), '0 B'));
    test('negative bytes', () => expect(formatBytes(-1), '0 B'));
    test('1 byte', () => expect(formatBytes(1), '1 B'));
    test('1023 bytes stays in bytes', () => expect(formatBytes(1023), '1023 B'));
    test('1024 bytes = 1.0 KB', () => expect(formatBytes(1024), '1.0 KB'));
    test('1025 bytes rounds to 1.0 KB', () => expect(formatBytes(1025), '1.0 KB'));
    test('1536 bytes = 1.5 KB', () => expect(formatBytes(1536), '1.5 KB'));
    test('1 MB', () => expect(formatBytes(1024 * 1024), '1.0 MB'));
    test('1.5 MB', () => expect(formatBytes((1.5 * 1024 * 1024).round()), '1.5 MB'));
    test('1 GB', () => expect(formatBytes(1024 * 1024 * 1024), '1.0 GB'));
  });

  group('fileBasename', () {
    test('extracts filename from path', () {
      final path = ['tmp', 'folder', 'photo.jpg'].join(Platform.pathSeparator);
      expect(fileBasename(path), 'photo.jpg');
    });

    test('filename with no directory', () {
      expect(fileBasename('file.txt'), 'file.txt');
    });

    test('nested path', () {
      final path = ['a', 'b', 'c', 'video.mp4'].join(Platform.pathSeparator);
      expect(fileBasename(path), 'video.mp4');
    });
  });

  group('fileNameWithoutExtension', () {
    test('removes single extension', () {
      expect(fileNameWithoutExtension('photo.jpg'), 'photo');
    });

    test('removes last extension for dotted names', () {
      expect(fileNameWithoutExtension('archive.tar.gz'), 'archive.tar');
    });

    test('no extension returns original', () {
      expect(fileNameWithoutExtension('Makefile'), 'Makefile');
    });

    test('hidden file with no extension', () {
      expect(fileNameWithoutExtension('.gitignore'), '');
    });

    test('full path — strips directory and extension', () {
      final path = ['tmp', 'doc.pdf'].join(Platform.pathSeparator);
      expect(fileNameWithoutExtension(path), 'doc');
    });
  });

  group('formatBytes — large values', () {
    test('1 TB', () => expect(formatBytes(1024 * 1024 * 1024 * 1024), '1.0 TB'));
    test('very large int stays numeric', () {
      final result = formatBytes(1024 * 1024 * 1024 * 1024 * 2);
      expect(result, isNotEmpty);
    });
  });

  group('fileNameWithoutExtension — edge cases', () {
    test('file with only a dot has empty name', () {
      expect(fileNameWithoutExtension('.'), '');
    });

    test('file ending with dot returns base', () {
      expect(fileNameWithoutExtension('file.'), 'file');
    });
  });

  group('inferFileKind', () {
    const imageExts = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'];
    const videoExts = ['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm'];

    for (final ext in imageExts) {
      test('.$ext → image', () {
        expect(inferFileKind('photo.$ext'), FileKind.image);
      });
    }

    for (final ext in imageExts) {
      test('.${ext.toUpperCase()} → image (case insensitive)', () {
        expect(inferFileKind('photo.${ext.toUpperCase()}'), FileKind.image);
      });
    }

    for (final ext in videoExts) {
      test('.$ext → video', () {
        expect(inferFileKind('video.$ext'), FileKind.video);
      });
    }

    test('.pdf → pdf', () {
      expect(inferFileKind('document.pdf'), FileKind.pdf);
    });

    test('.PDF → pdf (case insensitive)', () {
      expect(inferFileKind('document.PDF'), FileKind.pdf);
    });

    test('.xyz → unsupported', () {
      expect(inferFileKind('unknown.xyz'), FileKind.unsupported);
    });

    test('no extension → unsupported', () {
      expect(inferFileKind('Makefile'), FileKind.unsupported);
    });
  });

  group('outputExtensionFor', () {
    test('image → jpg', () => expect(outputExtensionFor(FileKind.image), 'jpg'));
    test('video → mp4', () => expect(outputExtensionFor(FileKind.video), 'mp4'));
    test('pdf → pdf', () => expect(outputExtensionFor(FileKind.pdf), 'pdf'));
    test('unsupported → bin', () => expect(outputExtensionFor(FileKind.unsupported), 'bin'));
  });

  group('iconForKind', () {
    test('returns distinct icons for each kind', () {
      final icons = FileKind.values.map(iconForKind).toList();
      // Each kind should have a non-null icon
      for (final icon in icons) {
        expect(icon, isNotNull);
      }
    });

    test('all icons are distinct', () {
      final icons = FileKind.values.map(iconForKind).toSet();
      expect(icons.length, FileKind.values.length);
    });
  });
}
