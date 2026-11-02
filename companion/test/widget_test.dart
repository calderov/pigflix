import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pigflix_remote/main.dart';

void main() {
  testWidgets('shows the welcome pairing screen on first launch', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const PigflixRemoteApp());
    await tester.pumpAndSettle();

    expect(find.text('Scan QR code'), findsOneWidget);
    expect(find.text('Enter manually'), findsOneWidget);
  });
}
