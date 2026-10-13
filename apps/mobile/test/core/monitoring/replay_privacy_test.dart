/// Session Replay pauses on every screen where credentials are entered (the PIN
/// keypad's tap positions would reveal a PIN even with text masked), resumes
/// when the last such screen closes, and is harmless where Sentry is off.
library;

import 'package:arena_ops/app/sync/cloud_root.dart';
import 'package:arena_ops/core/monitoring/replay_privacy.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/features/auth/presentation/change_password_dialog.dart';
import 'package:arena_ops/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_db.dart';

Widget _host(Widget child) => MaterialApp(theme: AppTheme.dark(), home: child);

void main() {
  testWidgets('counts nested zones; works with Sentry not initialised', (
    tester,
  ) async {
    expect(ReplayPause.activeZones, 0);
    await tester.pumpWidget(
      _host(const ReplayPause(child: ReplayPause(child: Text('pin')))),
    );
    expect(ReplayPause.activeZones, 2);
    await tester.pumpWidget(_host(const ReplayPause(child: Text('pin'))));
    expect(ReplayPause.activeZones, 1);
    await tester.pumpWidget(_host(const Text('floor')));
    expect(ReplayPause.activeZones, 0, reason: 'resumes once all are gone');
  });

  testWidgets('the PIN login screen pauses the replay', (tester) async {
    final db = await seededMemoryDb();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(db),
        child: _host(const LoginScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(ReplayPause), findsOneWidget);
    expect(ReplayPause.activeZones, 1);
    await tester.pumpWidget(const SizedBox());
    expect(ReplayPause.activeZones, 0);
  });

  testWidgets('cloud sign-in pauses the replay', (tester) async {
    await tester.pumpWidget(
      _host(
        CloudSignInScreen(signIn: (_, _) async {}, onSignedIn: () async {}),
      ),
    );
    expect(find.byType(ReplayPause), findsOneWidget);
    expect(ReplayPause.activeZones, 1);
    await tester.pumpWidget(const SizedBox());
    expect(ReplayPause.activeZones, 0);
  });

  testWidgets('the change-password dialog pauses the replay while open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  ChangePasswordDialog(changePassword: (_) async {}),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    expect(ReplayPause.activeZones, 0);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(ReplayPause.activeZones, 1);
    Navigator.of(tester.element(find.byType(ChangePasswordDialog))).pop();
    await tester.pumpAndSettle();
    expect(ReplayPause.activeZones, 0, reason: 'recording resumes after');
  });
}
