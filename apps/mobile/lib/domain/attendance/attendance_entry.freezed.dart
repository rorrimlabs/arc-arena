// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'attendance_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AttendancePunch {

 String get id; PunchKind get kind;/// When the server received it — the time that counts.
 DateTime get serverAt;/// What the phone's clock said (evidence only).
 DateTime? get deviceAt; double? get lat; double? get lng; double? get accuracyM; bool? get isMocked;/// `attendance_punches.location_status` (ok, denied, gps_off, …).
 String get locationStatus; int? get distanceM; GeofenceVerdict get verdict;/// The geofence in force when the punch was judged.
 Geofence? get geofence; List<String> get flags;
/// Create a copy of AttendancePunch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttendancePunchCopyWith<AttendancePunch> get copyWith => _$AttendancePunchCopyWithImpl<AttendancePunch>(this as AttendancePunch, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AttendancePunch;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AttendancePunch&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.serverAt, _this.serverAt) || other.serverAt == _this.serverAt)&&(identical(other.deviceAt, _this.deviceAt) || other.deviceAt == _this.deviceAt)&&(identical(other.lat, _this.lat) || other.lat == _this.lat)&&(identical(other.lng, _this.lng) || other.lng == _this.lng)&&(identical(other.accuracyM, _this.accuracyM) || other.accuracyM == _this.accuracyM)&&(identical(other.isMocked, _this.isMocked) || other.isMocked == _this.isMocked)&&(identical(other.locationStatus, _this.locationStatus) || other.locationStatus == _this.locationStatus)&&(identical(other.distanceM, _this.distanceM) || other.distanceM == _this.distanceM)&&(identical(other.verdict, _this.verdict) || other.verdict == _this.verdict)&&(identical(other.geofence, _this.geofence) || other.geofence == _this.geofence)&&const DeepCollectionEquality().equals(other.flags, _this.flags));
}


@override
int get hashCode {
  final _this = this as AttendancePunch;
  return Object.hash(runtimeType,_this.id,_this.kind,_this.serverAt,_this.deviceAt,_this.lat,_this.lng,_this.accuracyM,_this.isMocked,_this.locationStatus,_this.distanceM,_this.verdict,_this.geofence,const DeepCollectionEquality().hash(_this.flags));
}

@override
String toString() {
  final _this = this as AttendancePunch;
  return 'AttendancePunch(id: ${_this.id}, kind: ${_this.kind}, serverAt: ${_this.serverAt}, deviceAt: ${_this.deviceAt}, lat: ${_this.lat}, lng: ${_this.lng}, accuracyM: ${_this.accuracyM}, isMocked: ${_this.isMocked}, locationStatus: ${_this.locationStatus}, distanceM: ${_this.distanceM}, verdict: ${_this.verdict}, geofence: ${_this.geofence}, flags: ${_this.flags})';
}


}

