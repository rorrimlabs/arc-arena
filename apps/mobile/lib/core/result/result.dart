/// A tiny Result type for operations that can fail with a user-facing reason.
///
/// Every failure carries both **what happened** and **what the staff should do
/// next** (spec §41), so the UI never has to invent error copy.
library;

import 'package:meta/meta.dart';

@immutable
class Failure {
  const Failure({required this.message, this.fix, this.code});

  /// What happened, in plain language. e.g. "VOID was just taken."
  final String message;

  /// What the staff should do next. e.g. "Pick another station."
  final String? fix;

  /// Stable machine code for tests / logging. e.g. `resource_busy`.
  final String? code;

  /// One-line display combining message and fix.
  String get display => fix == null ? message : '$message $fix';

  @override
  bool operator ==(Object other) =>
      other is Failure &&
      other.message == message &&
      other.fix == fix &&
      other.code == code;

  @override
  int get hashCode => Object.hash(message, fix, code);

  @override
  String toString() => 'Failure(${code ?? '-'}: $display)';
}

@immutable
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  Failure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final failure) => failure,
      };

  R fold<R>(R Function(T value) ok, R Function(Failure failure) err) =>
      switch (this) {
        Ok<T>(:final value) => ok(value),
        Err<T>(:final failure) => err(failure),
      };
}

@immutable
final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

@immutable
final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;

  @override
  bool operator ==(Object other) => other is Err<T> && other.failure == failure;
  @override
  int get hashCode => failure.hashCode;
}
