# OWNER CONFIRMATION REQUIRED

These are **business rules not yet confirmed by the owner**. Each is implemented as a configurable
field on `BillingPolicy` / config (never hidden in a widget). The **Default** below is a safe,
documented assumption chosen only so the engine is testable — it is **not** a permanent decision.
The owner confirms the real value later with **no code redesign**.

Legend: 🟡 = pending owner confirmation · ✅ = fixed rule the spec already states (implemented, not a choice).

| # | Rule | Default (assumption) | Alternatives | Where |
|---|------|----------------------|--------------|-------|
| 1 | Partial-time billing granularity | 🟡 `perMinute` | 15 / 30 / 60-min blocks | `BillingPolicy.billingUnit` |
| 2 | Block rounding | 🟡 `roundUp` | `nearest` | `BillingPolicy.blockRounding` |
| 3 | Grace period | 🟡 `0 min` | any minutes | `BillingPolicy.graceMinutes` |
| 4 | Minimum session charge | 🟡 `0 min` | any minutes | `BillingPolicy.minimumChargeMinutes` |
| 5 | Early exit billing | 🟡 `actualTime` | `plannedDuration` | `BillingPolicy.earlyExit` |
| 6 | Happy-hour boundary | ✅ decided 2026-10-15: happy hours are a pricing rule; the session's (group's) start decides it for the whole session (replaces the spec §16 split) | split at window edges | `pricing_rules`, `_pr_rule` |
| 7 | Rounding scope | 🟡 `wholeSession` | `perSegment` | `BillingPolicy.roundingScope` |
| 8 | Late arrival basis | 🟡 `actualStart` | `plannedBooking` | `BillingPolicy.lateArrival` |
| 9 | Mid-session controller change | 🟡 not supported in MVP | reprice from change moment | documented seam in `SessionService` |
| 10 | Happy-hour eligible: VR | ✅ per rule: the rule's station types (seeded rule: PS5 and Pool) | — | `pricing_rules.activity_codes` |
| 11 | Happy-hour eligible: Lounge | ✅ per rule, as #10 | — | `pricing_rules.activity_codes` |
| 12 | VR partial unit billing | 🟡 `roundUpUnit` (₹200 / 30 min, 31 min → 2 units) | per-minute prorate / nearest | `BillingPolicy.vrUnitRounding` |
| 13 | RIFT concurrency (PS5 ⊕ VR) | ✅ mutually exclusive (hard rule) | — | `AvailabilityService` |
| 14 | Lounge min duration / included resources | 🟡 `60 min`, none bundled | any | `Activity`/`BillingPolicy` |
| 15 | Public holiday list | 🟡 empty (each rule says any / only / not on holidays; happy hours: not on holidays) | owner-populated | `holidays` table |
| 16 | Money rounding | 🟡 nearest `₹1` (100 paise) | ₹5 / ₹10 / up vs nearest | `BillingPolicy.moneyRounding` |
| 17 | Payment timing | 🟡 `either` | at start / at end | `BillingPolicy.paymentTiming` |
| 18 | Extend beyond 11 PM | 🟡 `blocked` | allowed | `BillingPolicy.allowExtendPastClose` |
| 19 | Station change during session | 🟡 not supported in MVP | supported | documented seam |
| 20 | Pause support | 🟡 not supported in MVP | supported | documented seam |
| 21 | Discounts / complimentary & approval | ✅ decided 2026-10-14: owner-defined presets and coupons (% or ₹, cap, minimum bill, types, dates/expiry, use limit) plus manual staff discounts up to Settings › Billing's max %, with a reason when required; one discount per bill, off the subtotal before cash rounding; recorded per bill (`bill_discounts`). Waive stays separate | — | `discounts`, `bill_discounts`, `_discount_apply` |
| 22 | GST treatment / receipt rules | 🟡 none in MVP (out of §3 scope) | GST invoicing | later phase |
| 23 | Cleaning / setup gap between sessions | 🟡 `0 min` | any minutes | `BillingPolicy.cleaningGapMinutes` |
| 24 | **Group multi-system billing** | 🟡 `perSystem` (each system billed for its own time at the rate for the controllers on it; 3 systems cost ~3× one system — a 3-controller price is **not** assumed to cover 3 systems) | `sharedControllerPool` (purchased controllers billed once at the single-system multi-controller rate regardless of how many systems) | `BillingPolicy.groupBillingMode` (captured per group in its pricing snapshot) |

| 25 | **Monday trading** | 🟡 `closed` (per the brief: open Tue–Sun) | open Mon–Sun | Settings → Opening hours |
| 26 | Public holiday = closed, or open without happy hour? | 🟡 `open`, with a per-holiday "closed" switch; rules follow their holiday mode | always closed | Settings → Holidays |
| 27 | Walk-in identity | 🟡 one customer record **per visit**, named "Walk-in", hidden from the member directory | a single shared "Walk-in" record | `CustomerRepository.createGuest` |
| 28 | Booking vs a live session on the same resource (server check) | 🟡 checked on the floor app only; the server refuses booking-vs-booking overlaps | server refuses a booking that overlaps a live session (open-ended sessions: until when?) | `_booking_free` (docs/GENERALIZATION.md phase 5) |
| 29 | Turf / court bookings: deposit or prepayment | 🟡 none; payment is taken on the checked-in session | deposit at booking, refundable or not | needs payments on bookings (phase 6) |
| 30 | Overtime past the booked end | ✅ decided 2026-10-15: the live amount stops at the booked end (only Extend raises it); at End the bill shows the booked price and the overtime price; an owner-set **overtime grace per station type** (Pricing › the type, next to Charged per; default None) bills only the booked time when the session ends within it, and the whole actual time beyond it; the type the session ends on decides. The actual end is always stored. Single sessions only for now; groups still bill every minute | — | `activities.overtime_grace_minutes`, `_pr_session_bill`, `overtimeBillUntil` |

