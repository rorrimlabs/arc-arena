/// Cloud mode: a new arena owner's own account — sign up with e-mail and
/// password, confirm the e-mail with the 6-digit code the server sends, then
/// create the arena (`create_my_arena`: confirmed logins only, one arena per
/// login). Staff never sign up into an arena: an owner links their login from
/// Settings → Staff.
///
/// The screens only collect input and show outcomes; [CloudRoot] talks to
/// Supabase and decides where to go next.
library;

import 'dart:async';
import 'dart:io';

import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/features/auth/presentation/change_password_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Longest arena or owner name the server accepts (create_my_arena).
const maxAccountNameLength = 80;

/// What went wrong while signing up, confirming or creating the arena, in words
/// that say what to do. Only a failure to reach the server is a connection
/// problem; the server's own refusals carry a stable code.
String describeAccountError(Object e) {
  if (e is AuthRetryableFetchException || e is SocketException ||
      e is TimeoutException) {
    return 'Needs a connection. Try again when online.';
  }
  if (e is AuthException) {
    return switch (e.code) {
      'user_already_exists' || 'email_exists' =>
        'That e-mail already has an account. Go back and sign in.',
      'weak_password' => 'The server says this password is too weak. Use at '
          'least ${ChangePasswordDialog.minLength} characters with letters and digits.',
      'email_address_invalid' || 'validation_failed' =>
        'That e-mail address does not look right.',
      'otp_expired' => 'That code is wrong or has expired. Check the latest '
          'e-mail, or tap Resend code.',
      'over_email_send_rate_limit' =>
        'Too many e-mails sent. Wait a few minutes, then try again.',
      'over_request_rate_limit' =>
        'Too many attempts. Wait a few minutes, then try again.',
      'signup_disabled' || 'email_provider_disabled' =>
        'This server does not accept new accounts. Ask the operator for a login.',
      _ => e.message,
    };
  }
  if (e is PostgrestException) {
    return switch (e.message) {
      'arena_limit' => 'This login already owns an arena. Sign out and sign in '
          'again to open it.',
      'account_not_confirmed' =>
        'Confirm your e-mail first: sign out, sign in, and enter the code.',
      'invalid_name' => 'Names must be 1 to $maxAccountNameLength characters.',
      'forbidden' => 'Your sign-in has expired. Sign out and sign in again.',
      _ => 'Not created: ${e.message}',
    };
  }
  return 'Could not reach the server ($e).';
}

/// The password rule shared with the server (`minimum_password_length = 10`,
/// `password_requirements = "letters_digits"`), or null when it passes.
String? passwordProblem(String password, String again) {
  if (password.length < ChangePasswordDialog.minLength) {
    return 'Use at least ${ChangePasswordDialog.minLength} characters.';
  }
  if (!password.contains(RegExp('[A-Za-z]')) || !password.contains(RegExp('[0-9]'))) {
    return 'Use both letters and digits.';
  }
  if (password != again) return 'The two passwords are different.';
  return null;
}

/// Step 1: e-mail and a password only this person knows.
class CloudSignUpScreen extends StatefulWidget {
  const CloudSignUpScreen({
    required this.signUp,
    required this.onBack,
    super.key,
  });

  /// Creates the login (Supabase in the app; a fake in tests). The server
  /// then e-mails the confirmation code.
  final Future<void> Function(String email, String password) signUp;
  final VoidCallback onBack;

  @override
  State<CloudSignUpScreen> createState() => _CloudSignUpScreenState();
}

class _CloudSignUpScreenState extends State<CloudSignUpScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final problem = !email.contains('@')
        ? 'Enter your e-mail address.'
        : passwordProblem(_password.text, _again.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.signUp(email, _password.text);
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeAccountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountForm(
      title: 'Create an account',
      subtitle: 'For a new arena owner. Staff: ask your owner to add you '
          'instead — you do not need your own arena.',
      error: _error,
      fields: [
        TextField(
          key: const Key('signup-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'E-mail'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('signup-password'),
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: 'At least ${ChangePasswordDialog.minLength} characters, '
                'letters and digits',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('signup-password-again'),
          controller: _again,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Type it again'),
          onSubmitted: (_) => _busy ? null : _submit(),
        ),
      ],
      actions: [
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Create account'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: _busy ? null : widget.onBack,
          child: const Text('I already have a login — sign in'),
        ),
      ],
    );
  }
}

