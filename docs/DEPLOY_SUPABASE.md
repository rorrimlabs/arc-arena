# Hosted Supabase — deployment checklist (new DEVELOPMENT project)

Prepared 2026-10-11 (updated 2026-10-12 for 0016; 2026-10-14 for the generated
migrations after it: invitations, Realtime, the `private` schema, narrower
money/customer reads) from an audit of the migrations, RLS, grants, the
auth design and the mobile configuration. **Nothing added after 0015 has been
run against a hosted project, and the hosted state has not been re-verified
since 2026-10-12.** Every step that creates or changes anything hosted is
yours to do (or to approve explicitly). Read [SYNC.md](SYNC.md) for how sync
works.

This is a *development* hosted project: use it to prove two real phones on
different networks before a production project is created the same way.

---

## 0. Keys and secrets — what may go where

| Item | Kind | Where it may live | Never |
|---|---|---|---|
| Project URL (`https://<ref>.supabase.co`) | public | app build config (`dart_define.<env>.json`), docs | — |
| **Publishable key** (`sb_publishable_…`) or legacy **anon** key | public (it is shipped inside the app; RLS + `sync_push` checks are what protect data) | app build config; admin dashboard `apps/admin/src/environments/environment.production.ts` (filled at deploy time) | — |
| **Secret key** (`sb_secret_…`) / legacy **service_role** key | **SECRET — bypasses RLS** | password manager only. The `staff-admin` Edge Function gets it from the hosted function environment automatically; nothing else needs it | the app, the dashboard, the repo, `dart_define` files, CI logs, chat, screenshots |
| `staff-admin` function secrets `ADMIN_SITE_URL`, `ADMIN_ORIGINS` | config (URLs, not secret) | `supabase secrets set` | — |
| **Database password** | **SECRET** | password manager; typed at the `supabase link` / `db push` prompt | the repo, shell history, chat |
| JWT secret / signing keys | **SECRET** | stays in the dashboard | anywhere else |
| Supabase **personal access token** (CLI `supabase login`) | **SECRET** (acts as you, all projects) | the CLI's keychain entry | the repo, chat |
| SMTP credentials (if custom SMTP) | **SECRET** | dashboard only | anywhere else |

The app reads exactly two values in cloud mode: `AO_SUPABASE_URL` and
`AO_SUPABASE_ANON_KEY` (the publishable or anon key — the name is historical).
`dart_define*.json` files are git-ignored; only `dart_define.example.json`
(placeholders) is committed. A release build refuses local mode, a missing URL
or key, any non-https or development host, and any secret (`sb_secret_…`) or
`service_role` key ([RELEASE.md](RELEASE.md)). The dashboard's production build
likewise refuses a non-https or local URL and a secret/`service_role` key, and
shows "Setup needed" instead of the app while `environment.production.ts` is
empty.

## 1. What the audit found

