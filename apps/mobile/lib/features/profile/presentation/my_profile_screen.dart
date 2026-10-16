/// My profile: the staff member's own contact details, date of birth, blood
/// group, address and emergency contact. Every field is optional; a blank one
/// clears what was saved. Online only, like leave.
library;

import 'package:arena_ops/app/controllers/profile_actions.dart';
import 'package:arena_ops/app/providers/core_providers.dart';
import 'package:arena_ops/app/providers/profile_providers.dart';
import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/core/theme/app_theme.dart';
import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/core/widgets/app_toast.dart';
import 'package:arena_ops/domain/profile/staff_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MyProfileScreen extends ConsumerWidget {
  const MyProfileScreen({super.key});

  static const String path = '/more/profile';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arena = context.arena;
    final details = ref.watch(myStaffDetailsProvider);
    void retry() => ref.invalidate(myStaffDetailsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      backgroundColor: arena.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: switch (details) {
              AsyncData(value: Ok(value: final d)) => _DetailsForm(initial: d),
              AsyncData(value: Err(failure: final f)) => _FailureView(
                  failure: f,
                  onRetry: f.code == 'profile_needs_cloud' ? null : retry,
                ),
              AsyncError() => _FailureView(
                  failure: ProfileActions.detailsLoadFailed,
                  onRetry: retry,
                ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ),
      ),
    );
  }
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.failure, this.onRetry});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: arena.dangerSoft,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(failure.message,
                  style: ArenaType.label.copyWith(color: arena.danger)),
              if (failure.fix != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(failure.fix!, style: ArenaType.body.copyWith(color: arena.text)),
              ],
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ],
    );
  }
}

/// The text fields of the form, in order (date and blood group are pickers).
const _textFields = [
  StaffDetailsField.phone,
  StaffDetailsField.email,
  StaffDetailsField.addressLine1,
  StaffDetailsField.addressLine2,
  StaffDetailsField.city,
  StaffDetailsField.state,
  StaffDetailsField.pinCode,
  StaffDetailsField.emergencyName,
  StaffDetailsField.emergencyRelation,
  StaffDetailsField.emergencyPhone,
];

class _DetailsForm extends ConsumerStatefulWidget {
  const _DetailsForm({required this.initial});

  final StaffDetails initial;