/// @nodoc
abstract mixin class $AttendancePunchCopyWith<$Res>  {
  factory $AttendancePunchCopyWith(AttendancePunch value, $Res Function(AttendancePunch) _then) = _$AttendancePunchCopyWithImpl;
@useResult
$Res call({
 String id, PunchKind kind, DateTime serverAt, DateTime? deviceAt, double? lat, double? lng, double? accuracyM, bool? isMocked, String locationStatus, int? distanceM, GeofenceVerdict verdict, Geofence? geofence, List<String> flags
});




}
/// @nodoc
class _$AttendancePunchCopyWithImpl<$Res>
    implements $AttendancePunchCopyWith<$Res> {
  _$AttendancePunchCopyWithImpl(this._self, this._then);

  final AttendancePunch _self;
  final $Res Function(AttendancePunch) _then;

/// Create a copy of AttendancePunch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? kind = null,Object? serverAt = null,Object? deviceAt = freezed,Object? lat = freezed,Object? lng = freezed,Object? accuracyM = freezed,Object? isMocked = freezed,Object? locationStatus = null,Object? distanceM = freezed,Object? verdict = null,Object? geofence = freezed,Object? flags = null,}) {
  return _then(AttendancePunch(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as PunchKind,serverAt: null == serverAt ? _self.serverAt : serverAt // ignore: cast_nullable_to_non_nullable
as DateTime,deviceAt: freezed == deviceAt ? _self.deviceAt : deviceAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lat: freezed == lat ? _self.lat : lat // ignore: cast_nullable_to_non_nullable
as double?,lng: freezed == lng ? _self.lng : lng // ignore: cast_nullable_to_non_nullable
as double?,accuracyM: freezed == accuracyM ? _self.accuracyM : accuracyM // ignore: cast_nullable_to_non_nullable
as double?,isMocked: freezed == isMocked ? _self.isMocked : isMocked // ignore: cast_nullable_to_non_nullable
as bool?,locationStatus: null == locationStatus ? _self.locationStatus : locationStatus // ignore: cast_nullable_to_non_nullable
as String,distanceM: freezed == distanceM ? _self.distanceM : distanceM // ignore: cast_nullable_to_non_nullable
as int?,verdict: null == verdict ? _self.verdict : verdict // ignore: cast_nullable_to_non_nullable
as GeofenceVerdict,geofence: freezed == geofence ? _self.geofence : geofence // ignore: cast_nullable_to_non_nullable
as Geofence?,flags: null == flags ? _self.flags : flags // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [AttendancePunch].
extension AttendancePunchPatterns on AttendancePunch {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AttendancePunch value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AttendancePunch() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AttendancePunch value)  $default,){
final _that = this;
switch (_that) {
case _AttendancePunch():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AttendancePunch value)?  $default,){
final _that = this;
switch (_that) {
case _AttendancePunch() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  PunchKind kind,  DateTime serverAt,  DateTime? deviceAt,  double? lat,  double? lng,  double? accuracyM,  bool? isMocked,  String locationStatus,  int? distanceM,  GeofenceVerdict verdict,  Geofence? geofence,  List<String> flags)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AttendancePunch() when $default != null:
return $default(_that.id,_that.kind,_that.serverAt,_that.deviceAt,_that.lat,_that.lng,_that.accuracyM,_that.isMocked,_that.locationStatus,_that.distanceM,_that.verdict,_that.geofence,_that.flags);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  PunchKind kind,  DateTime serverAt,  DateTime? deviceAt,  double? lat,  double? lng,  double? accuracyM,  bool? isMocked,  String locationStatus,  int? distanceM,  GeofenceVerdict verdict,  Geofence? geofence,  List<String> flags)  $default,) {final _that = this;
switch (_that) {
case _AttendancePunch():
return $default(_that.id,_that.kind,_that.serverAt,_that.deviceAt,_that.lat,_that.lng,_that.accuracyM,_that.isMocked,_that.locationStatus,_that.distanceM,_that.verdict,_that.geofence,_that.flags);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  PunchKind kind,  DateTime serverAt,  DateTime? deviceAt,  double? lat,  double? lng,  double? accuracyM,  bool? isMocked,  String locationStatus,  int? distanceM,  GeofenceVerdict verdict,  Geofence? geofence,  List<String> flags)?  $default,) {final _that = this;
switch (_that) {
case _AttendancePunch() when $default != null:
return $default(_that.id,_that.kind,_that.serverAt,_that.deviceAt,_that.lat,_that.lng,_that.accuracyM,_that.isMocked,_that.locationStatus,_that.distanceM,_that.verdict,_that.geofence,_that.flags);case _:
  return null;

}
}

}

/// @nodoc


class _AttendancePunch implements AttendancePunch {
  const _AttendancePunch({required this.id, required this.kind, required this.serverAt, this.deviceAt, this.lat, this.lng, this.accuracyM, this.isMocked, required this.locationStatus, this.distanceM, required this.verdict, this.geofence,  List<String> flags = const <String>[]}): _flags = flags;
  

@override final  String id;
@override final  PunchKind kind;
/// When the server received it — the time that counts.
@override final  DateTime serverAt;
/// What the phone's clock said (evidence only).
@override final  DateTime? deviceAt;
@override final  double? lat;
@override final  double? lng;
@override final  double? accuracyM;
@override final  bool? isMocked;
/// `attendance_punches.location_status` (ok, denied, gps_off, …).
@override final  String locationStatus;
@override final  int? distanceM;
@override final  GeofenceVerdict verdict;
/// The geofence in force when the punch was judged.
@override final  Geofence? geofence;
 final  List<String> _flags;
@override@JsonKey() List<String> get flags {
  if (_flags is EqualUnmodifiableListView) return _flags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_flags);
}


