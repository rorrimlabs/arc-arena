/// New arena owner sign-up (cloud mode): e-mail + password, the 6-digit
/// confirmation code, then the arena. Each screen refuses bad input before the
/// server and turns the server's refusal codes into words that say what to do.
library;

import 'package:arena_ops/app/sync/cloud_account_screens.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, AuthRetryableFetchException, PostgrestException;

Widget _host(Widget child) => MaterialApp(theme: AppTheme.dark(), home: child);

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pump();
}

void main() {
  group('describeAccountError', () {
    test('server refusals say what to do; only fetch failures mean offline', () {
      expect(describeAccountError(AuthRetryableFetchException()),
          contains('Needs a connection'));
      expect(describeAccountError(const AuthException('x', code: 'user_already_exists')),
          contains('already has an account'));
      expect(describeAccountError(const AuthException('x', code: 'weak_password')),
          contains('letters and digits'));
      expect(describeAccountError(const AuthException('x', code: 'otp_expired')),
          contains('wrong or has expired'));
      expect(describeAccountError(
              const AuthException('x', code: 'over_email_send_rate_limit')),
          contains('Wait a few minutes'));
      expect(describeAccountError(const AuthException('x', code: 'signup_disabled')),
          contains('does not accept new accounts'));
      expect(describeAccountError(const PostgrestException(message: 'arena_limit')),
          contains('already owns an arena'));
      expect(describeAccountError(const PostgrestException(message: 'invalid_name')),
          contains('1 to 80'));
      expect(
          describeAccountError(const PostgrestException(message: 'account_not_confirmed')),
          contains('Confirm your e-mail'));
      for (final code in ['weak_password', 'otp_expired', 'user_already_exists']) {
        expect(describeAccountError(AuthException('x', code: code)),
            isNot(contains('connection')));
      }
    });

    test('password rule matches the server: 10+, letters and digits, typed twice',
        () {
      expect(passwordProblem('short1', 'short1'), contains('at least 10'));
      expect(passwordProblem('onlyletters', 'onlyletters'), contains('letters and digits'));
      expect(passwordProblem('1234567890', '1234567890'), contains('letters and digits'));
      expect(passwordProblem('arena-pass-42', 'arena-pass-43'), contains('different'));
      expect(passwordProblem('arena-pass-42', 'arena-pass-42'), isNull);
    });
  });

  group('sign up', () {
    testWidgets('bad input is refused before the server', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(CloudSignUpScreen(
        signUp: (_, _) async => calls++,
        onBack: () {},
      )));
      await _tapText(tester, 'Create account');
      expect(find.text('Enter your e-mail address.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('signup-email')), 'owner@arena.example');
      await tester.enterText(find.byKey(const Key('signup-password')), 'short');
      await tester.enterText(find.byKey(const Key('signup-password-again')), 'short');
      await _tapText(tester, 'Create account');
      expect(find.textContaining('at least 10'), findsOneWidget);
      expect(calls, 0);
    });

    testWidgets('sends the trimmed e-mail and the password once', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(_host(CloudSignUpScreen(
        signUp: (e, p) async => sent.add('$e|$p'),
        onBack: () {},
      )));
      await tester.enterText(find.byKey(const Key('signup-email')), ' owner@arena.example ');
      await tester.enterText(find.byKey(const Key('signup-password')), 'arena-pass-42');
      await tester.enterText(find.byKey(const Key('signup-password-again')), 'arena-pass-42');
      await _tapText(tester, 'Create account');
      expect(sent, ['owner@arena.example|arena-pass-42']);
    });

    testWidgets('a server refusal is shown in plain words', (tester) async {
      await tester.pumpWidget(_host(CloudSignUpScreen(
        signUp: (_, _) async =>
            throw const AuthException('raw', code: 'weak_password'),
        onBack: () {},
      )));
      await tester.enterText(find.byKey(const Key('signup-email')), 'owner@arena.example');
      await tester.enterText(find.byKey(const Key('signup-password')), 'arena-pass-42');
      await tester.enterText(find.byKey(const Key('signup-password-again')), 'arena-pass-42');
      await _tapText(tester, 'Create account');
      expect(find.textContaining('too weak'), findsOneWidget);
      expect(find.text('raw'), findsNothing);
    });

    testWidgets('back goes to sign in', (tester) async {
      var back = false;
      await tester.pumpWidget(_host(CloudSignUpScreen(
        signUp: (_, _) async {},
        onBack: () => back = true,
      )));
      await _tapText(tester, 'I already have a login — sign in');
      expect(back, isTrue);
    });
  });

  group('confirm e-mail', () {
    testWidgets('needs all 6 digits; letters cannot be typed', (tester) async {
      final codes = <String>[];
      await tester.pumpWidget(_host(CloudVerifyEmailScreen(
        email: 'owner@arena.example',
        verify: (c) async => codes.add(c),
        resend: () async {},
        onBack: () {},
      )));
      expect(find.textContaining('owner@arena.example'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('signup-code')), '12ab3');
      await _tapText(tester, 'Confirm');
      expect(find.textContaining('6-digit code'), findsWidgets);
      expect(codes, isEmpty);
      await tester.enterText(find.byKey(const Key('signup-code')), '1234567');
      await _tapText(tester, 'Confirm');
      expect(codes, ['123456']);
    });

    testWidgets('a wrong code says so; resend confirms it was sent', (tester) async {
      var resent = 0;
      await tester.pumpWidget(_host(CloudVerifyEmailScreen(
        email: 'owner@arena.example',
        verify: (_) async => throw const AuthException('x', code: 'otp_expired'),
        resend: () async => resent++,
        onBack: () {},
      )));
      await tester.enterText(find.byKey(const Key('signup-code')), '000000');
      await _tapText(tester, 'Confirm');
      expect(find.textContaining('wrong or has expired'), findsOneWidget);
      await _tapText(tester, 'Resend code');
      expect(resent, 1);
      expect(find.text('Sent a new code to owner@arena.example.'), findsOneWidget);
      expect(find.textContaining('wrong or has expired'), findsNothing);
    });
  });

  group('create arena', () {
    testWidgets('both names are required, then sent trimmed', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(_host(CloudCreateArenaScreen(
        email: 'owner@arena.example',
        createArena: (a, o) async => sent.add('$a|$o'),
        onBack: () {},
      )));
      await tester.enterText(find.byKey(const Key('arena-name')), '  ');
      await _tapText(tester, 'Create arena');
      expect(find.text('Enter the arena name and your name.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('arena-name')), ' Game Zone ');
      await tester.enterText(find.byKey(const Key('owner-name')), ' Sam ');
      await _tapText(tester, 'Create arena');
      expect(sent, ['Game Zone|Sam']);
    });

    testWidgets('the one-arena limit is explained', (tester) async {
      await tester.pumpWidget(_host(CloudCreateArenaScreen(
        email: 'owner@arena.example',
        createArena: (_, _) async =>
            throw const PostgrestException(message: 'arena_limit'),
        onBack: () {},
      )));
      await tester.enterText(find.byKey(const Key('arena-name')), 'Second');
      await tester.enterText(find.byKey(const Key('owner-name')), 'Sam');
      await _tapText(tester, 'Create arena');
      expect(find.textContaining('already owns an arena'), findsOneWidget);
    });
  });

  for (final (label, size) in [
    ('phone', const Size(1080, 2340)),
    ('tablet', const Size(2560, 1600)),
  ]) {
    testWidgets('every sign-up screen lays out on a $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      for (final screen in <Widget>[
        CloudSignUpScreen(signUp: (_, _) async {}, onBack: () {}),
        CloudVerifyEmailScreen(
            email: 'a-rather-long-owner-address@arena.example',
            verify: (_) async {},
            resend: () async {},
            onBack: () {}),
        CloudCreateArenaScreen(
            email: 'owner@arena.example', createArena: (_, _) async {}, onBack: () {}),
      ]) {
        await tester.pumpWidget(_host(screen));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$label: ${screen.runtimeType}');
      }
    });
  }
}
