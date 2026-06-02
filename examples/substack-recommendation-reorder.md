# Example — Substack reorders newsletter recommendations

A worked illustration where the design hinges on **ranker change with creator-side spillover**. Substack's newsletter recommendation surface (the "Discover" / sidebar / inline-promotion slots) decides which newsletters reach which readers. Changing the ranker affects (a) reader subscription decisions, (b) creator (newsletter writer) growth trajectories, and (c) the platform's overall content distribution dynamics. The skill should reach for the **§15.3 two-stage interleaving architecture** plus creator-side spillover measurement.

> **Note on provenance.** First-pass plan produced directly using SKILL.md + the loaded playbook. Depth-pass tightens creator-side spillover and interleaving subtleties.

---

## The prompt

```
/ab-test-plan Substack is considering changing the newsletter
recommendation ranker on the Discover surface (Discover homepage,
post-subscribe upsell slots, post-read related-newsletter cards).
The current ranker is a hand-tuned popularity + topical-affinity
model; the candidate ranker is a learned model using collaborative
filtering + reader-engagement signals. Goal is to lift new-newsletter
subscriptions per reader-session while preserving the long-tail
ecosystem (so the new ranker doesn't just send everyone to the top
50 newsletters). Subscription tiers: free reader, free writer, paid
writer (gets % cut of paid subscriptions). Plan the experiment.
```

**Why this problem is a good illustration:**
- Ranker change → §15.3 two-stage interleaving + A/B applies
- Multi-sided platform: readers + writers + Substack itself
- Creator-side spillover: shifted recommendations change writer-side growth
- Long-tail preservation as a guardrail (Goodhart on "subscriptions")
- Paid-writer revenue is the long-term goal
- Skill should specifically reach for two-stage architecture per §15.3

---

## First pass

### 1. Problem framing

- **Decision the experiment informs:** Whether to ship the learned ranker as default on Discover surfaces.
- **Pre-committed decision rubric:** Launch iff composite OEC moves ≥ +3pp on subscription rate AND long-tail-newsletter share of recommended impressions ≥ baseline − 5pp AND new-writer 30-day retention ≥ baseline AND paid-tier writer revenue ≥ baseline. Auto-shutoff iff long-tail share drops > 15pp at $p < 0.005$.
- **Is A/B the right tool?** Yes, with the §15.3 two-stage architecture: **interleaving first** to compare many ranker variants quickly, then **A/B on the winner** for the long-term writer-side measurement. The interleaving stage is fast and powerful (~10–50× variance reduction per §15.3); the A/B stage validates the long-term creator effects that interleaving can't capture.

### 2. Hypothesis

- **Direction:** Learned ranker → better personalization → higher per-impression subscription rate. Risk: collaborative filtering may concentrate on already-popular newsletters → long-tail share drops.
- **Magnitude:**
  - **Per-impression subscription click rate:** +20 to +40% relative (large because the current ranker is hand-tuned and weak)
  - **Per-session subscription rate:** +3 to +6pp absolute
  - **Long-tail newsletter share of impressions** (newsletters outside top 100): −5 to −15pp (the cannibalization risk)
  - **New-writer 30-day retention** (writers with < 50 subscribers): flat to −2pp (concerning — these are the writers most dependent on Discover surface)
  - **Paid-writer revenue per writer:** flat (top-of-distribution writers may gain; long-tail writers may lose; net unclear)
- **Mechanism:** Collaborative filtering captures latent preference signals the hand-tuned model misses. But CF favors popular items by default (the "rich get richer" failure mode); without explicit long-tail regularization, the new ranker concentrates impressions on already-popular newsletters, starving new and niche writers.

### 3. Metric hierarchy

