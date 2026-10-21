# Working state

**Objective:** fix the pre-production audit (`audit/`, run 2026-10-16 at `24a4bdd`). Roadmap: `audit/09-remediation-roadmap.md`. User said "fix all issues" (2026-10-19).

**Decisions (2026-10-19):**
- Payroll: fix. Run may end on pay date; finalise refused while period not over / clock-in open / entry pending review.
- BL-001: refuse future (>2 min) and older than offline window (settings `offline_rules.max_offline_hours`, default 24, 1–720); flag end recorded >15 min late on Sales.
- FL-003: warn only for launch. SEC-001: narrow sync_pull by permission. DEP-001: fresh prod project.
- Waive: reason now required server-side. **Waive cap NOT done — needs owner decision** (manual cap defaults 0% → would block all non-settings waives).

**Done (all local; pgTAP 1495 PASS; Drift migration suite 32 PASS; analyze/build clean):**
- A: NG-001, FL-005/DEP-006, SEC-003/ST-006 (+ salary_adjustment.reverse), FL-004/CQ-001 (fixtures + v16→17, v17→18 tests), stale pgTAP 00/16/19/30 fixed.
- B: DB-002 (10 FKs → no action, runbook), ST-001/ST-010/DB-006 (finalise guards + share lock in `_period_finalised`, admin button/notes/messages).
- C: BL-001 (`_client_time`, `ended_recorded_at`, Sales late-end flag, `offline_rules` setting), BL-002 single sessions (`_seg_priced`: no_rate / activity_not_offered; mobile pre-flight on switch/change controllers; end-sheet copy), BL-003 reason only. Test fixtures widened via offline_rules.
- Migrations: 20261018200818, 201749, 202010, 202941, 203328, 203502.

- D (done): NG-002 (`Attempt` ids, all money/pay/leave/attendance dialogs), FL-001/DB-008 (sync_push per-op refusals, transient classes, 200 cap; mobile batch halving + stuck message), FL-002/DB-005 (per-source limited paging, verified vs single page on local data), FL-003 (unsent count on revoke), SEC-001 (`_sync_hidden`, pull scope + mobile re-pull).
- E (done): FL-006/DEP-005 (release refuses non-production env; RELEASE.md), NG-003/DEP-004 (`public/_headers` CSP, `_redirects`, inlineCritical off), DEP-003 (`.github/workflows/ci.yml`), DEP-001/DEP-002/SEC-002 docs (§4a rewritten), DEP-007 (prod env emptied).
- §3 (done): DB-004 (`_append_only` triggers on 9 tables), DB-009 (sync_ops.payload for config/pay ops; staff access audit).
- 2026-10-19 decisions done: BL-003 waive cap (owner level uncapped; `_waive_check`, mobile `waiveOverLimit`, discount_options synced), ST-002 (refuse turning off a shift in use: `shift_in_use`; `shift_inactive`), ST-007 (unassign ends yesterday; assignment edits into finalised periods refused), ST-008 (`_att_work_date`: entry belongs to the shift it falls in), SEC-004 admin side (`shared/turnstile`, `Captcha` service, env `turnstileSiteKey`, CSP).
- pgTAP 1523 PASS.

**Open:**
- SEC-004 floor app: needs a Turnstile dependency (cloudflare_turnstile / webview_flutter) — ask user. Don't enable hosted CAPTCHA before.
- Need go-ahead (pay semantics): ST-003, ST-004, ST-005, DB-007. ST-009 docs.
- §3: BL-004, BL-005, DB-010, CQ-002/003/004, NG-004; BL-002 groups; P3s.
- BL-002 for groups (shared-pool sweep) not done; admin UI for offline_rules not built.
- tool/ scripts removed 2026-10-21; e2e suite to replace them (billing + sync coverage).

## Environment separation (local / staging / prod), started 2026-10-19

**Decisions:** D1 staging = NEW personal project `arena-ops-staging` (don't rebuild/reset the old hosted project `<ref in docs §4a>` until its data + history are reviewed). D2 prod app ID unchanged (`in.rorrim.arena_ops` / `in.rorrim.arenaOps`), `.dev` / `.staging` suffixes. D3 devices running a build from today's `prod.json`: unknown — switch no backend, touch nothing hosted until verified. D4 prod flavor refused in debug. D5 no VS Code staging entry. D6 Claude edits the Xcode project, user verifies in Xcode. D7 admin staging config in Phase B.

**Phases:** A (Flutter flavors, validation, build checks, docs) → B (create `arena-ops-staging`, pin its host, `dart_define.staging.json`, admin staging, retire `hosted-dev.json`) → C (company prod project, pin, rewrite `prod.json`, company signing/Sentry).

**Phase A done (uncommitted, 2026-10-19):** `AppConfig.problemFor(mode:)` + `environmentForFlavor` + `hostedSupabaseHosts` (both sets EMPTY → staging/prod refuse to start); Gradle `productFlavors` + per-flavor check; iOS 9 flavor configs, schemes dev/staging/prod, "Check Environment" phase (`ios/scripts/check_build_environment.sh`), `APP_DISPLAY_NAME`; macOS `*-dev` configs + dev scheme (for `default-flavor: dev`); launch.json `--flavor dev`; docs. Verified: analyze clean, 34 config/sentry tests pass, Gradle + iOS refusals, dev debug builds on Android / iOS sim / macOS. User to verify in Xcode. Consequence: no build can reach the old hosted project now.

**Next:** Phase B on the user's go-ahead (user creates `arena-ops-staging`).
