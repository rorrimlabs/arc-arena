-- sync_tombstones_id_seq — id generator for sync_tombstones
--
-- Owned by sync_tombstones.id (default nextval). Ids are only a surrogate key in
-- insertion order; the change feed orders tombstones by sync_xid. Server-only:
-- usable by postgres / service_role (and the SECURITY DEFINER trigger function
-- sync_record_delete), revoked from anon and authenticated.
create sequence "public"."sync_tombstones_id_seq" as bigint increment by 1 minvalue 1 maxvalue
  9223372036854775807 START with 1 cache 1 no cycle;

grant select, update, usage
  on sequence "public"."sync_tombstones_id_seq"
  to "postgres", "service_role";

revoke all on sequence "public"."sync_tombstones_id_seq" from "anon", "authenticated";
