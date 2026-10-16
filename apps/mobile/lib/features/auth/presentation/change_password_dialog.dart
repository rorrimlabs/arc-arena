import 'dart:async';
import 'dart:io';

import 'package:arena_ops/core/monitoring/replay_privacy.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cloud mode: the signed-in person replaces their own password. The owner
/// creates each login with a starting password; this turns it into
/// credentials only that person knows. Needs a connection (the server keeps
/// the password; nothing about it is stored on the device).
class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({required this.changePassword, super.key});

  final Future<void> Function(String newPassword) changePassword;

  /// Matches the minimum recommended for the hosted project
  /// (docs/DEPLOY_SUPABASE.md); the server enforces its own minimum too.
  static const minLength = 10;

  /// What went wrong, in words that say what to do. Only a failure to reach
  /// the server is a connection problem; the server's own refusals (same or
  /// weak password, a sign-in too old for a password change) are not.
  @visibleForTesting
  static String describeError(Object e) {
    if (e is AuthRetryableFetchException ||
        e is SocketException ||
        e is TimeoutException) {
      return 'Not changed — needs a connection. Try again when online.';
    }
    if (e is AuthException) {
      return switch (e.code) {
        'same_password' => 'That is already your password. Choose a new one.',
        'weak_password' =>
          'The server says this password is too weak. '
              'Use a longer one with letters and digits.',
        'reauthentication_needed' ||
        'reauth_nonce_missing' ||
        'session_not_found' ||
        'session_expired' =>
          'For safety, sign out and sign in again, then change it.',
        _ => 'Not changed: ${e.message}',
      };
    }
    return 'Not changed ($e).';
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p = _password.text;
    final problem = p.length < ChangePasswordDialog.minLength
        ? 'Use at least ${ChangePasswordDialog.minLength} characters.'
        : p != _again.text
        ? 'The two passwords are different.'
        : null;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.changePassword(p);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = ChangePasswordDialog.describeError(e);
        });
      }
    }
  }

  // Credentials are entered here: Session Replay pauses while it is open.
  @override
  Widget build(BuildContext context) => ReplayPause(child: _screen(context));

  Widget _screen(BuildContext context) {
    final arena = context.arena;
    return AlertDialog(
      title: const Text('Change password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('new-password'),
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          TextField(
            key: const Key('new-password-again'),
            controller: _again,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Type it again'),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: ArenaType.label.copyWith(color: arena.danger)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
