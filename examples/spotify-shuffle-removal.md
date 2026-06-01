# Example — Spotify removes the album-page shuffle button

A worked illustration of the `/ab-test-plan` skill on a real product question. This example shows **two passes:**

1. **First pass** — the structured 10-component plan the skill produces from the problem statement alone.
2. **Depth pass** — the senior iteration: critique the first pass, add the things a staff DS would surface on closer review (variance reduction stacking, platform context, traffic constraints, sequential testing, segment heterogeneity, other).

The pattern is intentional: the skill produces a defensible plan immediately, but real staff-level work iterates. Use this example as a template for how to push the skill from "draft plan" to "ship-ready plan" through follow-up questions.

---

## The prompt

```
/ab-test-plan Spotify is considering removing the shuffle button from album pages. Plan the experiment.
```

**Why this problem is a good illustration:**
- It's a real product debate (Spotify has shipped variants of this over the years)
- A two-sided market (listeners + artists) with substitution dynamics
- UI change with both immediate and long-term effects
- Sparse outcomes (album-page interactions are a fraction of total listening)
- Exposes triggering analysis, anytime-valid sequential testing, multi-experiment platform context, and segment heterogeneity

---

## First-pass plan (skill output)

### Clarifications the skill would ask

In an interactive session the skill would surface three clarifications before drafting:

1. *Are we removing only the album-page shuffle button, or also the corresponding action on Apple CarPlay / Spotify Connect / desktop? (Cross-surface affects randomization unit.)*
2. *Is the goal artist satisfaction (album completion as intended) or listener engagement, or both with weights?*
3. *Premium-only or Free-and-Premium? Premium has unlimited skips, which changes substitution behavior.*

For this example: **all surfaces, both motives with weights pre-committed, both Free and Premium.**

---

### 1. Problem framing

- **Decision:** Whether to remove the shuffle button from album pages across all surfaces (button remains on playlists / library / "Liked Songs").
- **Pre-committed launch rubric:** Launch iff combined OEC moves ≥ +1pp AND listening_hours/user doesn't degrade by ≥ 2% AND premium retention doesn't degrade by ≥ 0.5pp. Auto-shutoff iff listening_hours/user degrades > 5% with $p < 0.005$.
- **Is A/B the right tool?** Yes. User-level randomization is feasible, the change is reversible, effect should be detectable in 4 weeks.

### 2. Hypothesis

- **Direction:** Album-page shuffle CTR → ~0 (mechanical). Substitution: ~40% to "play-from-start," ~30% to playlist shuffle, ~30% abandon the album session. Album completion ↑, total listening hours roughly flat to slightly ↓.
- **Magnitude:**
  - Album completion rate: **+2 to +5 pp** (currently ~35%)
  - Listening hours/user/day: **−1 to −3%**
  - Playlist shuffle usage: **+5 to +15%** (substitution)
  - Premium retention: **flat ± 0.3 pp**
- **Mechanism:** Users who clicked shuffle wanted variety. Without the button, some accept the artist's intended ordering (quality up); others bounce or shift to a playlist (volume down or shifted). Net: quality gain plausibly exceeds volume loss for the median user; heavy-shuffle users may degrade.

### 3. Metric hierarchy

- **Goal metric:** Premium retention rate D30 / D90 — the LTV proxy.
- **OEC (combined, weights pre-committed):**

$$
\text{OEC} = 0.4 \cdot \Delta(\text{album\_completion\_rate}) + 0.4 \cdot \Delta(\text{listening\_hours\_per\_user}) - 0.2 \cdot \Delta(\text{abandonment\_rate\_on\_album\_pages})
$$

- **Guardrails (at $\alpha = 0.005$, FWER per §8.2):** listening hours/user/day, premium retention D30, NPS, skip rate.
- **Counter metric:** Playlist shuffle usage — if Spotify's shuffle demand just relocates rather than disappears, the net is OEC-positive even with album listening dropping.
- **Debug metrics:** Album-page button-click distribution, time from album page to first action, bounce rate, substitution patterns.
- **Gameability check:** Could completion rate be gamed by penalizing skips? Yes — define completion as "≥ 75% of track length played" rather than "no skip recorded."

