// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:encantadas_app/main.dart';

void main() {
  testWidgets('App loads with bottom navigation', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const EncantadasApp());

    // Wait for the app to initialize
    await tester.pumpAndSettle();

    // Verify that the bottom navigation bar exists
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    
    // Verify that bottom navigation tabs are present
    expect(find.text('Turnos'), findsOneWidget);
    expect(find.text('Stock'), findsOneWidget);
    expect(find.text('Ventas'), findsOneWidget);
    expect(find.text('Balance'), findsOneWidget);
    
    // Verify that the floating action button exists
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
