set local check_function_bodies = off;

create table "public"."leave_adjustments" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "staff_id"   uuid                     not null,
  "year_start" date                     not null,
  "days"       numeric(4,1)             not null,
  "reason"     text                     not null,
  "created_by" uuid                     not null,
  "created_at" timestamp with time zone not null default now(),
  constraint "leave_adjustments_days_check" check ((days <> (0)::numeric)),
  constraint "leave_adjustments_pkey" primary key (id),
  constraint "leave_adjustments_reason_check" check ((btrim(reason) <> ''::text))
);

alter table "public"."leave_adjustments"
  enable row level security;

create table "public"."leave_requests" (
  "id"            uuid                     not null,
  "arena_id"      uuid                     not null,
  "staff_id"      uuid                     not null,
  "kind"          text                     not null,
  "from_date"     date                     not null,
  "to_date"       date                     not null,
  "half_day"      text                     not null default 'none'::text,
  "days"          numeric(4,1)             not null,
  "paid_days"     numeric(4,1),
  "lop_days"      numeric(4,1),
  "day_split"     jsonb,
  "reason"        text                     not null,
  "status"        text                     not null default 'pending'::text,
  "decided_by"    uuid,
  "decided_at"    timestamp with time zone,
  "decision_note" text,
  "cancel_reason" text,
  "created_by"    uuid                     not null,
  "created_at"    timestamp with time zone not null default now(),
  "updated_at"    timestamp with time zone not null default now(),
  constraint "leave_requests_days_check" check ((days > (0)::numeric)),
  constraint "leave_requests_half_day_check"
    check
    (((half_day = ANY (ARRAY['none'::text, 'first_half'::text, 'second_half'::text])) AND ((half_day
    = 'none'::text) OR (from_date = to_date)))),
  constraint "leave_requests_kind_check"
    check ((kind = ANY (ARRAY['planned'::text, 'unplanned'::text]))),
  constraint "leave_requests_pkey" primary key (id),
  constraint "leave_requests_range_check" check ((to_date >= from_date)),
  constraint "leave_requests_reason_check" check ((btrim(reason) <> ''::text)),
  constraint "leave_requests_split_check" check (
CASE
    WHEN (status = ANY (ARRAY['approved'::text, 'cancel_pending'::text])) THEN
      ((paid_days >= (0)::numeric) AND (lop_days >= (0)::numeric) AND ((paid_days + lop_days) =
      days) AND (day_split IS NOT NULL))
    ELSE ((paid_days IS NULL) AND (lop_days IS NULL))
END),
  constraint "leave_requests_status_check"
    check
    ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text,
    'cancel_pending'::text])))
);

alter table "public"."leave_requests"
  enable row level security;

create table "public"."pay_policies" (
  "id"             uuid                     not null,
  "arena_id"       uuid                     not null,
  "effective_from" date                     not null,
  "policy"         jsonb                    not null,
  "created_by"     uuid                     not null,
  "created_at"     timestamp with time zone not null default now(),
  constraint "pay_policies_arena_id_effective_from_key" unique (arena_id, effective_from),
  constraint "pay_policies_pkey" primary key (id)
);

alter table "public"."pay_policies"
  enable row level security;

create table "public"."salary_adjustments" (
  "id"           uuid                     not null,
  "arena_id"     uuid                     not null,
  "run_id"       uuid                     not null,
  "staff_id"     uuid                     not null,
  "kind"         text                     not null,
  "amount_paise" bigint                   not null,
  "note"         text                     not null,
  "reverses_id"  uuid,
  "created_by"   uuid                     not null,
  "created_at"   timestamp with time zone not null default now(),
  constraint "salary_adjustments_kind_check"
    check
    ((kind = ANY (ARRAY['bonus'::text, 'advance'::text, 'deduction'::text, 'reversal'::text]))),
  constraint "salary_adjustments_note_check" check ((btrim(note) <> ''::text)),
  constraint "salary_adjustments_pkey" primary key (id),
  constraint "salary_adjustments_reverses_id_key" unique (reverses_id),
  constraint "salary_adjustments_sign_check"
    check
    (((amount_paise <> 0) AND ((kind <> 'bonus'::text) OR (amount_paise > 0)) AND ((kind <> ALL
    (ARRAY['advance'::text, 'deduction'::text])) OR (amount_paise < 0)) AND
    ((kind = 'reversal'::text) = (reverses_id IS NOT NULL))))
);

alter table "public"."salary_adjustments"
  enable row level security;

create table "public"."salary_deduction_decisions" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "run_id"     uuid                     not null,
  "staff_id"   uuid                     not null,
  "code"       text                     not null,
  "applied"    boolean                  not null,
  "note"       text,
  "decided_by" uuid                     not null,
  "decided_at" timestamp with time zone not null default now(),
  constraint "salary_deduction_decisions_code_check"
    check ((code = ANY (ARRAY['absent'::text, 'lop_leave'::text, 'half_day'::text, 'late'::text]))),
  constraint "salary_deduction_decisions_pkey" primary key (id),
  constraint "salary_deduction_decisions_run_id_staff_id_code_key" unique (run_id, staff_id, code)
);

alter table "public"."salary_deduction_decisions"
  enable row level security;

create table "public"."salary_run_lines" (
  "id"                uuid    not null default gen_random_uuid(),
  "arena_id"          uuid    not null,
  "run_id"            uuid    not null,
  "staff_id"          uuid    not null,
  "staff_name"        text    not null,
  "pay_type"          text    not null,
  "rates"             jsonb   not null,
  "day_counts"        jsonb   not null,
  "worked_min"        integer not null,
  "regular_min"       integer not null,
  "extra_min"         integer not null,
  "base_paise"        bigint  not null,
  "extra_paise"       bigint  not null,
  "gross_paise"       bigint  not null,
  "deductions"        jsonb   not null,
  "deductions_paise"  bigint  not null,
  "adjustments_paise" bigint  not null,
  "net_paise"         bigint  not null,
  "days"              jsonb   not null,
  "notes"             jsonb   not null default '[]'::jsonb,
  constraint "salary_run_lines_pkey" primary key (id),
  constraint "salary_run_lines_run_id_staff_id_key" unique (run_id, staff_id)
);

alter table "public"."salary_run_lines"
  enable row level security;

create table "public"."salary_runs" (
  "id"                uuid                     not null,
  "arena_id"          uuid                     not null,
  "period_start"      date                     not null,
  "period_end"        date                     not null,
  "status"            text                     not null default 'draft'::text,
  "rules_snapshot"    jsonb                    not null,
  "computed_at"       timestamp with time zone not null,
  "staff_count"       integer                  not null default 0,
  "gross_paise"       bigint                   not null default 0,
  "deductions_paise"  bigint                   not null default 0,
  "adjustments_paise" bigint                   not null default 0,
  "net_paise"         bigint                   not null default 0,
  "created_by"        uuid                     not null,
  "created_at"        timestamp with time zone not null default now(),
  "finalised_by"      uuid,
  "finalised_at"      timestamp with time zone,
  "updated_at"        timestamp with time zone not null default now(),
  constraint "salary_runs_final_check" check (((status = 'finalised'::text) = (finalised_at IS
    NOT NULL))),
  constraint "salary_runs_period_check"
    check (((period_end >= period_start) AND ((period_end - period_start) < 62))),
  constraint "salary_runs_pkey" primary key (id),
  constraint "salary_runs_status_check"
    check ((status = ANY (ARRAY['draft'::text, 'finalised'::text, 'discarded'::text])))
);

alter table "public"."salary_runs"
  enable row level security;

create table "public"."shifts" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "name"       text                     not null,
  "start_min"  integer                  not null,
  "end_min"    integer                  not null,
  "days"       smallint[]               not null,
  "break_min"  integer                  not null default 0,
  "active"     boolean                  not null default true,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  constraint "shifts_break_check" check (((break_min >= 0) AND (break_min < 720))),
  constraint "shifts_days_check"
    check
    (((days <@ ARRAY[(1)::smallint, (2)::smallint, (3)::smallint, (4)::smallint, (5)::smallint,
    (6)::smallint, (7)::smallint]) AND (cardinality(days) > 0))),
  constraint "shifts_minutes_check"
    check
    (((start_min >= 0) AND (start_min <= 1439) AND (end_min >= 0) AND (end_min <= 1439) AND (end_min
    <> start_min))),
  constraint "shifts_name_check" check ((btrim(name) <> ''::text)),
  constraint "shifts_pkey" primary key (id)
);

alter table "public"."shifts"
  enable row level security;

create table "public"."staff_holidays" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "day"        date                     not null,
  "name"       text                     not null,
  "paid"       boolean                  not null default true,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  constraint "staff_holidays_arena_id_day_key" unique (arena_id, day),
  constraint "staff_holidays_pkey" primary key (id)
);

alter table "public"."staff_holidays"
  enable row level security;

create table "public"."staff_hr_profiles" (
  "staff_id"          uuid                     not null,
  "arena_id"          uuid                     not null,
  "joined_on"         date,
  "left_on"           date,
  "tracks_attendance" boolean                  not null default true,
  "employee_code"     text,
  "paid_leave_days"   numeric(4,1),
  "standard_day_min"  integer,
  "created_at"        timestamp with time zone not null default now(),
  "updated_at"        timestamp with time zone not null default now(),
  constraint "staff_hr_profiles_dates_check"
    check (((left_on IS NULL) OR (joined_on IS NULL) OR (left_on >= joined_on))),
  constraint "staff_hr_profiles_leave_check"
    check
    (((paid_leave_days IS NULL) OR ((paid_leave_days >= (0)::numeric) AND (paid_leave_days <=
    (366)::numeric)))),
  constraint "staff_hr_profiles_pkey" primary key (staff_id),
  constraint "staff_hr_profiles_std_day_check"
    check
    (((standard_day_min IS NULL) OR ((standard_day_min >= 60) AND (standard_day_min <= 1440))))
);

alter table "public"."staff_hr_profiles"
  enable row level security;

create table "public"."staff_pay_rates" (
  "id"                 uuid                     not null,
  "arena_id"           uuid                     not null,
  "staff_id"           uuid                     not null,
  "effective_from"     date                     not null,
  "pay_type"           text                     not null,
  "base_paise"         bigint                   not null,
  "extra_hours_paid"   boolean                  not null default false,
  "extra_hourly_paise" bigint,
  "note"               text,
  "created_by"         uuid                     not null,
  "created_at"         timestamp with time zone not null default now(),
  constraint "staff_pay_rates_amount_check"
    check (((base_paise >= 0) AND ((extra_hourly_paise IS NULL) OR (extra_hourly_paise >= 0)))),
  constraint "staff_pay_rates_extra_check"
    check ((extra_hours_paid OR (extra_hourly_paise IS NULL))),
  constraint "staff_pay_rates_pkey" primary key (id),
  constraint "staff_pay_rates_staff_id_effective_from_key" unique (staff_id, effective_from),
  constraint "staff_pay_rates_type_check"
    check ((pay_type = ANY (ARRAY['monthly'::text, 'daily'::text, 'hourly'::text])))
);

alter table "public"."staff_pay_rates"
  enable row level security;

create table "public"."staff_shifts" (
  "id"             uuid                     not null default gen_random_uuid(),
  "arena_id"       uuid                     not null,
  "staff_id"       uuid                     not null,
  "shift_id"       uuid                     not null,
  "effective_from" date                     not null,
  "effective_to"   date,
  "created_at"     timestamp with time zone not null default now(),
  "updated_at"     timestamp with time zone not null default now(),
  constraint "staff_shifts_pkey" primary key (id),
  constraint "staff_shifts_range_check"
    check (((effective_to IS NULL) OR (effective_to >= effective_from)))
);

alter table "public"."staff_shifts"
  enable row level security;

