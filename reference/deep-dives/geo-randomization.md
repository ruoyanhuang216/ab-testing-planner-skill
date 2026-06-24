# Deep dive: Geo randomization — coarse assignment, user-level questions (Uber)

> Expands **[§7 Interference, SUTVA, and two-sided markets](../ab-testing-playbook.md#7-interference-sutva-and-two-sided-markets)** (§7.1 designs, §7.2 the marketplace case) and **[§16.1 Switchback designs at scale](../ab-testing-playbook.md#161-switchback-designs-at-scale--lyft--doordash--uber)**. This is the canonical case where the thing you *care about* (user behavior) and the thing you're *forced to randomize on* (geography) sit at opposite ends of the coarseness ladder — the same coarse-randomize / fine-analyze tension as the [unit-of-analysis trap](unit-of-analysis.md), but with $\rho$ driven by a shared marketplace equilibrium instead of repeat sessions.

---

## 1. The change we're testing

Uber rolls out a **new dispatch algorithm that cuts ETA** (smarter rider↔driver matching). The hypothesis is about **user behavior**: lower wait → more completed trips → higher **trips per active rider** and better **28-day retention**.

So the **analysis unit is the rider** and the metric is **trips/rider** (a per-user mean), plus retention — but as we'll see, we cannot randomize riders.

---

## 2. Why we can't randomize riders

Uber is a two-sided marketplace with a **shared, finite pool of drivers**. Split riders into treatment/control *within a city* and both arms draw from the **same drivers**:

- Treatment riders get matched faster → they consume cars sooner.
- The leftover supply for control riders gets worse (higher ETA/surge) — or, if the algorithm reshuffles, better.

Either way the control group is **contaminated by the treatment through the supply pool**. This is textbook **SUTVA / interference** (§7): a rider's outcome depends on *other riders'* assignment. The measured treatment-minus-control gap then mixes the real effect with **displacement/cannibalization**, and you can manufacture a "win" that is just supply shifted from control to treatment.

```
Within-city rider split (WRONG)              Geo split (RIGHT)
┌───────────────────────────┐               ┌────────────┐ ┌────────────┐
│  shared driver pool        │               │  NYC       │ │  Chicago   │
│  T riders ⇄ C riders       │ ← coupled     │  all T     │ │  all C     │
│  (one rider's match steals │   through     │  true T    │ │  true C    │
│   another's car)           │   supply      │  equilib.  │ │  equilib.  │
└───────────────────────────┘               └────────────┘ └────────────┘
```

---

## 3. The geo design

Randomize **whole markets**: each city is assigned treatment or control. Inside a treated city, *everyone* gets the new dispatch, so the marketplace reaches its true treated equilibrium (ETA, surge, driver earnings) with **no cross-contamination** from control.

| | Randomization unit | Analysis unit |
|---|---|---|
| Geo design | **city / market** (coarse) | **rider** (fine) |

**Variance-reducing variant — switchback.** Instead of splitting cities, *alternate* treatment/control over time blocks within each city (e.g. 1-hour slots); the unit becomes `(city × time-block)`. This uses each city as its own control and removes the brutal between-city variance — at the cost of **carryover** between adjacent slots. This is the Lyft/DoorDash/Uber workhorse (§16.1); the burn-in and slot-size rules there apply directly.

---

## 4. The catch: effective sample size is ~the number of cities, not riders

You have millions of riders, but they're nested in a handful of cities that each sit at **one shared equilibrium**. Reusing the design-effect math from the [unit-of-analysis deep dive](unit-of-analysis.md):

$$\text{DEFF}=1+(m-1)\rho,\qquad n_\text{eff}=\frac{G\cdot m}{1+(m-1)\rho}$$

with $G$ = #cities, $m$ = riders/city (huge), $\rho$ = intra-city correlation (here driven by the shared equilibrium *and* city demographics). For large $m$ this collapses to:

$$\boxed{\,n_\text{eff}\;\approx\;\frac{G}{\rho}\,}$$

**The punchline:** effective sample size is bounded by $G/\rho$ — essentially the number of cities. With 80 markets, treating 4M riders as independent understates the SE by $\sqrt{\text{DEFF}}$, which can be 100×+.

> **The lever changes.** Adding more *riders per city* is nearly free information once you're past a point; **adding more cities (or switchback time-blocks) is the only real power lever.** And cities are wildly heterogeneous (NYC vs. Topeka), so **between-city variance dominates everything** — which is what the analysis below is built to kill.

---

## 5. How to actually do the analysis

You still **report the user-level metric** (trips/rider, retention) — but **inference must happen at the city level**. The menu, roughly in the order I'd layer it:

### 5.1 Collapse to city, infer across cities (honest baseline)
Compute trips/rider *within each city* → $G$ numbers. t-test treatment vs control cities with $G-2$ df. Correct but low-power, and it equal-weights NYC and Topeka.

### 5.2 Difference-in-differences (kill the heterogeneity)
Compare the **pre→post change** in treated cities to the change in control cities. Differences out each city's time-invariant level — the dominant variance source.

$$\hat\tau=(\bar Y^{\text{post}}_T-\bar Y^{\text{pre}}_T)-(\bar Y^{\text{post}}_C-\bar Y^{\text{pre}}_C)$$

This is the geo-experiment workhorse (and the §9 quasi-experiment tool when you can't fully randomize).

### 5.3 Pre-period covariate adjustment / CUPED at the city level
A city's baseline trips/rider is hugely predictive of its experiment-period value, so regressing it out is the single biggest power gain (DiD is the lagged-outcome special case). Same $(1-\rho^2)$ variance reduction as in [test-statistics §3.3](test-statistics-and-sample-size.md), now applied to city-level series.

### 5.4 Synthetic control — when you have only a *few* treatable markets
Can't afford 40 treated cities? Treat 3–5, and for each build a **synthetic twin** = a weighted blend of control cities matching its **pre-period trajectory**, then read the post-period gap. The right tool when $G$ is tiny (links to §7.1 "counterfactual matched markets" and the causal-inference notes on Synthetic DiD).

### 5.5 Valid p-values with few clusters — don't trust asymptotic SEs
With ≲40 clusters, normal-theory cluster-robust SEs are **anti-conservative** (under-cover). Use:
- **Randomization (permutation) inference — the gold standard here.** Re-shuffle the treatment label across cities thousands of times, recompute $\hat\tau$ each time to build the null, and place the observed effect in it. Exact, assumption-light, and it mirrors *exactly how you randomized*.
- **Wild cluster bootstrap** as the regression-based alternative.

### 5.6 User-level regression, if you insist
Fit with **city as the cluster / random effect** (`mixedlm` random intercept per city, or OLS with SEs clustered on city) — then *still* wrap inference in §5.5, because few clusters break the asymptotics. Mechanics + the few-cluster caveat: [unit-of-analysis §5](unit-of-analysis.md).

```python
import numpy as np
# eff: per-city metric (e.g. DiD of trips/rider);  assign: 0/1 labels (40 treat / 40 control)
obs  = eff[assign == 1].mean() - eff[assign == 0].mean()
rng  = np.random.default_rng(0)
null = np.array([
    (lambda p: eff[p == 1].mean() - eff[p == 0].mean())(rng.permutation(assign))
    for _ in range(10_000)
])
p_value = (np.abs(null) >= abs(obs)).mean()   # two-sided, exact-ish via Monte Carlo
```

---

## 6. What I'd actually recommend

1. **Design:** switchback on `(market × hour-block)` if carryover is short; otherwise a market-level geo holdout with **40+ matched-pair markets** (pair NYC-like with NYC-like).
2. **Primary analysis:** DiD on city-level (or pair-level) **trips/rider**, with the pre-period as a covariate (CUPED).
3. **Inference:** **randomization inference** across markets — *not* asymptotic SEs.
4. **Report** user-level effects (trips/rider, retention) but always with city-level variance.

---

## 7. Pitfalls specific to this design

- **Border spillover** — riders/drivers cross between an adjacent treated and control city → leakage. Use geographically separated markets or buffer zones.
- **Carryover (switchback)** — supply from the previous regime lingers; drop a burn-in window at the start of each slot (§16.1).
- **Few-cluster over-confidence** — the #1 way these tests lie; never report normal-theory SEs with ~80 clusters.
- **One mega-city dominating** a size-weighted estimate; **SRM at the city level**; **seasonality** across the pre/post windows.

---

## 8. Interview soundbites

- "In a marketplace I can't randomize riders — the arms share one driver pool, so treatment cannibalizes control through supply. I randomize whole markets (or switchback on market×time) to contain the spillover."
- "The trap is thinking I have millions of observations. With a shared equilibrium, my effective $n$ is ~$G/\rho$ — the number of *cities*, not riders. More users per city is nearly free; more cities (or time-blocks) is the real lever."
- "I report user-level metrics but infer at the city level — DiD with a pre-period covariate to kill between-city variance, and **randomization inference** for the p-value because asymptotic cluster SEs lie with ~40 clusters."
- "Few treatable markets → synthetic control. Short carryover → switchback for power. Always check border spillover."

---

*Back to playbook: [§7 Interference & two-sided markets](../ab-testing-playbook.md#7-interference-sutva-and-two-sided-markets) · [§16.1 Switchback at scale](../ab-testing-playbook.md#161-switchback-designs-at-scale--lyft--doordash--uber) · [deep-dive index](README.md)*
