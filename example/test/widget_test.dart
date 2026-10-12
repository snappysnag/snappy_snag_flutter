import 'package:flutter_test/flutter_test.dart';
import 'package:snappy_snag_example/main.dart';

void main() {
  testWidgets('SnappySnag showcase smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SnappySnagShowroomApp());
    expect(find.text('SnappySnag Playground'), findsOneWidget);
  });
}
