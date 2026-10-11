/// Cloud mode's root: sign in → pick the arena → open that arena's database on
/// this device (downloading it the first time) → the normal app, with every
/// repository recording sync ops and a sync engine running.
///
/// Each (arena, person) gets its own database file. A device used by two people
/// therefore never pushes one person's unsent work under the other's sign-in,
/// and the local-only database (`arena_ops.sqlite`) is never touched.
library;

import 'dart:async';
import 'dart:io';

import 'package:arena_ops/app/arena_ops_app.dart';
import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/data_providers.dart';
import 'package:arena_ops/app/providers/notification_providers.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/core/clock/clock.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/data/local/database.dart';
import 'package:arena_ops/data/local/db_safety.dart';
import 'package:arena_ops/data/sync/sync_engine.dart';
import 'package:arena_ops/data/sync/sync_recorder.dart';
import 'package:arena_ops/data/sync/sync_transport.dart';
import 'package:arena_ops/domain/auth/app_user.dart';
import 'package:arena_ops/domain/auth/permission.dart';
import 'package:arena_ops/features/more/presentation/database_locked_screen.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One membership as my_arenas() reports it.
typedef Membership = ({
  String arenaId,
  String arenaName,
  String name,
  bool active,
});

enum _Phase { checking, signIn, pickArena, opening, ready, failed }

class CloudRoot extends StatefulWidget {
  const CloudRoot({required this.documentsPath, super.key});

  /// Where the per-arena database files and their backups live.
  final String documentsPath;

  @override
  State<CloudRoot> createState() => _CloudRootState();
}

