import 'package:flutter_test/flutter_test.dart';
import 'package:kivo/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const KivoApp());
    expect(find.text('KIVO'), findsOneWidget);
  });
}