> **#25 note (brief §8).** The brief states *"Operating hours: Tuesday–Sunday, 2 PM–11 PM. Monday is closed"*
> and *"Happy Hours: Tuesday–Friday, 2 PM–5 PM"*. The earlier spec in this repo said open Mon–Sun with
> happy hour Mon–Fri, and the code matched the older reading. The brief now wins: the seeded schedule is
> **closed Monday, happy Tue–Fri**, and the two Monday happy-hour tests were rewritten accordingly.
> Since 2026-10-15 happy hours are a pricing rule the owner edits on the dashboard, not a fixed window.
> Hours are persisted and editable, so if Monday really does trade, change it in
> Settings → Opening hours — no code change, and sessions already billed keep the hours they ran under.

> **#27 note (brief §4, §12).** A walk-in still needs *a* customer row, because a session is billed to
> someone. One row per visit keeps the visit countable (footfall, history, reports) without inventing a
> name; the alternative — one shared "Walk-in" record — would collapse every anonymous visit into a
> single "customer" and understate footfall.

> **#24 note (group feature §9).** When a group spreads across several PS5s, the price depends entirely on this rule, so it is **owner-confirmation-required**. The default `perSystem` is the conservative reading of the spec's warning ("do not automatically assume a three-controller price permits three separate PS5 systems at the same price"): co-located players on one system are combined onto that system's controller rate, while separate systems each bill their own controllers. `sharedControllerPool` is the alternative where the party pays once for the controllers they bought, however many systems they use. The mode is stored on each `GroupSession` (via its snapshot) so historical groups re-price identically; changing the policy only affects new groups.

## Fixed facts from the spec (not assumptions)

- Operating hours: **Tue–Sun 14:00–23:00 IST; Monday closed** (brief §8). Editable, see #25.
- Happy Hours: **Tue–Fri 14:00–17:00 IST** (2:00 PM – 5:00 PM); never at the weekend; never on a
  public holiday. Since 2026-10-15 this is a pricing rule ("Happy hours": those days and hours, not on
  holidays, PS5 and Pool, 20% lower), not a separate rate band. A rule changes every price by one percent or ₹ per
  hour, so the brief's happy rates are approximated: 20% lower gives ₹120 / ₹224 / ₹312 / ₹384 for
  1–4 controllers instead of ₹120 / ₹220 / ₹310 / ₹380 (Pool's ₹220 is exact).
- Rate card (current, snapshotted per session): see `seed.sql` / rate seed.
  - PS5 1c ₹150 · 2c ₹280 · 3c ₹390 · 4c ₹480 per hour (brief's happy rates ₹120/₹220/₹310/₹380: see above)
  - VR ₹200 / 30 min · Pool ₹275 per hour (brief's happy rate ₹220) · Lounge ₹2000 / hour
- Resources: HEX, VOID, GHOST, RIFT (PS5); RIFT also VR; Pool Table 1; Private Lounge.
- Session statuses: active / completed / voided. Payment: unpaid / partial / paid / waived.
  Overtime is **not** a status.

## Admin dashboard controls waiting on these decisions

The admin dashboard shows these controls disabled with a
"Not connected yet" note. Each one changes what a bill is worth, so it is built only after the
owner answers the questions below. Every answer has to hold identically in the server pricer
(`_pr_*`) and the floor app (`PricingService`), and in the pricing snapshot a session captures.

| Control (admin screen) | Rule | Decisions needed |
|---|---|---|
| ~~Discount on a bill~~ — **decided (#21), built on server + dashboard**: Sales discount row, Overview "Discounts given", Settings › Billing limits. Still open: "Discounts · 30 days" (Users) | #21 | Answered: % or ₹; off the subtotal before cash rounding; staff capped by the Settings max %, owners (Settings permission) not; free-text reason when required; manual needs the `discount` permission, presets and coupons do not; a group discount applies to the whole group bill. |
| GST %, Prices include GST, Invoice prefix (Settings › Billing); GST row (Sales) | #22 | Is the arena GST-registered? Rate (18%?) and HSN/SAC code? Rates inclusive (back out tax) or exclusive (add on top)? Rounding of the tax line? Invoice series: one per arena, per financial year, gap-free? What happens to the number of a voided bill? Are receipts printed/shared with the GSTIN? |
| ~~Percentage / flat pricing rules~~ — **decided 2026-10-14, built on server + dashboard** | #6, #15, #26 | Rules sit on top of the one standard price per type and controller count; percent or flat ₹ per hour, up or down; the session's start decides the rule for the whole session; overlapping rules: the first by priority wins; each rule says any / only / not on holidays. 2026-10-15: happy hours are no longer built in, they are a rule like any other (no happy rate band, window or per-type flag). |
| Membership plans ("Weekday 10h", "Gamer 25h"; Members) | — | Prepaid hours or a discount tier? Price, validity and expiry? Which station types and times may use plan hours? How plan minutes appear on a bill (₹0 line, separate payment method?) and in takings? Refunds of unused hours? |

Already connected on the dashboard (no owner decision needed): game age rating and media, arena
name / area / phone, payment methods offered, session start durations and end warning
(`floor_options`), and member birth year.
