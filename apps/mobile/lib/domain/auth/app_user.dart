import 'package:arena_ops/domain/auth/permission.dart';
import 'package:meta/meta.dart';

/// A person who can sign in to run the floor (design: staff/owner with a PIN).
///
/// Deliberately carries no credential: the salted PIN hash never leaves the
/// data layer, so no screen, provider or log can read a PIN back out of a user
/// object. Setting a PIN goes through `UserRepository.upsert(newPin: ...)`.
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.perms,
    this.active = true,
  });

  final String id;
  final String name;
  final Set<Permission> perms;
  final bool active;

  bool can(Permission p) => perms.contains(p);

  /// Owner mode: full access (Money, Reports, Settings, pricing). Mirrors the
  /// design's `owner = perms.money || perms.reports`.
  bool get isOwner => can(Permission.money) || can(Permission.reports);

  String get roleLabel => isOwner ? 'Owner' : 'Staff';

  AppUser copyWith({
    String? name,
    Set<Permission>? perms,
    bool? active,
  }) =>
      AppUser(
        id: id,
        name: name ?? this.name,
        perms: perms ?? this.perms,
        active: active ?? this.active,
      );
}
