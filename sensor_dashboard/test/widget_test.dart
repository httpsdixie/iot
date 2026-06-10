import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sensor_dashboard/main.dart';

void main() {
  testWidgets('Dashboard basic loading smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the title and basic layout load
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
