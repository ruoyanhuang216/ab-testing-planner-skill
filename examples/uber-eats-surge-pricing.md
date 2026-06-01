# Example — Uber Eats peak-hour surge pricing on restaurants

A worked illustration of the `/ab-test-plan` skill on a hard **two-sided market** problem. The dominant design concern here is **SUTVA violation** — user-level A/B is structurally invalid because surge pricing is a market-level intervention. The right answer is a switchback design (with a geo-experiment overlay for validation), which the skill correctly identifies in the first pass.

> **Note on provenance.** The first-pass plan is the actual verbatim output from invoking `/ab-test-plan` on the prompt below. The depth-pass that follows is the senior iteration on switchback-specific subtleties.

---

## The prompt

```
/ab-test-plan Uber Eats is considering introducing surge pricing
on restaurants during peak meal hours (lunch and dinner rush).
The hypothesis is that surge pricing on the busiest restaurants
will shift demand toward less-saturated restaurants, reducing wait
times overall and improving net contribution margin. Assumptions:
surge is a multiplier applied to delivery fee + service fee (not
to restaurant menu prices); peak hours defined as 11:30am-1:30pm
and 6:00pm-8:30pm local; pilot scope is US markets only; we
control both the consumer and merchant sides of the marketplace;
courier (dasher) labor is the third side and is paid the same
per-delivery regardless. Plan the experiment.
```

**Why this problem is a good illustration:**
- Hard SUTVA violation — user-level random is structurally invalid
- Two-sided market with three sides (consumers, restaurants, couriers); spillover everywhere
- Switchback design with carryover concerns (the dominant Lyft / DoorDash design pattern)
- Regulatory dimension (some US states restrict dynamic pricing)
- Long-term acclimation: surge becomes "normal" over months
- The skill must reach for §7 (SUTVA / two-sided markets) and §16.1 (switchback at scale) immediately

---

## First pass — actual skill output

> *Captured verbatim from a real `/ab-test-plan` invocation. The skill loaded the playbook from disk and produced the plan below with inline `§` citations.*

### 1. Problem framing

- **Decision the experiment informs:** Whether to roll out peak-hour surge pricing on high-demand restaurants (delivery + service fee multiplier; menu prices unchanged), and at what surge intensity (1.2× / 1.5× / 2.0×).
- **Pre-committed decision rubric:** Launch iff net contribution margin per active customer rises by ≥ 2% AND total peak-hour orders don't degrade by ≥ 3% AND customer 30-day repeat rate doesn't degrade by ≥ 1pp. Auto-shutoff iff total peak-hour orders fall > 8% with $p < 0.005$.
- **Is A/B the right tool?** **Yes, but not user-level A/B.** Surge pricing is a market-level intervention with hard SUTVA violation (§7) — you can't price the same delivery differently for two customers in the same city in the same minute. The right design is **switchback at market × 2-hour-slot level**, with **geo experiment as the validation overlay** (§7.1). User-level A/B is structurally invalid here; do not propose it.

### 2. Hypothesis

- **Direction:** Surge on busiest restaurants → demand shifts to non-surge restaurants (price elasticity); average wait times drop because demand spreads; net margin per order rises on the surged restaurants (price up, volume down — net should be positive within the elastic range).
- **Magnitude:**
  - Surge-restaurant order volume: **−15 to −35%** at 1.5× multiplier (price elasticity of demand ≈ −0.5 to −1.0 for food delivery in peak)
  - Non-surge-restaurant order volume in same market/slot: **+8 to +20%** (substitution capture)
  - Total market peak-hour orders: **flat to −5%** (some demand evaporates entirely vs substitutes)
  - Net contribution margin per active customer per peak slot: **+3 to +8%**
  - Average wait time on surge restaurants: **−10 to −20%**
- **Mechanism:** Surge raises the relative price of constrained-supply restaurants → marginal customers substitute to non-surged restaurants with available kitchen capacity → marketplace clears more efficiently.

### 3. Metric hierarchy

- **Goal metric:** Customer 90-day order frequency × order margin (LTV proxy).
- **OEC (combined, weights pre-committed):**