### 4. Randomization

- **Unit:** User (account_id) — consistent experience across sessions / devices / platforms.
- **Stratification:** By tier (Free / Premium) and recent-30-day listening hours (heavy / medium / light) — also the CUPED covariate.
- **Targeting / eligibility:** All users on iOS / Android / Web / Connect / CarPlay; no targeting on listening behavior (avoids SSRM trap).
- **SUTVA check:** Valid. UI change affects only the listener's view; no creator-side feedback within the experiment window.

### 5. Sample size & duration

- **Baseline variance:** $\sigma^2(\text{listening\_hours/day}) \approx 4 \text{ hours}^2$ at baseline mean ≈ 2 hours.
- **MDE:** $\delta = 0.04$ hours (2% relative) — defended by Spotify-scale revenue sensitivity at ≈ 600M MAU.
- **Naive $n$ per arm:** $16\sigma^2/\delta^2 = 16 \cdot 4 / 0.04^2 = 40{,}000$ per arm.
- **Variance reduction:** CUPED with prior-30-day listening hours; expected $\rho \approx 0.7$ → $1 - \rho^2 = 51\%$ variance reduction. **Effective $n \approx 20{,}000$ per arm.**
- **Duration:** 4 weeks minimum (week 1–2 day-of-week patterns, week 3–4 primacy fade).
- **Ramp:** 1% → 5% → 25% → 50% over week 1, then steady at 50/50 for 3 weeks.

### 6. Trustworthy execution

- **A/A test:** 1-week A/A on a holdout immediately before launch; verify uniform p-distribution.
- **SRM monitoring:** chi-square assignment-ratio test every hour at $p < 10^{-6}$.
- **Pre-period sanity:** PSI on covariates (device, region, listening baseline, premium status) for treatment vs control; verify $< 0.1$.
- **Logging audit:** verify shuffle button impressions, clicks, album-page interactions log correctly per arm. Treatment arm shouldn't fire shuffle-button impressions (it's hidden) — confirm the exposure log handles this asymmetry.

### 7. Interference & spillover

- None at the user level for this UI change. Edge case (collaborative playlists) is negligible. No design modification needed.

### 8. Decision rubric (pre-committed)

| | Practically meaningful | Not practically meaningful |
|---|---|---|
| **Stat sig** | **LAUNCH** (guardrails clean) | Don't launch — OEC mis-specified |
| **Not stat sig** | Inconclusive — pilot one country, extend 4 more weeks | **DON'T LAUNCH** |

Specific thresholds:
- **Launch iff:** OEC moves ≥ +1 pp AND listening_hours/user ≥ baseline − 2% AND premium_retention_D30 ≥ baseline − 0.5pp AND no SRM
- **Auto-shutoff iff:** listening_hours/user degrades > 5% with $p < 0.005$
- **Multiple testing:** primary OEC at $\alpha = 0.05$; premium retention at $\alpha = 0.005$ (FWER, Holm-Bonferroni); secondary at BH within tier

### 9. Long-term measurement

- **Holdback:** 5% permanent control for 12 months on the launched population.
- **Long-term metrics:** D90 retention by listening-archetype, premium upgrade/downgrade rate, listening minutes/user trend, external-platform switching proxies.
- **Reverse experiment:** at month 6, restore the shuffle button for a fresh sample (never in original control) for 4 weeks.
- **Novelty / primacy mitigation:** plot effect over time; expect initial abandonment then recovery; cohort by entry date; brand-new-user sub-cohort.

