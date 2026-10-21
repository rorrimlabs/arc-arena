// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'pricing_rule.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PricingRule {

 String get id; String get name;/// Lower wins when several rules match; ties by [name], then [id].
 int get priority;/// ISO weekdays (1 = Monday … 7 = Sunday) of the IST date of the start.
 List<int> get days;/// Window in minutes after IST midnight, `[startMin, endMin)`.
 int get startMin; int get endMin; RuleHolidayMode get holidayMode;/// First / last IST date the rule applies (inclusive); null = open-ended.
 IstDate? get validFrom; IstDate? get validUntil;/// Activity codes the rule applies to; empty = every activity.
 List<String> get activityCodes; RuleAdjustKind get adjustKind;/// Signed: percent (−100…500) or paise per hour.
 int get adjustValue;
/// Create a copy of PricingRule
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PricingRuleCopyWith<PricingRule> get copyWith => _$PricingRuleCopyWithImpl<PricingRule>(this as PricingRule, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PricingRule;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PricingRule&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.priority, _this.priority) || other.priority == _this.priority)&&const DeepCollectionEquality().equals(other.days, _this.days)&&(identical(other.startMin, _this.startMin) || other.startMin == _this.startMin)&&(identical(other.endMin, _this.endMin) || other.endMin == _this.endMin)&&(identical(other.holidayMode, _this.holidayMode) || other.holidayMode == _this.holidayMode)&&(identical(other.validFrom, _this.validFrom) || other.validFrom == _this.validFrom)&&(identical(other.validUntil, _this.validUntil) || other.validUntil == _this.validUntil)&&const DeepCollectionEquality().equals(other.activityCodes, _this.activityCodes)&&(identical(other.adjustKind, _this.adjustKind) || other.adjustKind == _this.adjustKind)&&(identical(other.adjustValue, _this.adjustValue) || other.adjustValue == _this.adjustValue));
}


@override
int get hashCode {
  final _this = this as PricingRule;
  return Object.hash(runtimeType,_this.id,_this.name,_this.priority,const DeepCollectionEquality().hash(_this.days),_this.startMin,_this.endMin,_this.holidayMode,_this.validFrom,_this.validUntil,const DeepCollectionEquality().hash(_this.activityCodes),_this.adjustKind,_this.adjustValue);
}

@override
String toString() {
  final _this = this as PricingRule;
  return 'PricingRule(id: ${_this.id}, name: ${_this.name}, priority: ${_this.priority}, days: ${_this.days}, startMin: ${_this.startMin}, endMin: ${_this.endMin}, holidayMode: ${_this.holidayMode}, validFrom: ${_this.validFrom}, validUntil: ${_this.validUntil}, activityCodes: ${_this.activityCodes}, adjustKind: ${_this.adjustKind}, adjustValue: ${_this.adjustValue})';
}


}

