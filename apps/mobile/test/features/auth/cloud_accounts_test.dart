/// The floor app is staff-only: the entry screen only signs in (owners register
/// and create staff logins on the admin dashboard), nobody can create an
/// account or an arena here, and a person can replace their starting password.
library;

import 'package:arena_ops/app/sync/cloud_root.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/features/auth/presentation/change_password_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthRetryableFetchException;

Widget _host(Widget child) => MaterialApp(theme: AppTheme.dark(), home: child);

void main() {
  group('sign-in screen', () {
    testWidgets(
      'offers Sign in and nothing else — no registration in the app',
      (tester) async {
        await tester.pumpWidget(
          _host(
            CloudSignInScreen(signIn: (_, _) async {}, onSignedIn: () async {}),
          ),
        );
        expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
        expect(find.textContaining('Create'), findsNothing);
        expect(find.textContaining('Sign up'), findsNothing);
        expect(find.textContaining('Register'), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(
          find.byType(TextField),
          findsNWidgets(2),
          reason: 'e-mail + password only',
        );
      },
    );

    testWidgets('signs in with the typed credentials, then continues', (
      tester,
    ) async {
      String? email;
      String? password;
      var continued = false;
      await tester.pumpWidget(
        _host(
          CloudSignInScreen(
            signIn: (e, p) async {
              email = e;
              password = p;
            },
            onSignedIn: () async => continued = true,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('cloud-email')),
        '  staff@arena.example ',
      );
      await tester.enterText(
        find.byKey(const Key('cloud-password')),
        'their-own-password',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      expect(email, 'staff@arena.example');
      expect(password, 'their-own-password');
      expect(continued, isTrue);
    });

    testWidgets('a refused sign-in shows why and does not continue', (
      tester,
    ) async {
      var continued = false;
      await tester.pumpWidget(
        _host(
          CloudSignInScreen(
            signIn: (_, _) async =>
                throw const AuthException('Invalid login credentials'),
            onSignedIn: () async => continued = true,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('cloud-email')),
        'x@y.example',
      );
      await tester.enterText(find.byKey(const Key('cloud-password')), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pump();
      expect(find.text('Invalid login credentials'), findsOneWidget);
      expect(continued, isFalse);
    });

    testWidgets('says why the device came back here', (tester) async {
      await tester.pumpWidget(
        _host(
          CloudSignInScreen(
            signIn: (_, _) async {},
            onSignedIn: () async {},
            notice: 'Your access to this arena was turned off.',
          ),
        ),
      );
      expect(
        find.text('Your access to this arena was turned off.'),
        findsOneWidget,
      );
    });
  });

  group('arena screen', () {
    testWidgets('a login with no arena is told to ask the owner — it cannot '
        'create an arena', (tester) async {
      await tester.pumpWidget(
        _host(
          CloudArenaPickScreen(
            arenas: const [],
            email: 'new@arena.example',
            onPick: (_) async {},
            onRefresh: () async {},
            onSignOut: () async {},
          ),
        ),
      );
      expect(
        find.textContaining('Ask the owner to add new@arena.example'),
        findsOneWidget,
      );
      expect(find.textContaining('Create'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('lists memberships; a turned-off one cannot be opened', (
      tester,
    ) async {
      Membership? opened;
      await tester.pumpWidget(
        _host(
          CloudArenaPickScreen(
            arenas: const [
              (
                arenaId: 'a1',
                arenaName: '404 Arena',
                name: 'Alan',
                active: true,
              ),
              (
                arenaId: 'a2',
                arenaName: 'Old Arena',
                name: 'Alan',
                active: false,
              ),
            ],
            email: 'alan@arena.example',
            onPick: (m) async => opened = m,
            onRefresh: () async {},
            onSignOut: () async {},
          ),
        ),
      );
      await tester.tap(find.text('Old Arena'));
      await tester.pump();
      expect(opened, isNull);
      await tester.tap(find.text('404 Arena'));
      await tester.pump();
      expect(opened?.arenaId, 'a1');
    });
  });

  group('change password', () {
    test('server refusals are not reported as a connection problem', () {
      String say(Object e) => ChangePasswordDialog.describeError(e);
      expect(
        say(AuthRetryableFetchException()),
        contains('needs a connection'),
      );
      expect(
        say(AuthException('x', code: 'same_password')),
        contains('already your password'),
      );
      expect(
        say(AuthException('x', code: 'weak_password')),
        contains('too weak'),
      );
      expect(
        say(AuthException('x', code: 'reauthentication_needed')),
        contains('sign in again'),
      );
      for (final e in [
        AuthException('x', code: 'same_password'),
        AuthException('x', code: 'weak_password'),
      ]) {
        expect(say(e), isNot(contains('connection')));
      }
    });

    Future<void> open(
      WidgetTester tester,
      Future<void> Function(String) change,
    ) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => ChangePasswordDialog(changePassword: change),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('too short or not matching: refused before the server', (
      tester,
    ) async {
      var calls = 0;
      await open(tester, (_) async => calls++);
      await tester.enterText(find.byKey(const Key('new-password')), 'short');
      await tester.enterText(
        find.byKey(const Key('new-password-again')),
        'short',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.textContaining('at least 10'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('new-password')),
        'long-enough-1',
      );
      await tester.enterText(
        find.byKey(const Key('new-password-again')),
        'long-enough-2',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('The two passwords are different.'), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets('a valid new password is sent once and the dialog closes', (
      tester,
    ) async {
      final sent = <String>[];
      await open(tester, (p) async => sent.add(p));
      await tester.enterText(
        find.byKey(const Key('new-password')),
        'my-own-pass-42',
      );
      await tester.enterText(
        find.byKey(const Key('new-password-again')),
        'my-own-pass-42',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(sent, ['my-own-pass-42']);
      expect(find.byType(ChangePasswordDialog), findsNothing);
    });

    testWidgets('offline: says it was not changed and stays open', (
      tester,
    ) async {
      await open(tester, (_) async => throw Exception('no route'));
      await tester.enterText(
        find.byKey(const Key('new-password')),
        'my-own-pass-42',
      );
      await tester.enterText(
        find.byKey(const Key('new-password-again')),
        'my-own-pass-42',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Not changed'), findsOneWidget);
      expect(find.byType(ChangePasswordDialog), findsOneWidget);
    });
  });
}
