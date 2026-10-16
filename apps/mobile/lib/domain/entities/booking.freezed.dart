// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'booking.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Booking {

 String get id; String? get customerId; String get activityCode; String? get gameId; String? get resourceId; DateTime get scheduledStart; DateTime get scheduledEnd; int? get playersRequired; int? get controllerRequirement; BookingStatus get status;/// Party name for a walk-in reservation with no customer record yet.
 String? get partyName; String? get phone; String? get notes; ReminderStatus get reminderStatus; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of Booking
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BookingCopyWith<Booking> get copyWith => _$BookingCopyWithImpl<Booking>(this as Booking, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Booking;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Booking&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.customerId, _this.customerId) || other.customerId == _this.customerId)&&(identical(other.activityCode, _this.activityCode) || other.activityCode == _this.activityCode)&&(identical(other.gameId, _this.gameId) || other.gameId == _this.gameId)&&(identical(other.resourceId, _this.resourceId) || other.resourceId == _this.resourceId)&&(identical(other.scheduledStart, _this.scheduledStart) || other.scheduledStart == _this.scheduledStart)&&(identical(other.scheduledEnd, _this.scheduledEnd) || other.scheduledEnd == _this.scheduledEnd)&&(identical(other.playersRequired, _this.playersRequired) || other.playersRequired == _this.playersRequired)&&(identical(other.controllerRequirement, _this.controllerRequirement) || other.controllerRequirement == _this.controllerRequirement)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.partyName, _this.partyName) || other.partyName == _this.partyName)&&(identical(other.phone, _this.phone) || other.phone == _this.phone)&&(identical(other.notes, _this.notes) || other.notes == _this.notes)&&(identical(other.reminderStatus, _this.reminderStatus) || other.reminderStatus == _this.reminderStatus)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as Booking;
  return Object.hash(runtimeType,_this.id,_this.customerId,_this.activityCode,_this.gameId,_this.resourceId,_this.scheduledStart,_this.scheduledEnd,_this.playersRequired,_this.controllerRequirement,_this.status,_this.partyName,_this.phone,_this.notes,_this.reminderStatus,_this.createdAt,_this.updatedAt);
}

