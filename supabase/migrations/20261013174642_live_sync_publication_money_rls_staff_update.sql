set local check_function_bodies = off;

drop policy "p_sel_audit_log" on "public"."audit_log";

drop policy "p_sel_customers" on "public"."customers";

drop policy "p_sel_group_charges" on "public"."group_charges";

drop policy "p_sel_group_payments" on "public"."group_payments";

drop policy "p_sel_payments" on "public"."payments";

drop policy "p_sel_session_charges" on "public"."session_charges";

create or replace function private.app_arena_ids_with (
  p_any text[]
)
  returns SETOF uuid
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select arena_id from staff_profiles
   where user_id = auth.uid() and active and (role = 'owner' or perms && p_any);
$function$;

create or replace function public.op_staff_update (
  p_arena uuid,
  p       jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path to 'public'
  AS $function$
declare
  -- money / reports make a member "owner level" (app_is_owner, and the app's
  -- AppUser.isOwner). Only an owner-level member may hand them out or take them away.
  c_owner_perms constant text[] := array['money', 'reports'];
  v_user   uuid    := (p->>'user_id')::uuid;
  -- A field the op leaves out keeps its current value: a partial update must
  -- never wipe someone's permissions or silently reactivate them.
  v_perms  text[]  := case when p ? 'perms'
                        then array(select jsonb_array_elements_text(coalesce(p->'perms', '[]'::jsonb))) end;
  v_active boolean := (p->>'active')::boolean;
  v_role   text;
  v_old_perms  text[];
  v_old_active boolean;
  v_adj    boolean := false;
begin
  perform _need(p_arena, 'settings');
  select role, perms, active into v_role, v_old_perms, v_old_active from staff_profiles
    where arena_id = p_arena and user_id = v_user for update;
  if not found then raise exception 'not_found' using hint = 'staff'; end if;
  v_perms := coalesce(v_perms, v_old_perms);
  v_active := coalesce(v_active, v_old_active);
  perform _assert_known_perms(v_perms);

  if v_role = 'owner' then
    if not exists (select 1 from staff_profiles where arena_id = p_arena
         and user_id = auth.uid() and active and role = 'owner') then
      raise exception 'forbidden' using errcode = '42501', hint = 'only an owner can change an owner';
    end if;
    -- The server already treats a role owner as holding everything
    -- (app_has_perm); the app reads the perms list. Keep the list complete and
    -- the profile active so both agree and the arena always has an owner.
    -- Removing an owner is an operator action on the database, not an op.
    v_adj := not (v_perms @> _known_perms()) or not v_active;
    v_perms := _known_perms();
    v_active := true;
  else
    -- Nobody changes their own access: a Settings holder could otherwise grant
    -- themselves money/reports and become owner level.
    if v_user = auth.uid()
       and (not (v_perms @> v_old_perms and v_old_perms @> v_perms) or v_active <> v_old_active) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'you cannot change your own permissions';
    end if;
    -- Owner-level perms, and owner-level members, are managed by owners only.
    if not private.app_is_owner(p_arena)
       and (v_old_perms && c_owner_perms
            or ('money' = any(v_perms)) <> ('money' = any(v_old_perms))
            or ('reports' = any(v_perms)) <> ('reports' = any(v_old_perms))) then
      raise exception 'forbidden' using errcode = '42501',
        hint = 'only an owner can grant money or reports, or change an owner-level member';
    end if;
  end if;

  update staff_profiles set name = coalesce(nullif(btrim(p->>'name'), ''), name),
      perms = v_perms, active = v_active,
      sort_order = coalesce((p->>'sort_order')::int, sort_order),
      updated_at = statement_timestamp()
    where arena_id = p_arena and user_id = v_user;
  perform _assert_settings_holder(p_arena);
  -- adjusted = the device wrote something else: it refetches the staff list.
  return case when v_adj then '{"adjusted": true}'::jsonb else '{}'::jsonb end;
end;
$function$;

create policy "p_sel_audit_log" on "public"."audit_log"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['money'::text, 'reports'::text]) as
    app_arena_ids_with)));

create policy "p_sel_customers" on "public"."customers"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['start'::text, 'members'::text,
    'money'::text, 'reports'::text]) as app_arena_ids_with)));

create policy "p_sel_group_charges" on "public"."group_charges"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['bill'::text, 'money'::text,
    'reports'::text]) as app_arena_ids_with)));

create policy "p_sel_group_payments" on "public"."group_payments"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['bill'::text, 'money'::text,
    'reports'::text]) as app_arena_ids_with)));

create policy "p_sel_payments" on "public"."payments"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['bill'::text, 'money'::text,
    'reports'::text]) as app_arena_ids_with)));

create policy "p_sel_session_charges" on "public"."session_charges"
  for select
  to "authenticated"
  using
    ((arena_id in ( select private.app_arena_ids_with(ARRAY['bill'::text, 'money'::text,
    'reports'::text]) as app_arena_ids_with)));

alter publication "supabase_realtime" add table "public"."billing_policies";

alter publication "supabase_realtime" add table "public"."game_categories";

alter publication "supabase_realtime" add table "public"."game_controls";

alter publication "supabase_realtime" add table "public"."game_resources";

alter publication "supabase_realtime" add table "public"."group_extensions";

alter publication "supabase_realtime" add table "public"."holidays";

alter publication "supabase_realtime" add table "public"."rate_bands";

alter publication "supabase_realtime" add table "public"."rate_cards";

alter publication "supabase_realtime" add table "public"."session_extensions";

alter publication "supabase_realtime" add table "public"."staff_profiles";

comment on function "private"."app_arena_ids_with"(text[]) is 'Arena ids where the signed-in user is an active owner or holds any of the given permissions; the membership test of the RLS policies on money, customer and audit tables.';

revoke all on function "private"."app_arena_ids_with"(text[]) from public;

grant execute on function "private"."app_arena_ids_with"(text[]) to "authenticated";

revoke all on function "private"."app_arena_ids_with"(text[]) from "postgres";

grant execute on function "private"."app_arena_ids_with"(text[]) to "postgres";

grant execute on function "private"."app_arena_ids_with"(text[]) to "service_role";
