// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'game.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Game {

 String get id; String get name; List<String> get aliases; String? get categoryId; String? get categoryName; List<String> get platforms; PlayerMode get playerMode; int get maxLocalPlayers; bool get active; DateTime? get lastPlayedAt;
/// Create a copy of Game
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameCopyWith<Game> get copyWith => _$GameCopyWithImpl<Game>(this as Game, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Game;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Game&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&const DeepCollectionEquality().equals(other.aliases, _this.aliases)&&(identical(other.categoryId, _this.categoryId) || other.categoryId == _this.categoryId)&&(identical(other.categoryName, _this.categoryName) || other.categoryName == _this.categoryName)&&const DeepCollectionEquality().equals(other.platforms, _this.platforms)&&(identical(other.playerMode, _this.playerMode) || other.playerMode == _this.playerMode)&&(identical(other.maxLocalPlayers, _this.maxLocalPlayers) || other.maxLocalPlayers == _this.maxLocalPlayers)&&(identical(other.active, _this.active) || other.active == _this.active)&&(identical(other.lastPlayedAt, _this.lastPlayedAt) || other.lastPlayedAt == _this.lastPlayedAt));
}


@override
int get hashCode {
  final _this = this as Game;
  return Object.hash(runtimeType,_this.id,_this.name,const DeepCollectionEquality().hash(_this.aliases),_this.categoryId,_this.categoryName,const DeepCollectionEquality().hash(_this.platforms),_this.playerMode,_this.maxLocalPlayers,_this.active,_this.lastPlayedAt);
}

@override
String toString() {
  final _this = this as Game;
  return 'Game(id: ${_this.id}, name: ${_this.name}, aliases: ${_this.aliases}, categoryId: ${_this.categoryId}, categoryName: ${_this.categoryName}, platforms: ${_this.platforms}, playerMode: ${_this.playerMode}, maxLocalPlayers: ${_this.maxLocalPlayers}, active: ${_this.active}, lastPlayedAt: ${_this.lastPlayedAt})';
}


}

