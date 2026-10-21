import 'dart:async';

import 'package:flutter/material.dart';

import '../result/result.dart';
import '../theme/app_theme.dart';

enum ToastKind { success, info, error }

/// The app's one feedback toast. Drawn on the root overlay, so it shows above
/// open sheets and dialogs (a SnackBar would sit under them). One at a time:
/// a new toast replaces the last, and the same text again only restarts it.
///
/// Take it before an await when the widget may be gone after (like a
/// ScaffoldMessenger): `final toast = AppToast.of(context);`.
class AppToast {
  AppToast._(this._overlay);

  factory AppToast.of(BuildContext context) =>
      AppToast._(Overlay.of(context, rootOverlay: true));

  final OverlayState _overlay;

  static OverlayEntry? _entry;
  static String? _text;
  static Timer? _timer;

  void show(String message, {ToastKind kind = ToastKind.success}) {
    if (!_overlay.mounted) return;
    final duration = kind == ToastKind.error
        ? const Duration(seconds: 6)
        : const Duration(seconds: 3);
    _timer?.cancel();
    if (_entry != null && _text == message) {
      _timer = Timer(duration, _hide);
      return;
    }
    _hide();
    final entry = OverlayEntry(
      builder: (_) => _ToastView(message: message, kind: kind, onTap: _hide),
    );
    _entry = entry;
    _text = message;
    _overlay.insert(entry);
    _timer = Timer(duration, _hide);
  }

  /// A refusal or error: the failure's own message and fix, never raw errors.
  void failure(Failure f) => show(f.display, kind: ToastKind.error);

  /// [done] when [r] succeeded, otherwise its failure.
  void result(Result<Object?> r, String done) => switch (r.failureOrNull) {
    final f? => failure(f),
    null => show(done),
  };

  static void _hide() {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    _entry = null;
    _text = null;
    if (entry != null && entry.mounted) entry.remove();
  }
}

void showToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.success,
}) => AppToast.of(context).show(message, kind: kind);

void showFailure(BuildContext context, Failure f) =>
    AppToast.of(context).failure(f);

void showResult(BuildContext context, Result<Object?> r, String done) =>
    AppToast.of(context).result(r, done);

class _ToastView extends StatelessWidget {
  const _ToastView({
    required this.message,
    required this.kind,
    required this.onTap,
  });

  final String message;
  final ToastKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final arena = context.arena;
    final media = MediaQuery.of(context);
    final (icon, color) = switch (kind) {
      ToastKind.success => (Icons.check_circle_outline, arena.success),
      ToastKind.info => (Icons.info_outline, arena.info),
      ToastKind.error => (Icons.error_outline, arena.danger),
    };
    return Positioned(
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      bottom: media.viewInsets.bottom + media.padding.bottom + AppSpacing.lg,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Semantics(
          liveRegion: true,
          child: Material(
            color: arena.surfaceRaised,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              side: BorderSide(
                color: kind == ToastKind.error ? arena.danger : arena.border,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.md),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        message,
                        style: ArenaType.body.copyWith(color: arena.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
