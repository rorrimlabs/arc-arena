-- pay_policies — the arena's pay rules, from a date (append-only, effective-dated)
--
-- policy is validated by _pay_policy_settings: pay period, day divisor, absent / LOP / half-day
-- factors, the late rule, the extra-hours multiplier, daily staff on holidays. A salary run uses
-- the row in force on its period_start (_pay_policy); with no row, the defaults apply.
create table "public"."pay_policies" (
  "id"             uuid                     not null,
  "arena_id"       uuid                     not null,
  "effective_from" date                     not null,
  "policy"         jsonb                    not null,
  "created_by"     uuid                     not null,
  "created_at"     timestamp with time zone not null default now(),
  constraint "pay_policies_arena_id_effective_from_key" unique (arena_id, effective_from),
  constraint "pay_policies_arena_id_fkey" foreign key (arena_id) references public.arenas(id) on delete cascade,
  constraint "pay_policies_created_by_fkey" foreign key (created_by) references auth.users(id),
  constraint "pay_policies_pkey" primary key (id)
);

comment on table public.pay_policies is 'Effective-dated pay rules per arena (period, divisor, deduction factors, late rule, extra-hours multiplier).';

alter table "public"."pay_policies"
  enable row level security;

create index ix_pay_policies_created_by on public.pay_policies using btree (created_by);

-- Payroll holders only.
-- No write policy: clients change data only through sync_push.
create policy "p_sel_pay_policies" on "public"."pay_policies"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids_with(ARRAY['payroll'::text]) as app_arena_ids_with)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."pay_policies"
  to "postgres", "service_role";

revoke all on table "public"."pay_policies" from "anon";

revoke all on table "public"."pay_policies" from "authenticated";

grant select on table "public"."pay_policies" to "authenticated";
