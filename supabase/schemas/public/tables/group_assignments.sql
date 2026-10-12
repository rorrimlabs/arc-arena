-- group_assignments — one player of a group on one station for a stretch of time
--
-- The group equivalent of a segment: the open row (ended_at null) is where that
-- player is now. Inserted by _group_place (op_group_create / add / switch);
-- closed by op_group_switch / end_player / end / void. Players of the SAME group
-- may share a station (same activity + game, controllers within capacity and
-- usable pads, checked in _group_assignable); trigger
-- assert_resource_free_for_assignment keeps out single segments and other groups.
create table "public"."group_assignments" (
  "id"               uuid                     not null default gen_random_uuid(),
  "arena_id"         uuid                     not null,
  "group_id"         uuid                     not null,
  "player_number"    integer                  not null,
  "player_label"     text,
  "idx"              integer                  not null,
  "resource_id"      uuid                     not null,
  "activity_code"    text                     not null,
  "game_id"          uuid,
  "controller_count" integer,
  "started_at"       timestamp with time zone not null,
  "ended_at"         timestamp with time zone,
  "request_id"       text,
  "created_at"       timestamp with time zone not null default now(),
  "sync_xid"         xid8                     not null default pg_current_xact_id(),
  constraint "group_assignments_arena_id_activity_code_fkey" foreign key (arena_id, activity_code)
    references public.activities(arena_id, code),
  constraint "group_assignments_arena_id_fkey" foreign key (arena_id) references public.arenas(id)
    on delete cascade,
  constraint "group_assignments_check" check (((ended_at IS NULL) OR (ended_at >= started_at))),
  -- 4 = controller port capacity of one station.
  constraint "group_assignments_controller_count_check"
    check (((controller_count >= 1) AND (controller_count <= 4))),
  constraint "group_assignments_game_id_fkey" foreign key (game_id) references public.games(id),
  constraint "group_assignments_pkey" primary key (id),
  constraint "group_assignments_player_number_check" check ((player_number > 0)),
  constraint "group_assignments_group_id_fkey" foreign key (group_id)
    references public.group_sessions(id) on delete cascade,
  constraint "group_assignments_resource_id_fkey" foreign key (resource_id)
    references public.resources(id)
);

comment on table public.group_assignments is 'Placement of one group player on one station, activity, game and controller count for a stretch of time; the open row is where the player is now.';

comment on column public.group_assignments.arena_id is 'Owning arena (tenant); RLS shows the row only to active members of this arena.';

comment on column public.group_assignments.player_number is 'Player''s number within the group (> 0); stable across switches.';

comment on column public.group_assignments.player_label is 'Display name for the player; carried over on a switch.';

comment on column public.group_assignments.idx is '0-based position of this assignment in the player''s own history (each switch or re-add + 1).';

comment on column public.group_assignments.resource_id is 'Station the player is on.';

comment on column public.group_assignments.activity_code is 'Activity business code (not uuid), tied to the arena''s catalog by the composite FK.';

comment on column public.group_assignments.controller_count is 'Controllers this player uses (1 to 4); equals the number of allocated pads when pads are tracked. Null when not applicable.';

comment on column public.group_assignments.started_at is 'When the player started on this station (UTC), as reported by the device.';

comment on column public.group_assignments.ended_at is 'When the player left this station (UTC); null = the open assignment.';

comment on column public.group_assignments.request_id is 'Legacy idempotency key from the pre-sync RPCs; sync ops leave it null (they are idempotent by sync_ops.op_id).';

comment on column public.group_assignments.sync_xid is 'Id of the transaction that last wrote the row (set by trigger sync_stamp); sync_pull change-feed cursor.';

alter table "public"."group_assignments"
  enable row level security;

create index ix_assignments_group on public.group_assignments using btree (group_id, idx);

create index ix_assignments_resource on public.group_assignments
  using btree (resource_id, started_at);

create index ix_group_assignments_sync on public.group_assignments using btree (arena_id, sync_xid);

-- Legacy request_id idempotency (pre-sync RPCs); sync ops leave request_id null.
create unique index ux_assignments_request on public.group_assignments
  using btree (arena_id, request_id)
  where (request_id is not null);

-- Foreign-key index (joins and cascading deletes).
create index ix_group_assignments_game_id on public.group_assignments using btree (game_id);

create index ix_group_assignments_activity on public.group_assignments using btree (arena_id, activity_code);

-- Opening an assignment locks the station row and raises resource_busy if an open
-- single segment or another group's open assignment is on it. Same-group sharing
-- is allowed here; its finer rules live in _group_assignable.
create trigger t_assignment_resource_free
  before insert or update of resource_id, ended_at on public.group_assignments
  for each row
  execute function public.assert_resource_free_for_assignment();

-- Change feed: stamp sync_xid on every write; record deletes as tombstones.
create trigger t_group_assignments_sync
  before insert or update on public.group_assignments
  for each row
  execute function public.sync_stamp();

create trigger t_group_assignments_tomb
  after delete on public.group_assignments
  for each row
  execute function public.sync_record_delete();

-- Referenced game, group and station must belong to this row's arena (cross_arena_reference, 0016).
create trigger t_same_arena
  before insert or update on public.group_assignments
  for each row
  execute function
    public._assert_same_arena('game_id', 'games', 'group_id', 'group_sessions', 'resource_id',
    'resources');

-- Members read their arenas' rows. No write policy: clients change data only through sync_push.
create policy "p_sel_group_assignments" on "public"."group_assignments"
  for select
  to authenticated
  using ((arena_id in ( select public.app_arena_ids() as app_arena_ids)));

grant delete, insert, maintain, references, select, trigger, truncate, update
  on table "public"."group_assignments"
  to "postgres", "service_role";

revoke all on table "public"."group_assignments" from "anon";

revoke all on table "public"."group_assignments" from "authenticated";

grant select on table "public"."group_assignments" to "authenticated";