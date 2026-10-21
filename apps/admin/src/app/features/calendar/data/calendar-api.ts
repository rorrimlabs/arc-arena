import { Service, inject } from '@angular/core';
import { dbError } from '../../../core/supabase/db-error';
import { Supabase } from '../../../core/supabase/supabase';
import { AttendanceDay, toAttendanceDay } from './calendar.models';

/**
 * Reads person-days through the client RPC `attendance_days`, which returns a jsonb array of
 * rows (`entries` is a count, not the entries themselves). Every tracked staff member:
 * needs `attendance_review` or `payroll`; at most 62 days; it closes forgotten clock-ins
 * first). Tests provide SampleCalendarApi.
 */
@Service({ factory: () => new SupabaseCalendarApi() })
export abstract class CalendarApi {
  /** Every tracked staff member's days, or one person's (`staffId`). */
  abstract days(
    arenaId: string,
    first: string,
    last: string,
    staffId?: string | null,
  ): Promise<AttendanceDay[]>;
}

class SupabaseCalendarApi extends CalendarApi {
  private readonly supabase = inject(Supabase);

  async days(
    arenaId: string,
    first: string,
    last: string,
    staffId: string | null = null,
  ): Promise<AttendanceDay[]> {
    const client = await this.supabase.client();
    const { data, error } = await client.rpc('attendance_days', {
      p_arena: arenaId,
      p_from: first,
      p_to: last,
      ...(staffId ? { p_staff: staffId } : {}),
    });
    if (error) throw dbError(error);
    return ((data as Record<string, unknown>[] | null) ?? []).map(toAttendanceDay);
  }
}
