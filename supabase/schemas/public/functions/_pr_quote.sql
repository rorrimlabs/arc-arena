-- _pr_quote(s, p_act, p_cc, p_start, p_end) — price one interval for one activity / controller count.
--
-- Port of PricingService.quote (domain/pricing/pricing_service.dart) on snapshot s. Returns {subtotal,
-- amount (cash-rounded), lines:[{start, end, band, played_seconds, billed_minutes, units, unit_minutes,
-- unit_price, amount}]}, or null when p_end < p_start, the activity is not in s, or a band has no rate.
-- Applies grace (free when <= grace_minutes), minimum charge (extends the billed end only), happy-hour
-- band splits, per-minute / block / VR-unit billing and the session-or-segment rounding scope.
-- Used by _pr_session_bill, _pr_sweep, _pr_group_bill and op_session_extend.
-- Server-only: not executable by anon/authenticated.
create or replace function public._pr_quote (
  s       jsonb,
  p_act   text,
  p_cc    integer,
  p_start timestamp with time zone,
  p_end   timestamp with time zone
)
  returns jsonb
  language plpgsql
  immutable
  set search_path to 'public', 'extensions'
  AS $function$
declare
  pol jsonb := _pr_policy(s);
  v_act jsonb;
  v_total bigint; v_min bigint; v_bend timestamptz;
  v_pts timestamptz[]; v_d date; v_hw tstzrange; v_mid timestamptz; v_band text;
  bs timestamptz[] := '{}'; be timestamptz[] := '{}'; bb text[] := '{}';
  n int := 0; i int;
  v_rate jsonb; v_price bigint; v_um int; v_us bigint; v_sec bigint; v_played bigint;
  v_num bigint; v_den bigint; v_billed bigint; v_units bigint; v_block int;
  v_sum_num bigint := 0; v_common bigint; v_mixed boolean := false; v_seg_sum bigint := 0;
  v_amount bigint; v_sub bigint;
  v_lines jsonb := '[]'::jsonb;
