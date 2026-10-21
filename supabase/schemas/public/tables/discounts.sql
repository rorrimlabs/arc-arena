-- discounts — owner-defined bill discounts: presets staff pick, and coupon codes staff type in
--
-- kind = preset (named, picked from a list, no code) or coupon (has a code the
-- customer gives). value_kind percent (value 1–100) or flat (value in paise).
-- A discount applies to a whole bill at checkout, on the part of the bill whose
-- station types are in activity_codes (empty = all), capped by
-- max_discount_paise and never above that part; min_bill_paise is checked on
-- the whole bill's subtotal. valid_from / valid_until bound when a bill may end
-- with it (a coupon's expiry); max_uses caps how many non-voided bills used it.
-- Applied discounts are recorded in bill_discounts (_discount_apply). Written by
-- op_discount_upsert / op_discount_set_active / op_discount_delete (settings).
create table "public"."discounts" (
  "id"                 uuid                     not null default gen_random_uuid(),
  "arena_id"           uuid                     not null,
  "kind"               text                     not null,
  "name"               text                     not null,
  "code"               text,
  "value_kind"         text                     not null,
  "value"              bigint                   not null,
  "max_discount_paise" bigint,
  "min_bill_paise"     bigint,
  "activity_codes"     text[]                   not null default '{}'::text[],
  "valid_from"         timestamp with time zone,
  "valid_until"        timestamp with time zone,
  "max_uses"           integer,
  "active"             boolean                  not null default true,
  "created_at"         timestamp with time zone not null default now(),
  "updated_at"         timestamp with time zone not null default now(),
  "sync_xid"           xid8                     not null default pg_current_xact_id(),
  constraint "discounts_pkey" primary key (id),
  constraint "discounts_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "discounts_kind_check" check ((kind = ANY (ARRAY['preset'::text, 'coupon'::text]))),
  -- A coupon has a code (A–Z, 0–9, - or _, 3–20); a preset has none.
  constraint "discounts_code_check"
    check ((((kind = 'coupon'::text) and (code ~ '^[A-Z0-9_-]{3,20}$'::text))
         or ((kind = 'preset'::text) and (code is null)))),
  constraint "discounts_name_check" check ((char_length(name) >= 1 and char_length(name) <= 40)),
  constraint "discounts_value_check"
    check ((((value_kind = 'percent'::text) and (value >= 1) and (value <= 100))
         or ((value_kind = 'flat'::text) and (value >= 1) and (value <= 100000000)))),
  constraint "discounts_max_discount_check"
    check (((max_discount_paise is null) or (max_discount_paise >= 1))),
  constraint "discounts_min_bill_check" check (((min_bill_paise is null) or (min_bill_paise >= 0))),
  constraint "discounts_valid_check"
    check (((valid_from is null) or (valid_until is null) or (valid_from < valid_until))),
  constraint "discounts_max_uses_check" check (((max_uses is null) or (max_uses >= 1)))
);

comment on table public.discounts is 'Owner-defined discounts: presets staff pick and coupon codes, percent or flat, with type scope, cap, minimum bill, validity window and use limit. Applied ones are recorded in bill_discounts.';

comment on column public.discounts.arena_id is 'Owning arena (tenant). RLS limits reads to arenas the caller is an active member of.';

comment on column public.discounts.kind is 'preset: picked by staff from a list; coupon: entered by its code.';

comment on column public.discounts.code is 'Coupon code, upper-case A–Z, 0–9, - or _ (3–20), unique per arena; null for a preset.';

comment on column public.discounts.value_kind is 'percent (value 1–100 % of the bill part in scope) or flat (value in paise).';

comment on column public.discounts.value is 'Percent (1–100) or paise, per value_kind.';

comment on column public.discounts.max_discount_paise is 'Upper limit of a percent discount in paise; null = no limit.';

comment on column public.discounts.min_bill_paise is 'Smallest bill subtotal (before discount) the discount may be used on; null = any.';

comment on column public.discounts.activity_codes is 'Station types (activities.code) whose charges the discount applies to; empty = the whole bill.';

comment on column public.discounts.valid_from is 'First instant a bill may end with this discount; null = no start.';

comment on column public.discounts.valid_until is 'Expiry: last instant a bill may end with this discount; null = never expires.';

comment on column public.discounts.max_uses is 'How many bills (voided ones excluded) may use it; null = unlimited.';

comment on column public.discounts.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); change-feed cursor for sync_pull.';

alter table "public"."discounts"
  enable row level security;

create unique index ux_discounts_code on public.discounts using btree (arena_id, code)
  where (code is not null);

create index ix_discounts_sync on public.discounts using btree (arena_id, sync_xid);

create trigger t_discounts_sync
  before insert or update on public.discounts
  for each row
  execute function public.sync_stamp();

create trigger t_discounts_tomb
  after delete on public.discounts
  for each row
  execute function public.sync_record_delete();

create trigger t_discounts_updated
  before update on public.discounts
  for each row
  execute function public.set_updated_at();

create policy "p_sel_discounts" on "public"."discounts"
  for select
  to authenticated
  using ((arena_id in ( select private.app_arena_ids_with(ARRAY['discount'::text, 'settings'::text, 'money'::text, 'reports'::text]) as app_arena_ids_with)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."discounts"
  to "postgres", "service_role";

revoke all on table "public"."discounts" from "anon";

revoke all on table "public"."discounts" from "authenticated";

grant select on table "public"."discounts" to "authenticated";