create or replace function private.attendance_days (
  p_arena uuid,
  p_from  date,
  p_to    date,
  p_staff uuid default null::uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_out jsonb;
begin
  if auth.uid() is null or p_arena is null
     or not exists (select 1 from private.app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'not an active member of this arena';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from >= 62 then
    raise exception 'invalid_period' using hint = 'p_from to p_to, at most 62 days';
  end if;
  if (p_staff is null or not exists (select 1 from staff_profiles
        where id = p_staff and arena_id = p_arena and user_id = auth.uid()))
     and not exists (select 1 from private.app_arena_ids_with(array['attendance_review', 'payroll']) a
                      where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs attendance_review';
  end if;
  perform _att_close_stale(p_arena, p_staff, v_now);
  select coalesce(jsonb_agg(jsonb_build_object('staff_id', s.id, 'staff_name', s.name,
           'work_date', f->>'day', 'status', f->>'status', 'sched_min', f->'sched_min',
           'worked_min', f->'worked_min', 'regular_min', f->'regular_min',
           'extra_min', f->'extra_min', 'late', f->'late', 'early', f->'early',
           'present_units', f->'present_units', 'absent_units', f->'absent_units',
           'half_day', f->'half_day', 'leave_paid', f->'leave_paid', 'leave_lop', f->'leave_lop',
           'holiday_name', f->'holiday', 'flags', f->'flags', 'open', f->'open',
           'entries', f->'entries') order by s.sort_order, s.name, d), '[]'::jsonb)
    into v_out
    from staff_profiles s
    cross join lateral generate_series(p_from, p_to, interval '1 day') d
    cross join lateral _att_day(s.id, d::date, v_now) f
   where s.arena_id = p_arena
     and (case when p_staff is not null then s.id = p_staff
               else (select h.tracks from _staff_hr(s.id) h)
                    and (s.active or exists (select 1 from attendance_entries e
                          where e.staff_id = s.id and e.work_date between p_from and p_to)) end);
  return v_out;
end;
$function$;

create or replace function private.invite_member (
  p_arena uuid,
  p_email text,
  p_name  text,
  p_role  text,
  p_perms text[]
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_name    text := btrim(coalesce(p_name, ''));
  v_owner   boolean;
  v_perms   text[];
  v_token   text;
  v_id      uuid;
  v_expires timestamptz := statement_timestamp() + interval '7 days';
begin
  if auth.uid() is null then
    raise exception 'forbidden' using errcode = '42501', hint = 'sign in first';
  end if;
  if p_role is null or p_role not in ('staff', 'owner') then
    raise exception 'invalid_role' using hint = 'role must be staff or owner';
  end if;
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid_email' using hint = 'enter a valid e-mail address';
  end if;
  if length(v_name) < 1 or length(v_name) > 80 then
    raise exception 'invalid_name' using hint = 'the name must be 1 to 80 characters';
  end if;
  v_owner := exists (select 1 from staff_profiles where arena_id = p_arena
                       and user_id = auth.uid() and active and role = 'owner');
  if p_role = 'owner' then
    if not v_owner then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can invite an owner';
    end if;
    v_perms := _known_perms();
  else
    perform _need(p_arena, 'settings');
    perform _assert_known_perms(p_perms);
    v_perms := coalesce(p_perms, '{}');
    if v_perms && array['money', 'reports', 'payroll', 'payroll_finalise']
       and not private.app_is_owner(p_arena) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant money, reports or payroll';
    end if;
  end if;
  if exists (select 1 from auth.users where id = auth.uid() and lower(email) = v_email) then
    raise exception 'forbidden' using errcode = '42501', hint = 'you cannot invite yourself';
  end if;
  if not v_owner and exists (select 1 from staff_invites where arena_id = p_arena
       and email = v_email and role = 'owner' and accepted_at is null and revoked_at is null) then
    raise exception 'forbidden' using errcode = '42501',
      hint = 'an owner invited this address; only an owner can replace that invite';
  end if;
  update staff_invites set revoked_at = statement_timestamp()
   where arena_id = p_arena and email = v_email and accepted_at is null and revoked_at is null;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into staff_invites (arena_id, email, name, role, perms, token_hash, invited_by, expires_at)
    values (p_arena, v_email, v_name, p_role, v_perms,
            extensions.digest(v_token, 'sha256'), auth.uid(), v_expires)
    returning id into v_id;
  return jsonb_build_object('invite_id', v_id, 'token', v_token, 'expires_at', v_expires);
end;
$function$;

create or replace function private.leave_balances (
  p_arena uuid,
  p_staff uuid default null::uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare v_today date := _pr_ist_date(statement_timestamp());
begin
  if auth.uid() is null or p_arena is null
     or not exists (select 1 from private.app_arena_ids() a where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'not an active member of this arena';
  end if;
  if (p_staff is null or not exists (select 1 from staff_profiles
        where id = p_staff and arena_id = p_arena and user_id = auth.uid()))
     and not exists (select 1 from private.app_arena_ids_with(array['leave_approve', 'payroll']) a
                      where a = p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs leave_approve';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('staff_id', s.id, 'staff_name', s.name, 'active', s.active,
             'joined_on', h.joined_on) || _leave_balance(s.id, v_today) order by s.sort_order, s.name)
      from staff_profiles s
      cross join lateral _staff_hr(s.id) h
     where s.arena_id = p_arena and (p_staff is null or s.id = p_staff)), '[]'::jsonb);
end;
$function$;

create or replace function public._att_blocks (
  p_staff uuid,
  p_day   date
)
  returns table (
    shift_id  uuid,
    start_at  timestamp with time zone,
    end_at    timestamp with time zone,
    break_min integer
  )
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select s.id,
         (p_day::timestamp + make_interval(mins => s.start_min - 330)) at time zone 'UTC',
         ((p_day + case when s.end_min <= s.start_min then 1 else 0 end)::timestamp
            + make_interval(mins => s.end_min - 330)) at time zone 'UTC',
         s.break_min
    from staff_shifts a
    join shifts s on s.id = a.shift_id
   where a.staff_id = p_staff
     and a.effective_from <= p_day
     and (a.effective_to is null or a.effective_to >= p_day)
     and extract(isodow from p_day)::smallint = any (s.days)
   order by 2;
$function$;

create or replace function public._att_close_stale (
  p_arena uuid,
  p_staff uuid,
  p_now   timestamp with time zone
)
  returns integer
  language plpgsql
  set search_path to 'public'
  AS $function$
declare v_n int;
begin
  update attendance_entries e
     set out_at = _att_close_time(e.staff_id, e.work_date, e.in_at),
         out_source = 'auto',
         flags = array(select distinct f from unnest(e.flags || '{auto_out}'::text[]) f order by f),
         review = 'pending'
   where e.arena_id = p_arena
     and (p_staff is null or e.staff_id = p_staff)
     and e.status = 'active' and e.out_at is null
     and e.in_at + make_interval(hours => (_attendance_rules(p_arena)->>'max_open_hours')::int) < p_now;
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

create or replace function public._att_close_time (
  p_staff     uuid,
  p_work_date date,
  p_in_at     timestamp with time zone
)
  returns timestamp with time zone
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select least(
    coalesce(
      (select max(b.end_at) from _att_blocks(p_staff, p_work_date) b where b.end_at > p_in_at),
      p_in_at + make_interval(mins => (select h.standard_day_min from _staff_hr(p_staff) h))),
    p_in_at + make_interval(hours => (_attendance_rules(
      (select arena_id from staff_profiles where id = p_staff))->>'max_open_hours')::int));
$function$;

create or replace function public._att_day (
  p_staff uuid,
  p_day   date,
  p_now   timestamp with time zone
)
  returns jsonb
  language plpgsql
  stable
  set search_path to 'public'
  AS $function$
declare
  v_hr       record;
  v_wh       jsonb;
  v_blocks   int := 0;
  v_first    timestamptz;
  v_last_end timestamptz;
  v_len      int := 0;
  v_brk_max  int := 0;
  v_sched    int := 0;
  v_hol      staff_holidays;
  v_units    numeric := 0;
  v_paid     numeric := 0;
  e          attendance_entries;
  v_end      timestamptz;
  v_prev     timestamptz;
  v_gross    int := 0;
  v_gap      int := 0;
  v_first_in timestamptz;
  v_last_out timestamptz;
  v_open     boolean := false;
  v_auto     boolean := false;
  v_n        int := 0;
  v_flags    text[] := '{}';
  v_net      int;
  v_worked   int;
  v_extra    int;
  v_late     boolean := false;
  v_early    boolean := false;
  v_target   numeric;
  v_status   text;
  v_present  numeric := 0;
  v_absent   numeric := 0;
  v_halfday  boolean := false;
  v_today    date := _pr_ist_date(p_now);
begin
  select * into v_hr from _staff_hr(p_staff);
  if not found then return null; end if;
  if p_day < v_hr.joined_on or (v_hr.left_on is not null and p_day > v_hr.left_on) then
    return jsonb_build_object('day', p_day, 'status', 'not_employed', 'sched_min', 0,
      'worked_min', 0, 'regular_min', 0, 'extra_min', 0, 'late', false, 'early', false,
      'present_units', 0, 'absent_units', 0, 'half_day', false, 'leave_units', 0,
      'leave_paid', 0, 'leave_lop', 0, 'holiday', null, 'holiday_paid', false,
      'flags', '[]'::jsonb, 'open', false, 'entries', 0);
  end if;
  v_wh := _work_hours(v_hr.arena_id);

  select count(*), min(b.start_at), max(b.end_at),
         coalesce(sum(extract(epoch from b.end_at - b.start_at) / 60), 0)::int,
         coalesce(max(b.break_min), 0)
    into v_blocks, v_first, v_last_end, v_len, v_brk_max
    from _att_blocks(p_staff, p_day) b;
  v_sched := case when v_blocks > 0 then greatest(0, v_len - v_brk_max) else 0 end;

  select * into v_hol from staff_holidays where arena_id = v_hr.arena_id and day = p_day;

  select coalesce(sum((x->>'units')::numeric), 0), coalesce(sum((x->>'paid_units')::numeric), 0)
    into v_units, v_paid
    from leave_requests r, jsonb_array_elements(r.day_split) x
   where r.staff_id = p_staff and r.status in ('approved', 'cancel_pending')
     and r.from_date <= p_day and r.to_date >= p_day
     and (x->>'day')::date = p_day;

  for e in select * from attendance_entries
            where staff_id = p_staff and work_date = p_day and status = 'active'
            order by in_at loop
    v_n := v_n + 1;
    v_end := coalesce(e.out_at, greatest(p_now, e.in_at));
    if e.out_at is null then v_open := true; end if;
    if e.out_source = 'auto' then v_auto := true; end if;
    v_gross := v_gross + floor(extract(epoch from v_end - e.in_at) / 60)::int;
    if v_prev is not null then
      v_gap := greatest(v_gap, floor(extract(epoch from e.in_at - v_prev) / 60)::int);
    end if;
    v_prev := v_end;
    v_first_in := coalesce(v_first_in, e.in_at);
    v_last_out := v_end;
    v_flags := v_flags || e.flags;
  end loop;

  -- Break: once a day, when the day is long enough and no gap between entries already took it.
  v_net := greatest(0, v_gross - case
    when v_blocks > 0 and v_brk_max > 0 and v_gross >= (v_wh->>'break_after_min')::int
         and v_gap < v_brk_max then v_brk_max else 0 end);
  v_worked := case v_wh->>'rounding'
    when 'nearest_15' then (floor((v_net + 7.5) / 15) * 15)::int
    when 'down_15' then (floor(v_net / 15.0) * 15)::int
    else v_net end;

  if v_blocks > 0 and v_first_in is not null then
    v_late := v_first_in > v_first + make_interval(mins => (v_wh->>'late_grace_min')::int);
    v_early := not v_open and not v_auto
      and v_last_out < v_last_end - make_interval(mins => (v_wh->>'early_leave_min')::int);
  end if;

  if v_hol.id is not null or v_blocks = 0 then
    v_extra := v_worked;
  else
    v_extra := greatest(0, v_worked - v_hr.standard_day_min);
  end if;

  if v_hol.id is not null then
    v_status := 'holiday';
  elsif v_blocks = 0 then
    v_status := 'week_off';
  elsif v_units >= 1 then
    v_status := 'on_leave';
    if v_worked > 0 then v_flags := v_flags || 'worked_on_leave'::text; end if;
  elsif p_day > v_today or (p_day = v_today and p_now < v_last_end) then
    -- Not over yet: judged once the shift has ended (no absent / half-day before then).
    v_status := case when v_units > 0 then 'half_leave'
                     when v_n > 0 and v_late then 'late'
                     when v_n > 0 then 'present'
                     else 'upcoming' end;
  else
    v_target := case when v_units > 0 then v_sched / 2.0 else v_sched end;
    if v_units > 0 then
      v_status := 'half_leave';
      if v_worked >= v_target * (v_wh->>'half_day_pct')::int / 100 then v_present := 0.5;
      else v_absent := 0.5; end if;
    elsif v_worked >= v_target * (v_wh->>'full_day_pct')::int / 100 then
      v_status := case when v_late then 'late' else 'present' end;
      v_present := 1;
    elsif v_worked >= v_target * (v_wh->>'half_day_pct')::int / 100 then
      v_status := 'half_day';
      v_present := 0.5;
      v_halfday := true;
    else
      v_status := 'absent';
      v_absent := 1;
    end if;
  end if;

  return jsonb_build_object('day', p_day, 'status', v_status, 'sched_min', v_sched,
    'worked_min', v_worked, 'regular_min', v_worked - v_extra, 'extra_min', v_extra,
    'late', v_late and v_status in ('present', 'late', 'half_day', 'half_leave'),
    'early', v_early and v_status in ('present', 'late', 'half_day', 'half_leave'),
    'present_units', v_present, 'absent_units', v_absent, 'half_day', v_halfday,
    'leave_units', v_units, 'leave_paid', v_paid, 'leave_lop', v_units - v_paid,
    'holiday', v_hol.name, 'holiday_paid', coalesce(v_hol.paid, false),
    'flags', to_jsonb(array(select distinct f from unnest(v_flags) f order by f)),
    'open', v_open, 'entries', v_n);
end;
$function$;

create or replace function public._known_perms()
  returns text[]
  language sql
  immutable
  set search_path to 'public'
  AS $function$
  select array['start','bill','discount','members','stations','money','reports','settings',
               'attendance_review','leave_approve','payroll','payroll_finalise'];
$function$;

create or replace function public._leave_balance (
  p_staff uuid,
  p_day   date
)
  returns jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  with y as (
    select _leave_year_start(p_staff, p_day) as ys,
           (_leave_year_start(p_staff, p_day) + interval '1 year' - interval '1 day')::date as ye,
           (select paid_leave_days from _staff_hr(p_staff)) as allowance
  ), parts as (
    select y.*,
      coalesce((select sum(a.days) from leave_adjustments a
                 where a.staff_id = p_staff and a.year_start = y.ys), 0) as adjustments,
      coalesce((select sum((x->>'paid_units')::numeric)
                  from leave_requests r, jsonb_array_elements(r.day_split) x
                 where r.staff_id = p_staff and r.status in ('approved', 'cancel_pending')
                   and (x->>'day')::date between y.ys and y.ye), 0) as used,
      coalesce((select sum(r.days) from leave_requests r
                 where r.staff_id = p_staff and r.status = 'pending'
                   and r.from_date between y.ys and y.ye), 0) as pending
      from y
  )
  select jsonb_build_object('year_start', ys, 'year_end', ye, 'allowance', allowance,
           'adjustments', adjustments, 'used', used, 'pending', pending,
           'balance', allowance + adjustments - used)
    from parts;
$function$;

create or replace function public._leave_rules (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object('paid_leave_days', 12, 'half_day_allowed', true,
           'unplanned_backdate_days', 7)
      || coalesce((select json from settings where arena_id = p_arena and key = 'leave_rules'),
                  '{}'::jsonb);
$function$;

create or replace function public._leave_rules_settings (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
declare v_days numeric; v_back numeric;
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k
                 where k not in ('paid_leave_days', 'half_day_allowed', 'unplanned_backdate_days'))
     or not (p ?& array['paid_leave_days', 'half_day_allowed', 'unplanned_backdate_days']) then
    raise exception 'invalid_leave_rules'
      using hint = 'an object of paid_leave_days, half_day_allowed and unplanned_backdate_days';
  end if;
  if jsonb_typeof(p->'paid_leave_days') is distinct from 'number' then
    raise exception 'invalid_leave_rules' using hint = 'paid_leave_days';
  end if;
  v_days := (p->>'paid_leave_days')::numeric;
  if v_days < 0 or v_days > 366 or (v_days * 2) % 1 <> 0 then
    raise exception 'invalid_leave_rules' using hint = 'paid_leave_days: 0–366, in halves';
  end if;
  if jsonb_typeof(p->'half_day_allowed') is distinct from 'boolean' then
    raise exception 'invalid_leave_rules' using hint = 'half_day_allowed';
  end if;
  if jsonb_typeof(p->'unplanned_backdate_days') is distinct from 'number' then
    raise exception 'invalid_leave_rules' using hint = 'unplanned_backdate_days';
  end if;
  v_back := (p->>'unplanned_backdate_days')::numeric;
  if v_back % 1 <> 0 or v_back < 0 or v_back > 31 then
    raise exception 'invalid_leave_rules' using hint = 'unplanned_backdate_days: 0–31';
  end if;
  return jsonb_build_object('paid_leave_days', v_days, 'half_day_allowed', p->'half_day_allowed',
    'unplanned_backdate_days', v_back::int);
end;
$function$;

create or replace function public._leave_working_days (
  p_staff    uuid,
  p_from     date,
  p_to       date,
  p_half_day text
)
  returns table (
    day   date,
    units numeric
  )
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select d::date, case when p_half_day = 'none' then 1.0 else 0.5 end
    from generate_series(p_from, p_to, interval '1 day') d
   where exists (select 1 from _att_blocks(p_staff, d::date))
     and not exists (select 1 from staff_holidays h
                      where h.arena_id = (select arena_id from staff_profiles where id = p_staff)
                        and h.day = d::date)
   order by 1;
$function$;

create or replace function public._leave_year_start (
  p_staff uuid,
  p_day   date
)
  returns date
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select case when p_day <= h.joined_on then h.joined_on
              else (h.joined_on + make_interval(years => date_part('year', age(p_day, h.joined_on))::int))::date
         end
    from _staff_hr(p_staff) h;
$function$;

create or replace function public._own_record (
  p_arena uuid,
  p_staff uuid
)
  returns void
  language plpgsql
  stable
  set search_path to 'public'
  AS $function$
begin
  if exists (select 1 from staff_profiles where id = p_staff and user_id = auth.uid())
     and not exists (select 1 from staff_profiles where arena_id = p_arena
                      and user_id = auth.uid() and active and role = 'owner') then
    raise exception 'own_record' using hint = 'ask someone else to do this for you';
  end if;
end;
$function$;

create or replace function public._pay_build_line (
  p_run   uuid,
  p_staff uuid
)
  returns boolean
  language plpgsql
  set search_path to 'public'
  AS $function$
declare
  r         salary_runs;
  v_hr      record;
  v_pol     jsonb;
  v_wh      jsonb;
  v_now     timestamptz := statement_timestamp();
  v_n       int;
  v_std_h   numeric;
  v_mult    numeric;
  v_week    boolean;
  v_facts   jsonb[] := '{}';
  f         jsonb;
  d         date;
  i         int;
  v_rate    staff_pay_rates;
  v_last    staff_pay_rates;
  v_rates   jsonb := '[]'::jsonb;
  v_sched_days int := 0;
  v_div     numeric;
  v_dayrate numeric;
  v_hourly  numeric;
  v_units   numeric;
  -- tallies
  c_sched int := 0; c_present numeric := 0; c_late int := 0; c_early int := 0; c_half int := 0;
  c_absent numeric := 0; c_paid numeric := 0; c_lop numeric := 0; c_hol int := 0; c_off int := 0;
  v_worked int := 0; v_regular int := 0; v_extra int := 0;
  -- money (exact until the end)
  m_base numeric := 0; m_extra numeric := 0;
  m_absent numeric := 0; m_lop numeric := 0; m_half numeric := 0; m_late numeric := 0;
  u_absent numeric := 0; u_lop numeric := 0; u_half numeric := 0; u_late numeric := 0;
  v_no_rate_until date;
  -- week basis
  v_wend    date;
  v_wk_work int; v_wk_sched int; v_wk_off int; v_wx int;
  wf        jsonb;
  wd        date;
  -- out
  v_ded     jsonb := '[]'::jsonb;
  v_ded_sum bigint := 0;
  v_gross   bigint;
  v_adj     bigint;
  v_notes   jsonb := '[]'::jsonb;
  v_dec     salary_deduction_decisions;
  v_code    text; v_label text; v_amt numeric; v_u numeric; v_rp numeric;
begin
  select * into r from salary_runs where id = p_run;
  select * into v_hr from _staff_hr(p_staff);
  delete from salary_run_lines where run_id = p_run and staff_id = p_staff;
  if not exists (select 1 from staff_pay_rates where staff_id = p_staff and effective_from <= r.period_end)
     or v_hr.joined_on > r.period_end
     or (v_hr.left_on is not null and v_hr.left_on < r.period_start) then
    return false;
  end if;

  v_pol := r.rules_snapshot->'pay_policy';
  v_wh := r.rules_snapshot->'work_hours';
  v_n := r.period_end - r.period_start + 1;
  v_std_h := v_hr.standard_day_min / 60.0;
  v_mult := (v_pol->>'extra_multiplier')::numeric;
  v_week := v_wh->>'extra_basis' = 'week';

  for d in select g::date from generate_series(r.period_start, r.period_end, interval '1 day') g loop
    f := _att_day(p_staff, d, v_now);
    v_facts := v_facts || f;
    if (f->>'sched_min')::int > 0 and f->>'status' not in ('holiday', 'not_employed') then
      v_sched_days := v_sched_days + 1;
    end if;
  end loop;
  v_div := case v_pol->>'day_divisor' when 'calendar' then v_n when '30' then 30
                                      when '26' then 26 else greatest(v_sched_days, 1) end;

  for i in 1 .. array_length(v_facts, 1) loop
    f := v_facts[i];
    d := (f->>'day')::date;
    continue when f->>'status' = 'not_employed';
    -- Tallies (whatever the pay type).
    if (f->>'sched_min')::int > 0 and f->>'status' <> 'holiday' then c_sched := c_sched + 1; end if;
    c_present := c_present + (f->>'present_units')::numeric;
    c_absent := c_absent + (f->>'absent_units')::numeric;
    c_paid := c_paid + (f->>'leave_paid')::numeric;
    c_lop := c_lop + (f->>'leave_lop')::numeric;
    if (f->>'late')::boolean then c_late := c_late + 1; end if;
    if (f->>'early')::boolean then c_early := c_early + 1; end if;
    if (f->>'half_day')::boolean then c_half := c_half + 1; end if;
    if f->>'status' = 'holiday' then c_hol := c_hol + 1; end if;
    if f->>'status' = 'week_off' then c_off := c_off + 1; end if;
    v_worked := v_worked + (f->>'worked_min')::int;
    if not v_week then
      v_regular := v_regular + (f->>'regular_min')::int;
      v_extra := v_extra + (f->>'extra_min')::int;
    end if;

    select * into v_rate from staff_pay_rates
     where staff_id = p_staff and effective_from <= d order by effective_from desc limit 1;
    if not found then
      v_no_rate_until := d;
      continue;
    end if;
    v_last := v_rate;
    if not v_rates @> jsonb_build_array(jsonb_build_object('effective_from', v_rate.effective_from)) then
      v_rates := v_rates || jsonb_build_array(jsonb_build_object('effective_from', v_rate.effective_from,
        'pay_type', v_rate.pay_type, 'base_paise', v_rate.base_paise,
        'extra_hours_paid', v_rate.extra_hours_paid, 'extra_hourly_paise', v_rate.extra_hourly_paise));
    end if;
    v_dayrate := case v_rate.pay_type when 'monthly' then v_rate.base_paise / v_div
                                      when 'daily' then v_rate.base_paise::numeric
                                      else v_rate.base_paise * v_std_h end;

    if v_rate.pay_type = 'monthly' then
      m_base := m_base + v_rate.base_paise::numeric / v_n;
      u_absent := u_absent + (f->>'absent_units')::numeric;
      m_absent := m_absent + (f->>'absent_units')::numeric * v_dayrate * (v_pol->>'absent_factor')::numeric;
      u_lop := u_lop + (f->>'leave_lop')::numeric;
      m_lop := m_lop + (f->>'leave_lop')::numeric * v_dayrate * (v_pol->>'lop_factor')::numeric;
      if (f->>'half_day')::boolean then
        u_half := u_half + 1;
        m_half := m_half + v_dayrate * (v_pol->>'half_day_factor')::numeric;
      end if;
    elsif v_rate.pay_type = 'daily' then
      v_units := (f->>'present_units')::numeric + (f->>'leave_paid')::numeric
        + case when f->>'status' = 'holiday' and (f->>'holiday_paid')::boolean
                    and (v_pol->>'daily_paid_holidays')::boolean then 1 else 0 end;
      m_base := m_base + v_units * v_rate.base_paise;
    else
      m_base := m_base + (case when v_week then (f->>'worked_min')::int else (f->>'regular_min')::int end)
                         / 60.0 * v_rate.base_paise
                       + (f->>'leave_paid')::numeric * v_std_h * v_rate.base_paise;
    end if;

    if not v_week then
      v_hourly := coalesce(v_rate.extra_hourly_paise::numeric, case v_rate.pay_type
        when 'monthly' then v_rate.base_paise / v_div / v_std_h
        when 'daily' then v_rate.base_paise / v_std_h else v_rate.base_paise::numeric end);
      if v_rate.extra_hours_paid then
        m_extra := m_extra + (f->>'extra_min')::int / 60.0 * v_hourly * v_mult;
      elsif v_rate.pay_type = 'hourly' then
        m_extra := m_extra + (f->>'extra_min')::int / 60.0 * v_rate.base_paise;
      end if;
    end if;
  end loop;

  -- Extra hours per week: each week ending inside the period, priced at that day's rate.
  if v_week then
    for v_wend in select g::date from generate_series(r.period_start, r.period_end, interval '1 day') g
                   where extract(isodow from g)::int = ((v_wh->>'week_start')::int + 5) % 7 + 1 loop
      v_wk_work := 0; v_wk_sched := 0; v_wk_off := 0;
      for wd in select g::date from generate_series(v_wend - 6, v_wend, interval '1 day') g loop
        wf := case when wd >= r.period_start then v_facts[wd - r.period_start + 1]
                   else _att_day(p_staff, wd, v_now) end;
        continue when wf->>'status' = 'not_employed';
        if wf->>'status' in ('holiday', 'week_off') then
          v_wk_off := v_wk_off + (wf->>'worked_min')::int;
        else
          v_wk_work := v_wk_work + (wf->>'worked_min')::int;
          v_wk_sched := v_wk_sched + 1;
        end if;
      end loop;
      v_wx := greatest(0, v_wk_work - v_hr.standard_day_min * v_wk_sched) + v_wk_off;
      v_extra := v_extra + v_wx;
      select * into v_rate from staff_pay_rates
       where staff_id = p_staff and effective_from <= v_wend order by effective_from desc limit 1;
      continue when not found or v_wx = 0;
      v_hourly := coalesce(v_rate.extra_hourly_paise::numeric, case v_rate.pay_type
        when 'monthly' then v_rate.base_paise / v_div / v_std_h
        when 'daily' then v_rate.base_paise / v_std_h else v_rate.base_paise::numeric end);
      if v_rate.pay_type = 'hourly' then
        -- Base paid every hour; the extra ones move to the extra line.
        m_base := m_base - v_wx / 60.0 * v_rate.base_paise;
        m_extra := m_extra + v_wx / 60.0 * case when v_rate.extra_hours_paid
          then v_hourly * v_mult else v_rate.base_paise end;
      elsif v_rate.extra_hours_paid then
        m_extra := m_extra + v_wx / 60.0 * v_hourly * v_mult;
      end if;
    end loop;
    v_regular := v_worked - v_extra;
  end if;

  if v_last.id is null then
    select * into v_last from staff_pay_rates
     where staff_id = p_staff and effective_from <= r.period_end order by effective_from desc limit 1;
  end if;

  -- Late rule, by the pay type in force at the end of the period.
  if (v_pol->>'late_every')::int > 0 and v_last.id is not null
     and v_pol->'late_applies_to' ? v_last.pay_type then
    u_late := floor((c_late + case when (v_pol->>'early_leave_counts_as_late')::boolean
                                   then c_early else 0 end)::numeric / (v_pol->>'late_every')::int)
              * (v_pol->>'late_penalty_days')::numeric;
    m_late := u_late * case v_last.pay_type when 'monthly' then v_last.base_paise / v_div
                                            when 'daily' then v_last.base_paise::numeric
                                            else v_last.base_paise * v_std_h end;
  end if;

  -- Suggested deductions with the owner's keep / waive decision (no decision = kept).
  foreach v_code in array array['absent', 'lop_leave', 'half_day', 'late'] loop
    v_u := case v_code when 'absent' then u_absent when 'lop_leave' then u_lop
                       when 'half_day' then u_half else u_late end;
    v_amt := case v_code when 'absent' then m_absent when 'lop_leave' then m_lop
                         when 'half_day' then m_half else m_late end;
    continue when round(v_amt) = 0;
    v_label := case v_code when 'absent' then 'Absent' when 'lop_leave' then 'Leave without pay (LOP)'
                           when 'half_day' then 'Half days'
                           else 'Late marks (' || (c_late + case when (v_pol->>'early_leave_counts_as_late')::boolean
                                  then c_early else 0 end) || ')' end;
    v_rp := case when v_u = 0 then 0 else v_amt / v_u end;
    select * into v_dec from salary_deduction_decisions
     where run_id = p_run and staff_id = p_staff and code = v_code;
    v_ded := v_ded || jsonb_build_array(jsonb_build_object('code', v_code, 'label', v_label,
      'units', v_u, 'rate_paise', round(v_rp), 'amount_paise', round(v_amt)::bigint,
      'applied', coalesce(v_dec.applied, true), 'note', v_dec.note));
    if coalesce(v_dec.applied, true) then v_ded_sum := v_ded_sum + round(v_amt)::bigint; end if;
  end loop;

  v_gross := round(m_base)::bigint + round(m_extra)::bigint;
  if v_ded_sum > v_gross then
    v_notes := v_notes || to_jsonb('Deductions capped at gross pay'::text);
    v_ded_sum := v_gross;
  end if;
  if v_no_rate_until is not null then
    v_notes := v_notes || to_jsonb(('No pay rate before ' || to_char(v_no_rate_until + 1, 'DD Mon YYYY'))::text);
  end if;
  select coalesce(sum(amount_paise), 0) into v_adj from salary_adjustments
   where run_id = p_run and staff_id = p_staff;

  insert into salary_run_lines(arena_id, run_id, staff_id, staff_name, pay_type, rates, day_counts,
      worked_min, regular_min, extra_min, base_paise, extra_paise, gross_paise, deductions,
      deductions_paise, adjustments_paise, net_paise, days, notes)
    values (r.arena_id, p_run, p_staff, v_hr.name, v_last.pay_type, v_rates,
      jsonb_build_object('scheduled', c_sched, 'present', c_present, 'late', c_late,
        'half_day', c_half, 'absent', c_absent, 'paid_leave', c_paid, 'lop_leave', c_lop,
        'holiday', c_hol, 'week_off', c_off, 'early', c_early),
      v_worked, v_regular, v_extra, round(m_base)::bigint, round(m_extra)::bigint, v_gross, v_ded,
      v_ded_sum, v_adj, v_gross - v_ded_sum + v_adj, to_jsonb(v_facts), v_notes);
  return true;
end;
$function$;

create or replace function public._pay_draft (
  p_arena uuid,
  p_run   uuid
)
  returns public.salary_runs
  language plpgsql
  set search_path to 'public'
  AS $function$
declare r salary_runs;
begin
  select * into r from salary_runs where id = p_run and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'salary run'; end if;
  if r.status <> 'draft' then raise exception 'run_not_draft' using hint = r.status; end if;
  return r;
end;
$function$;

create or replace function public._pay_policy (
  p_arena uuid,
  p_day   date
)
  returns jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object('period_kind', 'monthly', 'cycle_start_day', 1,
           'day_divisor', 'calendar', 'absent_factor', 1, 'lop_factor', 1, 'half_day_factor', 0.5,
           'late_every', 3, 'late_penalty_days', 0.5, 'late_applies_to', '["daily","monthly"]'::jsonb,
           'early_leave_counts_as_late', true, 'extra_multiplier', 1, 'daily_paid_holidays', false)
      || coalesce((select policy from pay_policies where arena_id = p_arena and effective_from <= p_day
                    order by effective_from desc limit 1), '{}'::jsonb);
$function$;

create or replace function public._pay_policy_settings (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
declare
  c_keys constant text[] := array['period_kind', 'cycle_start_day', 'day_divisor', 'absent_factor',
    'lop_factor', 'half_day_factor', 'late_every', 'late_penalty_days', 'late_applies_to',
    'early_leave_counts_as_late', 'extra_multiplier', 'daily_paid_holidays'];
  c_nums constant text[][] := array[['cycle_start_day', '1', '28'], ['absent_factor', '0', '3'],
    ['lop_factor', '0', '3'], ['half_day_factor', '0', '1'], ['late_every', '0', '31'],
    ['late_penalty_days', '0', '1'], ['extra_multiplier', '1', '5']];
  v_out jsonb := '{}'::jsonb;
  v_n numeric;
  v_types text[];
  i int;
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k where k <> all (c_keys))
     or not (p ?& c_keys) then
    raise exception 'invalid_pay_policy' using hint = 'every pay-rule field, and nothing else';
  end if;
  for i in 1 .. array_length(c_nums, 1) loop
    if jsonb_typeof(p->c_nums[i][1]) is distinct from 'number' then
      raise exception 'invalid_pay_policy' using hint = c_nums[i][1];
    end if;
    v_n := (p->>c_nums[i][1])::numeric;
    if v_n < c_nums[i][2]::numeric or v_n > c_nums[i][3]::numeric
       or (c_nums[i][1] in ('cycle_start_day', 'late_every') and v_n % 1 <> 0) then
      raise exception 'invalid_pay_policy'
        using hint = c_nums[i][1] || ': ' || c_nums[i][2] || '–' || c_nums[i][3];
    end if;
    v_out := v_out || jsonb_build_object(c_nums[i][1], v_n);
  end loop;
  if p->>'period_kind' not in ('monthly', 'weekly', 'custom') then
    raise exception 'invalid_pay_policy' using hint = 'period_kind: monthly, weekly or custom';
  end if;
  if p->>'day_divisor' not in ('calendar', '30', '26', 'scheduled') then
    raise exception 'invalid_pay_policy' using hint = 'day_divisor: calendar, 30, 26 or scheduled';
  end if;
  if jsonb_typeof(p->'late_applies_to') is distinct from 'array' then
    raise exception 'invalid_pay_policy' using hint = 'late_applies_to';
  end if;
  select coalesce(array_agg(distinct t order by t), '{}') into v_types
    from jsonb_array_elements_text(p->'late_applies_to') t;
  if not (v_types <@ array['daily', 'hourly', 'monthly']) then
    raise exception 'invalid_pay_policy' using hint = 'late_applies_to: monthly, daily, hourly';
  end if;
  if jsonb_typeof(p->'early_leave_counts_as_late') is distinct from 'boolean' then
    raise exception 'invalid_pay_policy' using hint = 'early_leave_counts_as_late';
  end if;
  if jsonb_typeof(p->'daily_paid_holidays') is distinct from 'boolean' then
    raise exception 'invalid_pay_policy' using hint = 'daily_paid_holidays';
  end if;
  return v_out || jsonb_build_object('period_kind', p->>'period_kind', 'day_divisor', p->>'day_divisor',
    'late_applies_to', to_jsonb(v_types), 'early_leave_counts_as_late', p->'early_leave_counts_as_late',
    'daily_paid_holidays', p->'daily_paid_holidays');
end;
$function$;

create or replace function public._pay_rebuild_run (
  p_run   uuid,
  p_staff uuid
)
  returns integer
  language plpgsql
  set search_path to 'public'
  AS $function$
declare r salary_runs; v_s uuid; v_n int;
begin
  select * into r from salary_runs where id = p_run;
  update salary_runs set rules_snapshot = jsonb_build_object(
      'work_hours', _work_hours(r.arena_id), 'attendance', _attendance_rules(r.arena_id),
      'leave_rules', _leave_rules(r.arena_id), 'pay_policy', _pay_policy(r.arena_id, r.period_start))
   where id = p_run;
  for v_s in select id from staff_profiles
              where arena_id = r.arena_id and (p_staff is null or id = p_staff) loop
    perform _pay_build_line(p_run, v_s);
  end loop;
  update salary_runs s set computed_at = statement_timestamp(),
      staff_count = t.n, gross_paise = t.g, deductions_paise = t.d,
      adjustments_paise = t.a, net_paise = t.net
    from (select count(*)::int as n, coalesce(sum(gross_paise), 0) as g,
                 coalesce(sum(deductions_paise), 0) as d, coalesce(sum(adjustments_paise), 0) as a,
                 coalesce(sum(net_paise), 0) as net
            from salary_run_lines where run_id = p_run) t
   where s.id = p_run
  returning s.staff_count into v_n;
  return v_n;
end;
$function$;

create or replace function public._period_finalised (
  p_arena uuid,
  p_from  date,
  p_to    date
)
  returns boolean
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select exists (select 1 from salary_runs
                  where arena_id = p_arena and status = 'finalised'
                    and period_start <= p_to and period_end >= p_from);
$function$;

create or replace function public._staff_hr (
  p_staff uuid
)
  returns table (
    arena_id         uuid,
    name             text,
    role             text,
    active           boolean,
    joined_on        date,
    left_on          date,
    tracks           boolean,
    standard_day_min integer,
    paid_leave_days  numeric
  )
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select sp.arena_id, sp.name, sp.role, sp.active,
         coalesce(h.joined_on, _pr_ist_date(sp.created_at)),
         h.left_on,
         coalesce(h.tracks_attendance, sp.role <> 'owner'),
         coalesce(h.standard_day_min, (_work_hours(sp.arena_id)->>'standard_day_min')::int),
         coalesce(h.paid_leave_days, (_leave_rules(sp.arena_id)->>'paid_leave_days')::numeric)
    from staff_profiles sp
    left join staff_hr_profiles h on h.staff_id = sp.id
   where sp.id = p_staff;
$function$;

create or replace function public._sync_apply (
  p_arena uuid,
  p_kind  text,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_before jsonb; v_res jsonb;
begin
  -- A price-list change retires the previous catalog into
  -- pricing_catalog_history, so a session priced on it still validates.
  if p_kind in ('rate.upsert', 'rate.delete', 'policy.save', 'settings.save',
                'holiday.upsert', 'holiday.delete', 'activity.upsert', 'activity.remove',
                'rule.upsert', 'rule.delete', 'rule.reorder') then
    v_before := _pricing_canon(_pricing_snapshot(p_arena));
  end if;

  -- Dispatch: one op kind -> one op_* function. Unknown kinds return null and
  -- sync_push rejects them.
  v_res := case p_kind
      when 'session.start'        then op_session_start(p_arena, p)
      when 'session.reconfigure'  then op_session_reconfigure(p_arena, p)
      when 'session.extend'       then op_session_extend(p_arena, p)
      when 'session.end'          then op_session_end(p_arena, p)
      when 'session.void'         then op_session_void(p_arena, p)
      when 'payment.record'       then op_payment(p_arena, p)
      when 'payment.correct'      then op_payment_correct(p_arena, p)
      when 'group.create'         then op_group_create(p_arena, p)
      when 'group.add'            then op_group_add(p_arena, p)
      when 'group.switch'         then op_group_switch(p_arena, p)
      when 'group.end_player'     then op_group_end_player(p_arena, p)
      when 'group.extend'         then op_group_extend(p_arena, p)
      when 'group.end'            then op_group_end(p_arena, p)
      when 'group.void'           then op_group_void(p_arena, p)
      when 'controller.move'      then op_controller_move(p_arena, p)
      when 'controller.upsert'    then op_controller_upsert(p_arena, p)
      when 'controller.set_status' then op_controller_set_status(p_arena, p)
      when 'accessory_kind.upsert' then op_accessory_kind_upsert(p_arena, p)
      when 'accessory_kind.remove' then op_accessory_kind_remove(p_arena, p)
      when 'customer.create'      then op_customer_create(p_arena, p)
      when 'customer.update'      then op_customer_update(p_arena, p)
      when 'booking.create'       then op_booking_create(p_arena, p)
      when 'booking.update'       then op_booking_update(p_arena, p)
      when 'booking.set_status'   then op_booking_set_status(p_arena, p)
      when 'game.upsert'          then op_game_upsert(p_arena, p)
      when 'game.set_active'      then op_game_set_active(p_arena, p)
      when 'game.delete'          then op_game_delete(p_arena, p)
      when 'game.replace_controls' then op_game_replace_controls(p_arena, p)
      when 'game.set_compat'      then op_game_set_compat(p_arena, p)
      when 'resource.upsert'      then op_resource_upsert(p_arena, p)
      when 'resource.set_status'  then op_resource_set_status(p_arena, p)
      when 'resource.set_mode'    then op_resource_set_mode(p_arena, p)
      when 'activity.upsert'      then op_activity_upsert(p_arena, p)
      when 'activity.remove'      then op_activity_remove(p_arena, p)
      when 'rate.upsert'          then op_rate_upsert(p_arena, p)
      when 'rate.delete'          then op_rate_delete(p_arena, p)
      when 'policy.save'          then op_policy_save(p_arena, p)
      when 'settings.save'        then op_settings_save(p_arena, p)
      when 'holiday.upsert'       then op_holiday_upsert(p_arena, p)
      when 'holiday.delete'       then op_holiday_delete(p_arena, p)
      when 'rule.upsert'          then op_rule_upsert(p_arena, p)
      when 'rule.delete'          then op_rule_delete(p_arena, p)
      when 'rule.reorder'         then op_rule_reorder(p_arena, p)
      when 'discount.upsert'      then op_discount_upsert(p_arena, p)
      when 'discount.set_active'  then op_discount_set_active(p_arena, p)
      when 'discount.delete'      then op_discount_delete(p_arena, p)
      when 'staff.update'         then op_staff_update(p_arena, p)
      when 'arena.update'         then op_arena_update(p_arena, p)
      when 'attendance.punch'     then op_attendance_punch(p_arena, p)
      when 'attendance.correct'   then op_attendance_correct(p_arena, p)
      when 'attendance.review'    then op_attendance_review(p_arena, p)
      when 'shift.upsert'         then op_shift_upsert(p_arena, p)
      when 'shift.assign'         then op_shift_assign(p_arena, p)
      when 'shift.unassign'       then op_shift_unassign(p_arena, p)
      when 'staff_holiday.upsert' then op_staff_holiday_upsert(p_arena, p)
      when 'staff_holiday.delete' then op_staff_holiday_delete(p_arena, p)
      when 'hr_profile.save'      then op_hr_profile_save(p_arena, p)
      when 'leave.request'        then op_leave_request(p_arena, p)
      when 'leave.cancel'         then op_leave_cancel(p_arena, p)
      when 'leave.decide'         then op_leave_decide(p_arena, p)
      when 'leave.adjust'         then op_leave_adjust(p_arena, p)
      when 'pay_rate.add'         then op_pay_rate_add(p_arena, p)
      when 'pay_policy.add'       then op_pay_policy_add(p_arena, p)
      when 'salary_run.create'    then op_salary_run_create(p_arena, p)
      when 'salary_run.recalculate' then op_salary_run_recalculate(p_arena, p)
      when 'salary_run.set_deduction' then op_salary_run_set_deduction(p_arena, p)
      when 'salary_run.finalise'  then op_salary_run_finalise(p_arena, p)
      when 'salary_run.discard'   then op_salary_run_discard(p_arena, p)
      when 'salary_adjustment.add' then op_salary_adjustment_add(p_arena, p)
      when 'salary_adjustment.reverse' then op_salary_adjustment_reverse(p_arena, p)
      else null
    end;

  if v_before is not null and v_before <> _pricing_canon(_pricing_snapshot(p_arena)) then
    insert into pricing_catalog_history(arena_id, canon, retired_at)
      values (p_arena, v_before, statement_timestamp())
    on conflict (arena_id, canon_md5) do update set retired_at = excluded.retired_at;
  end if;
  return v_res;
end;
$function$;

create or replace function public._work_hours (
  p_arena uuid
)
  returns jsonb
  language sql
  stable
  set search_path to 'public'
  AS $function$
  select jsonb_build_object('late_grace_min', 10, 'early_leave_min', 15, 'break_after_min', 300,
           'rounding', 'exact', 'full_day_pct', 75, 'half_day_pct', 40, 'standard_day_min', 480,
           'extra_basis', 'day', 'week_start', 1, 'auto_out_after_min', 120)
      || coalesce((select json from settings where arena_id = p_arena and key = 'work_hours'),
                  '{}'::jsonb);
$function$;

create or replace function public._work_hours_settings (
  p jsonb
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public'
  AS $function$
declare
  c_ints constant text[][] := array[
    ['late_grace_min', '0', '120'], ['early_leave_min', '0', '240'],
    ['break_after_min', '0', '1440'], ['full_day_pct', '1', '100'], ['half_day_pct', '1', '99'],
    ['standard_day_min', '60', '1440'], ['week_start', '1', '7'],
    ['auto_out_after_min', '0', '720']];
  v_out jsonb := '{}'::jsonb;
  v_n numeric;
  i int;
begin
  if p is null or jsonb_typeof(p) <> 'object'
     or exists (select 1 from jsonb_object_keys(p) k
                 where k not in ('late_grace_min', 'early_leave_min', 'break_after_min', 'rounding',
                   'full_day_pct', 'half_day_pct', 'standard_day_min', 'extra_basis', 'week_start',
                   'auto_out_after_min'))
     or not (p ?& array['late_grace_min', 'early_leave_min', 'break_after_min', 'rounding',
                   'full_day_pct', 'half_day_pct', 'standard_day_min', 'extra_basis', 'week_start',
                   'auto_out_after_min']) then
    raise exception 'invalid_work_hours'
      using hint = 'every working-hours field, and nothing else';
  end if;
  for i in 1 .. array_length(c_ints, 1) loop
    if jsonb_typeof(p->c_ints[i][1]) is distinct from 'number' then
      raise exception 'invalid_work_hours' using hint = c_ints[i][1];
    end if;
    v_n := (p->>c_ints[i][1])::numeric;
    if v_n % 1 <> 0 or v_n < c_ints[i][2]::int or v_n > c_ints[i][3]::int then
      raise exception 'invalid_work_hours'
        using hint = c_ints[i][1] || ': ' || c_ints[i][2] || '–' || c_ints[i][3];
    end if;
    v_out := v_out || jsonb_build_object(c_ints[i][1], v_n::int);
  end loop;
  if (v_out->>'half_day_pct')::int >= (v_out->>'full_day_pct')::int then
    raise exception 'invalid_work_hours' using hint = 'half_day_pct must be below full_day_pct';
  end if;
  if p->>'rounding' is null or p->>'rounding' not in ('exact', 'nearest_15', 'down_15') then
    raise exception 'invalid_work_hours' using hint = 'rounding: exact, nearest_15 or down_15';
  end if;
  if p->>'extra_basis' is null or p->>'extra_basis' not in ('day', 'week') then
    raise exception 'invalid_work_hours' using hint = 'extra_basis: day or week';
  end if;
  return v_out || jsonb_build_object('rounding', p->>'rounding', 'extra_basis', p->>'extra_basis');
end;
$function$;

create or replace function public.attendance_days (
  p_arena uuid,
  p_from  date,
  p_to    date,
  p_staff uuid default null::uuid
)
  returns jsonb
  language sql
  set search_path to ''
  AS $function$
  select private.attendance_days(p_arena, p_from, p_to, p_staff);
$function$;

create or replace function public.leave_balances (
  p_arena uuid,
  p_staff uuid default null::uuid
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.leave_balances(p_arena, p_staff);
$function$;

create or replace function public.op_attendance_correct (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now    timestamptz := statement_timestamp();
  v_action text := p->>'action';
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_old    attendance_entries;
  v_staff  uuid;
  v_in     timestamptz := (p->>'in_at')::timestamptz;
  v_out    timestamptz := (p->>'out_at')::timestamptz;
  v_day    date;
  v_id     uuid;
begin
  perform _need(p_arena, 'attendance_review');
  if v_action is null or v_action not in ('edit', 'void', 'add') then
    raise exception 'invalid_payload' using hint = 'action: edit, void or add';
  end if;
  if v_reason is null then raise exception 'reason_required'; end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long'; end if;

  if v_action in ('edit', 'void') then
    select * into v_old from attendance_entries
      where id = (p->>'entry_id')::uuid and arena_id = p_arena for update;
    if not found then raise exception 'not_found' using hint = 'entry'; end if;
    v_staff := v_old.staff_id;
    perform _own_record(p_arena, v_staff);
    if v_old.status <> 'active' then raise exception 'not_active'; end if;
    if _period_finalised(p_arena, v_old.work_date, v_old.work_date) then
      raise exception 'period_finalised' using hint = v_old.work_date::text;
    end if;
  else
    v_staff := (p->>'staff_id')::uuid;
    if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
      raise exception 'not_found' using hint = 'staff';
    end if;
    perform _own_record(p_arena, v_staff);
  end if;

  if v_action = 'void' then
    update attendance_entries set status = 'voided', review = 'corrected' where id = v_old.id;
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, created_by, created_at)
      values (p_arena, 'attendance_entry', v_old.id, 'void', v_reason,
              jsonb_build_object('in_at', v_old.in_at, 'out_at', v_old.out_at), auth.uid(), v_now);
    return jsonb_build_object('entry_id', v_old.id);
  end if;

  if v_in is null or (v_action = 'add' and v_out is null) then
    raise exception 'invalid_times' using hint = 'in_at and out_at';
  end if;
  if v_in > v_now or (v_out is not null and (v_out <= v_in or v_out > v_now
                       or v_out - v_in > interval '24 hours')) then
    raise exception 'invalid_times'
      using hint = 'clock-out after clock-in, not in the future, at most 24 h';
  end if;
  v_day := _pr_ist_date(v_in);
  if _period_finalised(p_arena, v_day, v_day) then
    raise exception 'period_finalised' using hint = v_day::text;
  end if;

  if v_action = 'edit' then
    update attendance_entries set status = 'superseded' where id = v_old.id;
  end if;
  begin
    insert into attendance_entries(arena_id, staff_id, work_date, in_at, out_at, in_punch_id,
        out_punch_id, source, out_source, replaces_id, flags, review, reason, created_by)
      values (p_arena, v_staff, v_day, v_in, v_out,
        case when v_action = 'edit' then v_old.in_punch_id end,
        case when v_action = 'edit' then v_old.out_punch_id end,
        'manual',
        case when v_out is null then null
             when v_action = 'edit' and v_out is not distinct from v_old.out_at then v_old.out_source
             else 'manual' end,
        case when v_action = 'edit' then v_old.id end,
        case when v_action = 'edit' then v_old.flags else '{}'::text[] end,
        'corrected', v_reason, auth.uid())
      returning id into v_id;
  exception when exclusion_violation or unique_violation then
    raise exception 'overlap' using hint = 'another stretch of this person covers that time';
  end;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, before, after, created_by, created_at)
    values (p_arena, 'attendance_entry', v_id, case when v_action = 'edit' then 'correct' else 'add' end,
            v_reason,
            case when v_action = 'edit'
                 then jsonb_build_object('entry_id', v_old.id, 'in_at', v_old.in_at, 'out_at', v_old.out_at) end,
            jsonb_build_object('in_at', v_in, 'out_at', v_out), auth.uid(), v_now);
  return jsonb_build_object('entry_id', v_id);
end;
$function$;

create or replace function public.op_attendance_punch (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now      timestamptz := statement_timestamp();
  v_rules    jsonb := _attendance_rules(p_arena);
  v_fence    jsonb := nullif(v_rules->'geofence', 'null'::jsonb);
  v_rule     text  := v_rules->>'outside_rule';
  v_min_acc  int   := (v_rules->>'min_accuracy_m')::int;
  v_max_open interval := make_interval(hours => (v_rules->>'max_open_hours')::int);
  v_punch    uuid  := (p->>'punch_id')::uuid;
  v_kind     text  := p->>'kind';
  v_device   text  := nullif(btrim(p->>'device_id'), '');
  v_loc      jsonb := coalesce(p->'location', '{}'::jsonb);
  v_status   text  := v_loc->>'status';
  v_lat      double precision := (v_loc->>'lat')::double precision;
  v_lng      double precision := (v_loc->>'lng')::double precision;
  v_acc      numeric := (v_loc->>'accuracy_m')::numeric;
  v_mocked   boolean := (v_loc->>'is_mocked')::boolean;
  v_staff    uuid;
  v_dist     int;
  v_verdict  text;
  v_flags    text[] := '{}';
  v_review   text := 'none';
  v_open     attendance_entries;
  v_auto     uuid;
  v_close    timestamptz;
  v_late_out boolean := false;
  v_entry    uuid;
begin
  -- Shape first: a malformed punch is refused before anything is looked up.
  if v_punch is null then raise exception 'invalid_payload' using hint = 'punch_id'; end if;
  if v_kind is null or v_kind not in ('in', 'out') then
    raise exception 'invalid_payload' using hint = 'kind: in or out';
  end if;
  if v_device is null then raise exception 'invalid_payload' using hint = 'device_id'; end if;
  if v_status is null or v_status not in ('ok', 'denied', 'gps_off', 'timeout', 'unavailable') then
    raise exception 'invalid_payload' using hint = 'location.status';
  end if;
  if (v_status = 'ok') <> (v_lat is not null and v_lng is not null and v_acc is not null) then
    raise exception 'invalid_payload' using hint = 'location: lat, lng and accuracy_m exactly when status is ok';
  end if;
  if v_status <> 'ok' then v_mocked := null; end if;

  -- The caller's own profile; locking it queues two punches from two of their devices.
  select id into v_staff from staff_profiles
    where arena_id = p_arena and user_id = auth.uid() and active for update;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;

  -- Verdict against the rules in force now.
  if v_status <> 'ok' then
    v_verdict := 'unknown';
  elsif v_fence is null then
    v_verdict := 'unknown';
    v_flags := v_flags || 'no_geofence'::text;
  else
    v_dist := _geo_distance_m(v_lat, v_lng, (v_fence->>'lat')::double precision,
                              (v_fence->>'lng')::double precision);
    if v_acc > v_min_acc then
      v_verdict := 'unknown';
      v_flags := v_flags || 'low_accuracy'::text;
    elsif v_dist <= (v_fence->>'radius_m')::int then
      v_verdict := 'inside';
    else
      v_verdict := 'outside';
    end if;
  end if;

  if v_mocked then
    if v_rules->>'mock_rule' = 'block' then
      raise exception 'mock_location' using hint = 'the phone reported a mock (fake) location';
    end if;
    v_flags := v_flags || 'mock'::text;
    v_review := 'pending';
  end if;

  if v_verdict <> 'inside' then
    if v_rule = 'block' then
      if v_verdict = 'outside' then
        raise exception 'outside_geofence'
          using hint = v_dist || ' m from the arena; the limit is ' || (v_fence->>'radius_m') || ' m';
      end if;
      raise exception 'location_required'
        using hint = case when v_status = 'denied' then 'location permission is off'
                          when v_status = 'gps_off' then 'location services are off'
                          when v_status in ('timeout', 'unavailable') then 'no location fix'
                          else 'location accuracy is ' || round(v_acc) || ' m; ' || v_min_acc
                               || ' m or better is needed' end;
    end if;
    v_flags := v_flags || v_verdict;
    if v_rule = 'flag' then v_review := 'pending'; end if;
  end if;

  -- The person's open stretch, closed automatically when it was forgotten.
  select * into v_open from attendance_entries
    where staff_id = v_staff and out_at is null and status = 'active' for update;
  if found then
    v_close := _att_close_time(v_staff, v_open.work_date, v_open.in_at);
    if v_open.in_at + v_max_open < v_now
       or (v_kind = 'in' and v_close + make_interval(
             mins => (_work_hours(p_arena)->>'auto_out_after_min')::int) < v_now) then
      update attendance_entries
         set out_at = v_close, out_source = 'auto',
             flags = array(select distinct f from unnest(flags || '{auto_out}'::text[]) f order by f),
             review = 'pending'
       where id = v_open.id;
      v_auto := v_open.id;
    elsif v_kind = 'out' and v_close + make_interval(
            mins => (_work_hours(p_arena)->>'auto_out_after_min')::int) < v_now then
      v_late_out := true;
      v_review := 'pending';
    end if;
  end if;

  if v_kind = 'in' and v_open.id is not null and v_auto is null then
    raise exception 'already_clocked_in'
      using hint = 'clocked in at ' || to_char(v_open.in_at at time zone 'Asia/Kolkata', 'HH24:MI DD Mon');
  end if;
  if v_kind = 'out' and v_open.id is null then
    raise exception 'not_clocked_in';
  end if;

  insert into attendance_punches(id, arena_id, staff_id, kind, server_at, device_at, device_id,
      lat, lng, accuracy_m, is_mocked, location_status, distance_m, geofence, geofence_snapshot,
      flags, created_by)
    values (v_punch, p_arena, v_staff, v_kind, v_now, (p->>'device_at')::timestamptz, v_device,
      v_lat, v_lng, v_acc, v_mocked, v_status, v_dist, v_verdict,
      jsonb_build_object('geofence', coalesce(v_fence, 'null'::jsonb), 'outside_rule', v_rule,
                         'min_accuracy_m', v_min_acc, 'mock_rule', v_rules->>'mock_rule'),
      v_flags, auth.uid());

  if v_kind = 'in' then
    insert into attendance_entries(arena_id, staff_id, work_date, in_at, in_punch_id, flags,
        review, created_by)
      values (p_arena, v_staff, _pr_ist_date(v_now), v_now, v_punch,
        array(select f || '_in' from unnest(v_flags) f order by f), v_review, auth.uid())
      returning id into v_entry;
  else
    -- On an automatic close the punch is kept on the row as evidence of when the person
    -- actually tapped; the stretch itself stays at in_at + max_open_hours.
    update attendance_entries
       set out_at = case when v_auto is null then v_now else out_at end,
           out_source = case when v_auto is null then 'punch' else out_source end,
           out_punch_id = v_punch,
           flags = array(select distinct f from unnest(flags
                     || array(select f2 || '_out' from unnest(v_flags) f2)
                     || case when v_late_out then '{past_shift_end}'::text[] else '{}'::text[] end) f
                   order by f),
           review = case when v_review = 'pending' then 'pending' else review end
     where id = v_open.id;
    v_entry := v_open.id;
  end if;

  return jsonb_build_object('punch_id', v_punch, 'entry_id', v_entry, 'kind', v_kind,
    'server_at', v_now, 'geofence', v_verdict, 'distance_m', v_dist, 'flags', to_jsonb(v_flags),
    'review', (select review from attendance_entries where id = v_entry),
    'auto_closed_entry_id', v_auto);
end;
$function$;

create or replace function public.op_attendance_review (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_e attendance_entries;
begin
  perform _need(p_arena, 'attendance_review');
  select * into v_e from attendance_entries
    where id = (p->>'entry_id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'entry'; end if;
  perform _own_record(p_arena, v_e.staff_id);
  if v_e.review <> 'pending' or v_e.status <> 'active' then raise exception 'not_pending'; end if;
  update attendance_entries set review = 'accepted' where id = v_e.id;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, created_by, created_at)
    values (p_arena, 'attendance_entry', v_e.id, 'accept',
            nullif(btrim(coalesce(p->>'note', '')), ''), auth.uid(), statement_timestamp());
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_hr_profile_save (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_staff uuid := (p->>'staff_id')::uuid;
  v_old   staff_hr_profiles;
  v_hr    record;
  v_new   staff_hr_profiles;
begin
  perform _need(p_arena, 'payroll');
  if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  select * into v_old from staff_hr_profiles where staff_id = v_staff;
  select * into v_hr from _staff_hr(v_staff);
  v_new.staff_id := v_staff;
  v_new.arena_id := p_arena;
  v_new.joined_on := case when p ? 'joined_on' then (p->>'joined_on')::date else v_old.joined_on end;
  v_new.left_on := case when p ? 'left_on' then (p->>'left_on')::date else v_old.left_on end;
  v_new.tracks_attendance := case when p ? 'tracks_attendance'
    then coalesce((p->>'tracks_attendance')::boolean, true) else coalesce(v_old.tracks_attendance, v_hr.tracks) end;
  v_new.employee_code := case when p ? 'employee_code' then nullif(btrim(p->>'employee_code'), '')
    else v_old.employee_code end;
  v_new.paid_leave_days := case when p ? 'paid_leave_days' then (p->>'paid_leave_days')::numeric
    else v_old.paid_leave_days end;
  v_new.standard_day_min := case when p ? 'standard_day_min' then (p->>'standard_day_min')::int
    else v_old.standard_day_min end;
  if v_new.left_on is not null and v_new.joined_on is not null and v_new.left_on < v_new.joined_on then
    raise exception 'invalid_payload' using hint = 'left_on is before joined_on';
  end if;
  if v_new.paid_leave_days is not null
     and (v_new.paid_leave_days < 0 or v_new.paid_leave_days > 366 or (v_new.paid_leave_days * 2) % 1 <> 0) then
    raise exception 'invalid_payload' using hint = 'paid_leave_days: 0–366, in halves';
  end if;
  if v_new.standard_day_min is not null and v_new.standard_day_min not between 60 and 1440 then
    raise exception 'invalid_payload' using hint = 'standard_day_min: 60–1440';
  end if;
  insert into staff_hr_profiles(staff_id, arena_id, joined_on, left_on, tracks_attendance,
      employee_code, paid_leave_days, standard_day_min)
    values (v_new.staff_id, v_new.arena_id, v_new.joined_on, v_new.left_on, v_new.tracks_attendance,
      v_new.employee_code, v_new.paid_leave_days, v_new.standard_day_min)
  on conflict (staff_id) do update set joined_on = excluded.joined_on, left_on = excluded.left_on,
      tracks_attendance = excluded.tracks_attendance, employee_code = excluded.employee_code,
      paid_leave_days = excluded.paid_leave_days, standard_day_min = excluded.standard_day_min;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_leave_adjust (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_staff  uuid := (p->>'staff_id')::uuid;
  v_days   numeric := (p->>'days')::numeric;
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_ys     date;
begin
  perform _need(p_arena, 'leave_approve');
  if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  if v_reason is null then raise exception 'reason_required'; end if;
  if v_days is null or v_days = 0 or (v_days * 2) % 1 <> 0 or abs(v_days) > 366 then
    raise exception 'invalid_payload' using hint = 'days: a non-zero number of half days';
  end if;
  v_ys := _leave_year_start(v_staff, _pr_ist_date(statement_timestamp()));
  insert into leave_adjustments(arena_id, staff_id, year_start, days, reason, created_by)
    values (p_arena, v_staff, v_ys, v_days, v_reason, auth.uid());
  return jsonb_build_object('year_start', v_ys);
end;
$function$;

create or replace function public.op_leave_cancel (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_r leave_requests; v_status text;
begin
  select r.* into v_r from leave_requests r
    join staff_profiles sp on sp.id = r.staff_id
   where r.id = (p->>'id')::uuid and r.arena_id = p_arena and sp.user_id = auth.uid()
   for update of r;
  if not found then raise exception 'not_found' using hint = 'leave request'; end if;
  if v_r.status not in ('pending', 'approved') then raise exception 'invalid_state'; end if;
  if _period_finalised(p_arena, v_r.from_date, v_r.to_date) then
    raise exception 'period_finalised' using hint = 'salary for those days is already finalised';
  end if;
  v_status := case when v_r.status = 'pending' then 'cancelled' else 'cancel_pending' end;
  update leave_requests set status = v_status,
      cancel_reason = nullif(btrim(coalesce(p->>'reason', '')), '')
   where id = v_r.id;
  return jsonb_build_object('status', v_status);
end;
$function$;

create or replace function public.op_leave_decide (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_r       leave_requests;
  v_approve boolean := (p->>'approve')::boolean;
  v_note    text := nullif(btrim(coalesce(p->>'note', '')), '');
  v_paid    numeric;
  v_left    numeric;
  v_split   jsonb;
  v_status  text;
  v_action  text;
begin
  perform _need(p_arena, 'leave_approve');
  if v_approve is null then raise exception 'invalid_payload' using hint = 'approve'; end if;
  select * into v_r from leave_requests
    where id = (p->>'id')::uuid and arena_id = p_arena for update;
  if not found then raise exception 'not_found' using hint = 'leave request'; end if;
  perform _own_record(p_arena, v_r.staff_id);
  if v_r.status not in ('pending', 'cancel_pending') then raise exception 'invalid_state'; end if;
  if _period_finalised(p_arena, v_r.from_date, v_r.to_date) then
    raise exception 'period_finalised' using hint = 'salary for those days is already finalised';
  end if;

  if v_r.status = 'pending' and v_approve then
    if p ? 'paid_days' and p->'paid_days' <> 'null'::jsonb then
      v_paid := (p->>'paid_days')::numeric;
      if v_paid < 0 or v_paid > v_r.days or (v_paid * 2) % 1 <> 0 then
        raise exception 'invalid_paid_days' using hint = '0 to ' || v_r.days || ', in halves';
      end if;
    else
      v_left := greatest(0, (_leave_balance(v_r.staff_id, v_r.from_date)->>'balance')::numeric);
      v_paid := least(v_r.days, floor(v_left * 2) / 2);
    end if;
    -- Pin the paid days to the earliest working days, the rest is LOP.
    select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'units', d.units,
             'paid_units', greatest(0, least(d.units, v_paid - d.before))) order by d.day), '[]'::jsonb)
      into v_split
      from (select w.day, w.units,
                   coalesce(sum(w.units) over (order by w.day rows between unbounded preceding and 1 preceding), 0) as before
              from _leave_working_days(v_r.staff_id, v_r.from_date, v_r.to_date, v_r.half_day) w) d;
    v_status := 'approved'; v_action := 'approve';
    update leave_requests set status = v_status, paid_days = v_paid, lop_days = days - v_paid,
        day_split = v_split, decided_by = auth.uid(), decided_at = statement_timestamp(),
        decision_note = v_note
     where id = v_r.id;
  elsif v_r.status = 'pending' then
    v_status := 'rejected'; v_action := 'reject';
    update leave_requests set status = v_status, decided_by = auth.uid(),
        decided_at = statement_timestamp(), decision_note = v_note
     where id = v_r.id;
  elsif v_approve then
    v_status := 'cancelled'; v_action := 'cancel_approved';
    update leave_requests set status = v_status, paid_days = null, lop_days = null,
        decided_by = auth.uid(), decided_at = statement_timestamp(), decision_note = v_note
     where id = v_r.id;
  else
    v_status := 'approved'; v_action := 'cancel_rejected';
    update leave_requests set status = v_status, decided_by = auth.uid(),
        decided_at = statement_timestamp(), decision_note = v_note
     where id = v_r.id;
  end if;
  select * into v_r from leave_requests where id = v_r.id;
  insert into audit_log(arena_id, entity_type, entity_id, action, reason, after, created_by, created_at)
    values (p_arena, 'leave_request', v_r.id, v_action, v_note,
            jsonb_build_object('paid_days', v_r.paid_days, 'lop_days', v_r.lop_days),
            auth.uid(), statement_timestamp());
  return jsonb_build_object('status', v_status, 'paid_days', v_r.paid_days, 'lop_days', v_r.lop_days);
end;
$function$;

create or replace function public.op_leave_request (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_today  date := _pr_ist_date(statement_timestamp());
  v_rules  jsonb := _leave_rules(p_arena);
  v_staff  uuid;
  v_kind   text := p->>'kind';
  v_from   date := (p->>'from_date')::date;
  v_to     date := (p->>'to_date')::date;
  v_half   text := coalesce(p->>'half_day', 'none');
  v_reason text := nullif(btrim(coalesce(p->>'reason', '')), '');
  v_days   numeric;
begin
  select id into v_staff from staff_profiles
    where arena_id = p_arena and user_id = auth.uid() and active for update;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;
  if v_reason is null then raise exception 'reason_required'; end if;
  if length(v_reason) > 500 then raise exception 'reason_too_long'; end if;
  if v_kind is null or v_kind not in ('planned', 'unplanned') then
    raise exception 'invalid_payload' using hint = 'kind: planned or unplanned';
  end if;
  if v_from is null or v_to is null or v_to < v_from or v_to - v_from > 92 then
    raise exception 'invalid_dates' using hint = 'from_date to to_date, at most 93 days';
  end if;
  if v_half not in ('none', 'first_half', 'second_half') then
    raise exception 'invalid_payload' using hint = 'half_day';
  end if;
  if v_half <> 'none' and (v_from <> v_to or not (v_rules->>'half_day_allowed')::boolean) then
    raise exception 'half_day_not_allowed';
  end if;
  if v_kind = 'planned' and v_from < v_today then
    raise exception 'planned_in_past' using hint = 'planned leave starts today or later';
  end if;
  if v_kind = 'unplanned'
     and v_from < v_today - (v_rules->>'unplanned_backdate_days')::int then
    raise exception 'too_far_back'
      using hint = 'at most ' || (v_rules->>'unplanned_backdate_days') || ' days back';
  end if;
  if _period_finalised(p_arena, v_from, v_to) then
    raise exception 'period_finalised' using hint = 'salary for those days is already finalised';
  end if;
  if exists (select 1 from leave_requests where staff_id = v_staff
              and status in ('pending', 'approved', 'cancel_pending')
              and from_date <= v_to and to_date >= v_from) then
    raise exception 'leave_overlap';
  end if;
  select sum(units) into v_days from _leave_working_days(v_staff, v_from, v_to, v_half);
  if coalesce(v_days, 0) = 0 then
    raise exception 'no_working_days' using hint = 'those days are week-offs or holidays';
  end if;
  insert into leave_requests(id, arena_id, staff_id, kind, from_date, to_date, half_day, days,
      reason, created_by)
    values ((p->>'id')::uuid, p_arena, v_staff, v_kind, v_from, v_to, v_half, v_days, v_reason,
      auth.uid());
  return jsonb_build_object('days', v_days);
end;
$function$;

create or replace function public.op_pay_policy_add (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_from date := (p->>'effective_from')::date; v_policy jsonb;
begin
  perform _need(p_arena, 'payroll');
  if v_from is null then raise exception 'invalid_pay_policy' using hint = 'effective_from'; end if;
  v_policy := _pay_policy_settings(p->'policy');
  if exists (select 1 from salary_runs where arena_id = p_arena and status = 'finalised'
              and period_end >= v_from) then
    raise exception 'rate_in_finalised_period'
      using hint = 'pay up to ' || (select max(period_end) from salary_runs
                                    where arena_id = p_arena and status = 'finalised') || ' is finalised';
  end if;
  insert into pay_policies(id, arena_id, effective_from, policy, created_by)
    values ((p->>'id')::uuid, p_arena, v_from, v_policy, auth.uid());
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_pay_rate_add (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_staff uuid := (p->>'staff_id')::uuid;
  v_from  date := (p->>'effective_from')::date;
  v_type  text := p->>'pay_type';
  v_base  numeric := (p->>'base_paise')::numeric;
  v_paid  boolean := coalesce((p->>'extra_hours_paid')::boolean, false);
  v_xrate numeric := (p->>'extra_hourly_paise')::numeric;
begin
  perform _need(p_arena, 'payroll');
  if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  if v_from is null then raise exception 'invalid_rate' using hint = 'effective_from'; end if;
  if v_type is null or v_type not in ('monthly', 'daily', 'hourly') then
    raise exception 'invalid_rate' using hint = 'pay_type: monthly, daily or hourly';
  end if;
  if v_base is null or v_base < 0 or v_base % 1 <> 0 then
    raise exception 'invalid_rate' using hint = 'base_paise: whole paise';
  end if;
  if v_xrate is not null and (not v_paid or v_xrate < 0 or v_xrate % 1 <> 0) then
    raise exception 'invalid_rate' using hint = 'extra_hourly_paise: whole paise, with extra_hours_paid';
  end if;
  if exists (select 1 from salary_runs where arena_id = p_arena and status = 'finalised'
              and period_end >= v_from) then
    raise exception 'rate_in_finalised_period'
      using hint = 'pay up to ' || (select max(period_end) from salary_runs
                                    where arena_id = p_arena and status = 'finalised') || ' is finalised';
  end if;
  insert into staff_pay_rates(id, arena_id, staff_id, effective_from, pay_type, base_paise,
      extra_hours_paid, extra_hourly_paise, note, created_by)
    values ((p->>'id')::uuid, p_arena, v_staff, v_from, v_type, v_base::bigint, v_paid,
      v_xrate::bigint, nullif(btrim(coalesce(p->>'note', '')), ''), auth.uid());
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_salary_adjustment_add (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  r       salary_runs;
  v_staff uuid := (p->>'staff_id')::uuid;
  v_kind  text := p->>'kind';
  v_amt   numeric := (p->>'amount_paise')::numeric;
  v_note  text := nullif(btrim(coalesce(p->>'note', '')), '');
begin
  perform _need(p_arena, 'payroll');
  r := _pay_draft(p_arena, (p->>'run_id')::uuid);
  if v_note is null then raise exception 'note_required'; end if;
  if v_kind is null or v_kind not in ('bonus', 'advance', 'deduction') then
    raise exception 'invalid_payload' using hint = 'kind: bonus, advance or deduction';
  end if;
  if v_amt is null or v_amt <= 0 or v_amt % 1 <> 0 then
    raise exception 'invalid_payload' using hint = 'amount_paise: whole paise above 0';
  end if;
  if not exists (select 1 from salary_run_lines where run_id = r.id and staff_id = v_staff) then
    raise exception 'not_found' using hint = 'line';
  end if;
  insert into salary_adjustments(id, arena_id, run_id, staff_id, kind, amount_paise, note, created_by)
    values ((p->>'id')::uuid, p_arena, r.id, v_staff, v_kind,
            case when v_kind = 'bonus' then v_amt else -v_amt end::bigint, v_note, auth.uid());
  perform _pay_rebuild_run(r.id, v_staff);
  return jsonb_build_object('net_paise',
    (select net_paise from salary_run_lines where run_id = r.id and staff_id = v_staff));
end;
$function$;

create or replace function public.op_salary_adjustment_reverse (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  a      salary_adjustments;
  r      salary_runs;
  v_note text := nullif(btrim(coalesce(p->>'note', '')), '');
begin
  perform _need(p_arena, 'payroll');
  select * into a from salary_adjustments
   where id = (p->>'reverses_id')::uuid and arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'adjustment'; end if;
  r := _pay_draft(p_arena, a.run_id);
  if v_note is null then raise exception 'note_required'; end if;
  if a.kind = 'reversal' then raise exception 'invalid_payload' using hint = 'a reversal cannot be reversed'; end if;
  begin
    insert into salary_adjustments(id, arena_id, run_id, staff_id, kind, amount_paise, note,
        reverses_id, created_by)
      values ((p->>'id')::uuid, p_arena, a.run_id, a.staff_id, 'reversal', -a.amount_paise,
              v_note, a.id, auth.uid());
  exception when unique_violation then
    if exists (select 1 from salary_adjustments where reverses_id = a.id) then
      raise exception 'already_reversed';
    end if;
    raise;
  end;
  perform _pay_rebuild_run(r.id, a.staff_id);
  return jsonb_build_object('net_paise',
    (select net_paise from salary_run_lines where run_id = r.id and staff_id = a.staff_id));
end;
$function$;

create or replace function public.op_salary_run_create (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id   uuid := (p->>'id')::uuid;
  v_from date := (p->>'period_start')::date;
  v_to   date := (p->>'period_end')::date;
begin
  perform _need(p_arena, 'payroll');
  if v_id is null or v_from is null or v_to is null or v_to < v_from or v_to - v_from >= 62 then
    raise exception 'invalid_period' using hint = 'period_start to period_end, at most 62 days';
  end if;
  perform _att_close_stale(p_arena, null, statement_timestamp());
  begin
    insert into salary_runs(id, arena_id, period_start, period_end, rules_snapshot, computed_at, created_by)
      values (v_id, p_arena, v_from, v_to, '{}'::jsonb, statement_timestamp(), auth.uid());
  exception when exclusion_violation then
    raise exception 'run_overlap' using hint = 'another salary run covers some of those days';
  end;
  return jsonb_build_object('staff_count', _pay_rebuild_run(v_id, null));
end;
$function$;

create or replace function public.op_salary_run_discard (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare r salary_runs;
begin
  perform _need(p_arena, 'payroll_finalise');
  r := _pay_draft(p_arena, (p->>'id')::uuid);
  update salary_runs set status = 'discarded' where id = r.id;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_salary_run_finalise (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare r salary_runs; v_neg text;
begin
  perform _need(p_arena, 'payroll_finalise');
  r := _pay_draft(p_arena, (p->>'id')::uuid);
  perform _att_close_stale(p_arena, null, statement_timestamp());
  perform _pay_rebuild_run(r.id, null);
  select string_agg(staff_name, ', ' order by staff_name) into v_neg
    from salary_run_lines where run_id = r.id and net_paise < 0;
  if v_neg is not null then
    raise exception 'net_negative' using hint = v_neg;
  end if;
  update salary_runs set status = 'finalised', finalised_by = auth.uid(),
      finalised_at = statement_timestamp()
   where id = r.id returning * into r;
  insert into audit_log(arena_id, entity_type, entity_id, action, after, created_by, created_at)
    values (p_arena, 'salary_run', r.id, 'finalise',
            jsonb_build_object('net_paise', r.net_paise, 'staff_count', r.staff_count,
                               'period_start', r.period_start, 'period_end', r.period_end),
            auth.uid(), statement_timestamp());
  return jsonb_build_object('net_paise', r.net_paise);
end;
$function$;

create or replace function public.op_salary_run_recalculate (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare r salary_runs;
begin
  perform _need(p_arena, 'payroll');
  r := _pay_draft(p_arena, (p->>'id')::uuid);
  perform _att_close_stale(p_arena, null, statement_timestamp());
  return jsonb_build_object('staff_count', _pay_rebuild_run(r.id, null));
end;
$function$;

create or replace function public.op_salary_run_set_deduction (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  r       salary_runs;
  v_staff uuid := (p->>'staff_id')::uuid;
  v_code  text := p->>'code';
begin
  perform _need(p_arena, 'payroll');
  r := _pay_draft(p_arena, (p->>'run_id')::uuid);
  if v_code is null or v_code not in ('absent', 'lop_leave', 'half_day', 'late')
     or (p->>'applied') is null then
    raise exception 'invalid_payload' using hint = 'code and applied';
  end if;
  if not exists (select 1 from salary_run_lines where run_id = r.id and staff_id = v_staff) then
    raise exception 'not_found' using hint = 'line';
  end if;
  insert into salary_deduction_decisions(arena_id, run_id, staff_id, code, applied, note, decided_by)
    values (p_arena, r.id, v_staff, v_code, (p->>'applied')::boolean,
            nullif(btrim(coalesce(p->>'note', '')), ''), auth.uid())
  on conflict (run_id, staff_id, code) do update set applied = excluded.applied,
      note = excluded.note, decided_by = excluded.decided_by, decided_at = statement_timestamp();
  perform _pay_rebuild_run(r.id, v_staff);
  return jsonb_build_object('net_paise',
    (select net_paise from salary_run_lines where run_id = r.id and staff_id = v_staff));
end;
$function$;

create or replace function public.op_settings_save (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_json jsonb := p->'json';
begin
  perform _need(p_arena, 'settings');
  if (p->>'key') not in ('business_hours', 'floor_options', 'discount_options', 'venue_profile',
                         'attendance', 'work_hours', 'leave_rules') then
    raise exception 'setting_not_shared' using hint = coalesce(p->>'key', 'null');
  end if;
  if p->>'key' = 'floor_options' then
    v_json := _floor_options(p->'json');
  elsif p->>'key' = 'discount_options' then
    v_json := _discount_options(p->'json');
  elsif p->>'key' = 'venue_profile' then
    v_json := _venue_profile(p->'json');
  elsif p->>'key' = 'attendance' then
    v_json := _attendance_settings(p->'json');
  elsif p->>'key' = 'work_hours' then
    v_json := _work_hours_settings(p->'json');
  elsif p->>'key' = 'leave_rules' then
    v_json := _leave_rules_settings(p->'json');
  end if;
  insert into settings(arena_id, key, json) values (p_arena, p->>'key', v_json)
  on conflict (arena_id, key) do update set json = excluded.json, updated_at = statement_timestamp();
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_shift_assign (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id    uuid := (p->>'id')::uuid;
  v_staff uuid := (p->>'staff_id')::uuid;
  v_shift uuid := (p->>'shift_id')::uuid;
  v_from  date := (p->>'effective_from')::date;
  v_to    date := (p->>'effective_to')::date;
begin
  perform _need(p_arena, 'settings');
  if v_id is null then raise exception 'invalid_payload' using hint = 'id'; end if;
  if v_from is null then raise exception 'invalid_payload' using hint = 'effective_from'; end if;
  if v_to is not null and v_to < v_from then
    raise exception 'invalid_payload' using hint = 'effective_to is before effective_from';
  end if;
  if not exists (select 1 from staff_profiles where id = v_staff and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'staff';
  end if;
  if not exists (select 1 from shifts where id = v_shift and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'shift';
  end if;
  begin
    insert into staff_shifts(id, arena_id, staff_id, shift_id, effective_from, effective_to)
      values (v_id, p_arena, v_staff, v_shift, v_from, v_to)
    on conflict (id) do update set staff_id = excluded.staff_id, shift_id = excluded.shift_id,
        effective_from = excluded.effective_from, effective_to = excluded.effective_to
      where staff_shifts.arena_id = p_arena;
  exception when exclusion_violation then
    raise exception 'assignment_overlap' using hint = 'this person already has this shift on some of those days';
  end;
  if not found then raise exception 'not_found' using hint = 'assignment'; end if;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_shift_unassign (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform _need(p_arena, 'settings');
  delete from staff_shifts where id = (p->>'id')::uuid and arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_shift_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_id    uuid := (p->>'id')::uuid;
  v_name  text := btrim(coalesce(p->>'name', ''));
  v_start int; v_end int; v_break int;
  v_days  smallint[];
begin
  perform _need(p_arena, 'settings');
  if v_id is null then raise exception 'invalid_shift' using hint = 'id'; end if;
  if v_name = '' or length(v_name) > 60 then
    raise exception 'invalid_shift' using hint = 'name: 1–60 characters';
  end if;
  begin
    v_start := (p->>'start_min')::int; v_end := (p->>'end_min')::int;
    v_break := coalesce((p->>'break_min')::int, 0);
  exception when others then
    raise exception 'invalid_shift' using hint = 'start_min, end_min and break_min are whole minutes';
  end;
  if v_start is null or v_end is null or v_start not between 0 and 1439
     or v_end not between 0 and 1439 or v_start = v_end then
    raise exception 'invalid_shift' using hint = 'start_min and end_min: 0–1439, not equal';
  end if;
  if v_break not between 0 and 719 then
    raise exception 'invalid_shift' using hint = 'break_min: 0–719';
  end if;
  if jsonb_typeof(p->'days') is distinct from 'array' then
    raise exception 'invalid_shift' using hint = 'days';
  end if;
  select array_agg(distinct (d)::smallint order by (d)::smallint) into v_days
    from jsonb_array_elements_text(p->'days') d;
  if v_days is null or not (v_days <@ array[1,2,3,4,5,6,7]::smallint[]) then
    raise exception 'invalid_shift' using hint = 'days: one or more of 1–7';
  end if;
  insert into shifts(id, arena_id, name, start_min, end_min, days, break_min, active)
    values (v_id, p_arena, v_name, v_start, v_end, v_days, v_break,
            coalesce((p->>'active')::boolean, true))
  on conflict (id) do update set name = excluded.name, start_min = excluded.start_min,
      end_min = excluded.end_min, days = excluded.days, break_min = excluded.break_min,
      active = excluded.active
    where shifts.arena_id = p_arena;
  if not found then raise exception 'not_found' using hint = 'shift'; end if;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_staff_holiday_delete (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
begin
  perform _need(p_arena, 'settings');
  delete from staff_holidays where arena_id = p_arena and day = (p->>'day')::date;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_staff_holiday_upsert (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare v_name text := btrim(coalesce(p->>'name', ''));
begin
  perform _need(p_arena, 'settings');
  if p->>'day' is null then raise exception 'invalid_payload' using hint = 'day'; end if;
  if v_name = '' or length(v_name) > 80 then
    raise exception 'invalid_payload' using hint = 'name: 1–80 characters';
  end if;
  insert into staff_holidays(arena_id, day, name, paid)
    values (p_arena, (p->>'day')::date, v_name, coalesce((p->>'paid')::boolean, true))
  on conflict (arena_id, day) do update set name = excluded.name, paid = excluded.paid;
  return '{}'::jsonb;
end;
$function$;

create or replace function public.op_staff_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  -- money / reports make a member "owner level" (app_is_owner, and the app's
  -- AppUser.isOwner). Only an owner-level member may hand them out or take them away.
  c_owner_perms constant text[] := array['money', 'reports'];
  v_user   uuid    := (p->>'user_id')::uuid;
  -- A field the op leaves out keeps its current value: a partial update must
  -- never wipe someone's permissions or silently reactivate them.
  v_perms  text[]  := case when p ? 'perms'
                        then array(select jsonb_array_elements_text(coalesce(p->'perms', '[]'::jsonb))) end;
  v_active boolean := (p->>'active')::boolean;
  v_role   text;
  v_old_perms  text[];
  v_old_active boolean;
  v_adj    boolean := false;
begin
  perform _need(p_arena, 'settings');
  select role, perms, active into v_role, v_old_perms, v_old_active from staff_profiles
    where arena_id = p_arena and user_id = v_user for update;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;
  v_perms := coalesce(v_perms, v_old_perms);
  v_active := coalesce(v_active, v_old_active);
  perform _assert_known_perms(v_perms);

  if v_role = 'owner' then
    if not exists (select 1 from staff_profiles where arena_id = p_arena
         and user_id = auth.uid() and active and role = 'owner') then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can change an owner';
    end if;
    -- The server already treats a role owner as holding everything
    -- (app_has_perm); the app reads the perms list. Keep the list complete and
    -- the profile active so both agree and the arena always has an owner.
    -- Removing an owner is an operator action on the database, not an op.
    v_adj := not (v_perms @> _known_perms()) or not v_active;
    v_perms := _known_perms();
    v_active := true;
  else
    -- Nobody changes their own access: a Settings holder could otherwise grant
    -- themselves money/reports and become owner level.
    if v_user = auth.uid()
       and (not (v_perms @> v_old_perms and v_old_perms @> v_perms) or v_active <> v_old_active) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'you cannot change your own permissions';
    end if;
    -- Owner-level perms, and owner-level members, are managed by owners only.
    if not private.app_is_owner(p_arena)
       and (v_old_perms && c_owner_perms
            or ('money' = any(v_perms)) <> ('money' = any(v_old_perms))
            or ('reports' = any(v_perms)) <> ('reports' = any(v_old_perms))) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant money or reports, or change an owner-level member';
    end if;
    -- Pay is owner-level business too: only an owner-level member hands out or takes away
    -- payroll / payroll_finalise.
    if not private.app_is_owner(p_arena)
       and (('payroll' = any(v_perms)) <> ('payroll' = any(v_old_perms))
            or ('payroll_finalise' = any(v_perms)) <> ('payroll_finalise' = any(v_old_perms))) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant or remove payroll permissions';
    end if;
  end if;

  update staff_profiles set name = coalesce(nullif(btrim(p->>'name'), ''), name),
      perms = v_perms, active = v_active,
      sort_order = coalesce((p->>'sort_order')::int, sort_order),
      updated_at = statement_timestamp()
    where arena_id = p_arena and user_id = v_user;
  perform _assert_settings_holder(p_arena);
  -- adjusted = the device wrote something else: it refetches the staff list.
  return case when v_adj then '{"adjusted": true}'::jsonb else '{}'::jsonb end;
end;
$function$;

alter table "public"."leave_adjustments"
  add constraint "leave_adjustments_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."leave_adjustments"
  add constraint "leave_adjustments_created_by_fkey" foreign key (created_by)
    references auth.users(id);

alter table "public"."leave_adjustments"
  add constraint "leave_adjustments_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id) on delete cascade;

alter table "public"."leave_requests"
  add constraint "leave_requests_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."leave_requests"
  add constraint "leave_requests_created_by_fkey" foreign key (created_by) references auth.users(id);

alter table "public"."leave_requests"
  add constraint "leave_requests_decided_by_fkey" foreign key (decided_by) references auth.users(id);

alter table "public"."leave_requests"
  add constraint "leave_requests_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id) on delete cascade;

alter table "public"."pay_policies"
  add constraint "pay_policies_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."pay_policies"
  add constraint "pay_policies_created_by_fkey" foreign key (created_by) references auth.users(id);

alter table "public"."salary_adjustments"
  add constraint "salary_adjustments_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."salary_adjustments"
  add constraint "salary_adjustments_created_by_fkey" foreign key (created_by)
    references auth.users(id);

alter table "public"."salary_adjustments"
  add constraint "salary_adjustments_reverses_id_fkey" foreign key (reverses_id)
    references public.salary_adjustments(id);

alter table "public"."salary_adjustments"
  add constraint "salary_adjustments_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id) on delete cascade;

alter table "public"."salary_deduction_decisions"
  add constraint "salary_deduction_decisions_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."salary_deduction_decisions"
  add constraint "salary_deduction_decisions_decided_by_fkey" foreign key (decided_by)
    references auth.users(id);

alter table "public"."salary_deduction_decisions"
  add constraint "salary_deduction_decisions_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id) on delete cascade;

alter table "public"."salary_run_lines"
  add constraint "salary_run_lines_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."salary_run_lines"
  add constraint "salary_run_lines_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id) on delete cascade;

alter table "public"."salary_runs"
  add constraint "salary_runs_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."salary_runs"
  add constraint "salary_runs_created_by_fkey" foreign key (created_by) references auth.users(id);

alter table "public"."salary_runs"
  add constraint "salary_runs_finalised_by_fkey" foreign key (finalised_by)
    references auth.users(id);

alter table "public"."salary_runs"
  add constraint "salary_runs_no_overlap" EXCLUDE using gist (arena_id
    with =,
    daterange(period_start, period_end, '[]'::text) with &&) where ((status <> 'discarded'::text));

alter table "public"."salary_adjustments"
  add constraint "salary_adjustments_run_id_fkey" foreign key (run_id)
    references public.salary_runs(id) on delete cascade;

alter table "public"."salary_deduction_decisions"
  add constraint "salary_deduction_decisions_run_id_fkey" foreign key (run_id)
    references public.salary_runs(id) on delete cascade;

alter table "public"."salary_run_lines"
  add constraint "salary_run_lines_run_id_fkey" foreign key (run_id)
    references public.salary_runs(id) on delete cascade;

alter table "public"."shifts"
  add constraint "shifts_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."staff_holidays"
  add constraint "staff_holidays_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."staff_hr_profiles"
  add constraint "staff_hr_profiles_arena_id_fkey" foreign key (arena_id)
    references public.arenas(id) on delete cascade;

alter table "public"."staff_hr_profiles"
  add constraint "staff_hr_profiles_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id) on delete cascade;

alter table "public"."staff_pay_rates"
  add constraint "staff_pay_rates_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."staff_pay_rates"
  add constraint "staff_pay_rates_created_by_fkey" foreign key (created_by)
    references auth.users(id);

alter table "public"."staff_pay_rates"
  add constraint "staff_pay_rates_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id) on delete cascade;

alter table "public"."staff_shifts"
  add constraint "staff_shifts_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade;

alter table "public"."staff_shifts"
  add constraint "staff_shifts_no_overlap" EXCLUDE using gist (staff_id with =, shift_id
    with =, daterange(effective_from, effective_to, '[]'::text) with &&);

alter table "public"."staff_shifts"
  add constraint "staff_shifts_shift_id_fkey" foreign key (shift_id) references public.shifts(id)
    on delete cascade;

alter table "public"."staff_shifts"
  add constraint "staff_shifts_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id) on delete cascade;

create index ix_leave_adjustments_arena on public.leave_adjustments using btree (arena_id);

create index ix_leave_adjustments_created_by on public.leave_adjustments using btree (created_by);

create index ix_leave_adjustments_staff on public.leave_adjustments
  using btree (staff_id, year_start);

create index ix_leave_requests_arena_status on public.leave_requests using btree (arena_id, status);

create index ix_leave_requests_created_by on public.leave_requests using btree (created_by);

create index ix_leave_requests_decided_by on public.leave_requests using btree (decided_by);

create index ix_leave_requests_staff on public.leave_requests using btree (staff_id, from_date);

create index ix_pay_policies_created_by on public.pay_policies using btree (created_by);

create index ix_salary_adjustments_arena on public.salary_adjustments using btree (arena_id);

create index ix_salary_adjustments_created_by on public.salary_adjustments using btree (created_by);

create index ix_salary_adjustments_run_staff on public.salary_adjustments
  using btree (run_id, staff_id);

create index ix_salary_adjustments_staff on public.salary_adjustments using btree (staff_id);

create index ix_salary_deduction_decisions_arena on public.salary_deduction_decisions
  using btree (arena_id);

create index ix_salary_deduction_decisions_decided_by on public.salary_deduction_decisions
  using btree (decided_by);

create index ix_salary_deduction_decisions_staff on public.salary_deduction_decisions
  using btree (staff_id);

create index ix_salary_run_lines_arena on public.salary_run_lines using btree (arena_id);

create index ix_salary_run_lines_staff on public.salary_run_lines using btree (staff_id);

create index ix_salary_runs_arena_period on public.salary_runs using btree (arena_id, period_start);

create index ix_salary_runs_created_by on public.salary_runs using btree (created_by);

create index ix_salary_runs_finalised_by on public.salary_runs using btree (finalised_by);

create index ix_staff_hr_profiles_arena on public.staff_hr_profiles using btree (arena_id);

create index ix_staff_pay_rates_arena on public.staff_pay_rates using btree (arena_id);

create index ix_staff_pay_rates_created_by on public.staff_pay_rates using btree (created_by);

create index ix_staff_shifts_arena on public.staff_shifts using btree (arena_id);

create index ix_staff_shifts_shift on public.staff_shifts using btree (shift_id);

create index ix_staff_shifts_staff on public.staff_shifts using btree (staff_id, effective_from);

create unique index ux_shifts_name on public.shifts using btree (arena_id, lower(name));

create trigger t_same_arena
  before insert or update on public.leave_adjustments
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

create trigger t_leave_requests_updated
  before update on public.leave_requests
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.leave_requests
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

create trigger t_same_arena
  before insert or update on public.salary_adjustments
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles', 'run_id', 'salary_runs');

create trigger t_same_arena
  before insert or update on public.salary_deduction_decisions
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles', 'run_id', 'salary_runs');

create trigger t_same_arena
  before insert or update on public.salary_run_lines
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles', 'run_id', 'salary_runs');

create trigger t_salary_runs_updated
  before update on public.salary_runs
  for each row
  execute function public.set_updated_at();

create trigger t_shifts_updated
  before update on public.shifts
  for each row
  execute function public.set_updated_at();

create trigger t_staff_holidays_updated
  before update on public.staff_holidays
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.staff_hr_profiles
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

create trigger t_staff_hr_profiles_updated
  before update on public.staff_hr_profiles
  for each row
  execute function public.set_updated_at();

create trigger t_same_arena
  before insert or update on public.staff_pay_rates
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

create trigger t_same_arena
  before insert or update on public.staff_shifts
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles', 'shift_id', 'shifts');

create trigger t_staff_shifts_updated
  before update on public.staff_shifts
  for each row
  execute function public.set_updated_at();

create policy "p_sel_leave_adjustments" on "public"."leave_adjustments"
  for select
  to "authenticated"
  using
    (((staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids)) or (arena_id in (
    select
    private.app_arena_ids_with(ARRAY['leave_approve'::text, 'attendance_review'::text,
    'payroll'::text]) as app_arena_ids_with))));

create policy "p_sel_leave_requests" on "public"."leave_requests"
  for select
  to "authenticated"
  using
    (((staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids)) or (arena_id in (
    select
    private.app_arena_ids_with(ARRAY['leave_approve'::text, 'attendance_review'::text,
    'payroll'::text]) as app_arena_ids_with))));

create policy "p_sel_pay_policies" on "public"."pay_policies"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['payroll'::text]) as
    app_arena_ids_with)));

create policy "p_sel_salary_adjustments" on "public"."salary_adjustments"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['payroll'::text,
    'payroll_finalise'::text]) as app_arena_ids_with)));

create policy "p_sel_salary_deduction_decisions" on "public"."salary_deduction_decisions"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['payroll'::text,
    'payroll_finalise'::text]) as app_arena_ids_with)));

create policy "p_sel_salary_run_lines" on "public"."salary_run_lines"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['payroll'::text,
    'payroll_finalise'::text]) as app_arena_ids_with)));

create policy "p_sel_salary_runs" on "public"."salary_runs"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['payroll'::text,
    'payroll_finalise'::text]) as app_arena_ids_with)));

create policy "p_sel_shifts" on "public"."shifts"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_staff_holidays" on "public"."staff_holidays"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

create policy "p_sel_staff_hr_profiles" on "public"."staff_hr_profiles"
  for select
  to "authenticated"
  using
    (((staff_id in ( select private.app_my_staff_ids() as app_my_staff_ids)) or (arena_id in (
    select
    private.app_arena_ids_with(ARRAY['attendance_review'::text, 'leave_approve'::text,
    'payroll'::text]) as app_arena_ids_with))));

create policy "p_sel_staff_pay_rates" on "public"."staff_pay_rates"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['payroll'::text]) as
    app_arena_ids_with)));

