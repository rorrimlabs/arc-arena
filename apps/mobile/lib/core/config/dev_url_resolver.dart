import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Resolves the local development backend URL for the active runtime environment.
///
/// On Android, an emulator needs `10.0.2.2`, while a physical device (with
/// `adb reverse tcp:<port> tcp:<port>`) needs `127.0.0.1`. In debug mode on
/// Android, this probes `127.0.0.1` first (via Socket.connect with a 300ms timeout)
/// so that physical devices connect seamlessly instead of hanging on the
/// emulator's unroutable `10.0.2.2`.
Future<String> resolveDevBackendUrl(
  String rawUrl, {
  TargetPlatform? platform,
  bool? isWeb,
  bool releaseBuild = kReleaseMode,
}) async {
  final effectiveIsWeb = isWeb ?? kIsWeb;
  final effectivePlatform = platform ?? defaultTargetPlatform;
  if (releaseBuild || effectiveIsWeb || effectivePlatform != TargetPlatform.android) {
    return rawUrl;
  }
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return rawUrl;
  if (uri.host != '127.0.0.1' && uri.host != 'localhost' && uri.host != '10.0.2.2') {
    return rawUrl;
  }
  final port = uri.port == 0 ? 54431 : uri.port;

  // 1. Probe 127.0.0.1 first (physical device via adb reverse, or emulator with reverse)
  try {
    final s = await Socket.connect(
      '127.0.0.1',
      port,
      timeout: const Duration(milliseconds: 300),
    );
    await s.close();
    return uri.replace(host: '127.0.0.1').toString();
  } catch (_) {}

  // 2. Probe 10.0.2.2 (Android emulator default routing)
  try {
    final s = await Socket.connect(
      '10.0.2.2',
      port,
      timeout: const Duration(milliseconds: 300),
    );
    await s.close();
    return uri.replace(host: '10.0.2.2').toString();
  } catch (_) {}

  return rawUrl;
}
