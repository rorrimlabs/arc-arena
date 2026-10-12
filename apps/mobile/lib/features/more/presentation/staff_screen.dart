import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/widgets/arena_badge.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';

/// Staff accounts and what each one may do (brief §12, design role model).
///
/// A user becomes an **owner** by holding Money or Reports; everyone else is
/// staff and lands on the Floor with the owner areas hidden. The PIN is a
/// convenience lock for a shared counter device, not a hardened credential.
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  static const String path = '/settings/staff';

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  List<AppUser> _users = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await ref.read(userRepositoryProvider).all();
    if (mounted) {
      setState(() {
        _users = users;
        _loading = false;
      });
    }
  }

  /// Cloud mode: a person is a real account. They create it on their own
  /// device; the owner then grants it access here (online only).
  Future<void> _addByEmail(CloudBinding cloud) async {
    final email = TextEditingController();
    final name = TextEditingController();
    var owner = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Add by e-mail'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('First create their login in the Supabase '
                  'dashboard (Authentication → Users → Add user, with a '
                  'starting password). Then add that e-mail here; they can '
                  'change the password after signing in.'),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Owner access'),
                subtitle: const Text('Money, reports and settings'),
                value: owner,
                onChanged: (v) => set(() => owner = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (go != true || !mounted) return;
    final perms = owner
        ? Permission.codesOf(Permission.all)
        : Permission.codesOf({
            Permission.start,
            Permission.bill,
            Permission.discount,
            Permission.members,
          });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await cloud.addStaffByEmail(email.text.trim(), name.text.trim(), perms);
      await cloud.engine.syncNow();
      await _load();
      messenger.showSnackBar(
          SnackBar(content: Text('${name.text.trim()} can now sign in.')));
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.message == 'no_account'
              ? 'No login uses that e-mail yet — create it in the Supabase '
                  'dashboard first (Authentication → Users → Add user).'
              : 'Not added: ${e.message}')));
    } on Object catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Needs a connection to add someone ($e).')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final cloud = ref.watch(cloudBindingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Staff & roles')),
      floatingActionButton: cloud == null
          ? FloatingActionButton.extended(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add person'),
            )
          : FloatingActionButton.extended(
              onPressed: () => _addByEmail(cloud),
              icon: const Icon(Icons.alternate_email),
              label: const Text('Add by e-mail'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
              children: [
                Text(
                  'Anyone holding Money or Reports is an owner and sees the '
                  'owner tabs. PINs unlock this device only.',
                  style: ArenaType.caption.copyWith(color: arena.textMuted),
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final u in _users)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Material(
                      color: arena.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        side: BorderSide(color: arena.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(u.name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            StatusDotLabel(
                              label: u.active ? u.roleLabel : 'Disabled',
                              color: u.active
                                  ? (u.isOwner ? arena.primary : arena.textMuted)
                                  : arena.textSubtle,
                            ),
                          ],
                        ),
                        subtitle: Text(
                          u.perms.isEmpty
                              ? 'No permissions'
                              : u.perms.map((p) => p.label).join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _edit(u),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _edit(AppUser? existing) async {
    final result = await showModalBottomSheet<_StaffEdit>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StaffEditor(existing: existing),
    );
    if (result == null) return;
    final saved = result.user;

    // The last person who can reach Settings must keep that access, or the
    // arena locks itself out of its own configuration on this device.
    final wouldLockOut = _users
        .where((u) =>
            u.id != saved.id && u.active && u.perms.contains(Permission.settings))
        .isEmpty;
    if (wouldLockOut &&
        (!saved.active || !saved.perms.contains(Permission.settings))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Keep Settings access for at least one active person, or no one '
              'can configure this device.',
            ),
          ),
        );
      }
      return;
    }

    await ref
        .read(userRepositoryProvider)
        .upsert(saved, newPin: result.newPin);
    ref.invalidate(usersProvider);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${saved.name} saved.')));
    }
  }
}

/// What the staff editor hands back: the account, plus a new PIN only when one
/// was actually typed (blank = keep the existing one, which cannot be read).
class _StaffEdit {
  const _StaffEdit({required this.user, this.newPin});
  final AppUser user;
  final String? newPin;
}

class _StaffEditor extends StatefulWidget {
  const _StaffEditor({required this.existing});
  final AppUser? existing;

  @override
  State<_StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends State<_StaffEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  // Always starts empty: a stored PIN is a salted hash and cannot be shown.
  // Blank means "keep the current PIN".
  late final TextEditingController _pin = TextEditingController();
  late final Set<Permission> _perms = {...?widget.existing?.perms};
  late bool _active = widget.existing?.active ?? true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arena = context.arena;
    final isOwner = _perms.contains(Permission.money) ||
        _perms.contains(Permission.reports);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(widget.existing == null ? 'Add person' : 'Edit person',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _pin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: widget.existing == null
                    ? '4-digit PIN'
                    : 'New 4-digit PIN',
                helperText: widget.existing == null
                    ? null
                    : 'Leave blank to keep the current PIN',
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Can do', style: theme.textTheme.labelLarge),
            Text(
              isOwner
                  ? 'Owner — sees Today, Money, Reports and Settings.'
                  : 'Staff — sees the Floor only.',
              style: ArenaType.caption.copyWith(
                color: isOwner ? arena.primary : arena.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final p in Permission.values)
                  FilterChip(
                    label: Text(p.label),
                    selected: _perms.contains(p),
                    onSelected: (on) => setState(() {
                      on ? _perms.add(p) : _perms.remove(p);
                      _error = null;
                    }),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Inactive people cannot sign in'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: arena.danger)),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    final isNew = widget.existing == null;
    final pin = _pin.text;
    if (isNew && pin.length != 4) {
      setState(() => _error = 'Set a 4-digit PIN for this person.');
      return;
    }
    if (!isNew && pin.isNotEmpty && pin.length != 4) {
      setState(() => _error = 'A new PIN must be 4 digits, or leave it blank.');
      return;
    }
    if (_perms.isEmpty) {
      setState(() => _error = 'Pick at least one thing this person can do.');
      return;
    }
    Navigator.of(context).pop(
      _StaffEdit(
        user: AppUser(
          id: widget.existing?.id ?? const Uuid().v4(),
          name: name,
          perms: _perms,
          active: _active,
        ),
        newPin: pin.isEmpty ? null : pin,
      ),
    );
  }
}
