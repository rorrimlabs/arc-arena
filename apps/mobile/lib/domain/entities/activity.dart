import 'package:arena_ops/domain/pricing/rate.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'activity.freezed.dart';

/// An activity the center offers (spec §11). Defines whether it uses
/// controllers, uses games, and how its time is priced.
@freezed
abstract class Activity with _$Activity {
  const Activity._();

  const factory Activity({
    required String id,
    required String code, // PS5 | VR | POOL | LOUNGE
    required String name,
    required bool usesControllers,
    required bool usesGames,
    required DurationModel durationModel,
    @Default(0) int sortOrder,
    @Default(true) bool active,
  }) = _Activity;

  /// The pricing-only view of this activity used by the engine.
  ActivitySpec get spec => ActivitySpec(
        code: code,
        durationModel: durationModel,
      );
}