/// Create a copy of AttendancePunch
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AttendancePunchCopyWith<_AttendancePunch> get copyWith => __$AttendancePunchCopyWithImpl<_AttendancePunch>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AttendancePunch&&(identical(other.id, id) || other.id == id)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.serverAt, serverAt) || other.serverAt == serverAt)&&(identical(other.deviceAt, deviceAt) || other.deviceAt == deviceAt)&&(identical(other.lat, lat) || other.lat == lat)&&(identical(other.lng, lng) || other.lng == lng)&&(identical(other.accuracyM, accuracyM) || other.accuracyM == accuracyM)&&(identical(other.isMocked, isMocked) || other.isMocked == isMocked)&&(identical(other.locationStatus, locationStatus) || other.locationStatus == locationStatus)&&(identical(other.distanceM, distanceM) || other.distanceM == distanceM)&&(identical(other.verdict, verdict) || other.verdict == verdict)&&(identical(other.geofence, geofence) || other.geofence == geofence)&&const DeepCollectionEquality().equals(other.flags, _flags));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,kind,serverAt,deviceAt,lat,lng,accuracyM,isMocked,locationStatus,distanceM,verdict,geofence,const DeepCollectionEquality().hash(_flags));
}

@override
String toString() {
    return 'AttendancePunch(id: $id, kind: $kind, serverAt: $serverAt, deviceAt: $deviceAt, lat: $lat, lng: $lng, accuracyM: $accuracyM, isMocked: $isMocked, locationStatus: $locationStatus, distanceM: $distanceM, verdict: $verdict, geofence: $geofence, flags: $flags)';
}


}

