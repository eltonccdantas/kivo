import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/services/json_service.dart';
import 'package:kivo/utils/cancellation_token.dart';

void main() {
  late Directory tmpDir;
  late JsonService service;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('kivo_json_test_');
    service = JsonService();
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  Future<File> write(String name, String content) async {
    final f = File('${tmpDir.path}/$name');
    await f.writeAsString(content);
    return f;
  }

  // ── Minification ──────────────────────────────────────────────────────────

  group('minification', () {
    test('minifies pretty-printed object', () async {
      final input = await write('in.json', '''
{
  "name": "kivo",
  "version": "3.0.0",
  "nested": {
    "key": "value"
  }
}
''');
      final out = '${tmpDir.path}/out.json';
      final result = await service.compress(input, out);

      expect(result.improved, isTrue);
      expect(result.compressedBytes, lessThan(result.originalBytes));
      expect(await File(out).readAsString(), isNot(contains('\n')));
    });

    test('minifies pretty-printed array', () async {
      final input = await write('in.json', '''
[
  { "id": 1 },
  { "id": 2 },
  { "id": 3 }
]
''');
      final out = '${tmpDir.path}/out.json';
      final result = await service.compress(input, out);

      expect(result.improved, isTrue);
      final decoded = jsonDecode(await File(out).readAsString());
      expect(decoded, isA<List>());
      expect((decoded as List).length, 3);
    });

    test('detects already-minified JSON as not improved', () async {
      final input = await write('in.json', '{"name":"kivo","v":1}');
      final out = '${tmpDir.path}/out.json';
      final result = await service.compress(input, out);

      expect(result.improved, isFalse);
      expect(result.note, contains('already minified'));
    });

    test('strips UTF-8 BOM before parsing', () async {
      // BOM is \uFEFF (3 UTF-8 bytes) — some Windows tools prepend it.
      // After stripping the BOM the content is valid JSON and the output
      // is smaller (BOM removed), so the service reports improved = true.
      final input = await write('in.json', '\uFEFF{"key":"value"}');
      final out = '${tmpDir.path}/out.json';
      await service.compress(input, out);

      // Parsing must succeed and data must be intact.
      final decoded = jsonDecode(await File(out).readAsString());
      expect(decoded['key'], 'value');
      // Output must not start with the BOM character.
      expect(await File(out).readAsString(), isNot(startsWith('\uFEFF')));
    });
  });

  // ── Data integrity ─────────────────────────────────────────────────────────

  group('data integrity', () {
    test('preserves all JSON types', () async {
      final original = {
        'string': 'hello world',
        'integer': 42,
        'float': 3.14,
        'bool_true': true,
        'bool_false': false,
        'null_val': null,
        'array': [1, 'two', false, null],
        'nested': {'a': 'b'},
      };
      final input = await write(
          'in.json', const JsonEncoder.withIndent('  ').convert(original));
      final out = '${tmpDir.path}/out.json';
      await service.compress(input, out);

      final decoded = jsonDecode(await File(out).readAsString());
      expect(decoded, equals(original));
    });

    test('preserves unicode strings', () async {
      final input = await write('in.json',
          const JsonEncoder.withIndent('  ').convert({'msg': 'こんにちは 🌍'}));
      final out = '${tmpDir.path}/out.json';
      await service.compress(input, out);

      final decoded = jsonDecode(await File(out).readAsString());
      expect(decoded['msg'], 'こんにちは 🌍');
    });

    test('preserves deeply nested structure', () async {
      final deep = {'l1': {'l2': {'l3': {'l4': {'value': 99}}}}};
      final input = await write(
          'in.json', const JsonEncoder.withIndent('  ').convert(deep));
      final out = '${tmpDir.path}/out.json';
      await service.compress(input, out);

      expect(jsonDecode(await File(out).readAsString()), equals(deep));
    });

    test('preserves large array', () async {
      final arr = List.generate(100, (i) => {'id': i, 'name': 'item_$i'});
      final input = await write(
          'in.json', const JsonEncoder.withIndent('  ').convert(arr));
      final out = '${tmpDir.path}/out.json';
      await service.compress(input, out);

      final decoded =
          (jsonDecode(await File(out).readAsString()) as List).cast<Map>();
      expect(decoded.length, 100);
      expect(decoded[42]['name'], 'item_42');
    });
  });

  // ── Error handling ─────────────────────────────────────────────────────────

  group('error handling', () {
    test('throws on invalid JSON', () async {
      final input = await write('in.json', '{ not valid json }');
      expect(
        () => service.compress(input, '${tmpDir.path}/out.json'),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'msg', contains('Invalid JSON'))),
      );
    });

    test('throws on empty file', () async {
      final input = await write('in.json', '');
      expect(
        () => service.compress(input, '${tmpDir.path}/out.json'),
        throwsA(isA<Exception>()),
      );
    });

    test('throws on truncated JSON', () async {
      final input = await write('in.json', '{"key": "val');
      expect(
        () => service.compress(input, '${tmpDir.path}/out.json'),
        throwsA(isA<Exception>()),
      );
    });

    test('error message is user-friendly (no raw stack trace)', () async {
      final input = await write('in.json', 'not json at all');
      try {
        await service.compress(input, '${tmpDir.path}/out.json');
        fail('should have thrown');
      } on Exception catch (e) {
        expect(e.toString(), contains('Invalid JSON file'));
      }
    });
  });

  // ── Cancellation ──────────────────────────────────────────────────────────

  group('cancellation', () {
    test('pre-cancelled token throws immediately', () async {
      final input = await write('in.json', '{"key": "value"}');
      final token = CancellationToken()..cancel();
      expect(
        () => service.compress(input, '${tmpDir.path}/out.json',
            cancellationToken: token),
        throwsA(isA<CompressionCancelledException>()),
      );
    });

    test('cancelling after read throws before write', () async {
      final input = await write('in.json',
          const JsonEncoder.withIndent('  ').convert({'a': 1, 'b': 2}));
      final out = '${tmpDir.path}/out.json';
      final token = CancellationToken();
      var cancelled = false;

      try {
        await service.compress(
          input,
          out,
          cancellationToken: token,
          onProgress: (p) {
            if (p >= 0.4) token.cancel();
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
      final input = await write(
          'in.json',
          const JsonEncoder.withIndent('  ')
              .convert({'a': 1, 'b': 2, 'c': 3}));
      final progresses = <double>[];
      await service.compress(input, '${tmpDir.path}/out.json',
          onProgress: progresses.add);

      expect(progresses, isNotEmpty);
      for (var i = 1; i < progresses.length; i++) {
        expect(progresses[i], greaterThanOrEqualTo(progresses[i - 1]));
      }
    });

    test('last reported progress is 1.0', () async {
      final input = await write('in.json',
          const JsonEncoder.withIndent('  ').convert({'key': 'value'}));
      double? last;
      await service.compress(input, '${tmpDir.path}/out.json',
          onProgress: (p) => last = p);
      expect(last, 1.0);
    });

    test('works without a progress callback', () async {
      final input = await write('in.json', '{"x":1}');
      await expectLater(
        service.compress(input, '${tmpDir.path}/out.json'),
        completes,
      );
    });
  });

  // ── Result fields ──────────────────────────────────────────────────────────

  group('result fields', () {
    test('outputPath matches the provided path', () async {
      final input = await write('in.json',
          const JsonEncoder.withIndent('  ').convert({'k': 'v'}));
      final out = '${tmpDir.path}/out.json';
      final result = await service.compress(input, out);
      expect(result.outputPath, out);
    });

    test('originalBytes matches input file size', () async {
      final content =
          const JsonEncoder.withIndent('  ').convert({'k': 'v'});
      final input = await write('in.json', content);
      final result =
          await service.compress(input, '${tmpDir.path}/out.json');
      expect(result.originalBytes, await input.length());
    });

    test('note mentions whitespace when improved', () async {
      final input = await write(
          'in.json', const JsonEncoder.withIndent('  ').convert({'a': 1}));
      final result =
          await service.compress(input, '${tmpDir.path}/out.json');
      if (result.improved) {
        expect(result.note.toLowerCase(), contains('whitespace'));
      }
    });
  });
}