/// @nodoc
abstract mixin class $PricingRuleCopyWith<$Res>  {
  factory $PricingRuleCopyWith(PricingRule value, $Res Function(PricingRule) _then) = _$PricingRuleCopyWithImpl;
@useResult
$Res call({
 String id, String name, int priority, List<int> days, int startMin, int endMin, RuleHolidayMode holidayMode, IstDate? validFrom, IstDate? validUntil, List<String> activityCodes, RuleAdjustKind adjustKind, int adjustValue
});




}
/// @nodoc
class _$PricingRuleCopyWithImpl<$Res>
    implements $PricingRuleCopyWith<$Res> {
  _$PricingRuleCopyWithImpl(this._self, this._then);

  final PricingRule _self;
  final $Res Function(PricingRule) _then;

/// Create a copy of PricingRule
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? priority = null,Object? days = null,Object? startMin = null,Object? endMin = null,Object? holidayMode = null,Object? validFrom = freezed,Object? validUntil = freezed,Object? activityCodes = null,Object? adjustKind = null,Object? adjustValue = null,}) {
  return _then(PricingRule(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,days: null == days ? _self.days : days // ignore: cast_nullable_to_non_nullable
as List<int>,startMin: null == startMin ? _self.startMin : startMin // ignore: cast_nullable_to_non_nullable
as int,endMin: null == endMin ? _self.endMin : endMin // ignore: cast_nullable_to_non_nullable
as int,holidayMode: null == holidayMode ? _self.holidayMode : holidayMode // ignore: cast_nullable_to_non_nullable
as RuleHolidayMode,validFrom: freezed == validFrom ? _self.validFrom : validFrom // ignore: cast_nullable_to_non_nullable
as IstDate?,validUntil: freezed == validUntil ? _self.validUntil : validUntil // ignore: cast_nullable_to_non_nullable
as IstDate?,activityCodes: null == activityCodes ? _self.activityCodes : activityCodes // ignore: cast_nullable_to_non_nullable
as List<String>,adjustKind: null == adjustKind ? _self.adjustKind : adjustKind // ignore: cast_nullable_to_non_nullable
as RuleAdjustKind,adjustValue: null == adjustValue ? _self.adjustValue : adjustValue // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PricingRule].
extension PricingRulePatterns on PricingRule {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PricingRule value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PricingRule() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PricingRule value)  $default,){
final _that = this;
switch (_that) {
case _PricingRule():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PricingRule value)?  $default,){
final _that = this;
switch (_that) {
case _PricingRule() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  int priority,  List<int> days,  int startMin,  int endMin,  RuleHolidayMode holidayMode,  IstDate? validFrom,  IstDate? validUntil,  List<String> activityCodes,  RuleAdjustKind adjustKind,  int adjustValue)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PricingRule() when $default != null:
return $default(_that.id,_that.name,_that.priority,_that.days,_that.startMin,_that.endMin,_that.holidayMode,_that.validFrom,_that.validUntil,_that.activityCodes,_that.adjustKind,_that.adjustValue);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  int priority,  List<int> days,  int startMin,  int endMin,  RuleHolidayMode holidayMode,  IstDate? validFrom,  IstDate? validUntil,  List<String> activityCodes,  RuleAdjustKind adjustKind,  int adjustValue)  $default,) {final _that = this;
switch (_that) {
case _PricingRule():
return $default(_that.id,_that.name,_that.priority,_that.days,_that.startMin,_that.endMin,_that.holidayMode,_that.validFrom,_that.validUntil,_that.activityCodes,_that.adjustKind,_that.adjustValue);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  int priority,  List<int> days,  int startMin,  int endMin,  RuleHolidayMode holidayMode,  IstDate? validFrom,  IstDate? validUntil,  List<String> activityCodes,  RuleAdjustKind adjustKind,  int adjustValue)?  $default,) {final _that = this;
switch (_that) {
case _PricingRule() when $default != null:
return $default(_that.id,_that.name,_that.priority,_that.days,_that.startMin,_that.endMin,_that.holidayMode,_that.validFrom,_that.validUntil,_that.activityCodes,_that.adjustKind,_that.adjustValue);case _:
  return null;

}
}

}

/// @nodoc


class _PricingRule extends PricingRule {
  const _PricingRule({required this.id, required this.name, required this.priority, required  List<int> days, required this.startMin, required this.endMin, this.holidayMode = RuleHolidayMode.any, this.validFrom, this.validUntil,  List<String> activityCodes = const <String>[], required this.adjustKind, required this.adjustValue}): _days = days,_activityCodes = activityCodes,super._();
  

@override final  String id;
@override final  String name;
/// Lower wins when several rules match; ties by [name], then [id].
@override final  int priority;
/// ISO weekdays (1 = Monday … 7 = Sunday) of the IST date of the start.
 final  List<int> _days;
/// ISO weekdays (1 = Monday … 7 = Sunday) of the IST date of the start.
@override List<int> get days {
  if (_days is EqualUnmodifiableListView) return _days;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_days);
}

/// Window in minutes after IST midnight, `[startMin, endMin)`.
@override final  int startMin;
@override final  int endMin;
@override@JsonKey() final  RuleHolidayMode holidayMode;
/// First / last IST date the rule applies (inclusive); null = open-ended.
@override final  IstDate? validFrom;
@override final  IstDate? validUntil;
/// Activity codes the rule applies to; empty = every activity.
 final  List<String> _activityCodes;