$$
\text{OEC} = 0.5 \cdot \Delta(\text{net\_margin\_per\_active\_customer\_per\_peak\_slot}) + 0.3 \cdot \Delta(\text{avg\_wait\_time\_improvement}) - 0.2 \cdot \Delta(\text{customer\_complaint\_rate})
$$

- **Guardrails (FWER at $\alpha = 0.005$, Holm-Bonferroni per §8.2):**
  - Total peak-hour orders per market
  - Customer 30-day repeat rate
  - Restaurant partner satisfaction
  - Courier earnings per peak hour
- **Counter metric:** Demand on **non-surge restaurants** in the same market × slot.
- **Debug metrics:** order substitution patterns (surge → non-surge), price sensitivity by customer segment, restaurant prep-time changes, courier dispatch latency.
- **Gameability check (per §2.2):** "net margin" gameable by raising surge multiplier — lock the surge-eligibility logic before launch; don't let restaurants opt in or out mid-experiment.

### 4. Randomization

- **Unit:** **Market × 2-hour time slot** (switchback unit, per §7.1 + §16.1).
- **Stratification:** Market size (top-30 vs next-50 US DMAs), daypart (lunch vs dinner — different elasticities).
- **Targeting / eligibility:** Restaurants eligible = top 25% by peak-hour order volume per market. Surge = **1.5× test value** (1.0× control vs 1.5× treatment).
- **SUTVA check:** **Violated at the user level** (hence switchback). Within a market × slot, treatment is uniform → SUTVA holds at the slot level. **Cross-slot carryover** is the residual concern.
- **If SUTVA violated:** Switchback per §7.1. See §7 below for the full design.

### 5. Sample size & duration

- **Baseline variance:** $\sigma^2 \approx 25\%^2$ at the slot level (per §16.1 Lyft/DoorDash benchmarks).
- **MDE:** 2% relative on net margin (absolute = 0.5% of baseline) — defended by Uber Eats revenue scale.
- **Naive $n$ per arm:** $16\sigma^2/\delta^2 = 10{,}000$ slot-occurrences per arm.
- **Variance reduction (per §5):** Pre-period CUPED at market × daypart × DOW level with 8 weeks history; expected $\rho \approx 0.8$ → 64% reduction. **Effective $n \approx 3{,}600$ slot-occurrences per arm.**
- **Slot calculus:** 30 markets × 2 peak slots × 2-hour switchback = ~60 slot-occurrences per arm per day. **Required: ~60 days = 8–9 weeks** at full scale.
- **Geo overlay (per §7.1):** synthetic-control geo experiment in parallel across 10 treated + 30 matched control markets for an independent estimate not subject to carryover concerns.
- **Ramp protocol:** week 1 single-market pilot (mid-size, low strategic risk), weeks 2–9 scale to all 30 top-DMA markets.

### 6. Trustworthy execution

- **A/A test:** 2-week switchback A/A in 5 markets with no surge applied; verify slot-level variance estimates and check no systematic difference between treated-OFF and control-OFF slots (catches DOW × treatment confounds).
- **SRM analog:** **schedule-adherence audit** — verify switches happened on schedule and surge was actually shown in treated slots. Auto-alert on miss > 2% of slots.
- **Pre-period sanity:** PSI on slot-level demand patterns between treated and control slot pairs; require < 0.1.
- **Logging audit:** verify (a) surge multiplier applied at checkout in treated slots, (b) baseline displayed in control slots, (c) order timestamps fall within the assigned slot.

### 7. Interference & spillover (the critical section)

