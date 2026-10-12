-- _assert_same_arena() — trigger: cross-table references must stay inside the row's arena
--
-- BEFORE INSERT OR UPDATE row trigger (t_same_arena) on tables that reference
-- other arena-scoped rows. Trigger arguments are (column, table) pairs, e.g.
-- _assert_same_arena('booking_id', 'bookings', 'customer_id', 'customers').
-- For each non-null id it checks that <table> has that id with the same
-- arena_id; an UPDATE that changes neither the column nor arena_id is skipped.
-- Raises 'cross_arena_reference' (23503). Not SECURITY DEFINER.
-- Server-only: not executable by anon/authenticated.
create or replace function public._assert_same_arena()
  returns trigger
  language plpgsql
  set search_path to 'public'
  AS $function$
declare
  i int := 0;
  v_new jsonb := to_jsonb(new);
  v_old jsonb := case when tg_op = 'UPDATE' then to_jsonb(old) end;
  v_col text; v_tab text; v_id uuid; v_ok boolean;
begin
  while i < tg_nargs loop
    v_col := tg_argv[i];
    v_tab := tg_argv[i + 1];
    i := i + 2;
    v_id := nullif(v_new->>v_col, '')::uuid;
    continue when v_id is null;
    continue when v_old is not null and (v_old->>v_col) is not distinct from (v_new->>v_col)
                  and (v_old->>'arena_id') = (v_new->>'arena_id');
    execute format('select exists (select 1 from %I where id = $1 and arena_id = $2)', v_tab)
      into v_ok using v_id, (v_new->>'arena_id')::uuid;
    if not v_ok then
      raise exception 'cross_arena_reference' using errcode = '23503',
        hint = tg_table_name || '.' || v_col || ' must belong to the same arena';
    end if;
  end loop;
  return new;
end;
$function$;

comment on function public._assert_same_arena() is 'Trigger (t_same_arena): for each (column, table) pair given as trigger arguments, refuse a reference to a row of another arena with cross_arena_reference.';

grant execute on function "public"."_assert_same_arena"() to "postgres", "service_role";

revoke all on function "public"."_assert_same_arena"() from public;

revoke all on function "public"._assert_same_arena() from anon;

revoke all on function "public"._assert_same_arena() from authenticated;