create policy "p_sel_staff_shifts" on "public"."staff_shifts"
  for select
  to "authenticated"
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

comment on column "public"."leave_adjustments"."year_start" is 'First day of the leave year (a joining anniversary) the change counts in.';

comment on column "public"."leave_requests"."day_split" is 'Set on approval: [{day, units, paid_units}] for each working day, paid days filling the earliest dates. Kept while cancel_pending.';

comment on column "public"."leave_requests"."days" is 'Working days the request covers (0.5 for a half day), counted when it is made.';

comment on column "public"."leave_requests"."lop_days" is 'Days of loss of pay (days - paid_days), set on approval.';

comment on column "public"."leave_requests"."paid_days" is 'Days paid from the allowance, set on approval; null until then.';

comment on column "public"."leave_requests"."status" is 'pending, approved, rejected, cancelled, or cancel_pending (approved leave whose cancellation awaits approval).';

comment on column "public"."salary_adjustments"."amount_paise" is 'Signed paise: bonus > 0; advance and deduction < 0; a reversal is the opposite of the row it reverses.';

comment on column "public"."salary_run_lines"."days" is 'The timesheet: one entry per day of the period from _att_day.';

comment on column "public"."salary_run_lines"."deductions" is '[{code, label, units, rate_paise, amount_paise, applied, note}]: suggested deductions (absent, lop_leave, half_day, late); only applied ones count.';

