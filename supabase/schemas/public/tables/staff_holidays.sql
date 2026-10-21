-- staff_holidays — the arena's holidays for staff (separate from pricing's holidays)
--
-- A staff holiday is a day off for everyone, paid unless paid = false; work done on it counts
-- entirely as extra hours (OWNER_CONFIRMATION S2). Kept apart from public.holidays, which is
-- part of the pricing snapshot. Written by op_staff_holiday_upsert / op_staff_holiday_delete
-- (needs settings).
create table "public"."staff_holidays" (
  "id"         uuid                     not null default gen_random_uuid(),
  "arena_id"   uuid                     not null,
  "day"        date                     not null,
  "name"       text                     not null,
  "paid"       boolean                  not null default true,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  constraint "staff_holidays_arena_id_day_key" unique (arena_id, day),
  constraint "staff_holidays_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "staff_holidays_pkey" primary key (id)
);

comment on table public.staff_holidays is 'Staff holidays per arena (IST days off for everyone, paid by default); separate from the pricing holidays.';

comment on column public.staff_holidays.paid is 'Whether the day is paid (monthly staff are never docked for it; daily staff are paid for it when the pay rules say so).';

alter table "public"."staff_holidays"
  enable row level security;

create trigger t_staff_holidays_updated
  before update on public.staff_holidays
  for each row
  execute function public.set_updated_at();

-- Every member sees the holidays.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_staff_holidays" on "public"."staff_holidays"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."staff_holidays"
  to "postgres", "service_role";

revoke all on table "public"."staff_holidays" from "anon";

revoke all on table "public"."staff_holidays" from "authenticated";

grant select on table "public"."staff_holidays" to "authenticated";