| Area | Result |
|---|---|
| Migration order | `0001` … `0016`, then the generated `2026…` migrations (list in §4a), applied in filename order by `supabase db push`. 0013 renames the 0011 op functions to `_v1` and wraps them, 0014 tightens grants, 0015 closes the app's route to arena ownership, 0016 wraps four ops again (payments, staff, pad moves, stations) and adds same-arena triggers — order matters and is exactly the filename order. No step needs manual ordering. |
| Fresh-project compatibility | `0001`–`0016` apply cleanly on an empty database (verified by `supabase db reset --local` on the same Postgres 17 image); the generated migrations are applied on the local stack. Extensions: `pgcrypto` (already present on hosted — `if not exists` is a no-op), `btree_gist` (unused; 0014 moves it to `extensions`). `0001`–`0016` touch neither `auth`, `storage` nor `realtime`; the generated migrations add the `realtime.messages` policies and tables to the `supabase_realtime` publication. No migration inserts users or needs superuser beyond what `postgres` has on hosted. |
| `seed.sql` | Intentionally empty (arenas start with no catalog). `db push` does not run it unless `--include-seed` is passed — don't. The real arena is created by the owner's sign-up or once by `bootstrap_owner` (step 7). |
| Client write path | No table or view is writable by `anon`/`authenticated`; every change goes through `sync_push` (permission + rule checks per op). |
| RLS | Enabled on every public table; every policy is scoped to arena membership. Payment and charge rows also need `bill`, `money` or `reports`; customers `start`, `members`, `money` or `reports`; `audit_log` owner level; `staff_invites` has no client access. Views are not client-readable (views bypass RLS). The device feed (`sync_pull`) is unchanged: every active member's device still receives the arena's rows, payments and customers included (an open product decision). |
| Client API | Signed-in users can execute exactly: `sync_push`, `sync_pull`, `sync_fetch_entity`, `my_arenas`, `create_my_arena` (sign-up: confirmed logins, one arena each), `invite_member` / `accept_invite` / `revoke_invite` / `arena_invites` (invitations), `arena_staff` (owner's staff list with e-mails), `arena_sales` / `arena_sale` (owner's Sales screen), `arena_pricing` (owner's Pricing screen), `app_is_owner` (asserted by pgTAP test 13). `anon` can call nothing. `bootstrap_owner` is database-only; `invite_delivery_target` is `service_role` only (the Edge Function); `create_arena`, `add_staff_by_email` and `add_member_by_email` are dropped. Found and fixed in 0014: trigger functions still had Postgres' default EXECUTE grant (unreachable, but removed). |
| SECURITY DEFINER | All pin `search_path`. None in an exposed schema is executable by `anon` or `authenticated` (lints 0028/0029): the client API's definer bodies live in schema `private` (not exposed by the Data API) and `public` holds `security invoker` wrappers. Server-only definer functions (`op_*`, `_pr_*`, `bootstrap_owner`, …) stay in `public` without client EXECUTE. |
| Realtime | One private channel per arena (`arena:<arena uuid>`); `realtime.messages` policies admit only active members of that arena. Postgres Changes on 29 published tables (INSERT/UPDATE, RLS-filtered); a `sync` broadcast after committed ops. No business data in Realtime — events only trigger authorized pulls/refetches (SYNC.md "Read path"). |
| Role limits | Same as hosted defaults: `authenticated` 8 s statement timeout, 8 s lock timeout. The two-device suite runs under them through PostgREST. Pulls are paged at 2,000 rows; pushes at 50 ops. |
| Auth design | Per-person logins. A new arena owner registers on the admin dashboard and confirms the e-mail with a 6-digit code, then `create_my_arena` creates their one arena; the operator can also use `bootstrap_owner` (SQL editor). Everyone else (staff and co-owners) joins **only by accepting an invitation**: the owner invites from the dashboard's Users page, the `staff-admin` Edge Function (the only holder of the service-role key) runs `invite_member` as the caller and e-mails the link through Supabase Auth, and the invited, confirmed login accepts on the dashboard's `/accept-invite` page after choosing its own password (SYNC.md "Auth and roles"). No owner-set passwords, no linking of an existing login without consent. No service-role key anywhere in the app or repo. |
| Mobile — Android | **Fixed:** the release manifest had no `INTERNET` permission (only debug/profile did), so a release build could not reach Supabase at all. Debug builds now allow cleartext only for the local dev stack. Release builds are cloud-only and need the release key (RELEASE.md). |
| Mobile — iOS | No ATS exceptions; https works as is. Session (refresh token) stored in the Keychain via `flutter_secure_storage`, one entry per backend (`arena_ops.supabase.session@<host:port>`). |
| Settings that are NOT migrations | Everything under `[auth]` in `supabase/config.toml` applies to the LOCAL stack only. On hosted you set them in the dashboard (step 3), together with Realtime's "Allow public access" (step 3.7) and the `staff-admin` function and its secrets (step 7). |

Run `supabase/audit/security_audit.sql` after the push (step 5): it re-checks
grants, RLS, views and `search_path` on the hosted database. Its allowlist of
client functions predates the current client API (it still names
`add_staff_by_email`), so see step 5 for which `FAIL` rows to expect.

## 2. Create the project (dashboard)

1. Sign in at **supabase.com/dashboard** → your organization → **New project**.
2. **Name**: `arena-ops-dev` (keep "dev" in the name; production gets its own project later).
3. **Database password**: click *Generate a password*, then store it in your password manager **before** continuing. You will type it at the CLI prompt in step 4; it is never written to the repo.
4. **Region**: *South Asia (Mumbai)* — closest to the venue.
5. **Security options** (if shown): keep *Data API* enabled and exposing the `public` schema (the app uses PostgREST RPCs) — never `private`. Any "automatic RLS" option can stay on — the migrations enable RLS themselves.
6. Create the project and wait until it reports healthy.
7. **Project Settings → General**: note the **Reference ID** (`<ref>`).
8. **Project Settings → API Keys**: copy the **Project URL** and the **publishable key** (or the legacy **anon** key). Do **not** copy the secret / service_role key — nothing needs it.

## 3. Authentication settings (dashboard)

1. **Authentication → Sign In / Providers → Email**: enabled.
   * Keep the **Email provider itself ENABLED** — it is how everyone signs in with e-mail + password.
   * **Authentication → Sign In / Providers → User Signups → Allow new users to sign up**: **ON** — new arena owners register on the admin dashboard. A sign-up belongs to no arena until it confirms its e-mail and creates one (`create_my_arena`, one per login).
   * **Confirm email**: **ON**. The app asks for the 6-digit code, so:
     * **Authentication → Emails → Templates → Confirm signup**: replace the body with the one in `supabase/templates/confirmation.html` — it must contain `{{ .Token }}` (the default template only has a link the app cannot open).
     * **Project Settings → Authentication → SMTP**: set up your own SMTP sender. The built-in one delivers only to the project's team members, at a low rate, so real sign-ups would never get their code and invitations would never arrive.
   * **Attack protection**: turn on **CAPTCHA** (hCaptcha or Turnstile) once the app sends a captcha token — until then leave it off or sign-up fails. Keep the default sign-up rate limits.
   * **Secure password change**: ON. A person whose last sign-in is older than 24 h may be asked to sign out and back in before More → Change password succeeds.
2. **Authentication → Sign In / Providers → Anonymous sign-ins**: **OFF**.
3. **Authentication → Policies / Passwords** (wording varies): minimum length **10**, require letters and digits; enable **leaked-password protection** if your plan offers it.
4. **Authentication → URL Configuration**: **Site URL** = the admin dashboard's https URL; **Redirect URLs** must include `https://<dashboard>/accept-invite` **and** `https://<dashboard>/reset-password` (or simply `https://<dashboard>/**`). The sign-up confirmation uses a code, but the invitation and sign-in e-mails link to the dashboard's `/accept-invite` page, and the password-reset e-mail (Sign in → *Forgot your password?*) links to `/reset-password`. The dashboard asks for the redirect to its own address (`<the origin it is served from>/reset-password`); a redirect URL missing from this list makes Supabase send the person to the Site URL instead, where the link does nothing. The floor app needs no redirect URLs (no OAuth, no deep links); staff who forgot their password can reset it from the dashboard's sign-in page too.
   * **Authentication → Emails → Templates → Reset password**: the default template (a link, `{{ .ConfirmationURL }}`) works as is; change only the wording if you like. It needs the SMTP sender from step 1 like every other e-mail.
   * The reset link signs the person in, so **Secure password change** (step 1) does not get in the way: they set the new password right after a fresh sign-in.
   * Locally, `supabase/config.toml` already allows `http://127.0.0.1:4200/**` and `http://localhost:4200/**`; the reset e-mail shows up in Mailpit (`http://127.0.0.1:54434`, `[inbucket]` in `config.toml`).
5. Leave JWT expiry (3600 s) and refresh-token rotation at their defaults (they match the local stack the app was tested with). A Realtime revocation takes effect within the JWT expiry.
6. *(Optional, smaller surface)* **Integrations / Database → Extensions**: the app does not use GraphQL; you may disable `pg_graphql`.
7. **Realtime → Settings**: turn **off** "Allow public access" (private channels only). Both apps use private channels; this is a dashboard-only setting.

## 4. Apply the migrations (your terminal, from the repo root)

```bash
supabase login
```
Opens a browser to create a personal access token; the CLI keeps it in your keychain.

```bash
supabase link --project-ref <ref>
```
Prompts for the database password from step 2.3. This writes `supabase/.temp/project-ref` (git-ignored).

```bash
supabase db push --dry-run
```
For a new project: must list exactly `0001` … `0016` followed by the generated
migrations in §4a, in that order, and nothing else. (For the existing hosted
dev project, see §4a.)

```bash
supabase db push
```
Applies them. Do NOT add `--include-seed`.

```bash
supabase migration list --linked
```
Local and Remote columns must both show the same list.

Rules while linked:
* **Never** run `supabase db reset --linked` or `supabase test db --linked` (the pgTAP files insert users and fixtures).
* Every repo script (`tool/verify_all.sh`, `tool/sync_it.sh`, `tool/pricing_parity.sh`, the race scripts) targets the local Docker container only and refuses anything else; keep using them locally.
* Future schema changes: edit `supabase/schemas/` and generate the migration (CLAUDE.md, "Supabase — declarative schemas only"; never write one by hand), run `bash tool/verify_all.sh --with-it --with-psql` locally, then `supabase db push --dry-run` / `db push`.

## 4a. Bringing an already-deployed project up to date (0016 and after)

**Status 2026-10-14 (with the owner's approval): done on the hosted dev project
`ouxvtvlzhxddmqirmnxo`.** `0016` was already there; the 20 files from
`20261011202706` to `20261014065708` were pushed after the pre-checks below
passed (`verify_all.sh --with-it --with-psql`: no failures, no skips; drift check
clean; hosted publication empty). `supabase migration list --linked`: 36/36
match. `supabase db advisors --linked`: only `auth_leaked_password_protection`
(an Auth setting, §3). `staff-admin` deployed (`--no-verify-jwt`, no
`ADMIN_SITE_URL` yet: links use the dashboard's own address). The dashboard's
`environment.production.ts` holds the hosted URL and anon key. Still to do by
the owner: §3.4 redirect URLs (add `http://127.0.0.1:4200/**` and
`http://localhost:4200/**` while the dashboard runs locally against hosted),
custom SMTP (§3; without it Supabase e-mails only the project's team
members), leaked-password protection.

The hosted dev project was pushed with `0001` … `0015` on 2026-10-11. The list
below is what was pending before 2026-10-14, in push order:

1. `0016_integrity_and_authz` (money integrity, owner protection, pad-move
   permission, same-arena triggers, pinned `search_path` — see SYNC.md "Money
   and permission rules")
2. `20261011202706_drop_legacy_rpcs_flatten_ops`
3. `20261011203332_security_hardening`
4. `20261011203913_activity_fk_indexes`
5. `20261012105945_drift_check`
6. `20261012113650_self_serve_owner_signup`
7. `20261012165818_admin_arena_staff`
8. `20261012173542_add_member_by_email_roles`
9. `20261013050414_admin_sales`
10. `20261013090648_owner_built_catalog`
11. `20261013093743_admin_pricing_read`
12. `20261013105623_activity_remove`
13. `20261013142228_admin_catalog_details`
14. `20261013143752_floor_options_and_birth_year`
15. `20261013151140_enable_supabase_realtime_publication`
16. `20261013165054_security_definer_to_private_schema`
17. `20261013173321_staff_invitations`
18. `20261013174103_realtime_probe` (despite its name it holds the
    `realtime.messages` authorization policies and
    `private.can_use_arena_topic`; generated, so not renamed)
19. `20261013174642_live_sync_publication_money_rls_staff_update`
20. `20261014053857_game_lifecycle_delete_archive` (`game.delete` for never-used
    games; game names trimmed and unique ignoring case; an edit over a newer
    archive is refused; a deleted game is never re-created; `game.set_compat`
    keeps a note it is not sent)
21. `20261014065708_station_status_guard` (a station with a live session can no
    longer be taken out of service or removed through `resource.set_status` /
    `resource.upsert`; a `resource.upsert` without a status keeps it)
22. `20261014102347_sales_corrections_and_audit` (a void needs a reason; refunds
    allowed on a voided bill; waives audited; new server-only op
    `op_payment_correct` = `payment.correct`; `arena_sales` / `arena_sale` return
    the payments ledger, returning customer, player-minutes, void who/when,
    server receipt time and the audit history)
23. `20261014102752_payment_voided_before_balance` (a payment on a voided bill is
    refused as `voided` before the balance check)
24. `20261014105230_sales_correction_rows_not_refunds` (a method correction's
    rows are flagged and left out of the refunds total)

> **Verified read-only on 2026-10-14** with `supabase migration list --linked`:
> hosted has `0001` … `0016`. Item 1 above (`0016`) is therefore already applied;
> items 2–24 are not. `supabase functions list` shows no Edge Function deployed.

The first two 2026-10-14 migrations only replace function bodies and add one new
server-only function (`op_game_delete`, no client grant); no table changes,
nothing rewritten. Older floor-app builds keep working: they always send the
fields the new checks read as optional. A floor app on the new build also
needs these migrations: it sends `base_active` on game edits (an older server
ignores it) and drops games/station types the server deleted.

Items 22–24 (the staff handover audit, `STAFF_HANDOVER_AUDIT_2026-10-14.md`) also
only replace function bodies and add one server-only function
(`op_payment_correct`, no client grant); no table changes. Behaviour a client can
notice: a void without a reason is refused (`void_reason_required`; the dashboard
always sends one, the floor app never voids); a payment on a voided bill answers
`voided` instead of `overpayment`. Floor builds that do not send `waive_reason`
still end waived sessions (the reason is optional on the server). The dashboard
from this audit needs items 22–24 (it reads the new `arena_sales` fields and
sends `payment.correct`).

```bash
bash tool/verify_all.sh --with-it --with-psql
```
Everything locally first; it must end `NO FAILURES` with no `SKIP` line. Then
run the declarative drift check by hand (`supabase db schema declarative sync
--no-apply` must say "No schema changes found").

**Before pushing, check the hosted publication** (SQL Editor):
`select * from pg_publication_tables where pubname = 'supabase_realtime';` —
the publication migrations use `alter publication … add table` and fail if a
table is already published there.

```bash
supabase db push --dry-run
```
Must list exactly the files above, in that order, and nothing else.

```bash
supabase db push
```
`20261013165054_security_definer_to_private_schema` drops and recreates 31
policies and 11 RPCs inside its transaction: expect a brief PostgREST
schema-cache reload.

```bash
supabase migration list --linked
```
Both columns show the same list.

Right after the push, deploy `staff-admin` from this repo with its secrets
(step 7.4): earlier versions link logins through functions these migrations
drop. Then re-run step 5. `supabase db advisors --linked` should no longer
list `function_search_path_mutable` or any
`authenticated_security_definer_function_executable` /
`anon_security_definer_function_executable` row (locally, `supabase db
advisors --local --type all` returns none).

Accounts created on hosted dev by the old `staff-admin` (already confirmed,
password chosen by the owner) still exist: those people should reset their
password.

0016 is safe on live data: it adds checks to future writes only. Existing rows are
not re-validated, nothing is deleted or rewritten, and an op that was already
applied replays its stored answer. Devices on an older build keep working;
the only difference they see is that an overpayment, an over-refund or an
owner edit that would remove the owner is now refused or adjusted.

## 5. Verify the hosted database

1. **SQL Editor** → paste `supabase/audit/security_audit.sql` → **Run**. The script's allowlist predates the current client API, so on the current schema it reports `unexpected function callable by authenticated` for `create_my_arena`, `invite_member`, `accept_invite`, `revoke_invite`, `arena_invites`, `arena_staff`, `arena_sales`, `arena_sale` and `arena_pricing` — those are intended (section 1; pgTAP test 13 asserts the exact list). Any other `FAIL` row is real. The `REVIEW` rows must list exactly the 14 client functions in section 1 and the extensions.
2. **Advisors → Security Advisor**: review; there should be no RLS-disabled or exposed-view findings. On 2026-10-12 it also listed **Leaked password protection disabled** — turn it on under Authentication → Policies / Passwords if the plan offers it (step 3.3).
3. **Database → Tables**: `arenas` holds only arenas created by sign-up or `bootstrap_owner` (`seed.sql` is empty and is never pushed).
4. **SQL Editor**: `select tablename from pg_publication_tables where pubname = 'supabase_realtime' order by 1;` lists the 29 tables in `supabase/schemas/_cluster/publications.sql`.

## 6. Point a build at it (your machine)

Create `dart_define.hosted-dev.json` (git-ignored by `dart_define*.json`):

```json
{
  "AO_BACKEND": "supabase",
  "AO_SUPABASE_URL": "https://<ref>.supabase.co",
  "AO_SUPABASE_ANON_KEY": "<publishable or anon key from step 2.8>"
}
```

Then build or run with `--dart-define-from-file=dart_define.hosted-dev.json`:

```bash
flutter run --dart-define-from-file=dart_define.hosted-dev.json
```

Release builds are cloud-only and use the same kind of file
(`dart_define.prod.json`); an Android release also needs `android/key.properties`
— Gradle refuses the release otherwise, it never signs with the debug key
([RELEASE.md](RELEASE.md)).

**Admin dashboard:** fill `apps/admin/src/environments/environment.production.ts`
(intentionally empty in the repo) with the project URL and the publishable key
at deploy time. Production requires an https, non-local URL and a publishable
(`sb_publishable_…`) or legacy anon key; a secret or `service_role` key is
refused, and a build with no or bad configuration shows "Setup needed" instead
of the app. Serve it at the https URL you set as Site URL (step 3.4).

## 7. Bootstrap and the two-phone test

**Initial owner — either route:**

* **On the admin dashboard (self-serve, `/register`):** *Create an account* → e-mail + password → enter the 6-digit code from the e-mail → *Create your arena* (one arena per confirmed login). Needs steps 3.1's sign-up, confirmation, template and SMTP settings. Then continue at step 3 below.
* **By the operator (dashboard + database access):**

1. **Authentication → Users → Add user → Create new user**: your e-mail, a strong password (password manager), tick **Auto Confirm User**.
2. **SQL Editor** → run (your values):
   ```sql
   select bootstrap_owner('you@example.com', '404 Arena', 'Your Name');
   ```
   It creates an empty arena (the owner adds types, prices, stations, games and controllers on the dashboard) and makes that login its owner. It refuses an unknown or unconfirmed login. Running it again creates a *second* arena — run it once.
3. **Admin dashboard**: sign in → the arena starts **empty**: add station types, prices, stations, controllers, games and each game's per-station availability (game detail → *Stations*: Playable / Not installed / Not playable). A game playable on no station shows "No station", and the server refuses a session start for a game not marked playable on that station (`not_playable`). Then the **owner phone**: *Sign in* with that e-mail and password → the arena opens.

**Each staff member or co-owner (owner, any time) — by invitation only:**

4. **Deploy the Edge Function once** (your terminal): `supabase functions deploy staff-admin --no-verify-jwt` (it checks the caller's session itself). Set its secrets with `supabase secrets set`: `ADMIN_SITE_URL=https://<dashboard>` (base of the invitation link) and optionally `ADMIN_ORIGINS` (comma-separated origins allowed by CORS; unset = any origin, for local development only). Its service-role key comes from the hosted environment automatically. Needs steps 3.1 (SMTP) and 3.4 (URL configuration).
5. **Admin dashboard** → Users → **Invite user**: name, e-mail, role (staff, or owner for a co-owner — only an owner may invite an owner) and permissions. No password: the person receives the link by e-mail (valid 7 days; a newer invite to the same address replaces it). Pending invitations are listed on the Users page with **Withdraw**.
6. The person opens the link → the dashboard's `/accept-invite` page → a new login chooses its own password → accepted. Their confirmed e-mail must be the invited address. On their phone: *Sign in* with that e-mail and password.
7. To remove a staff member's access: admin dashboard → Users → **Deactivate** (their device returns to sign-in; their Realtime access ends within the JWT expiry). To remove the login entirely: Authentication → Users → delete.
8. Run the multi-device checks on **different networks** (one on mobile data):
   * start a session on one phone, see it on the other within about a second (Realtime), at worst on the next 10 s poll;
   * put one phone in airplane mode, take a payment and start a session there; reconnect; confirm it syncs (or, if the other phone took the same station meanwhile, that it is refused and shown under Sync → Needs attention, money included);
   * both phones try to use the same controller; exactly one succeeds;
   * end and bill a session; confirm the bill is accepted (no `price_mismatch`);
   * owner changes a price; staff phone shows it; a session started on the old price list still ends cleanly;
   * owner turns the staff member off; the staff phone returns to sign-in and keeps any unsent work on the device.
9. Record the results; only then plan the production project (same steps, separate project, separate keys).

## 8. Known limits that still apply after deployment

* **Session times are device-asserted.** The server re-prices every bill
  (migration 0013), but only for the times the device sent; it cannot prove an
  end time is true. Amount validation is therefore **not** protection against
  forged or wrong timestamps. Audit evidence: server receipt time and sender of
  every op (`sync_ops.created_at`, `user_id`). See SYNC.md.
* A Dart pricing change needs a matching migration and a green
  `tool/pricing_parity.sh` (SYNC.md "Changing pricing").
* No backups/PITR policy has been chosen for the hosted project (plan-dependent).
* Realtime only nudges: a missed event is caught by the floor app's 10 s poll
  and by the catch-up pull on reconnect (the dashboard refetches on reconnect).
* Every active member's device receives the arena's rows through `sync_pull`,
  payments and customers included, even where direct reads are narrower.
  Whether floor devices should hold less is an open product decision.