comment on column "public"."salary_runs"."rules_snapshot" is 'The rules used: {work_hours, attendance, leave_rules, pay_policy}.';

comment on column "public"."salary_runs"."status" is 'draft, finalised (locked) or discarded.';

comment on column "public"."shifts"."break_min" is 'Unpaid break in minutes, deducted once a day (see work_hours.break_after_min).';

comment on column "public"."shifts"."days" is 'ISO weekdays the shift runs on (1 = Monday … 7 = Sunday).';

comment on column "public"."shifts"."end_min" is 'End, minutes after IST midnight; <= start_min means the next day.';

comment on column "public"."shifts"."start_min" is 'Start, minutes after IST midnight (0–1439).';

comment on column "public"."staff_holidays"."paid" is 'Whether the day is paid (monthly staff are never docked for it; daily staff are paid for it when the pay rules say so).';

comment on column "public"."staff_hr_profiles"."joined_on" is 'Joining date; each leave year runs from its anniversary. Null = the profile''s creation date.';

comment on column "public"."staff_hr_profiles"."left_on" is 'Last working day, or null while employed.';

comment on column "public"."staff_hr_profiles"."paid_leave_days" is 'Paid leave days per leave year; null = the arena default (leave_rules).';

comment on column "public"."staff_hr_profiles"."standard_day_min" is 'Minutes in a standard day (extra hours start after it); null = the arena default (work_hours).';

