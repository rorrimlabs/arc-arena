import 'package:flutter/material.dart';

/// Centralized navigation helper for ARQ.
///
/// Ensures secondary and detail screens are pushed onto the root navigator,
/// completely covering the shell's bottom navigation bar, while preserving
/// typed return values ([T]) and backstack restoration.
abstract final class AppNav {
  /// Pushes a [page] onto the root navigator as a full-screen view.
  static Future<T?> to<T>(BuildContext context, Widget page) {
    return Navigator.of(context, rootNavigator: true).push<T>(
      MaterialPageRoute<T>(builder: (_) => page),
    );
  }

  /// Replaces the current route on the root navigator with [page].
  static Future<T?> replace<T, TO>(
    BuildContext context,
    Widget page, {
    TO? result,
  }) {
    return Navigator.of(context, rootNavigator: true).pushReplacement<T, TO>(
      MaterialPageRoute<T>(builder: (_) => page),
      result: result,
    );
  }
}

/// Convenience extension on [BuildContext] for full-screen navigation.
extension AppNavContext on BuildContext {
  Future<T?> pushFullScreen<T>(Widget page) => AppNav.to<T>(this, page);

  Future<T?> pushReplacementFullScreen<T, TO>(Widget page, {TO? result}) =>
      AppNav.replace<T, TO>(this, page, result: result);
}
