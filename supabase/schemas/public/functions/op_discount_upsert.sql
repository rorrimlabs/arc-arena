-- op_discount_upsert — sync op 'discount.upsert': create or edit a preset discount or a coupon.
--
-- Permission: settings.
-- Payload: id, kind ('preset' | 'coupon'), name, code (coupon only; upper-cased), value_kind
--   ('percent' | 'flat'), value (percent 1–100 or paise), max_discount_paise?, min_bill_paise?,
--   activity_codes[]? (empty = whole bill), valid_from?, valid_until? (expiry), max_uses?, active?.
-- Bills already discounted keep their own copy (bill_discounts), so edits never change them.
-- Checks / errors: forbidden; not_found (hint discount: the id belongs to another arena);
--   invalid_name (1–40 characters); invalid_code (coupon code not 3–20 of A–Z, 0–9, - or _);
--   invalid_discount (value, cap, minimum, use limit or dates out of range); kind_locked
--   (switching preset ↔ coupon once used); unknown_type (hint: an activity code the arena does
--   not have); duplicate (code already used by another coupon).
-- Writes: discounts. Returns: {}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_discount_upsert (
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
  v_kind  text := p->>'kind';
  v_name  text := btrim(coalesce(p->>'name', ''));
  v_code  text := nullif(upper(btrim(coalesce(p->>'code', ''))), '');
  v_vkind text := p->>'value_kind';
  v_value bigint := (p->>'value')::bigint;
  v_cap   bigint := nullif(p->>'max_discount_paise', '')::bigint;
  v_min   bigint := nullif(p->>'min_bill_paise', '')::bigint;
  v_uses  int := nullif(p->>'max_uses', '')::int;
  v_from  timestamptz := nullif(p->>'valid_from', '')::timestamptz;
  v_until timestamptz := nullif(p->>'valid_until', '')::timestamptz;
  v_codes text[] := array(select distinct upper(btrim(x)) from jsonb_array_elements_text(
                          coalesce(p->'activity_codes', '[]'::jsonb)) x order by 1);
  v_old   discounts%rowtype;
  v_bad   text;
begin
  perform _need(p_arena, 'settings');
  if exists (select 1 from discounts where id = v_id and arena_id <> p_arena) then
    raise exception 'not_found' using hint = 'discount';
  end if;
  if v_kind is null or v_kind not in ('preset', 'coupon') then
    raise exception 'invalid_discount' using hint = 'kind';
  end if;
  if char_length(v_name) not between 1 and 40 then
    raise exception 'invalid_name' using hint = '1–40 characters';
  end if;
  if v_kind = 'coupon' and (v_code is null or v_code !~ '^[A-Z0-9_-]{3,20}$') then
    raise exception 'invalid_code' using hint = '3–20 of A–Z, 0–9, - or _';
  end if;
  if v_kind = 'preset' then v_code := null; end if;
  if v_value is null or not ((v_vkind = 'percent' and v_value between 1 and 100)
                             or (v_vkind = 'flat' and v_value between 1 and 100000000))
     or coalesce(v_cap, 1) < 1 or coalesce(v_min, 0) < 0 or coalesce(v_uses, 1) < 1
     or (v_from is not null and v_until is not null and v_from >= v_until) then
    raise exception 'invalid_discount';
  end if;
  select c into v_bad from unnest(v_codes) c
   where not exists (select 1 from activities where arena_id = p_arena and code = c) limit 1;
  if v_bad is not null then raise exception 'unknown_type' using hint = v_bad; end if;

  select * into v_old from discounts where id = v_id and arena_id = p_arena for update;
  if found and v_old.kind <> v_kind and exists (select 1 from bill_discounts where discount_id = v_id) then
    raise exception 'kind_locked' using hint = v_old.kind;
  end if;

  insert into discounts(id, arena_id, kind, name, code, value_kind, value, max_discount_paise,
      min_bill_paise, activity_codes, valid_from, valid_until, max_uses, active)
    values (v_id, p_arena, v_kind, v_name, v_code, v_vkind, v_value,
      case when v_vkind = 'percent' then v_cap end, v_min, v_codes, v_from, v_until, v_uses,
      coalesce((p->>'active')::boolean, true))
  on conflict (id) do update set
    kind = excluded.kind, name = excluded.name, code = excluded.code,
    value_kind = excluded.value_kind, value = excluded.value,
    max_discount_paise = excluded.max_discount_paise, min_bill_paise = excluded.min_bill_paise,
    activity_codes = excluded.activity_codes, valid_from = excluded.valid_from,
    valid_until = excluded.valid_until, max_uses = excluded.max_uses, active = excluded.active,
    updated_at = statement_timestamp()
  where discounts.arena_id = p_arena;
  return '{}'::jsonb;
end;
$function$;

comment on function public.op_discount_upsert(uuid, jsonb) is
  'Sync op discount.upsert: creates or edits a preset discount or a coupon (value, scope, cap, minimum, validity, use limit).';

grant execute on function "public"."op_discount_upsert"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_discount_upsert"(uuid, jsonb) from public;

revoke all on function "public".op_discount_upsert(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_discount_upsert(p_arena uuid, p jsonb) from authenticated;
