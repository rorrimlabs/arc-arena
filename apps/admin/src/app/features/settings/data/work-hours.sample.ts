import { AppError } from '../../../core/auth/auth-api';
import {
  WORK_HOURS_MESSAGES,
  WorkHours,
  WorkHoursApi,
  parseWorkHours,
  workHoursJson,
} from './work-hours';

/** In-memory working-hours rules for tests; the arena starts on the server's defaults. */
export class SampleWorkHoursApi extends WorkHoursApi {
  saved: WorkHours | null = null;
  /** Every save, as the payload json the server would receive. */
  readonly writes: Record<string, unknown>[] = [];

  async load(): Promise<WorkHours | null> {
    return this.saved;
  }

  async save(_arenaId: string, w: WorkHours): Promise<void> {
    // As the server: half day below full day.
    if (w.halfDayPct >= w.fullDayPct) {
      throw new AppError('invalid_work_hours', WORK_HOURS_MESSAGES['invalid_work_hours']);
    }
    const json = workHoursJson(w);
    this.writes.push(json);
    this.saved = parseWorkHours(json);
  }
}
