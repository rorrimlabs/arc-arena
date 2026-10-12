-- op_group_end — sync op 'group.end': end an active group and store its final bill.
--
-- Permission: bill; plus discount when mark_waived.
-- Payload: group_id, ended_at, billed_amount_paise, mark_waived?, expected_assignment_ids[],
--   expected_scheduled_end_at; charges[] {id, assignment_id?, player_number?, charge_index,
--   band_code, activity_code, resource_id?, controller_count?, segment_start, segment_end,
--   played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise}.
-- Checks / errors: forbidden; not_found (hint group); not_active; stale (assignment ids or
--   scheduled end differ from what the device saw; compared with is distinct from, so a missing
--   expected value counts as stale); invalid_time (ended_at before a player's open assignment
--   started); price_mismatch (total differs from _pr_group_bill, or the charge rows differ from
--   its keys).
-- Writes: group_assignments.ended_at, controller_allocations.ended_at, group_charges,
--   group_sessions (completed, actual_ended_at, billed_amount_paise, payment_status). Returns:
--   {payment_status} ('waived', or derived from payments already taken).
-- Server-only: not executable by anon/authenticated; reached through sync_push.
create or replace function public.op_group_end (
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
  v_group uuid := (p->>'group_id')::uuid;
  v_ended timestamptz := (p->>'ended_at')::timestamptz;
  v_waive boolean := coalesce((p->>'mark_waived')::boolean, false);
  v_billed bigint := (p->>'billed_amount_paise')::bigint;
  v_end timestamptz; v_ids uuid[]; v_paid bigint; v_pay text; v_c jsonb;
  v_bill jsonb; v_keys text[];
begin
  perform _need(p_arena, 'bill');
  if v_waive then perform _need(p_arena, 'discount'); end if;
  perform _group_active(p_arena, v_group);
  select scheduled_end_at into v_end from group_sessions where id = v_group;
  select coalesce(array_agg(id), '{}') into v_ids from group_assignments where group_id = v_group;
  if not _same_ids(v_ids, _jsonb_uuids(p->'expected_assignment_ids'))
     or v_end is distinct from (p->>'expected_scheduled_end_at')::timestamptz then
    raise exception 'stale' using hint = 'the group was changed on another device';
  end if;
  update group_assignments set ended_at = v_ended where group_id = v_group and ended_at is null;
  update controller_allocations set ended_at = v_ended where group_id = v_group and ended_at is null;
  for v_c in select value from jsonb_array_elements(coalesce(p->'charges', '[]'::jsonb)) loop
    insert into group_charges(id, arena_id, group_id, assignment_id, player_number, charge_index,
        band_code, activity_code, resource_id, controller_count, segment_start, segment_end,
        played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise, created_at)
      values ((v_c->>'id')::uuid, p_arena, v_group, nullif(v_c->>'assignment_id','')::uuid,
        nullif(v_c->>'player_number','')::int, (v_c->>'charge_index')::int, v_c->>'band_code',
        v_c->>'activity_code', nullif(v_c->>'resource_id','')::uuid,
        nullif(v_c->>'controller_count','')::int, (v_c->>'segment_start')::timestamptz,
        (v_c->>'segment_end')::timestamptz, (v_c->>'played_minutes')::int,
        (v_c->>'billed_minutes')::int, (v_c->>'unit_minutes')::int,
        (v_c->>'unit_price_paise')::bigint, (v_c->>'amount_paise')::bigint, v_now);
  end loop;
  select coalesce(sum(amount_paise), 0) into v_paid from group_payments where group_id = v_group;
  -- Payments may already have been taken against the running bill.
  v_pay := case when v_waive then 'waived' else _payment_status(v_billed, v_paid) end;
  update group_sessions set status = 'completed', actual_ended_at = v_ended,
      billed_amount_paise = v_billed, payment_status = v_pay, updated_at = v_now
    where id = v_group;

  -- Server-side pricing (0013): re-price the bill from the stored assignments
  -- and refuse the op unless the total AND every charge row match exactly.
  if exists (select 1 from group_assignments where group_id = v_group and ended_at < started_at) then
    raise exception 'invalid_time' using hint = 'the end is before a player''s current system started';
  end if;
  v_bill := _pr_group_bill(v_group, v_ended);
  if (v_bill->>'total')::bigint is distinct from v_billed then
    perform _price_mismatch('bill', (v_bill->>'total')::bigint, v_billed);
  end if;
  select coalesce(array_agg(k order by k), '{}') into v_keys from (
    select _pr_charge_key(activity_code, resource_id, controller_count, band_code, segment_start,
      segment_end, played_minutes, billed_minutes, unit_minutes, unit_price_paise, amount_paise) k
      from group_charges where group_id = v_group) t;
  if v_keys <> array(select jsonb_array_elements_text(v_bill->'keys')) then
    raise exception 'price_mismatch' using hint = 'charge rows differ from the server''s bill';
  end if;
  return jsonb_build_object('payment_status', v_pay);
end;
$function$;

comment on function public.op_group_end(uuid, jsonb) is
  'Sync op group.end: closes an active group, stores its charges and bill, and refuses unless the server re-prices it to exactly the same money.';

grant execute on function "public"."op_group_end"(uuid, jsonb) to "postgres", "service_role";

revoke all on function "public"."op_group_end"(uuid, jsonb) from public;

revoke all on function "public".op_group_end(p_arena uuid, p jsonb) from anon;

revoke all on function "public".op_group_end(p_arena uuid, p jsonb) from authenticated;
