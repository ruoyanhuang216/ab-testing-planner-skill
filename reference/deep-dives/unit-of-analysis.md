# Deep dive: The unit-of-analysis trap — ICC, DEFF, and the four fixes

> Expands **[§3 Randomization unit & unit of analysis](../ab-testing-playbook.md#3-randomization-unit--unit-of-analysis)** of the playbook — specifically the *Coarseness-vs-power tradeoff* and the *Unit-of-analysis trap*.

The distinction between the **unit of randomization** (where you flip the coin) and the **unit of analysis** (the row in your hypothesis test) is where many well-intentioned A/B tests quietly break. Get it wrong and you ship phantom wins: noise dressed up as significance.

---

## 1. The rule: who should be coarser?

**The randomization unit must be at least as coarse as the analysis unit.**

- Analyze at the **session** level → you may randomize at the session, user, or geo level.
- You may **not** randomize at the **page-view** level and analyze at the **session** level.

Violating this is a SUTVA-flavored trap: it breaks the independence assumption that standard hypothesis tests rely on.

```
        coarser  ─────────────────────────────────►  finer
        geo / cluster  >  user  >  session  >  page-view  >  event

        randomization unit  ──must be at least as coarse as──►  analysis unit
```

---

## 2. Why would they ever differ?

Keeping them **the same is the default and is preferred.** Randomize by user, analyze by user (conversion per user, revenue per user): observations are i.i.d., the math is clean, no correction needed.

They diverge when business logic wants a **granular metric** (session length, CTR per page-view, order-completion rate per session) but UX or SUTVA constraints force a **coarser randomization unit**:

- **Consistent UX.** Testing a new checkout flow: if you randomize by *session*, a returning user sees the old flow Tuesday and the new flow Wednesday → confusion, frustration, novelty/change-aversion learning effects. You randomize by **user** to keep the experience stable — even though the metric you care about is "checkout success rate per **session**."
- **Spillover / SUTVA.** In a two-sided market or social network you randomize at the **cluster/geo** level to contain network effects, but you still want to read the impact on individual **user** engagement.

In both cases: coarse randomization unit, fine analysis unit → you owe a variance correction.

---

## 3. The math: why naive t-tests over-reject

Say you randomize by **user** but your analysis dataframe has **one row per session**. A standard t-test assumes every row is independent. But sessions from the same user are correlated — a power user's sessions are all similarly engaged.

Let:
- $m$ = average number of sessions per user,
- $\rho$ = **intraclass correlation coefficient (ICC)** — how similar sessions from the same user are.

The variance of the sample mean is inflated by the **design effect (DEFF)**:

$$\text{DEFF} = 1 + (m-1)\rho$$

Naive i.i.d. math estimates the variance as $\dfrac{\sigma^2}{N_\text{total}}$, but the **true** variance is:

$$\text{Var}_\text{true}(\bar{Y}) = \frac{\sigma^2}{N_\text{total}}\big[\,1 + (m-1)\rho\,\big]$$

The t-statistic is $\;t = \dfrac{\Delta}{\sqrt{\text{Var}(\bar{Y})}}$. Because $\rho > 0$ for within-user behavior, the naive denominator is **too small**, so $t$ is **artificially inflated** → **massive over-rejection of the null**. Your A/A tests fail and you "ship significance" that is pure noise.

**Numerical feel.** With $m = 5$ sessions/user and $\rho = 0.3$:

$$\text{DEFF} = 1 + (5-1)(0.3) = 2.2$$

True variance is **2.2×** the naive estimate, so the naive SE is understated by $\sqrt{2.2} \approx 1.48\times$. Every t-stat is ~48% too big, and your effective sample size is not $N_\text{sessions}$ but $N_\text{sessions}/\text{DEFF}$ — barely more than 2 sessions' worth of *independent* information per user.

---

## 4. The four fixes (simple → scalable)

| # | Fix | Idea | Best when |
|---|---|---|---|
| 1 | **Roll-up to user-level** | Collapse to one row per user | Metric is a simple per-user mean |
| 2 | **Delta method** | Analytic variance for a ratio-of-sums | Production, ratio metrics, huge $N$ |
| 3 | **Cluster-robust SE (CRSE)** | Regression + sandwich covariance clustered on user | You want a regression / covariates / CUPED in the same model |
| 4 | **Cluster (block) bootstrap** | Resample *users*, recompute metric | Weird metric, no clean closed form (quantiles, custom ratios) |

### Fix 1 — Roll-up to a user-level metric (the cleanest)

Aggregate 10 session-rows for a user into **one** row: "mean session length per user" or "total clicks per user." i.i.d. is instantly restored; run a normal Welch t-test.
**Tradeoff:** you discard between-session variance information, so power drops a little — but the test is honest.

### Fix 2 — Delta method (the production standard)

For a ratio-of-sums metric $R = \dfrac{\sum Y_i}{\sum X_i} = \dfrac{\bar Y}{\bar X}$ (e.g. orders / sessions), aggregate numerator $Y_i$ and denominator $X_i$ **per user**, then:

$$\text{Var}(R) \approx \frac{1}{\bar X^2}\Big[\,\text{Var}(\bar Y) - 2R\,\text{Cov}(\bar X, \bar Y) + R^2\,\text{Var}(\bar X)\,\Big]$$

This computes variance at the **randomization unit** (user) while still evaluating a **granular ratio** (per-session). It's what large-scale platforms use because it's $O(N)$ and needs no resampling. (See also the playbook's quantile-bootstrap note in §15.4 for when the delta method *doesn't* apply.)

---

## 5. Fix 3 — Cluster-robust standard errors (CRSE), step by step

**Setup (running example).** DoorDash tests a checkout change. Randomization unit = **user**; metric = **order-completion rate per session** (binary `completed ∈ {0,1}` per session). Data is **long**: one row per session.

| user_id | treat | completed |
|---|---|---|
| u1 | 1 | 1 |
| u1 | 1 | 1 |
| u1 | 1 | 0 |
| u2 | 0 | 0 |
| u2 | 0 | 1 |
| … | … | … |

**Steps.**

1. **Build the long dataframe** — one row per session, with columns `user_id`, `treat` (0/1 from assignment), `completed`.
2. **Fit OLS** of the outcome on the treatment indicator:
   $$\text{completed}_{ij} = \beta_0 + \beta_1\,\text{treat}_i + \varepsilon_{ij}$$
   The coefficient $\hat\beta_1$ is the ATE — numerically identical to the naive difference in session completion rates. (A linear probability model is fine here; the *point estimate* isn't the problem, the *SE* is.)
3. **Recognize the naive SE is wrong** — default OLS SEs assume independent rows; sessions within a user are correlated, so they're too small.
4. **Apply the cluster-robust (Huber–White sandwich) covariance, clustered on `user_id`:**
   $$\hat V_\text{cluster} = (X'X)^{-1}\Big(\sum_{g=1}^{G} X_g'\,\hat u_g \hat u_g'\,X_g\Big)(X'X)^{-1}$$
   where $g$ indexes the $G$ user-clusters, $X_g$ are that user's rows, and $\hat u_g$ their residuals. Intuition: it stops treating each session as fresh information and lets residuals correlate **arbitrarily within a user**, **independent across users**. A finite-sample factor $c = \frac{G}{G-1}\cdot\frac{N-1}{N-K}$ is usually applied.
5. **Re-read the inflated SE.** $\text{SE}_\text{cluster} \approx \sqrt{\text{DEFF}}\times \text{SE}_\text{naive}$ — the ~1.48× from §3 reappears here mechanically.
6. **Recompute** $t = \hat\beta_1 / \text{SE}_\text{cluster}$, its p-value, and the CI $\hat\beta_1 \pm 1.96\,\text{SE}_\text{cluster}$.

**Code.**

```python
import statsmodels.formula.api as smf

# df: long, one row per session
naive  = smf.ols("completed ~ treat", data=df).fit()
robust = smf.ols("completed ~ treat", data=df).fit(
    cov_type="cluster",
    cov_kwds={"groups": df["user_id"]},      # cluster on the RANDOMIZATION unit
)

print(naive.bse["treat"])     # too small
print(robust.bse["treat"])    # ~sqrt(DEFF) larger — the honest SE
print(robust.summary())
```

**Caveats.**
- CRSE is **asymptotic in the number of clusters $G$**, not rows. With few clusters (e.g. geo experiments with ~20 regions) it under-covers — use wild-cluster bootstrap or a small-cluster correction instead.
- Cluster on the **randomization unit** (user), not the analysis unit (session). Clustering at the wrong level silently does nothing.
- Want variance reduction too? Add covariates / pre-period outcome (CUPED) to the same regression and keep the clustered SE — that's the main reason to prefer CRSE over Fix 1.

---

## 6. Fix 4 — Block / cluster bootstrap, step by step

When the metric has no clean closed-form variance (quantiles, custom ratios, capped metrics), estimate variance **empirically** — but resample at the **randomization unit**, not the analysis unit. Resampling sessions would destroy the within-user correlation and reproduce the naive bug; resampling **users** preserves it.

**Same DoorDash example.** Statistic of interest: $\Delta = \text{(session completion rate | treat)} - \text{(session completion rate | control)}$.

**Steps.**

1. **List the unique randomization units** — the $G$ `user_id`s, each tagged with its arm. (Keep arms separate so the bootstrap respects the design.)
2. **Resample users with replacement.** Draw $G$ users with replacement. If user `u1` is drawn twice, **all of `u1`'s sessions come along twice** — this is what carries the intra-user correlation into the resample.
3. **Recompute the statistic** $\Delta^{(b)}$ on the resampled session set.
4. **Repeat** for $b = 1 \dots B$ (use $B \ge 1{,}000$; $10{,}000$ for stable tails).
5. **Read off the variance / CI:**
   - $\text{SE} = \text{std}\big(\{\Delta^{(b)}\}\big)$,
   - 95% CI = the **2.5th and 97.5th percentiles** of $\{\Delta^{(b)}\}$ (percentile method),
   - approximate two-sided p-value = fraction of $\{\Delta^{(b)}\}$ on the opposite side of 0, doubled — or invert the CI.

**Code.**

```python
import numpy as np, pandas as pd

def stat(d):  # session completion-rate difference
    g = d.groupby("treat")["completed"].mean()
    return g.loc[1] - g.loc[0]

# index sessions by their user so we can pull whole users at once
by_user = {uid: g for uid, g in df.groupby("user_id")}
users   = np.array(list(by_user.keys()))
rng     = np.random.default_rng(0)

B, boot = 10_000, []
for _ in range(B):
    pick   = rng.choice(users, size=len(users), replace=True)  # resample USERS
    sample = pd.concat([by_user[u] for u in pick])             # all their sessions ride along
    boot.append(stat(sample))

boot = np.array(boot)
print("SE       :", boot.std(ddof=1))
print("95% CI   :", np.percentile(boot, [2.5, 97.5]))
print("p (2-sided):", 2 * min((boot < 0).mean(), (boot > 0).mean()))
```

**Caveats.**
- For two arms, the cleanest version resamples users **within each arm** separately (stratified), so each bootstrap keeps the original per-arm user counts. The snippet above resamples the pooled user list, which is fine when arm sizes are large and balanced; stratify when they're not.
- Like CRSE, the bootstrap is asymptotic in **clusters**; with few users/clusters it's unreliable.
- This is the same machinery as the **quantile bootstrap** in playbook §15.4 — just resampling users instead of a single i.i.d. column.

---

## 7. Which fix should I reach for?

```
Is the metric a simple per-user mean (e.g. revenue/user)?
        └─ yes → Fix 1 (roll-up). Done.
Is it a ratio-of-sums (orders/sessions) at huge N, in a production pipeline?
        └─ yes → Fix 2 (delta method). O(N), no resampling.
Do you want covariates / CUPED / a regression interface?
        └─ yes → Fix 3 (CRSE), clustered on the randomization unit.
Is it a gnarly functional (quantile, custom ratio, capped metric) with no clean variance?
        └─ yes → Fix 4 (cluster bootstrap), resampling the randomization unit.
Few clusters (≈ <40 geos/regions)?
        └─ avoid plain CRSE → wild-cluster bootstrap / small-sample correction.
```

All four recover the **same honest variance**; they differ only in cost, flexibility, and what metric shape they handle.

---

## 8. Interview soundbites

- "The randomization unit must be **at least as coarse as** the analysis unit — otherwise within-cluster correlation makes the naive variance too small and you over-reject."
- "The inflation is the **design effect**, $1 + (m-1)\rho$. With 5 sessions/user and ICC 0.3 that's 2.2× the variance, so naive t-stats run ~1.5× too hot."
- "Four fixes, increasing flexibility: roll-up to user-level, delta method for ratios, cluster-robust SEs, cluster bootstrap. CRSE if I want covariates/CUPED in the model; bootstrap if the metric has no closed-form variance."
- "Whatever I do, I **cluster/resample on the randomization unit**, not the analysis unit — that's the whole point."

---

*Back to playbook: [§3 Randomization unit & unit of analysis](../ab-testing-playbook.md#3-randomization-unit--unit-of-analysis) · [deep-dive index](README.md)*
