import {
  AttendanceDraft,
  DEFAULT_ATTENDANCE_RULES,
  attendanceJson,
  draftProblems,
  fromDraft,
  parseAttendanceRules,
  sameDraft,
  toDraft,
} from './attendance-rules';

const located: AttendanceDraft = {
  lat: '12.9352',
  lng: '77.6245',
  radius: '150',
  outsideRule: 'block',
  minAccuracy: '30',
  mockRule: 'flag',
  maxOpenHours: '12',
};

describe('attendance rules', () => {
  it('reads the server defaults when nothing is saved, and a saved row as saved', () => {
    expect(parseAttendanceRules(null)).toEqual(DEFAULT_ATTENDANCE_RULES);
    expect(
      parseAttendanceRules({
        geofence: { lat: 12.9352, lng: 77.6245, radius_m: 150 },
        outside_rule: 'allow',
        min_accuracy_m: 30,
        mock_rule: 'flag',
        max_open_hours: 12,
      }),
    ).toEqual({
      geofence: { lat: 12.9352, lng: 77.6245, radiusM: 150 },
      outsideRule: 'allow',
      minAccuracyM: 30,
      mockRule: 'flag',
      maxOpenHours: 12,
    });
  });

  it('maps a draft to exactly the five keys the server requires, lat/lng to 6 decimals', () => {
    const rules = fromDraft({ ...located, lat: '12.93521234', lng: '77.62459876' })!;
    expect(attendanceJson(rules)).toEqual({
      geofence: { lat: 12.935212, lng: 77.624599, radius_m: 150 },
      outside_rule: 'block',
      min_accuracy_m: 30,
      mock_rule: 'flag',
      max_open_hours: 12,
    });
    expect(Object.keys(attendanceJson(rules)).sort()).toEqual([
      'geofence',
      'max_open_hours',
      'min_accuracy_m',
      'mock_rule',
      'outside_rule',
    ]);
  });

  it('no location saves geofence null (the radius is not sent)', () => {
    const json = attendanceJson(fromDraft({ ...located, lat: '', lng: '', outsideRule: 'flag' })!);
    expect(json['geofence']).toBeNull();
    expect(json['outside_rule']).toBe('flag');
  });

  it('round-trips the saved rules through the draft', () => {
    const rules = parseAttendanceRules(attendanceJson(fromDraft(located)!));
    expect(sameDraft(toDraft(rules), located)).toBe(true);
    expect(sameDraft(toDraft(rules), { ...located, radius: '151' })).toBe(false);
    // Without a location the radius is not saved, so it does not count as a change.
    const none = toDraft(DEFAULT_ATTENDANCE_RULES);
    expect(sameDraft(none, { ...none, radius: '300' })).toBe(true);
  });

  it('block needs the arena location', () => {
    const problems = draftProblems({ ...located, lat: '', lng: '' });
    expect(problems.outsideRule).toBe(
      'Block needs the arena location: set it on the map, or choose Flag or Allow',
    );
    expect(fromDraft({ ...located, lat: '', lng: '' })).toBeNull();
    expect(draftProblems(located)).toEqual({});
  });

  it('mirrors the server limits', () => {
    expect(draftProblems({ ...located, lat: '12.9', lng: '' }).location).toBe(
      'Enter both latitude and longitude, or clear the location',
    );
    expect(draftProblems({ ...located, lat: '91' }).location).toBe(
      'Latitude must be between -90 and 90',
    );
    expect(draftProblems({ ...located, lng: '-181' }).location).toBe(
      'Longitude must be between -180 and 180',
    );
    expect(draftProblems({ ...located, radius: '19' }).radius).toBe(
      'Radius must be a whole number of metres from 20 to 5000',
    );
    expect(draftProblems({ ...located, radius: '5000' }).radius).toBeUndefined();
    expect(draftProblems({ ...located, radius: '20.5' }).radius).toBeDefined();
    expect(draftProblems({ ...located, minAccuracy: '4' }).minAccuracy).toBe(
      'Minimum accuracy must be a whole number of metres from 5 to 500',
    );
    expect(draftProblems({ ...located, minAccuracy: '500' }).minAccuracy).toBeUndefined();
    expect(draftProblems({ ...located, maxOpenHours: '25' }).maxOpenHours).toBe(
      'Auto-close must be a whole number of hours from 4 to 24',
    );
    expect(draftProblems({ ...located, maxOpenHours: '' }).maxOpenHours).toBeDefined();
    expect(draftProblems({ ...located, maxOpenHours: '4' }).maxOpenHours).toBeUndefined();
  });
});