/// Step 2: the 6-digit code from the confirmation e-mail.
class CloudVerifyEmailScreen extends StatefulWidget {
  const CloudVerifyEmailScreen({
    required this.email,
    required this.verify,
    required this.resend,
    required this.onBack,
    super.key,
  });

  final String email;

  /// Confirms the e-mail and signs in (Supabase verifyOTP in the app).
  final Future<void> Function(String code) verify;
  final Future<void> Function() resend;
  final VoidCallback onBack;

  static const codeLength = 6;

  @override
  State<CloudVerifyEmailScreen> createState() => _CloudVerifyEmailScreenState();
}

class _CloudVerifyEmailScreenState extends State<CloudVerifyEmailScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
      if (mounted && done != null) setState(() => _info = done);
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeAccountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.length != CloudVerifyEmailScreen.codeLength) {
      setState(() => _error =
          'Enter the ${CloudVerifyEmailScreen.codeLength}-digit code from the e-mail.');
      return;
    }
    await _run(() => widget.verify(code));
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return AccountForm(
      title: 'Check your e-mail',
      subtitle: 'We sent a ${CloudVerifyEmailScreen.codeLength}-digit code to '
          '${widget.email}. Enter it to confirm the address. If that e-mail '
          'already has an account, no code is sent: go back and sign in.',
      error: _error,
      fields: [
        TextField(
          key: const Key('signup-code'),
          controller: _code,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(CloudVerifyEmailScreen.codeLength),
          ],
          decoration: const InputDecoration(labelText: 'Code'),
          onSubmitted: (_) => _busy ? null : _submit(),
        ),
        if (_info != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(_info!, style: ArenaType.label.copyWith(color: arena.textMuted)),
        ],
      ],
      actions: [
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Confirm'),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(widget.resend, done: 'Sent a new code to ${widget.email}.'),
          child: const Text('Resend code'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: _busy ? null : widget.onBack,
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }
}

/// Step 3: name the arena. The server creates it with the starter catalog
/// (stations, rates, games — all editable in Settings) and makes this login
/// its owner.
class CloudCreateArenaScreen extends StatefulWidget {
  const CloudCreateArenaScreen({
    required this.email,
    required this.createArena,
    required this.onBack,
    super.key,
  });

  final String email;
  final Future<void> Function(String arenaName, String ownerName) createArena;
  final VoidCallback onBack;

  @override
  State<CloudCreateArenaScreen> createState() => _CloudCreateArenaScreenState();
}

class _CloudCreateArenaScreenState extends State<CloudCreateArenaScreen> {
  final _arenaName = TextEditingController();
  final _ownerName = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _arenaName.dispose();
    _ownerName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final arenaName = _arenaName.text.trim();
    final ownerName = _ownerName.text.trim();
    if (arenaName.isEmpty || ownerName.isEmpty) {
      setState(() => _error = 'Enter the arena name and your name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.createArena(arenaName, ownerName);
    } on Object catch (e) {
      if (mounted) setState(() => _error = describeAccountError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AccountForm(
      title: 'Create your arena',
      subtitle: 'Signed in as ${widget.email}. You will be its owner. It starts '
          'with a sample set of stations, rates and games — change them in '
          'More → Settings. One arena per login.',
      error: _error,
      fields: [
        TextField(
          key: const Key('arena-name'),
          controller: _arenaName,
          maxLength: maxAccountNameLength,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Arena name'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('owner-name'),
          controller: _ownerName,
          maxLength: maxAccountNameLength,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: const InputDecoration(labelText: 'Your name'),
          onSubmitted: (_) => _busy ? null : _submit(),
        ),
      ],
      actions: [
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Create arena'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextButton(
          onPressed: _busy ? null : widget.onBack,
          child: const Text('Back'),
        ),
      ],
    );
  }
}

/// The centred, width-capped form layout of the cloud entry screens.
class AccountForm extends StatelessWidget {
  const AccountForm({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.actions,
    this.error,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> fields;
  final List<Widget> actions;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Text(title, style: ArenaType.h1.copyWith(color: arena.text)),
                const SizedBox(height: AppSpacing.sm),
                Text(subtitle, style: ArenaType.body.copyWith(color: arena.textMuted)),
                const SizedBox(height: AppSpacing.xl),
                ...fields,
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(error!, style: ArenaType.label.copyWith(color: arena.danger)),
                ],
                const SizedBox(height: AppSpacing.xl),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