### 10. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Novelty fades slowly | High | 4-week minimum; tenure segmentation; brand-new-user benchmark |
| Heavy-shuffle users churn | Medium-high | Stratify by listening-hours; tighter guardrail on heavy-user segment ($\alpha = 0.005$) |
| Artist backlash not captured | Medium | Off-experiment qualitative work; monitor public conversation |
| Premium retention degradation (small, slow) | Medium | 12-month holdback; $\alpha = 0.005$ on retention; auto-shutoff at −1 pp |
| Substitution to playlists masks net change | Medium | Counter metric: playlist shuffle usage |
| iOS / Android logging asymmetry | Low | Pre-launch instrumentation audit per platform |

---

## Depth pass (senior iteration)

The first pass is a defensible plan a PM can take to launch review. A senior DS reviewing it would push on six dimensions before signing off.

### Critique — what the first pass missed

| Miss | Why it matters |
|---|---|
| **No triggering analysis.** Analysis at the user level, but the treatment only affects users who *visit album pages*. Most Spotify listening is playlists, library, radio — those users dilute the signal. | Single highest-leverage move missed. Per playbook §5.1. |
| **No Free-tier mobile carveout.** Spotify mobile Free is *forced shuffle only* — there's no album-page shuffle button to remove. Treating these users dilutes signal *and* causes an instrumentation paradox. | Logical bug — Free-mobile users in "treatment" see zero change. |
| **No platform / layer reasoning.** Designed as if it were the only experiment running. Spotify runs hundreds simultaneously; album-page layer collisions are real. | Per §15.6 — need to specify which layer and check for conflicts. |
| **No early-stopping framework.** Committed to 4 weeks. In practice the team will peek and inflate Type-I. | Per §15.1 — median Optimizely experiment stops at ~30% of horizon. 4× opportunity-cost saving. |
| **No platform-segment heterogeneity.** Mobile / desktop / car have radically different shuffle propensities; car especially relies on hands-off control. | Need pre-registered segment analysis. |
| **MDE chosen without baseline measurement.** Plucked 2% out of "Spotify scale" rather than anchoring on observed historical variation. | Per §4.3 anti-pattern. |

### A. Triggering — the highest-leverage fix

Per §5.1: treatment only has an effect on users who visit an album page during the experiment window. Analyzing the whole population dilutes the effect estimate proportionally to the fraction never triggered.

For Spotify:
- ~15–25% of MAU visit an album page weekly
- Over 4 weeks, ~40–50% trigger at least once
- Intensity varies wildly (1 visit vs 50)

**Two flavors:**
1. **Standard triggering** — analyze only users who triggered. If triggered fraction is $t$ and treatment effect on triggered is $\tau$, ITT (analyzing everyone) gives $t \cdot \tau$, triggered analysis gives $\tau$. With $t = 0.4$, you get **2.5× the effect size** with 0.4× the $n$ → net **6.4× fewer users required**.
2. **Counterfactual triggering** — predict which control users *would have* triggered using logged features. Eliminates selection bias if treatment changes triggering rate.

**Trigger rule for this experiment:** "user navigated to ≥ 1 album page during the experiment window AND the album has ≥ 3 tracks" (excludes degenerate singles / EPs).

### B. Variance reduction beyond vanilla CUPED

Vanilla CUPED with one covariate gave us 51% reduction. Stack more:

| Technique | Stacks with CUPED? | Expected gain |
|---|---|---|
| **Multi-covariate CUPED** (prior listening hours + prior album-page visits + prior skip rate) | Yes — if not collinear | $\rho^2$ rises to 0.6–0.7 → **65–70% reduction** |
| **CUPAC** — replace pre-period covariates with a predicted post-period outcome from an ML model | Replaces CUPED | When the prediction model is rich, CUPAC dominates. Used at Etsy and Microsoft. **70–80% reduction** |
| **Post-stratification on listening archetype** | Stacks | ~5–10% additional |
| **Winsorization at 99th percentile** | Yes, before everything | ~10–15% additional |
| **Triggering** (§A) | Multiplicative with CUPED | 6.4× independent of CUPED |

**Stacked estimate:**
- Triggering: 6.4× effective sample reduction
- CUPED + post-stratification + winsorization on triggered population: 70% additional variance reduction
- **Net required $n$ drops from 40k/arm to ~ 2k/arm — 20× efficiency gain.**