- **Type of interference:** **Two-sided market + time-locked supply + cross-slot carryover.**
- **Mitigation design (per §7.1, §16.1):**
  - **Primary:** switchback at 2-hour slot granularity within market. Treatment / control alternates with **30-minute burn-in discarded from analysis** (Lyft's published rule per §16.1: `dwell / slot ≤ 30%`).
  - **Schedule:** anti-symmetric across days to balance DOW × treatment confounds.
  - **Secondary validation:** synthetic-DiD geo experiment with 10 treated + 30 matched control markets, 6-week pre-period.
- **Inference adjustment:**
  - Cluster-robust SEs at the **market level** (~30 effective clusters)
  - For switchback: model carryover explicitly via AR(1) on slot-level residuals
  - For geo: synthetic-DiD with rank-inference test
- **Spillover measurement first (per §7.2):** before committing to switchback, run a 2-week pilot in 3 markets to **estimate the carryover decay rate** — verify dwell/slot assumption holds before the full design.

### 8. Decision rubric (pre-committed)

| | Practically meaningful | Not practically meaningful |
|---|---|---|
| **Stat sig** | **LAUNCH** (both designs agree) | Don't launch — OEC mis-specified |
| **Not stat sig** | Inconclusive — extend or change surge multiplier | **DON'T LAUNCH** |

- **Launch iff:** OEC ≥ +2% (switchback and geo agree within 1pp) AND total peak orders ≥ baseline − 3% AND repeat rate ≥ baseline − 1pp AND restaurant satisfaction ≥ baseline.
- **Auto-shutoff iff:** total peak orders < baseline − 8% with $p < 0.005$ OR complaint rate > baseline + 50% at $p < 0.005$.
- **Multiple-testing protocol (per §8.2):** primary OEC at $\alpha = 0.05$; total order volume + repeat at $\alpha = 0.005$ FWER; restaurant/courier guardrails at BH within tier.
- **Disagreement protocol:** if switchback and geo overlay give opposite-sign effects or differ by > 2× — do not launch; investigate carryover or geo selection bias.

### 9. Long-term measurement

- **Holdback:** 10% of markets stay surge-free for 12 months. Required because (a) D90 LTV is slow and (b) market-side merchant and customer behavior adapts over time.
- **Long-term metrics:** D90 retention, order-frequency trend, restaurant churn, Eats Pass subscription rate, marketplace concentration (Gini on restaurant order share).
- **Reverse experiment (per §8.3):** at month 9, **turn off surge in 3 launched markets for 4 weeks**. Validates steady-state vs novelty / acclimation.
- **Novelty / primacy mitigation:** cohort customers by first-surge-encounter date; check last 2 weeks of switchback separately from first 2 (initial reaction vs equilibrium).

### 10. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Carryover between slots biases switchback estimate | **High** — dominant switchback risk per §16.1 | 30-min burn-in; AR(1) carryover model; geo overlay |
| Customer acclimation (surge becomes normal, demand recovers) | High over months | 12-month holdback; reverse experiment at month 9 |
| Restaurant retaliation (raise menu prices to offset surge) | Medium | Monitor menu-price changes on surged restaurants; mid-experiment intervention if observed |
| Courier earnings drop because dispatches spread thinner | Medium-high | Courier earnings as $\alpha = 0.005$ guardrail |
| Geo selection bias in synthetic-DiD overlay | Medium | Pre-register donor pool; rank-inference; leave-one-out stability |
| Brand damage / press cycle around "Uber price gouging" | Medium-high | Communications plan; defensive narrative on *better wait times* not *higher prices*; transparency disclosures |
| Regulatory scrutiny (anti-surge laws in some US states — e.g. emergency-only surge in NY/NJ) | Medium | Legal pre-screen of pilot markets; exclude restrictive jurisdictions |
| Restaurant attribution wrong (which qualify for surge?) | Low-medium | Lock eligibility rule pre-experiment; verify set doesn't change mid-experiment |
| Cross-experiment interaction with Eats Pass promo or recommender tests | Medium | Mutual exclusion with concurrent pricing or ranking experiments per §15.6 |

### First-pass summary

Uber Eats peak-hour surge is structurally **not user-A/B-testable** — it's a market-level intervention with hard SUTVA violation. Switchback at market × 2-hour-slot granularity with 30-minute burn-in, paired with a synthetic-DiD geo overlay (10 treated + 30 matched control markets) for independent validation. CUPED reduces required slot-occurrences from 10,000 to ~3,600 per arm (~8–9 weeks at 30 markets). Launch iff combined OEC ≥ +2% and total peak-hour orders ≥ baseline − 3% and both designs agree within 1pp. 12-month geo holdback in 10% of markets; reverse-experiment at month 9. Dominant risks: carryover (mitigated by burn-in + AR(1) + geo overlay), customer acclimation (12-month holdback), regulatory pre-screen.

---

## Depth pass — senior iteration on switchback subtleties

The first pass is solid on the design choice (switchback + geo overlay). The depth pass focuses on switchback-specific pitfalls the first pass mentioned but didn't fully flesh out.

### A. Carryover diagnostics — beyond "30-min burn-in"

The first pass cited Lyft's `dwell / slot ≤ 30%` rule but didn't say **how to measure carryover empirically**. A staff DS would:

1. **Pilot-phase carryover estimation.** Before the full 8-week experiment, run a 2-week intensive pilot in 3 markets at multiple burn-in durations (15, 30, 60 min). Measure the residual treatment effect in the first 30 min of a control slot following a treatment slot. If it's > 5% of the slot-level effect, carryover is contaminating.
2. **Carryover model in the analysis.** Don't just discard the burn-in — model it. AR(1) on slot residuals captures persistence; for stronger carryover, an AR(2) or distributed-lag model is appropriate. The slot-level treatment effect is the long-run coefficient.
3. **Day-of-week × treatment confounding.** Anti-symmetric schedule (Mon-T / Tue-C / Wed-T...) only works if DOW effects don't interact with treatment. Verify with a DOW × treatment-state interaction term in the slot-level regression; if significant, expand to a **2-week Latin-square design** where each DOW gets balanced T/C exposure.

### B. The 3-sided market — courier-side spillover

The first pass treats couriers as "paid the same per-delivery regardless," which is *contractually* true but **economically misleading**. Under surge:

- Total peak-hour orders may drop, so total courier earnings per peak hour drops even though per-delivery pay is constant
- Courier wait time between deliveries increases
- **Courier supply elasticity:** couriers who are paid less per peak hour may stop showing up for peak hours, reducing fulfillment capacity for the *next* day's peak — a delayed cross-side effect
- **Recommended additional metric:** courier session count and acceptance rate per peak hour, monitored daily with auto-alert on sustained decline

This is a worked example of the playbook's two-sided / three-sided market discipline (§7) — the framework prompts you to ask "who else is affected?" but doesn't always volunteer that in the first pass.

### C. Carryover *across* peak slots within a day

The first pass models lunch and dinner as independent slot types. They're not. If lunch carries surge → customers who ate elsewhere at lunch may *also* be less likely to order at dinner. Specifically:

- **Demand satiation carryover:** a customer who paid surge at lunch is less likely to repeat at dinner
- **Repeated-exposure annoyance:** the same customer seeing surge twice in a day may churn more

**Fix:** randomize at the **customer-day** level for the *between-slot* effect — but this collides with the within-slot SUTVA violation. The compromise: track **within-customer day-level cumulative surge exposure** as a debug metric; if the effect from lunch-surge to dinner-order is large, the experiment underestimates the true negative cumulative effect.

### D. Restaurant-side opt-in/opt-out — the gameability deep-dive

The first pass said "lock the surge-eligibility logic." A senior would push further:

- **Top 25% by volume** is a moving target. As surge depresses volume on the top, restaurants slip out of the top 25%, dropping their surge designation mid-experiment → reverse-causality circle.
- **Fix:** lock eligibility **at the start of each slot using pre-experiment-period rolling-window rank**, not real-time. Specifically: rank restaurants by their volume in the same DOW × daypart window in the prior 4 weeks; that rank is fixed for the experiment.
- **Restaurant opt-out:** some restaurants will lobby Uber to opt out (worried about volume loss). Pre-commit a policy: no opt-outs during the experiment; concerns are addressed via the post-experiment review. Document this in the experiment charter.

### E. Statistical inference under switchback — what actually goes in the t-test

The first pass said "cluster-robust SEs at the market level" but switchback inference is subtle:

- The "unit of analysis" is the **slot-level metric** (e.g., margin in the slot)
- The "randomization unit" is the **slot assignment** (T/C per slot)
- The right standard error is **cluster-robust at the market level** (multiple slots per market are correlated) **plus** **HAC (Newey-West) adjustment for temporal autocorrelation** across slots within a market
- For the disagreement protocol (switchback vs geo): the two effect estimates have correlated standard errors because they share the same market populations; the **difference-of-effects test** requires joint variance estimation, not the naive subtraction

### F. Regulatory + transparency considerations the first pass listed but didn't operationalize

- **State pre-screen:** New York / New Jersey / California Public Utilities Commission jurisdiction restrictions. Pre-experiment legal memo required.
- **In-app disclosure:** if surge is applied, the consumer-facing UI must show a "Peak Demand" indicator (Uber's standard practice). The instrumentation should verify the indicator fires in treatment slots — instrumentation parity check.
- **External communications plan:** the experiment leaks (always does). Pre-draft talking points framing the test as "experimenting with marketplace efficiency during peak demand" rather than "raising prices."

### G. Variance reduction beyond CUPED at the market × daypart × DOW level

Same playbook as Spotify (§B of that example), adapted:

| Technique | Add for Uber Eats? | Notes |
|---|---|---|
| Multi-covariate CUPED | Yes | Prior-period margin + prior-period order volume + weather + local-event calendar |
| Stratified post-stratification by market tier | Yes | Top-10 vs 11-30 vs 31-50 markets have different elasticities |
| Synthetic control as a CUPED-style adjustment | Yes | For the geo overlay design specifically, this *is* the analysis method |
| Winsorization on slot-level margin | Yes | Cap at 99th percentile to handle extreme weather days or local events |

Stacked, expect total variance reduction of 75–85% vs naive (vs 64% from CUPED alone), shrinking the required duration from 8–9 weeks to 4–5 weeks.

---

## Final consolidated summary

Surge pricing on Uber Eats peak hours is best executed as a **switchback at market × 2-hour-slot granularity** with **30-minute burn-in discarded and AR(1) carryover modeling**, paired with a **synthetic-DiD geo overlay** on 10 treated + 30 matched control markets as an independent validation. Restaurant eligibility is locked at the start of each slot based on the prior 4-week rolling rank (not real-time); courier earnings per peak hour is a hard-tier guardrail at $\alpha = 0.005$; in-app surge disclosure must fire in treatment slots and is part of the instrumentation parity check. Stacked variance reduction (multi-covariate CUPED + post-stratification by market tier + winsorization) cuts required duration from 8–9 weeks to 4–5 weeks. Launch iff both switchback and geo overlay agree within 1pp on a combined OEC of margin + wait-time − complaints ≥ +2pp, with no breach of total peak orders, customer repeat rate, restaurant satisfaction, or courier earnings. 12-month geo holdback in 10% of markets and a 4-week reverse experiment at month 9 to validate steady-state.

---

## Key takeaways from this example

1. **The skill correctly refuses user-level A/B** — a junior plan would propose A/B-randomizing users into "see surge" vs "don't see surge," which is structurally invalid. The skill reaches for §7 and §16.1 immediately.
2. **Geo overlay is the senior insurance policy** — switchback is the primary design, but carryover is a known dominant risk. The geo overlay (synthetic-DiD on 10+30 markets) is an independent estimate. The "disagreement protocol" between the two designs is the staff move the first pass introduced explicitly.
3. **Three-sided market discipline** — the prompt called out couriers as the third side; the first pass added a courier guardrail; the depth-pass deepened it to courier-supply elasticity (the delayed cross-side effect).
4. **Slot-level inference is subtle** — cluster-robust SEs at the market level + HAC adjustment for within-market temporal autocorrelation; not just "cluster by market."
5. **Pre-screen for regulatory restrictions** — surge pricing is restricted in several US states. The experiment charter needs a legal memo before launch.

## How this example was generated

```bash
# Install (one-time)
ln -s ~/ab-testing-planner-skill/skill ~/.claude/skills/ab-test-plan

# Invoke
/ab-test-plan Uber Eats is considering introducing surge pricing
on restaurants during peak meal hours (lunch and dinner rush).
[...full prompt above...]
```

The first-pass output is verbatim. The depth-pass below it is a follow-up conversation iterating the plan.
