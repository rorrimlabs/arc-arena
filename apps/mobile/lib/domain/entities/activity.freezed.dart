// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'activity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Activity {

 String get id; String get code; String get name; bool get usesControllers; bool get usesGames; DurationModel get durationModel; int get sortOrder; bool get active;
/// Create a copy of Activity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivityCopyWith<Activity> get copyWith => _$ActivityCopyWithImpl<Activity>(this as Activity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Activity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Activity&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.usesControllers, _this.usesControllers) || other.usesControllers == _this.usesControllers)&&(identical(other.usesGames, _this.usesGames) || other.usesGames == _this.usesGames)&&(identical(other.durationModel, _this.durationModel) || other.durationModel == _this.durationModel)&&(identical(other.sortOrder, _this.sortOrder) || other.sortOrder == _this.sortOrder)&&(identical(other.active, _this.active) || other.active == _this.active));
}


@override
int get hashCode {
  final _this = this as Activity;
  return Object.hash(runtimeType,_this.id,_this.code,_this.name,_this.usesControllers,_this.usesGames,_this.durationModel,_this.sortOrder,_this.active);
}

@override
String toString() {
  final _this = this as Activity;
  return 'Activity(id: ${_this.id}, code: ${_this.code}, name: ${_this.name}, usesControllers: ${_this.usesControllers}, usesGames: ${_this.usesGames}, durationModel: ${_this.durationModel}, sortOrder: ${_this.sortOrder}, active: ${_this.active})';
}


}

/// @nodoc
abstract mixin class $ActivityCopyWith<$Res>  {
  factory $ActivityCopyWith(Activity value, $Res Function(Activity) _then) = _$ActivityCopyWithImpl;
@useResult
$Res call({
 String id, String code, String name, bool usesControllers, bool usesGames, DurationModel durationModel, int sortOrder, bool active
});




}
/// @nodoc
class _$ActivityCopyWithImpl<$Res>
    implements $ActivityCopyWith<$Res> {
  _$ActivityCopyWithImpl(this._self, this._then);

  final Activity _self;
  final $Res Function(Activity) _then;

/// Create a copy of Activity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? code = null,Object? name = null,Object? usesControllers = null,Object? usesGames = null,Object? durationModel = null,Object? sortOrder = null,Object? active = null,}) {
  return _then(Activity(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,usesControllers: null == usesControllers ? _self.usesControllers : usesControllers // ignore: cast_nullable_to_non_nullable
as bool,usesGames: null == usesGames ? _self.usesGames : usesGames // ignore: cast_nullable_to_non_nullable
as bool,durationModel: null == durationModel ? _self.durationModel : durationModel // ignore: cast_nullable_to_non_nullable
as DurationModel,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [Activity].
extension ActivityPatterns on Activity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Activity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Activity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Activity value)  $default,){
final _that = this;
switch (_that) {
case _Activity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Activity value)?  $default,){
final _that = this;
switch (_that) {
case _Activity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String code,  String name,  bool usesControllers,  bool usesGames,  DurationModel durationModel,  int sortOrder,  bool active)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Activity() when $default != null:
return $default(_that.id,_that.code,_that.name,_that.usesControllers,_that.usesGames,_that.durationModel,_that.sortOrder,_that.active);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String code,  String name,  bool usesControllers,  bool usesGames,  DurationModel durationModel,  int sortOrder,  bool active)  $default,) {final _that = this;
switch (_that) {
case _Activity():
return $default(_that.id,_that.code,_that.name,_that.usesControllers,_that.usesGames,_that.durationModel,_that.sortOrder,_that.active);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String code,  String name,  bool usesControllers,  bool usesGames,  DurationModel durationModel,  int sortOrder,  bool active)?  $default,) {final _that = this;
switch (_that) {
case _Activity() when $default != null:
return $default(_that.id,_that.code,_that.name,_that.usesControllers,_that.usesGames,_that.durationModel,_that.sortOrder,_that.active);case _:
  return null;

}
}

}

/// @nodoc


class _Activity extends Activity {
  const _Activity({required this.id, required this.code, required this.name, required this.usesControllers, required this.usesGames, required this.durationModel, this.sortOrder = 0, this.active = true}): super._();
  

@override final  String id;
@override final  String code;
@override final  String name;
@override final  bool usesControllers;
@override final  bool usesGames;
@override final  DurationModel durationModel;
@override@JsonKey() final  int sortOrder;
@override@JsonKey() final  bool active;

/// Create a copy of Activity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivityCopyWith<_Activity> get copyWith => __$ActivityCopyWithImpl<_Activity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Activity&&(identical(other.id, id) || other.id == id)&&(identical(other.code, code) || other.code == code)&&(identical(other.name, name) || other.name == name)&&(identical(other.usesControllers, usesControllers) || other.usesControllers == usesControllers)&&(identical(other.usesGames, usesGames) || other.usesGames == usesGames)&&(identical(other.durationModel, durationModel) || other.durationModel == durationModel)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&(identical(other.active, active) || other.active == active));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,code,name,usesControllers,usesGames,durationModel,sortOrder,active);
}

@override
String toString() {
    return 'Activity(id: $id, code: $code, name: $name, usesControllers: $usesControllers, usesGames: $usesGames, durationModel: $durationModel, sortOrder: $sortOrder, active: $active)';
}


}

/// @nodoc
abstract mixin class _$ActivityCopyWith<$Res> implements $ActivityCopyWith<$Res> {
  factory _$ActivityCopyWith(_Activity value, $Res Function(_Activity) _then) = __$ActivityCopyWithImpl;
@override @useResult
$Res call({
 String id, String code, String name, bool usesControllers, bool usesGames, DurationModel durationModel, int sortOrder, bool active
});




}
/// @nodoc
class __$ActivityCopyWithImpl<$Res>
    implements _$ActivityCopyWith<$Res> {
  __$ActivityCopyWithImpl(this._self, this._then);

  final _Activity _self;
  final $Res Function(_Activity) _then;

/// Create a copy of Activity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? code = null,Object? name = null,Object? usesControllers = null,Object? usesGames = null,Object? durationModel = null,Object? sortOrder = null,Object? active = null,}) {
  return _then(_Activity(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,usesControllers: null == usesControllers ? _self.usesControllers : usesControllers // ignore: cast_nullable_to_non_nullable
as bool,usesGames: null == usesGames ? _self.usesGames : usesGames // ignore: cast_nullable_to_non_nullable
as bool,durationModel: null == durationModel ? _self.durationModel : durationModel // ignore: cast_nullable_to_non_nullable
as DurationModel,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,active: null == active ? _self.active : active // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
