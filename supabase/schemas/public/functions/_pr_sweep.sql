-- _pr_sweep(v_snap, p_group, p_res, p_open_end, p_no_controllers, p_until?) — bill one station's group assignments.
--
-- Port of GroupBilling's sweepResource: splits the station's assignment windows (open ones end at
-- p_open_end; empty ones dropped) at every start / end and quotes each covered stretch at the summed
-- controller count (null when 0) with the activity of the first covering assignment in
-- (player_number, idx) order. p_no_controllers sweeps only assignments without controllers
-- (shared_controller_pool mode). p_until (the booked end when overtime is not charged) caps every
-- window. Unpriceable stretches are skipped. Returns {subtotal, keys}.
-- Server-only: not executable by anon/authenticated.
create or replace function public._pr_sweep (
  v_snap           jsonb,
  p_group          uuid,
  p_res            uuid,
  p_open_end       timestamp with time zone,
  p_no_controllers boolean,
  p_until          timestamp with time zone default null
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  ws timestamptz[]; we timestamptz[]; wc int[]; wa text[];
  v_pts timestamptz[]; i int; j int; s timestamptz; e timestamptz;
  v_cc int; v_act text; v_n int; q jsonb; v_started timestamptz;
  v_sub bigint := 0; v_keys text[] := '{}'; v_by jsonb := '{}'::jsonb;
begin
  select started_at into v_started from group_sessions where id = p_group;
  -- Windows in the device's list order (player, then index); empty ones dropped.
  select coalesce(array_agg(started_at order by player_number, idx), '{}'),
         coalesce(array_agg(least(coalesce(ended_at, p_open_end), coalesce(p_until, 'infinity'))
           order by player_number, idx), '{}'),
         coalesce(array_agg(controller_count order by player_number, idx), '{}'),
         coalesce(array_agg(activity_code order by player_number, idx), '{}')
    into ws, we, wc, wa
    from group_assignments
   where group_id = p_group and resource_id = p_res
     and (not p_no_controllers or controller_count is null)
     and least(coalesce(ended_at, p_open_end), coalesce(p_until, 'infinity')) > started_at;
  select array_agg(distinct x order by x) into v_pts
    from (select unnest(ws) as x union all select unnest(we)) t;
  for i in 1 .. coalesce(array_length(v_pts, 1), 0) - 1 loop
    s := v_pts[i]; e := v_pts[i + 1];
    continue when e <= s;
    v_n := 0; v_cc := 0; v_act := null;
    for j in 1 .. coalesce(array_length(ws, 1), 0) loop
      if ws[j] <= s and we[j] >= e then
        v_n := v_n + 1;
        v_cc := v_cc + coalesce(wc[j], 0);
        v_act := coalesce(v_act, wa[j]);
      end if;
    end loop;
    continue when v_n = 0;
    q := _pr_quote(v_snap, v_act, nullif(v_cc, 0), s, e, v_started);   -- rule judged at the group start
    continue when q is null;     -- misconfigured rate: excluded, as on the device
    v_sub := v_sub + (q->>'subtotal')::bigint;
    v_by := jsonb_set(v_by, array[v_act], to_jsonb(coalesce((v_by->>v_act)::bigint, 0) + (q->>'subtotal')::bigint));
    v_keys := v_keys || _pr_keys(q, v_act, p_res, nullif(v_cc, 0));
  end loop;
  return jsonb_build_object('subtotal', v_sub, 'keys', to_jsonb(v_keys), 'by_activity', v_by);
end;
$function$;

comment on function public._pr_sweep(jsonb, uuid, uuid, timestamp with time zone, boolean, timestamp with time zone) is 'Pricing: sweeps one station''s group assignments into constant-controller stretches and quotes each; port of GroupBilling sweepResource.';

grant execute
  on function "public"."_pr_sweep"(jsonb, uuid, uuid, timestamp with time zone, boolean, timestamp with time zone)
  to "postgres", "service_role";

revoke all
  on function "public"."_pr_sweep"(jsonb, uuid, uuid, timestamp with time zone, boolean, timestamp with time zone)
  from public;

revoke all on function "public"._pr_sweep(v_snap jsonb, p_group uuid, p_res uuid, p_open_end timestamp with time zone, p_no_controllers boolean, p_until timestamp with time zone) from anon;

revoke all on function "public"._pr_sweep(v_snap jsonb, p_group uuid, p_res uuid, p_open_end timestamp with time zone, p_no_controllers boolean, p_until timestamp with time zone) from authenticated;
