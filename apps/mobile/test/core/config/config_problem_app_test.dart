import 'package:arena_ops/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConfigProblemApp', () {
    testWidgets('renders dark themed error screen with problem details and instructions', (tester) async {
      const sampleProblem = 'No production Supabase project is set up yet: this build cannot run until its host is added to AppConfig.hostedSupabaseHosts.';

      await tester.pumpWidget(const ConfigProblemApp(sampleProblem));
      await tester.pumpAndSettle();

      // Verify title / headline
      expect(find.text('Configuration problem — app not started'), findsOneWidget);

      // Verify diagnostic problem content is shown
      expect(find.text(sampleProblem), findsOneWidget);

      // Verify "Why it stopped" and "What to do" guidance
      expect(find.text('Why it stopped'), findsOneWidget);
      expect(find.text('What to do'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

      // Verify MaterialApp uses dark theme mode to avoid white-screen flash
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.dark);
    });

    testWidgets('startupFailed shows the device error and staff steps, not build instructions', (tester) async {
      const error = 'PlatformException(read_failed, Keystore unavailable, null, null)';

      await tester.pumpWidget(const ConfigProblemApp.startupFailed(error));
      await tester.pumpAndSettle();

      // Startup-failure title, not the configuration one
      expect(find.text('App could not start on this device'), findsOneWidget);
      expect(find.text('Configuration problem — app not started'), findsNothing);

      // The raw error is shown under "Error details"
      expect(find.text('Error details'), findsOneWidget);
      expect(find.text('Why it stopped'), findsNothing);
      expect(find.text(error), findsOneWidget);

      // Staff steps, including the warning that protects unsent records
      expect(find.textContaining('Close the app completely and open it again.'), findsOneWidget);
      expect(find.textContaining('restart the device'), findsOneWidget);
      expect(find.textContaining('tell the owner'), findsOneWidget);
      expect(find.textContaining('Do not uninstall the app or clear its data'), findsOneWidget);
      expect(find.textContaining('--flavor'), findsNothing);
    });
  });
}
