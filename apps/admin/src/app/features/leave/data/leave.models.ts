import { PillTone } from '../../../shared/status-pill/status-pill';
import {
  formatCount,
  formatDay,
  formatRange,
  rangesOverlap,
} from '../../../shared/staff/staff-format';

/**
 * Leave (docs/STAFF.md §2 Leave, docs/STAFF_API.md › leave_requests): one paid allowance per
 * leave year (from the joining date), planned or unplanned requests, and the approver deciding
 * how many days are paid and how many are loss of pay (LOP). No leave types, no carry-forward.
 * The server counts the days and keeps the balances; this side only shows and decides.
 */
export type LeaveKind = 'planned' | 'unplanned';
export type HalfDay = 'none' | 'first_half' | 'second_half';
export type LeaveStatus = 'pending' | 'approved' | 'rejected' | 'cancelled' | 'cancel_pending';

export const LEAVE_STATUSES: readonly LeaveStatus[] = [
  'pending',
  'cancel_pending',
  'approved',
  'rejected',
  'cancelled',
];

/** A staff profile as the leave screens need it (names for requests and deciders). */
export interface LeaveStaff {
  readonly id: string;
  /** The login (auth user) of this profile: decided_by / created_by point at it. */
  readonly userId: string;
  readonly name: string;
  readonly role: 'owner' | 'staff';
  readonly active: boolean;
}

