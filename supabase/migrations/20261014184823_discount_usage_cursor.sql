set local check_function_bodies = off;

drop function "private"."arena_discount_usage"(uuid, uuid, integer, timestamp with time zone);

drop function "public"."arena_discount_usage"(uuid, uuid, integer, timestamp with time zone);

create or replace function private.arena_discount_usage (
  p_arena    uuid,
  p_discount uuid,
  p_limit    integer default 40,
  p_cursor   text    default null::text
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path to 'public'
  AS $function$
declare
  v_limit int := least(greatest(coalesce(p_limit, 40), 1), 100);
  v_rows  jsonb;
  v_at    timestamptz := nullif(split_part(coalesce(p_cursor, ''), '|', 1), '')::timestamptz;
  v_id    uuid := nullif(split_part(coalesce(p_cursor, ''), '|', 2), '')::uuid;
begin
  if not private.app_is_owner(p_arena) then
    raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can read sales';
  end if;
  if not exists (select 1 from discounts where id = p_discount and arena_id = p_arena) then
    raise exception 'not_found' using hint = 'discount';
  end if;

  select coalesce(jsonb_agg(x.j || jsonb_build_object('cursor', x.at::text || '|' || x.id)
                            order by x.at desc, x.id desc), '[]'::jsonb) into v_rows
    from (select d.id, d.applied_at as at, jsonb_build_object(
              'bill_id', coalesce(d.session_id, d.group_id),
              'kind', case when d.session_id is not null then 'single' else 'group' end,
              'at', d.applied_at, 'customer', c.name,
              'billed_paise', coalesce(s.billed_amount_paise, g.billed_amount_paise),
              'amount_paise', d.amount_paise, 'base_paise', d.base_paise,
              'status', coalesce(s.status, g.status), 'by', sp.name) as j
            from bill_discounts d
            left join sessions s on s.id = d.session_id
            left join group_sessions g on g.id = d.group_id
            left join customers c on c.id = coalesce(s.customer_id, g.primary_customer_id)
            left join staff_profiles sp on sp.arena_id = d.arena_id and sp.user_id = d.applied_by
           where d.arena_id = p_arena and d.discount_id = p_discount
             and (v_at is null or (d.applied_at, d.id) < (v_at, coalesce(v_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
           order by d.applied_at desc, d.id desc
           limit v_limit + 1) x;

  return jsonb_build_object(
    'uses', (select count(*) from bill_discounts where discount_id = p_discount),
    'active_uses', (select count(*) from bill_discounts d
                      left join sessions s on s.id = d.session_id
                      left join group_sessions g on g.id = d.group_id
                     where d.discount_id = p_discount and coalesce(s.status, g.status) <> 'voided'),
    'rows', (select coalesce(jsonb_agg(r - 'cursor' order by n), '[]'::jsonb)
               from jsonb_array_elements(v_rows) with ordinality x(r, n) where n <= v_limit),
    'next', case when jsonb_array_length(v_rows) > v_limit
                 then v_rows->(v_limit - 1)->>'cursor' end);
end;
$function$;

create or replace function public.arena_discount_usage (
  p_arena    uuid,
  p_discount uuid,
  p_limit    integer default 40,
  p_cursor   text    default null::text
)
  returns jsonb
  language sql
  stable
  set search_path to ''
  AS $function$
  select private.arena_discount_usage(p_arena, p_discount, p_limit, p_cursor);
$function$;

comment on function "private"."arena_discount_usage"(uuid, uuid, integer, text) is
  'Client API (owner level): the bills a preset discount or coupon was used on, newest first, paged by an (applied time, id) cursor, with use counts.';

comment on function "public"."arena_discount_usage"(uuid, uuid, integer, text) is
  'Client API (owner level): the bills a preset discount or coupon was used on, newest first, paged by an (applied time, id) cursor, with use counts.';

revoke all on function "private"."arena_discount_usage"(uuid, uuid, integer, text) from public;

grant execute
  on function "private"."arena_discount_usage"(uuid, uuid, integer, text)
  to "authenticated", "postgres", "service_role";

revoke all on function "public"."arena_discount_usage"(uuid, uuid, integer, text) from public;

grant execute
  on function "public"."arena_discount_usage"(uuid, uuid, integer, text)
  to "authenticated", "postgres", "service_role";
