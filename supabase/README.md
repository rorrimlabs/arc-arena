# supabase/ — arena_ops backend

Postgres (Supabase, PG 17) backend for the staff app's multi-device sync. Many arenas
(gaming centres) share one database; every row carries `arena_id`, and a signed-in
staff member only ever sees the arenas they are an active member of.

## Layout

| Path | What |
|---|---|
| `schemas/` | **Source of truth.** One file per object, the layout `supabase db schema declarative generate` writes. Each file holds the object plus its indexes, triggers, RLS policy, grants and `comment on` docs. |
| `schemas/public/tables/` | 34 tables |
| `schemas/public/views/` | 4 `sync_v_*` views used by the change feed (server-only) |
| `schemas/public/functions/` | Client API, sync ops, pricing, helpers, triggers (map below) |
| `schemas/public/default_privileges.sql` | New objects grant nothing to `anon` / `authenticated` |
| `schemas/_cluster/extensions/` | `pgcrypto`, `uuid-ossp`, `btree_gist` |
| `migrations/` | **Generated** by `supabase db schema declarative sync` — never edit. `0001`–`0016` are the original hand-written history. |
| `tests/` | pgTAP (`supabase test db --local`) |
| `seed.sql` | One owner-less dev arena with the starter catalog. Local only. |
| `concurrency_tests/` | `race_A.sql` / `race_B.sql`: two halves of a two-device race on one station |
| `audit/security_audit.sql` | Read-only report of the API surface (grants, SECURITY DEFINER, RLS) |
| `functions/staff-admin/` | Edge Function: an owner creates a staff login (already confirmed, starting password) from the admin dashboard. Verifies the caller with `app_is_owner`, then links with `add_member_by_email` (role staff or owner) **as the caller**; deletes the login again if linking fails. The only place the service-role key is used. |
| `templates/confirmation.html` | Sign-up e-mail with the 6-digit `{{ .Token }}` the admin dashboard asks for |
| `config.toml` | Local stack (ports 5443x). Sign-up on with e-mail code confirmation; pg-delta is on. |

## Changing the schema

1. Edit the end state in `schemas/` (the `create table`, the function body, the policy, the comment) — never `alter`.
2. `supabase db schema declarative sync --name <what_changed> --no-apply` → read the generated migration.
3. `supabase migration up --local`.
4. Run the same sync again: it must say **No schema changes found**.
5. `supabase test db --local` and `supabase db advisors --local --type all`.