@override
String toString() {
  final _this = this as Booking;
  return 'Booking(id: ${_this.id}, customerId: ${_this.customerId}, activityCode: ${_this.activityCode}, gameId: ${_this.gameId}, resourceId: ${_this.resourceId}, scheduledStart: ${_this.scheduledStart}, scheduledEnd: ${_this.scheduledEnd}, playersRequired: ${_this.playersRequired}, controllerRequirement: ${_this.controllerRequirement}, status: ${_this.status}, partyName: ${_this.partyName}, phone: ${_this.phone}, notes: ${_this.notes}, reminderStatus: ${_this.reminderStatus}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $BookingCopyWith<$Res>  {
  factory $BookingCopyWith(Booking value, $Res Function(Booking) _then) = _$BookingCopyWithImpl;
@useResult
$Res call({
 String id, String? customerId, String activityCode, String? gameId, String? resourceId, DateTime scheduledStart, DateTime scheduledEnd, int? playersRequired, int? controllerRequirement, BookingStatus status, String? partyName, String? phone, String? notes, ReminderStatus reminderStatus, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$BookingCopyWithImpl<$Res>
    implements $BookingCopyWith<$Res> {
  _$BookingCopyWithImpl(this._self, this._then);

  final Booking _self;
  final $Res Function(Booking) _then;

/// Create a copy of Booking
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? customerId = freezed,Object? activityCode = null,Object? gameId = freezed,Object? resourceId = freezed,Object? scheduledStart = null,Object? scheduledEnd = null,Object? playersRequired = freezed,Object? controllerRequirement = freezed,Object? status = null,Object? partyName = freezed,Object? phone = freezed,Object? notes = freezed,Object? reminderStatus = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(Booking(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,customerId: freezed == customerId ? _self.customerId : customerId // ignore: cast_nullable_to_non_nullable
as String?,activityCode: null == activityCode ? _self.activityCode : activityCode // ignore: cast_nullable_to_non_nullable
as String,gameId: freezed == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String?,resourceId: freezed == resourceId ? _self.resourceId : resourceId // ignore: cast_nullable_to_non_nullable
as String?,scheduledStart: null == scheduledStart ? _self.scheduledStart : scheduledStart // ignore: cast_nullable_to_non_nullable
as DateTime,scheduledEnd: null == scheduledEnd ? _self.scheduledEnd : scheduledEnd // ignore: cast_nullable_to_non_nullable
as DateTime,playersRequired: freezed == playersRequired ? _self.playersRequired : playersRequired // ignore: cast_nullable_to_non_nullable
as int?,controllerRequirement: freezed == controllerRequirement ? _self.controllerRequirement : controllerRequirement // ignore: cast_nullable_to_non_nullable
as int?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BookingStatus,partyName: freezed == partyName ? _self.partyName : partyName // ignore: cast_nullable_to_non_nullable
as String?,phone: freezed == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,reminderStatus: null == reminderStatus ? _self.reminderStatus : reminderStatus // ignore: cast_nullable_to_non_nullable
as ReminderStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Booking].
extension BookingPatterns on Booking {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Booking value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Booking() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Booking value)  $default,){
final _that = this;
switch (_that) {
case _Booking():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Booking value)?  $default,){
final _that = this;
switch (_that) {
case _Booking() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? customerId,  String activityCode,  String? gameId,  String? resourceId,  DateTime scheduledStart,  DateTime scheduledEnd,  int? playersRequired,  int? controllerRequirement,  BookingStatus status,  String? partyName,  String? phone,  String? notes,  ReminderStatus reminderStatus,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Booking() when $default != null:
return $default(_that.id,_that.customerId,_that.activityCode,_that.gameId,_that.resourceId,_that.scheduledStart,_that.scheduledEnd,_that.playersRequired,_that.controllerRequirement,_that.status,_that.partyName,_that.phone,_that.notes,_that.reminderStatus,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? customerId,  String activityCode,  String? gameId,  String? resourceId,  DateTime scheduledStart,  DateTime scheduledEnd,  int? playersRequired,  int? controllerRequirement,  BookingStatus status,  String? partyName,  String? phone,  String? notes,  ReminderStatus reminderStatus,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Booking():
return $default(_that.id,_that.customerId,_that.activityCode,_that.gameId,_that.resourceId,_that.scheduledStart,_that.scheduledEnd,_that.playersRequired,_that.controllerRequirement,_that.status,_that.partyName,_that.phone,_that.notes,_that.reminderStatus,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? customerId,  String activityCode,  String? gameId,  String? resourceId,  DateTime scheduledStart,  DateTime scheduledEnd,  int? playersRequired,  int? controllerRequirement,  BookingStatus status,  String? partyName,  String? phone,  String? notes,  ReminderStatus reminderStatus,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Booking() when $default != null:
return $default(_that.id,_that.customerId,_that.activityCode,_that.gameId,_that.resourceId,_that.scheduledStart,_that.scheduledEnd,_that.playersRequired,_that.controllerRequirement,_that.status,_that.partyName,_that.phone,_that.notes,_that.reminderStatus,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Booking extends Booking {
  const _Booking({required this.id, this.customerId, required this.activityCode, this.gameId, this.resourceId, required this.scheduledStart, required this.scheduledEnd, this.playersRequired, this.controllerRequirement, required this.status, this.partyName, this.phone, this.notes, this.reminderStatus = ReminderStatus.scheduled, required this.createdAt, required this.updatedAt}): super._();
  

@override final  String id;
@override final  String? customerId;
@override final  String activityCode;
@override final  String? gameId;
@override final  String? resourceId;
@override final  DateTime scheduledStart;
@override final  DateTime scheduledEnd;
@override final  int? playersRequired;
@override final  int? controllerRequirement;
@override final  BookingStatus status;
/// Party name for a walk-in reservation with no customer record yet.
@override final  String? partyName;
@override final  String? phone;
@override final  String? notes;
@override@JsonKey() final  ReminderStatus reminderStatus;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of Booking
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BookingCopyWith<_Booking> get copyWith => __$BookingCopyWithImpl<_Booking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Booking&&(identical(other.id, id) || other.id == id)&&(identical(other.customerId, customerId) || other.customerId == customerId)&&(identical(other.activityCode, activityCode) || other.activityCode == activityCode)&&(identical(other.gameId, gameId) || other.gameId == gameId)&&(identical(other.resourceId, resourceId) || other.resourceId == resourceId)&&(identical(other.scheduledStart, scheduledStart) || other.scheduledStart == scheduledStart)&&(identical(other.scheduledEnd, scheduledEnd) || other.scheduledEnd == scheduledEnd)&&(identical(other.playersRequired, playersRequired) || other.playersRequired == playersRequired)&&(identical(other.controllerRequirement, controllerRequirement) || other.controllerRequirement == controllerRequirement)&&(identical(other.status, status) || other.status == status)&&(identical(other.partyName, partyName) || other.partyName == partyName)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.reminderStatus, reminderStatus) || other.reminderStatus == reminderStatus)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,customerId,activityCode,gameId,resourceId,scheduledStart,scheduledEnd,playersRequired,controllerRequirement,status,partyName,phone,notes,reminderStatus,createdAt,updatedAt);
}

@override
String toString() {
    return 'Booking(id: $id, customerId: $customerId, activityCode: $activityCode, gameId: $gameId, resourceId: $resourceId, scheduledStart: $scheduledStart, scheduledEnd: $scheduledEnd, playersRequired: $playersRequired, controllerRequirement: $controllerRequirement, status: $status, partyName: $partyName, phone: $phone, notes: $notes, reminderStatus: $reminderStatus, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$BookingCopyWith<$Res> implements $BookingCopyWith<$Res> {
  factory _$BookingCopyWith(_Booking value, $Res Function(_Booking) _then) = __$BookingCopyWithImpl;
@override @useResult
$Res call({
 String id, String? customerId, String activityCode, String? gameId, String? resourceId, DateTime scheduledStart, DateTime scheduledEnd, int? playersRequired, int? controllerRequirement, BookingStatus status, String? partyName, String? phone, String? notes, ReminderStatus reminderStatus, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$BookingCopyWithImpl<$Res>
    implements _$BookingCopyWith<$Res> {
  __$BookingCopyWithImpl(this._self, this._then);

  final _Booking _self;
  final $Res Function(_Booking) _then;

/// Create a copy of Booking
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? customerId = freezed,Object? activityCode = null,Object? gameId = freezed,Object? resourceId = freezed,Object? scheduledStart = null,Object? scheduledEnd = null,Object? playersRequired = freezed,Object? controllerRequirement = freezed,Object? status = null,Object? partyName = freezed,Object? phone = freezed,Object? notes = freezed,Object? reminderStatus = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Booking(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,customerId: freezed == customerId ? _self.customerId : customerId // ignore: cast_nullable_to_non_nullable
as String?,activityCode: null == activityCode ? _self.activityCode : activityCode // ignore: cast_nullable_to_non_nullable
as String,gameId: freezed == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String?,resourceId: freezed == resourceId ? _self.resourceId : resourceId // ignore: cast_nullable_to_non_nullable
as String?,scheduledStart: null == scheduledStart ? _self.scheduledStart : scheduledStart // ignore: cast_nullable_to_non_nullable
as DateTime,scheduledEnd: null == scheduledEnd ? _self.scheduledEnd : scheduledEnd // ignore: cast_nullable_to_non_nullable
as DateTime,playersRequired: freezed == playersRequired ? _self.playersRequired : playersRequired // ignore: cast_nullable_to_non_nullable
as int?,controllerRequirement: freezed == controllerRequirement ? _self.controllerRequirement : controllerRequirement // ignore: cast_nullable_to_non_nullable
as int?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BookingStatus,partyName: freezed == partyName ? _self.partyName : partyName // ignore: cast_nullable_to_non_nullable
as String?,phone: freezed == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,reminderStatus: null == reminderStatus ? _self.reminderStatus : reminderStatus // ignore: cast_nullable_to_non_nullable
as ReminderStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
