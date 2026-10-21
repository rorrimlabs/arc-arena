// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'group_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$GroupSession {

 String get id; String get primaryCustomerId; int get playerCount; int get purchasedControllerCount; GroupSessionStatus get status; PaymentStatus get paymentStatus; DateTime get startedAt; DateTime get scheduledEndAt; DateTime? get actualEndedAt; Map<String, dynamic> get pricingSnapshot; GroupBillingMode get billingMode; int? get billedAmountPaise; String? get voidReason; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of GroupSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GroupSessionCopyWith<GroupSession> get copyWith => _$GroupSessionCopyWithImpl<GroupSession>(this as GroupSession, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GroupSession;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GroupSession&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.primaryCustomerId, _this.primaryCustomerId) || other.primaryCustomerId == _this.primaryCustomerId)&&(identical(other.playerCount, _this.playerCount) || other.playerCount == _this.playerCount)&&(identical(other.purchasedControllerCount, _this.purchasedControllerCount) || other.purchasedControllerCount == _this.purchasedControllerCount)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.paymentStatus, _this.paymentStatus) || other.paymentStatus == _this.paymentStatus)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.scheduledEndAt, _this.scheduledEndAt) || other.scheduledEndAt == _this.scheduledEndAt)&&(identical(other.actualEndedAt, _this.actualEndedAt) || other.actualEndedAt == _this.actualEndedAt)&&const DeepCollectionEquality().equals(other.pricingSnapshot, _this.pricingSnapshot)&&(identical(other.billingMode, _this.billingMode) || other.billingMode == _this.billingMode)&&(identical(other.billedAmountPaise, _this.billedAmountPaise) || other.billedAmountPaise == _this.billedAmountPaise)&&(identical(other.voidReason, _this.voidReason) || other.voidReason == _this.voidReason)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as GroupSession;
  return Object.hash(runtimeType,_this.id,_this.primaryCustomerId,_this.playerCount,_this.purchasedControllerCount,_this.status,_this.paymentStatus,_this.startedAt,_this.scheduledEndAt,_this.actualEndedAt,const DeepCollectionEquality().hash(_this.pricingSnapshot),_this.billingMode,_this.billedAmountPaise,_this.voidReason,_this.createdAt,_this.updatedAt);
}

