# Hosted Supabase — deployment checklist (new DEVELOPMENT project)

Prepared 2026-10-11 from an audit of migrations 0001–0014, RLS, grants, the
auth design and the mobile configuration. **Nothing here has been run against a
hosted project.** Every step that creates or changes anything hosted is
yours to do (or to approve explicitly). Read [SYNC.md](SYNC.md) for how sync
works.

This is a *development* hosted project: use it to prove two real phones on
different networks before a production project is created the same way.

---

## 0. Keys and secrets — what may go where

| Item | Kind | Where it may live | Never |
|---|---|---|---|
| Project URL (`https://<ref>.supabase.co`) | public | app build config (`dart_define.<env>.json`), docs | — |
| **Publishable key** (`sb_publishable_…`) or legacy **anon** key | public (it is shipped inside the app; RLS + `sync_push` checks are what protect data) | app build config | — |
| **Secret key** (`sb_secret_…`) / legacy **service_role** key | **SECRET — bypasses RLS** | password manager only; not needed by anything in this repo | the app, the repo, `dart_define` files, CI logs, chat, screenshots |
| **Database password** | **SECRET** | password manager; typed at the `supabase link` / `db push` prompt | the repo, shell history, chat |
| JWT secret / signing keys | **SECRET** | stays in the dashboard | anywhere else |
| Supabase **personal access token** (CLI `supabase login`) | **SECRET** (acts as you, all projects) | the CLI's keychain entry | the repo, chat |
| SMTP credentials (if custom SMTP) | **SECRET** | dashboard only | anywhere else |

The app reads exactly two values in cloud mode: `AO_SUPABASE_URL` and
`AO_SUPABASE_ANON_KEY` (the publishable or anon key — the name is historical).
`dart_define*.json` files are git-ignored; only `dart_define.example.json`
(placeholders) is committed. A release build refuses any non-https or
loopback URL.

## 1. What the audit found

| Area | Result |
|---|---|
| Migration order | `0001` … `0014`, applied in filename order by `supabase db push`. 0013 renames the 0011 op functions to `_v1` and wraps them, 0014 tightens grants — order matters and is exactly the filename order. No step needs manual ordering. |
| Fresh-project compatibility | Applies cleanly on an empty database (verified by `supabase db reset --local` on the same Postgres 17 image). Extensions: `pgcrypto` (already present on hosted — `if not exists` is a no-op), `btree_gist` (unused; 0014 moves it to `extensions`). No migration touches `auth`, `storage` or `realtime`, inserts users, or needs superuser beyond what `postgres` has on hosted. |
| `seed.sql` | **Do not apply to hosted.** It creates a dev arena with no owner. `db push` does not run it unless `--include-seed` is passed — don't. Real arenas are created from the app (`create_arena`). |
| Client write path | No table or view is writable by `anon`/`authenticated`; every change goes through `sync_push` (permission + rule checks per op). |
| RLS | Enabled on every public table; every policy is scoped to arena membership. Views are not client-readable (views bypass RLS). |
| Client API | Signed-in users can call only: `sync_push`, `sync_pull`, `sync_fetch_entity`, `my_arenas`, `create_arena`, `add_staff_by_email`, and four read-only membership helpers. `anon` can call nothing. Found and fixed in 0014: trigger functions still had Postgres' default EXECUTE grant (unreachable, but removed). |
| SECURITY DEFINER | All pin `search_path`. |
| Role limits | Same as hosted defaults: `authenticated` 8 s statement timeout, 8 s lock timeout. The two-device suite runs under them through PostgREST. Pulls are paged at 2,000 rows; pushes at 50 ops. |
| Auth design | Per-person accounts; staff sign up themselves and an owner adds the e-mail (`add_staff_by_email`); no service-role key anywhere in the app or repo. |
| Mobile — Android | **Fixed:** the release manifest had no `INTERNET` permission (only debug/profile did), so a release build could not reach Supabase at all. Debug builds now allow cleartext only for the local dev stack. |
| Mobile — iOS | No ATS exceptions; https works as is. Session (refresh token) stored in the Keychain via `flutter_secure_storage`. |
| Settings that are NOT migrations | Everything under `[auth]` in `supabase/config.toml` applies to the LOCAL stack only. On hosted you set them in the dashboard (step 3). |

Run `supabase/audit/security_audit.sql` after the push (step 5): it re-checks
all of the above on the hosted database. It must return no `FAIL` row.

## 2. Create the project (dashboard)

