/// The staff terms gate: shown instead of the app until a member who is not
/// owner level has accepted the version in force. The agree box unlocks once
/// the text has been scrolled to the end; Accept sends the acceptance. While
/// the check runs or cannot run, this screen (with Retry and Sign out) is all
/// there is.
library;

import 'package:arena_ops/app/auth/auth_controller.dart';
import 'package:arena_ops/app/controllers/profile_actions.dart';
import 'package:arena_ops/app/providers/profile_providers.dart';
import 'package:arena_ops/app/sync/cloud_binding.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/confirm_dialog.dart';
import 'package:arena_ops/domain/profile/staff_terms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class TermsScreen extends ConsumerStatefulWidget {
  const TermsScreen({super.key});

  static const String path = '/terms';

  @override
  ConsumerState<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends ConsumerState<TermsScreen> {
  /// Why the text changed under the reader (a newer version was published).
  Failure? _notice;

  Future<void> _stale(Failure f) async {
    setState(() => _notice = f);
    await ref.read(termsGateProvider.notifier).check();
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final gate = ref.watch(termsGateProvider);
    return Scaffold(
      backgroundColor: arena.bg,
      appBar: AppBar(
        title: const Text('Staff terms'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () async {
              // As on More: say so before leaving changes unsent.
              final pending = ref.read(syncStatusProvider).value?.pending ?? 0;
              if (pending > 0 &&
                  !await confirmAction(
                    context,
                    title: 'Changes not sent yet',
                    message: '$pending change(s) have not reached the server. '
                        'They stay on this device and are sent the next time '
                        'you sign in here.',
                    cancel: 'Stay signed in',
                    confirm: 'Sign out',
                  )) {
                return;
              }
              ref.read(authControllerProvider.notifier).signOut();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: switch (gate) {
              TermsGateBlocked(terms: final t) => _TermsReader(
                  key: ValueKey(t.id),
                  terms: t,
                  notice: _notice,
                  onStale: _stale,
                ),
              TermsGateFailed(failure: final f) => ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    _FailureCard(
                      failure: f,
                      onRetry: () => ref.read(termsGateProvider.notifier).check(),
                    ),
                  ],
                ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ),
    );
  }
}

class _TermsReader extends ConsumerStatefulWidget {
  const _TermsReader({
    super.key,
    required this.terms,
    required this.notice,
    required this.onStale,
  });

  final StaffTerms terms;
  final Failure? notice;
  final Future<void> Function(Failure f) onStale;

  @override
  ConsumerState<_TermsReader> createState() => _TermsReaderState();
}

class _TermsReaderState extends ConsumerState<_TermsReader> {
  final _scroll = ScrollController();
  bool _readToEnd = false;
  bool _agreed = false;
  bool _busy = false;
  Failure? _failure;

  /// Kept to resend with the same id after a dropped connection.
  TermsAcceptCommand? _unsent;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_checkEnd);
    // Text that fits without scrolling counts as read.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkEnd());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _checkEnd() {
    if (_readToEnd || !mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - AppSpacing.xl) {
      setState(() => _readToEnd = true);
    }
  }

  Future<void> _accept() async {
    final actions = ref.read(profileActionsProvider);
    final cmd = _unsent ?? actions.prepareAcceptance(widget.terms);
    setState(() {
      _busy = true;
      _failure = null;
    });
    final res = await actions.acceptTerms(cmd);
    if (!mounted) return;
    switch (res) {
      case Ok():
        ref.read(termsGateProvider.notifier).accepted();
      case Err(failure: final f) when f.code == 'stale':
        setState(() {
          _busy = false;
          _unsent = null;
        });
        await widget.onStale(f);
      case Err(failure: final f):
        setState(() {
          _busy = false;
          _failure = f;
          _unsent = f.code == 'offline' || f.code == 'retry' ? cmd : null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final t = widget.terms;
    final notice = widget.notice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              _checkEnd();
              return false;
            },
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (notice != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: arena.warningSoft,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Text(notice.display,
                          style: ArenaType.body.copyWith(color: arena.text)),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  Text(t.title, style: ArenaType.h2.copyWith(color: arena.text)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Version ${t.version} · published ${_date(IstDate.fromUtc(t.publishedAt))}',
                    style: ArenaType.caption.copyWith(color: arena.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final p in t.paragraphs) ...[
                    Text(p, style: ArenaType.body.copyWith(color: arena.text)),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
          decoration: BoxDecoration(
            color: arena.surface,
            border: Border(top: BorderSide(color: arena.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _agreed,
                onChanged: !_readToEnd || _busy
                    ? null
                    : (v) => setState(() => _agreed = v ?? false),
                title: const Text('I have read and agree to these terms'),
                subtitle: _readToEnd ? null : const Text('Scroll to the end to agree.'),
              ),
              if (_failure != null) ...[
                Text(_failure!.message,
                    style: ArenaType.label.copyWith(color: arena.danger)),
                if (_failure!.fix != null)
                  Text(_failure!.fix!,
                      style: ArenaType.body.copyWith(color: arena.text)),
                const SizedBox(height: AppSpacing.sm),
              ],
              SizedBox(
                height: AppSpacing.minTarget,
                child: FilledButton(
                  onPressed: _agreed && !_busy ? _accept : null,
                  child: Text(_busy
                      ? 'Sending…'
                      : _unsent != null
                          ? 'Try again'
                          : 'Accept'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _date(IstDate d) =>
    DateFormat('d MMM yyyy').format(DateTime.utc(d.year, d.month, d.day));

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.failure, required this.onRetry});

  final Failure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: arena.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(failure.message, style: ArenaType.label.copyWith(color: arena.danger)),
          if (failure.fix != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(failure.fix!, style: ArenaType.body.copyWith(color: arena.text)),
          ],
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
