import 'dart:convert';

import 'package:drift/drift.dart';

/// Stores a `List<String>` (aliases, platforms, button tokens, activity codes)
/// as a JSON array in a TEXT column.
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List).map((e) => e as String).toList();

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

/// Stores a `List<int>` (a pricing rule's ISO weekdays) as a JSON array in a
/// TEXT column.
class IntListConverter extends TypeConverter<List<int>, String> {
  const IntListConverter();

  @override
  List<int> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List).map((e) => (e as num).toInt()).toList();

  @override
  String toSql(List<int> value) => jsonEncode(value);
}

/// Stores a JSON map (the immutable pricing snapshot) as a TEXT column.
class JsonMapConverter extends TypeConverter<Map<String, dynamic>, String> {
  const JsonMapConverter();

  @override
  Map<String, dynamic> fromSql(String fromDb) =>
      jsonDecode(fromDb) as Map<String, dynamic>;

  @override
  String toSql(Map<String, dynamic> value) => jsonEncode(value);
}