1. Sign in at **supabase.com/dashboard** → your organization → **New project**.
2. **Name**: `arena-ops-dev` (keep "dev" in the name; production gets its own project later).
3. **Database password**: click *Generate a password*, then store it in your password manager **before** continuing. You will type it at the CLI prompt in step 4; it is never written to the repo.
4. **Region**: *South Asia (Mumbai)* — closest to the venue.
5. **Security options** (if shown): keep *Data API* enabled and exposing the `public` schema (the app uses PostgREST RPCs). Any "automatic RLS" option can stay on — the migrations enable RLS themselves.
6. Create the project and wait until it reports healthy.
7. **Project Settings → General**: note the **Reference ID** (`<ref>`).
8. **Project Settings → API Keys**: copy the **Project URL** and the **publishable key** (or the legacy **anon** key). Do **not** copy the secret / service_role key — nothing needs it.

## 3. Authentication settings (dashboard)

1. **Authentication → Sign In / Providers → Email**: enabled.
   * **Allow new users to sign up**: **ON** — staff create their own accounts (they get no access until an owner adds their e-mail).
   * **Confirm email**: **ON** recommended. Note: Supabase's built-in mailer sends only to your organization's team members and is heavily rate-limited — for staff outside the team, set **custom SMTP** (Authentication → Emails → SMTP Settings) first. If you choose to leave confirmation OFF on this dev project, record that decision; anyone with the app could then create an (empty, access-less) account with any e-mail.
   * **Secure password change**: ON.
2. **Authentication → Sign In / Providers → Anonymous sign-ins**: **OFF**.
3. **Authentication → Policies / Passwords** (wording varies): minimum length **10**, require letters and digits; enable **leaked-password protection** if your plan offers it.
4. **Authentication → URL Configuration → Site URL**: a page you control (e.g. your website). The confirmation e-mail link confirms the account first and then redirects there; the app needs no redirect URLs (no OAuth, no deep links).
5. Leave JWT expiry (3600 s) and refresh-token rotation at their defaults (they match the local stack the app was tested with).
6. *(Optional, smaller surface)* **Integrations / Database → Extensions**: the app does not use GraphQL; you may disable `pg_graphql`.

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
Must list exactly `0001` … `0014`, in that order, and nothing else.

```bash
supabase db push
```
Applies them. Do NOT add `--include-seed`.

```bash
supabase migration list --linked
```
Local and Remote columns must both show `0001` … `0014`.

Rules while linked:
* **Never** run `supabase db reset --linked` or `supabase test db --linked` (the pgTAP files insert users and fixtures).
* Every repo script (`tool/verify_all.sh`, `tool/sync_it.sh`, `tool/pricing_parity.sh`, the race scripts) targets the local Docker container only and refuses anything else; keep using them locally.
* Future schema changes: add a new migration, run `bash tool/verify_all.sh` locally, then `supabase db push --dry-run` / `db push`.

## 5. Verify the hosted database

1. **SQL Editor** → paste `supabase/audit/security_audit.sql` → **Run**. Expect **no `FAIL` row**; the `REVIEW` rows must list exactly the ten client functions in section 1 and the extensions.
2. **Advisors → Security Advisor**: review; there should be no RLS-disabled or exposed-view findings.
3. **Database → Tables**: confirm there is no `Arena` row in `arenas` (the seed was not applied).

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

Release builds work too (the URL is https). Android release builds are
still debug-signed until your developer account exists
([RELEASE.md](RELEASE.md)).

## 7. Bootstrap and the two-phone test

1. **Owner phone**: *Create my account* → confirm e-mail (if on) → *Sign in* → *Create arena* (you become its owner; the starter catalog is seeded). Check prices, stations and controllers; adjust in Settings.
2. **Staff phone**: *Create my account* with the staff member's own e-mail → it shows "No arena has added you yet".
3. **Owner**: Settings → Staff → **Add by e-mail** → staff phone → *Refresh* → it opens the arena.
4. Run the multi-device checks on **different networks** (one on mobile data):
   * start a session on one phone, see it on the other within ~10 s;
   * put one phone in airplane mode, take a payment and start a session there; reconnect; confirm it syncs (or, if the other phone took the same station meanwhile, that it is refused and shown under Sync → Needs attention, money included);
   * both phones try to use the same controller; exactly one succeeds;
   * end and bill a session; confirm the bill is accepted (no `price_mismatch`);
   * owner changes a price; staff phone shows it; a session started on the old price list still ends cleanly;
   * owner turns the staff member off; the staff phone returns to sign-in and keeps any unsent work on the device.
5. Record the results; only then plan the production project (same steps, separate project, separate keys).

## 8. Known limits that still apply after deployment

* **Session times are device-asserted.** The server re-prices every bill
  (migration 0013), but only for the times the device sent; it cannot prove an
  end time is true. Amount validation is therefore **not** protection against
  forged or wrong timestamps. Audit evidence: server receipt time and sender of
  every op (`sync_ops.created_at`, `user_id`). See SYNC.md.
* A Dart pricing change needs a matching migration and a green
  `tool/pricing_parity.sh` (SYNC.md "Changing pricing").
* No backups/PITR policy has been chosen for the hosted project (plan-dependent).
* Other devices see changes by 10 s polling, not Realtime.