/// @nodoc
abstract mixin class $GameCopyWith<$Res>  {
  factory $GameCopyWith(Game value, $Res Function(Game) _then) = _$GameCopyWithImpl;
@useResult
$Res call({
 String id, String name, List<String> aliases, String? categoryId, String? categoryName, List<String> platforms, PlayerMode playerMode, int maxLocalPlayers, bool active, DateTime? lastPlayedAt
});




}
/// @nodoc
class _$GameCopyWithImpl<$Res>
    implements $GameCopyWith<$Res> {
  _$GameCopyWithImpl(this._self, this._then);

  final Game _self;
  final $Res Function(Game) _then;

/// Create a copy of Game
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? aliases = null,Object? categoryId = freezed,Object? categoryName = freezed,Object? platforms = null,Object? playerMode = null,Object? maxLocalPlayers = null,Object? active = null,Object? lastPlayedAt = freezed,}) {
  return _then(Game(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,aliases: null == aliases ? _self.aliases : aliases // ignore: cast_nullable_to_non_nullable
as List<String>,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,categoryName: freezed == categoryName ? _self.categoryName : categoryName // ignore: cast_nullable_to_non_nullable
as String?,platforms: null == platforms ? _self.platforms : platforms // ignore: cast_nullable_to_non_nullable
as List<String>,playerMode: null == playerMode ? _self.playerMode : playerMode // ignore: cast_nullable_to_non_nullable
as PlayerMode,maxLocalPlayers: null == maxLocalPlayers ? _self.maxLocalPlayers : maxLocalPlayers // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,lastPlayedAt: freezed == lastPlayedAt ? _self.lastPlayedAt : lastPlayedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [Game].
extension GamePatterns on Game {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Game value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Game() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Game value)  $default,){
final _that = this;
switch (_that) {
case _Game():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Game value)?  $default,){
final _that = this;
switch (_that) {
case _Game() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  List<String> aliases,  String? categoryId,  String? categoryName,  List<String> platforms,  PlayerMode playerMode,  int maxLocalPlayers,  bool active,  DateTime? lastPlayedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Game() when $default != null:
return $default(_that.id,_that.name,_that.aliases,_that.categoryId,_that.categoryName,_that.platforms,_that.playerMode,_that.maxLocalPlayers,_that.active,_that.lastPlayedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  List<String> aliases,  String? categoryId,  String? categoryName,  List<String> platforms,  PlayerMode playerMode,  int maxLocalPlayers,  bool active,  DateTime? lastPlayedAt)  $default,) {final _that = this;
switch (_that) {
case _Game():
return $default(_that.id,_that.name,_that.aliases,_that.categoryId,_that.categoryName,_that.platforms,_that.playerMode,_that.maxLocalPlayers,_that.active,_that.lastPlayedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  List<String> aliases,  String? categoryId,  String? categoryName,  List<String> platforms,  PlayerMode playerMode,  int maxLocalPlayers,  bool active,  DateTime? lastPlayedAt)?  $default,) {final _that = this;
switch (_that) {
case _Game() when $default != null:
return $default(_that.id,_that.name,_that.aliases,_that.categoryId,_that.categoryName,_that.platforms,_that.playerMode,_that.maxLocalPlayers,_that.active,_that.lastPlayedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Game implements Game {
  const _Game({required this.id, required this.name,  List<String> aliases = const <String>[], this.categoryId, this.categoryName,  List<String> platforms = const <String>[], this.playerMode = PlayerMode.single, this.maxLocalPlayers = 1, this.active = true, this.lastPlayedAt}): _aliases = aliases,_platforms = platforms;
  

@override final  String id;
@override final  String name;
 final  List<String> _aliases;
@override@JsonKey() List<String> get aliases {
  if (_aliases is EqualUnmodifiableListView) return _aliases;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_aliases);
}

@override final  String? categoryId;
@override final  String? categoryName;
 final  List<String> _platforms;
@override@JsonKey() List<String> get platforms {
  if (_platforms is EqualUnmodifiableListView) return _platforms;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_platforms);
}

@override@JsonKey() final  PlayerMode playerMode;
@override@JsonKey() final  int maxLocalPlayers;
@override@JsonKey() final  bool active;
@override final  DateTime? lastPlayedAt;

/// Create a copy of Game
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameCopyWith<_Game> get copyWith => __$GameCopyWithImpl<_Game>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Game&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&const DeepCollectionEquality().equals(other.aliases, _aliases)&&(identical(other.categoryId, categoryId) || other.categoryId == categoryId)&&(identical(other.categoryName, categoryName) || other.categoryName == categoryName)&&const DeepCollectionEquality().equals(other.platforms, _platforms)&&(identical(other.playerMode, playerMode) || other.playerMode == playerMode)&&(identical(other.maxLocalPlayers, maxLocalPlayers) || other.maxLocalPlayers == maxLocalPlayers)&&(identical(other.active, active) || other.active == active)&&(identical(other.lastPlayedAt, lastPlayedAt) || other.lastPlayedAt == lastPlayedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,const DeepCollectionEquality().hash(_aliases),categoryId,categoryName,const DeepCollectionEquality().hash(_platforms),playerMode,maxLocalPlayers,active,lastPlayedAt);
}

@override
String toString() {
    return 'Game(id: $id, name: $name, aliases: $aliases, categoryId: $categoryId, categoryName: $categoryName, platforms: $platforms, playerMode: $playerMode, maxLocalPlayers: $maxLocalPlayers, active: $active, lastPlayedAt: $lastPlayedAt)';
}


}

/// @nodoc
abstract mixin class _$GameCopyWith<$Res> implements $GameCopyWith<$Res> {
  factory _$GameCopyWith(_Game value, $Res Function(_Game) _then) = __$GameCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, List<String> aliases, String? categoryId, String? categoryName, List<String> platforms, PlayerMode playerMode, int maxLocalPlayers, bool active, DateTime? lastPlayedAt
});




}
/// @nodoc
class __$GameCopyWithImpl<$Res>
    implements _$GameCopyWith<$Res> {
  __$GameCopyWithImpl(this._self, this._then);

  final _Game _self;
  final $Res Function(_Game) _then;

/// Create a copy of Game
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? aliases = null,Object? categoryId = freezed,Object? categoryName = freezed,Object? platforms = null,Object? playerMode = null,Object? maxLocalPlayers = null,Object? active = null,Object? lastPlayedAt = freezed,}) {
  return _then(_Game(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,aliases: null == aliases ? _self._aliases : aliases // ignore: cast_nullable_to_non_nullable
as List<String>,categoryId: freezed == categoryId ? _self.categoryId : categoryId // ignore: cast_nullable_to_non_nullable
as String?,categoryName: freezed == categoryName ? _self.categoryName : categoryName // ignore: cast_nullable_to_non_nullable
as String?,platforms: null == platforms ? _self._platforms : platforms // ignore: cast_nullable_to_non_nullable
as List<String>,playerMode: null == playerMode ? _self.playerMode : playerMode // ignore: cast_nullable_to_non_nullable
as PlayerMode,maxLocalPlayers: null == maxLocalPlayers ? _self.maxLocalPlayers : maxLocalPlayers // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,lastPlayedAt: freezed == lastPlayedAt ? _self.lastPlayedAt : lastPlayedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc
mixin _$GameResource {

 String get gameId; String get resourceId; GameAvailability get status;/// Why the game is in this state on this system ("disc scratched").
 String? get notes; DateTime? get updatedAt;
/// Create a copy of GameResource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameResourceCopyWith<GameResource> get copyWith => _$GameResourceCopyWithImpl<GameResource>(this as GameResource, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GameResource;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameResource&&(identical(other.gameId, _this.gameId) || other.gameId == _this.gameId)&&(identical(other.resourceId, _this.resourceId) || other.resourceId == _this.resourceId)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.notes, _this.notes) || other.notes == _this.notes)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as GameResource;
  return Object.hash(runtimeType,_this.gameId,_this.resourceId,_this.status,_this.notes,_this.updatedAt);
}

@override
String toString() {
  final _this = this as GameResource;
  return 'GameResource(gameId: ${_this.gameId}, resourceId: ${_this.resourceId}, status: ${_this.status}, notes: ${_this.notes}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $GameResourceCopyWith<$Res>  {
  factory $GameResourceCopyWith(GameResource value, $Res Function(GameResource) _then) = _$GameResourceCopyWithImpl;
@useResult
$Res call({
 String gameId, String resourceId, GameAvailability status, String? notes, DateTime? updatedAt
});




}
/// @nodoc
class _$GameResourceCopyWithImpl<$Res>
    implements $GameResourceCopyWith<$Res> {
  _$GameResourceCopyWithImpl(this._self, this._then);

  final GameResource _self;
  final $Res Function(GameResource) _then;

/// Create a copy of GameResource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? gameId = null,Object? resourceId = null,Object? status = null,Object? notes = freezed,Object? updatedAt = freezed,}) {
  return _then(GameResource(
gameId: null == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String,resourceId: null == resourceId ? _self.resourceId : resourceId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as GameAvailability,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [GameResource].
extension GameResourcePatterns on GameResource {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameResource value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameResource() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameResource value)  $default,){
final _that = this;
switch (_that) {
case _GameResource():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameResource value)?  $default,){
final _that = this;
switch (_that) {
case _GameResource() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String gameId,  String resourceId,  GameAvailability status,  String? notes,  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameResource() when $default != null:
return $default(_that.gameId,_that.resourceId,_that.status,_that.notes,_that.updatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String gameId,  String resourceId,  GameAvailability status,  String? notes,  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _GameResource():
return $default(_that.gameId,_that.resourceId,_that.status,_that.notes,_that.updatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String gameId,  String resourceId,  GameAvailability status,  String? notes,  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _GameResource() when $default != null:
return $default(_that.gameId,_that.resourceId,_that.status,_that.notes,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _GameResource implements GameResource {
  const _GameResource({required this.gameId, required this.resourceId, required this.status, this.notes, this.updatedAt});
  

@override final  String gameId;
@override final  String resourceId;
@override final  GameAvailability status;
/// Why the game is in this state on this system ("disc scratched").
@override final  String? notes;
@override final  DateTime? updatedAt;

/// Create a copy of GameResource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameResourceCopyWith<_GameResource> get copyWith => __$GameResourceCopyWithImpl<_GameResource>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameResource&&(identical(other.gameId, gameId) || other.gameId == gameId)&&(identical(other.resourceId, resourceId) || other.resourceId == resourceId)&&(identical(other.status, status) || other.status == status)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,gameId,resourceId,status,notes,updatedAt);
}

@override
String toString() {
    return 'GameResource(gameId: $gameId, resourceId: $resourceId, status: $status, notes: $notes, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$GameResourceCopyWith<$Res> implements $GameResourceCopyWith<$Res> {
  factory _$GameResourceCopyWith(_GameResource value, $Res Function(_GameResource) _then) = __$GameResourceCopyWithImpl;
@override @useResult
$Res call({
 String gameId, String resourceId, GameAvailability status, String? notes, DateTime? updatedAt
});




}
/// @nodoc
class __$GameResourceCopyWithImpl<$Res>
    implements _$GameResourceCopyWith<$Res> {
  __$GameResourceCopyWithImpl(this._self, this._then);

  final _GameResource _self;
  final $Res Function(_GameResource) _then;

/// Create a copy of GameResource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? gameId = null,Object? resourceId = null,Object? status = null,Object? notes = freezed,Object? updatedAt = freezed,}) {
  return _then(_GameResource(
gameId: null == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String,resourceId: null == resourceId ? _self.resourceId : resourceId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as GameAvailability,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

/// @nodoc
mixin _$GameCategory {

 String get id; String get name; int get sortOrder;
/// Create a copy of GameCategory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameCategoryCopyWith<GameCategory> get copyWith => _$GameCategoryCopyWithImpl<GameCategory>(this as GameCategory, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GameCategory;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameCategory&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.sortOrder, _this.sortOrder) || other.sortOrder == _this.sortOrder));
}


@override
int get hashCode {
  final _this = this as GameCategory;
  return Object.hash(runtimeType,_this.id,_this.name,_this.sortOrder);
}

@override
String toString() {
  final _this = this as GameCategory;
  return 'GameCategory(id: ${_this.id}, name: ${_this.name}, sortOrder: ${_this.sortOrder})';
}


}

/// @nodoc
abstract mixin class $GameCategoryCopyWith<$Res>  {
  factory $GameCategoryCopyWith(GameCategory value, $Res Function(GameCategory) _then) = _$GameCategoryCopyWithImpl;
@useResult
$Res call({
 String id, String name, int sortOrder
});




}
/// @nodoc
class _$GameCategoryCopyWithImpl<$Res>
    implements $GameCategoryCopyWith<$Res> {
  _$GameCategoryCopyWithImpl(this._self, this._then);

  final GameCategory _self;
  final $Res Function(GameCategory) _then;

/// Create a copy of GameCategory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? sortOrder = null,}) {
  return _then(GameCategory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [GameCategory].
extension GameCategoryPatterns on GameCategory {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameCategory value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameCategory() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameCategory value)  $default,){
final _that = this;
switch (_that) {
case _GameCategory():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameCategory value)?  $default,){
final _that = this;
switch (_that) {
case _GameCategory() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  int sortOrder)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameCategory() when $default != null:
return $default(_that.id,_that.name,_that.sortOrder);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  int sortOrder)  $default,) {final _that = this;
switch (_that) {
case _GameCategory():
return $default(_that.id,_that.name,_that.sortOrder);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  int sortOrder)?  $default,) {final _that = this;
switch (_that) {
case _GameCategory() when $default != null:
return $default(_that.id,_that.name,_that.sortOrder);case _:
  return null;

}
}

}

/// @nodoc


class _GameCategory implements GameCategory {
  const _GameCategory({required this.id, required this.name, this.sortOrder = 0});
  

@override final  String id;
@override final  String name;
@override@JsonKey() final  int sortOrder;

/// Create a copy of GameCategory
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameCategoryCopyWith<_GameCategory> get copyWith => __$GameCategoryCopyWithImpl<_GameCategory>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameCategory&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,sortOrder);
}

@override
String toString() {
    return 'GameCategory(id: $id, name: $name, sortOrder: $sortOrder)';
}


}

/// @nodoc
abstract mixin class _$GameCategoryCopyWith<$Res> implements $GameCategoryCopyWith<$Res> {
  factory _$GameCategoryCopyWith(_GameCategory value, $Res Function(_GameCategory) _then) = __$GameCategoryCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, int sortOrder
});




}
/// @nodoc
class __$GameCategoryCopyWithImpl<$Res>
    implements _$GameCategoryCopyWith<$Res> {
  __$GameCategoryCopyWithImpl(this._self, this._then);

  final _GameCategory _self;
  final $Res Function(_GameCategory) _then;

/// Create a copy of GameCategory
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? sortOrder = null,}) {
  return _then(_GameCategory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$GameControl {

 String get id; String get gameId; String get section; String get action; List<String> get buttons; String? get explanation; String? get notes; String? get imageUrl; int get sortOrder;
/// Create a copy of GameControl
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GameControlCopyWith<GameControl> get copyWith => _$GameControlCopyWithImpl<GameControl>(this as GameControl, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GameControl;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GameControl&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.gameId, _this.gameId) || other.gameId == _this.gameId)&&(identical(other.section, _this.section) || other.section == _this.section)&&(identical(other.action, _this.action) || other.action == _this.action)&&const DeepCollectionEquality().equals(other.buttons, _this.buttons)&&(identical(other.explanation, _this.explanation) || other.explanation == _this.explanation)&&(identical(other.notes, _this.notes) || other.notes == _this.notes)&&(identical(other.imageUrl, _this.imageUrl) || other.imageUrl == _this.imageUrl)&&(identical(other.sortOrder, _this.sortOrder) || other.sortOrder == _this.sortOrder));
}


@override
int get hashCode {
  final _this = this as GameControl;
  return Object.hash(runtimeType,_this.id,_this.gameId,_this.section,_this.action,const DeepCollectionEquality().hash(_this.buttons),_this.explanation,_this.notes,_this.imageUrl,_this.sortOrder);
}

@override
String toString() {
  final _this = this as GameControl;
  return 'GameControl(id: ${_this.id}, gameId: ${_this.gameId}, section: ${_this.section}, action: ${_this.action}, buttons: ${_this.buttons}, explanation: ${_this.explanation}, notes: ${_this.notes}, imageUrl: ${_this.imageUrl}, sortOrder: ${_this.sortOrder})';
}


}

/// @nodoc
abstract mixin class $GameControlCopyWith<$Res>  {
  factory $GameControlCopyWith(GameControl value, $Res Function(GameControl) _then) = _$GameControlCopyWithImpl;
@useResult
$Res call({
 String id, String gameId, String section, String action, List<String> buttons, String? explanation, String? notes, String? imageUrl, int sortOrder
});




}
/// @nodoc
class _$GameControlCopyWithImpl<$Res>
    implements $GameControlCopyWith<$Res> {
  _$GameControlCopyWithImpl(this._self, this._then);

  final GameControl _self;
  final $Res Function(GameControl) _then;

/// Create a copy of GameControl
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? gameId = null,Object? section = null,Object? action = null,Object? buttons = null,Object? explanation = freezed,Object? notes = freezed,Object? imageUrl = freezed,Object? sortOrder = null,}) {
  return _then(GameControl(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,gameId: null == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String,section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as String,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String,buttons: null == buttons ? _self.buttons : buttons // ignore: cast_nullable_to_non_nullable
as List<String>,explanation: freezed == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,imageUrl: freezed == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String?,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [GameControl].
extension GameControlPatterns on GameControl {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GameControl value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GameControl() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GameControl value)  $default,){
final _that = this;
switch (_that) {
case _GameControl():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GameControl value)?  $default,){
final _that = this;
switch (_that) {
case _GameControl() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String gameId,  String section,  String action,  List<String> buttons,  String? explanation,  String? notes,  String? imageUrl,  int sortOrder)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GameControl() when $default != null:
return $default(_that.id,_that.gameId,_that.section,_that.action,_that.buttons,_that.explanation,_that.notes,_that.imageUrl,_that.sortOrder);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String gameId,  String section,  String action,  List<String> buttons,  String? explanation,  String? notes,  String? imageUrl,  int sortOrder)  $default,) {final _that = this;
switch (_that) {
case _GameControl():
return $default(_that.id,_that.gameId,_that.section,_that.action,_that.buttons,_that.explanation,_that.notes,_that.imageUrl,_that.sortOrder);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String gameId,  String section,  String action,  List<String> buttons,  String? explanation,  String? notes,  String? imageUrl,  int sortOrder)?  $default,) {final _that = this;
switch (_that) {
case _GameControl() when $default != null:
return $default(_that.id,_that.gameId,_that.section,_that.action,_that.buttons,_that.explanation,_that.notes,_that.imageUrl,_that.sortOrder);case _:
  return null;

}
}

}

/// @nodoc


class _GameControl implements GameControl {
  const _GameControl({required this.id, required this.gameId, required this.section, required this.action,  List<String> buttons = const <String>[], this.explanation, this.notes, this.imageUrl, this.sortOrder = 0}): _buttons = buttons;
  

@override final  String id;
@override final  String gameId;
@override final  String section;
@override final  String action;
 final  List<String> _buttons;
@override@JsonKey() List<String> get buttons {
  if (_buttons is EqualUnmodifiableListView) return _buttons;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_buttons);
}

@override final  String? explanation;
@override final  String? notes;
@override final  String? imageUrl;
@override@JsonKey() final  int sortOrder;

/// Create a copy of GameControl
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GameControlCopyWith<_GameControl> get copyWith => __$GameControlCopyWithImpl<_GameControl>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GameControl&&(identical(other.id, id) || other.id == id)&&(identical(other.gameId, gameId) || other.gameId == gameId)&&(identical(other.section, section) || other.section == section)&&(identical(other.action, action) || other.action == action)&&const DeepCollectionEquality().equals(other.buttons, _buttons)&&(identical(other.explanation, explanation) || other.explanation == explanation)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.imageUrl, imageUrl) || other.imageUrl == imageUrl)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,gameId,section,action,const DeepCollectionEquality().hash(_buttons),explanation,notes,imageUrl,sortOrder);
}

@override
String toString() {
    return 'GameControl(id: $id, gameId: $gameId, section: $section, action: $action, buttons: $buttons, explanation: $explanation, notes: $notes, imageUrl: $imageUrl, sortOrder: $sortOrder)';
}


}