@override
String toString() {
  final _this = this as GroupSession;
  return 'GroupSession(id: ${_this.id}, primaryCustomerId: ${_this.primaryCustomerId}, playerCount: ${_this.playerCount}, purchasedControllerCount: ${_this.purchasedControllerCount}, status: ${_this.status}, paymentStatus: ${_this.paymentStatus}, startedAt: ${_this.startedAt}, scheduledEndAt: ${_this.scheduledEndAt}, actualEndedAt: ${_this.actualEndedAt}, pricingSnapshot: ${_this.pricingSnapshot}, billingMode: ${_this.billingMode}, billedAmountPaise: ${_this.billedAmountPaise}, voidReason: ${_this.voidReason}, createdAt: ${_this.createdAt}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $GroupSessionCopyWith<$Res>  {
  factory $GroupSessionCopyWith(GroupSession value, $Res Function(GroupSession) _then) = _$GroupSessionCopyWithImpl;
@useResult
$Res call({
 String id, String primaryCustomerId, int playerCount, int purchasedControllerCount, GroupSessionStatus status, PaymentStatus paymentStatus, DateTime startedAt, DateTime scheduledEndAt, DateTime? actualEndedAt, Map<String, dynamic> pricingSnapshot, GroupBillingMode billingMode, int? billedAmountPaise, String? voidReason, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$GroupSessionCopyWithImpl<$Res>
    implements $GroupSessionCopyWith<$Res> {
  _$GroupSessionCopyWithImpl(this._self, this._then);

  final GroupSession _self;
  final $Res Function(GroupSession) _then;

/// Create a copy of GroupSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? primaryCustomerId = null,Object? playerCount = null,Object? purchasedControllerCount = null,Object? status = null,Object? paymentStatus = null,Object? startedAt = null,Object? scheduledEndAt = null,Object? actualEndedAt = freezed,Object? pricingSnapshot = null,Object? billingMode = null,Object? billedAmountPaise = freezed,Object? voidReason = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(GroupSession(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,primaryCustomerId: null == primaryCustomerId ? _self.primaryCustomerId : primaryCustomerId // ignore: cast_nullable_to_non_nullable
as String,playerCount: null == playerCount ? _self.playerCount : playerCount // ignore: cast_nullable_to_non_nullable
as int,purchasedControllerCount: null == purchasedControllerCount ? _self.purchasedControllerCount : purchasedControllerCount // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as GroupSessionStatus,paymentStatus: null == paymentStatus ? _self.paymentStatus : paymentStatus // ignore: cast_nullable_to_non_nullable
as PaymentStatus,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,scheduledEndAt: null == scheduledEndAt ? _self.scheduledEndAt : scheduledEndAt // ignore: cast_nullable_to_non_nullable
as DateTime,actualEndedAt: freezed == actualEndedAt ? _self.actualEndedAt : actualEndedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,pricingSnapshot: null == pricingSnapshot ? _self.pricingSnapshot : pricingSnapshot // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,billingMode: null == billingMode ? _self.billingMode : billingMode // ignore: cast_nullable_to_non_nullable
as GroupBillingMode,billedAmountPaise: freezed == billedAmountPaise ? _self.billedAmountPaise : billedAmountPaise // ignore: cast_nullable_to_non_nullable
as int?,voidReason: freezed == voidReason ? _self.voidReason : voidReason // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [GroupSession].
extension GroupSessionPatterns on GroupSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GroupSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GroupSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GroupSession value)  $default,){
final _that = this;
switch (_that) {
case _GroupSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GroupSession value)?  $default,){
final _that = this;
switch (_that) {
case _GroupSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String primaryCustomerId,  int playerCount,  int purchasedControllerCount,  GroupSessionStatus status,  PaymentStatus paymentStatus,  DateTime startedAt,  DateTime scheduledEndAt,  DateTime? actualEndedAt,  Map<String, dynamic> pricingSnapshot,  GroupBillingMode billingMode,  int? billedAmountPaise,  String? voidReason,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GroupSession() when $default != null:
return $default(_that.id,_that.primaryCustomerId,_that.playerCount,_that.purchasedControllerCount,_that.status,_that.paymentStatus,_that.startedAt,_that.scheduledEndAt,_that.actualEndedAt,_that.pricingSnapshot,_that.billingMode,_that.billedAmountPaise,_that.voidReason,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String primaryCustomerId,  int playerCount,  int purchasedControllerCount,  GroupSessionStatus status,  PaymentStatus paymentStatus,  DateTime startedAt,  DateTime scheduledEndAt,  DateTime? actualEndedAt,  Map<String, dynamic> pricingSnapshot,  GroupBillingMode billingMode,  int? billedAmountPaise,  String? voidReason,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _GroupSession():
return $default(_that.id,_that.primaryCustomerId,_that.playerCount,_that.purchasedControllerCount,_that.status,_that.paymentStatus,_that.startedAt,_that.scheduledEndAt,_that.actualEndedAt,_that.pricingSnapshot,_that.billingMode,_that.billedAmountPaise,_that.voidReason,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String primaryCustomerId,  int playerCount,  int purchasedControllerCount,  GroupSessionStatus status,  PaymentStatus paymentStatus,  DateTime startedAt,  DateTime scheduledEndAt,  DateTime? actualEndedAt,  Map<String, dynamic> pricingSnapshot,  GroupBillingMode billingMode,  int? billedAmountPaise,  String? voidReason,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _GroupSession() when $default != null:
return $default(_that.id,_that.primaryCustomerId,_that.playerCount,_that.purchasedControllerCount,_that.status,_that.paymentStatus,_that.startedAt,_that.scheduledEndAt,_that.actualEndedAt,_that.pricingSnapshot,_that.billingMode,_that.billedAmountPaise,_that.voidReason,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _GroupSession extends GroupSession {
  const _GroupSession({required this.id, required this.primaryCustomerId, required this.playerCount, required this.purchasedControllerCount, required this.status, required this.paymentStatus, required this.startedAt, required this.scheduledEndAt, this.actualEndedAt, required  Map<String, dynamic> pricingSnapshot, required this.billingMode, this.billedAmountPaise, this.voidReason, required this.createdAt, required this.updatedAt}): _pricingSnapshot = pricingSnapshot,super._();
  

@override final  String id;
@override final  String primaryCustomerId;
@override final  int playerCount;
@override final  int purchasedControllerCount;
@override final  GroupSessionStatus status;
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

@override final  GroupBillingMode billingMode;
@override final  int? billedAmountPaise;
@override final  String? voidReason;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of GroupSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GroupSessionCopyWith<_GroupSession> get copyWith => __$GroupSessionCopyWithImpl<_GroupSession>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GroupSession&&(identical(other.id, id) || other.id == id)&&(identical(other.primaryCustomerId, primaryCustomerId) || other.primaryCustomerId == primaryCustomerId)&&(identical(other.playerCount, playerCount) || other.playerCount == playerCount)&&(identical(other.purchasedControllerCount, purchasedControllerCount) || other.purchasedControllerCount == purchasedControllerCount)&&(identical(other.status, status) || other.status == status)&&(identical(other.paymentStatus, paymentStatus) || other.paymentStatus == paymentStatus)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.scheduledEndAt, scheduledEndAt) || other.scheduledEndAt == scheduledEndAt)&&(identical(other.actualEndedAt, actualEndedAt) || other.actualEndedAt == actualEndedAt)&&const DeepCollectionEquality().equals(other.pricingSnapshot, _pricingSnapshot)&&(identical(other.billingMode, billingMode) || other.billingMode == billingMode)&&(identical(other.billedAmountPaise, billedAmountPaise) || other.billedAmountPaise == billedAmountPaise)&&(identical(other.voidReason, voidReason) || other.voidReason == voidReason)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,primaryCustomerId,playerCount,purchasedControllerCount,status,paymentStatus,startedAt,scheduledEndAt,actualEndedAt,const DeepCollectionEquality().hash(_pricingSnapshot),billingMode,billedAmountPaise,voidReason,createdAt,updatedAt);
}

@override
String toString() {
    return 'GroupSession(id: $id, primaryCustomerId: $primaryCustomerId, playerCount: $playerCount, purchasedControllerCount: $purchasedControllerCount, status: $status, paymentStatus: $paymentStatus, startedAt: $startedAt, scheduledEndAt: $scheduledEndAt, actualEndedAt: $actualEndedAt, pricingSnapshot: $pricingSnapshot, billingMode: $billingMode, billedAmountPaise: $billedAmountPaise, voidReason: $voidReason, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$GroupSessionCopyWith<$Res> implements $GroupSessionCopyWith<$Res> {
  factory _$GroupSessionCopyWith(_GroupSession value, $Res Function(_GroupSession) _then) = __$GroupSessionCopyWithImpl;
@override @useResult
$Res call({
 String id, String primaryCustomerId, int playerCount, int purchasedControllerCount, GroupSessionStatus status, PaymentStatus paymentStatus, DateTime startedAt, DateTime scheduledEndAt, DateTime? actualEndedAt, Map<String, dynamic> pricingSnapshot, GroupBillingMode billingMode, int? billedAmountPaise, String? voidReason, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$GroupSessionCopyWithImpl<$Res>
    implements _$GroupSessionCopyWith<$Res> {
  __$GroupSessionCopyWithImpl(this._self, this._then);

  final _GroupSession _self;
  final $Res Function(_GroupSession) _then;

/// Create a copy of GroupSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? primaryCustomerId = null,Object? playerCount = null,Object? purchasedControllerCount = null,Object? status = null,Object? paymentStatus = null,Object? startedAt = null,Object? scheduledEndAt = null,Object? actualEndedAt = freezed,Object? pricingSnapshot = null,Object? billingMode = null,Object? billedAmountPaise = freezed,Object? voidReason = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_GroupSession(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,primaryCustomerId: null == primaryCustomerId ? _self.primaryCustomerId : primaryCustomerId // ignore: cast_nullable_to_non_nullable
as String,playerCount: null == playerCount ? _self.playerCount : playerCount // ignore: cast_nullable_to_non_nullable
as int,purchasedControllerCount: null == purchasedControllerCount ? _self.purchasedControllerCount : purchasedControllerCount // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as GroupSessionStatus,paymentStatus: null == paymentStatus ? _self.paymentStatus : paymentStatus // ignore: cast_nullable_to_non_nullable
as PaymentStatus,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,scheduledEndAt: null == scheduledEndAt ? _self.scheduledEndAt : scheduledEndAt // ignore: cast_nullable_to_non_nullable
as DateTime,actualEndedAt: freezed == actualEndedAt ? _self.actualEndedAt : actualEndedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,pricingSnapshot: null == pricingSnapshot ? _self._pricingSnapshot : pricingSnapshot // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,billingMode: null == billingMode ? _self.billingMode : billingMode // ignore: cast_nullable_to_non_nullable
as GroupBillingMode,billedAmountPaise: freezed == billedAmountPaise ? _self.billedAmountPaise : billedAmountPaise // ignore: cast_nullable_to_non_nullable
as int?,voidReason: freezed == voidReason ? _self.voidReason : voidReason // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc
mixin _$GroupAssignment {

 String get id; String get groupId; int get playerNumber; String? get playerLabel; int get index; String get resourceId; String get activityCode; String? get gameId; int? get controllerCount; DateTime get startedAt; DateTime? get endedAt; DateTime get createdAt;
/// Create a copy of GroupAssignment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GroupAssignmentCopyWith<GroupAssignment> get copyWith => _$GroupAssignmentCopyWithImpl<GroupAssignment>(this as GroupAssignment, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GroupAssignment;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GroupAssignment&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.groupId, _this.groupId) || other.groupId == _this.groupId)&&(identical(other.playerNumber, _this.playerNumber) || other.playerNumber == _this.playerNumber)&&(identical(other.playerLabel, _this.playerLabel) || other.playerLabel == _this.playerLabel)&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.resourceId, _this.resourceId) || other.resourceId == _this.resourceId)&&(identical(other.activityCode, _this.activityCode) || other.activityCode == _this.activityCode)&&(identical(other.gameId, _this.gameId) || other.gameId == _this.gameId)&&(identical(other.controllerCount, _this.controllerCount) || other.controllerCount == _this.controllerCount)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.endedAt, _this.endedAt) || other.endedAt == _this.endedAt)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}


@override
int get hashCode {
  final _this = this as GroupAssignment;
  return Object.hash(runtimeType,_this.id,_this.groupId,_this.playerNumber,_this.playerLabel,_this.index,_this.resourceId,_this.activityCode,_this.gameId,_this.controllerCount,_this.startedAt,_this.endedAt,_this.createdAt);
}

@override
String toString() {
  final _this = this as GroupAssignment;
  return 'GroupAssignment(id: ${_this.id}, groupId: ${_this.groupId}, playerNumber: ${_this.playerNumber}, playerLabel: ${_this.playerLabel}, index: ${_this.index}, resourceId: ${_this.resourceId}, activityCode: ${_this.activityCode}, gameId: ${_this.gameId}, controllerCount: ${_this.controllerCount}, startedAt: ${_this.startedAt}, endedAt: ${_this.endedAt}, createdAt: ${_this.createdAt})';
}


}

/// @nodoc
abstract mixin class $GroupAssignmentCopyWith<$Res>  {
  factory $GroupAssignmentCopyWith(GroupAssignment value, $Res Function(GroupAssignment) _then) = _$GroupAssignmentCopyWithImpl;
@useResult
$Res call({
 String id, String groupId, int playerNumber, String? playerLabel, int index, String resourceId, String activityCode, String? gameId, int? controllerCount, DateTime startedAt, DateTime? endedAt, DateTime createdAt
});




}
/// @nodoc
class _$GroupAssignmentCopyWithImpl<$Res>
    implements $GroupAssignmentCopyWith<$Res> {
  _$GroupAssignmentCopyWithImpl(this._self, this._then);

  final GroupAssignment _self;
  final $Res Function(GroupAssignment) _then;

/// Create a copy of GroupAssignment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? groupId = null,Object? playerNumber = null,Object? playerLabel = freezed,Object? index = null,Object? resourceId = null,Object? activityCode = null,Object? gameId = freezed,Object? controllerCount = freezed,Object? startedAt = null,Object? endedAt = freezed,Object? createdAt = null,}) {
  return _then(GroupAssignment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,groupId: null == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String,playerNumber: null == playerNumber ? _self.playerNumber : playerNumber // ignore: cast_nullable_to_non_nullable
as int,playerLabel: freezed == playerLabel ? _self.playerLabel : playerLabel // ignore: cast_nullable_to_non_nullable
as String?,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
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


/// Adds pattern-matching-related methods to [GroupAssignment].
extension GroupAssignmentPatterns on GroupAssignment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GroupAssignment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GroupAssignment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GroupAssignment value)  $default,){
final _that = this;
switch (_that) {
case _GroupAssignment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GroupAssignment value)?  $default,){
final _that = this;
switch (_that) {
case _GroupAssignment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String groupId,  int playerNumber,  String? playerLabel,  int index,  String resourceId,  String activityCode,  String? gameId,  int? controllerCount,  DateTime startedAt,  DateTime? endedAt,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GroupAssignment() when $default != null:
return $default(_that.id,_that.groupId,_that.playerNumber,_that.playerLabel,_that.index,_that.resourceId,_that.activityCode,_that.gameId,_that.controllerCount,_that.startedAt,_that.endedAt,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String groupId,  int playerNumber,  String? playerLabel,  int index,  String resourceId,  String activityCode,  String? gameId,  int? controllerCount,  DateTime startedAt,  DateTime? endedAt,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _GroupAssignment():
return $default(_that.id,_that.groupId,_that.playerNumber,_that.playerLabel,_that.index,_that.resourceId,_that.activityCode,_that.gameId,_that.controllerCount,_that.startedAt,_that.endedAt,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String groupId,  int playerNumber,  String? playerLabel,  int index,  String resourceId,  String activityCode,  String? gameId,  int? controllerCount,  DateTime startedAt,  DateTime? endedAt,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _GroupAssignment() when $default != null:
return $default(_that.id,_that.groupId,_that.playerNumber,_that.playerLabel,_that.index,_that.resourceId,_that.activityCode,_that.gameId,_that.controllerCount,_that.startedAt,_that.endedAt,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _GroupAssignment extends GroupAssignment {
  const _GroupAssignment({required this.id, required this.groupId, required this.playerNumber, this.playerLabel, required this.index, required this.resourceId, required this.activityCode, this.gameId, this.controllerCount, required this.startedAt, this.endedAt, required this.createdAt}): super._();
  

@override final  String id;
@override final  String groupId;
@override final  int playerNumber;
@override final  String? playerLabel;
@override final  int index;
@override final  String resourceId;
@override final  String activityCode;
@override final  String? gameId;
@override final  int? controllerCount;
@override final  DateTime startedAt;
@override final  DateTime? endedAt;
@override final  DateTime createdAt;

/// Create a copy of GroupAssignment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GroupAssignmentCopyWith<_GroupAssignment> get copyWith => __$GroupAssignmentCopyWithImpl<_GroupAssignment>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GroupAssignment&&(identical(other.id, id) || other.id == id)&&(identical(other.groupId, groupId) || other.groupId == groupId)&&(identical(other.playerNumber, playerNumber) || other.playerNumber == playerNumber)&&(identical(other.playerLabel, playerLabel) || other.playerLabel == playerLabel)&&(identical(other.index, index) || other.index == index)&&(identical(other.resourceId, resourceId) || other.resourceId == resourceId)&&(identical(other.activityCode, activityCode) || other.activityCode == activityCode)&&(identical(other.gameId, gameId) || other.gameId == gameId)&&(identical(other.controllerCount, controllerCount) || other.controllerCount == controllerCount)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.endedAt, endedAt) || other.endedAt == endedAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,groupId,playerNumber,playerLabel,index,resourceId,activityCode,gameId,controllerCount,startedAt,endedAt,createdAt);
}

@override
String toString() {
    return 'GroupAssignment(id: $id, groupId: $groupId, playerNumber: $playerNumber, playerLabel: $playerLabel, index: $index, resourceId: $resourceId, activityCode: $activityCode, gameId: $gameId, controllerCount: $controllerCount, startedAt: $startedAt, endedAt: $endedAt, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$GroupAssignmentCopyWith<$Res> implements $GroupAssignmentCopyWith<$Res> {
  factory _$GroupAssignmentCopyWith(_GroupAssignment value, $Res Function(_GroupAssignment) _then) = __$GroupAssignmentCopyWithImpl;
@override @useResult
$Res call({
 String id, String groupId, int playerNumber, String? playerLabel, int index, String resourceId, String activityCode, String? gameId, int? controllerCount, DateTime startedAt, DateTime? endedAt, DateTime createdAt
});




}
/// @nodoc
class __$GroupAssignmentCopyWithImpl<$Res>
    implements _$GroupAssignmentCopyWith<$Res> {
  __$GroupAssignmentCopyWithImpl(this._self, this._then);

  final _GroupAssignment _self;
  final $Res Function(_GroupAssignment) _then;

/// Create a copy of GroupAssignment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? groupId = null,Object? playerNumber = null,Object? playerLabel = freezed,Object? index = null,Object? resourceId = null,Object? activityCode = null,Object? gameId = freezed,Object? controllerCount = freezed,Object? startedAt = null,Object? endedAt = freezed,Object? createdAt = null,}) {
  return _then(_GroupAssignment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,groupId: null == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String,playerNumber: null == playerNumber ? _self.playerNumber : playerNumber // ignore: cast_nullable_to_non_nullable
as int,playerLabel: freezed == playerLabel ? _self.playerLabel : playerLabel // ignore: cast_nullable_to_non_nullable
as String?,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
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
mixin _$ActiveGroupSession {

 GroupSession get group; List<GroupAssignment> get assignments;
/// Create a copy of ActiveGroupSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActiveGroupSessionCopyWith<ActiveGroupSession> get copyWith => _$ActiveGroupSessionCopyWithImpl<ActiveGroupSession>(this as ActiveGroupSession, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActiveGroupSession;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActiveGroupSession&&(identical(other.group, _this.group) || other.group == _this.group)&&const DeepCollectionEquality().equals(other.assignments, _this.assignments));
}


@override
int get hashCode {
  final _this = this as ActiveGroupSession;
  return Object.hash(runtimeType,_this.group,const DeepCollectionEquality().hash(_this.assignments));
}

@override
String toString() {
  final _this = this as ActiveGroupSession;
  return 'ActiveGroupSession(group: ${_this.group}, assignments: ${_this.assignments})';
}


}

/// @nodoc
abstract mixin class $ActiveGroupSessionCopyWith<$Res>  {
  factory $ActiveGroupSessionCopyWith(ActiveGroupSession value, $Res Function(ActiveGroupSession) _then) = _$ActiveGroupSessionCopyWithImpl;
@useResult
$Res call({
 GroupSession group, List<GroupAssignment> assignments
});


$GroupSessionCopyWith<$Res> get group;

}
/// @nodoc
class _$ActiveGroupSessionCopyWithImpl<$Res>
    implements $ActiveGroupSessionCopyWith<$Res> {
  _$ActiveGroupSessionCopyWithImpl(this._self, this._then);

  final ActiveGroupSession _self;
  final $Res Function(ActiveGroupSession) _then;

/// Create a copy of ActiveGroupSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? group = null,Object? assignments = null,}) {
  return _then(ActiveGroupSession(
group: null == group ? _self.group : group // ignore: cast_nullable_to_non_nullable
as GroupSession,assignments: null == assignments ? _self.assignments : assignments // ignore: cast_nullable_to_non_nullable
as List<GroupAssignment>,
  ));
}
/// Create a copy of ActiveGroupSession
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GroupSessionCopyWith<$Res> get group {
  
  return $GroupSessionCopyWith<$Res>(_self.group, (value) {
    return _then(_self.copyWith(group: value));
  });
}
}


/// Adds pattern-matching-related methods to [ActiveGroupSession].
extension ActiveGroupSessionPatterns on ActiveGroupSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActiveGroupSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActiveGroupSession() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActiveGroupSession value)  $default,){
final _that = this;
switch (_that) {
case _ActiveGroupSession():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActiveGroupSession value)?  $default,){
final _that = this;
switch (_that) {
case _ActiveGroupSession() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( GroupSession group,  List<GroupAssignment> assignments)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActiveGroupSession() when $default != null:
return $default(_that.group,_that.assignments);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( GroupSession group,  List<GroupAssignment> assignments)  $default,) {final _that = this;
switch (_that) {
case _ActiveGroupSession():
return $default(_that.group,_that.assignments);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( GroupSession group,  List<GroupAssignment> assignments)?  $default,) {final _that = this;
switch (_that) {
case _ActiveGroupSession() when $default != null:
return $default(_that.group,_that.assignments);case _:
  return null;

}
}

}

/// @nodoc


class _ActiveGroupSession extends ActiveGroupSession {
  const _ActiveGroupSession({required this.group, required  List<GroupAssignment> assignments}): _assignments = assignments,super._();
  

@override final  GroupSession group;
 final  List<GroupAssignment> _assignments;
@override List<GroupAssignment> get assignments {
  if (_assignments is EqualUnmodifiableListView) return _assignments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_assignments);
}


/// Create a copy of ActiveGroupSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActiveGroupSessionCopyWith<_ActiveGroupSession> get copyWith => __$ActiveGroupSessionCopyWithImpl<_ActiveGroupSession>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActiveGroupSession&&(identical(other.group, group) || other.group == group)&&const DeepCollectionEquality().equals(other.assignments, _assignments));
}


@override
int get hashCode {
    return Object.hash(runtimeType,group,const DeepCollectionEquality().hash(_assignments));
}

@override
String toString() {
    return 'ActiveGroupSession(group: $group, assignments: $assignments)';
}


}

/// @nodoc
abstract mixin class _$ActiveGroupSessionCopyWith<$Res> implements $ActiveGroupSessionCopyWith<$Res> {
  factory _$ActiveGroupSessionCopyWith(_ActiveGroupSession value, $Res Function(_ActiveGroupSession) _then) = __$ActiveGroupSessionCopyWithImpl;
@override @useResult
$Res call({
 GroupSession group, List<GroupAssignment> assignments
});


@override $GroupSessionCopyWith<$Res> get group;

}
/// @nodoc
class __$ActiveGroupSessionCopyWithImpl<$Res>
    implements _$ActiveGroupSessionCopyWith<$Res> {
  __$ActiveGroupSessionCopyWithImpl(this._self, this._then);

  final _ActiveGroupSession _self;
  final $Res Function(_ActiveGroupSession) _then;

/// Create a copy of ActiveGroupSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? group = null,Object? assignments = null,}) {
  return _then(_ActiveGroupSession(
group: null == group ? _self.group : group // ignore: cast_nullable_to_non_nullable
as GroupSession,assignments: null == assignments ? _self._assignments : assignments // ignore: cast_nullable_to_non_nullable
as List<GroupAssignment>,
  ));
}

/// Create a copy of ActiveGroupSession
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$GroupSessionCopyWith<$Res> get group {
  
  return $GroupSessionCopyWith<$Res>(_self.group, (value) {
    return _then(_self.copyWith(group: value));
  });
}
}

/// @nodoc
mixin _$GroupExtension {

 String get id; String get groupId; int get addedMinutes; DateTime get oldEndAt; DateTime get newEndAt; int get addedAmountPaise; String? get reason; DateTime get createdAt;
/// Create a copy of GroupExtension
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GroupExtensionCopyWith<GroupExtension> get copyWith => _$GroupExtensionCopyWithImpl<GroupExtension>(this as GroupExtension, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GroupExtension;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GroupExtension&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.groupId, _this.groupId) || other.groupId == _this.groupId)&&(identical(other.addedMinutes, _this.addedMinutes) || other.addedMinutes == _this.addedMinutes)&&(identical(other.oldEndAt, _this.oldEndAt) || other.oldEndAt == _this.oldEndAt)&&(identical(other.newEndAt, _this.newEndAt) || other.newEndAt == _this.newEndAt)&&(identical(other.addedAmountPaise, _this.addedAmountPaise) || other.addedAmountPaise == _this.addedAmountPaise)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}


@override
int get hashCode {
  final _this = this as GroupExtension;
  return Object.hash(runtimeType,_this.id,_this.groupId,_this.addedMinutes,_this.oldEndAt,_this.newEndAt,_this.addedAmountPaise,_this.reason,_this.createdAt);
}

@override
String toString() {
  final _this = this as GroupExtension;
  return 'GroupExtension(id: ${_this.id}, groupId: ${_this.groupId}, addedMinutes: ${_this.addedMinutes}, oldEndAt: ${_this.oldEndAt}, newEndAt: ${_this.newEndAt}, addedAmountPaise: ${_this.addedAmountPaise}, reason: ${_this.reason}, createdAt: ${_this.createdAt})';
}


}

/// @nodoc
abstract mixin class $GroupExtensionCopyWith<$Res>  {
  factory $GroupExtensionCopyWith(GroupExtension value, $Res Function(GroupExtension) _then) = _$GroupExtensionCopyWithImpl;
@useResult
$Res call({
 String id, String groupId, int addedMinutes, DateTime oldEndAt, DateTime newEndAt, int addedAmountPaise, String? reason, DateTime createdAt
});




}
/// @nodoc
class _$GroupExtensionCopyWithImpl<$Res>
    implements $GroupExtensionCopyWith<$Res> {
  _$GroupExtensionCopyWithImpl(this._self, this._then);

  final GroupExtension _self;
  final $Res Function(GroupExtension) _then;

/// Create a copy of GroupExtension
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? groupId = null,Object? addedMinutes = null,Object? oldEndAt = null,Object? newEndAt = null,Object? addedAmountPaise = null,Object? reason = freezed,Object? createdAt = null,}) {
  return _then(GroupExtension(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,groupId: null == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
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


/// Adds pattern-matching-related methods to [GroupExtension].
extension GroupExtensionPatterns on GroupExtension {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GroupExtension value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GroupExtension() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GroupExtension value)  $default,){
final _that = this;
switch (_that) {
case _GroupExtension():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GroupExtension value)?  $default,){
final _that = this;
switch (_that) {
case _GroupExtension() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String groupId,  int addedMinutes,  DateTime oldEndAt,  DateTime newEndAt,  int addedAmountPaise,  String? reason,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GroupExtension() when $default != null:
return $default(_that.id,_that.groupId,_that.addedMinutes,_that.oldEndAt,_that.newEndAt,_that.addedAmountPaise,_that.reason,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String groupId,  int addedMinutes,  DateTime oldEndAt,  DateTime newEndAt,  int addedAmountPaise,  String? reason,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _GroupExtension():
return $default(_that.id,_that.groupId,_that.addedMinutes,_that.oldEndAt,_that.newEndAt,_that.addedAmountPaise,_that.reason,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String groupId,  int addedMinutes,  DateTime oldEndAt,  DateTime newEndAt,  int addedAmountPaise,  String? reason,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _GroupExtension() when $default != null:
return $default(_that.id,_that.groupId,_that.addedMinutes,_that.oldEndAt,_that.newEndAt,_that.addedAmountPaise,_that.reason,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _GroupExtension implements GroupExtension {
  const _GroupExtension({required this.id, required this.groupId, required this.addedMinutes, required this.oldEndAt, required this.newEndAt, this.addedAmountPaise = 0, this.reason, required this.createdAt});
  

@override final  String id;
@override final  String groupId;
@override final  int addedMinutes;
@override final  DateTime oldEndAt;
@override final  DateTime newEndAt;
@override@JsonKey() final  int addedAmountPaise;
@override final  String? reason;
@override final  DateTime createdAt;

/// Create a copy of GroupExtension
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GroupExtensionCopyWith<_GroupExtension> get copyWith => __$GroupExtensionCopyWithImpl<_GroupExtension>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GroupExtension&&(identical(other.id, id) || other.id == id)&&(identical(other.groupId, groupId) || other.groupId == groupId)&&(identical(other.addedMinutes, addedMinutes) || other.addedMinutes == addedMinutes)&&(identical(other.oldEndAt, oldEndAt) || other.oldEndAt == oldEndAt)&&(identical(other.newEndAt, newEndAt) || other.newEndAt == newEndAt)&&(identical(other.addedAmountPaise, addedAmountPaise) || other.addedAmountPaise == addedAmountPaise)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,groupId,addedMinutes,oldEndAt,newEndAt,addedAmountPaise,reason,createdAt);
}

@override
String toString() {
    return 'GroupExtension(id: $id, groupId: $groupId, addedMinutes: $addedMinutes, oldEndAt: $oldEndAt, newEndAt: $newEndAt, addedAmountPaise: $addedAmountPaise, reason: $reason, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$GroupExtensionCopyWith<$Res> implements $GroupExtensionCopyWith<$Res> {
  factory _$GroupExtensionCopyWith(_GroupExtension value, $Res Function(_GroupExtension) _then) = __$GroupExtensionCopyWithImpl;
@override @useResult
$Res call({
 String id, String groupId, int addedMinutes, DateTime oldEndAt, DateTime newEndAt, int addedAmountPaise, String? reason, DateTime createdAt
});




}
/// @nodoc
class __$GroupExtensionCopyWithImpl<$Res>
    implements _$GroupExtensionCopyWith<$Res> {
  __$GroupExtensionCopyWithImpl(this._self, this._then);

  final _GroupExtension _self;
  final $Res Function(_GroupExtension) _then;

/// Create a copy of GroupExtension
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? groupId = null,Object? addedMinutes = null,Object? oldEndAt = null,Object? newEndAt = null,Object? addedAmountPaise = null,Object? reason = freezed,Object? createdAt = null,}) {
  return _then(_GroupExtension(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,groupId: null == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
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
mixin _$GroupPayment {

 String get id; String get groupId; int get amountPaise; PaymentMethod get method; bool get isRefund; String? get note; String? get reason; DateTime get createdAt;
/// Create a copy of GroupPayment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GroupPaymentCopyWith<GroupPayment> get copyWith => _$GroupPaymentCopyWithImpl<GroupPayment>(this as GroupPayment, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GroupPayment;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GroupPayment&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.groupId, _this.groupId) || other.groupId == _this.groupId)&&(identical(other.amountPaise, _this.amountPaise) || other.amountPaise == _this.amountPaise)&&(identical(other.method, _this.method) || other.method == _this.method)&&(identical(other.isRefund, _this.isRefund) || other.isRefund == _this.isRefund)&&(identical(other.note, _this.note) || other.note == _this.note)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}


@override
int get hashCode {
  final _this = this as GroupPayment;
  return Object.hash(runtimeType,_this.id,_this.groupId,_this.amountPaise,_this.method,_this.isRefund,_this.note,_this.reason,_this.createdAt);
}

@override
String toString() {
  final _this = this as GroupPayment;
  return 'GroupPayment(id: ${_this.id}, groupId: ${_this.groupId}, amountPaise: ${_this.amountPaise}, method: ${_this.method}, isRefund: ${_this.isRefund}, note: ${_this.note}, reason: ${_this.reason}, createdAt: ${_this.createdAt})';
}


}

/// @nodoc
abstract mixin class $GroupPaymentCopyWith<$Res>  {
  factory $GroupPaymentCopyWith(GroupPayment value, $Res Function(GroupPayment) _then) = _$GroupPaymentCopyWithImpl;
@useResult
$Res call({
 String id, String groupId, int amountPaise, PaymentMethod method, bool isRefund, String? note, String? reason, DateTime createdAt
});




}
/// @nodoc
class _$GroupPaymentCopyWithImpl<$Res>
    implements $GroupPaymentCopyWith<$Res> {
  _$GroupPaymentCopyWithImpl(this._self, this._then);

  final GroupPayment _self;
  final $Res Function(GroupPayment) _then;

/// Create a copy of GroupPayment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? groupId = null,Object? amountPaise = null,Object? method = null,Object? isRefund = null,Object? note = freezed,Object? reason = freezed,Object? createdAt = null,}) {
  return _then(GroupPayment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,groupId: null == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String,amountPaise: null == amountPaise ? _self.amountPaise : amountPaise // ignore: cast_nullable_to_non_nullable
as int,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as PaymentMethod,isRefund: null == isRefund ? _self.isRefund : isRefund // ignore: cast_nullable_to_non_nullable
as bool,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [GroupPayment].
extension GroupPaymentPatterns on GroupPayment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GroupPayment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GroupPayment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GroupPayment value)  $default,){
final _that = this;
switch (_that) {
case _GroupPayment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GroupPayment value)?  $default,){
final _that = this;
switch (_that) {
case _GroupPayment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String groupId,  int amountPaise,  PaymentMethod method,  bool isRefund,  String? note,  String? reason,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GroupPayment() when $default != null:
return $default(_that.id,_that.groupId,_that.amountPaise,_that.method,_that.isRefund,_that.note,_that.reason,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String groupId,  int amountPaise,  PaymentMethod method,  bool isRefund,  String? note,  String? reason,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _GroupPayment():
return $default(_that.id,_that.groupId,_that.amountPaise,_that.method,_that.isRefund,_that.note,_that.reason,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String groupId,  int amountPaise,  PaymentMethod method,  bool isRefund,  String? note,  String? reason,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _GroupPayment() when $default != null:
return $default(_that.id,_that.groupId,_that.amountPaise,_that.method,_that.isRefund,_that.note,_that.reason,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _GroupPayment implements GroupPayment {
  const _GroupPayment({required this.id, required this.groupId, required this.amountPaise, required this.method, this.isRefund = false, this.note, this.reason, required this.createdAt});
  

@override final  String id;
@override final  String groupId;
@override final  int amountPaise;
@override final  PaymentMethod method;
@override@JsonKey() final  bool isRefund;
@override final  String? note;
@override final  String? reason;
@override final  DateTime createdAt;

/// Create a copy of GroupPayment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GroupPaymentCopyWith<_GroupPayment> get copyWith => __$GroupPaymentCopyWithImpl<_GroupPayment>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GroupPayment&&(identical(other.id, id) || other.id == id)&&(identical(other.groupId, groupId) || other.groupId == groupId)&&(identical(other.amountPaise, amountPaise) || other.amountPaise == amountPaise)&&(identical(other.method, method) || other.method == method)&&(identical(other.isRefund, isRefund) || other.isRefund == isRefund)&&(identical(other.note, note) || other.note == note)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,groupId,amountPaise,method,isRefund,note,reason,createdAt);
}

@override
String toString() {
    return 'GroupPayment(id: $id, groupId: $groupId, amountPaise: $amountPaise, method: $method, isRefund: $isRefund, note: $note, reason: $reason, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$GroupPaymentCopyWith<$Res> implements $GroupPaymentCopyWith<$Res> {
  factory _$GroupPaymentCopyWith(_GroupPayment value, $Res Function(_GroupPayment) _then) = __$GroupPaymentCopyWithImpl;
@override @useResult
$Res call({
 String id, String groupId, int amountPaise, PaymentMethod method, bool isRefund, String? note, String? reason, DateTime createdAt
});




}
/// @nodoc
class __$GroupPaymentCopyWithImpl<$Res>
    implements _$GroupPaymentCopyWith<$Res> {
  __$GroupPaymentCopyWithImpl(this._self, this._then);

  final _GroupPayment _self;
  final $Res Function(_GroupPayment) _then;

/// Create a copy of GroupPayment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? groupId = null,Object? amountPaise = null,Object? method = null,Object? isRefund = null,Object? note = freezed,Object? reason = freezed,Object? createdAt = null,}) {
  return _then(_GroupPayment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,groupId: null == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String,amountPaise: null == amountPaise ? _self.amountPaise : amountPaise // ignore: cast_nullable_to_non_nullable
as int,method: null == method ? _self.method : method // ignore: cast_nullable_to_non_nullable
as PaymentMethod,isRefund: null == isRefund ? _self.isRefund : isRefund // ignore: cast_nullable_to_non_nullable
as bool,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

/// @nodoc
mixin _$GroupCharge {

 String get id; String get groupId; String? get assignmentId; int? get playerNumber; int get chargeIndex; String get bandCode; String get activityCode; String? get resourceId; int? get controllerCount; DateTime get segmentStart; DateTime get segmentEnd; int get playedMinutes; int get billedMinutes; int get unitMinutes; int get unitPricePaise; int get amountPaise;
/// Create a copy of GroupCharge
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$GroupChargeCopyWith<GroupCharge> get copyWith => _$GroupChargeCopyWithImpl<GroupCharge>(this as GroupCharge, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as GroupCharge;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is GroupCharge&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.groupId, _this.groupId) || other.groupId == _this.groupId)&&(identical(other.assignmentId, _this.assignmentId) || other.assignmentId == _this.assignmentId)&&(identical(other.playerNumber, _this.playerNumber) || other.playerNumber == _this.playerNumber)&&(identical(other.chargeIndex, _this.chargeIndex) || other.chargeIndex == _this.chargeIndex)&&(identical(other.bandCode, _this.bandCode) || other.bandCode == _this.bandCode)&&(identical(other.activityCode, _this.activityCode) || other.activityCode == _this.activityCode)&&(identical(other.resourceId, _this.resourceId) || other.resourceId == _this.resourceId)&&(identical(other.controllerCount, _this.controllerCount) || other.controllerCount == _this.controllerCount)&&(identical(other.segmentStart, _this.segmentStart) || other.segmentStart == _this.segmentStart)&&(identical(other.segmentEnd, _this.segmentEnd) || other.segmentEnd == _this.segmentEnd)&&(identical(other.playedMinutes, _this.playedMinutes) || other.playedMinutes == _this.playedMinutes)&&(identical(other.billedMinutes, _this.billedMinutes) || other.billedMinutes == _this.billedMinutes)&&(identical(other.unitMinutes, _this.unitMinutes) || other.unitMinutes == _this.unitMinutes)&&(identical(other.unitPricePaise, _this.unitPricePaise) || other.unitPricePaise == _this.unitPricePaise)&&(identical(other.amountPaise, _this.amountPaise) || other.amountPaise == _this.amountPaise));
}


@override
int get hashCode {
  final _this = this as GroupCharge;
  return Object.hash(runtimeType,_this.id,_this.groupId,_this.assignmentId,_this.playerNumber,_this.chargeIndex,_this.bandCode,_this.activityCode,_this.resourceId,_this.controllerCount,_this.segmentStart,_this.segmentEnd,_this.playedMinutes,_this.billedMinutes,_this.unitMinutes,_this.unitPricePaise,_this.amountPaise);
}

@override
String toString() {
  final _this = this as GroupCharge;
  return 'GroupCharge(id: ${_this.id}, groupId: ${_this.groupId}, assignmentId: ${_this.assignmentId}, playerNumber: ${_this.playerNumber}, chargeIndex: ${_this.chargeIndex}, bandCode: ${_this.bandCode}, activityCode: ${_this.activityCode}, resourceId: ${_this.resourceId}, controllerCount: ${_this.controllerCount}, segmentStart: ${_this.segmentStart}, segmentEnd: ${_this.segmentEnd}, playedMinutes: ${_this.playedMinutes}, billedMinutes: ${_this.billedMinutes}, unitMinutes: ${_this.unitMinutes}, unitPricePaise: ${_this.unitPricePaise}, amountPaise: ${_this.amountPaise})';
}


}

/// @nodoc
abstract mixin class $GroupChargeCopyWith<$Res>  {
  factory $GroupChargeCopyWith(GroupCharge value, $Res Function(GroupCharge) _then) = _$GroupChargeCopyWithImpl;
@useResult
$Res call({
 String id, String groupId, String? assignmentId, int? playerNumber, int chargeIndex, String bandCode, String activityCode, String? resourceId, int? controllerCount, DateTime segmentStart, DateTime segmentEnd, int playedMinutes, int billedMinutes, int unitMinutes, int unitPricePaise, int amountPaise
});




}
/// @nodoc
class _$GroupChargeCopyWithImpl<$Res>
    implements $GroupChargeCopyWith<$Res> {
  _$GroupChargeCopyWithImpl(this._self, this._then);

  final GroupCharge _self;
  final $Res Function(GroupCharge) _then;

/// Create a copy of GroupCharge
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? groupId = null,Object? assignmentId = freezed,Object? playerNumber = freezed,Object? chargeIndex = null,Object? bandCode = null,Object? activityCode = null,Object? resourceId = freezed,Object? controllerCount = freezed,Object? segmentStart = null,Object? segmentEnd = null,Object? playedMinutes = null,Object? billedMinutes = null,Object? unitMinutes = null,Object? unitPricePaise = null,Object? amountPaise = null,}) {
  return _then(GroupCharge(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,groupId: null == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String,assignmentId: freezed == assignmentId ? _self.assignmentId : assignmentId // ignore: cast_nullable_to_non_nullable
as String?,playerNumber: freezed == playerNumber ? _self.playerNumber : playerNumber // ignore: cast_nullable_to_non_nullable
as int?,chargeIndex: null == chargeIndex ? _self.chargeIndex : chargeIndex // ignore: cast_nullable_to_non_nullable
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


/// Adds pattern-matching-related methods to [GroupCharge].
extension GroupChargePatterns on GroupCharge {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _GroupCharge value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _GroupCharge() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _GroupCharge value)  $default,){
final _that = this;
switch (_that) {
case _GroupCharge():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _GroupCharge value)?  $default,){
final _that = this;
switch (_that) {
case _GroupCharge() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String groupId,  String? assignmentId,  int? playerNumber,  int chargeIndex,  String bandCode,  String activityCode,  String? resourceId,  int? controllerCount,  DateTime segmentStart,  DateTime segmentEnd,  int playedMinutes,  int billedMinutes,  int unitMinutes,  int unitPricePaise,  int amountPaise)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _GroupCharge() when $default != null:
return $default(_that.id,_that.groupId,_that.assignmentId,_that.playerNumber,_that.chargeIndex,_that.bandCode,_that.activityCode,_that.resourceId,_that.controllerCount,_that.segmentStart,_that.segmentEnd,_that.playedMinutes,_that.billedMinutes,_that.unitMinutes,_that.unitPricePaise,_that.amountPaise);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String groupId,  String? assignmentId,  int? playerNumber,  int chargeIndex,  String bandCode,  String activityCode,  String? resourceId,  int? controllerCount,  DateTime segmentStart,  DateTime segmentEnd,  int playedMinutes,  int billedMinutes,  int unitMinutes,  int unitPricePaise,  int amountPaise)  $default,) {final _that = this;
switch (_that) {
case _GroupCharge():
return $default(_that.id,_that.groupId,_that.assignmentId,_that.playerNumber,_that.chargeIndex,_that.bandCode,_that.activityCode,_that.resourceId,_that.controllerCount,_that.segmentStart,_that.segmentEnd,_that.playedMinutes,_that.billedMinutes,_that.unitMinutes,_that.unitPricePaise,_that.amountPaise);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String groupId,  String? assignmentId,  int? playerNumber,  int chargeIndex,  String bandCode,  String activityCode,  String? resourceId,  int? controllerCount,  DateTime segmentStart,  DateTime segmentEnd,  int playedMinutes,  int billedMinutes,  int unitMinutes,  int unitPricePaise,  int amountPaise)?  $default,) {final _that = this;
switch (_that) {
case _GroupCharge() when $default != null:
return $default(_that.id,_that.groupId,_that.assignmentId,_that.playerNumber,_that.chargeIndex,_that.bandCode,_that.activityCode,_that.resourceId,_that.controllerCount,_that.segmentStart,_that.segmentEnd,_that.playedMinutes,_that.billedMinutes,_that.unitMinutes,_that.unitPricePaise,_that.amountPaise);case _:
  return null;

}
}

}

/// @nodoc


class _GroupCharge implements GroupCharge {
  const _GroupCharge({required this.id, required this.groupId, this.assignmentId, this.playerNumber, required this.chargeIndex, required this.bandCode, required this.activityCode, this.resourceId, this.controllerCount, required this.segmentStart, required this.segmentEnd, required this.playedMinutes, required this.billedMinutes, required this.unitMinutes, required this.unitPricePaise, required this.amountPaise});
  

@override final  String id;
@override final  String groupId;
@override final  String? assignmentId;
@override final  int? playerNumber;
@override final  int chargeIndex;
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

/// Create a copy of GroupCharge
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$GroupChargeCopyWith<_GroupCharge> get copyWith => __$GroupChargeCopyWithImpl<_GroupCharge>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _GroupCharge&&(identical(other.id, id) || other.id == id)&&(identical(other.groupId, groupId) || other.groupId == groupId)&&(identical(other.assignmentId, assignmentId) || other.assignmentId == assignmentId)&&(identical(other.playerNumber, playerNumber) || other.playerNumber == playerNumber)&&(identical(other.chargeIndex, chargeIndex) || other.chargeIndex == chargeIndex)&&(identical(other.bandCode, bandCode) || other.bandCode == bandCode)&&(identical(other.activityCode, activityCode) || other.activityCode == activityCode)&&(identical(other.resourceId, resourceId) || other.resourceId == resourceId)&&(identical(other.controllerCount, controllerCount) || other.controllerCount == controllerCount)&&(identical(other.segmentStart, segmentStart) || other.segmentStart == segmentStart)&&(identical(other.segmentEnd, segmentEnd) || other.segmentEnd == segmentEnd)&&(identical(other.playedMinutes, playedMinutes) || other.playedMinutes == playedMinutes)&&(identical(other.billedMinutes, billedMinutes) || other.billedMinutes == billedMinutes)&&(identical(other.unitMinutes, unitMinutes) || other.unitMinutes == unitMinutes)&&(identical(other.unitPricePaise, unitPricePaise) || other.unitPricePaise == unitPricePaise)&&(identical(other.amountPaise, amountPaise) || other.amountPaise == amountPaise));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,groupId,assignmentId,playerNumber,chargeIndex,bandCode,activityCode,resourceId,controllerCount,segmentStart,segmentEnd,playedMinutes,billedMinutes,unitMinutes,unitPricePaise,amountPaise);
}

@override
String toString() {
    return 'GroupCharge(id: $id, groupId: $groupId, assignmentId: $assignmentId, playerNumber: $playerNumber, chargeIndex: $chargeIndex, bandCode: $bandCode, activityCode: $activityCode, resourceId: $resourceId, controllerCount: $controllerCount, segmentStart: $segmentStart, segmentEnd: $segmentEnd, playedMinutes: $playedMinutes, billedMinutes: $billedMinutes, unitMinutes: $unitMinutes, unitPricePaise: $unitPricePaise, amountPaise: $amountPaise)';
}


}

/// @nodoc
abstract mixin class _$GroupChargeCopyWith<$Res> implements $GroupChargeCopyWith<$Res> {
  factory _$GroupChargeCopyWith(_GroupCharge value, $Res Function(_GroupCharge) _then) = __$GroupChargeCopyWithImpl;
@override @useResult
$Res call({
 String id, String groupId, String? assignmentId, int? playerNumber, int chargeIndex, String bandCode, String activityCode, String? resourceId, int? controllerCount, DateTime segmentStart, DateTime segmentEnd, int playedMinutes, int billedMinutes, int unitMinutes, int unitPricePaise, int amountPaise
});




}
/// @nodoc
class __$GroupChargeCopyWithImpl<$Res>
    implements _$GroupChargeCopyWith<$Res> {
  __$GroupChargeCopyWithImpl(this._self, this._then);

  final _GroupCharge _self;
  final $Res Function(_GroupCharge) _then;

/// Create a copy of GroupCharge
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? groupId = null,Object? assignmentId = freezed,Object? playerNumber = freezed,Object? chargeIndex = null,Object? bandCode = null,Object? activityCode = null,Object? resourceId = freezed,Object? controllerCount = freezed,Object? segmentStart = null,Object? segmentEnd = null,Object? playedMinutes = null,Object? billedMinutes = null,Object? unitMinutes = null,Object? unitPricePaise = null,Object? amountPaise = null,}) {
  return _then(_GroupCharge(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,groupId: null == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String,assignmentId: freezed == assignmentId ? _self.assignmentId : assignmentId // ignore: cast_nullable_to_non_nullable
as String?,playerNumber: freezed == playerNumber ? _self.playerNumber : playerNumber // ignore: cast_nullable_to_non_nullable
as int?,chargeIndex: null == chargeIndex ? _self.chargeIndex : chargeIndex // ignore: cast_nullable_to_non_nullable
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
