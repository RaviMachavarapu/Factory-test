// stacks/flutter/overlay/test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:__PKG__/app.dart';

void main() {
  testWidgets('shows the greeting', (tester) async {
    await tester.pumpWidget(const GreetingApp());
    expect(find.text('Hello from __NAME__'), findsOneWidget);
  });
}
