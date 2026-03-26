import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/services/xml_service.dart';
import 'package:kivo/utils/cancellation_token.dart';
import 'package:xml/xml.dart';

void main() {
  late Directory tmpDir;
  late XmlService service;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('kivo_xml_test_');
    service = XmlService();
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
    test('minifies pretty-printed XML', () async {
      final input = await write('in.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<root>
  <item id="1">
    <name>Alpha</name>
    <value>100</value>
  </item>
  <item id="2">
    <name>Beta</name>
    <value>200</value>
  </item>
</root>
''');
      final out = '${tmpDir.path}/out.xml';
      final result = await service.compress(input, out);

      expect(result.improved, isTrue);
      expect(result.compressedBytes, lessThan(result.originalBytes));
      final outContent = await File(out).readAsString();
      expect(outContent, isNot(contains('\n  ')));
    });

    test('detects already-minified XML as not improved', () async {
      const minified =
          '<?xml version="1.0"?><root><item id="1"><name>A</name></item></root>';
      final input = await write('in.xml', minified);
      final out = '${tmpDir.path}/out.xml';
      final result = await service.compress(input, out);

      expect(result.improved, isFalse);
      expect(result.note, contains('already minified'));
    });

    test('strips UTF-8 BOM before parsing', () async {
      final input =
          await write('in.xml', '\uFEFF<?xml version="1.0"?><r><a>1</a></r>');
      final out = '${tmpDir.path}/out.xml';
      await expectLater(service.compress(input, out), completes);
    });

    test('output is valid XML', () async {
      final input = await write('in.xml', '''
<config>
  <database>
    <host>localhost</host>
    <port>5432</port>
  </database>
</config>
''');
      final out = '${tmpDir.path}/out.xml';
      await service.compress(input, out);

      // Must parse without throwing
      final parsed = XmlDocument.parse(await File(out).readAsString());
      expect(parsed.rootElement.name.local, 'config');
    });
  });

  // ── Data integrity ─────────────────────────────────────────────────────────

  group('data integrity', () {
    test('preserves element count', () async {
      final input = await write('in.xml', '''
<items>
  <item>one</item>
  <item>two</item>
  <item>three</item>
</items>
''');
      final out = '${tmpDir.path}/out.xml';
      await service.compress(input, out);

      final doc = XmlDocument.parse(await File(out).readAsString());
      expect(doc.rootElement.children.whereType<XmlElement>().length, 3);
    });

    test('preserves attributes', () async {
      final input = await write('in.xml', '''
<root>
  <node id="42" class="primary" active="true" />
</root>
''');
      final out = '${tmpDir.path}/out.xml';
      await service.compress(input, out);

      final doc = XmlDocument.parse(await File(out).readAsString());
      final node = doc.rootElement.getElement('node')!;
      expect(node.getAttribute('id'), '42');
      expect(node.getAttribute('class'), 'primary');
      expect(node.getAttribute('active'), 'true');
    });

    test('preserves text content', () async {
      final input = await write('in.xml', '''
<root>
  <title>  Hello World  </title>
  <description>Some text here</description>
</root>
''');
      final out = '${tmpDir.path}/out.xml';
      await service.compress(input, out);

      final doc = XmlDocument.parse(await File(out).readAsString());
      expect(
          doc.rootElement.getElement('description')!.innerText, 'Some text here');
    });

    test('preserves namespaces', () async {
      final input = await write('in.xml', '''
<root xmlns:ns="http://example.com/ns">
  <ns:element>value</ns:element>
</root>
''');
      final out = '${tmpDir.path}/out.xml';
      await service.compress(input, out);

      final doc = XmlDocument.parse(await File(out).readAsString());
      expect(doc.rootElement, isNotNull);
    });

    test('preserves XML declaration', () async {
      const xmlDecl = '<?xml version="1.0" encoding="UTF-8"?>';
      final input = await write('in.xml', '$xmlDecl\n<root><a>1</a></root>\n');
      final out = '${tmpDir.path}/out.xml';
      await service.compress(input, out);

      final outContent = await File(out).readAsString();
      expect(outContent, startsWith('<?xml'));
    });

    test('preserves CDATA sections', () async {
      final input = await write('in.xml', '''
<root>
  <script>
    <![CDATA[
      function foo() { return 1 < 2; }
    ]]>
  </script>
</root>
''');
      final out = '${tmpDir.path}/out.xml';
      await service.compress(input, out);

      final outContent = await File(out).readAsString();
      expect(outContent, contains('CDATA'));
      expect(outContent, contains('function foo'));
    });
  });

  // ── Error handling ─────────────────────────────────────────────────────────

  group('error handling', () {
    test('throws on malformed XML (unclosed tag)', () async {
      final input = await write('in.xml', '<root><unclosed></root>');
      expect(
        () => service.compress(input, '${tmpDir.path}/out.xml'),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'msg', contains('Invalid XML'))),
      );
    });

    test('throws on empty file', () async {
      final input = await write('in.xml', '');
      expect(
        () => service.compress(input, '${tmpDir.path}/out.xml'),
        throwsA(isA<Exception>()),
      );
    });

    test('throws on plain text (not XML)', () async {
      final input = await write('in.xml', 'this is not xml at all');
      expect(
        () => service.compress(input, '${tmpDir.path}/out.xml'),
        throwsA(isA<Exception>()),
      );
    });

    test('error message is user-friendly', () async {
      final input = await write('in.xml', '<broken>');
      try {
        await service.compress(input, '${tmpDir.path}/out.xml');
        fail('should have thrown');
      } on Exception catch (e) {
        expect(e.toString(), contains('Invalid XML file'));
      }
    });
  });

  // ── Cancellation ──────────────────────────────────────────────────────────

  group('cancellation', () {
    test('pre-cancelled token throws immediately', () async {
      final input = await write('in.xml', '<root><a>1</a></root>');
      final token = CancellationToken()..cancel();
      expect(
        () => service.compress(input, '${tmpDir.path}/out.xml',
            cancellationToken: token),
        throwsA(isA<CompressionCancelledException>()),
      );
    });

    test('cancelling after read throws before write', () async {
      final input = await write('in.xml', '''
<root>
  <item>one</item>
  <item>two</item>
</root>
''');
      final out = '${tmpDir.path}/out.xml';
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
      final input = await write('in.xml', '''
<root>
  <a>1</a>
  <b>2</b>
</root>
''');
      final progresses = <double>[];
      await service.compress(input, '${tmpDir.path}/out.xml',
          onProgress: progresses.add);

      expect(progresses, isNotEmpty);
      for (var i = 1; i < progresses.length; i++) {
        expect(progresses[i], greaterThanOrEqualTo(progresses[i - 1]));
      }
    });

    test('last reported progress is 1.0', () async {
      final input = await write('in.xml', '<root><a>1</a></root>\n');
      double? last;
      await service.compress(input, '${tmpDir.path}/out.xml',
          onProgress: (p) => last = p);
      expect(last, 1.0);
    });
  });

  // ── Result fields ──────────────────────────────────────────────────────────

  group('result fields', () {
    test('outputPath matches the provided path', () async {
      final input = await write('in.xml', '''
<root>
  <a>1</a>
</root>
''');
      final out = '${tmpDir.path}/out.xml';
      final result = await service.compress(input, out);
      expect(result.outputPath, out);
    });

    test('originalBytes matches input file size', () async {
      final input = await write('in.xml', '''
<root>
  <a>hello</a>
</root>
''');
      final result =
          await service.compress(input, '${tmpDir.path}/out.xml');
      expect(result.originalBytes, await input.length());
    });
  });
}