/// Activity codes the rule applies to; empty = every activity.
@override@JsonKey() List<String> get activityCodes {
  if (_activityCodes is EqualUnmodifiableListView) return _activityCodes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activityCodes);
}

@override final  RuleAdjustKind adjustKind;
/// Signed: percent (−100…500) or paise per hour.
@override final  int adjustValue;

/// Create a copy of PricingRule
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PricingRuleCopyWith<_PricingRule> get copyWith => __$PricingRuleCopyWithImpl<_PricingRule>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PricingRule&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.priority, priority) || other.priority == priority)&&const DeepCollectionEquality().equals(other.days, _days)&&(identical(other.startMin, startMin) || other.startMin == startMin)&&(identical(other.endMin, endMin) || other.endMin == endMin)&&(identical(other.holidayMode, holidayMode) || other.holidayMode == holidayMode)&&(identical(other.validFrom, validFrom) || other.validFrom == validFrom)&&(identical(other.validUntil, validUntil) || other.validUntil == validUntil)&&const DeepCollectionEquality().equals(other.activityCodes, _activityCodes)&&(identical(other.adjustKind, adjustKind) || other.adjustKind == adjustKind)&&(identical(other.adjustValue, adjustValue) || other.adjustValue == adjustValue));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,priority,const DeepCollectionEquality().hash(_days),startMin,endMin,holidayMode,validFrom,validUntil,const DeepCollectionEquality().hash(_activityCodes),adjustKind,adjustValue);
}

@override
String toString() {
    return 'PricingRule(id: $id, name: $name, priority: $priority, days: $days, startMin: $startMin, endMin: $endMin, holidayMode: $holidayMode, validFrom: $validFrom, validUntil: $validUntil, activityCodes: $activityCodes, adjustKind: $adjustKind, adjustValue: $adjustValue)';
}


}

/// @nodoc
abstract mixin class _$PricingRuleCopyWith<$Res> implements $PricingRuleCopyWith<$Res> {
  factory _$PricingRuleCopyWith(_PricingRule value, $Res Function(_PricingRule) _then) = __$PricingRuleCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, int priority, List<int> days, int startMin, int endMin, RuleHolidayMode holidayMode, IstDate? validFrom, IstDate? validUntil, List<String> activityCodes, RuleAdjustKind adjustKind, int adjustValue
});




}
/// @nodoc
class __$PricingRuleCopyWithImpl<$Res>
    implements _$PricingRuleCopyWith<$Res> {
  __$PricingRuleCopyWithImpl(this._self, this._then);

  final _PricingRule _self;
  final $Res Function(_PricingRule) _then;

/// Create a copy of PricingRule
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? priority = null,Object? days = null,Object? startMin = null,Object? endMin = null,Object? holidayMode = null,Object? validFrom = freezed,Object? validUntil = freezed,Object? activityCodes = null,Object? adjustKind = null,Object? adjustValue = null,}) {
  return _then(_PricingRule(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,days: null == days ? _self._days : days // ignore: cast_nullable_to_non_nullable
as List<int>,startMin: null == startMin ? _self.startMin : startMin // ignore: cast_nullable_to_non_nullable
as int,endMin: null == endMin ? _self.endMin : endMin // ignore: cast_nullable_to_non_nullable
as int,holidayMode: null == holidayMode ? _self.holidayMode : holidayMode // ignore: cast_nullable_to_non_nullable
as RuleHolidayMode,validFrom: freezed == validFrom ? _self.validFrom : validFrom // ignore: cast_nullable_to_non_nullable
as IstDate?,validUntil: freezed == validUntil ? _self.validUntil : validUntil // ignore: cast_nullable_to_non_nullable
as IstDate?,activityCodes: null == activityCodes ? _self._activityCodes : activityCodes // ignore: cast_nullable_to_non_nullable
as List<String>,adjustKind: null == adjustKind ? _self.adjustKind : adjustKind // ignore: cast_nullable_to_non_nullable
as RuleAdjustKind,adjustValue: null == adjustValue ? _self.adjustValue : adjustValue // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
