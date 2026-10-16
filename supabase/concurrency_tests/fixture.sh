# Shared, self-cleaning fixture for the two-connection race scripts.
#
# Races need COMMITTED data (two connections must see it), so they cannot hide
# in a rolled-back transaction like pgTAP. Instead each script owns a
# dedicated arena (fixed id, the seed catalog) and owner account, created on
# start and deleted — with everything in it — on exit, even when the script
# fails. Nothing outside that arena is read or written.
#
# Usage (after setting ARENA, OWNER, CUSTOMER, LABEL):
#   source "$HERE/fixture.sh"; fixture_up; trap fixture_down EXIT
DB=supabase_db_arena_ops
PSQL() { docker exec -i "$DB" psql -U postgres -X -q -t -A -v ON_ERROR_STOP=1 "$@"; }

fixture_down() {
  PSQL <<SQL >/dev/null
delete from arenas where id = '$ARENA';            -- cascades: sessions, pads, ops…
delete from auth.users where id = '$OWNER';
SQL
}

fixture_up() {
  fixture_down   # a previous run that was killed before its trap
  PSQL <<SQL >/dev/null
insert into arenas(id, name) values ('$ARENA', '$LABEL (concurrency test)');
select _seed_arena_catalog('$ARENA');
insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
    created_at,updated_at,raw_app_meta_data,raw_user_meta_data,is_sso_user,is_anonymous)
  values ('00000000-0000-0000-0000-000000000000','$OWNER','authenticated','authenticated',
    '$LABEL@race.invalid','',now(),now(),now(),'{}','{}',false,false);
insert into staff_profiles(arena_id,user_id,name,role,perms,active)
  values ('$ARENA','$OWNER','Owner','owner',
    array['start','bill','discount','members','stations','money','reports','settings'],true);
insert into customers(id,arena_id,name) values ('$CUSTOMER','$ARENA','Race');
SQL
}