Every new object file must revoke `anon` and `authenticated` explicitly (see any existing
file's last lines). pg-delta builds a shadow database where default privileges apply, so a
missing revoke shows up as a generated `grant … to anon` — reject that migration.

## Security model

| Role | Can do |
|---|---|
| `anon` | Nothing. No table, view, sequence or function privilege. |
| `authenticated` | `select` on tables, filtered by RLS to its own arenas (`arena_id in (select app_arena_ids())`). Execute only the client API below. No direct writes. |
| `service_role` / `postgres` | Everything (dashboard, SQL editor, `bootstrap_owner`). Never shipped in an app. |

- **One write path.** Devices push operations to `sync_push`; `_sync_apply` maps each op kind
  to an `op_*` function. Every `op_*` is `security definer` with a pinned `search_path`, checks
  the same permission the app checks (`_need(arena, perm)`), locks stations then pads in a fixed
  order, refuses stale writes, and is applied exactly once per `op_id` (`sync_ops` ledger).
- **The server prices money itself.** Bills and extensions are re-priced from the session's
  frozen price list (`_pr_*`) and refused on any one-paisa mismatch.
- **Permissions.** `staff_profiles.perms` ⊆ `start, bill, discount, members, stations, money,
  reports, settings`. `role = 'owner'` implies all. Holding `money` or `reports` makes a member
  *owner level* (`app_is_owner`, same rule as the app). Only owner-level members grant or remove
  `money`/`reports` or edit an owner-level member; nobody changes their own perms.
- **Two routes to ownership, none to staff access.** A new arena owner registers on the admin
  dashboard (`apps/admin`), confirms the e-mail with a 6-digit code, and calls
  `create_my_arena()` (confirmed logins only, one owned arena per login). The operator can also
  attach an owner with `bootstrap_owner()` (SQL editor, no limit). Both go through
  `_create_arena_with_owner`. A sign-up belongs to no arena until then. Owners add staff from the
  dashboard's Users screen, as staff or (owners only) as a co-owner: the `staff-admin` Edge
  Function creates the login and links it with `add_member_by_email`; `arena_staff()` lists
  owners and staff with e-mails; changes go through
  `sync_push` (`staff.update`). The floor app (`apps/mobile`) only signs in.
- **Sales are read through owner-level RPCs.** The dashboard's Sales screen lists closed bills
  (completed or voided sessions and groups, by close time, at most 93 days) with
  `arena_sales()` and opens one with `arena_sale()` (charge lines, payments, void record); both
  share the server-only `_sales()`. A void is a `session.void` / `group.void` op through
  `sync_push`; it keeps the bill and its payments (voiding never refunds).
- **History is append-only.** There are no delete policies; payments, moves, extensions and
  audit rows are only ever added.

## Tables

| Area | Tables |
|---|---|
| Arena & people | `arenas`, `staff_profiles`, `customers` |
| Floor setup | `resources` (stations), `activities`, `resource_activities`, `games`, `game_categories`, `game_resources`, `game_controls`, `controllers` (physical pads) |
| Pricing & rules | `rate_cards`, `rates`, `rate_bands`, `billing_policies`, `holidays`, `settings`, `pricing_catalog_history` |
| Single sessions | `sessions` → `session_segments`, `session_extensions`, `session_charges`, `payments` |
| Group sessions | `group_sessions` → `group_assignments`, `group_extensions`, `group_charges`, `group_payments` |
| Pads in use | `controller_allocations`, `controller_moves` |
| Bookings & audit | `bookings`, `audit_log` |
| Sync (server-only) | `sync_ops`, `sync_tombstones`; views `sync_v_arenas`, `sync_v_bookings`, `sync_v_rates`, `sync_v_resource_activities` |

Money is `bigint` paise; instants are `timestamptz` (UTC); business days are Asia/Kolkata.
`sync_xid` on every synced row is the id of the transaction that last wrote it (the change-feed
cursor), stamped by the `sync_stamp` trigger; deletes leave a row in `sync_tombstones`.

## Functions

| Group | Functions |
|---|---|
| **Client API** (`authenticated`) | `sync_push`, `sync_pull`, `sync_fetch_entity`, `my_arenas`, `add_staff_by_email`, `add_member_by_email`, `create_my_arena`, `arena_staff`, `arena_sales`, `arena_sale`, `app_arena_ids`, `app_has_perm`, `app_is_owner` |
| Operator only | `bootstrap_owner` |
| Sync ops (`op_*`, via `sync_push`) | sessions: `op_session_start/_reconfigure/_extend/_end/_void`; groups: `op_group_create/_add/_switch/_end_player/_extend/_end/_void`; money: `op_payment`; pads: `op_controller_move/_upsert/_set_status`; customers & bookings: `op_customer_*`, `op_booking_*`; settings: `op_game_*`, `op_resource_*`, `op_rate_*`, `op_policy_save`, `op_settings_save`, `op_holiday_*`, `op_staff_update` |
| Sync plumbing | `_sync_apply` (op kind → `op_*`), `_sync_sources` |
| Server pricing | `_pr_*` (port of the app's PricingService / SegmentBilling / GroupBilling), `_pricing_snapshot`, `_pricing_canon`, `_pricing_grace`, `_assert_snapshot`, `_price_mismatch` |
| Floor rules | `_need`, `_lock_resources`, `_lock_pads`, `_station_*`, `_group_*`, `_pad_*`, `_single_supply`, `_game_*`, `_booking_free`, `_free_pads_at`, `_usable_pads_at`, `_untracked_busy`, … |
| Triggers | `sync_stamp`, `sync_record_delete`, `set_updated_at`, `_assert_same_arena`, `assert_resource_free_for_segment`, `assert_resource_free_for_assignment`, `assert_controller_free_for_allocation` |

Each function file starts with a header explaining what it does, who calls it, what it
checks and which errors it raises; the same summary is stored as `comment on function`
(visible in Studio).

## Tests

| File | Covers |
|---|---|
| `00_schema_parity_test.sql` | Postgres is a superset of the app's Drift schema |
| `01_rls_authorization_test.sql` | Owner vs staff authorization, retired functions are gone |
| `07_sync_ops_test.sql` | `sync_push` → `op_*` → `sync_pull` end to end |
| `08_server_pricing_test.sql` | Server re-prices bills and refuses mismatches |
| `09_account_provisioning_test.sql` | `bootstrap_owner`, `create_my_arena` (confirmation, names, one-arena limit), `add_staff_by_email`, `add_member_by_email` (co-owners), `arena_staff` |
| `10_integrity_authz_test.sql` | Payments fit the bill, owner protection, pad-move permission |
| `11_ported_floor_test.sql` | Sessions, payments and groups through `sync_push` |
| `12_ported_pads_test.sql` | Controller allocation, borrowing and moves through `sync_push` |
| `13_security_hardening_test.sql` | Client surface, RLS shape, owner-level perms, integrity checks |
| `14_admin_sales_test.sql` | `arena_sales` / `arena_sale`: who may read, half-open close-time ranges, voided bills, group lines |

Every file creates and isolates its own arena and rolls back.
