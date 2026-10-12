// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Session {

 String get id; String? get bookingId; String get customerId; SessionStatus get status; PaymentStatus get paymentStatus; DateTime get startedAt; DateTime get scheduledEndAt; DateTime? get actualEndedAt; Map<String, dynamic> get pricingSnapshot; int? get billedAmountPaise; String? get voidReason; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of Session
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCopyWith<Session> get copyWith => _$SessionCopyWithImpl<Session>(this as Session, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Session;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Session&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.bookingId, _this.bookingId) || other.bookingId == _this.bookingId)&&(identical(other.customerId, _this.customerId) || other.customerId == _this.customerId)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.paymentStatus, _this.paymentStatus) || other.paymentStatus == _this.paymentStatus)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.scheduledEndAt, _this.scheduledEndAt) || other.scheduledEndAt == _this.scheduledEndAt)&&(identical(other.actualEndedAt, _this.actualEndedAt) || other.actualEndedAt == _this.actualEndedAt)&&const DeepCollectionEquality().equals(other.pricingSnapshot, _this.pricingSnapshot)&&(identical(other.billedAmountPaise, _this.billedAmountPaise) || other.billedAmountPaise == _this.billedAmountPaise)&&(identical(other.voidReason, _this.voidReason) || other.voidReason == _this.voidReason)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as Session;
  return Object.hash(runtimeType,_this.id,_this.bookingId,_this.customerId,_this.status,_this.paymentStatus,_this.startedAt,_this.scheduledEndAt,_this.actualEndedAt,const DeepCollectionEquality().hash(_this.pricingSnapshot),_this.billedAmountPaise,_this.voidReason,_this.createdAt,_this.updatedAt);
}

