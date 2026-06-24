# Deep dive: Variance reduction — a worked example of each method

> Expands **[§5 Variance reduction](../ab-testing-playbook.md#5-variance-reduction--the-staff-level-differentiator)**. The playbook lists the five techniques and their formulas; this file runs a concrete, numeric example through **each one** so you can see the size of the win and the price you pay. Running context: a **streaming + commerce app** measuring **revenue per user / week** (skewed), plus a ranker-quality test at the end.

Throughout I use the per-arm sample-size rule of thumb for a *relative* MDE:

$$n \approx \frac{16\,\sigma^2}{\delta^2}=\frac{16\,\text{CV}^2}{\text{MDE}_\text{rel}^2}\quad\text{per arm},\qquad \text{CV}=\frac{\sigma}{\mu}.$$

So **any technique that shrinks the CV (or the effective denominator) shrinks $n$ quadratically through it.** Target: detect a **+2% relative** lift.

---

## 5.1 Filtering / triggering — only count exposed users

**Scenario.** A new one-tap checkout button is only seen by users who reach the cart — **8%** of weekly actives. The other 92% can't possibly be affected, so including them dilutes the effect: $\delta_\text{ITT}=0.08\times\delta_\text{triggered}$.

**Apply.** Analyze only cart-reachers (logged identically on both arms).

**Result.** Required traffic drops by ~$1/0.08\approx\mathbf{12\times}$ — the diluted ITT signal is 12× smaller than the triggered signal, so removing the structural non-exposed is the single biggest lever here.

**Cost / caveats.** The triggered effect ≠ the launch (full-population) number — report both; and the trigger must be **arm-invariant** (no differential triggering, no post-treatment selection).

> **Full treatment — including counterfactual logging, the validity conditions, and two worked examples (Robinhood credit gate + YouTube "Up Next") — is in the [triggered-analysis deep dive](triggered-analysis.md).**

---

## 5.2 Variance-stable transformations

Revenue/user is brutally right-skewed: mean $\mu=\$40$, but a few whales spend $5,000+, so $\sigma\approx\$200$ → **CV ≈ 5**. Naive sample size: $16\cdot 5^2/0.02^2 = \mathbf{1{,}000{,}000}$/arm. Three ways to tame the tail:

**(a) Capping / winsorization.** Clip per-user revenue at the 99th percentile (≈ \$500). The mean barely moves, but $\sigma$ collapses to ≈ \$80 → **CV ≈ 2**.

$$n: \frac{16\cdot 5^2}{0.02^2}=1{,}000{,}000 \;\longrightarrow\; \frac{16\cdot 2^2}{0.02^2}=160{,}000\ /\text{arm}\quad(\mathbf{\sim6\times}\text{ fewer}).$$

*Cost:* you've changed the estimand to "revenue up to \$500/user" — a deliberate decision to stop measuring the whale tail. State the cap and report how much revenue mass sits above it.

**(b) Log transform.** For multiplicative, positive metrics (session duration, watch-time), analyze $\log(1+Y)$. Compresses the tail and turns the test into a **% / multiplicative** change ("treatment lifts watch-time ~3%"). *Cost:* the estimand becomes the **geometric** mean, not the arithmetic mean; `log1p` to handle zeros; back-transform carefully.

**(c) Binarization.** When the tail dominates and you only care about *any vs none*, test **conversion** (`purchased ≥ 1`) instead of revenue. Variance becomes $p(1-p)$, often far smaller relative to signal. *Cost:* you've thrown away magnitude — a +2% conversion lift could still be revenue-negative if it's all tiny baskets, so keep revenue as a guardrail.

**Rule of thumb:** prefer capping/winsorizing when you still want a dollar metric; log when the effect is genuinely multiplicative; binarize only when "did it happen at all" is the real question.

---

## 5.3 Stratified sampling / post-stratification

**Scenario.** Revenue/user differs sharply by platform: iOS $\mu=\$60$, Android $\mu=\$20$, each ~50% of traffic. A big chunk of the *pooled* variance is just this **between-stratum** gap — noise that has nothing to do with treatment.

**Apply.** Use the stratum-weighted (post-stratified) estimator — you don't even need to have stratified the randomization:

$$\hat\Delta_\text{strat}=\sum_s w_s\,\hat\Delta_s,\qquad \sigma^2_\text{strat}=\sum_s w_s^2\sigma^2_s\;<\;\sigma^2_\text{pooled}.$$

```python
# post-stratified ATE: within-stratum effects, traffic-weighted
g = df.groupby(["stratum","arm"])["rev"].mean().unstack("arm")
w = df.groupby("stratum").size() / len(df)
ate_strat = float((w * (g["treat"] - g["control"])).sum())
```

**Result.** The variance reduction equals the share of total variance explained by the strata ($\eta^2$, the correlation ratio). If platform explains **25%** of revenue variance, you cut variance ~25% → **~25% smaller $n$**.

**Cost / caveats.** Gains are capped by how predictive the strata are; too many thin strata add estimation noise. Use a few high-signal strata (platform, new-vs-returning, country tier).

---

## 5.4 CUPED — pre-experiment covariate adjustment

**Scenario.** The best predictor of a user's experiment-week revenue is their **own pre-period revenue**. Suppose $\rho_{X,Y}=0.7$ between 30-day pre-period revenue $X$ and experiment revenue $Y$.

**Apply.** $Y_\text{cuped}=Y-\theta(X-\bar X)$ with $\theta=\text{Cov}(Y,X)/\text{Var}(X)$, then test on $Y_\text{cuped}$.

```python
theta = df["pre_rev"].cov(df["rev"]) / df["pre_rev"].var()
df["y_cuped"] = df["rev"] - theta * (df["pre_rev"] - df["pre_rev"].mean())
# then a normal two-sample test on y_cuped, per arm
```

**Result.** Variance multiplies by $1-\rho^2 = 1-0.49 = 0.51$ — a **~50% reduction**, halving $n$. Continuing the winsorized example: $160{,}000 \to \mathbf{\sim82{,}000}$/arm.

**Cost / caveats.** (1) The covariate **must be measured strictly before randomization** — anything treatment can touch biases the estimate. (2) **New users have no pre-history** → they fall out; analyze them separately or impute. (3) Composes with regression adjustment (add stratum, source, device to the same model).

---

## 5.5 Paired / matched designs

The most powerful when feasible: put the *same unit* under both conditions to cancel between-unit variance entirely. The paired variance is $2\sigma^2(1-\rho)$ (see [test-statistics §3.3](test-statistics-and-sample-size.md)), so high within-unit correlation $\rho$ is the whole game.

**(a) Interleaving (ranker tests).** To compare ranker A vs B, blend their results into **one list** shown to **one user** and measure which side's items win the clicks. Each user is their own control → between-user variance (taste, session length) vanishes. Interleaving is famously **10–100× more sensitive** than a between-user A/B for ranking quality — the canonical paired design. (Deep treatment: playbook §15.3.)

**(b) Switchback (time).** Alternate treatment/control over time slots in the same market/unit — the marketplace analog, used when you can't split users. Carryover is the cost. (See [geo randomization](geo-randomization.md) and §16.1.)

**(c) Matched pairs.** Pre-match users on covariates into pairs, randomize within each pair, analyze the paired differences. A pre-randomization cousin of CUPED.

**Result.** Variance reduction $=(1-\rho)$; with within-unit $\rho=0.8$ that's an **80%** cut. **Cost:** only applicable when a unit can experience both arms without contamination (ranking, latency, pricing-by-time) — for most user-visible product changes it isn't, because of consistency/learning effects.

---

## They compose — stack the multipliers

Variance factors multiply. On the revenue test:

$$\underbrace{\times\tfrac16}_{\text{winsorize (CV }5\to2)}\;\cdot\;\underbrace{\times0.75}_{\text{post-strat }(\eta^2=.25)}\;\cdot\;\underbrace{\times0.51}_{\text{CUPED }(\rho=.7)}\;\approx\;\times0.064$$

≈ **a 16× cut in required traffic** before you even touch triggering. In production you typically layer **triggering → transformation → CUPED/stratification**; that's why variance reduction is "the staff-level differentiator" — it routinely turns "we can't detect this" into a one-week read.

| Method | Typical reduction | What it costs | Reach for it when |
|---|---|---|---|
| **Triggering** (§5.1) | ~$1/\text{exposure}$ (often 5–20×) | effect ≠ launch number; needs arm-invariant trigger | only a fraction of users are exposed |
| **Transformation** (§5.2) | 2–10× (skew-dependent) | changes the estimand (capped/geo-mean/binary) | heavy-tailed metrics (revenue, latency) |
| **Stratification** (§5.3) | $\eta^2$ of variance (10–40%) | gains capped by strata signal | metric varies a lot across known segments |
| **CUPED** (§5.4) | $1-\rho^2$ (30–60%) | pre-covariate only; new users drop | a good pre-period predictor exists |
| **Paired/interleaving** (§5.5) | $1-\rho$ (up to 10–100×) | needs same-unit-both-arms (rare) | rankers, latency, time-sliced markets |

---

## Interview soundbites

- "Sample size goes as $16\,\text{CV}^2/\text{MDE}^2$, so anything that shrinks the CV or the denominator pays off quadratically. I stack triggering, then a tail transform, then CUPED — the variance factors multiply."
- "Winsorizing revenue took the CV from 5 to 2 — a ~6× sample cut — at the price of capping the whale tail, which I report explicitly."
- "CUPED with a pre-period covariate correlated 0.7 halves the variance ($1-\rho^2$). The one rule: the covariate must be strictly pre-randomization."
- "When a unit can take both arms — rankers, latency, time-sliced markets — paired designs like interleaving beat a between-user A/B by 10–100×, because between-user variance disappears."

---

*Back to playbook: [§5 Variance reduction](../ab-testing-playbook.md#5-variance-reduction--the-staff-level-differentiator) · [deep-dive index](README.md)*
