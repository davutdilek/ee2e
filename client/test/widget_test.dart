// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ee2e/app.dart';

void main() {
  testWidgets('shows connection screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester.pumpWidget(const EE2EApp());
    await tester.pump();

    expect(find.text('EE2E — Bağlantı'), findsOneWidget);
    expect(find.text('Faz 3 — E2EE Mesajlaşma'), findsOneWidget);
  });
}
