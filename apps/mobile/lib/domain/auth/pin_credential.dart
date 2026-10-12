/// How a staff PIN is stored.
///
/// The counter device is shared and sits on a public counter, and its database
/// file can be read by anyone who gets hold of the tablet — so the PIN is never
/// stored in a form that can be read back. Each account gets its own random
/// salt (so two staff who pick 1234 do not share a hash, and no precomputed
/// table helps) and the PIN is stretched with PBKDF2-HMAC-SHA256.
///
/// A 4-digit PIN only has 10 000 possibilities, so stretching cannot make an
/// offline guess impossible — it makes it slow, and the failed-attempt lockout
/// in `UserRepository.verify` is what stops guessing *through the app*.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

@immutable
class PinCredential {
  const PinCredential({
    required this.salt,
    required this.hash,
    required this.iterations,
  });

  /// Base64 random salt, unique per account.
  final String salt;

  /// Base64 PBKDF2 output.
  final String hash;

  /// Stretching cost, stored per credential so it can be raised later without
  /// invalidating PINs set by an older build.
  final int iterations;

  /// Cost chosen so a sign-in stays responsive on a counter tablet while a
  /// full sweep of all 10 000 four-digit PINs still costs real time.
  static const defaultIterations = 60000;

  static const _saltBytes = 16;
  static const _keyBytes = 32;

  /// Derives a credential for [pin] with a fresh random salt.
  static PinCredential create(String pin, {int? iterations}) {
    final rounds = iterations ?? defaultIterations;
    final salt = _randomSalt();
    return PinCredential(
      salt: salt,
      hash: _derive(pin, salt, rounds),
      iterations: rounds,
    );
  }

  /// True when [pin] matches this credential.
  ///
  /// The comparison is constant-time: a length- or byte-dependent early exit
  /// leaks how much of a guess was right.
  bool matches(String pin) {
    final candidate = _derive(pin, salt, iterations);
    return _constantTimeEquals(candidate, hash);
  }

  static String _randomSalt() {
    final rng = Random.secure();
    final bytes =
        Uint8List.fromList([for (var i = 0; i < _saltBytes; i++) rng.nextInt(256)]);
    return base64Encode(bytes);
  }

  static String _derive(String pin, String salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    final saltBytes = base64Decode(salt);
    final out = Uint8List(_keyBytes);
    var offset = 0;
    var block = 1;
    while (offset < _keyBytes) {
      // U1 = PRF(password, salt || INT_32_BE(block))
      final first = hmac.convert(<int>[
        ...saltBytes,
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ]);
      var u = Uint8List.fromList(first.bytes);
      final acc = Uint8List.fromList(first.bytes);
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < acc.length; j++) {
          acc[j] ^= u[j];
        }
      }
      final take = min(acc.length, _keyBytes - offset);
      out.setRange(offset, offset + take, acc);
      offset += take;
      block++;
    }
    return base64Encode(out);
  }

  static bool _constantTimeEquals(String a, String b) {
    final x = utf8.encode(a);
    final y = utf8.encode(b);
    var diff = x.length ^ y.length;
    final len = min(x.length, y.length);
    for (var i = 0; i < len; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }
}
