// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'resource.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Resource {

 String get id; String get name; ResourceKind get kind; ResourceStatus get status; int get sortOrder; List<String> get activityCodes; String? get currentMode;
/// Create a copy of Resource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResourceCopyWith<Resource> get copyWith => _$ResourceCopyWithImpl<Resource>(this as Resource, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Resource;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Resource&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.sortOrder, _this.sortOrder) || other.sortOrder == _this.sortOrder)&&const DeepCollectionEquality().equals(other.activityCodes, _this.activityCodes)&&(identical(other.currentMode, _this.currentMode) || other.currentMode == _this.currentMode));
}


@override
int get hashCode {
  final _this = this as Resource;
  return Object.hash(runtimeType,_this.id,_this.name,_this.kind,_this.status,_this.sortOrder,const DeepCollectionEquality().hash(_this.activityCodes),_this.currentMode);
}

@override
String toString() {
  final _this = this as Resource;
  return 'Resource(id: ${_this.id}, name: ${_this.name}, kind: ${_this.kind}, status: ${_this.status}, sortOrder: ${_this.sortOrder}, activityCodes: ${_this.activityCodes}, currentMode: ${_this.currentMode})';
}


}

/// @nodoc
abstract mixin class $ResourceCopyWith<$Res>  {
  factory $ResourceCopyWith(Resource value, $Res Function(Resource) _then) = _$ResourceCopyWithImpl;
@useResult
$Res call({
 String id, String name, ResourceKind kind, ResourceStatus status, int sortOrder, List<String> activityCodes, String? currentMode
});




}
/// @nodoc
class _$ResourceCopyWithImpl<$Res>
    implements $ResourceCopyWith<$Res> {
  _$ResourceCopyWithImpl(this._self, this._then);

  final Resource _self;
  final $Res Function(Resource) _then;

/// Create a copy of Resource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? kind = null,Object? status = null,Object? sortOrder = null,Object? activityCodes = null,Object? currentMode = freezed,}) {
  return _then(Resource(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ResourceKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ResourceStatus,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,activityCodes: null == activityCodes ? _self.activityCodes : activityCodes // ignore: cast_nullable_to_non_nullable
as List<String>,currentMode: freezed == currentMode ? _self.currentMode : currentMode // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [Resource].
extension ResourcePatterns on Resource {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Resource value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Resource() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Resource value)  $default,){
final _that = this;
switch (_that) {
case _Resource():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Resource value)?  $default,){
final _that = this;
switch (_that) {
case _Resource() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  ResourceKind kind,  ResourceStatus status,  int sortOrder,  List<String> activityCodes,  String? currentMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Resource() when $default != null:
return $default(_that.id,_that.name,_that.kind,_that.status,_that.sortOrder,_that.activityCodes,_that.currentMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  ResourceKind kind,  ResourceStatus status,  int sortOrder,  List<String> activityCodes,  String? currentMode)  $default,) {final _that = this;
switch (_that) {
case _Resource():
return $default(_that.id,_that.name,_that.kind,_that.status,_that.sortOrder,_that.activityCodes,_that.currentMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  ResourceKind kind,  ResourceStatus status,  int sortOrder,  List<String> activityCodes,  String? currentMode)?  $default,) {final _that = this;
switch (_that) {
case _Resource() when $default != null:
return $default(_that.id,_that.name,_that.kind,_that.status,_that.sortOrder,_that.activityCodes,_that.currentMode);case _:
  return null;

}
}

}

/// @nodoc


class _Resource implements Resource {
  const _Resource({required this.id, required this.name, required this.kind, this.status = ResourceStatus.available, this.sortOrder = 0,  List<String> activityCodes = const <String>[], this.currentMode}): _activityCodes = activityCodes;
  

@override final  String id;
@override final  String name;
@override final  ResourceKind kind;
@override@JsonKey() final  ResourceStatus status;
@override@JsonKey() final  int sortOrder;
 final  List<String> _activityCodes;
@override@JsonKey() List<String> get activityCodes {
  if (_activityCodes is EqualUnmodifiableListView) return _activityCodes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activityCodes);
}

@override final  String? currentMode;

/// Create a copy of Resource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ResourceCopyWith<_Resource> get copyWith => __$ResourceCopyWithImpl<_Resource>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Resource&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.status, status) || other.status == status)&&(identical(other.sortOrder, sortOrder) || other.sortOrder == sortOrder)&&const DeepCollectionEquality().equals(other.activityCodes, _activityCodes)&&(identical(other.currentMode, currentMode) || other.currentMode == currentMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,kind,status,sortOrder,const DeepCollectionEquality().hash(_activityCodes),currentMode);
}

@override
String toString() {
    return 'Resource(id: $id, name: $name, kind: $kind, status: $status, sortOrder: $sortOrder, activityCodes: $activityCodes, currentMode: $currentMode)';
}


}

/// @nodoc
abstract mixin class _$ResourceCopyWith<$Res> implements $ResourceCopyWith<$Res> {
  factory _$ResourceCopyWith(_Resource value, $Res Function(_Resource) _then) = __$ResourceCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, ResourceKind kind, ResourceStatus status, int sortOrder, List<String> activityCodes, String? currentMode
});




}
/// @nodoc
class __$ResourceCopyWithImpl<$Res>
    implements _$ResourceCopyWith<$Res> {
  __$ResourceCopyWithImpl(this._self, this._then);

  final _Resource _self;
  final $Res Function(_Resource) _then;

/// Create a copy of Resource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? kind = null,Object? status = null,Object? sortOrder = null,Object? activityCodes = null,Object? currentMode = freezed,}) {
  return _then(_Resource(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ResourceKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ResourceStatus,sortOrder: null == sortOrder ? _self.sortOrder : sortOrder // ignore: cast_nullable_to_non_nullable
as int,activityCodes: null == activityCodes ? _self._activityCodes : activityCodes // ignore: cast_nullable_to_non_nullable
as List<String>,currentMode: freezed == currentMode ? _self.currentMode : currentMode // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
