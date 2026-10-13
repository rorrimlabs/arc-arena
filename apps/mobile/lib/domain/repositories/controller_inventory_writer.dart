import 'package:arena_ops/core/result/result.dart';
import 'package:arena_ops/domain/entities/controller.dart';

/// Where a physical pad stands, and which mode a dual-capability station is
/// locked to — the inventory writes that are not part of a session.
///
/// The app layer (`CatalogActions`) checks who may do each of these before
/// calling; the implementation still refuses a move that would split a pad
/// from a running session, and a mode change on a busy station.
abstract interface class ControllerInventoryWriter {
  /// Walk a pad to another station: a [ControllerMoveKind.loan] (returns
  /// home later), a [ControllerMoveKind.permanent] re-home, or
  /// [ControllerMoveKind.returnHome].
  Future<Result<void>> moveController({
    required String controllerId,
    required String toResourceId,
    required ControllerMoveKind kind,
    String? loanSessionRef,
  });

  /// Lock a dual-capability station (RIFT) to one activity, or clear the lock
  /// with [mode] = null.
  Future<Result<void>> setResourceMode(String resourceId, String? mode);
}
