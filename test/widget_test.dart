import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/app.dart';

void main() {
  group('KivoApp', () {
    testWidgets('renders without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(const KivoApp());
      await tester.pump();
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('uses dark theme', (WidgetTester tester) async {
      await tester.pumpWidget(const KivoApp());
      await tester.pump();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme?.brightness, Brightness.dark);
    });

    testWidgets('debug banner is disabled', (WidgetTester tester) async {
      await tester.pumpWidget(const KivoApp());
      await tester.pump();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.debugShowCheckedModeBanner, false);
    });

    testWidgets('title is KIVO', (WidgetTester tester) async {
      await tester.pumpWidget(const KivoApp());
      await tester.pump();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.title, 'KIVO');
    });
  });
}
