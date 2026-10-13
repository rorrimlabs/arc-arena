set local check_function_bodies = off;

create or replace function private.can_use_arena_topic (
  p_topic text
)
  returns boolean
  language sql
  stable
  security definer
  set search_path to 'public'
  AS $function$
  select case
    when p_topic ~ '^arena:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then exists (select 1 from staff_profiles
                  where user_id = auth.uid() and active and arena_id = substr(p_topic, 7)::uuid)
    else false
  end;
$function$;

create policy "arena_members_receive" on "realtime"."messages"
  for select
  to "authenticated"
  using
    (((extension = ANY (ARRAY['broadcast'::text, 'presence'::text])) AND
    private.can_use_arena_topic(( select realtime.topic() as topic))));

create policy "arena_members_send" on "realtime"."messages"
  for insert
  to "authenticated"
  with
    check
    (((extension = 'broadcast'::text) AND private.can_use_arena_topic(( SELECT realtime.topic() AS
    topic))));

comment on function "private"."can_use_arena_topic"(text) is 'True when the topic is arena:<uuid> and the caller is an active member of that arena. Used by the realtime.messages policies (private channels).';

revoke all on function "private"."can_use_arena_topic"(text) from public;

grant execute on function "private"."can_use_arena_topic"(text) to "authenticated";

revoke all on function "private"."can_use_arena_topic"(text) from "postgres";

grant execute on function "private"."can_use_arena_topic"(text) to "postgres";

grant execute on function "private"."can_use_arena_topic"(text) to "service_role";