class _CloudRootState extends State<CloudRoot> with WidgetsBindingObserver {
  _Phase _phase = _Phase.checking;
  String? _message;
  List<Membership> _arenas = const [];
  ProviderContainer? _container;
  AppDatabase? _db;
  CloudBinding? _binding;
  DbProtectReport? _locked;
  StreamSubscription<SyncStatus>? _statusSub;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_client.auth.currentSession == null) {
      _phase = _Phase.signIn;
    } else {
      unawaited(_loadArenas());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_teardown());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final engine = _binding?.engine;
    if (engine == null) return;
    if (state == AppLifecycleState.resumed) {
      engine.start(); // also syncs at once: catch up after the pause
    } else if (state == AppLifecycleState.paused) {
      engine.stop();
    }
  }

  void _go(_Phase phase, {String? message}) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _message = message;
    });
  }

  Future<void> _loadArenas() async {
    _go(_Phase.checking);
    try {
      final rows = await _client.rpc('my_arenas') as List;
      _arenas = [
        for (final r in rows)
          (
            arenaId: (r as Map)['arena_id'] as String,
            arenaName: r['arena_name'] as String,
            name: r['name'] as String,
            active: r['active'] as bool,
          ),
      ];
      final active = _arenas.where((a) => a.active).toList();
      if (active.length == 1) {
        await _open(active.single);
      } else {
        _go(_Phase.pickArena);
      }
    } on Object catch (e) {
      // Offline with a previous sign-in: open the last arena from disk.
      final last = await _lastArenaOnDisk();
      if (last != null) {
        await _open(last);
      } else {
        _go(_Phase.failed, message: 'Could not reach the server ($e).');
      }
    }
  }

  /// The arena this person last opened on this device, for offline starts.
  Future<Membership?> _lastArenaOnDisk() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final marker = File('${widget.documentsPath}/arena_ops_cloud_last_${user.id}');
    if (!marker.existsSync()) return null;
    final parts = marker.readAsStringSync().split('\n');
    if (parts.length < 2) return null;
    return (arenaId: parts[0], arenaName: parts[1], name: '', active: true);
  }

  Future<void> _open(Membership arena) async {
    _go(_Phase.opening, message: 'Opening ${arena.arenaName}…');
    final user = _client.auth.currentUser!;
    final dbPath =
        '${widget.documentsPath}/arena_ops_cloud_${arena.arenaId}_${user.id}.sqlite';
    final safety = await DbSafety.protect(
      dbFile: File(dbPath),
      appSchemaVersion: AppDatabase.expectedSchemaVersion,
      backupDir: Directory('${widget.documentsPath}/arena_ops-backups'),
      label: 'arena_ops_cloud_${arena.arenaId}',
    );
    if (!safety.safeToOpen) {
      setState(() => _locked = safety);
      return;
    }
    final db = AppDatabase(driftDatabase(
      name: 'arena_ops_cloud',
      native: DriftNativeOptions(databasePath: () async => dbPath),
    ));
    final clock = OffsetClock(const SystemClock(), Duration.zero);
    final engine = SyncEngine(
      db: db,
      transport: SupabaseSyncTransport(_client),
      arenaId: arena.arenaId,
    );
    final recorder = SyncRecorder(db,
        actor: () => user.id, clock: clock, onRecorded: engine.nudge);

    // First open on this device: the arena must come down before anything
    // can be shown (there is no local catalog to fall back on).
    final cursor = await (db.select(db.syncMeta)
          ..where((t) => t.key.equals(SyncEngine.cursorKey)))
        .getSingleOrNull();
    if (cursor == null) {
      _go(_Phase.opening, message: 'Downloading ${arena.arenaName}…');
      final first = await engine.syncNow();
      if (first.endedIn != SyncState.synced) {
        await engine.dispose();
        await db.close();
        _go(_Phase.failed,
            message: engine.status.message ??
                'The first download needs a connection. Try again when online.');
        return;
      }
    }
    final me = await (db.select(db.users)..where((t) => t.id.equals(user.id)))
        .getSingleOrNull();
    if (me == null || !me.active) {
      await engine.dispose();
      await db.close();
      _go(_Phase.pickArena,
          message: 'Your access to ${arena.arenaName} is turned off.');
      return;
    }
    File('${widget.documentsPath}/arena_ops_cloud_last_${user.id}')
        .writeAsStringSync('${arena.arenaId}\n${arena.arenaName}');

    final binding = CloudBinding(
      arenaId: arena.arenaId,
      arenaName: arena.arenaName,
      userId: user.id,
      email: user.email ?? '',
      engine: engine,
      recorder: recorder,
      clock: clock,
      signOut: () => _signOut(),
      addStaffByEmail: (email, name, perms) => _client.rpc('add_staff_by_email',
          params: {
            'p_arena': arena.arenaId,
            'p_email': email,
            'p_name': name,
            'p_perms': perms,
          }),
    );
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      cloudBindingProvider.overrideWithValue(binding),
      clockProvider.overrideWithValue(clock),
      authControllerProvider.overrideWith(() => CloudAuthController(AppUser(
            id: me.id,
            name: me.name,
            perms: Permission.parse(me.perms),
          ))),
      clockOffsetProvider.overrideWith((ref) {
        final offset = ref.watch(_serverOffsetProvider).value ?? Duration.zero;
        return ClockOffset(offset);
      }),
    ]);
    // Follow the server clock once it is off by more than the warning
    // threshold — then every device stamps sessions on the same clock.
    _statusSub = engine.statusStream.listen((s) {
      unawaited(_applyClockOffset(db, clock));
      // Revoked on the server: stop at once rather than keep working on stale
      // permissions. Unsent work stays in this person's database file.
      if (s.accessRevoked) unawaited(_signOut(reason: s.message));
    });
    await _applyClockOffset(db, clock);
    engine.start();
    unawaited(_initReminders(container));
    _db = db;
    _binding = binding;
    _container = container;
    _go(_Phase.ready);
  }

  Future<void> _applyClockOffset(AppDatabase db, OffsetClock clock) async {
    final row = await (db.select(db.syncMeta)
          ..where((t) => t.key.equals(SyncEngine.clockOffsetKey)))
        .getSingleOrNull();
    final measured = Duration(milliseconds: int.tryParse(row?.value ?? '') ?? 0);
    clock.offset = ClockOffset(measured).isSignificant ? measured : Duration.zero;
  }

  Future<void> _initReminders(ProviderContainer container) async {
    try {
      final service = container.read(notificationServiceProvider);
      await service.init();
      await container.read(bookingRemindersProvider).syncUpcoming();
    } catch (e) {
      debugPrint('reminder init skipped: $e');
    }
  }

  Future<void> _teardown() async {
    await _statusSub?.cancel();
    _statusSub = null;
    final engine = _binding?.engine;
    _binding = null;
    final container = _container;
    _container = null;
    await engine?.dispose();
    container?.dispose();
    await _db?.close();
    _db = null;
  }

  Future<void> _signOut({String? reason}) async {
    if (_phase != _Phase.ready) return;
    _phase = _Phase.checking;
    await _teardown();
    try {
      await _client.auth.signOut();
    } on Object catch (_) {
      // Offline: the local session is cleared regardless.
    }
    _go(_Phase.signIn, message: reason);
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked;
    if (locked != null) return DatabaseLockedApp(report: locked);
    final container = _container;
    if (_phase == _Phase.ready && container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: const ArenaOpsApp(),
      );
    }
    return MaterialApp(
      title: 'arena_ops',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: switch (_phase) {
        _Phase.signIn => _SignInScreen(onSignedIn: _loadArenas, notice: _message),
        _Phase.pickArena => _ArenaPickScreen(
            arenas: _arenas,
            message: _message,
            email: _client.auth.currentUser?.email ?? '',
            onPick: _open,
            onRefresh: _loadArenas,
            onCreate: (name, ownerName) async {
              await _client.rpc('create_arena',
                  params: {'p_name': name, 'p_owner_name': ownerName});
              await _loadArenas();
            },
            onSignOut: () async {
              await _client.auth.signOut();
              _go(_Phase.signIn);
            },
          ),
        _Phase.failed => _Message(
            text: _message ?? 'Something went wrong.',
            action: 'Try again',
            onAction: _loadArenas,
          ),
        _ => _Message(text: _message ?? 'Checking your account…'),
      },
    );
  }
}