comment on column "public"."staff_hr_profiles"."tracks_attendance" is 'Whether this person clocks in and appears on timesheets.';

comment on column "public"."staff_pay_rates"."base_paise" is 'Pay per month, per day or per hour in paise, by pay_type.';

comment on column "public"."staff_pay_rates"."extra_hourly_paise" is 'Own rate for extra hours in paise; null = derived from the pay (monthly: base / day divisor / standard hours; daily: base / standard hours; hourly: base).';

comment on column "public"."staff_profiles"."perms" is 'Permission codes from _known_perms(): start, bill, discount, members, stations, money, reports, settings, attendance_review, leave_approve, payroll, payroll_finalise. Holding money or reports makes the member owner level (app_is_owner).';

comment on column "public"."staff_shifts"."effective_to" is 'Last day (inclusive); null = open-ended.';

comment on function "private"."attendance_days"(uuid, date, date, uuid) is 'Client API: attendance per person and IST day (status, scheduled / worked / extra minutes, leave, flags) — your own, or everyone''s with attendance_review / payroll.';

comment on function "private"."leave_balances"(uuid, uuid) is 'Client API: paid-leave allowance, used, pending and balance per person for the current leave year — your own, or everyone''s with leave_approve / payroll.';

comment on function "public"."_att_blocks"(uuid, date) is 'Internal: the shift blocks (UTC start/end, break) a staff profile is scheduled for on an IST day; none = week off.';

