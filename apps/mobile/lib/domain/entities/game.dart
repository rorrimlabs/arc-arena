import 'package:arena_ops/domain/value/enums.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'game.freezed.dart';

/// A game in the library (spec §3, §22). Disabled games stay for history but
/// drop out of active pickers. A game is never globally available — whether it
/// runs on a given resource is held in [GameResource] compatibility rows.
@freezed
abstract class Game with _$Game {
  const factory Game({
    required String id,
    required String name,
    @Default(<String>[]) List<String> aliases,
    String? categoryId,
    String? categoryName,
    @Default(<String>[]) List<String> platforms,
    @Default(PlayerMode.single) PlayerMode playerMode,
    @Default(1) int maxLocalPlayers,
    @Default(true) bool active,
    DateTime? lastPlayedAt,
  }) = _Game;
}

/// Compatibility of one game with one resource (spec §4). Editable by staff.
@freezed
abstract class GameResource with _$GameResource {
  const factory GameResource({
    required String gameId,
    required String resourceId,
    required GameAvailability status,
    /// Why the game is in this state on this system ("disc scratched").
    String? notes,
    DateTime? updatedAt,
  }) = _GameResource;
}

@freezed
abstract class GameCategory with _$GameCategory {
  const factory GameCategory({
    required String id,
    required String name,
    @Default(0) int sortOrder,
  }) = _GameCategory;
}

/// One control-guide row (spec §23). Buttons are stored as tokens (CROSS, R2 …),
/// never free text, so the UI can render PlayStation glyphs.
@freezed
abstract class GameControl with _$GameControl {
  const factory GameControl({
    required String id,
    required String gameId,
    required String section, // Attacking, Defending ...
    required String action, // Shoot, Short Pass ...
    @Default(<String>[]) List<String> buttons, // button tokens
    String? explanation,
    String? notes,
    String? imageUrl,
    @Default(0) int sortOrder,
  }) = _GameControl;
}