final _serverOffsetProvider = StreamProvider<Duration>((ref) async* {
  final binding = ref.watch(cloudBindingProvider);
  if (binding == null) return;
  final db = ref.watch(databaseProvider);
  yield* (db.select(db.syncMeta)
        ..where((t) => t.key.equals(SyncEngine.clockOffsetKey)))
      .watchSingleOrNull()
      .map((r) => Duration(milliseconds: int.tryParse(r?.value ?? '') ?? 0));
});

// ------------------------------------------------------------------ screens

class _SignInScreen extends StatefulWidget {
  const _SignInScreen({required this.onSignedIn, this.notice});
  final Future<void> Function() onSignedIn;

  /// Why the device came back here (e.g. access turned off), if it was not
  /// the person's own choice.
  final String? notice;

  @override
  State<_SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<_SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(GoTrueClient auth) action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(Supabase.instance.client.auth);
      if (Supabase.instance.client.auth.currentSession != null) {
        await widget.onSignedIn();
      } else {
        setState(() => _error = 'Check your e-mail to confirm the account, '
            'then sign in.');
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } on Object catch (e) {
      setState(() => _error = 'Could not reach the server ($e).');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
                Text('Sign in', style: ArenaType.h1.copyWith(color: arena.text)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Use your own account. Your owner gives it access to the '
                  'arena; what you can do comes from there.',
                  style: ArenaType.body.copyWith(color: arena.textMuted),
                ),
                if (widget.notice != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(widget.notice!,
                      style: ArenaType.label.copyWith(color: arena.warning)),
                ],
                const SizedBox(height: AppSpacing.xl),
                TextField(
                  key: const Key('cloud-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'E-mail'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const Key('cloud-password'),
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(_error!, style: ArenaType.label.copyWith(color: arena.danger)),
                ],
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run((auth) => auth.signInWithPassword(
                          email: _email.text.trim(), password: _password.text)),
                  child: const Text('Sign in'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run((auth) => auth.signUp(
                          email: _email.text.trim(), password: _password.text)),
                  child: const Text('Create my account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArenaPickScreen extends StatefulWidget {
  const _ArenaPickScreen({
    required this.arenas,
    required this.email,
    required this.onPick,
    required this.onRefresh,
    required this.onCreate,
    required this.onSignOut,
    this.message,
  });

  final List<Membership> arenas;
  final String email;
  final String? message;
  final Future<void> Function(Membership) onPick;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String name, String ownerName) onCreate;
  final Future<void> Function() onSignOut;

  @override
  State<_ArenaPickScreen> createState() => _ArenaPickScreenState();
}

class _ArenaPickScreenState extends State<_ArenaPickScreen> {
  final _name = TextEditingController();
  final _owner = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text('Your arenas', style: ArenaType.h1.copyWith(color: arena.text)),
            const SizedBox(height: AppSpacing.sm),
            Text('Signed in as ${widget.email}',
                style: ArenaType.caption.copyWith(color: arena.textMuted)),
            if (widget.message != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(widget.message!,
                  style: ArenaType.label.copyWith(color: arena.warning)),
            ],
            const SizedBox(height: AppSpacing.lg),
            for (final a in widget.arenas)
              ListTile(
                title: Text(a.arenaName),
                subtitle: Text(a.active ? a.name : 'Access turned off'),
                enabled: a.active,
                trailing: const Icon(Icons.chevron_right),
                onTap: a.active ? () => widget.onPick(a) : null,
              ),
            if (widget.arenas.isEmpty)
              Text(
                'No arena has added you yet. Ask the owner to add '
                '${widget.email} in Settings → Staff, then refresh.',
                style: ArenaType.body.copyWith(color: arena.textMuted),
              ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: widget.onRefresh, child: const Text('Refresh')),
            const SizedBox(height: AppSpacing.xxl),
            Text('Starting a new arena?',
                style: ArenaType.h3.copyWith(color: arena.text)),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Arena name'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _owner,
              decoration: const InputDecoration(labelText: 'Your name'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: ArenaType.label.copyWith(color: arena.danger)),
            ],
            const SizedBox(height: AppSpacing.sm),
            FilledButton.tonal(
              onPressed: () async {
                try {
                  await widget.onCreate(_name.text.trim(), _owner.text.trim());
                } on Object catch (e) {
                  setState(() => _error = 'Could not create it ($e).');
                }
              },
              child: const Text('Create arena (you become its owner)'),
            ),
            const SizedBox(height: AppSpacing.xxl),
            TextButton(onPressed: widget.onSignOut, child: const Text('Sign out')),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action, this.onAction});
  final String text;
  final String? action;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (action == null) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: AppSpacing.lg),
                ],
                Text(text,
                    textAlign: TextAlign.center,
                    style: ArenaType.body.copyWith(color: arena.text)),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(onPressed: onAction, child: Text(action!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