  @override
  ConsumerState<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends ConsumerState<_DetailsForm> {
  late final Map<StaffDetailsField, TextEditingController> _text = {
    for (final f in _textFields)
      f: TextEditingController(text: widget.initial.valueOf(f) ?? ''),
  };
  late IstDate? _birthDate = widget.initial.birthDate;
  late String? _bloodGroup =
      bloodGroups.contains(widget.initial.bloodGroup) ? widget.initial.bloodGroup : null;

  Map<StaffDetailsField, Failure> _errors = const {};
  bool _busy = false;
  Failure? _failure;

  /// Kept to resend with the same op id after a dropped connection.
  StaffDetailsCommand? _unsent;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  StaffDetails _details() {
    String t(StaffDetailsField f) => _text[f]!.text;
    return StaffDetails(
      phone: t(StaffDetailsField.phone),
      email: t(StaffDetailsField.email),
      birthDate: _birthDate,
      bloodGroup: _bloodGroup,
      addressLine1: t(StaffDetailsField.addressLine1),
      addressLine2: t(StaffDetailsField.addressLine2),
      city: t(StaffDetailsField.city),
      state: t(StaffDetailsField.state),
      pinCode: t(StaffDetailsField.pinCode),
      emergencyName: t(StaffDetailsField.emergencyName),
      emergencyRelation: t(StaffDetailsField.emergencyRelation),
      emergencyPhone: t(StaffDetailsField.emergencyPhone),
    );
  }

  void _edited(StaffDetailsField f) {
    _unsent = null;
    if (_errors.containsKey(f)) setState(() => _errors = {..._errors}..remove(f));
  }

  Future<void> _pickBirthDate() async {
    final today = IstDate.fromUtc(ref.read(clockProvider).now());
    final current = _birthDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null
          ? DateTime(today.year - 25, today.month, 1)
          : DateTime(current.year, current.month, current.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null || !mounted) return;
    setState(() => _birthDate = IstDate(picked.year, picked.month, picked.day));
    _edited(StaffDetailsField.birthDate);
  }

  Future<void> _save() async {
    final actions = ref.read(profileActionsProvider);
    final details = _details();
    final errors = actions.checkDetails(details);
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _failure = ProfileActions.fieldsToFix;
      });
      return;
    }
    final cmd = _unsent ?? actions.prepareDetails(details);
    setState(() {
      _busy = true;
      _failure = null;
      _errors = const {};
    });
    final res = await actions.saveDetails(cmd);
    if (!mounted) return;
    switch (res) {
      case Ok():
        setState(() {
          _busy = false;
          _unsent = null;
        });
        showToast(context, 'Your details are saved.');
      case Err(failure: final f):
        setState(() {
          _busy = false;
          _failure = f;
          _unsent = f.code == 'offline' || f.code == 'retry' ? cmd : null;
        });
    }
  }

  Widget _field(
    StaffDetailsField f, {
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    TextCapitalization caps = TextCapitalization.none,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: TextField(
          controller: _text[f],
          enabled: !_busy,
          keyboardType: keyboard,
          inputFormatters: formatters,
          textCapitalization: caps,
          maxLength: f.maxLength,
          decoration: InputDecoration(
            labelText: f.label,
            errorText: _errors[f]?.display,
            errorMaxLines: 3,
            counterText: '',
          ),
          onChanged: (_) => _edited(f),
        ),
      );

  Widget _section(String title) {
    final arena = context.arena;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Text(title, style: ArenaType.h3.copyWith(color: arena.text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final birth = _birthDate;
    final birthError = _errors[StaffDetailsField.birthDate];
    final bloodError = _errors[StaffDetailsField.bloodGroup];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
      children: [
        Text('All optional. The owner sees these details; leave a field blank to '
            'clear it.',
            style: ArenaType.caption.copyWith(color: arena.textMuted)),
        _section('Contact'),
        _field(StaffDetailsField.phone, keyboard: TextInputType.phone),
        _field(StaffDetailsField.email, keyboard: TextInputType.emailAddress),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickBirthDate,
              icon: const Icon(Icons.cake_outlined),
              label: Text(birth == null
                  ? 'Date of birth'
                  : DateFormat('d MMM yyyy')
                      .format(DateTime.utc(birth.year, birth.month, birth.day))),
            ),
          ),
          if (birth != null)
            IconButton(
              tooltip: 'Clear date of birth',
              onPressed: _busy
                  ? null
                  : () {
                      setState(() => _birthDate = null);
                      _edited(StaffDetailsField.birthDate);
                    },
              icon: const Icon(Icons.close_rounded),
            ),
        ]),
        if (birthError != null)
          Text(birthError.display,
              style: ArenaType.caption.copyWith(color: arena.danger)),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String?>(
          initialValue: _bloodGroup,
          decoration: InputDecoration(
            labelText: StaffDetailsField.bloodGroup.label,
            errorText: bloodError?.display,
          ),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Not set')),
            for (final g in bloodGroups)
              DropdownMenuItem<String?>(value: g, child: Text(g)),
          ],
          onChanged: _busy
              ? null
              : (g) {
                  setState(() => _bloodGroup = g);
                  _edited(StaffDetailsField.bloodGroup);
                },
        ),
        _section('Address'),
        _field(StaffDetailsField.addressLine1, caps: TextCapitalization.words),
        _field(StaffDetailsField.addressLine2, caps: TextCapitalization.words),
        _field(StaffDetailsField.city, caps: TextCapitalization.words),
        _field(StaffDetailsField.state, caps: TextCapitalization.words),
        _field(StaffDetailsField.pinCode,
            keyboard: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly]),
        _section('Emergency contact'),
        _field(StaffDetailsField.emergencyName, caps: TextCapitalization.words),
        _field(StaffDetailsField.emergencyRelation, caps: TextCapitalization.words),
        _field(StaffDetailsField.emergencyPhone, keyboard: TextInputType.phone),
        if (_failure != null) ...[
          Text(_failure!.message, style: ArenaType.label.copyWith(color: arena.danger)),
          if (_failure!.fix != null)
            Text(_failure!.fix!, style: ArenaType.body.copyWith(color: arena.text)),
          const SizedBox(height: AppSpacing.md),
        ],
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: AppSpacing.minTarget,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy
                ? 'Saving…'
                : _unsent != null
                    ? 'Try again'
                    : 'Save'),
          ),
        ),
      ],
    );
  }
}
