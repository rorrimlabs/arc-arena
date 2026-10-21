import { HrProfile, PayStaff, resolvedProfile } from '../../pay-setup/data/pay-setup.models';

/**
 * Who is an employee (docs/STAFF.md): every staff member, and an owner only when their HR
 * profile says they work here (tracks attendance). Owning the venue never makes someone an
 * employee; the server applies the same rule (_staff_hr.tracks, attendance_days,
 * leave_balances). Without the Payroll permission HR profiles are not readable, so an owner
 * shows as not an employee there.
 */
export function isEmployee(s: PayStaff, profile: HrProfile | undefined): boolean {
  return s.role !== 'owner' || resolvedProfile(s, profile).tracksAttendance;
}