comment on function "public"."_att_close_stale"(uuid, uuid, timestamp
  with time zone) is 'Internal: close forgotten clock-ins (open past max_open_hours) at the shift end / standard day, flagged auto_out for review.';

comment on function "public"."_att_close_time"(uuid, date, timestamp
  with time zone) is 'Internal: when a forgotten clock-in counts as ended: the shift end that day, else clock-in + standard day, capped at max_open_hours.';

comment on function "public"."_att_day"(uuid, date, timestamp
  with time zone) is 'Internal: one staff profile''s IST day: status, scheduled / worked / regular / extra minutes, late / early, present and absent units, leave split, holiday, flags. Shared by the floor, the dashboard and salary runs.';

comment on function "public"."_known_perms"() is 'The permission codes a staff profile may hold: start, bill, discount, members, stations, money, reports, settings, attendance_review, leave_approve, payroll, payroll_finalise.';

comment on function "public"."_leave_balance"(uuid, date) is 'Internal: paid-leave allowance, adjustments, used, pending and balance for the leave year containing an IST day.';

comment on function "public"."_leave_rules"(uuid) is 'Internal: the arena''s leave_rules setting merged over the defaults.';

comment on function "public"."_leave_rules_settings"(jsonb) is 'Validates the leave_rules setting (paid days per leave year, half days allowed, how far back unplanned leave may start); raises invalid_leave_rules.';