- **Goal metric:** Paid subscription revenue per active reader per quarter (Substack's revenue is % of paid subs).
- **OEC (combined, weights pre-committed):**

$$
\text{OEC} = 0.5 \cdot \Delta(\text{subscription\_rate\_per\_session}) + 0.3 \cdot \Delta(\text{long\_tail\_share}) - 0.2 \cdot \Delta(\text{new\_writer\_churn})
$$

Captures the **personalization gain + ecosystem health tension**. Long-tail share has a positive weight (preservation is a goal); writer churn has a negative weight.

- **Guardrails (FWER at $\alpha = 0.005$, Holm-Bonferroni per §8.2):**
  - **Long-tail newsletter share** (top 100 vs the rest)
  - **New-writer retention (D30, D90)** — writers most dependent on Discover for growth
  - **Paid-tier writer revenue** — Substack's revenue line
  - **Reader engagement on subscribed newsletters** — quality, not just quantity
  - **Recommendation diversity (Shannon entropy of impressions)** — concentration measure
- **Counter metric:** **Concentration metric** — top-50-newsletter share of total impressions. The cannibalization signal.
- **Debug metrics:** per-ranker-cohort subscription funnel, per-newsletter impression and subscription delta, reader-feature × newsletter-feature interaction effects.
- **Gameability check (per §2.2):** "subscription rate per session" gameable by surfacing already-popular newsletters reader is most likely to subscribe to (the collaborative-filtering trap). Mitigation: **long-tail share is a tight-$\alpha$ guardrail**; without it, the ranker collapses to popularity recommendations.

### 4. Randomization

- **Stage 1 — Interleaving (per §15.3):** within each user session, the rendered Discover surface alternates items from the current ranker and the candidate ranker (Team Draft interleaving). Each impression is tagged with its source ranker. Subscription clicks credit the source ranker.
- **Stage 2 — A/B:** if interleaving picks a winner, run a 4-week user-level A/B on the winner vs current ranker to measure (a) long-term subscription value, (b) creator-side spillover.
- **Stratification:** By user activity tier (heavy / medium / light readers); by reader's existing subscription portfolio (general-interest / niche / mixed).
- **Targeting / eligibility:** All readers on Discover surfaces.
- **SUTVA check:** **At the reader level: valid** — one reader's recommendations don't affect another reader's recommendations. **At the writer level: violated** — if treatment surfaces newsletter X more often, writer X's growth trajectory accelerates → affects writer X's future content production → affects long-term readership platform-wide.
- **If SUTVA violated:** Stage 2 A/B with **writer-side cluster analysis** — track writers by their treatment-group impression count over the experiment window; report per-writer-cluster effects on writer churn and revenue.

### 5. Sample size & duration

- **Stage 1 — Interleaving:**
  - Within-session paired design eliminates between-user variance per §15.3
  - **Effective sample size for ranker comparison: 10–50× more efficient than A/B**
  - With ~5M weekly active Substack readers and 10% hitting Discover, ~500k sessions/week
  - Interleaving converges on a winner in 1–2 weeks
  - **Statistic:** sign test on subscription preference within session (binomial test on user-level subscription-source ratio)
- **Stage 2 — A/B for long-term writer-side:**
  - Per-session subscription rate baseline ~5%, $\sigma^2 = 0.0475$
  - MDE 0.5pp absolute → $n = 16 \cdot 0.0475 / 0.000025 = 30{,}400$ readers per arm
  - With CUPED on prior-30-day session count, expected $\rho \approx 0.6$ → 36% reduction. Effective $n \approx 19{,}500$ per arm
  - 4-week duration to capture writer-side growth signals
- **Combined timeline:** 2 weeks Stage 1 + 4 weeks Stage 2 = 6 weeks total. Much faster than running A/B on every ranker variant.
- **Ramp protocol:** Stage 1 immediately at 50/50 interleaving; Stage 2 at 5% → 25% → 50% over week 1, then 50/50 for 3 weeks.

### 6. Trustworthy execution

- **A/A test for interleaving:** present same-ranker items in interleaved positions; verify equal preference signal.
- **SRM analog for interleaving:** verify the two rankers contribute equal-fraction impressions in each session (the team-draft balance check per §15.3.3 unbiasness audit).
- **SRM for A/B:** chi-square on user assignment ratios.
- **Pre-period sanity:** PSI on reader covariates between arms in Stage 2; require < 0.1.
- **Logging audit:** verify each impression's ranker source is correctly attributed to subsequent subscription events; verify reader's subscription clicks are credited to the ranker that generated the impression, not the one shown second.

### 7. Interference & spillover

- **Reader-side:** SUTVA holds; readers are independent.
- **Writer-side:** SUTVA violated. Recommended writers grow faster in the treatment arm; their behavior (posting frequency, content style) responds to growth, affecting their content quality and long-term subscriber retention.
- **Mitigation:** measure writer-side spillover in Stage 2 A/B explicitly. Track each writer's impression count from treatment vs control; cluster writers by impression-share-from-treatment; report per-cluster effects on (a) writer churn, (b) post-frequency, (c) paid-tier revenue.

### 8. Decision rubric (pre-committed)

The launch quadrant per §8.5:

- **Stage 1 launch threshold:** interleaving sign-test win rate > 53% on user-level subscription preference, with no breach of within-session diversity check.
- **Stage 2 launch iff:** composite OEC ≥ +3pp AND long-tail share ≥ baseline − 5pp AND new-writer D30 retention ≥ baseline − 0.5pp AND paid-tier writer revenue ≥ baseline AND no SRM.
- **Auto-shutoff iff:** long-tail share drops > 15pp with $p < 0.005$ OR new-writer D7 retention drops > 5pp with $p < 0.005$.
- **Multiple-testing protocol (per §8.2):** primary OEC at $\alpha = 0.05$; long-tail + new-writer retention guardrails at $\alpha = 0.005$ FWER; writer-side cluster effects at BH within tier.
- **Disagreement protocol:** if Stage 1 interleaving says "candidate wins" but Stage 2 A/B says "candidate hurts long-term writer revenue" — **do not launch**; the short-term subscription gain isn't worth the long-term ecosystem cost.

### 9. Long-term measurement

- **Holdback:** 5% of readers permanently kept on the current ranker for 12 months.
- **Long-term metrics:** reader 90-day subscription retention, writer 90-day retention by impression-tier, paid-tier writer revenue trajectory, long-tail share trend, recommendation diversity (Shannon entropy).
- **Reverse experiment (per §8.3):** at month 6, switch 5% of launched readers back to current ranker for 4 weeks. Validates whether the personalization gain is sticky or whether reader expectations recalibrate.
- **Novelty / primacy mitigation:** plot subscription rate over time; cohort readers by first-exposure date; brand-new readers (joined post-launch) as the steady-state benchmark.

### 10. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Long-tail collapse** (CF concentrates on top newsletters) | **High — dominant risk for CF-based rankers** | Long-tail share at $\alpha = 0.005$ guardrail; pre-launch model retraining if long-tail share too low at offline eval |
| **New-writer churn** (writers below visibility threshold lose Discover share) | High | New-writer retention guardrail; per-writer-tier monitoring; willingness to add long-tail regularization to the ranker if needed |
| Cold-start newsletter exclusion (new newsletters have no engagement history) | High | Explicit cold-start handling in the ranker; A/A test on cold-start newsletters specifically |
| Interleaving doesn't capture writer-side long-term effects | Medium | Stage 2 A/B required — interleaving alone insufficient for launch decision |
| Reader-side novelty effects | Medium | 4-week Stage 2 duration; brand-new-user cohort |
| Cross-experiment interaction with concurrent personalization tests | Medium | Mutual exclusion within the recommendation-layer experiments per §15.6 |
| Paid-tier writer revenue degrades despite engagement gain | Medium-high | Paid-tier writer revenue guardrail; monthly post-launch review during ramp |
| Recommendation diversity / filter-bubble effects | Medium | Shannon entropy of impressions per reader monitored; concentration alarm if entropy drops > 10% |
| Cross-side feedback loop (treatment writers post more → treatment readers see more → loop amplifies) | Medium | Stage 2 A/B duration captures short-loop; quarterly review for long-loop |

### First-pass summary

Substack recommendation ranker change is best executed as a **§15.3 two-stage architecture**: Stage 1 interleaving (Team Draft) on Discover surfaces for fast ranker comparison (~10–50× variance reduction; 1–2 weeks); Stage 2 reader-level A/B (~19k per arm with CUPED; 4 weeks) on the winner to measure long-term subscription value AND writer-side spillover. Combined OEC = 0.5·subscription + 0.3·long-tail-share − 0.2·new-writer-churn. **Long-tail share and new-writer retention are tight-$\alpha$ guardrails** — without them, the CF-based ranker collapses to popularity recommendations (the dominant CF failure mode). Disagreement protocol: if Stage 1 wins but Stage 2 shows long-term writer-side degradation, **do not launch**. 12-month reader holdback; writer-side cluster analysis for per-writer-tier effects.

---

## Depth pass — senior iteration

### A. Interleaving choice and the diversity failure mode

The first pass said "Team Draft interleaving." A senior would push:

1. **Team Draft is right for this case** (per §15.3.1). Alternatives: Balanced Interleaving fails on shift-by-one (close ranker comparisons); Probabilistic Interleaving degrades UX.
2. **But Team Draft has a known failure mode for set-level objectives like diversity.** The interleaving mixes outputs from two rankers, which can break per-set optimization. Per §15.3.3, Airbnb specifically called this out as a case where interleaving misled them. Substack's long-tail-preservation goal is a *set-level* objective — interleaving may underestimate the diversity damage.
3. **Fix:** treat Stage 1 interleaving as a quick prune on subscription rate only; **Stage 2 A/B is mandatory** for the diversity / long-tail / writer-side measurements. Don't ship from interleaving alone.

### B. Two-sided counterfactual evaluation

The first pass framed writer-side measurement as part of Stage 2. A more rigorous approach uses **counterfactual evaluation** per §15.3.4:

- For each newsletter, compute its impression count under treatment ranker vs (counterfactual) under control ranker on the same reader population
- Aggregate per-writer impression deltas; correlate with writer-side metrics (post frequency, paid-sub revenue)
- This is **a separate writer-side analysis**, not a separate A/B — uses the same Stage 2 traffic but a different analytical lens

### C. The CF ranker's specific Goodhart problem

The first pass mentioned "long-tail collapse" generically. The specific mechanism:

- CF predicts subscription probability based on co-subscription patterns
- New / niche newsletters have few subscribers → few co-subscription patterns → CF underrates them systematically
- This is a **data-density bias**, not just a popularity bias
- **Fix:** add explicit cold-start / diversity term to the loss function (negative log-likelihood + $\lambda \cdot$ entropy-of-impressions), tune $\lambda$ via offline eval
- The right $\lambda$ trades off subscription rate vs long-tail preservation; this is the **OEC weights** in math form

### D. Writer-as-customer perspective

Substack has two customer types: readers AND writers. Writers are the *strategic* customer (Substack's revenue depends on paid writers staying). A staff DS would:

1. **Run a writer-side qualitative review.** Survey 100 affected writers after the experiment: did they notice impression changes? How did it affect their motivation, posting frequency, and economic experience?
2. **Treat writer churn as a P0 metric**, not a P2 guardrail. Writers leaving the platform is harder to reverse than readers; their content is the moat.
3. **Pre-commit a writer-defense clause:** if any writer cohort shows > 5pp churn increase, the ranker is retrained with stronger long-tail regularization before any launch.

### E. The platform-mission alignment question

This is the strategic equivalent of LinkedIn's Connect→Follow question (see that example):

- Substack's mission is "fostering an ecosystem where independent writers thrive"
- A CF ranker maximizes reader subscription rate but may concentrate impressions on already-popular writers
- This trades off **subscription efficiency** vs **ecosystem health**
- A staff DS surfaces the strategic question explicitly: does Substack want to be **Spotify for newsletters** (algorithm-driven, popularity-concentrated) or **a writer-discovery platform** (long-tail-preserved, harder to grow but mission-aligned)?
- The OEC's long-tail weight (0.3 in the first pass) reflects this; the experiment is operationally answering this strategic question

### F. The downstream-revenue lag is large

Substack's revenue is a % of paid subscriptions. The lag from reader-impression to paid-subscription-conversion is months:

1. Reader sees recommendation → free subscribe (immediate)
2. Reader engages with newsletter for weeks → considers paid (1–3 months)
3. Reader pays (~3–9 months after first impression)
4. Writer earns Substack revenue (Substack takes 10%)
5. Writer churn / retention decision (~6–24 months)

**Implication:** the 4-week Stage 2 A/B can't observe full paid-revenue impact. The 12-month holdback captures it; quarterly reviews are mandatory.

---

## Final consolidated summary

Substack's recommendation ranker change is best executed as a **§15.3 two-stage architecture**: Stage 1 Team Draft interleaving (1–2 weeks) for fast subscription-rate ranker comparison; Stage 2 reader-level A/B (4 weeks, ~19k per arm with CUPED) for long-term subscription value + counterfactual writer-side analysis. Combined OEC = 0.5·subscription + 0.3·long-tail-share − 0.2·new-writer-churn, with **explicit cold-start / diversity regularization in the ranker's training loss** to prevent the CF concentration failure mode. **Stage 2 is mandatory** — interleaving alone undermeasures set-level objectives like diversity per §15.3.3. **Writer-defense clause**: if any writer cohort shows > 5pp churn increase, the ranker is retrained with stronger long-tail regularization before launch. 12-month reader holdback; writer qualitative survey + cluster analysis. **Strategic alignment review at month 6**: does the resulting recommendation concentration match Substack's "independent writers thrive" mission, or does it drift toward popularity-driven dynamics? Auto-shutoff on long-tail drop > 15pp at $p < 0.005$ OR new-writer D7 retention drop > 5pp at $p < 0.005$.

---

## Key takeaways

1. **Two-stage interleaving + A/B is the right architecture per §15.3.** Interleaving for fast ranker pruning (10–50× variance reduction); A/B for long-term creator-side measurement.
2. **CF rankers have a built-in long-tail bias.** Without explicit diversity regularization, they concentrate on already-popular items. The tight-$\alpha$ long-tail share guardrail catches this.
3. **Interleaving alone is insufficient.** Per §15.3.3, set-level objectives (diversity) and long-term effects (creator churn) aren't captured by interleaving's within-session pairing. Stage 2 A/B is mandatory.
4. **Writers are customers too.** Substack has two customer sides; writer churn is a strategic threat. Treat writer metrics as P0 guardrails, not P2 guardrails.
5. **The strategic question matters.** Subscription-rate optimization vs ecosystem-health preservation is the mission-alignment question. The OEC's long-tail weight is where this tradeoff lives.
