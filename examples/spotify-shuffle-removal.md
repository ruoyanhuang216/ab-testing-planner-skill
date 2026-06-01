# Example — Spotify removes the album-page shuffle button

A worked illustration of the `/ab-test-plan` skill on a real product question. This example shows **two passes:**

1. **First pass** — the structured 10-component plan the skill produces from the problem statement alone (the "defensible draft").
2. **Depth pass** — the senior iteration: critique the first pass, add the things a staff DS would push on under closer review (variance reduction stacking, platform context, traffic constraints, sequential testing, segment heterogeneity).

> **Note on provenance.** The first-pass plan below is the **actual captured output** from invoking `/ab-test-plan` after installing the skill in Claude Code (via `ln -s ~/ab-testing-planner-skill/skill ~/.claude/skills/ab-test-plan`). The depth-pass is what a staff DS conversation looks like as a follow-up.

The pattern is intentional: the skill produces a defensible plan immediately, but real staff-level work iterates. Use this example as a template for how to push the skill from "draft plan" to "ship-ready plan" through follow-up questions.

---

## The prompt

```
/ab-test-plan Spotify is considering removing the shuffle button
from album pages. Plan the experiment. Assumptions: all surfaces
(mobile / desktop / web / CarPlay / Spotify Connect), both Free
and Premium tiers, weights pre-committed for both artist-
satisfaction and listener-engagement motives.
```

**Why this problem is a good illustration:**

- It's a real product debate (Spotify has shipped variants of this over the years)
- A two-sided market (listeners + artists) with substitution dynamics
- UI change with both immediate and long-term effects
- Sparse outcomes (album-page interactions are a fraction of total listening)
- Exposes triggering analysis, anytime-valid sequential testing, multi-experiment platform context, and segment heterogeneity

**Clarifications the skill would normally ask** (skipped here because the prompt includes them as assumptions):

1. *Are we removing only the album-page shuffle button, or also the corresponding action on Apple CarPlay / Spotify Connect / desktop?*
2. *Is the goal artist satisfaction (album completion as intended), listener engagement, or both with weights?*
3. *Premium-only or Free-and-Premium? Premium has unlimited skips, which changes substitution behavior.*

---

## First pass — actual skill output

> *Captured from a real `/ab-test-plan` invocation. The skill loaded `reference/ab-testing-playbook.md` from disk and produced the 10-component plan below with inline `§` citations.*

### 1. Problem framing

- **Decision the experiment informs:** Whether to remove the shuffle button from album pages across all surfaces (button remains available on playlists, library, and "Liked Songs").
- **Pre-committed decision rubric:** Launch iff combined OEC moves ≥ +1pp AND listening_hours/user doesn't degrade by ≥ 2% AND premium retention doesn't degrade by ≥ 0.5pp. Auto-shutoff iff listening_hours/user degrades > 5% with $p < 0.005$. Inconclusive → extend 4 weeks or pilot single market.
- **Is A/B the right tool?** Yes (per §1 checklist). User-level randomization is feasible, the change is reversible, effect detectable in 4 weeks. Caveat: **Free-mobile users are forced-shuffle-only on Spotify** — the album-page button doesn't exist on that surface in the first place, so they should be excluded from the analysis cohort (otherwise pure dilution).

### 2. Hypothesis