comment on function "public"."_leave_working_days"(uuid, date, date, text) is
  'Internal: the scheduled, non-holiday IST days of a leave request with their units (1, or 0.5 for a half day).';

comment on function "public"."_leave_year_start"(uuid, date) is 'Internal: the joining anniversary that starts the leave year containing an IST day.';

comment on function "public"."_own_record"(uuid, uuid) is 'Internal: raise own_record when the caller acts on their own staff record and is not role owner.';

comment on function "public"."_pay_build_line"(uuid, uuid) is 'Internal: (re)build one staff member''s salary-run line: timesheet, base, extra hours, suggested deductions with keep / waive, adjustments and net, in paise.';

comment on function "public"."_pay_draft"(uuid, uuid) is 'Internal: lock an arena''s salary run and raise run_not_draft unless it is a draft.';

comment on function "public"."_pay_policy"(uuid, date) is 'Internal: the pay rules in force on an IST day, merged over the defaults.';

comment on function "public"."_pay_policy_settings"(jsonb) is 'Validates a pay policy (period, day divisor, absent / LOP / half-day factors, late rule, extra-hours multiplier, daily holidays); raises invalid_pay_policy.';

comment on function "public"."_pay_rebuild_run"(uuid, uuid) is 'Internal: refresh a draft salary run''s rules snapshot, rebuild one or every line, and recompute its totals.';

