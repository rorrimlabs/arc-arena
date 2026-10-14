import 'package:arena_ops/domain/entities/activity.dart';
import 'package:arena_ops/domain/services/group_activity.dart';
import 'package:arena_ops/domain/value/enums.dart';
import 'package:flutter_test/flutter_test.dart';

Activity _type(String code, {bool pads = true, bool games = true, bool active = true}) =>
    Activity(
      id: code.toLowerCase(),
      code: code,
      name: code,
      usesControllers: pads,
      usesGames: games,
      durationModel: DurationModel.hourly,
      happyHourEligible: true,
      active: active,
    );

void main() {
  test('groups play on the console type the owner set up, whatever its code', () {
    expect(groupActivityCode([_type('XBOX'), _type('POOL', pads: false, games: false)]), 'XBOX');
  });

  test('the tapped station\'s type wins when it qualifies', () {
    final types = [_type('PS5'), _type('XBOX')];
    expect(groupActivityCode(types), 'PS5');
    expect(groupActivityCode(types, prefer: ['POOL', 'XBOX']), 'XBOX');
  });

  test('retired types and types without controllers or games do not qualify', () {
    expect(
      groupActivityCode([
        _type('PS5', active: false),
        _type('VR', pads: false),
        _type('LOUNGE', games: false),
      ]),
      isNull,
    );
  });
}
