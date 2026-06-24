# Deep dive: Worked examples

> The full worked examples that the playbook references at high level. Each is linked from its section: [§4.4 UAR](../ab-testing-playbook.md#44-worked-example--uar-user-account-recovery), [§8.1 peeking](../ab-testing-playbook.md#81-peeking-and-sequential-testing), [§8.4 Simpson's](../ab-testing-playbook.md#84-simpsons-paradox), [§10.5 MAB](../ab-testing-playbook.md#105-worked-example--mab-beats-ab-for-a-short-lived-headline-test), [§13 Doordash end-to-end](../ab-testing-playbook.md#13-end-to-end-worked-example--doordash-extends-free-delivery-to-non-dashpass-customers).

---

## UAR sample-size example

*Expands [§4.4](../ab-testing-playbook.md#44-worked-example--uar-user-account-recovery).*

A common interview probe: *"Account recovery: lockout rate is 10% of monthly users; the recovery flow has a 50% pass rate. We want to detect a 15% relative improvement. What's the sample size?"*

The point is the **driver-vs-success-metric tradeoff**: success metrics are downstream and rare (small $p$, small $\delta$), so they need huge $n$; driver metrics are upstream and dense ($p$ near 0.5, larger $\delta$), so they need far fewer.

| Metric | What it measures | Baseline $p$ | Relative MDE | Absolute $\delta$ | $\sigma^2 = p(1-p)$ | $n$ per arm |
|---|---|---|---|---|---|---|
| **Success** (% raising lockout ticket) | Downstream outcome | 0.10 | 15% | 0.015 | 0.090 | ≈ 6,400 |
| **Driver** (% passing the recovery flow) | Mid-funnel proxy | 0.50 | 15% | 0.075 | 0.250 | ≈ 711 |

Math with $n \approx 16\sigma^2/\delta^2$ per arm:
- Success: $16 \cdot 0.09 / 0.015^2 = 1.44 / 0.000225 \approx 6{,}400$
- Driver: $16 \cdot 0.25 / 0.075^2 = 4.0 / 0.005625 \approx 711$

**Driver needs ~9× fewer users** for the same relative effect. Two staff takeaways:

1. **Don't power on the rare downstream metric** when a dense upstream proxy moves first — *provided* the proxy is causally linked to the success metric (validate the link on historical experiments — see §2.2).
2. **The $\delta^2$ in the denominator dominates.** A metric at $p = 0.5$ has the largest possible $\sigma^2$, but its absolute $\delta$ for a given relative effect is also largest — and $\delta$ enters squared. Dense metrics often need fewer users than rare ones, despite higher variance per unit.

The pattern in production: experiment on driver metrics for sensitivity, then run a long-running holdback to validate the success metric moves over time.

**Sanity check before launching.**
1. *Does the required $n$ fit in the traffic budget × duration we can afford?* If not, you need variance reduction (§5), a longer window, or a coarser metric.
2. *Have we accounted for the duration multiplier?* You need at least a week to cover day-of-week effects; longer if there's seasonality or novelty.
3. *Is the SRM detector configured?* You should know you'd catch a 50/50 split breaking before you read results.

---

## A/A peeking simulation

*Expands [§8.1](../ab-testing-playbook.md#81-peeking-and-sequential-testing).*

Under H₀ (no real effect) the running test statistic is a *random walk* — as data accumulates the cumulative difference wanders around zero and the p-value bounces up and down. A fixed-horizon test asks "is it past the boundary *at the one pre-set endpoint*?" — true ~5% of the time by construction. A peeker instead asks "does it *ever* cross the boundary at any of my looks?" Each look is another (correlated) chance to cross, so the probability of crossing *at least once* accumulates — the multiple-comparisons problem (§8.2), but across *time*. With continuous monitoring the walk crosses any fixed boundary with probability → 1, so a determined peeker reaches "significance" on pure noise almost surely.

A/A simulation (no true effect; stop early if a two-sample z ever crosses ±1.96), verified:

```
looks  →  false-positive rate (nominal 5%)
   1    →    4.8%     # single fixed look — correct
   5    →   13.8%
  10    →   19.1%
  50    →   30.2%     # peek often enough and ~1 in 3 A/A tests "wins"
```

The fix is to pre-commit a duration, or use a sequential method that widens the boundary at each look — full treatment in [sequential-testing](sequential-testing.md) (§15.1).

---

## Simpson's paradox example

*Expands [§8.4](../ab-testing-playbook.md#84-simpsons-paradox).*

The aggregated treatment effect disagrees with — even *reverses* — every subgroup's effect. It needs two ingredients together: (a) segments with very different baseline rates, **and** (b) a treatment/control split that's *imbalanced across those segments* (from an assignment bug or organic traffic mix).

**Worked example.** A new checkout flow, segmented by device. Treatment beats control *in each segment* yet loses *in aggregate* (verified):

```
            control   treat    diff
Mobile      20.0%     22.0%    +2.0%
Desktop     50.0%     52.0%    +2.0%
AGGREGATE   40.0%     32.0%    -8.0%   ← reverses!
```

How? Treatment was disproportionately served to **Mobile** — the low-baseline segment (2000 treatment users vs 1000 control), while control skewed Desktop. The aggregate treatment rate is dragged down by its heavier mix of low-converting mobile traffic, *not* by the flow being worse. Aggregation confounds the *effect* with the *segment composition*.

**The specific fix — stratify and re-weight.** Compute the effect *within* each segment, then combine with weights equal to each segment's share of the **overall** population (not its per-arm share):

$$\widehat{\text{ATE}} = \sum_s w_s\,\big(\bar y_{s,\text{treat}} - \bar y_{s,\text{control}}\big), \qquad w_s = \frac{n_s}{N}$$

```
stratified (population-weighted) effect = +2.0%   ← recovers the true effect
```

This is the post-stratification / Cochran–Mantel–Haenszel estimator. Two levels of fix:
- **Prevention (best):** **stratified randomization** — assign 50/50 *within* each segment, so the split is balanced by construction and Simpson can't arise from allocation. CUPED / regression adjustment that controls for the segment buys the same protection.
- **Diagnosis:** an imbalanced split within segments is usually an **SRM** symptom (§6.2) — check per-segment assignment ratios before trusting any aggregate.

*Staff reflex:* whenever the aggregate looks suspiciously different from the segments, suspect Simpson, and never report a pooled effect without confirming the arm split is balanced within the segments that drive the metric.

---

## MAB vs A/B — short-lived headline test

*Expands [§10.5](../ab-testing-playbook.md#105-worked-example--mab-beats-ab-for-a-short-lived-headline-test).*

*"You have 5 candidate headlines for a news story that's only hot for a day. A/B/n or bandit?"*

A fixed A/B/n splits traffic **evenly across all 5** for the whole test, so 80% of impressions go to non-winners — and by the time you'd "call" it, the story is cold. A bandit shifts traffic toward the leader *as it learns*, so most impressions land on the eventual winner *during the window that matters*. Simulation over 100k impressions, true CTRs `[3%, 4%, 5%, 4.5%, 3.5%]` (verified):

```
oracle (always the 5% headline): 5000 clicks
Thompson Sampling              : 4782 clicks
A/B/n equal split              : 4015 clicks
→ MAB captured 767 extra clicks (~19% more) during the test itself
```

The 767 clicks are **saved regret** — the opportunity cost A/B/n pays to hold an even split. This is the canonical "MAB more suited" setting from §10.2: **the test period is where the reward is** (short shelf-life), **opportunity cost per losing impression is direct** (lost clicks/revenue), and **many arms** make even-splitting expensive. Contrast §10.3's "A/B wins" conditions — if you needed a clean per-headline causal CTR estimate to feed a downstream model, the bandit's adaptive allocation would break naive inference and you'd want the fixed split instead. Decision rubric: §12.

---

## Doordash end-to-end — free delivery for non-DashPass

*Expands [§13](../ab-testing-playbook.md#13-end-to-end-worked-example--doordash-extends-free-delivery-to-non-dashpass-customers).*

A full-stack staff-level answer to a real interview question.

**Decision.** Should we extend free delivery (currently a DashPass benefit) to non-DashPass customers on orders > $15 from select restaurants?

### Step 0 — Decide if A/B is the right tool

- Treatment is reversible, can target customer-level.
- Effect plausibly detectable (industry priors: free-shipping campaigns move conversion +1–4%).
- The decision is real: would launch only if marginal-customer profit beats the subsidy cost *and* DashPass renewals don't crater.

A/B test is the right tool.

### Step 1 — Frame the OEC

- **Goal metric:** annualized customer LTV (too slow for the experiment).
- **OEC (combined driver):**
  $$
  \text{OEC} = \alpha \cdot \Delta\text{orders/active customer} - \beta \cdot \Delta\text{subsidy spend/active customer}
  $$
  with weights $\alpha, \beta$ committed up front (e.g., $1 \text{ order} = \$X$ contribution, $1 \text{ subsidy } = \$Y$).
- **Guardrails:** DashPass renewal rate (the cannibalization risk), customer complaints, dasher acceptance rate (could rise from larger orders).
- **Counter metrics:** order frequency uplift split by past-30-day DashPass status; spend on the marginal order; restaurant participation.

### Step 2 — Randomization & power

- **Unit:** non-DashPass customer (we're targeting them).
- **Stratify** by recent-90-day order frequency (heavy/light/lapsed) — CUPED-style covariate.
- **Pre-period covariate:** prior-30-day orders/customer (CUPED). Expect 40–60% variance reduction.
- **MDE:** 1.5% on combined OEC (smaller than that, the program doesn't beat its overhead).
- **Sample size:** baseline orders/customer ~ 1.4, $\sigma \approx 1.8$, with CUPED $\sigma_{\text{eff}} \approx 1.1$.
  - Without CUPED: $n \approx 16 \cdot 1.8^2 / (0.015 \cdot 1.4)^2 \approx 1.2M$ per arm.
  - With CUPED: $\approx 460K$ per arm — about 1M total, feasible in ~2 weeks.
- **Duration:** minimum 2 weeks (day-of-week + weekly novelty buffer); flag for primacy/novelty.

### Step 3 — Trustworthy execution

- **A/A test** on the OEC the week prior — confirm uniform p-distribution, calibrate variance for the power calc.
- **SRM monitor** on assignment and on triggered-into-checkout.
- **Triggering:** the change only affects checkout for orders ≥ $15; analyze on **triggered** customers (those who hit a qualifying basket). See [triggered-analysis](triggered-analysis.md).
- **Guardrails** monitored daily with sequential bounds — auto-stop if DashPass renewals drop by > 2% with $p < 0.01$.

### Step 4 — Interference

- This is a one-sided demand change; supply-side spillover is small but non-zero (more demand pulls dashers).
- Run in a few medium-sized markets first; cross-validate with a switchback design before national rollout.
- Use synthetic-DiD on the market-level rollout (companion causal-inference notes).

### Step 5 — Analysis

- Primary OEC test with CUPED + triggering.
- DashPass renewals at $\alpha = 0.005$ (tighter — high-risk guardrail).
- Subgroup analysis: heavy vs light non-DashPass users (Simpson's paradox check).
- Decision rubric pre-committed: launch iff (OEC ≥ MDE) AND (DashPass renewal rate ≥ −0.5pp) AND (no guardrail breach).

### Step 6 — Post-launch

- 5% holdback maintained indefinitely on the non-DashPass population to measure long-term LTV (cannibalization vs net new value).
- Quarterly re-evaluation; reverse experiment on a fresh cohort 6 months in.

### The one-sentence senior version

> *"Because non-DashPass free delivery has a real cannibalization risk and an OEC that depends on subsidy weight, I'd run a CUPED-adjusted user-randomized A/B with triggering on qualifying baskets, primary OEC = orders-minus-subsidy, DashPass-renewal as a tighter-$\alpha$ guardrail, two-week minimum duration, and a permanent 5% holdback to measure the long-term LTV signal that a short test can't see."*

---

*Back to playbook: [§4.4](../ab-testing-playbook.md#44-worked-example--uar-user-account-recovery) · [§8.1](../ab-testing-playbook.md#81-peeking-and-sequential-testing) · [§8.4](../ab-testing-playbook.md#84-simpsons-paradox) · [§10.5](../ab-testing-playbook.md#105-worked-example--mab-beats-ab-for-a-short-lived-headline-test) · [§13](../ab-testing-playbook.md#13-end-to-end-worked-example--doordash-extends-free-delivery-to-non-dashpass-customers) · [deep-dive index](README.md)*