The experiment becomes feasible at 5% of traffic for 2 weeks instead of 50/50 for 4 weeks.

### C. How this runs on the Spotify platform

Spotify's platform uses **layered overlapping experimentation** à la Google KDD 2010 (per §15.6.3). Key decisions:

1. **Which layer?** The "album-page UI" layer. Mutually exclusive with other album-page UI experiments; orthogonal to ranker / recommender / ads / settings.

2. **Layer conflicts to check before launch:**
   - Other album-page UI tests (header redesign, like-button placement, lyrics panel) — same-layer mutex
   - Onboarding flow experiments affecting new-user album discovery — affects the steady-state cohort
   - Premium upgrade prompt experiments — affects retention guardrail
   - Recommender experiments changing "what plays after the last track of an album" — interacts with abandonment vs continued-listening

3. **Pairwise interaction detection** (per §15.6.6): auto-detect against top 5 concurrent experiments by traffic overlap. Specifically check shuffle-removal × homepage-redesign, shuffle-removal × personalization-test.

4. **Hash-based assignment** (per §15.6.4) with `salt = experiment_id` — same `user_id` → same variant across all surfaces. Critical: user shouldn't see the button on phone but not desktop.

5. **Launched-layer placement** post-launch: if shipped, graduates from active to launched layer so future album-page experiments don't compete for traffic.

### D. If we don't have enough traffic

In order of preference:

1. **Variance reduction first** (§B) — the 20× gain almost always solves the traffic problem.
2. **Triggering** (§A) — already counted.
3. **Geo subset** — pilot in Sweden / Norway / Denmark / Finland (~30M MAU, Spotify's home markets with deepest data) first. Cultural variance risk; validate with 2–3 other markets before global.
4. **Extended duration** — 8 weeks instead of 4. Doubles power; doubles opportunity cost.
5. **Larger MDE** — only detect bigger effects. Only acceptable when small effects don't change the decision.
6. **Holdback inversion** — ship to 100% with a 1–5% "holdback to old behavior." Gives launch immediately, measures counterfactual. Use when team will ship anyway.

For this experiment: **variance reduction → triggering → geo subset**.

### E. Early peeking — anytime-valid sequential testing

The team *will* peek. Designed for it from day 1 (per §15.1):

**Setup:** design-based confidence sequences (Lindon et al. Netflix 2022) with regression adjustment (CUPED composed with anytime-valid, per §15.2).

**Three simultaneous stop conditions** (per §15.1.5):

| Condition | Rule | Action |
|---|---|---|
| **Efficacy** | Lower bound of OEC CI > +1pp | Launch |
| **Futility** | Upper bound of OEC CI < +1pp | Don't launch — close |
| **Harm** | Lower bound of listening-hours CI < −2pp with high confidence | **Auto-shutoff** |

The harm condition is the most operationally important — optimize for "stop quickly if engagement collapses."

**Cost / benefit:**
- Cost: ~2× sample-size penalty per experiment
- Benefit: median Optimizely experiment stops at ~30% of horizon
- Net: portfolio-level early stopping wins many times over

**Spotify-specific caveat:** the 4-week duration was anchored on novelty fade. Anytime-valid can stop early for *statistical* reasons but shouldn't stop before novelty has settled. **Add a 14-day floor on efficacy stops** (futility and harm can fire from day 1).

### F. Other senior considerations

| Consideration | Action |
|---|---|
| **Pre-experiment effect priors** | Observational analysis: historical variance in album-page completion rate; shuffle-click distribution. Anchor MDE rather than guess. |
| **Platform stratification** | Mobile / desktop / web / CarPlay / Connect have different shuffle propensities. Pre-register segment analysis. |
| **Album-length stratification** | Singles ≈ shuffle = play (degenerate). EPs intermediate. Albums (10+ tracks) primary. Pre-register by length tier. |
| **Geo / market segmentation** | Latin America heavy on full-album listening; US heavy on playlist. Don't assume one effect size globally. |
| **Free vs Premium** | Free has restricted skips → shuffle meaningful even on albums. Premium → may shuffle less. Different effects expected. |
| **Holdback governance** | The 5% permanent holdback can't be in any other launched-album-page experiment for 12 months. Coordinate with platform team. |
| **Creator-side experiment** | Listener experiment changes consumption, which changes artist release-format decisions over 6–12 months. Separate creator-side measurement needed; not in this experiment's scope but document. |
| **External / regulatory** | Some jurisdictions have user-control mandates around content delivery (accessibility). Legal review for regulated markets. |
| **A/A on the triggered population specifically** | Standard A/A on full population isn't enough. Run A/A on triggered subset to verify variance estimates on the analysis cohort. |
| **Reverse-experiment timing** | Anchor to listening-hours stability (± 0.5% week-over-week for 4 consecutive weeks) rather than calendar month 6. |

---

## Final consolidated summary

The Spotify shuffle experiment is better executed as a **triggered, multi-covariate-CUPED-stacked, anytime-valid sequential test on the active album-page UI layer** with mobile / desktop / CarPlay stratification, Free-mobile carved out, and **three simultaneous early-stop conditions** (efficacy / futility / harm). Triggered population analysis combined with multi-covariate CUPED + winsorization drops required $n$ from 40k/arm to ~2k/arm (20× efficiency), making the experiment feasible at 5% of traffic for 2 weeks instead of 50/50 for 4. The anytime-valid framework with a 14-day floor on efficacy stops protects against novelty-driven false positives while letting the harm condition fire from day one. A 5% permanent holdback for 12 months captures long-term LTV; a 6-month reverse experiment validates steady-state once listening-hours stability is achieved. Platform-side: confirm no concurrent album-page UI experiments in the same layer, run pairwise interaction detection against top-5 concurrent experiments, and coordinate the holdback with the platform team for future album-page launches.

---

## Other problems worth running through the skill

Each of these exposes a different staff-level dimension the framework needs to handle. Run them to compare what the skill surfaces vs what it misses, the same way this Spotify example was iterated.

| Problem | Dimension stressed |
|---|---|
| **"LinkedIn wants to test removing the 'Connect' button from suggested-connection cards and replacing with 'Follow.' Plan the experiment."** | Network effects (Connect is bidirectional, Follow isn't); cluster randomization design; multi-sided market (recruiters, members, creators); long-term creator-side effects |
| **"Stripe wants to test rolling out a new SCA / 3DS challenge flow for European card payments. Plan the experiment."** | Regulatory dimension (PSD2 compliance, can't withhold security); quasi-experimental fallback (rollout by issuing bank); sparse outcomes (fraud rates very low → power is binding) |
| **"Uber Eats wants to test surge pricing on restaurants during peak hours. Plan the experiment."** | Hard SUTVA (shared supply); switchback design mandatory; two-sided cannibalization (pricing change affects demand AND supply elasticity) |
| **"Anthropic wants to test a new Claude system prompt for code assistance tasks. Plan the experiment."** | LLM experimentation (per playbook §16.5): win-rate vs LLM-judge vs behavioral A/B; subjective quality; no clean CUPED analog for response quality; open frontier |

---

## Takeaways for using the skill

1. **The first pass is a defensible draft, not a ship-ready plan.** Treat it as the starting structure for a staff-DS conversation.
2. **Always ask: triggering, sequential, platform.** These three are the most-commonly-missed staff moves; the framework prompts for them but the depth pass is where they earn their weight.
3. **Push on variance reduction stacking.** Vanilla CUPED is one technique; the gains compound when you stack triggering + multi-covariate + winsorization + post-stratification.
4. **Make the launch rubric specific.** Numbers, not adjectives. Pre-commit before the data lands.
5. **Use the playbook citations.** When the skill cites `§5.4` or `§15.1`, that's the depth — go read it when you need to defend a choice.