export interface LeaveRequest {
  readonly id: string;
  readonly staffId: string;
  readonly kind: LeaveKind;
  readonly fromDate: string;
  readonly toDate: string;
  readonly halfDay: HalfDay;
  /** Working days, counted by the server (week-offs and staff holidays skipped). */
  readonly days: number;
  /** Set on approval; null before. */
  readonly paidDays: number | null;
  readonly lopDays: number | null;
  readonly reason: string;
  readonly status: LeaveStatus;
  readonly decidedBy: string | null;
  readonly decidedAt: string | null;
  readonly decisionNote: string | null;
  readonly cancelReason: string | null;
  readonly createdBy: string;
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface LeaveAdjustment {
  readonly id: string;
  readonly staffId: string;
  /** The leave year it counts in (its first day). */
  readonly yearStart: string;
  /** Signed. */
  readonly days: number;
  readonly reason: string;
  readonly createdBy: string;
  readonly createdAt: string;
}

/** One row of leave_balances(): the person's current leave year. */
export interface LeaveBalance {
  readonly staffId: string;
  readonly staffName: string;
  readonly joinedOn: string;
  readonly yearStart: string;
  readonly yearEnd: string;
  readonly allowance: number;
  readonly adjustments: number;
  /** Paid days approved in this leave year. */
  readonly used: number;
  /** Days in requests still waiting. */
  readonly pending: number;
  /** allowance + adjustments − used. */
  readonly balance: number;
}

export interface LeaveData {
  readonly staff: readonly LeaveStaff[];
  readonly requests: readonly LeaveRequest[];
  readonly adjustments: readonly LeaveAdjustment[];
}

const STATUS_LABEL: Readonly<Record<LeaveStatus, { label: string; tone: PillTone }>> = {
  pending: { label: 'Waiting', tone: 'warning' },
  cancel_pending: { label: 'Cancel requested', tone: 'warning' },
  approved: { label: 'Approved', tone: 'success' },
  rejected: { label: 'Rejected', tone: 'danger' },
  cancelled: { label: 'Cancelled', tone: 'info' },
};

export function statusLabel(s: LeaveStatus): { label: string; tone: PillTone } {
  return STATUS_LABEL[s];
}

export function kindLabel(k: LeaveKind): string {
  return k === 'planned' ? 'Planned' : 'Unplanned';
}

export function halfDayLabel(h: HalfDay): string {
  return h === 'first_half' ? 'First half' : h === 'second_half' ? 'Second half' : '';
}

/** Waiting for a decision: a new request or a cancellation of an approved one. */
export function isOpen(r: LeaveRequest): boolean {
  return r.status === 'pending' || r.status === 'cancel_pending';
}

/** "5–7 Oct 2026", "9 Oct 2026 · first half". */
export function datesLabel(r: LeaveRequest): string {
  const half = halfDayLabel(r.halfDay);
  return formatRange(r.fromDate, r.toDate) + (half ? ` · ${half.toLowerCase()}` : '');
}

/** "2 paid · 1 LOP" once decided; "" before. */
export function splitLabel(r: LeaveRequest): string {
  if (r.paidDays === null || r.lopDays === null) return '';
  return `${formatCount(r.paidDays)} paid · ${formatCount(r.lopDays)} LOP`;
}

/**
 * The approve dialog's starting split: paid = min(days, the balance) (never below 0), in whole
 * half days, the rest LOP (docs/STAFF.md §2: the approver may change it).
 */
export function defaultPaidDays(days: number, balance: number | null): number {
  const available = Math.max(balance ?? 0, 0);
  return Math.floor(Math.min(days, available) * 2) / 2;
}

/** Paid days is 0…days in steps of 0.5 (the server's rule; refusal `invalid_paid_days`). */
export function paidDaysProblem(paid: number, days: number): string | null {
  if (!Number.isFinite(paid)) return 'Enter the paid days';
  if (paid < 0 || paid > days) return `Paid days must be from 0 to ${formatCount(days)}`;
  if (Math.round(paid * 2) !== paid * 2) return 'Use whole or half days (e.g. 1.5)';
  return null;
}

/** "2 paid · 1 LOP — LOP is deducted from salary" (the live line in the approve dialog). */
export function splitSentence(paid: number, days: number): string {
  const lop = Math.round((days - paid) * 2) / 2;
  const base = `${formatCount(paid)} paid · ${formatCount(lop)} LOP`;
  return lop > 0 ? `${base} — LOP is deducted from salary` : base;
}

/** leave.decide payload (docs/STAFF_API.md › Leave). */
export function decidePayload(
  r: LeaveRequest,
  approve: boolean,
  paidDays: number | null,
  note: string,
): Record<string, unknown> {
  const payload: Record<string, unknown> = { id: r.id, approve };
  // paid_days only applies to approving a new request (not to a cancellation).
  if (approve && r.status === 'pending' && paidDays !== null) payload['paid_days'] = paidDays;
  const n = note.trim();
  if (n) payload['note'] = n;
  return payload;
}

/** leave.adjust payload: signed days (halves allowed), reason required. */
export function adjustPayload(
  staffId: string,
  days: number,
  reason: string,
): Record<string, unknown> {
  return { staff_id: staffId, days, reason: reason.trim() };
}

/** What a manager records directly (leave.record): already decided, all paid or all LOP. */
export interface LeaveRecord {
  readonly id: string;
  readonly staffId: string;
  readonly fromDate: string;
  readonly toDate: string;
  readonly halfDay: HalfDay;
  readonly paid: boolean;
  readonly reason: string;
}

/** leave.record payload (docs/STAFF_API.md › Leave); an empty reason is left to the server. */
export function recordPayload(r: LeaveRecord): Record<string, unknown> {
  const payload: Record<string, unknown> = {
    id: r.id,
    staff_id: r.staffId,
    from_date: r.fromDate,
    to_date: r.toDate,
    half_day: r.fromDate === r.toDate ? r.halfDay : 'none',
    paid: r.paid,
  };
  const reason = r.reason.trim();
  if (reason) payload['reason'] = reason;
  return payload;
}

/** An adjustment's days as typed ("+1", "-0.5", "2"): signed, non-zero, whole or half days. */
export function parseAdjustDays(text: string): number | null {
  const t = text.trim().replace(/^\+/, '');
  if (!/^-?\d{1,3}(\.\d+)?$/.test(t)) return null;
  const n = Number(t);
  if (!Number.isFinite(n) || n === 0 || Math.round(n * 2) !== n * 2 || Math.abs(n) > 366)
    return null;
  return n;
}

/** Other people's approved or waiting requests sharing a day with `r` ("Also off then"). */
export function alsoOff(r: LeaveRequest, all: readonly LeaveRequest[]): LeaveRequest[] {
  return all
    .filter(
      (o) =>
        o.staffId !== r.staffId &&
        (o.status === 'approved' || o.status === 'pending' || o.status === 'cancel_pending') &&
        rangesOverlap(o.fromDate, o.toDate, r.fromDate, r.toDate),
    )
    .sort((a, b) => a.fromDate.localeCompare(b.fromDate));
}

/** A request has at least one day in first…last. */
export function rangesOverlapRequest(r: LeaveRequest, first: string, last: string): boolean {
  return rangesOverlap(r.fromDate, r.toDate, first, last);
}

/** The Requests tab: everything waiting, cancellation requests first, then oldest dates first. */
export function openRequests(all: readonly LeaveRequest[]): LeaveRequest[] {
  return all
    .filter(isOpen)
    .sort(
      (a, b) =>
        Number(b.status === 'cancel_pending') - Number(a.status === 'cancel_pending') ||
        a.fromDate.localeCompare(b.fromDate) ||
        a.createdAt.localeCompare(b.createdAt),
    );
}

export interface RequestFilter {
  readonly staffId: string | null;
  readonly status: LeaveStatus | null;
  /** Requests with at least one day in first…last (either may be empty). */
  readonly first: string | null;
  readonly last: string | null;
}

/** The All requests tab: newest dates first. */
export function filterRequests(all: readonly LeaveRequest[], f: RequestFilter): LeaveRequest[] {
  return all
    .filter(
      (r) =>
        (!f.staffId || r.staffId === f.staffId) &&
        (!f.status || r.status === f.status) &&
        (!f.first || r.toDate >= f.first) &&
        (!f.last || r.fromDate <= f.last),
    )
    .sort((a, b) => b.fromDate.localeCompare(a.fromDate) || b.createdAt.localeCompare(a.createdAt));
}

export function asStatus(v: string | null | undefined): LeaveStatus | null {
  return LEAVE_STATUSES.includes(v as LeaveStatus) ? (v as LeaveStatus) : null;
}

export interface HistoryLine {
  readonly at: string;
  readonly text: string;
  readonly note: string | null;
}

/** What happened to a request, from its row: asked, decided, cancellation asked. */
export function requestHistory(
  r: LeaveRequest,
  nameOf: (userId: string | null) => string,
): HistoryLine[] {
  const lines: HistoryLine[] = [
    { at: r.createdAt, text: `Asked by ${nameOf(r.createdBy)}`, note: r.reason || null },
  ];
  if (r.decidedAt) {
    const who = nameOf(r.decidedBy);
    const split = splitLabel(r);
    const text =
      r.status === 'rejected'
        ? 'Rejected'
        : r.status === 'cancelled'
          ? 'Cancellation approved'
          : `Approved${split ? ` · ${split}` : ''}`;
    lines.push({ at: r.decidedAt, text: `${text} by ${who}`, note: r.decisionNote });
  }
  if (r.status === 'cancel_pending') {
    lines.push({ at: r.updatedAt, text: 'Cancellation requested', note: r.cancelReason });
  } else if (r.status === 'cancelled' && !r.decidedAt) {
    lines.push({ at: r.updatedAt, text: 'Cancelled by the staff member', note: r.cancelReason });
  }
  return lines.sort((a, b) => a.at.localeCompare(b.at));
}

/** "Leave year 12 Mar 2026 – 11 Mar 2027". */
export function yearLabel(b: LeaveBalance): string {
  return formatRange(b.yearStart, b.yearEnd);
}

/** "4.5 left" / "1 over". */
export function balanceShort(b: LeaveBalance): string {
  return b.balance >= 0 ? `${formatCount(b.balance)} left` : `${formatCount(-b.balance)} over`;
}

/** "5 Oct" of a request's first day (list rows). */
export function firstDay(r: LeaveRequest): string {
  return formatDay(r.fromDate);
}

/** Refusals of the leave ops (docs/STAFF_API.md › Leave), in plain words. */
export const LEAVE_MESSAGES: Readonly<Record<string, string>> = {
  forbidden: 'You need the Approve leave permission for that',
  not_found: 'That request or person is no longer there. Refresh',
  own_record: 'You can’t decide your own leave. Another approver (or the owner) must',
  invalid_state: 'This request was already decided or cancelled. Refresh to see where it stands',
  invalid_paid_days: 'Paid days must be from 0 to the request’s days, in whole or half days',
  period_finalised:
    'Pay for these dates is already finalised, so the leave can’t change. Add an adjustment in the next pay run instead',
  reason_required: 'Give a reason',
  invalid_payload: 'Check the values and try again',
  invalid_dates: 'Those dates aren’t valid',
  half_day_not_allowed: 'Half-day leave is turned off in Settings › Leave rules',
  planned_in_past: 'Planned leave must start today or later',
  too_far_back: 'Unplanned leave can’t go back that far (see Settings › Leave rules)',
  leave_overlap: 'This person already has leave on some of those days',
  no_working_days: 'Those dates have no working days: they are days off or holidays for this person',
  reason_too_long: 'Keep the note under 500 characters',
};
