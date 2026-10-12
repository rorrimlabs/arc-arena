create index ix_controller_allocations_activity on public.controller_allocations
  using btree (arena_id, activity_code);

create index ix_group_assignments_activity on public.group_assignments
  using btree (arena_id, activity_code);

create index ix_group_charges_activity on public.group_charges using btree (arena_id, activity_code);

create index ix_session_charges_activity on public.session_charges
  using btree (arena_id, activity_code);

create index ix_session_segments_activity on public.session_segments
  using btree (arena_id, activity_code);
