// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Customer _$CustomerFromJson(Map<String, dynamic> json) => _Customer(
  id: json['id'] as String,
  name: json['name'] as String,
  phone: json['phone'] as String?,
  notes: json['notes'] as String?,
  lastVisitAt: json['lastVisitAt'] == null
      ? null
      : DateTime.parse(json['lastVisitAt'] as String),
  isGuest: json['isGuest'] as bool? ?? false,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$CustomerToJson(_Customer instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'phone': instance.phone,
  'notes': instance.notes,
  'lastVisitAt': instance.lastVisitAt?.toIso8601String(),
  'isGuest': instance.isGuest,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
};