- **Direction:** Album-page shuffle CTR → ~0 (mechanical). Substitution: ~40% to play-from-start, ~30% to playlist shuffle, ~30% album-session abandonment. Album completion ↑, listening hours ~flat to slightly ↓.
- **Magnitude:** Album completion rate +2 to +5pp (baseline ~35%); listening_hours/user/day −1 to −3%; playlist shuffle usage +5 to +15% (substitution counter); premium retention flat ± 0.3pp. **MDE on combined OEC: 1pp absolute** (anchored on practical sig — below 1pp the engineering + creator-relations cost doesn't justify launch).
- **Mechanism:** Users who clicked shuffle wanted variety. Without the button, some accept artist-intended ordering (quality up); others bounce or substitute. The hypothesis is that the satisfaction lift from intentional listening outweighs the lost flexibility for the median user — but heavy-shuffle users may churn.

### 3. Metric hierarchy

- **Goal metric:** Premium retention rate D90 — the LTV proxy.
- **OEC (combined, weights pre-committed before test):**

$$
\text{OEC} = 0.4 \cdot \Delta(\text{album\_completion\_rate}) + 0.4 \cdot \Delta(\text{listening\_hours\_per\_user}) - 0.2 \cdot \Delta(\text{abandonment\_rate\_on\_album\_pages})
$$

Per §2.3 weighted-OEC discipline.

- **Guardrails (FWER at $\alpha = 0.005$, Holm-Bonferroni per §8.2):** listening_hours/user/day, premium_retention_D30, NPS, skip_rate.
- **Counter metric:** Playlist shuffle usage — if shuffle demand just relocates rather than disappears, the net is OEC-positive even with album listening dropping.
- **Debug metrics:** album-page button-click distribution by surface, time-to-first-action on album page, bounce rate, substitution patterns.
- **Gameability check (per §2.2):** completion rate is gameable by hiding skips. Define completion as "≥ 75% of track length played in a single listening pass" — not "no skip event recorded."

### 4. Randomization

- **Unit:** User (account_id) — consistent experience across all surfaces. Per §3.
- **Stratification:** Tier (Free / Premium) × recent-30-day listening hours (heavy / medium / light) — same covariate as CUPED.
- **Targeting / eligibility:** All users on iOS / Android / Web / Desktop / CarPlay / Connect, **excluding Free-mobile** (no album-page shuffle button exists there). Targeting frozen at pre-experiment snapshot to avoid SSRM per §3 unit-of-analysis trap.
- **SUTVA check:** Valid at the listener level. Edge case (collaborative playlists) is negligible. No creator-side feedback within the experiment window.
- **If SUTVA violated:** N/A. Standard user-level randomization is appropriate.

### 5. Sample size & duration

- **Baseline variance:** $\sigma^2(\text{listening\_hours/day}) \approx 4 \text{ hours}^2$ at baseline mean ≈ 2 hours (Spotify historical).
- **MDE:** $\delta = 0.04$ hours (2% relative on listening hours) — defended by practical sig at Spotify revenue scale.
- **Naive $n$ per arm:** $16\sigma^2/\delta^2 = 16 \cdot 4 / 0.04^2 = 40{,}000$ per arm.
- **Variance reduction (per §5):** CUPED with prior-30-day listening hours per user; expected $\rho \approx 0.7$ → $1 - \rho^2 = 51\%$ reduction. **Effective $n \approx 20{,}000$ per arm.**
- **Triggering (per §5.1):** analyze only users who hit ≥ 1 album page with ≥ 3 tracks during the window — single highest-leverage move for this experiment given most Spotify listening is on playlists, not albums.
- **Duration:** 4 weeks minimum — 2 weeks for day-of-week + 2 weeks for primacy fade.
- **Ramp protocol (per §6.3):** 1% → 5% → 25% → 50% over week 1, then steady at 50/50 for 3 weeks.

### 6. Trustworthy execution

- **A/A test (§6.1):** 1-week A/A on a control segment prior to launch; verify uniform p-distribution on listening_hours and album_completion. **Run A/A on the triggered subset too** to verify variance estimates on the actual analysis cohort, not the assignment cohort.
- **SRM monitoring (§6.2):** chi-square assignment-ratio test every hour; alert at $p < 10^{-6}$.
- **Pre-period sanity:** PSI on covariates (device, region, listening baseline, premium status) for treatment vs control; require $< 0.1$.
- **Logging audit:** verify treatment arm doesn't fire shuffle-button impressions (button hidden) and control arm does. Audit exposure log handles this asymmetry on iOS / Android / Web / CarPlay / Connect separately — platform parity is a known logging risk.

### 7. Interference & spillover

Not flagged for this UI change. Per §7, user-level randomization is the appropriate design — no two-sided market dynamics, no shared resources, no time-locked supply. Collaborative-playlist edge case is below the threshold of concern.

### 8. Decision rubric (pre-committed)

The launch quadrant per §8.5:

| | Practically meaningful | Not practically meaningful |
|---|---|---|
| **Stat sig** | **LAUNCH** (guardrails clean) | Don't launch — OEC mis-specified |
| **Not stat sig** | Inconclusive — extend 4 weeks or pilot single market | **DON'T LAUNCH** |

Specific thresholds:

- **Launch iff:** OEC ≥ +1pp AND listening_hours/user ≥ baseline − 2% AND premium_retention_D30 ≥ baseline − 0.5pp AND no SRM.
- **Auto-shutoff iff:** listening_hours/user < baseline − 5% with $p < 0.005$.
- **Multiple-testing protocol (per §8.2):** primary OEC at $\alpha = 0.05$; premium retention guardrail at $\alpha = 0.005$ FWER (Holm-Bonferroni); secondary drivers at BH within tier.
- **Recommend anytime-valid sequential (per §15.1)** for early-peeking protection — 1.5–2× sample-size penalty bought back by median ~30% horizon stop (Optimizely empirical). With 14-day floor on efficacy stops to handle novelty.

### 9. Long-term measurement

- **Holdback:** 5% permanent control for 12 months on the launched population. Coordinated with platform team — cannot overlap with other album-page launched experiments.
- **Long-term metrics:** D90 retention by listening archetype, premium upgrade/downgrade rate, listening minutes/user trend, external-platform-switching proxies.
- **Reverse experiment (per §8.3):** at month 6 (or when listening_hours stability is reached — ±0.5% week-over-week for 4 consecutive weeks), restore shuffle button for a fresh sample for 4 weeks. Validates steady-state effect.
- **Novelty / primacy mitigation:** plot effect over time; cohort by entry date; **brand-new-user sub-cohort** (joined Spotify after launch — never knew the button existed) as the steady-state benchmark.

### 10. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Novelty drives initial abandonment that recovers slowly | High | 4-week minimum; tenure segmentation; brand-new-user benchmark per §8.3 |
| Heavy-shuffle users (high LTV) churn | Medium-high | Stratify by listening-hours; tighter guardrail on heavy-user segment ($\alpha = 0.005$) |
| Artist backlash → cross-side effect not captured | Medium | Off-experiment qualitative work; separate creator-side measurement; not in this experiment's scope |
| Premium retention degradation (small, slow signal) | Medium | 12-month holdback; $\alpha = 0.005$ on retention; auto-shutoff at −1pp |
| Substitution to playlists masks net negative | Medium | Counter metric: playlist shuffle usage. If playlists absorb fully → OEC net positive; if users abandon Spotify → listening_hours guardrail catches it |
| Cross-experiment interaction (album-page UI layer collisions) | Medium at Spotify scale | Mutual exclusion within the album-page UI layer; pairwise interaction detection against top-5 concurrent experiments per §15.6.6 |
| iOS / Android / CarPlay logging asymmetry | Low | Pre-launch instrumentation audit per platform |

### First-pass summary

User-level A/B with CUPED on prior-30-day listening hours (51% variance reduction), triggered analysis on users hitting ≥ 1 album page with ≥ 3 tracks, Free-mobile carved out, 4-week duration, 5% permanent holdback for 12-month LTV. Launch iff combined OEC (album completion + listening hours − abandonment, weights pre-committed) moves ≥ +1pp with no degradation > 0.5pp on premium retention. Anytime-valid sequential testing with 14-day novelty floor recommended for early-peeking protection. Mutual exclusion within the album-page UI layer; pairwise interaction detection against top-5 concurrent experiments.

> **What the skill caught on its own** (vs the earlier simulated first pass): the Free-mobile carveout, the triggering analysis as the highest-leverage move, the anytime-valid recommendation, the cross-experiment layer-collision risk, and the brand-new-user sub-cohort as steady-state benchmark. These were "depth pass" additions in the simulated version; the real skill surfaced them in the first pass because the playbook explicitly directs them.

---

## Depth pass — senior iteration

The first pass above is a defensible plan a PM can take to launch review. A senior DS reviewing it would still push on three dimensions before signing off:

### A. Variance reduction beyond vanilla CUPED — stacking gains

Vanilla CUPED with one covariate gave 51% reduction. Stack more:

| Technique | Stacks with CUPED? | Expected gain |
|---|---|---|
| **Multi-covariate CUPED** (prior listening hours + prior album-page visits + prior skip rate) | Yes — if not collinear | $\rho^2$ rises to 0.6–0.7 → **65–70% reduction** |
| **CUPAC** — replace pre-period covariates with a predicted post-period outcome from an ML model | Replaces CUPED | When the prediction model is rich, CUPAC dominates. Used at Etsy and Microsoft. **70–80% reduction** |
| **Post-stratification on listening archetype** | Stacks | ~5–10% additional |
| **Winsorization at 99th percentile** | Yes, before everything | ~10–15% additional |
| **Triggering** (already in first pass) | Multiplicative with CUPED | 6.4× independent of CUPED |

**Stacked estimate:**
- Triggering: 6.4× effective sample reduction
- CUPED-stack on triggered population: 70% additional variance reduction
- **Net required $n$ drops from 40k/arm to ~ 2k/arm — 20× efficiency gain.**

The experiment becomes feasible at 5% of traffic for 2 weeks instead of 50/50 for 4 weeks. **The first-pass plan understated this** by only naming vanilla CUPED.

### B. Spotify platform context — which layer, which conflicts

Spotify's platform uses **layered overlapping experimentation** à la Google KDD 2010 (per §15.6.3). Decisions:

1. **Which layer?** The "album-page UI" layer. Mutually exclusive with other album-page UI experiments; orthogonal to ranker / recommender / ads / settings.

2. **Layer conflicts to check before launch:**
   - Other album-page UI tests (header redesign, like-button placement, lyrics panel) — same-layer mutex
   - Onboarding flow experiments affecting new-user album discovery — affects the brand-new-user steady-state cohort
   - Premium upgrade prompt experiments — affects retention guardrail
   - Recommender experiments changing "what plays after the last track of an album" — interacts with abandonment vs continued-listening

3. **Hash-based assignment** with `salt = experiment_id` — same `user_id` → same variant across all surfaces. Critical: user shouldn't see button on phone but not desktop.

4. **Launched-layer placement** post-launch: if shipped, graduates from active to launched layer so future album-page experiments don't compete for traffic.

### C. If we don't have enough traffic — preference order

1. **Variance reduction first** (§A) — the 20× gain almost always solves it
2. **Triggering** (already in first pass)
3. **Geo subset** — pilot in Sweden / Norway / Denmark / Finland (~30M MAU, Spotify's home markets) first; cultural variance risk, validate with 2–3 other markets before global
4. **Extended duration** — 8 weeks instead of 4; doubles power and opportunity cost
5. **Larger MDE** — only detect bigger effects; acceptable when small effects don't change the decision
6. **Holdback inversion** — ship to 100% with a 1–5% "holdback to old behavior"; use when team will ship anyway

### D. Other senior considerations the first pass missed

| Consideration | Action |
|---|---|
| **Pre-experiment effect priors** | Observational analysis: historical variance in album-page completion rate; shuffle-click distribution. Anchor MDE rather than guess. |
| **Album-length stratification** | Singles ≈ shuffle = play (degenerate); EPs intermediate; albums (10+ tracks) primary. Pre-register by length tier (first-pass triggering rule used ≥ 3 tracks — could be tightened). |
| **Geo / market segmentation** | Latin America heavy on full-album listening; US heavy on playlist. Don't assume one effect size globally. |
| **Free vs Premium effects** | Free has restricted skips → shuffle meaningful on albums; Premium → may shuffle less. Different effects expected. |
| **Creator-side experiment** | Listener change → consumption shift → artist release-format decisions over 6–12 months. Separate creator-side measurement; not in this experiment's scope but document. |
| **External / regulatory** | Some jurisdictions have user-control mandates around content delivery (accessibility). Legal review for regulated markets. |
| **Reverse-experiment timing anchored to stability** | First pass had this right — month 6 OR listening-hours stability for 4 weeks. Anchor to stability over calendar. |

---

## Final consolidated summary

The Spotify shuffle experiment is **best executed as a triggered, multi-covariate-CUPED-stacked, anytime-valid sequential test on the active album-page UI layer** with mobile / desktop / CarPlay stratification, Free-mobile carved out, album-length tiered analysis, and **three simultaneous early-stop conditions** (efficacy / futility / harm with 14-day floor on efficacy). Triggered population analysis combined with multi-covariate CUPED + winsorization drops required $n$ from 40k/arm to ~2k/arm (20× efficiency), making the experiment feasible at 5% of traffic for 2 weeks instead of 50/50 for 4. A 5% permanent holdback for 12 months captures long-term LTV; a reverse experiment at listening-hours stability validates steady-state. Platform-side: mutual exclusion within the album-page UI layer; pairwise interaction detection against top-5 concurrent experiments; coordinate holdback with platform team.

---

## Other problems worth running through the skill

Each of these exposes a different staff-level dimension the framework needs to handle. Run them to compare what the skill surfaces vs what it misses.

| Problem | Dimension stressed |
|---|---|
| **"LinkedIn wants to test removing the 'Connect' button from suggested-connection cards and replacing with 'Follow.' Plan the experiment."** | Network effects (Connect is bidirectional, Follow isn't); cluster randomization design; multi-sided market (recruiters, members, creators); long-term creator-side effects |
| **"Stripe wants to test rolling out a new SCA / 3DS challenge flow for European card payments. Plan the experiment."** | Regulatory dimension (PSD2 compliance, can't withhold security); quasi-experimental fallback (rollout by issuing bank); sparse outcomes (fraud rates very low → power is binding) |
| **"Uber Eats wants to test surge pricing on restaurants during peak hours. Plan the experiment."** | Hard SUTVA (shared supply); switchback design mandatory; two-sided cannibalization (pricing change affects demand AND supply elasticity) |
| **"Anthropic wants to test a new Claude system prompt for code assistance tasks. Plan the experiment."** | LLM experimentation (per playbook §16.5): win-rate vs LLM-judge vs behavioral A/B; subjective quality; no clean CUPED analog for response quality; open frontier |

---

## Takeaways for using the skill

1. **The first pass is a defensible draft, not a ship-ready plan.** Treat it as the starting structure for a staff-DS conversation.
2. **Always ask: variance reduction stacking, platform context, sequential testing.** These three are the most-commonly-needed depth-pass additions.
3. **Push on variance reduction stacking.** Vanilla CUPED is one technique; the gains compound when you stack triggering + multi-covariate + winsorization + post-stratification.
4. **Make the launch rubric specific.** Numbers, not adjectives. Pre-commit before the data lands.
5. **Use the playbook citations.** When the skill cites `§5.4` or `§15.1`, that's the depth — go read it when you need to defend a choice.

## How this example was generated

```bash
# Install
ln -s ~/ab-testing-planner-skill/skill ~/.claude/skills/ab-test-plan

# Invoke (in any Claude Code session after install)
/ab-test-plan Spotify is considering removing the shuffle button
from album pages. Plan the experiment. Assumptions: all surfaces
(mobile / desktop / web / CarPlay / Spotify Connect), both Free
and Premium tiers, weights pre-committed for both artist-
satisfaction and listener-engagement motives.
```

The first-pass output above is verbatim. The depth-pass below it is a follow-up conversation the user iterated with the skill.
