-- op_customer_create — sync op 'customer.create': register a customer (phone clash is tolerated,
--   not refused).
--
-- Permission: start OR members.
-- Payload: id, name, phone?, notes, last_visit_at?, is_guest? (default false), created_at?
--   (default server time), birth_year? (1900 to the current year).
-- Checks / errors: invalid_birth_year (before 1900 or in the future).
-- Checks / errors: forbidden; duplicate (id reused, or a concurrent insert of the same phone). A
--   phone already on another customer is not an error: the row is kept without the phone and the
--   clash audited.
-- Writes: customers; audit_log (action 'duplicate_phone_on_sync') on a phone clash. Returns:
--   {adjusted: false} or {adjusted: true, phone_taken_by: <existing customer id>}.
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_customer_create (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_now timestamptz := statement_timestamp();
  v_phone text := nullif(btrim(p->>'phone'), '');
  v_other uuid;
begin
  if not (private.app_has_perm(p_arena, 'start') or private.app_has_perm(p_arena, 'members')) then
    raise exception 'forbidden' using errcode = '42501', hint = 'needs start or members';
  end if;
  -- A phone already in use (two devices registering the same person offline) must not sink
  -- the sessions that reference this customer: keep the row phone-less and audit the clash.
  if (p->>'birth_year') is not null and ((p->>'birth_year')::int < 1900
      or (p->>'birth_year')::int > extract(year from v_now at time zone 'Asia/Kolkata')) then
    raise exception 'invalid_birth_year' using hint = '1900 to this year';
  end if;
  if v_phone is not null then
    select id into v_other from customers where arena_id = p_arena and phone = v_phone;
  end if;
  insert into customers(id, arena_id, name, phone, notes, last_visit_at, is_guest, created_at, updated_at,
      birth_year)
    values ((p->>'id')::uuid, p_arena, p->>'name', case when v_other is null then v_phone end,
      p->>'notes', (p->>'last_visit_at')::timestamptz, coalesce((p->>'is_guest')::boolean, false),
      coalesce((p->>'created_at')::timestamptz, v_now), v_now, (p->>'birth_year')::smallint);
  if v_other is not null then
    insert into audit_log(arena_id, entity_type, entity_id, action, reason, after, created_by, created_at)
      values (p_arena, 'customer', (p->>'id')::uuid, 'duplicate_phone_on_sync',
        'phone already belongs to another customer', jsonb_build_object('phone', v_phone,
        'existing_customer_id', v_other), auth.uid(), v_now);
    return jsonb_build_object('adjusted', true, 'phone_taken_by', v_other);
  end if;
  return jsonb_build_object('adjusted', false);
end;
$function$;

comment on function public.op_customer_create(uuid, jsonb) is
  'Sync op customer.create: registers a customer, keeping the row without its phone when that phone already belongs to someone else.';

grant execute on function "public"."op_customer_create"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_customer_create"(uuid, jsonb) from public;

revoke all on function "public".op_customer_create(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_customer_create(p_arena uuid, p jsonb) from authenticated;
