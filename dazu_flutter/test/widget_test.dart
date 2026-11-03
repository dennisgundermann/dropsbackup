import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dazu_flutter/screens/main_shell.dart';

void main() {
  testWidgets('MainShell zeigt alle 5 Tab-Labels', (WidgetTester tester) async {
    // Testen die Shell direkt (Firebase.initializeApp im main() wird
    // im Widget-Test nicht aufgerufen; Shell braucht sie auch nicht).
    await tester.pumpWidget(
      const MaterialApp(home: MainShell()),
    );
    await tester.pump();

    expect(find.text('Karte'), findsOneWidget);
    expect(find.text('Umgebung'), findsOneWidget);
    expect(find.text('dazu'), findsWidgets);
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
  });
}
