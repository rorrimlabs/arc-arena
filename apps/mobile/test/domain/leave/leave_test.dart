import 'package:arena_ops/core/time/ist.dart';
import 'package:arena_ops/domain/attendance/attendance_day.dart';
import 'package:arena_ops/domain/leave/leave.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a leave request row from the server', () {
    final r = LeaveRequest.fromJson({
      'id': 'r1',
      'kind': 'unplanned',
      'from_date': '2026-10-19',
      'to_date': '2026-10-20',
      'half_day': 'none',
      'days': 2.0,
      'paid_days': 1.0,
      'lop_days': 1.0,
      'reason': 'fever',
      'status': 'approved',
      'decision_note': 'get well',
      'decided_at': '2026-10-18T05:00:00+00:00',
      'created_at': '2026-10-18T04:00:00+00:00',
    });
    expect(r.kind, LeaveKind.unplanned);
    expect(r.from, const IstDate(2026, 10, 19));
    expect([r.days, r.paidDays, r.lopDays], [2, 1, 1]);
    expect(r.status, LeaveStatus.approved);
    expect(r.cancellable, isTrue, reason: 'approved leave can be asked to be cancelled');
    expect(LeaveStatus.fromWire('cancel_pending'), LeaveStatus.cancelPending);
  });

  test('the balance and what is left after waiting requests', () {
    final b = LeaveBalance.fromJson({
      'joined_on': '2025-06-01',
      'year_start': '2026-06-01',
      'year_end': '2027-05-31',
      'allowance': 12,
      'adjustments': -1,
      'used': 4,
      'pending': 2,
      'balance': 7,
    });
    expect(b.available, 5);
    expect(b.yearEnd, const IstDate(2027, 5, 31));
  });

  test('a request command is the op payload', () {
    const cmd = LeaveRequestCommand(
      id: 'c1',
      kind: LeaveKind.planned,
      from: IstDate(2026, 10, 21),
      to: IstDate(2026, 10, 21),
      halfDay: HalfDay.secondHalf,
      reason: '  exam  ',
    );
    expect(cmd.toPayload(), {
      'id': 'c1',
      'kind': 'planned',
      'from_date': '2026-10-21',
      'to_date': '2026-10-21',
      'half_day': 'second_half',
      'reason': 'exam',
    });
  });

  test('an attendance day from attendance_days', () {
    final d = AttendanceDay.fromJson({
      'staff_id': 's',
      'work_date': '2026-10-15',
      'status': 'half_leave',
      'sched_min': 480,
      'worked_min': 240,
      'extra_min': 0,
      'late': false,
      'early': true,
      'leave_paid': 0.5,
      'leave_lop': 0,
      'holiday_name': null,
      'flags': ['outside_in'],
      'open': false,
      'entries': 1,
    });
    expect(d.status, DayStatus.halfLeave);
    expect(d.workedMin, 240);
    expect(d.leavePaid, 0.5);
    expect(d.flags, ['outside_in']);
    expect(DayStatus.fromWire('something new'), DayStatus.upcoming);
  });
}
