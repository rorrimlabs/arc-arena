import { AppError } from '../../../core/auth/auth-api';
import {
  ATTENDANCE_RULE_MESSAGES,
  AttendanceRules,
  AttendanceRulesApi,
  attendanceJson,
  parseAttendanceRules,
} from './attendance-rules';

/** In-memory attendance rules for tests; the arena starts on the server's defaults. */
export class SampleAttendanceRulesApi extends AttendanceRulesApi {
  saved: AttendanceRules | null = null;
  /** Every save, as the payload json the server would receive. */
  readonly writes: Record<string, unknown>[] = [];

  async load(): Promise<AttendanceRules | null> {
    return this.saved;
  }

  async save(_arenaId: string, r: AttendanceRules): Promise<void> {
    // As the server: block needs a geofence.
    if (r.outsideRule === 'block' && !r.geofence) {
      throw new AppError(
        'invalid_attendance_settings',
        ATTENDANCE_RULE_MESSAGES['invalid_attendance_settings'],
      );
    }
    const json = attendanceJson(r);
    this.writes.push(json);
    this.saved = parseAttendanceRules(json);
  }
}