/// @nodoc
abstract mixin class _$GameControlCopyWith<$Res> implements $GameControlCopyWith<$Res> {
  factory _$GameControlCopyWith(_GameControl value, $Res Function(_GameControl) _then) = __$GameControlCopyWithImpl;
@override @useResult
$Res call({
 String id, String gameId, String section, String action, List<String> buttons, String? explanation, String? notes, String? imageUrl, int sortOrder
});




}
/// @nodoc
class __$GameControlCopyWithImpl<$Res>
    implements _$GameControlCopyWith<$Res> {
  __$GameControlCopyWithImpl(this._self, this._then);

  final _GameControl _self;
  final $Res Function(_GameControl) _then;

/// Create a copy of GameControl
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? gameId = null,Object? section = null,Object? action = null,Object? buttons = null,Object? explanation = freezed,Object? notes = freezed,Object? imageUrl = freezed,Object? sortOrder = null,}) {
  return _then(_GameControl(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,gameId: null == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String,section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as String,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as String,buttons: null == buttons ? _self._buttons : buttons // ignore: cast_nullable_to_non_nullable
as List<String>,explanation: freezed == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,imageUrl: freezed == imageUrl ? _self.imageUrl : imageUrl // ignore: cast_nullable_to_non_nullable
as String?,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