/// @nodoc
abstract mixin class _$AttendancePunchCopyWith<$Res> implements $AttendancePunchCopyWith<$Res> {
  factory _$AttendancePunchCopyWith(_AttendancePunch value, $Res Function(_AttendancePunch) _then) = __$AttendancePunchCopyWithImpl;
@override @useResult
$Res call({
 String id, PunchKind kind, DateTime serverAt, DateTime? deviceAt, double? lat, double? lng, double? accuracyM, bool? isMocked, String locationStatus, int? distanceM, GeofenceVerdict verdict, Geofence? geofence, List<String> flags
});




}
/// @nodoc
class __$AttendancePunchCopyWithImpl<$Res>
    implements _$AttendancePunchCopyWith<$Res> {
  __$AttendancePunchCopyWithImpl(this._self, this._then);

  final _AttendancePunch _self;
  final $Res Function(_AttendancePunch) _then;

/// Create a copy of AttendancePunch
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? kind = null,Object? serverAt = null,Object? deviceAt = freezed,Object? lat = freezed,Object? lng = freezed,Object? accuracyM = freezed,Object? isMocked = freezed,Object? locationStatus = null,Object? distanceM = freezed,Object? verdict = null,Object? geofence = freezed,Object? flags = null,}) {
  return _then(_AttendancePunch(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as PunchKind,serverAt: null == serverAt ? _self.serverAt : serverAt // ignore: cast_nullable_to_non_nullable
as DateTime,deviceAt: freezed == deviceAt ? _self.deviceAt : deviceAt // ignore: cast_nullable_to_non_nullable
as DateTime?,lat: freezed == lat ? _self.lat : lat // ignore: cast_nullable_to_non_nullable
as double?,lng: freezed == lng ? _self.lng : lng // ignore: cast_nullable_to_non_nullable
as double?,accuracyM: freezed == accuracyM ? _self.accuracyM : accuracyM // ignore: cast_nullable_to_non_nullable
as double?,isMocked: freezed == isMocked ? _self.isMocked : isMocked // ignore: cast_nullable_to_non_nullable
as bool?,locationStatus: null == locationStatus ? _self.locationStatus : locationStatus // ignore: cast_nullable_to_non_nullable
as String,distanceM: freezed == distanceM ? _self.distanceM : distanceM // ignore: cast_nullable_to_non_nullable
as int?,verdict: null == verdict ? _self.verdict : verdict // ignore: cast_nullable_to_non_nullable
as GeofenceVerdict,geofence: freezed == geofence ? _self.geofence : geofence // ignore: cast_nullable_to_non_nullable
as Geofence?,flags: null == flags ? _self._flags : flags // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc
mixin _$AttendanceEntry {

 String get id;/// The IST day the clock-in fell on (a shift past midnight stays there).
 IstDate get workDate; DateTime get inAt;/// Null while the person is on the clock.
 DateTime? get outAt;/// punch, auto (closed automatically) or manual; null while open.
 String? get outSource; List<String> get flags;/// none, pending, accepted or corrected.
 String get review; AttendancePunch? get inPunch; AttendancePunch? get outPunch;
/// Create a copy of AttendanceEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttendanceEntryCopyWith<AttendanceEntry> get copyWith => _$AttendanceEntryCopyWithImpl<AttendanceEntry>(this as AttendanceEntry, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AttendanceEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AttendanceEntry&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.workDate, _this.workDate) || other.workDate == _this.workDate)&&(identical(other.inAt, _this.inAt) || other.inAt == _this.inAt)&&(identical(other.outAt, _this.outAt) || other.outAt == _this.outAt)&&(identical(other.outSource, _this.outSource) || other.outSource == _this.outSource)&&const DeepCollectionEquality().equals(other.flags, _this.flags)&&(identical(other.review, _this.review) || other.review == _this.review)&&(identical(other.inPunch, _this.inPunch) || other.inPunch == _this.inPunch)&&(identical(other.outPunch, _this.outPunch) || other.outPunch == _this.outPunch));
}


@override
int get hashCode {
  final _this = this as AttendanceEntry;
  return Object.hash(runtimeType,_this.id,_this.workDate,_this.inAt,_this.outAt,_this.outSource,const DeepCollectionEquality().hash(_this.flags),_this.review,_this.inPunch,_this.outPunch);
}

@override
String toString() {
  final _this = this as AttendanceEntry;
  return 'AttendanceEntry(id: ${_this.id}, workDate: ${_this.workDate}, inAt: ${_this.inAt}, outAt: ${_this.outAt}, outSource: ${_this.outSource}, flags: ${_this.flags}, review: ${_this.review}, inPunch: ${_this.inPunch}, outPunch: ${_this.outPunch})';
}


}

/// @nodoc
abstract mixin class $AttendanceEntryCopyWith<$Res>  {
  factory $AttendanceEntryCopyWith(AttendanceEntry value, $Res Function(AttendanceEntry) _then) = _$AttendanceEntryCopyWithImpl;
@useResult
$Res call({
 String id, IstDate workDate, DateTime inAt, DateTime? outAt, String? outSource, List<String> flags, String review, AttendancePunch? inPunch, AttendancePunch? outPunch
});


$AttendancePunchCopyWith<$Res>? get inPunch;$AttendancePunchCopyWith<$Res>? get outPunch;

}
/// @nodoc
class _$AttendanceEntryCopyWithImpl<$Res>
    implements $AttendanceEntryCopyWith<$Res> {
  _$AttendanceEntryCopyWithImpl(this._self, this._then);

  final AttendanceEntry _self;
  final $Res Function(AttendanceEntry) _then;

/// Create a copy of AttendanceEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? workDate = null,Object? inAt = null,Object? outAt = freezed,Object? outSource = freezed,Object? flags = null,Object? review = null,Object? inPunch = freezed,Object? outPunch = freezed,}) {
  return _then(AttendanceEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,workDate: null == workDate ? _self.workDate : workDate // ignore: cast_nullable_to_non_nullable
as IstDate,inAt: null == inAt ? _self.inAt : inAt // ignore: cast_nullable_to_non_nullable
as DateTime,outAt: freezed == outAt ? _self.outAt : outAt // ignore: cast_nullable_to_non_nullable
as DateTime?,outSource: freezed == outSource ? _self.outSource : outSource // ignore: cast_nullable_to_non_nullable
as String?,flags: null == flags ? _self.flags : flags // ignore: cast_nullable_to_non_nullable
as List<String>,review: null == review ? _self.review : review // ignore: cast_nullable_to_non_nullable
as String,inPunch: freezed == inPunch ? _self.inPunch : inPunch // ignore: cast_nullable_to_non_nullable
as AttendancePunch?,outPunch: freezed == outPunch ? _self.outPunch : outPunch // ignore: cast_nullable_to_non_nullable
as AttendancePunch?,
  ));
}
/// Create a copy of AttendanceEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AttendancePunchCopyWith<$Res>? get inPunch {
    if (_self.inPunch == null) {
    return null;
  }

  return $AttendancePunchCopyWith<$Res>(_self.inPunch!, (value) {
    return _then(_self.copyWith(inPunch: value));
  });
}/// Create a copy of AttendanceEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AttendancePunchCopyWith<$Res>? get outPunch {
    if (_self.outPunch == null) {
    return null;
  }

  return $AttendancePunchCopyWith<$Res>(_self.outPunch!, (value) {
    return _then(_self.copyWith(outPunch: value));
  });
}
}