@override
String toString() {
  final _this = this as Session;
  return 'Session(id: ${_this.id}, bookingId: ${_this.bookingId}, customerId: ${_this.customerId}, status: ${_this.status}, paymentStatus: ${_this.paymentStatus}, startedAt: ${_this.startedAt}, scheduledEndAt: ${_this.scheduledEndAt}, actualEndedAt: ${_this.actualEndedAt}, pricingSnapshot: ${_this.pricingSnapshot}, billedAmountPaise: ${_this.billedAmountPaise}, voidReason: ${_this.voidReason}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $SessionCopyWith<$Res>  {
  factory $SessionCopyWith(Session value, $Res Function(Session) _then) = _$SessionCopyWithImpl;
@useResult
$Res call({
 String id, String? bookingId, String customerId, SessionStatus status, PaymentStatus paymentStatus, DateTime startedAt, DateTime scheduledEndAt, DateTime? actualEndedAt, Map<String, dynamic> pricingSnapshot, int? billedAmountPaise, String? voidReason, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$SessionCopyWithImpl<$Res>
    implements $SessionCopyWith<$Res> {
  _$SessionCopyWithImpl(this._self, this._then);

  final Session _self;
  final $Res Function(Session) _then;

/// Create a copy of Session
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? bookingId = freezed,Object? customerId = null,Object? status = null,Object? paymentStatus = null,Object? startedAt = null,Object? scheduledEndAt = null,Object? actualEndedAt = freezed,Object? pricingSnapshot = null,Object? billedAmountPaise = freezed,Object? voidReason = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(Session(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,bookingId: freezed == bookingId ? _self.bookingId : bookingId // ignore: cast_nullable_to_non_nullable
as String?,customerId: null == customerId ? _self.customerId : customerId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SessionStatus,paymentStatus: null == paymentStatus ? _self.paymentStatus : paymentStatus // ignore: cast_nullable_to_non_nullable
as PaymentStatus,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,scheduledEndAt: null == scheduledEndAt ? _self.scheduledEndAt : scheduledEndAt // ignore: cast_nullable_to_non_nullable
as DateTime,actualEndedAt: freezed == actualEndedAt ? _self.actualEndedAt : actualEndedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,pricingSnapshot: null == pricingSnapshot ? _self.pricingSnapshot : pricingSnapshot // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,billedAmountPaise: freezed == billedAmountPaise ? _self.billedAmountPaise : billedAmountPaise // ignore: cast_nullable_to_non_nullable
as int?,voidReason: freezed == voidReason ? _self.voidReason : voidReason // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Session].
extension SessionPatterns on Session {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Session value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Session() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Session value)  $default,){
final _that = this;
switch (_that) {
case _Session():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Session value)?  $default,){
final _that = this;
switch (_that) {
case _Session() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? bookingId,  String customerId,  SessionStatus status,  PaymentStatus paymentStatus,  DateTime startedAt,  DateTime scheduledEndAt,  DateTime? actualEndedAt,  Map<String, dynamic> pricingSnapshot,  int? billedAmountPaise,  String? voidReason,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Session() when $default != null:
return $default(_that.id,_that.bookingId,_that.customerId,_that.status,_that.paymentStatus,_that.startedAt,_that.scheduledEndAt,_that.actualEndedAt,_that.pricingSnapshot,_that.billedAmountPaise,_that.voidReason,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? bookingId,  String customerId,  SessionStatus status,  PaymentStatus paymentStatus,  DateTime startedAt,  DateTime scheduledEndAt,  DateTime? actualEndedAt,  Map<String, dynamic> pricingSnapshot,  int? billedAmountPaise,  String? voidReason,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Session():
return $default(_that.id,_that.bookingId,_that.customerId,_that.status,_that.paymentStatus,_that.startedAt,_that.scheduledEndAt,_that.actualEndedAt,_that.pricingSnapshot,_that.billedAmountPaise,_that.voidReason,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? bookingId,  String customerId,  SessionStatus status,  PaymentStatus paymentStatus,  DateTime startedAt,  DateTime scheduledEndAt,  DateTime? actualEndedAt,  Map<String, dynamic> pricingSnapshot,  int? billedAmountPaise,  String? voidReason,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Session() when $default != null:
return $default(_that.id,_that.bookingId,_that.customerId,_that.status,_that.paymentStatus,_that.startedAt,_that.scheduledEndAt,_that.actualEndedAt,_that.pricingSnapshot,_that.billedAmountPaise,_that.voidReason,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _Session extends Session {
  const _Session({required this.id, this.bookingId, required this.customerId, required this.status, required this.paymentStatus, required this.startedAt, required this.scheduledEndAt, this.actualEndedAt, required  Map<String, dynamic> pricingSnapshot, this.billedAmountPaise, this.voidReason, required this.createdAt, required this.updatedAt}): _pricingSnapshot = pricingSnapshot,super._();
  

@override final  String id;
@override final  String? bookingId;
@override final  String customerId;
@override final  SessionStatus status;
@override final  PaymentStatus paymentStatus;
@override final  DateTime startedAt;
@override final  DateTime scheduledEndAt;
@override final  DateTime? actualEndedAt;
 final  Map<String, dynamic> _pricingSnapshot;
@override Map<String, dynamic> get pricingSnapshot {
  if (_pricingSnapshot is EqualUnmodifiableMapView) return _pricingSnapshot;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_pricingSnapshot);
}

@override final  int? billedAmountPaise;
@override final  String? voidReason;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of Session
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionCopyWith<_Session> get copyWith => __$SessionCopyWithImpl<_Session>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Session&&(identical(other.id, id) || other.id == id)&&(identical(other.bookingId, bookingId) || other.bookingId == bookingId)&&(identical(other.customerId, customerId) || other.customerId == customerId)&&(identical(other.status, status) || other.status == status)&&(identical(other.paymentStatus, paymentStatus) || other.paymentStatus == paymentStatus)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.scheduledEndAt, scheduledEndAt) || other.scheduledEndAt == scheduledEndAt)&&(identical(other.actualEndedAt, actualEndedAt) || other.actualEndedAt == actualEndedAt)&&const DeepCollectionEquality().equals(other.pricingSnapshot, _pricingSnapshot)&&(identical(other.billedAmountPaise, billedAmountPaise) || other.billedAmountPaise == billedAmountPaise)&&(identical(other.voidReason, voidReason) || other.voidReason == voidReason)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,bookingId,customerId,status,paymentStatus,startedAt,scheduledEndAt,actualEndedAt,const DeepCollectionEquality().hash(_pricingSnapshot),billedAmountPaise,voidReason,createdAt,updatedAt);
}

@override
String toString() {
    return 'Session(id: $id, bookingId: $bookingId, customerId: $customerId, status: $status, paymentStatus: $paymentStatus, startedAt: $startedAt, scheduledEndAt: $scheduledEndAt, actualEndedAt: $actualEndedAt, pricingSnapshot: $pricingSnapshot, billedAmountPaise: $billedAmountPaise, voidReason: $voidReason, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$SessionCopyWith<$Res> implements $SessionCopyWith<$Res> {
  factory _$SessionCopyWith(_Session value, $Res Function(_Session) _then) = __$SessionCopyWithImpl;
@override @useResult
$Res call({
 String id, String? bookingId, String customerId, SessionStatus status, PaymentStatus paymentStatus, DateTime startedAt, DateTime scheduledEndAt, DateTime? actualEndedAt, Map<String, dynamic> pricingSnapshot, int? billedAmountPaise, String? voidReason, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$SessionCopyWithImpl<$Res>
    implements _$SessionCopyWith<$Res> {
  __$SessionCopyWithImpl(this._self, this._then);

  final _Session _self;
  final $Res Function(_Session) _then;

/// Create a copy of Session
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? bookingId = freezed,Object? customerId = null,Object? status = null,Object? paymentStatus = null,Object? startedAt = null,Object? scheduledEndAt = null,Object? actualEndedAt = freezed,Object? pricingSnapshot = null,Object? billedAmountPaise = freezed,Object? voidReason = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Session(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,bookingId: freezed == bookingId ? _self.bookingId : bookingId // ignore: cast_nullable_to_non_nullable
as String?,customerId: null == customerId ? _self.customerId : customerId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as SessionStatus,paymentStatus: null == paymentStatus ? _self.paymentStatus : paymentStatus // ignore: cast_nullable_to_non_nullable
as PaymentStatus,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,scheduledEndAt: null == scheduledEndAt ? _self.scheduledEndAt : scheduledEndAt // ignore: cast_nullable_to_non_nullable
as DateTime,actualEndedAt: freezed == actualEndedAt ? _self.actualEndedAt : actualEndedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,pricingSnapshot: null == pricingSnapshot ? _self._pricingSnapshot : pricingSnapshot // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,billedAmountPaise: freezed == billedAmountPaise ? _self.billedAmountPaise : billedAmountPaise // ignore: cast_nullable_to_non_nullable
as int?,voidReason: freezed == voidReason ? _self.voidReason : voidReason // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc
mixin _$SessionSegment {

 String get id; String get sessionId; int get index; String get resourceId; String get activityCode; String? get gameId; int? get controllerCount; DateTime get startedAt; DateTime? get endedAt; DateTime get createdAt;
/// Create a copy of SessionSegment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionSegmentCopyWith<SessionSegment> get copyWith => _$SessionSegmentCopyWithImpl<SessionSegment>(this as SessionSegment, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionSegment;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionSegment&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.resourceId, _this.resourceId) || other.resourceId == _this.resourceId)&&(identical(other.activityCode, _this.activityCode) || other.activityCode == _this.activityCode)&&(identical(other.gameId, _this.gameId) || other.gameId == _this.gameId)&&(identical(other.controllerCount, _this.controllerCount) || other.controllerCount == _this.controllerCount)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.endedAt, _this.endedAt) || other.endedAt == _this.endedAt)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}


@override
int get hashCode {
  final _this = this as SessionSegment;
  return Object.hash(runtimeType,_this.id,_this.sessionId,_this.index,_this.resourceId,_this.activityCode,_this.gameId,_this.controllerCount,_this.startedAt,_this.endedAt,_this.createdAt);
}

@override
String toString() {
  final _this = this as SessionSegment;
  return 'SessionSegment(id: ${_this.id}, sessionId: ${_this.sessionId}, index: ${_this.index}, resourceId: ${_this.resourceId}, activityCode: ${_this.activityCode}, gameId: ${_this.gameId}, controllerCount: ${_this.controllerCount}, startedAt: ${_this.startedAt}, endedAt: ${_this.endedAt}, createdAt: ${_this.createdAt})';
}


}

/// @nodoc
abstract mixin class $SessionSegmentCopyWith<$Res>  {
  factory $SessionSegmentCopyWith(SessionSegment value, $Res Function(SessionSegment) _then) = _$SessionSegmentCopyWithImpl;
@useResult
$Res call({
 String id, String sessionId, int index, String resourceId, String activityCode, String? gameId, int? controllerCount, DateTime startedAt, DateTime? endedAt, DateTime createdAt
});




}
/// @nodoc
class _$SessionSegmentCopyWithImpl<$Res>
    implements $SessionSegmentCopyWith<$Res> {
  _$SessionSegmentCopyWithImpl(this._self, this._then);

  final SessionSegment _self;
  final $Res Function(SessionSegment) _then;

/// Create a copy of SessionSegment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sessionId = null,Object? index = null,Object? resourceId = null,Object? activityCode = null,Object? gameId = freezed,Object? controllerCount = freezed,Object? startedAt = null,Object? endedAt = freezed,Object? createdAt = null,}) {
  return _then(SessionSegment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,resourceId: null == resourceId ? _self.resourceId : resourceId // ignore: cast_nullable_to_non_nullable
as String,activityCode: null == activityCode ? _self.activityCode : activityCode // ignore: cast_nullable_to_non_nullable
as String,gameId: freezed == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String?,controllerCount: freezed == controllerCount ? _self.controllerCount : controllerCount // ignore: cast_nullable_to_non_nullable
as int?,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,endedAt: freezed == endedAt ? _self.endedAt : endedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionSegment].
extension SessionSegmentPatterns on SessionSegment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionSegment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionSegment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionSegment value)  $default,){
final _that = this;
switch (_that) {
case _SessionSegment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionSegment value)?  $default,){
final _that = this;
switch (_that) {
case _SessionSegment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String sessionId,  int index,  String resourceId,  String activityCode,  String? gameId,  int? controllerCount,  DateTime startedAt,  DateTime? endedAt,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionSegment() when $default != null:
return $default(_that.id,_that.sessionId,_that.index,_that.resourceId,_that.activityCode,_that.gameId,_that.controllerCount,_that.startedAt,_that.endedAt,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String sessionId,  int index,  String resourceId,  String activityCode,  String? gameId,  int? controllerCount,  DateTime startedAt,  DateTime? endedAt,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _SessionSegment():
return $default(_that.id,_that.sessionId,_that.index,_that.resourceId,_that.activityCode,_that.gameId,_that.controllerCount,_that.startedAt,_that.endedAt,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String sessionId,  int index,  String resourceId,  String activityCode,  String? gameId,  int? controllerCount,  DateTime startedAt,  DateTime? endedAt,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _SessionSegment() when $default != null:
return $default(_that.id,_that.sessionId,_that.index,_that.resourceId,_that.activityCode,_that.gameId,_that.controllerCount,_that.startedAt,_that.endedAt,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _SessionSegment extends SessionSegment {
  const _SessionSegment({required this.id, required this.sessionId, required this.index, required this.resourceId, required this.activityCode, this.gameId, this.controllerCount, required this.startedAt, this.endedAt, required this.createdAt}): super._();
  

@override final  String id;
@override final  String sessionId;
@override final  int index;
@override final  String resourceId;
@override final  String activityCode;
@override final  String? gameId;
@override final  int? controllerCount;
@override final  DateTime startedAt;
@override final  DateTime? endedAt;
@override final  DateTime createdAt;

/// Create a copy of SessionSegment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionSegmentCopyWith<_SessionSegment> get copyWith => __$SessionSegmentCopyWithImpl<_SessionSegment>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionSegment&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.index, index) || other.index == index)&&(identical(other.resourceId, resourceId) || other.resourceId == resourceId)&&(identical(other.activityCode, activityCode) || other.activityCode == activityCode)&&(identical(other.gameId, gameId) || other.gameId == gameId)&&(identical(other.controllerCount, controllerCount) || other.controllerCount == controllerCount)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.endedAt, endedAt) || other.endedAt == endedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,sessionId,index,resourceId,activityCode,gameId,controllerCount,startedAt,endedAt,createdAt);
}

@override
String toString() {
    return 'SessionSegment(id: $id, sessionId: $sessionId, index: $index, resourceId: $resourceId, activityCode: $activityCode, gameId: $gameId, controllerCount: $controllerCount, startedAt: $startedAt, endedAt: $endedAt, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$SessionSegmentCopyWith<$Res> implements $SessionSegmentCopyWith<$Res> {
  factory _$SessionSegmentCopyWith(_SessionSegment value, $Res Function(_SessionSegment) _then) = __$SessionSegmentCopyWithImpl;
@override @useResult
$Res call({
 String id, String sessionId, int index, String resourceId, String activityCode, String? gameId, int? controllerCount, DateTime startedAt, DateTime? endedAt, DateTime createdAt
});




}
/// @nodoc
class __$SessionSegmentCopyWithImpl<$Res>
    implements _$SessionSegmentCopyWith<$Res> {
  __$SessionSegmentCopyWithImpl(this._self, this._then);

  final _SessionSegment _self;
  final $Res Function(_SessionSegment) _then;

/// Create a copy of SessionSegment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sessionId = null,Object? index = null,Object? resourceId = null,Object? activityCode = null,Object? gameId = freezed,Object? controllerCount = freezed,Object? startedAt = null,Object? endedAt = freezed,Object? createdAt = null,}) {
  return _then(_SessionSegment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,resourceId: null == resourceId ? _self.resourceId : resourceId // ignore: cast_nullable_to_non_nullable
as String,activityCode: null == activityCode ? _self.activityCode : activityCode // ignore: cast_nullable_to_non_nullable
as String,gameId: freezed == gameId ? _self.gameId : gameId // ignore: cast_nullable_to_non_nullable
as String?,controllerCount: freezed == controllerCount ? _self.controllerCount : controllerCount // ignore: cast_nullable_to_non_nullable
as int?,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,endedAt: freezed == endedAt ? _self.endedAt : endedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc
mixin _$ActiveSession {

 Session get session; List<SessionSegment> get segments;
/// Create a copy of ActiveSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActiveSessionCopyWith<ActiveSession> get copyWith => _$ActiveSessionCopyWithImpl<ActiveSession>(this as ActiveSession, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActiveSession;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActiveSession&&(identical(other.session, _this.session) || other.session == _this.session)&&const DeepCollectionEquality().equals(other.segments, _this.segments));
}


@override
int get hashCode {
  final _this = this as ActiveSession;
  return Object.hash(runtimeType,_this.session,const DeepCollectionEquality().hash(_this.segments));
}

@override
String toString() {
  final _this = this as ActiveSession;
  return 'ActiveSession(session: ${_this.session}, segments: ${_this.segments})';
}


}

/// @nodoc
abstract mixin class $ActiveSessionCopyWith<$Res>  {
  factory $ActiveSessionCopyWith(ActiveSession value, $Res Function(ActiveSession) _then) = _$ActiveSessionCopyWithImpl;
@useResult
$Res call({
 Session session, List<SessionSegment> segments
});


$SessionCopyWith<$Res> get session;

}
/// @nodoc
class _$ActiveSessionCopyWithImpl<$Res>
    implements $ActiveSessionCopyWith<$Res> {
  _$ActiveSessionCopyWithImpl(this._self, this._then);

  final ActiveSession _self;
  final $Res Function(ActiveSession) _then;

/// Create a copy of ActiveSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? session = null,Object? segments = null,}) {
  return _then(ActiveSession(
session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as Session,segments: null == segments ? _self.segments : segments // ignore: cast_nullable_to_non_nullable
as List<SessionSegment>,
  ));
}
/// Create a copy of ActiveSession
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCopyWith<$Res> get session {
  
  return $SessionCopyWith<$Res>(_self.session, (value) {
    return _then(_self.copyWith(session: value));
  });
}
}


/// Adds pattern-matching-related methods to [ActiveSession].
extension ActiveSessionPatterns on ActiveSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActiveSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActiveSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActiveSession value)  $default,){
final _that = this;
switch (_that) {
case _ActiveSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActiveSession value)?  $default,){
final _that = this;
switch (_that) {
case _ActiveSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Session session,  List<SessionSegment> segments)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActiveSession() when $default != null:
return $default(_that.session,_that.segments);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Session session,  List<SessionSegment> segments)  $default,) {final _that = this;
switch (_that) {
case _ActiveSession():
return $default(_that.session,_that.segments);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Session session,  List<SessionSegment> segments)?  $default,) {final _that = this;
switch (_that) {
case _ActiveSession() when $default != null:
return $default(_that.session,_that.segments);case _:
  return null;

}
}

}

/// @nodoc


class _ActiveSession extends ActiveSession {
  const _ActiveSession({required this.session, required  List<SessionSegment> segments}): _segments = segments,super._();
  

@override final  Session session;
 final  List<SessionSegment> _segments;
@override List<SessionSegment> get segments {
  if (_segments is EqualUnmodifiableListView) return _segments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_segments);
}


/// Create a copy of ActiveSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActiveSessionCopyWith<_ActiveSession> get copyWith => __$ActiveSessionCopyWithImpl<_ActiveSession>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActiveSession&&(identical(other.session, session) || other.session == session)&&const DeepCollectionEquality().equals(other.segments, _segments));
}


@override
int get hashCode {
    return Object.hash(runtimeType,session,const DeepCollectionEquality().hash(_segments));
}

@override
String toString() {
    return 'ActiveSession(session: $session, segments: $segments)';
}


}

/// @nodoc
abstract mixin class _$ActiveSessionCopyWith<$Res> implements $ActiveSessionCopyWith<$Res> {
  factory _$ActiveSessionCopyWith(_ActiveSession value, $Res Function(_ActiveSession) _then) = __$ActiveSessionCopyWithImpl;
@override @useResult
$Res call({
 Session session, List<SessionSegment> segments
});


@override $SessionCopyWith<$Res> get session;

}
/// @nodoc
class __$ActiveSessionCopyWithImpl<$Res>
    implements _$ActiveSessionCopyWith<$Res> {
  __$ActiveSessionCopyWithImpl(this._self, this._then);

  final _ActiveSession _self;
  final $Res Function(_ActiveSession) _then;

/// Create a copy of ActiveSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? session = null,Object? segments = null,}) {
  return _then(_ActiveSession(
session: null == session ? _self.session : session // ignore: cast_nullable_to_non_nullable
as Session,segments: null == segments ? _self._segments : segments // ignore: cast_nullable_to_non_nullable
as List<SessionSegment>,
  ));
}

/// Create a copy of ActiveSession
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCopyWith<$Res> get session {
  
  return $SessionCopyWith<$Res>(_self.session, (value) {
    return _then(_self.copyWith(session: value));
  });
}
}

/// @nodoc
mixin _$SessionExtension {

 String get id; String get sessionId; int get addedMinutes; DateTime get oldEndAt; DateTime get newEndAt; int get addedAmountPaise; String? get reason; DateTime get createdAt;
/// Create a copy of SessionExtension
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionExtensionCopyWith<SessionExtension> get copyWith => _$SessionExtensionCopyWithImpl<SessionExtension>(this as SessionExtension, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionExtension;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionExtension&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.addedMinutes, _this.addedMinutes) || other.addedMinutes == _this.addedMinutes)&&(identical(other.oldEndAt, _this.oldEndAt) || other.oldEndAt == _this.oldEndAt)&&(identical(other.newEndAt, _this.newEndAt) || other.newEndAt == _this.newEndAt)&&(identical(other.addedAmountPaise, _this.addedAmountPaise) || other.addedAmountPaise == _this.addedAmountPaise)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}


@override
int get hashCode {
  final _this = this as SessionExtension;
  return Object.hash(runtimeType,_this.id,_this.sessionId,_this.addedMinutes,_this.oldEndAt,_this.newEndAt,_this.addedAmountPaise,_this.reason,_this.createdAt);
}

@override
String toString() {
  final _this = this as SessionExtension;
  return 'SessionExtension(id: ${_this.id}, sessionId: ${_this.sessionId}, addedMinutes: ${_this.addedMinutes}, oldEndAt: ${_this.oldEndAt}, newEndAt: ${_this.newEndAt}, addedAmountPaise: ${_this.addedAmountPaise}, reason: ${_this.reason}, createdAt: ${_this.createdAt})';
}


}

/// @nodoc
abstract mixin class $SessionExtensionCopyWith<$Res>  {
  factory $SessionExtensionCopyWith(SessionExtension value, $Res Function(SessionExtension) _then) = _$SessionExtensionCopyWithImpl;
@useResult
$Res call({
 String id, String sessionId, int addedMinutes, DateTime oldEndAt, DateTime newEndAt, int addedAmountPaise, String? reason, DateTime createdAt
});




}
/// @nodoc
class _$SessionExtensionCopyWithImpl<$Res>
    implements $SessionExtensionCopyWith<$Res> {
  _$SessionExtensionCopyWithImpl(this._self, this._then);

  final SessionExtension _self;
  final $Res Function(SessionExtension) _then;

/// Create a copy of SessionExtension
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sessionId = null,Object? addedMinutes = null,Object? oldEndAt = null,Object? newEndAt = null,Object? addedAmountPaise = null,Object? reason = freezed,Object? createdAt = null,}) {
  return _then(SessionExtension(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,addedMinutes: null == addedMinutes ? _self.addedMinutes : addedMinutes // ignore: cast_nullable_to_non_nullable
as int,oldEndAt: null == oldEndAt ? _self.oldEndAt : oldEndAt // ignore: cast_nullable_to_non_nullable
as DateTime,newEndAt: null == newEndAt ? _self.newEndAt : newEndAt // ignore: cast_nullable_to_non_nullable
as DateTime,addedAmountPaise: null == addedAmountPaise ? _self.addedAmountPaise : addedAmountPaise // ignore: cast_nullable_to_non_nullable
as int,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionExtension].
extension SessionExtensionPatterns on SessionExtension {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionExtension value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionExtension() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionExtension value)  $default,){
final _that = this;
switch (_that) {
case _SessionExtension():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionExtension value)?  $default,){
final _that = this;
switch (_that) {
case _SessionExtension() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String sessionId,  int addedMinutes,  DateTime oldEndAt,  DateTime newEndAt,  int addedAmountPaise,  String? reason,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionExtension() when $default != null:
return $default(_that.id,_that.sessionId,_that.addedMinutes,_that.oldEndAt,_that.newEndAt,_that.addedAmountPaise,_that.reason,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String sessionId,  int addedMinutes,  DateTime oldEndAt,  DateTime newEndAt,  int addedAmountPaise,  String? reason,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _SessionExtension():
return $default(_that.id,_that.sessionId,_that.addedMinutes,_that.oldEndAt,_that.newEndAt,_that.addedAmountPaise,_that.reason,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String sessionId,  int addedMinutes,  DateTime oldEndAt,  DateTime newEndAt,  int addedAmountPaise,  String? reason,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _SessionExtension() when $default != null:
return $default(_that.id,_that.sessionId,_that.addedMinutes,_that.oldEndAt,_that.newEndAt,_that.addedAmountPaise,_that.reason,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _SessionExtension implements SessionExtension {
  const _SessionExtension({required this.id, required this.sessionId, required this.addedMinutes, required this.oldEndAt, required this.newEndAt, this.addedAmountPaise = 0, this.reason, required this.createdAt});
  

@override final  String id;
@override final  String sessionId;
@override final  int addedMinutes;
@override final  DateTime oldEndAt;
@override final  DateTime newEndAt;
@override@JsonKey() final  int addedAmountPaise;
@override final  String? reason;
@override final  DateTime createdAt;

/// Create a copy of SessionExtension
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionExtensionCopyWith<_SessionExtension> get copyWith => __$SessionExtensionCopyWithImpl<_SessionExtension>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionExtension&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.addedMinutes, addedMinutes) || other.addedMinutes == addedMinutes)&&(identical(other.oldEndAt, oldEndAt) || other.oldEndAt == oldEndAt)&&(identical(other.newEndAt, newEndAt) || other.newEndAt == newEndAt)&&(identical(other.addedAmountPaise, addedAmountPaise) || other.addedAmountPaise == addedAmountPaise)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,sessionId,addedMinutes,oldEndAt,newEndAt,addedAmountPaise,reason,createdAt);
}

@override
String toString() {
    return 'SessionExtension(id: $id, sessionId: $sessionId, addedMinutes: $addedMinutes, oldEndAt: $oldEndAt, newEndAt: $newEndAt, addedAmountPaise: $addedAmountPaise, reason: $reason, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$SessionExtensionCopyWith<$Res> implements $SessionExtensionCopyWith<$Res> {
  factory _$SessionExtensionCopyWith(_SessionExtension value, $Res Function(_SessionExtension) _then) = __$SessionExtensionCopyWithImpl;
@override @useResult
$Res call({
 String id, String sessionId, int addedMinutes, DateTime oldEndAt, DateTime newEndAt, int addedAmountPaise, String? reason, DateTime createdAt
});




}
/// @nodoc
class __$SessionExtensionCopyWithImpl<$Res>
    implements _$SessionExtensionCopyWith<$Res> {
  __$SessionExtensionCopyWithImpl(this._self, this._then);

  final _SessionExtension _self;
  final $Res Function(_SessionExtension) _then;

/// Create a copy of SessionExtension
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sessionId = null,Object? addedMinutes = null,Object? oldEndAt = null,Object? newEndAt = null,Object? addedAmountPaise = null,Object? reason = freezed,Object? createdAt = null,}) {
  return _then(_SessionExtension(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,addedMinutes: null == addedMinutes ? _self.addedMinutes : addedMinutes // ignore: cast_nullable_to_non_nullable
as int,oldEndAt: null == oldEndAt ? _self.oldEndAt : oldEndAt // ignore: cast_nullable_to_non_nullable
as DateTime,newEndAt: null == newEndAt ? _self.newEndAt : newEndAt // ignore: cast_nullable_to_non_nullable
as DateTime,addedAmountPaise: null == addedAmountPaise ? _self.addedAmountPaise : addedAmountPaise // ignore: cast_nullable_to_non_nullable
as int,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc
mixin _$SessionCharge {

 String get id; String get sessionId; String? get segmentId; int get segmentIndex; String get bandCode; String get activityCode; String? get resourceId; int? get controllerCount; DateTime get segmentStart; DateTime get segmentEnd; int get playedMinutes; int get billedMinutes; int get unitMinutes; int get unitPricePaise; int get amountPaise;
/// Create a copy of SessionCharge
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionChargeCopyWith<SessionCharge> get copyWith => _$SessionChargeCopyWithImpl<SessionCharge>(this as SessionCharge, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionCharge;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCharge&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.segmentId, _this.segmentId) || other.segmentId == _this.segmentId)&&(identical(other.segmentIndex, _this.segmentIndex) || other.segmentIndex == _this.segmentIndex)&&(identical(other.bandCode, _this.bandCode) || other.bandCode == _this.bandCode)&&(identical(other.activityCode, _this.activityCode) || other.activityCode == _this.activityCode)&&(identical(other.resourceId, _this.resourceId) || other.resourceId == _this.resourceId)&&(identical(other.controllerCount, _this.controllerCount) || other.controllerCount == _this.controllerCount)&&(identical(other.segmentStart, _this.segmentStart) || other.segmentStart == _this.segmentStart)&&(identical(other.segmentEnd, _this.segmentEnd) || other.segmentEnd == _this.segmentEnd)&&(identical(other.playedMinutes, _this.playedMinutes) || other.playedMinutes == _this.playedMinutes)&&(identical(other.billedMinutes, _this.billedMinutes) || other.billedMinutes == _this.billedMinutes)&&(identical(other.unitMinutes, _this.unitMinutes) || other.unitMinutes == _this.unitMinutes)&&(identical(other.unitPricePaise, _this.unitPricePaise) || other.unitPricePaise == _this.unitPricePaise)&&(identical(other.amountPaise, _this.amountPaise) || other.amountPaise == _this.amountPaise));
}


@override
int get hashCode {
  final _this = this as SessionCharge;
  return Object.hash(runtimeType,_this.id,_this.sessionId,_this.segmentId,_this.segmentIndex,_this.bandCode,_this.activityCode,_this.resourceId,_this.controllerCount,_this.segmentStart,_this.segmentEnd,_this.playedMinutes,_this.billedMinutes,_this.unitMinutes,_this.unitPricePaise,_this.amountPaise);
}

@override
String toString() {
  final _this = this as SessionCharge;
  return 'SessionCharge(id: ${_this.id}, sessionId: ${_this.sessionId}, segmentId: ${_this.segmentId}, segmentIndex: ${_this.segmentIndex}, bandCode: ${_this.bandCode}, activityCode: ${_this.activityCode}, resourceId: ${_this.resourceId}, controllerCount: ${_this.controllerCount}, segmentStart: ${_this.segmentStart}, segmentEnd: ${_this.segmentEnd}, playedMinutes: ${_this.playedMinutes}, billedMinutes: ${_this.billedMinutes}, unitMinutes: ${_this.unitMinutes}, unitPricePaise: ${_this.unitPricePaise}, amountPaise: ${_this.amountPaise})';
}


}

/// @nodoc
abstract mixin class $SessionChargeCopyWith<$Res>  {
  factory $SessionChargeCopyWith(SessionCharge value, $Res Function(SessionCharge) _then) = _$SessionChargeCopyWithImpl;
@useResult
$Res call({
 String id, String sessionId, String? segmentId, int segmentIndex, String bandCode, String activityCode, String? resourceId, int? controllerCount, DateTime segmentStart, DateTime segmentEnd, int playedMinutes, int billedMinutes, int unitMinutes, int unitPricePaise, int amountPaise
});




}
/// @nodoc
class _$SessionChargeCopyWithImpl<$Res>
    implements $SessionChargeCopyWith<$Res> {
  _$SessionChargeCopyWithImpl(this._self, this._then);

  final SessionCharge _self;
  final $Res Function(SessionCharge) _then;

/// Create a copy of SessionCharge
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sessionId = null,Object? segmentId = freezed,Object? segmentIndex = null,Object? bandCode = null,Object? activityCode = null,Object? resourceId = freezed,Object? controllerCount = freezed,Object? segmentStart = null,Object? segmentEnd = null,Object? playedMinutes = null,Object? billedMinutes = null,Object? unitMinutes = null,Object? unitPricePaise = null,Object? amountPaise = null,}) {
  return _then(SessionCharge(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,segmentId: freezed == segmentId ? _self.segmentId : segmentId // ignore: cast_nullable_to_non_nullable
as String?,segmentIndex: null == segmentIndex ? _self.segmentIndex : segmentIndex // ignore: cast_nullable_to_non_nullable
as int,bandCode: null == bandCode ? _self.bandCode : bandCode // ignore: cast_nullable_to_non_nullable
as String,activityCode: null == activityCode ? _self.activityCode : activityCode // ignore: cast_nullable_to_non_nullable
as String,resourceId: freezed == resourceId ? _self.resourceId : resourceId // ignore: cast_nullable_to_non_nullable
as String?,controllerCount: freezed == controllerCount ? _self.controllerCount : controllerCount // ignore: cast_nullable_to_non_nullable
as int?,segmentStart: null == segmentStart ? _self.segmentStart : segmentStart // ignore: cast_nullable_to_non_nullable
as DateTime,segmentEnd: null == segmentEnd ? _self.segmentEnd : segmentEnd // ignore: cast_nullable_to_non_nullable
as DateTime,playedMinutes: null == playedMinutes ? _self.playedMinutes : playedMinutes // ignore: cast_nullable_to_non_nullable
as int,billedMinutes: null == billedMinutes ? _self.billedMinutes : billedMinutes // ignore: cast_nullable_to_non_nullable
as int,unitMinutes: null == unitMinutes ? _self.unitMinutes : unitMinutes // ignore: cast_nullable_to_non_nullable
as int,unitPricePaise: null == unitPricePaise ? _self.unitPricePaise : unitPricePaise // ignore: cast_nullable_to_non_nullable
as int,amountPaise: null == amountPaise ? _self.amountPaise : amountPaise // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionCharge].
extension SessionChargePatterns on SessionCharge {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionCharge value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionCharge() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionCharge value)  $default,){
final _that = this;
switch (_that) {
case _SessionCharge():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionCharge value)?  $default,){
final _that = this;
switch (_that) {
case _SessionCharge() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String sessionId,  String? segmentId,  int segmentIndex,  String bandCode,  String activityCode,  String? resourceId,  int? controllerCount,  DateTime segmentStart,  DateTime segmentEnd,  int playedMinutes,  int billedMinutes,  int unitMinutes,  int unitPricePaise,  int amountPaise)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionCharge() when $default != null:
return $default(_that.id,_that.sessionId,_that.segmentId,_that.segmentIndex,_that.bandCode,_that.activityCode,_that.resourceId,_that.controllerCount,_that.segmentStart,_that.segmentEnd,_that.playedMinutes,_that.billedMinutes,_that.unitMinutes,_that.unitPricePaise,_that.amountPaise);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String sessionId,  String? segmentId,  int segmentIndex,  String bandCode,  String activityCode,  String? resourceId,  int? controllerCount,  DateTime segmentStart,  DateTime segmentEnd,  int playedMinutes,  int billedMinutes,  int unitMinutes,  int unitPricePaise,  int amountPaise)  $default,) {final _that = this;
switch (_that) {
case _SessionCharge():
return $default(_that.id,_that.sessionId,_that.segmentId,_that.segmentIndex,_that.bandCode,_that.activityCode,_that.resourceId,_that.controllerCount,_that.segmentStart,_that.segmentEnd,_that.playedMinutes,_that.billedMinutes,_that.unitMinutes,_that.unitPricePaise,_that.amountPaise);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String sessionId,  String? segmentId,  int segmentIndex,  String bandCode,  String activityCode,  String? resourceId,  int? controllerCount,  DateTime segmentStart,  DateTime segmentEnd,  int playedMinutes,  int billedMinutes,  int unitMinutes,  int unitPricePaise,  int amountPaise)?  $default,) {final _that = this;
switch (_that) {
case _SessionCharge() when $default != null:
return $default(_that.id,_that.sessionId,_that.segmentId,_that.segmentIndex,_that.bandCode,_that.activityCode,_that.resourceId,_that.controllerCount,_that.segmentStart,_that.segmentEnd,_that.playedMinutes,_that.billedMinutes,_that.unitMinutes,_that.unitPricePaise,_that.amountPaise);case _:
  return null;

}
}

}

/// @nodoc


class _SessionCharge implements SessionCharge {
  const _SessionCharge({required this.id, required this.sessionId, this.segmentId, required this.segmentIndex, required this.bandCode, required this.activityCode, this.resourceId, this.controllerCount, required this.segmentStart, required this.segmentEnd, required this.playedMinutes, required this.billedMinutes, required this.unitMinutes, required this.unitPricePaise, required this.amountPaise});
  

@override final  String id;
@override final  String sessionId;
@override final  String? segmentId;
@override final  int segmentIndex;
@override final  String bandCode;
@override final  String activityCode;
@override final  String? resourceId;
@override final  int? controllerCount;
@override final  DateTime segmentStart;
@override final  DateTime segmentEnd;
@override final  int playedMinutes;
@override final  int billedMinutes;
@override final  int unitMinutes;
@override final  int unitPricePaise;
@override final  int amountPaise;

/// Create a copy of SessionCharge
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionChargeCopyWith<_SessionCharge> get copyWith => __$SessionChargeCopyWithImpl<_SessionCharge>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionCharge&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.segmentId, segmentId) || other.segmentId == segmentId)&&(identical(other.segmentIndex, segmentIndex) || other.segmentIndex == segmentIndex)&&(identical(other.bandCode, bandCode) || other.bandCode == bandCode)&&(identical(other.activityCode, activityCode) || other.activityCode == activityCode)&&(identical(other.resourceId, resourceId) || other.resourceId == resourceId)&&(identical(other.controllerCount, controllerCount) || other.controllerCount == controllerCount)&&(identical(other.segmentStart, segmentStart) || other.segmentStart == segmentStart)&&(identical(other.segmentEnd, segmentEnd) || other.segmentEnd == segmentEnd)&&(identical(other.playedMinutes, playedMinutes) || other.playedMinutes == playedMinutes)&&(identical(other.billedMinutes, billedMinutes) || other.billedMinutes == billedMinutes)&&(identical(other.unitMinutes, unitMinutes) || other.unitMinutes == unitMinutes)&&(identical(other.unitPricePaise, unitPricePaise) || other.unitPricePaise == unitPricePaise)&&(identical(other.amountPaise, amountPaise) || other.amountPaise == amountPaise));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,sessionId,segmentId,segmentIndex,bandCode,activityCode,resourceId,controllerCount,segmentStart,segmentEnd,playedMinutes,billedMinutes,unitMinutes,unitPricePaise,amountPaise);
}

@override
String toString() {
    return 'SessionCharge(id: $id, sessionId: $sessionId, segmentId: $segmentId, segmentIndex: $segmentIndex, bandCode: $bandCode, activityCode: $activityCode, resourceId: $resourceId, controllerCount: $controllerCount, segmentStart: $segmentStart, segmentEnd: $segmentEnd, playedMinutes: $playedMinutes, billedMinutes: $billedMinutes, unitMinutes: $unitMinutes, unitPricePaise: $unitPricePaise, amountPaise: $amountPaise)';
}


}

/// @nodoc
abstract mixin class _$SessionChargeCopyWith<$Res> implements $SessionChargeCopyWith<$Res> {
  factory _$SessionChargeCopyWith(_SessionCharge value, $Res Function(_SessionCharge) _then) = __$SessionChargeCopyWithImpl;
@override @useResult
$Res call({
 String id, String sessionId, String? segmentId, int segmentIndex, String bandCode, String activityCode, String? resourceId, int? controllerCount, DateTime segmentStart, DateTime segmentEnd, int playedMinutes, int billedMinutes, int unitMinutes, int unitPricePaise, int amountPaise
});




}
/// @nodoc
class __$SessionChargeCopyWithImpl<$Res>
    implements _$SessionChargeCopyWith<$Res> {
  __$SessionChargeCopyWithImpl(this._self, this._then);

  final _SessionCharge _self;
  final $Res Function(_SessionCharge) _then;

/// Create a copy of SessionCharge
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sessionId = null,Object? segmentId = freezed,Object? segmentIndex = null,Object? bandCode = null,Object? activityCode = null,Object? resourceId = freezed,Object? controllerCount = freezed,Object? segmentStart = null,Object? segmentEnd = null,Object? playedMinutes = null,Object? billedMinutes = null,Object? unitMinutes = null,Object? unitPricePaise = null,Object? amountPaise = null,}) {
  return _then(_SessionCharge(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,segmentId: freezed == segmentId ? _self.segmentId : segmentId // ignore: cast_nullable_to_non_nullable
as String?,segmentIndex: null == segmentIndex ? _self.segmentIndex : segmentIndex // ignore: cast_nullable_to_non_nullable
as int,bandCode: null == bandCode ? _self.bandCode : bandCode // ignore: cast_nullable_to_non_nullable
as String,activityCode: null == activityCode ? _self.activityCode : activityCode // ignore: cast_nullable_to_non_nullable
as String,resourceId: freezed == resourceId ? _self.resourceId : resourceId // ignore: cast_nullable_to_non_nullable
as String?,controllerCount: freezed == controllerCount ? _self.controllerCount : controllerCount // ignore: cast_nullable_to_non_nullable
as int?,segmentStart: null == segmentStart ? _self.segmentStart : segmentStart // ignore: cast_nullable_to_non_nullable
as DateTime,segmentEnd: null == segmentEnd ? _self.segmentEnd : segmentEnd // ignore: cast_nullable_to_non_nullable
as DateTime,playedMinutes: null == playedMinutes ? _self.playedMinutes : playedMinutes // ignore: cast_nullable_to_non_nullable
as int,billedMinutes: null == billedMinutes ? _self.billedMinutes : billedMinutes // ignore: cast_nullable_to_non_nullable
as int,unitMinutes: null == unitMinutes ? _self.unitMinutes : unitMinutes // ignore: cast_nullable_to_non_nullable
as int,unitPricePaise: null == unitPricePaise ? _self.unitPricePaise : unitPricePaise // ignore: cast_nullable_to_non_nullable
as int,amountPaise: null == amountPaise ? _self.amountPaise : amountPaise // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