begin
  if p_end < p_start then return null; end if;
  select a into v_act from jsonb_array_elements(coalesce(s->'activities', '[]'::jsonb)) a
   where a->>'code' = p_act limit 1;
  if v_act is null then return null; end if;

  v_total := _pr_secs(p_start, p_end);
  -- Grace: free when under the grace period.
  if v_total <= (pol->>'grace_minutes')::int * 60 then
    return jsonb_build_object('subtotal', 0, 'amount', 0, 'lines', '[]'::jsonb);
  end if;
  -- Minimum charge: bill at least this much by extending the billed interval.
  v_min := (pol->>'minimum_charge_minutes')::int * 60;
  v_bend := case when v_total < v_min then p_start + make_interval(secs => v_min) else p_end end;

  -- Band segments: split at every happy-hour boundary, label by midpoint, merge.
  if not coalesce((v_act->>'happy_eligible')::boolean, false) then
    bs := array[p_start]; be := array[v_bend]; bb := array['standard']; n := 1;
  else
    v_pts := array[p_start, v_bend];
    v_d := _pr_ist_date(p_start);
    while v_d <= _pr_ist_date(v_bend) loop
      v_hw := _pr_happy(s, v_d);
      if v_hw is not null then
        if lower(v_hw) > p_start and lower(v_hw) < v_bend then v_pts := v_pts || lower(v_hw); end if;
        if upper(v_hw) > p_start and upper(v_hw) < v_bend then v_pts := v_pts || upper(v_hw); end if;
      end if;
      v_d := v_d + 1;
    end loop;
    select array_agg(distinct x order by x) into v_pts from unnest(v_pts) x;
    for i in 1 .. coalesce(array_length(v_pts, 1), 0) - 1 loop
      continue when v_pts[i + 1] <= v_pts[i];
      v_mid := v_pts[i] + (v_pts[i + 1] - v_pts[i]) / 2;
      v_hw := _pr_happy(s, _pr_ist_date(v_mid));
      v_band := case when v_hw is not null and v_hw @> v_mid then 'happy' else 'standard' end;
      if n > 0 and bb[n] = v_band then
        be[n] := v_pts[i + 1];
      else
        n := n + 1; bs[n] := v_pts[i]; be[n] := v_pts[i + 1]; bb[n] := v_band;
      end if;
    end loop;
  end if;

  for i in 1 .. n loop
    v_rate := _pr_rate(s, p_act, bb[i], p_cc);
    if v_rate is null and bb[i] = 'happy' then
      v_rate := _pr_rate(s, p_act, 'standard', p_cc);   -- happy → standard fallback
    end if;
    if v_rate is null then return null; end if;
    v_price := (v_rate->>'price_paise')::bigint;
    v_um := (v_rate->>'unit_minutes')::int;
    v_us := v_um::bigint * 60;
    v_sec := _pr_secs(bs[i], be[i]);
    -- Played time counts only the real [p_start, p_end]; the billed piece may run past p_end.
    v_played := case when least(p_end, be[i]) > greatest(p_start, bs[i])
                     then _pr_secs(greatest(p_start, bs[i]), least(p_end, be[i])) else 0 end;
    v_units := 0;
    if v_act->>'duration_model' = 'unit' then
      case pol->>'vr_unit_rounding'
        when 'prorate' then
          v_num := v_price * v_sec; v_den := v_us; v_billed := _pr_div(v_sec, 60);
        when 'nearest' then
          v_units := _pr_div(v_sec, v_us);
          v_num := v_price * v_units; v_den := 1; v_billed := v_units * v_um;
        else -- up
          v_units := (v_sec + v_us - 1) / v_us;
          v_num := v_price * v_units; v_den := 1; v_billed := v_units * v_um;
      end case;
    elsif pol->>'billing_unit' = 'per_minute' then
      v_num := v_price * v_sec; v_den := v_us; v_billed := _pr_div(v_sec, 60);
    else
      v_block := case pol->>'billing_unit' when 'block_15' then 15 when 'block_30' then 30 else 60 end;
      v_billed := (v_sec + 59) / 60;   -- whole minutes first
      v_billed := case when pol->>'block_rounding' = 'up' then _pr_ceil_step(v_billed, v_block)
                       else _pr_round_step(v_billed, v_block) end;
      v_num := v_price * v_billed; v_den := v_um;
    end if;

    -- Rounding scope: keep the exact numerator over a common denominator so 'session' scope
    -- rounds once (below); 'segment' scope or mixed denominators sum the per-line paise.
    v_common := coalesce(v_common, v_den);
    if v_den <> v_common then v_mixed := true; end if;
    v_sum_num := v_sum_num + v_num;
    v_amount := _pr_div(v_num, v_den);
    v_seg_sum := v_seg_sum + v_amount;
    v_lines := v_lines || jsonb_build_object('start', bs[i], 'end', be[i], 'band', bb[i],
      'played_seconds', v_played, 'billed_minutes', v_billed, 'units', v_units,
      'unit_minutes', v_um, 'unit_price', v_price, 'amount', v_amount);
  end loop;

  v_sub := case when pol->>'rounding_scope' = 'segment' or v_mixed then v_seg_sum
                else _pr_div(v_sum_num, coalesce(v_common, 1)) end;
  return jsonb_build_object('subtotal', v_sub,
    'amount', _pr_money(v_sub, (pol->>'money_rounding_paise')::int, pol->>'money_rounding_dir'),
    'lines', v_lines);
end;
$function$;

comment on function public._pr_quote(jsonb, text, integer, timestamp with time zone, timestamp with time zone) is 'Pricing: quotes one interval for one activity and controller count on a snapshot (lines, subtotal, cash-rounded amount); port of PricingService.quote.';

grant execute
  on function "public"."_pr_quote"(jsonb, text, integer, timestamp with time zone, timestamp
    with time zone)
  to "postgres", "service_role";

revoke all
  on function "public"."_pr_quote"(jsonb, text, integer, timestamp with time zone, timestamp
    with time zone)
  from public;

revoke all on function "public"._pr_quote(s jsonb, p_act text, p_cc integer, p_start timestamp with time zone, p_end timestamp with time zone) from anon;

revoke all on function "public"._pr_quote(s jsonb, p_act text, p_cc integer, p_start timestamp with time zone, p_end timestamp with time zone) from authenticated;
