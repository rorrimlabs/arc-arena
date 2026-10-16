# Working state

**Objective:** staff personal details (own edit on floor app, owner view/edit on admin) + versioned staff terms that non-owner staff must accept on the floor app (blocking gate).

**Done (2026-10-16):**
- Games: Settings › Games in the 3-panel detail pane (`games-library.ts`, table view); multiselect play modes (`games.play_modes`, story/single/local/online; `player_mode` dropped; Drift v18); age 3–18. Migration `20261016123826_game_play_modes`.
- Server: `staff_personal_details`, `staff_terms`, `staff_terms_acceptances`; ops `staff_details.save` (self or owner level), `terms.publish` (owner level), `terms.accept` (self, latest only, idempotent). Migration `20261016125200_staff_details_and_terms` applied locally; smoke-run OK; advisors clean. Docs: `docs/STAFF_API.md`, `supabase/README.md`.

**In progress:** admin UI (Team › Profile tab, Settings › Staff › Terms tab) and mobile (My profile screen, terms gate) — delegated; verify diffs, `npm run build`, `flutter analyze`.

**Decisions:** fields = phone, personal e-mail, DOB, blood group, address (2 lines, city, state, PIN), emergency contact; no bank/ID. Gate blocks until accepted; owner level exempt; demo mode no gate. Owners view+edit details.

**Outdated tests to flag:** pgTAP 00/15/19 (`player_mode`), `games-page.spec.ts` (old Games page).
