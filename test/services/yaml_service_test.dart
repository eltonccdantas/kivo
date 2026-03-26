import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/services/yaml_service.dart';
import 'package:kivo/utils/cancellation_token.dart';

void main() {
  late Directory tmpDir;
  late YamlService service;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('kivo_yaml_test_');
    service = YamlService();
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  Future<File> write(String name, String content) async {
    final f = File('${tmpDir.path}/$name');
    await f.writeAsString(content);
    return f;
  }

  // ── Comment removal ────────────────────────────────────────────────────────

  group('comment removal', () {
    test('removes full-line comments', () async {
      final input = await write('in.yaml', '''
# This is a comment
name: kivo
# Another comment
version: 3.0.0
''');
      final out = '${tmpDir.path}/out.yaml';
      final result = await service.compress(input, out);

      expect(result.improved, isTrue);
      final lines = await File(out).readAsLines();
      expect(lines.any((l) => l.trimLeft().startsWith('#')), isFalse);
      expect(lines, contains('name: kivo'));
      expect(lines, contains('version: 3.0.0'));
    });

    test('removes indented comments', () async {
      final input = await write('in.yaml', '''
parent:
  # indented comment
  child: value
''');
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      final lines = await File(out).readAsLines();
      expect(lines.any((l) => l.contains('#')), isFalse);
      expect(lines.any((l) => l.contains('child: value')), isTrue);
    });

    test('removes inline comments after values', () async {
      final input = await write('in.yaml', '''
host: localhost # the database host
port: 5432 # default postgres port
''');
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      final content = await File(out).readAsString();
      expect(content, isNot(contains('the database host')));
      expect(content, isNot(contains('default postgres port')));
      expect(content, contains('host: localhost'));
      expect(content, contains('port: 5432'));
    });

    test('preserves # inside double-quoted strings', () async {
      final input = await write('in.yaml', 'key: "value#notacomment"\n');
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      expect(await File(out).readAsString(), contains('"value#notacomment"'));
    });

    test('preserves # inside single-quoted strings', () async {
      final input = await write('in.yaml', "key: 'value#notacomment'\n");
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      expect(await File(out).readAsString(), contains("'value#notacomment'"));
    });

    test('preserves URL with # fragment in unquoted value', () async {
      // YAML: unquoted "http://x.com#frag" is fine; the # must be preceded
      // by a space to be treated as a comment (per spec).
      final input =
          await write('in.yaml', 'url: http://example.com#fragment\n');
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      expect(await File(out).readAsString(),
          contains('http://example.com#fragment'));
    });

    test('strips inline comment separated by space from URL', () async {
      // "http://example.com #comment" — the space before # makes it a comment.
      final input =
          await write('in.yaml', 'url: http://example.com #comment\n');
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      final content = await File(out).readAsString();
      expect(content, isNot(contains('#comment')));
      expect(content, contains('http://example.com'));
    });

    test("preserves hash in single-quoted string with escaped quote ('it''s')",
        () async {
      final input =
          await write('in.yaml', "msg: 'it''s a #hash value'\n");
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      // The # is inside the single-quoted string — must be preserved.
      expect(await File(out).readAsString(), contains('#hash value'));
    });
  });

  // ── Blank line removal ─────────────────────────────────────────────────────

  group('blank line removal', () {
    test('removes blank lines between keys', () async {
      final input = await write('in.yaml', '''
name: kivo

version: 3.0.0

description: compressor
''');
      final out = '${tmpDir.path}/out.yaml';
      final result = await service.compress(input, out);

      expect(result.improved, isTrue);
      final lines = await File(out).readAsLines();
      expect(lines.where((l) => l.isEmpty).length, 0);
    });

    test('removes lines that are only whitespace', () async {
      final input = await write('in.yaml', 'a: 1\n   \nb: 2\n');
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      final lines = await File(out).readAsLines();
      expect(lines.every((l) => l.isNotEmpty), isTrue);
    });
  });

  // ── Structure preservation ─────────────────────────────────────────────────

  group('structure preservation', () {
    test('preserves indentation of nested keys', () async {
      final input = await write('in.yaml', '''
# App config
app:
  # Server settings
  server:
    host: localhost
    port: 8080
  # Database settings
  database:
    host: db.local
    port: 5432
''');
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      final content = await File(out).readAsString();
      expect(content, contains('  server:'));
      expect(content, contains('    host: localhost'));
      expect(content, contains('    port: 8080'));
    });

    test('preserves list items with dashes', () async {
      final input = await write('in.yaml', '''
# Fruits
fruits:
  - apple
  - banana
  - cherry
''');
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      final lines = await File(out).readAsLines();
      expect(lines.where((l) => l.trim().startsWith('-')).length, 3);
    });

    test('preserves multiline block scalar content lines', () async {
      // NOTE: blank lines INSIDE block scalars may be removed by the current
      // implementation. This test documents current behaviour.
      final input = await write('in.yaml', '''
description: |
  Line one
  Line two
  Line three
''');
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      final content = await File(out).readAsString();
      expect(content, contains('Line one'));
      expect(content, contains('Line two'));
      expect(content, contains('Line three'));
    });

    test('handles CRLF line endings', () async {
      final input = await write('in.yaml', '# comment\r\nkey: value\r\n');
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      final content = await File(out).readAsString();
      expect(content, contains('key: value'));
      expect(content, isNot(contains('# comment')));
    });

    test('output ends with a single newline', () async {
      final input = await write('in.yaml', '# comment\nkey: value\n');
      final out = '${tmpDir.path}/out.yaml';
      await service.compress(input, out);

      final content = await File(out).readAsString();
      expect(content, endsWith('\n'));
      expect(content, isNot(endsWith('\n\n')));
    });
  });

  // ── Already minified ───────────────────────────────────────────────────────

  group('already minified', () {
    test('detects file with no comments or blank lines as not improved',
        () async {
      final input = await write('in.yaml', 'name: kivo\nversion: 3.0.0\n');
      final out = '${tmpDir.path}/out.yaml';
      final result = await service.compress(input, out);

      expect(result.improved, isFalse);
      expect(result.note, contains('already minified'));
    });
  });

  // ── Error handling ─────────────────────────────────────────────────────────

  group('error handling', () {
    test('throws when file contains only comments', () async {
      final input = await write('in.yaml', '''
# Just a comment
# Another comment
''');
      expect(
        () => service.compress(input, '${tmpDir.path}/out.yaml'),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'msg', contains('empty'))),
      );
    });

    test('throws on empty file', () async {
      final input = await write('in.yaml', '');
      expect(
        () => service.compress(input, '${tmpDir.path}/out.yaml'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ── Cancellation ──────────────────────────────────────────────────────────

  group('cancellation', () {
    test('pre-cancelled token throws immediately', () async {
      final input = await write('in.yaml', 'key: value\n');
      final token = CancellationToken()..cancel();
      expect(
        () => service.compress(input, '${tmpDir.path}/out.yaml',
            cancellationToken: token),
        throwsA(isA<CompressionCancelledException>()),
      );
    });

    test('cancelling after read throws before write', () async {
      final input = await write('in.yaml', '''
# comment
name: kivo
version: 3.0.0
''');
      final out = '${tmpDir.path}/out.yaml';
      final token = CancellationToken();
      var cancelled = false;

      try {
        await service.compress(
          input,
          out,
          cancellationToken: token,
          onProgress: (p) {
            if (p >= 0.5) token.cancel();
          },
        );
      } on CompressionCancelledException {
        cancelled = true;
      }

      expect(cancelled, isTrue);
    });
  });

  // ── Progress callbacks ─────────────────────────────────────────────────────

  group('progress callbacks', () {
    test('reports progress in non-decreasing order', () async {
      final input = await write('in.yaml', '''
# Config
name: kivo
version: 3.0.0
''');
      final progresses = <double>[];
      await service.compress(input, '${tmpDir.path}/out.yaml',
          onProgress: progresses.add);

      expect(progresses, isNotEmpty);
      for (var i = 1; i < progresses.length; i++) {
        expect(progresses[i], greaterThanOrEqualTo(progresses[i - 1]));
      }
    });

    test('last reported progress is 1.0', () async {
      final input = await write('in.yaml', '# comment\nkey: val\n');
      double? last;
      await service.compress(input, '${tmpDir.path}/out.yaml',
          onProgress: (p) => last = p);
      expect(last, 1.0);
    });
  });

  // ── Real-world fixtures ────────────────────────────────────────────────────

  group('real-world fixtures', () {
    test('compresses GitHub Actions workflow YAML', () async {
      final input = await write('workflow.yaml', '''
# GitHub Actions workflow
name: CI

# Trigger on push and PR
on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

jobs:
  # Build and test job
  build:
    runs-on: ubuntu-latest

    steps:
      # Check out the code
      - uses: actions/checkout@v3

      # Set up Flutter
      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x' # latest stable

      # Get dependencies
      - name: Get dependencies
        run: flutter pub get # install packages

      # Run tests
      - name: Run tests
        run: flutter test
''');
      final out = '${tmpDir.path}/out.yaml';
      final result = await service.compress(input, out);

      expect(result.improved, isTrue);
      final content = await File(out).readAsString();
      // Key structure preserved
      expect(content, contains('name: CI'));
      expect(content, contains('runs-on: ubuntu-latest'));
      expect(content, contains('run: flutter test'));
      // Comments stripped
      expect(content, isNot(contains('GitHub Actions workflow')));
      expect(content, isNot(contains('Trigger on push')));
    });

    test('compresses docker-compose YAML', () async {
      final input = await write('docker-compose.yaml', '''
# Docker Compose configuration
version: '3.8'

services:
  # Web application service
  web:
    image: nginx:latest # use latest nginx
    ports:
      - "80:80" # HTTP
      - "443:443" # HTTPS
    volumes:
      - ./html:/usr/share/nginx/html

  # Database service
  db:
    image: postgres:15
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: secret # change in production
      POSTGRES_DB: myapp
''');
      final out = '${tmpDir.path}/out.yaml';
      final result = await service.compress(input, out);

      expect(result.improved, isTrue);
      final content = await File(out).readAsString();
      expect(content, contains("version: '3.8'"));
      expect(content, contains('image: nginx:latest'));
      expect(content, contains('POSTGRES_USER: admin'));
      expect(content, isNot(contains('Docker Compose')));
      expect(content, isNot(contains('change in production')));
    });
  });
}