/// Adds pattern-matching-related methods to [AttendanceEntry].
extension AttendanceEntryPatterns on AttendanceEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AttendanceEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AttendanceEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AttendanceEntry value)  $default,){
final _that = this;
switch (_that) {
case _AttendanceEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AttendanceEntry value)?  $default,){
final _that = this;
switch (_that) {
case _AttendanceEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  IstDate workDate,  DateTime inAt,  DateTime? outAt,  String? outSource,  List<String> flags,  String review,  AttendancePunch? inPunch,  AttendancePunch? outPunch)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AttendanceEntry() when $default != null:
return $default(_that.id,_that.workDate,_that.inAt,_that.outAt,_that.outSource,_that.flags,_that.review,_that.inPunch,_that.outPunch);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  IstDate workDate,  DateTime inAt,  DateTime? outAt,  String? outSource,  List<String> flags,  String review,  AttendancePunch? inPunch,  AttendancePunch? outPunch)  $default,) {final _that = this;
switch (_that) {
case _AttendanceEntry():
return $default(_that.id,_that.workDate,_that.inAt,_that.outAt,_that.outSource,_that.flags,_that.review,_that.inPunch,_that.outPunch);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  IstDate workDate,  DateTime inAt,  DateTime? outAt,  String? outSource,  List<String> flags,  String review,  AttendancePunch? inPunch,  AttendancePunch? outPunch)?  $default,) {final _that = this;
switch (_that) {
case _AttendanceEntry() when $default != null:
return $default(_that.id,_that.workDate,_that.inAt,_that.outAt,_that.outSource,_that.flags,_that.review,_that.inPunch,_that.outPunch);case _:
  return null;

}
}

}

/// @nodoc


class _AttendanceEntry extends AttendanceEntry {
  const _AttendanceEntry({required this.id, required this.workDate, required this.inAt, this.outAt, this.outSource,  List<String> flags = const <String>[], this.review = 'none', this.inPunch, this.outPunch}): _flags = flags,super._();
  

@override final  String id;
/// The IST day the clock-in fell on (a shift past midnight stays there).
@override final  IstDate workDate;
@override final  DateTime inAt;
/// Null while the person is on the clock.
@override final  DateTime? outAt;
/// punch, auto (closed automatically) or manual; null while open.
@override final  String? outSource;
 final  List<String> _flags;
@override@JsonKey() List<String> get flags {
  if (_flags is EqualUnmodifiableListView) return _flags;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_flags);
}

/// none, pending, accepted or corrected.
@override@JsonKey() final  String review;
@override final  AttendancePunch? inPunch;
@override final  AttendancePunch? outPunch;

