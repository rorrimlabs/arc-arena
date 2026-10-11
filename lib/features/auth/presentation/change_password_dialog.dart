import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

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
          _error = 'Not changed — needs a connection ($e).';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
