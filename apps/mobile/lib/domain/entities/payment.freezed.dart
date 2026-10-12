// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'payment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Payment {

 String get id; String get sessionId; int get amountPaise; PaymentMethod get method; bool get isRefund; String? get note; String? get reason; DateTime get createdAt;
/// Create a copy of Payment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PaymentCopyWith<Payment> get copyWith => _$PaymentCopyWithImpl<Payment>(this as Payment, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Payment;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Payment&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.sessionId, _this.sessionId) || other.sessionId == _this.sessionId)&&(identical(other.amountPaise, _this.amountPaise) || other.amountPaise == _this.amountPaise)&&(identical(other.method, _this.method) || other.method == _this.method)&&(identical(other.isRefund, _this.isRefund) || other.isRefund == _this.isRefund)&&(identical(other.note, _this.note) || other.note == _this.note)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}


@override
int get hashCode {
  final _this = this as Payment;
  return Object.hash(runtimeType,_this.id,_this.sessionId,_this.amountPaise,_this.method,_this.isRefund,_this.note,_this.reason,_this.createdAt);
}

@override
String toString() {
  final _this = this as Payment;
  return 'Payment(id: ${_this.id}, sessionId: ${_this.sessionId}, amountPaise: ${_this.amountPaise}, method: ${_this.method}, isRefund: ${_this.isRefund}, note: ${_this.note}, reason: ${_this.reason}, createdAt: ${_this.createdAt})';
}


}

/// @nodoc
abstract mixin class $PaymentCopyWith<$Res>  {
  factory $PaymentCopyWith(Payment value, $Res Function(Payment) _then) = _$PaymentCopyWithImpl;
@useResult
$Res call({
 String id, String sessionId, int amountPaise, PaymentMethod method, bool isRefund, String? note, String? reason, DateTime createdAt
});




}
/// @nodoc
class _$PaymentCopyWithImpl<$Res>
    implements $PaymentCopyWith<$Res> {
  _$PaymentCopyWithImpl(this._self, this._then);

  final Payment _self;
  final $Res Function(Payment) _then;

/// Create a copy of Payment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sessionId = null,Object? amountPaise = null,Object? method = null,Object? isRefund = null,Object? note = freezed,Object? reason = freezed,Object? createdAt = null,}) {
  return _then(Payment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
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


/// Adds pattern-matching-related methods to [Payment].
extension PaymentPatterns on Payment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Payment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Payment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Payment value)  $default,){
final _that = this;
switch (_that) {
case _Payment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Payment value)?  $default,){
final _that = this;
switch (_that) {
case _Payment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String sessionId,  int amountPaise,  PaymentMethod method,  bool isRefund,  String? note,  String? reason,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Payment() when $default != null:
return $default(_that.id,_that.sessionId,_that.amountPaise,_that.method,_that.isRefund,_that.note,_that.reason,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String sessionId,  int amountPaise,  PaymentMethod method,  bool isRefund,  String? note,  String? reason,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _Payment():
return $default(_that.id,_that.sessionId,_that.amountPaise,_that.method,_that.isRefund,_that.note,_that.reason,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String sessionId,  int amountPaise,  PaymentMethod method,  bool isRefund,  String? note,  String? reason,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _Payment() when $default != null:
return $default(_that.id,_that.sessionId,_that.amountPaise,_that.method,_that.isRefund,_that.note,_that.reason,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _Payment extends Payment {
  const _Payment({required this.id, required this.sessionId, required this.amountPaise, required this.method, this.isRefund = false, this.note, this.reason, required this.createdAt}): super._();
  

@override final  String id;
@override final  String sessionId;
@override final  int amountPaise;
@override final  PaymentMethod method;
@override@JsonKey() final  bool isRefund;
@override final  String? note;
@override final  String? reason;
@override final  DateTime createdAt;

/// Create a copy of Payment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PaymentCopyWith<_Payment> get copyWith => __$PaymentCopyWithImpl<_Payment>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Payment&&(identical(other.id, id) || other.id == id)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.amountPaise, amountPaise) || other.amountPaise == amountPaise)&&(identical(other.method, method) || other.method == method)&&(identical(other.isRefund, isRefund) || other.isRefund == isRefund)&&(identical(other.note, note) || other.note == note)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,sessionId,amountPaise,method,isRefund,note,reason,createdAt);
}

@override
String toString() {
    return 'Payment(id: $id, sessionId: $sessionId, amountPaise: $amountPaise, method: $method, isRefund: $isRefund, note: $note, reason: $reason, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$PaymentCopyWith<$Res> implements $PaymentCopyWith<$Res> {
  factory _$PaymentCopyWith(_Payment value, $Res Function(_Payment) _then) = __$PaymentCopyWithImpl;
@override @useResult
$Res call({
 String id, String sessionId, int amountPaise, PaymentMethod method, bool isRefund, String? note, String? reason, DateTime createdAt
});




}
/// @nodoc
class __$PaymentCopyWithImpl<$Res>
    implements _$PaymentCopyWith<$Res> {
  __$PaymentCopyWithImpl(this._self, this._then);

  final _Payment _self;
  final $Res Function(_Payment) _then;

/// Create a copy of Payment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? sessionId = null,Object? amountPaise = null,Object? method = null,Object? isRefund = null,Object? note = freezed,Object? reason = freezed,Object? createdAt = null,}) {
  return _then(_Payment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
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

// dart format on