/// Create a copy of AttendanceEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AttendanceEntryCopyWith<_AttendanceEntry> get copyWith => __$AttendanceEntryCopyWithImpl<_AttendanceEntry>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AttendanceEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.workDate, workDate) || other.workDate == workDate)&&(identical(other.inAt, inAt) || other.inAt == inAt)&&(identical(other.outAt, outAt) || other.outAt == outAt)&&(identical(other.outSource, outSource) || other.outSource == outSource)&&const DeepCollectionEquality().equals(other.flags, _flags)&&(identical(other.review, review) || other.review == review)&&(identical(other.inPunch, inPunch) || other.inPunch == inPunch)&&(identical(other.outPunch, outPunch) || other.outPunch == outPunch));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,workDate,inAt,outAt,outSource,const DeepCollectionEquality().hash(_flags),review,inPunch,outPunch);
}

@override
String toString() {
    return 'AttendanceEntry(id: $id, workDate: $workDate, inAt: $inAt, outAt: $outAt, outSource: $outSource, flags: $flags, review: $review, inPunch: $inPunch, outPunch: $outPunch)';
}


}

/// @nodoc
abstract mixin class _$AttendanceEntryCopyWith<$Res> implements $AttendanceEntryCopyWith<$Res> {
  factory _$AttendanceEntryCopyWith(_AttendanceEntry value, $Res Function(_AttendanceEntry) _then) = __$AttendanceEntryCopyWithImpl;
@override @useResult
$Res call({
 String id, IstDate workDate, DateTime inAt, DateTime? outAt, String? outSource, List<String> flags, String review, AttendancePunch? inPunch, AttendancePunch? outPunch
});


@override $AttendancePunchCopyWith<$Res>? get inPunch;@override $AttendancePunchCopyWith<$Res>? get outPunch;

}
/// @nodoc
class __$AttendanceEntryCopyWithImpl<$Res>
    implements _$AttendanceEntryCopyWith<$Res> {
  __$AttendanceEntryCopyWithImpl(this._self, this._then);

  final _AttendanceEntry _self;
  final $Res Function(_AttendanceEntry) _then;

/// Create a copy of AttendanceEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? workDate = null,Object? inAt = null,Object? outAt = freezed,Object? outSource = freezed,Object? flags = null,Object? review = null,Object? inPunch = freezed,Object? outPunch = freezed,}) {
  return _then(_AttendanceEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,workDate: null == workDate ? _self.workDate : workDate // ignore: cast_nullable_to_non_nullable
as IstDate,inAt: null == inAt ? _self.inAt : inAt // ignore: cast_nullable_to_non_nullable
as DateTime,outAt: freezed == outAt ? _self.outAt : outAt // ignore: cast_nullable_to_non_nullable
as DateTime?,outSource: freezed == outSource ? _self.outSource : outSource // ignore: cast_nullable_to_non_nullable
as String?,flags: null == flags ? _self._flags : flags // ignore: cast_nullable_to_non_nullable
as List<String>,review: null == review ? _self.review : review // ignore: cast_nullable_to_non_nullable
as String,inPunch: freezed == inPunch ? _self.inPunch : inPunch // ignore: cast_nullable_to_non_nullable
as AttendancePunch?,outPunch: freezed == outPunch ? _self.outPunch : outPunch // ignore: cast_nullable_to_non_nullable
as AttendancePunch?,
  ));
}

/// Create a copy of AttendanceEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AttendancePunchCopyWith<$Res>? get inPunch {
    if (_self.inPunch == null) {
    return null;
  }

  return $AttendancePunchCopyWith<$Res>(_self.inPunch!, (value) {
    return _then(_self.copyWith(inPunch: value));
  });
}/// Create a copy of AttendanceEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AttendancePunchCopyWith<$Res>? get outPunch {
    if (_self.outPunch == null) {
    return null;
  }

  return $AttendancePunchCopyWith<$Res>(_self.outPunch!, (value) {
    return _then(_self.copyWith(outPunch: value));
  });
}
}

// dart format on
