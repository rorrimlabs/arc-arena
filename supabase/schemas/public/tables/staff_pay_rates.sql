-- staff_pay_rates — what a person is paid, from a date (append-only, effective-dated)
--
-- monthly / daily / hourly base in paise. extra_hours_paid pays the minutes beyond the standard
-- day (and all minutes on holidays and week-offs) at extra_hourly_paise, or a rate derived from
-- the pay when null (OWNER_CONFIRMATION S3), times the arena multiplier. A new rate never
-- changes a finalised period: op_pay_rate_add refuses an effective date inside one. Pay is
-- never shown in the floor app: readable with payroll only.
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
  constraint "staff_pay_rates_amount_check" check (((base_paise >= 0) AND ((extra_hourly_paise IS NULL) OR (extra_hourly_paise >= 0)))),
  constraint "staff_pay_rates_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "staff_pay_rates_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "staff_pay_rates_extra_check" check ((extra_hours_paid OR (extra_hourly_paise IS NULL))),
  constraint "staff_pay_rates_pkey" primary key (id),
  constraint "staff_pay_rates_staff_id_effective_from_key" unique (staff_id, effective_from),
  constraint "staff_pay_rates_staff_id_fkey" foreign key (staff_id) references public.staff_profiles(id),
  constraint "staff_pay_rates_type_check" check ((pay_type = ANY (ARRAY['monthly'::text, 'daily'::text, 'hourly'::text])))
);

comment on table public.staff_pay_rates is 'Effective-dated pay per staff profile: monthly, daily or hourly base in paise, and whether (and at what rate) extra hours are paid.';

comment on column public.staff_pay_rates.base_paise is 'Pay per month, per day or per hour in paise, by pay_type.';

comment on column public.staff_pay_rates.extra_hourly_paise is 'Own rate for extra hours in paise; null = derived from the pay (monthly: base / day divisor / standard hours; daily: base / standard hours; hourly: base).';

alter table "public"."staff_pay_rates"
  enable row level security;

create index ix_staff_pay_rates_arena on public.staff_pay_rates using btree (arena_id);

create index ix_staff_pay_rates_created_by on public.staff_pay_rates using btree (created_by);

create trigger t_same_arena
  before insert or update on public.staff_pay_rates
  for each row
  execute function public._assert_same_arena('staff_id', 'staff_profiles');

-- Pay is visible to payroll holders only (never on the floor).
-- No write policy: clients change data only through sync_push.
create policy "p_sel_staff_pay_rates" on "public"."staff_pay_rates"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids_with(ARRAY['payroll'::text]) as app_arena_ids_with)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_pay_rates"
  to "postgres", "service_role";

revoke all on table "public"."staff_pay_rates" from "anon";

revoke all on table "public"."staff_pay_rates" from "authenticated";

grant select on table "public"."staff_pay_rates" to "authenticated";
