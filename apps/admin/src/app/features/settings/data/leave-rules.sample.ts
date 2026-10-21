import { AppError } from '../../../core/auth/auth-api';
import {
  LEAVE_RULE_MESSAGES,
  LeaveRules,
  LeaveRulesApi,
  leaveRulesJson,
  parseLeaveRules,
} from './leave-rules';

/** In-memory leave rules for tests; the arena starts on the server's defaults. */
export class SampleLeaveRulesApi extends LeaveRulesApi {
  saved: LeaveRules | null = null;
  /** Every save, as the payload json the server would receive. */
  readonly writes: Record<string, unknown>[] = [];

  async load(): Promise<LeaveRules | null> {
    return this.saved;
  }

  async save(_arenaId: string, r: LeaveRules): Promise<void> {
    const json = leaveRulesJson(r);
    if (r.paidLeaveDays < 0 || r.paidLeaveDays > 366 || r.unplannedBackdateDays > 31) {
      throw new AppError('invalid_leave_rules', LEAVE_RULE_MESSAGES['invalid_leave_rules']);
    }
    this.writes.push(json);
    this.saved = parseLeaveRules(json);
  }
}