comment on function "public"."_period_finalised"(uuid, date, date) is 'Internal: true when a finalised salary run covers any day of [from, to].';

comment on function "public"."_staff_hr"(uuid) is 'Internal: a staff profile''s joining/leaving dates, tracking, standard day and paid-leave allowance, defaults filled in.';

comment on function "public"."_work_hours"(uuid) is 'Internal: the arena''s work_hours setting merged over the defaults.';

comment on function "public"."_work_hours_settings"(jsonb) is 'Validates the work_hours setting (grace, early leave, break, rounding, full/half-day %, standard day, extra-hours basis, week start, auto clock-out grace); raises invalid_work_hours.';

comment on function "public"."attendance_days"(uuid, date, date, uuid) is 'Client API: attendance per person and IST day (status, minutes, leave, flags) — your own, or everyone''s with attendance_review / payroll.';

comment on function "public"."leave_balances"(uuid, uuid) is 'Client API: paid-leave balance per person for the current leave year — your own, or everyone''s with leave_approve / payroll.';

comment on function "public"."op_attendance_correct"(uuid, jsonb) is 'Sync op attendance.correct: edit (supersede), void or add an attendance entry with a reason; history and audit_log kept.';

comment on function "public"."op_attendance_review"(uuid, jsonb) is 'Sync op attendance.review: accept a flagged attendance entry as it is (audit_log keeps who and the note).';

comment on function "public"."op_hr_profile_save"(uuid, jsonb) is 'Sync op hr_profile.save: a staff member''s joining/leaving dates, tracking, employee code and standard-day / paid-leave overrides (payroll).';

comment on function "public"."op_leave_adjust"(uuid, jsonb) is 'Sync op leave.adjust: add (or take) paid-leave days in a staff member''s current leave year, with a reason.';

comment on function "public"."op_leave_cancel"(uuid, jsonb) is 'Sync op leave.cancel: the requester cancels a pending request, or asks to cancel an approved one (cancel_pending).';

comment on function "public"."op_leave_decide"(uuid, jsonb) is 'Sync op leave.decide: approve (with the paid / LOP split pinned to dates) or reject a leave request, or its cancellation.';

comment on function "public"."op_leave_request"(uuid, jsonb) is 'Sync op leave.request: the caller applies for planned or unplanned leave; working days are counted by the server.';

comment on function "public"."op_pay_policy_add"(uuid, jsonb) is 'Sync op pay_policy.add: the arena''s pay rules from a date after the last finalised run.';

comment on function "public"."op_pay_rate_add"(uuid, jsonb) is 'Sync op pay_rate.add: a staff member''s pay (monthly / daily / hourly, extra hours) from a date after the last finalised run.';

comment on function "public"."op_salary_adjustment_add"(uuid, jsonb) is 'Sync op salary_adjustment.add: a bonus, advance or deduction with a note on a person in a draft run (payroll).';

comment on function "public"."op_salary_adjustment_reverse"(uuid, jsonb) is
  'Sync op salary_adjustment.reverse: undo a salary adjustment with an opposite reversal row (payroll).';

comment on function "public"."op_salary_run_create"(uuid, jsonb) is 'Sync op salary_run.create: a draft salary run for a pay period, one line per paid staff member (payroll).';

comment on function "public"."op_salary_run_discard"(uuid, jsonb) is 'Sync op salary_run.discard: mark a draft salary run discarded (payroll_finalise).';

comment on function "public"."op_salary_run_finalise"(uuid, jsonb) is 'Sync op salary_run.finalise: rebuild a draft salary run and lock it and its period (payroll_finalise).';

comment on function "public"."op_salary_run_recalculate"(uuid, jsonb) is 'Sync op salary_run.recalculate: rebuild a draft salary run from live attendance, leave and rates (payroll).';

comment on function "public"."op_salary_run_set_deduction"(uuid, jsonb) is 'Sync op salary_run.set_deduction: the owner keeps or waives one suggested deduction of a person in a draft run (payroll).';

comment on function "public"."op_shift_assign"(uuid, jsonb) is 'Sync op shift.assign: assign (or re-date) a staff profile to a shift for an inclusive date range.';

comment on function "public"."op_shift_unassign"(uuid, jsonb) is 'Sync op shift.unassign: remove a shift assignment (no-op when already gone).';

comment on function "public"."op_shift_upsert"(uuid, jsonb) is 'Sync op shift.upsert: create or edit a named shift (IST start/end minutes, weekdays, unpaid break, active).';

comment on function "public"."op_staff_holiday_delete"(uuid, jsonb) is 'Sync op staff_holiday.delete: remove the staff holiday on an IST day.';

comment on function "public"."op_staff_holiday_upsert"(uuid, jsonb) is 'Sync op staff_holiday.upsert: add or edit the staff holiday on an IST day (paid by default).';

comment on table "public"."leave_adjustments" is 'Append-only manual changes (signed days, with a reason) to a staff member''s paid-leave balance for one leave year.';

comment on table "public"."leave_requests" is 'Leave requests per staff profile: dates, planned/unplanned, working days counted, and the approver''s paid/LOP split pinned to dates (day_split).';

comment on table "public"."pay_policies" is 'Effective-dated pay rules per arena (period, divisor, deduction factors, late rule, extra-hours multiplier).';

comment on table "public"."salary_adjustments" is 'Append-only salary adjustments in a run (bonus, advance, deduction, reversal) with a note; signed paise.';

comment on table "public"."salary_deduction_decisions" is 'The owner''s keep (applied) or waive decision on each suggested salary deduction of a draft run.';

comment on table "public"."salary_run_lines" is 'One staff member''s pay in one salary run: day-by-day timesheet, rates used, base, extra hours, suggested deductions with keep/waive, adjustments and net, in paise.';

comment on table "public"."salary_runs" is 'Salary runs per arena and pay period: draft (rebuilt on demand), finalised (frozen, locks the period) or discarded; totals in paise.';

comment on table "public"."shifts" is 'Named shifts per arena: IST start/end minutes (end <= start = ends next day), ISO weekdays and an unpaid break.';

comment on table "public"."staff_holidays" is 'Staff holidays per arena (IST days off for everyone, paid by default); separate from the pricing holidays.';

comment on table "public"."staff_hr_profiles" is 'HR facts per staff profile for leave and payroll: joining/leaving dates, whether attendance is tracked, employee code, and overrides of the arena standard day and paid-leave allowance.';

comment on table "public"."staff_pay_rates" is 'Effective-dated pay per staff profile: monthly, daily or hourly base in paise, and whether (and at what rate) extra hours are paid.';

comment on table "public"."staff_shifts" is 'Shift assignments per staff profile with an inclusive effective date range (null end = open-ended).';

revoke all on function "private"."attendance_days"(uuid, date, date, uuid) from public;

grant execute
  on function "private"."attendance_days"(uuid, date, date, uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "private"."leave_balances"(uuid, uuid) from public;

grant execute
  on function "private"."leave_balances"(uuid, uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."_att_blocks"(uuid, date) from public;

grant execute on function "public"."_att_blocks"(uuid, date) to "postgres", "service_role";

revoke all on function "public"."_att_close_stale"(uuid, uuid, timestamp with time zone) from public;

grant execute
  on function "public"."_att_close_stale"(uuid, uuid, timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_att_close_time"(uuid, date, timestamp with time zone) from public;

grant execute
  on function "public"."_att_close_time"(uuid, date, timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_att_day"(uuid, date, timestamp with time zone) from public;

grant execute
  on function "public"."_att_day"(uuid, date, timestamp with time zone)
  to "postgres", "service_role";

revoke all on function "public"."_leave_balance"(uuid, date) from public;

grant execute on function "public"."_leave_balance"(uuid, date) to "postgres", "service_role";

revoke all on function "public"."_leave_rules"(uuid) from public;

grant execute on function "public"."_leave_rules"(uuid) to "postgres", "service_role";

revoke all on function "public"."_leave_rules_settings"(jsonb) from public;

grant execute on function "public"."_leave_rules_settings"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_leave_working_days"(uuid, date, date, text) from public;

grant execute
  on function "public"."_leave_working_days"(uuid, date, date, text)
  to "postgres", "service_role";

revoke all on function "public"."_leave_year_start"(uuid, date) from public;

grant execute on function "public"."_leave_year_start"(uuid, date) to "postgres", "service_role";

revoke all on function "public"."_own_record"(uuid, uuid) from public;

grant execute on function "public"."_own_record"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_pay_build_line"(uuid, uuid) from public;

grant execute on function "public"."_pay_build_line"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_pay_draft"(uuid, uuid) from public;

grant execute on function "public"."_pay_draft"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_pay_policy"(uuid, date) from public;

grant execute on function "public"."_pay_policy"(uuid, date) to "postgres", "service_role";

revoke all on function "public"."_pay_policy_settings"(jsonb) from public;

grant execute on function "public"."_pay_policy_settings"(jsonb) to "postgres", "service_role";

revoke all on function "public"."_pay_rebuild_run"(uuid, uuid) from public;

grant execute on function "public"."_pay_rebuild_run"(uuid, uuid) to "postgres", "service_role";

revoke all on function "public"."_period_finalised"(uuid, date, date) from public;

grant execute
  on function "public"."_period_finalised"(uuid, date, date)
  to "postgres", "service_role";

revoke all on function "public"."_staff_hr"(uuid) from public;

grant execute on function "public"."_staff_hr"(uuid) to "postgres", "service_role";

revoke all on function "public"."_work_hours"(uuid) from public;

grant execute on function "public"."_work_hours"(uuid) to "postgres", "service_role";

revoke all on function "public"."_work_hours_settings"(jsonb) from public;

grant execute on function "public"."_work_hours_settings"(jsonb) to "postgres", "service_role";

revoke all on function "public"."attendance_days"(uuid, date, date, uuid) from public;

grant execute
  on function "public"."attendance_days"(uuid, date, date, uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."leave_balances"(uuid, uuid) from public;

grant execute
  on function "public"."leave_balances"(uuid, uuid)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."op_attendance_correct"(uuid, jsonb) from public;

grant execute
  on function "public"."op_attendance_correct"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_attendance_review"(uuid, jsonb) from public;

grant execute on function "public"."op_attendance_review"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_hr_profile_save"(uuid, jsonb) from public;

grant execute on function "public"."op_hr_profile_save"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_leave_adjust"(uuid, jsonb) from public;

grant execute on function "public"."op_leave_adjust"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_leave_cancel"(uuid, jsonb) from public;

grant execute on function "public"."op_leave_cancel"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_leave_decide"(uuid, jsonb) from public;

grant execute on function "public"."op_leave_decide"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_leave_request"(uuid, jsonb) from public;

grant execute on function "public"."op_leave_request"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_pay_policy_add"(uuid, jsonb) from public;

grant execute on function "public"."op_pay_policy_add"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_pay_rate_add"(uuid, jsonb) from public;

grant execute on function "public"."op_pay_rate_add"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_salary_adjustment_add"(uuid, jsonb) from public;

grant execute
  on function "public"."op_salary_adjustment_add"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_salary_adjustment_reverse"(uuid, jsonb) from public;

grant execute
  on function "public"."op_salary_adjustment_reverse"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_salary_run_create"(uuid, jsonb) from public;

grant execute on function "public"."op_salary_run_create"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_salary_run_discard"(uuid, jsonb) from public;

grant execute
  on function "public"."op_salary_run_discard"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_salary_run_finalise"(uuid, jsonb) from public;

grant execute
  on function "public"."op_salary_run_finalise"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_salary_run_recalculate"(uuid, jsonb) from public;

grant execute
  on function "public"."op_salary_run_recalculate"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_salary_run_set_deduction"(uuid, jsonb) from public;

grant execute
  on function "public"."op_salary_run_set_deduction"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_shift_assign"(uuid, jsonb) from public;

grant execute on function "public"."op_shift_assign"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_shift_unassign"(uuid, jsonb) from public;

grant execute on function "public"."op_shift_unassign"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_shift_upsert"(uuid, jsonb) from public;

grant execute on function "public"."op_shift_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_staff_holiday_delete"(uuid, jsonb) from public;

grant execute
  on function "public"."op_staff_holiday_delete"(uuid, jsonb)
  to "postgres", "service_role";

revoke all on function "public"."op_staff_holiday_upsert"(uuid, jsonb) from public;

grant execute
  on function "public"."op_staff_holiday_upsert"(uuid, jsonb)
  to "postgres", "service_role";

grant select on table "public"."leave_adjustments" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."leave_adjustments"
  to "postgres", "service_role";

grant select on table "public"."leave_requests" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."leave_requests"
  to "postgres", "service_role";

grant select on table "public"."pay_policies" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."pay_policies"
  to "postgres", "service_role";

grant select on table "public"."salary_adjustments" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."salary_adjustments"
  to "postgres", "service_role";

grant select on table "public"."salary_deduction_decisions" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."salary_deduction_decisions"
  to "postgres", "service_role";

grant select on table "public"."salary_run_lines" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."salary_run_lines"
  to "postgres", "service_role";

grant select on table "public"."salary_runs" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."salary_runs"
  to "postgres", "service_role";

grant select on table "public"."shifts" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."shifts"
  to "postgres", "service_role";

grant select on table "public"."staff_holidays" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_holidays"
  to "postgres", "service_role";

grant select on table "public"."staff_hr_profiles" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_hr_profiles"
  to "postgres", "service_role";

grant select on table "public"."staff_pay_rates" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_pay_rates"
  to "postgres", "service_role";

grant select on table "public"."staff_shifts" to "authenticated";

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_shifts"
  to "postgres", "service_role";
