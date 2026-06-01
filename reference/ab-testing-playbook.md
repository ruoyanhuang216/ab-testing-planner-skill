# A/B Testing — Staff-Level Deep Dive

Most A/B testing interview answers stop at "split users 50/50, run a t-test, look for `p < 0.05`." That answer reveals a junior. Staff-level A/B testing is about the **eight things juniors don't know they don't know**:

1. **You usually shouldn't A/B test.** Logging, ramps, opportunity cost, and the time it takes to read a result all have a price. Half the staff-level move is deciding whether the experiment is worth running at all.
2. **The metric you pick is 80% of the answer.** OEC design — guardrails, drivers, dilution, attribution — is what separates a senior answer from a textbook one.
3. **Power and MDE are business questions, not statistical ones.** The hardest part of sample-size math isn't the formula; it's defending the MDE you chose.
4. **Variance reduction is where modern A/B testing actually lives.** CUPED, triggering, stratification, and paired designs can buy you 2–10× sensitivity on the same traffic.
5. **A/A tests, SRM, and pre-experiment sanity checks** catch most of the bugs that ship as launches.
6. **SUTVA gets violated more than it holds.** Two-sided markets, social networks, shared resources, and time-locked decisions all need cluster, switchback, or geo designs.
7. **Sometimes you can't randomize.** Quasi-experiments (DiD, RDD, IV, synthetic control, DML) are the toolkit; knowing when to reach for which is staff-level.
8. **Reading a result is harder than running it.** Peeking, multiple comparisons, novelty/primacy, Simpson's paradox, and the practical-significance vs statistical-significance quadrant decide whether you ship.

This guide walks each of these in the order an interviewer probes them. Numbered math, decision tables, worked examples, and a Doordash-flavored end-to-end case at the close.

> **Companion notes.** Quasi-experimental detail (DiD/RDD/IV/synthetic control/DML, sensitivity analysis, uplift) lives in [`ml-interview-prep/algorithms/notes/causal_inference.md`](../../../repos/ml-interview-prep/algorithms/notes/causal_inference.md). Time-series considerations (seasonality, novelty fade, holdback dynamics) overlap with [`time_series_forecasting.md`](../../../repos/ml-interview-prep/algorithms/notes/time_series_forecasting.md). This guide cross-links rather than duplicates.

---

## 1. The strategic frame — when (not) to A/B test

Before the math, decide whether an experiment is the right tool. The questions to ask in order:

| Question | Implication |
|---|---|
| **Is there a tractable causal question?** | If not (e.g., "is the brand strategy working?"), an experiment will tell you nothing useful — use observational analysis instead. |
| **Can we even randomize the unit?** | If the treatment affects everyone (pricing change site-wide, regulatory rollout), there's no control group — go quasi-experimental. |
| **Is the change reversible and ethically OK to withhold?** | Some changes (security patches, legal compliance) can't be A/B tested. |
| **Is the expected effect detectable?** | If your power analysis says you'd need 10× your daily traffic to detect a 0.1% lift, you're in long-run / holdback / pooled-evidence territory, not an A/B test. |
| **Will the answer change a decision?** | If both arms of the result lead to the same action, the experiment is wasted resources. State the decision rubric *before* running. |
| **Is now the right time?** | Holidays, launches, regime changes (post-COVID, post-pricing-change) all introduce variance that can swamp your effect. Sometimes the right move is to wait. |

A staff reflex: **the framing question is what an interviewer scores you on**. Most junior answers jump to "I'd split 50/50…" without ever stating the decision the experiment is meant to inform. State it explicitly: *"This experiment exists to inform decision D between options X and Y; we'll launch if metric M moves by at least Δ with confidence at least 1 - α."*

---

## 2. Metric strategy — OEC, drivers, guardrails

A senior A/B-testing answer designs a **metric hierarchy**, not a single metric.

### 2.1 The three tiers

| Tier | What it does | Failure mode |
|---|---|---|
| **Goal / North Star** | The thing the company ultimately cares about (DAU, GMV, retention, customer LTV) | Slow-moving, dilute, often insensitive in a single experiment |
| **Driver (OEC)** | Short-term, sensitive, *causally upstream* of the goal — the thing the experiment is actually scored on | Often *over-fit* to short-term impact and miss long-term harm |
| **Guardrails** | Things that must NOT degrade: latency, error rate, click-bait proxies, fairness, regret signals | Easy to ignore until they hurt the brand |

Add two more practical tiers staff-level answers carry but juniors forget:

- **Counter / debug metrics** — the symptoms you'd look at to diagnose *why* the OEC moved (search query rewrites, retry counts, downstream funnel steps).
- **Long-term holdback metrics** — what you measure in a small population kept on control indefinitely, to detect novelty fade or harm that takes weeks to surface.

### 2.2 Picking the OEC — the senior moves

A good OEC is:

- **Sensitive** — moves enough in a single experiment to be detectable with available traffic. CTR > DAU > LTV in sensitivity.
- **Timely** — measurable within the experiment window, not in 90 days.
- **Attributable** — caused by the change being tested, not by ten other things.
- **Aligned** — moving the OEC actually moves the goal metric, validated by *prior* experiments or observational analysis.
- **Hard to game** — incentives matter: short-term revenue is gameable by aggressive coupons; engagement is gameable by clickbait.

Staff-level practice **validates the OEC link to the goal using past data** ("the last 6 experiments that moved CTR +X% saw downstream retention move +Y%"). If you can't show that, you don't actually know what your OEC tells you.

### 2.3 The combined OEC (weighted)

When several driver metrics matter (e.g., bookings + cancellations + customer satisfaction), combine them into one number:

$$
\text{OEC} = \sum_i w_i \cdot z_i
$$

where each $z_i$ is the normalized (z-scored or % change) driver metric. The weights $w_i$ encode the **business tradeoff**: a senior states the weights explicitly *before* the experiment, because choosing them after sees the data invites cherry-picking. Microsoft's *Trustworthy Experiments* book recommends **no more than 5 driver metrics**; beyond that, the false-rejection rate from multiple testing washes out the signal.

**Example.** *Doordash, free-delivery rollout to non-DashPass customers.* OEC candidates:

| Candidate | Why it's tempting | Why it fails as primary |
|---|---|---|
| Orders per active customer | Direct, sensitive | Doesn't price in the subsidy cost |
| Net contribution margin per order | Right business answer | Slow, noisy, dilute |
| (Orders / customer) × (margin / order) | Combined OEC | Better — captures both lift and cannibalization of DashPass |
| New-DashPass-signup rate | Guardrail | This is exactly what you'd cannibalize, so it's the guardrail to watch |

**Sanity check before using an OEC.**
1. *Does moving the OEC in the past actually predict moving the goal?* If you have no causal chain evidence, you have a guess, not an OEC.
2. *Is your OEC gameable in a way the team would notice — and a way they wouldn't?*
3. *Will a 10% move in the OEC actually change the launch decision?* If not, you're measuring vanity.

---

## 3. Randomization unit & unit of analysis

The randomization unit is the level at which you flip a coin; the analysis unit is the row in your hypothesis test. **The randomization unit must be at least as coarse as the analysis unit.** Violating this is the most common SUTVA-flavored bug.

| Unit | Pros | Cons | When |
|---|---|---|---|
| **User ID** | Stable across devices & time, consistent UX | Requires login event before assignment; PII concerns | Anything user-visible |
| **Cookie / device** | Anonymous, no-login | Cleared, not cross-device, can be spoofed | Anonymous web experiences |
| **Session** | Finer granularity → higher power | Same user gets different experiences → inconsistent UX | Only when change isn't user-visible (ranker tweaks behind the scenes) |
| **Geo / region** | Captures network effects, ideal for two-sided markets | Few units → high variance → low power | Two-sided markets, regulated rollouts |
| **Time slot (switchback)** | Same population, less variance | Carryover effects, hour-of-day confounds | Two-sided markets where geo isn't viable |
| **Cluster** (network neighborhood, household) | Internalizes spillovers | Cluster count drives power, bias-variance tradeoff in cluster definition | Social/network products |

**Coarseness-vs-power tradeoff.** Coarser units have more variance per unit (geo > user > session) but better internalize spillovers. The right tradeoff depends on **how strong the spillover is** — see §7 on network effects.

**Unit-of-analysis trap.** If you randomize by user but analyze by session (e.g., "average session length"), repeated sessions per user induce within-cluster correlation; naive t-tests will *understate* the variance and over-reject. Fixes:

1. **Use a user-level metric** — collapse to one row per user (mean session length per user). Loses information but is clean.
2. **Delta method** — analytical variance for ratio-of-sums metrics.
3. **Bootstrap at the randomization unit** — resample users, recompute the metric, repeat.
4. **Cluster-robust standard errors** — regression with clustered SEs.

**Example.** *Doordash, ranker tweak that may show different restaurants on different sessions.* If you randomize by user, the ranker is consistent per user → clean. If you randomize by session, a hungry customer's "good" session can pull the next session's expectation — and you have within-user correlation. The right answer depends on whether the change can be invisible across sessions; if yes, session randomization gives more power, but you must analyze with the right variance.

---

## 4. Sample size & MDE — the math behind the number

### 4.1 The formula

For a two-sample t-test on means with significance level $\alpha$ (typically 0.05) and power $1-\beta$ (typically 0.80):

$$
n \;=\; \frac{2 \sigma^2 (z_{1-\alpha/2} + z_{1-\beta})^2}{\delta^2}
$$

where $\sigma^2$ is the metric variance per unit and $\delta$ is the **minimum detectable effect (MDE)** in absolute terms. For $\alpha=0.05$, $\beta=0.20$, $(z_{0.975}+z_{0.80})^2 \approx (1.96 + 0.84)^2 \approx 7.84$, so the rule-of-thumb form is:

$$
n \;\approx\; \frac{16\,\sigma^2}{\delta^2} \quad \text{per arm.}
$$

For binary metrics (CTR, conversion, retention), $\sigma^2 = p(1-p)$ at the baseline proportion $p$. For relative MDE (e.g., "detect a 2% lift"), substitute $\delta = p \cdot \Delta_{\text{rel}}$.

### 4.2 Intuitions to recite

The interviewer expects you to know how each lever moves the sample size:

| Lever | Effect on $n$ |
|---|---|
| Tighter $\alpha$ (e.g. 0.01 vs 0.05) | $n$ increases (squared $z$ effect) |
| Higher power (e.g. 0.90 vs 0.80) | $n$ increases |
| Larger variance $\sigma^2$ | $n$ increases linearly |
| Smaller MDE $\delta$ | $n$ increases *quadratically* — the big one |
| Skewed metric (revenue per user) | Effective $\sigma^2$ much larger than the mean suggests — use winsorization / log-transform / capping or **switch to a ratio metric** |
| Triggering (only count exposed users) | Effective $n$ shrinks (only triggered count) but $\delta$ relative to triggered users grows |

### 4.3 The MDE question — the senior move

The math is mechanical; **defending your MDE choice** is what an interviewer probes. Two valid anchors:

1. **Practical significance.** What's the smallest effect the business would *act on*? Below that, the experiment is wasted. State it: *"a 0.5% lift in net contribution margin is the minimum that pays for the implementation and ongoing ops cost; below that we wouldn't launch."*
2. **Historical experiment effects.** Past experiments in this product area have produced lifts of e.g. 0.5–2% on this metric; pick the smallest lift that would still matter.

Anti-patterns:
- "We'll detect a 10% lift" when typical effects are 1–2% — you'll never see anything significant.
- "We'll detect a 0.01% lift" — you don't have the traffic; the experiment is impossible.
- Picking MDE *after* seeing the data — you've invalidated the test.

### 4.4 Worked example — UAR (User Account Recovery)

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
1. *Does the required $n$ fit in the traffic budget × duration we can afford?* If not, you need variance reduction (next section), a longer window, or a coarser metric.
2. *Have we accounted for the duration multiplier?* You need at least a week to cover day-of-week effects; longer if there's seasonality or novelty.
3. *Is the SRM detector configured?* You should know you'd catch a 50/50 split breaking before you read results.

---

## 5. Variance reduction — the staff-level differentiator

For the same traffic, variance reduction is the lever that turns "we can't detect this" into "we can." Five techniques in roughly ascending sophistication.

### 5.1 Filtering / triggering — only count exposed users

If only some users actually see the change, including the untreated dilutes the effect:

$$
\text{ATE on exposed} = \frac{\text{ITT}}{\text{exposure rate}}.
$$

**Trigger** analysis logs both *who was assigned* and *who actually saw the treatment*, then analyzes only the triggered population on both arms. This is the **single highest-leverage move** in modern A/B practice — especially for ranker / personalization changes where only a fraction of users hit the changed code path.

**Counterfactual triggering** (the more rigorous form): for each user in *either* arm, predict whether they *would have* been triggered under the *other* arm using logged features. Compare actual vs counterfactual outcomes on the consistent triggered population. This eliminates the selection bias from differential triggering rates between arms.

**Sanity check before using triggering.**
1. *Is the triggering condition logged identically on both arms?* If only the treatment arm logs the trigger, you have selection bias.
2. *Did the change itself shift the triggering rate?* If treatment makes more users trigger, the populations differ and you're comparing apples to oranges. Use counterfactual triggering or the ITT.
3. *Is the triggered population large enough?* Triggering shrinks $n$ — see §5.5.

### 5.2 Variance-stable transformations

| Transformation | When |
|---|---|
| **Capping / winsorization** | Long-tail revenue, GMV — clip at the 99th percentile per user |
| **Log transform** | Multiplicative, right-skewed metrics — interpret as % change |
| **Binarization** | When the tail dominates and you care about "any" vs "none" (e.g., "converted at all" rather than revenue) |

Each costs something — capping loses extremes, log changes the estimand. State what you give up.

### 5.3 Stratified sampling

If the metric variance is heterogeneous across known segments (new vs returning users, mobile vs web), randomize *within* strata. The stratified-mean estimator has variance:

$$
\sigma^2_{\text{strat}} = \sum_s w_s^2 \sigma^2_s \;<\; \sigma^2_{\text{pooled}} \quad \text{(usually).}
$$

In practice, post-stratification (analyze with stratum-weighted estimator even if randomization was unconditional) recovers most of the gain.

### 5.4 CUPED — variance reduction using pre-experiment data

The standard variance-reduction technique. For each user, take a *pre-experiment* covariate $X$ correlated with the post-experiment outcome $Y$ (e.g., 30-day pre-period revenue), and form:

$$
Y_{\text{cuped}} = Y - \theta (X - \bar X), \quad \theta = \frac{\text{Cov}(Y, X)}{\text{Var}(X)}.
$$

Then run the test on $Y_{\text{cuped}}$. The variance reduction is approximately:

$$
1 - \rho^2_{X,Y}
$$

where $\rho$ is the correlation between pre and post. **A correlation of 0.7 reduces variance by 50%**, halving the required sample size. In practice, well-chosen covariates (the same metric, pre-period) deliver 30–60% reduction.

**Sanity check before using CUPED.**
1. *The covariate must be measured strictly before randomization.* Using anything that could be affected by treatment biases the estimate.
2. *New users with no pre-history fall out.* Plan for them — either run a separate analysis on new users or use a hybrid imputation.
3. *Regression-style adjustments compose with CUPED* — you can also adjust for stratum, traffic source, etc.

### 5.5 Paired / matched designs

When you can run the same user under both conditions (e.g., switchback in time, or interleaved ranking results), you eliminate between-user variance and only see within-user variance. This is enormously powerful when within-user variance is small (rare).

---

## 6. Trustworthy execution — the pre-result checklist

Before reading results, every staff-level review asks the same questions.

### 6.1 A/A tests

Split users into two arms that get the *same* experience and verify:

- The p-value distribution across many simulated tests is **uniform** on [0, 1].
- Type I error matches $\alpha$ (~5% of tests significant at $p<0.05$).
- Metric variance estimates match prior knowledge — used to power future tests.
- No SRM (sample ratio mismatch).

Run A/A tests on every new metric before trusting it, and on every new experimentation platform before trusting *it*. A/A failures reveal logging bugs, bot traffic, residual treatment leakage from prior tests, and instrumented-but-broken metrics. Most "we shipped a bad thing" post-mortems trace back to a missing A/A.

### 6.2 Sample Ratio Mismatch (SRM)

If you targeted a 50/50 split but observe 49.2/50.8, is it noise or a bug?

$$
\chi^2 = \sum_{\text{arms}} \frac{(O - E)^2}{E}.
$$

A $p < 0.001$ on the SRM test is a *red flag, do not ship*. Common causes:

| Cause | Where to look |
|---|---|
| Ramp-up plan changed mid-test | Assignment service logs |
| Differential redirects / errors | Edge / CDN / app crash analytics |
| Variant assignment bug | A/B platform configuration |
| Bot filtering applied to one arm | Pre-processing pipeline |
| Crashes on one variant | Telemetry per arm |
| Cookie expiry / login behavior different | Identity service |

Never read results from a test with SRM. Fix the bug, restart.

### 6.3 The pre-result checklist

Before looking at the primary metric:

1. SRM clean on overall and on key segments.
2. Guardrails clean (latency, error rates).
3. Pre-period A/A on this metric was clean.
4. Experiment ran the planned duration (no peeking, see §8.1).
5. No major external event (outage, holiday, marketing push) overlapped the experiment.
6. Triggering rate matches expectations.
7. Effect size and direction are *plausible* — implausible huge effects often = bug.

---

## 7. Interference, SUTVA, and two-sided markets

SUTVA (Stable Unit Treatment Value Assumption) demands that one unit's treatment doesn't affect another's outcome. It gets violated whenever:

- **Two-sided market.** Treatment customers and control customers compete for the same supply of restaurants / drivers / inventory. A "boost" to treatment cannibalizes from control.
- **Social network.** Treatment users' behavior affects friends in control (referrals, content sharing, shared playlists).
- **Shared resources.** Cache hits, recommendation queues, rate limits, batch jobs.
- **Time-locked supply.** A driver who picks up a treatment order isn't available for a control order in the same minute.

### 7.1 Designs that mitigate interference

| Design | Mechanism | Cost |
|---|---|---|
| **Cluster randomization** (neighborhoods, friend cliques) | Treat whole clusters identically | Fewer effective units → more variance |
| **Geo / market randomization** | Whole DMA / city goes treatment or control | Very few units, geographies differ |
| **Switchback** (time slot) | Same market alternates treatment / control by hour or day | Carryover, day-of-week effects |
| **Ego-network randomization** | Randomize seed, but include 1-hop neighbors in treated cluster | Hard to implement correctly |
| **Counterfactual matched markets** | Use a synthetic control on a separate market as the comparator | Requires SCM modeling — see causal_inference.md |

### 7.2 The two-sided-market case — Doordash flavor

For Doordash's market-level changes (new fee structure, expanded radius), the supply (restaurants, dashers) responds. Two valid designs:

1. **Switchback by market × time slot.** Run treatment for 2-hour windows alternating with control across markets. Effective when carryover decays within the slot duration. Risks: dinner-rush bias, dashers learning the schedule.
2. **Geo experiments (DMA-level).** Treat e.g. 30 cities, hold 30 as control, match on pre-period demand. Use synthetic-control style estimators (see [causal_inference.md](../../../repos/ml-interview-prep/algorithms/notes/causal_inference.md) §Synthetic DiD). Few units → low power → MDE measured in single-digit percentage points typically.

**Sanity check before declaring a two-sided design.**
1. *How big is the spillover?* If small (e.g. 1% of treated drivers' deliveries displace control orders), unit-level randomization with a small interference adjustment can still be valid.
2. *Is your spillover model correct?* Misspecified spillover models bias the answer worse than no model.
3. *Could you measure spillover first?* Run a small switchback or geo to *estimate* the interference factor before committing to the design.

---

## 8. Reading results — pitfalls and their fixes

### 8.1 Peeking and sequential testing

Looking at the test early and stopping when it's "significant" inflates the type-I error far past $\alpha$. The fixes:

- **Don't peek.** Pre-commit to a duration; only read at the end.
- **If you need to peek**, use **sequential testing** methods: mSPRT (mixture sequential probability ratio test), always-valid p-values (Howard et al.), group sequential boundaries (O'Brien-Fleming, Pocock). These preserve type-I error across multiple peeks at the cost of either some statistical efficiency or stricter early thresholds.
- **For early stopping for *futility*** (no point continuing), use conditional power or predictive probability — both well-defined Bayesian / frequentist approaches.

### 8.2 Multiple hypothesis testing — FWER vs FDR

If you test $K$ metrics, the chance at least one is significant at $\alpha = 0.05$ by luck is $1 - 0.95^K$ — ~22% at $K=5$, ~40% at $K=10$, **~99% at $K=100$**. At platform scale this matters a lot. The senior nuance: there are **two fundamentally different error-rate concepts**, controlled by different families of correction. Naming both and choosing between them deliberately is a staff signal.

#### Family-Wise Error Rate (FWER)

**Definition:** $\Pr(\text{at least one false positive across the entire family of } K \text{ tests})$.

**Corrections targeting FWER:**
- **Bonferroni** ($\alpha / K$) — the simple baseline, conservative; gets very strict as $K$ grows.
- **Holm-Bonferroni** — sequential / step-down: sort p-values ascending and compare against $\alpha/K, \alpha/(K-1), \alpha/(K-2), \ldots$ until one fails. Strictly more powerful than Bonferroni while still controlling FWER.
- **Hochberg / Hommel** — step-up variants; more powerful again but require independence or positive dependence.

**Use FWER control when *one* false positive has catastrophic cost:**
- Clinical drug approval (FDA requires strict FWER)
- Security / fraud feature rollouts where a false positive exposes a vulnerability
- Ad-quality launches where shipping a low-quality ad damages brand long-term
- Cross-team launch decisions where the cost of misshipping is unrecoverable

| Pro | Con |
|---|---|
| Strict guarantee on family-wise error | Power collapses as $K$ grows; at $K=20$ Bonferroni runs each test at $\alpha = 0.0025$ — you miss almost all real effects |

#### False Discovery Rate (FDR)

**Definition:** $\mathbb{E}\!\left[\dfrac{\text{false positives}}{\text{total discoveries called significant}}\right]$.

If you reject 100 hypotheses and the FDR is 5%, you *expect* ~5 of those 100 to be false positives. Critically, FDR doesn't bound the *number* of false positives — it bounds their *proportion among discoveries*.

**Corrections targeting FDR:**
- **Benjamini-Hochberg (BH)** — sort p-values ascending; reject the largest $k$ such that $p_{(k)} \le (k/K) \cdot \alpha$. The modern industry default for tech.
- **Benjamini-Yekutieli (BY)** — variant valid under arbitrary correlation structure; more conservative.
- **Storey's q-value** — adaptive: estimates the proportion of true nulls $\hat\pi_0$ and corrects accordingly. More power when most nulls are actually false.

**Use FDR control when discoveries are exploratory and a small fraction of false positives is acceptable:**
- Feature ramps tracking many secondary metrics
- A/B platforms running thousands of simultaneous experiments (LinkedIn ~41K concurrent — see §15.6)
- Exploratory subgroup analyses, segment cuts
- Scientific-discovery work (gene expression, fMRI, ML hyperparameter search)
- Metric ranking on dashboards

| Pro | Con |
|---|---|
| Retains power as $K$ grows; scales proportionally with the number of tests | Allows multiple false positives in large families; not appropriate when one false positive is unacceptable |

#### Side-by-side

| Aspect | FWER | FDR |
|---|---|---|
| Controls | $\Pr(\geq 1 \text{ FP})$ | $\mathbb{E}[\text{FP} / \text{discoveries}]$ |
| Power at large $K$ | Collapses | Retains |
| When to use | Each false positive is catastrophic | False positives are tolerable in aggregate |
| Default correction | **Holm-Bonferroni** | **Benjamini-Hochberg** |
| Industry tier | Launch-decision tier, regulated work | Platform-default for exploratory tier |

#### The hybrid that production platforms actually run

Mature experimentation platforms (Microsoft, LinkedIn, Netflix) tier metrics by the *cost of a false positive* and apply different control to each tier:

| Tier | Cost of FP | $\alpha$ level | Correction within tier |
|---|---|---|---|
| Primary OEC | High | 0.05 | None (single test) or FWER if multiple OECs exist |
| **Guardrails** (latency, error rate, churn) | **Very high** | **0.005** | **FWER (Holm-Bonferroni)** |
| Secondary drivers | Moderate | 0.01 | BH (FDR) within tier |
| Exploratory / segment cuts | Low | 0.05 | BH (FDR) within tier |

This is the framing the Kohavi-Tang-Xu book recommends and what LinkedIn / Netflix actually run. **Document the tier protocol before the test starts** — choosing post-hoc invalidates the inference.

### 8.3 Novelty and primacy effects

Early-period results are unreliable when:
- **Novelty:** users try the new thing because it's new (initial lift fades).
- **Primacy:** users underuse the new thing because they don't know it yet (initial drop recovers).

Diagnoses:
- Plot the treatment effect over time. Is it monotone or fading?
- Cohort by experiment-entry date. New cohorts after week 2 should show "steady-state" behavior.
- Segment by new vs existing users — new users have no prior to anchor on, so their behavior is the closest to "long-run."

Mitigations:
- Run longer (4–8 weeks).
- **Holdback experiment:** after launching, keep 1–5% of users on control indefinitely. Measure long-term effect on that holdback. Cross-reference [time_series_forecasting.md](../../../repos/ml-interview-prep/algorithms/notes/time_series_forecasting.md) §Walk-forward retraining cadence — same discipline applies.
- **Reverse experiment:** post-launch, switch a fresh sample of users *back* to control. Did they degrade? You've measured the steady-state effect.

### 8.4 Simpson's paradox

Aggregated treatment effect disagrees with every subgroup's effect. Caused by differing assignment rates or differing baseline conversion rates across segments. The fix is to **stratify the analysis** and use a weighted estimator, or to ensure stratified randomization in the first place. Whenever the aggregate looks suspiciously different from segments, suspect Simpson.

### 8.5 The launch decision quadrant

A two-by-two of *statistical* significance vs *practical* significance:

| | Practically meaningful | Not practically meaningful |
|---|---|---|
| **Stat sig** | **Launch.** | Don't launch — effect too small to matter; revisit OEC. |
| **Not stat sig** | Inconclusive — either re-run with more power *or* launch if CI overlaps the practical threshold (a "neutral with potential" decision). | **Don't launch.** Effect is plausibly zero or trivial. |

**Practical-but-not-statistical** with CI extending past the practical threshold is the most-debated quadrant. The senior answer is *"the experiment doesn't have power to conclude; either re-run powered for the smaller effect, or — if the cost of relaunching is high and the downside is small — launch as a calculated bet with monitoring."*

---

## 9. When you can't randomize — quasi-experiments

When A/B testing is impossible or impractical, the rigorous fallback is quasi-experimental causal inference. Brief map; deep treatment lives in [causal_inference.md](../../../repos/ml-interview-prep/algorithms/notes/causal_inference.md).

| Method | When to use | Identifying assumption |
|---|---|---|
| **Difference-in-Differences (DiD)** | Treatment rolled out to some markets/cohorts at a known time | Parallel trends absent treatment |
| **Synthetic Control / Synthetic DiD** | Treatment hits *one* (or few) units, many control units | Pre-period donor pool reproduces target's path |
| **Regression Discontinuity (RDD)** | Treatment determined by crossing a known threshold (FICO cutoff, $X minimum spend) | Continuity of potential outcomes at the cutoff |
| **Instrumental Variables (IV) / 2SLS** | Treatment endogenous, but an *instrument* affects treatment but not outcome directly | Relevance + exclusion + monotonicity |
| **Propensity Score Matching / IPW** | Observable confounders only; rich covariates | No unmeasured confounding + overlap |
| **DML / Doubly Robust** | Same as PSM but with ML for nuisance functions | Same + correct cross-fitting |
| **Interrupted Time Series** | Treatment at a known time, single unit, long pre-period | Counterfactual = extrapolated pre-period trend |
| **Interleaved experiments** | Comparing ranker A vs B by mixing results within a single response | Both rankers must score the same items |

**Staff reflex:** every quasi-experimental method substitutes a *design assumption* for randomization. Name the assumption out loud, then state what could violate it and how you'd check. Naming "parallel trends" or "monotonicity" earns staff-level points juniors miss.

---

## 10. Multi-armed bandits — when MAB beats A/B

### 10.1 The exploration-exploitation tradeoff

MAB exists because every adaptive allocation faces a fundamental tension:

- **Exploit** — show users the arm that's *currently best* on the data so far. Maximizes short-term reward.
- **Explore** — show users an arm that *might be better* but is less certain. Maximizes long-term learning.

Pure exploitation is greedy and gets stuck on a locally-good arm — you never discover the genuine winner if it happens to start with bad luck. Pure exploration is wasteful and never collects the cumulative reward you're paid to maximize. **The MAB literature is essentially the study of how to balance these two.**

Three classical balancing strategies, ordered by how "intelligent" the exploration is:

| Strategy | How it balances | Intuition |
|---|---|---|
| **ε-greedy** | With probability $\epsilon$ pick a random arm (explore); with $1-\epsilon$ pick the best so far (exploit) | Simple but explores blindly — wastes pulls on arms already known to be bad. The $\epsilon_t \propto t^{-1/3}$ schedule helps |
| **UCB (Upper Confidence Bound)** | Pick the arm with the *highest optimistic estimate* — its mean plus an uncertainty bonus that shrinks with sample size | "Optimism under uncertainty": well-explored arms have tight bounds, under-explored arms have wide ones — automatically forces exploration where uncertainty is high |
| **Thompson Sampling** | Sample once from each arm's posterior, pick the arm with the highest sampled value | Bayesian explore/exploit; uncertainty in the posterior naturally drives exploration. **Empirically the best in most production settings** |

(The formal regret rates for each are in §10.4 below.)

### 10.2 Real-world MAB use cases

The pattern shared by every successful production MAB deployment: **the opportunity cost of pulling a sub-optimal arm is direct revenue**, and the decision is repeated continuously rather than once per quarter.

| Application | Why MAB beats A/B in this setting |
|---|---|
| **News headline selection** (Yahoo, Reddit, Microsoft) | Many candidate titles per story; each lost impression is real revenue; stories have short shelf-lives so you can't run a full multi-week A/B |
| **Ad creative selection** (Meta, Google Ads, TikTok) | Many creatives × many audiences; the auction-side opportunity cost of showing a losing creative is direct ad revenue lost |
| **Email subject line testing** (Mailchimp, Substack, Klaviyo) | Many candidates per campaign, one-shot decision per send. Adaptive allocation within the send window picks winners before the whole list is exhausted |
| **Search ranking promotions** (Google, Bing) | Adaptive promotion of candidate items / refinements in real-user traffic, learning which work without committing to a full A/B |
| **Personalized row ordering** (Netflix homepage rows, Spotify discovery shelves) | Each user gets a different row order; bandit per user learns from clicks within session |
| **Pricing / promo exploration** (regulated, use with care) | Discover which discount level maximizes conversion × margin without committing to a single discount for everyone |
| **Adaptive clinical trials** | Patients prefer adaptive allocation to the apparently-best treatment; FDA increasingly allows adaptive designs |
| **Robotic / RL training in simulation** | The bandit is the inner loop of every reinforcement-learning system; choosing which actions to explore at each step |

### 10.3 When MAB beats A/B vs when A/B beats MAB

A/B testing **commits** to an even split until the end. MAB **adapts**, shifting traffic toward winners. Two main MAB variants:

- **Stochastic bandits** (Thompson Sampling, UCB): treat each arm as an unknown reward distribution; allocate to maximize cumulative reward.
- **Contextual bandits**: pick the arm conditional on user / context features; closer to personalization. The framework behind most production deployments above.

When MAB wins:
- **Opportunity cost is high** (every losing-arm impression costs money — homepage banner, headline test, ad creative).
- **Short-lived treatments** (news headlines, daily promotions).
- **Many arms** (8+ creatives) where pure A/B/n is expensive.

When A/B wins:
- **You need a clean causal estimate** for each arm (MAB's adaptive allocation breaks naive inference).
- **Decisions involve cross-team commitments** that need a single, defensible launch metric.
- **Effects compound over weeks** (MAB's short-horizon focus misses long-term effects).
- **Auditability matters** (regulators, partners).

### 10.4 Regret bounds — the vocabulary an interviewer expects

*Regret* is the expected reward gap between your policy and always pulling the best arm. The asymptotic regret rate is MAB's report card, and staff candidates know the rates.

| Algorithm | Idea | Regret ($T$ horizon, $K$ arms) |
|---|---|---|
| **Uniform exploration** | Pull each arm equally for $T_0$ rounds, then exploit empirical best | $O(K^{1/3} T^{2/3})$ — exploration is wasteful |
| **ε-greedy** ($\epsilon_t \propto t^{-1/3}$) | Pull random arm with prob $\epsilon$, best arm otherwise | $O(K^{1/3} T^{2/3})$ — same rate as uniform |
| **Successive Elimination** (Hoeffding) | Maintain an active arm set; drop arms whose UCB lies below another's LCB | $O(\sqrt{KT \log T})$ — the modern rate |
| **UCB (Upper Confidence Bound)** | Pull $\arg\max_a [\hat\mu_a + \sqrt{2 \log T / N_a(t)}]$ | $O(\sqrt{KT \log T})$ |
| **Thompson Sampling** | Sample from each arm's posterior; pull the arm with the sampled max | $O(\sqrt{KT \log T})$ — often best in practice |
| **KL-UCB / KL-Thompson** | Use KL-based confidence widths instead of Hoeffding | $O(\log T / \Delta)$ instance-dependent — the asymptotic floor |

**Why the $T^{2/3}$ vs $\sqrt{T}$ split matters.** The first two allocate exploration *uniformly* over time and pay a $T^{2/3}$ penalty; the latter three allocate *adaptively* (explore only when confidence is low) and hit the optimal $\sqrt{T}$. **Production MAB systems use Thompson Sampling or UCB**; the $T^{2/3}$ family is pedagogical.

**Post-experiment analysis under MAB**: standard statistical tests do not apply because the allocation is not iid. Use **importance-weighted estimators**, **off-policy evaluation**, or **sequential testing methods** designed for adaptive allocation. State this if you propose MAB.

---

## 11. Multivariate / factorial designs

When testing multiple changes at once, a $2 \times 2$ (or $2^k$) factorial design measures:

- **Main effects** of each factor (X alone, Y alone).
- **Interaction effects** (does X depend on Y?).

Per-cell sample size grows with the number of factors. Use a factorial when interactions are *expected and important*; otherwise prefer independent single-factor tests, which have higher power per factor.

**Example.** *New ranker (X) + new layout (Y)* on Doordash:

| Group | Ranker | Layout |
|---|---|---|
| A (control) | Old | Old |
| B | New | Old |
| C | Old | New |
| D | New | New |

The interaction term tests whether new ranker + new layout perform differently than the sum of their individual effects. Usually small; if you can't power for it, run two separate single-factor tests.

---

## 12. Decision rubric — the senior summary

| Situation | Reach for |
|---|---|
| Standard user-visible change, enough traffic | User-randomized A/B with CUPED |
| Ranker / personalization where only a fraction trigger | Triggered analysis, possibly counterfactual triggering |
| Two-sided market, supply/demand spillover | Switchback or geo experiment + synthetic-DiD analysis |
| Social / network product | Cluster randomization on network communities |
| Treatment can't be randomized (regulatory rollout, etc.) | DiD or RDD if there's a cutoff; synthetic control if one unit treated |
| Many short-lived creative variants | Multi-armed bandit (Thompson) with off-policy eval |
| Slow / dilute primary metric | Compose an OEC from sensitive drivers; validate with prior experiments |
| Hard to measure long-term harm | Reverse experiment or permanent holdback |
| Effect smaller than expected, can't power | Variance reduction (CUPED + triggering) before increasing sample size |
| Multiple metrics, want all-or-nothing | Stratify metrics by tier, BH correction within tier |

---

## 13. End-to-end worked example — Doordash extends free delivery to non-DashPass customers

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
- **Triggering:** the change only affects checkout for orders ≥ $15; analyze on **triggered** customers (those who hit a qualifying basket).
- **Guardrails** monitored daily with sequential bounds — auto-stop if DashPass renewals drop by > 2% with $p < 0.01$.

### Step 4 — Interference

- This is a one-sided demand change; supply-side spillover is small but non-zero (more demand pulls dashers).
- Run in a few medium-sized markets first; cross-validate with a switchback design before national rollout.
- Cross-reference with [causal_inference.md](../../../repos/ml-interview-prep/algorithms/notes/causal_inference.md) for synthetic-DiD on the market-level rollout.

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

## 14. Common interview traps & staff reflexes

- **Stating the decision the experiment informs** — most candidates skip this. State it explicitly.
- **MDE without anchoring** — "we'd detect 10%" with no justification is a tell.
- **Forgetting variance reduction** — modern A/B is CUPED + triggering by default.
- **Treating SUTVA as automatic** — for two-sided markets, social, shared resources, it's violated.
- **Reading results without sanity checks** — SRM, A/A, guardrails, triggering rate.
- **Confusing statistical and practical significance** — they're not the same; state both thresholds.
- **Reaching for MAB when you actually need clean inference**.
- **Ignoring novelty / primacy** — at least mention them; if your test is short, you can't read steady-state.
- **Multiple-testing without a plan** — tier metrics and choose a correction up front.
- **No long-term plan** — holdback or reverse experiment for anything user-visible and reversible.
- **Saying "A/B test it"** when the right answer is "we can't randomize — quasi-experiment" — see §9.

---

## 15. Frontier techniques — the Netflix-style staff angle

Most staff-level experimentation teams at consumer-tech companies have internalized a small set of advanced techniques developed and published by industry research groups over the past decade. Naming these — and knowing when each beats the textbook A/B — earns an extra notch of staff signal. The six below are drawn from Netflix's published work on their XP (eXperimentation) platform; see §15.7 for references.

### 15.1 Anytime-valid sequential testing — the deep dive

The peeking problem (§8.1) has a modern, deployment-ready fix. Below is the **what / why / how / cost / when-not-to-use** treatment.

#### 15.1.1 The peeking trap, quantified

A naive interim check inflates type-I error far past $\alpha$. The widely-cited Armitage-McPherson-Rowe (1969) calculation:

| Number of equally-spaced peeks at $\alpha = 0.05$ | Actual Type-I error |
|---|---|
| 1 (the fixed-horizon test) | 0.050 |
| 2 | 0.083 |
| 5 | 0.142 |
| 10 | 0.193 |
| 100 | ~0.40 |
| ∞ (continuous monitoring) | 1.0 (will eventually cross with prob 1) |

So a team that "peeks every Friday" for 10 weeks is running tests at an *actual* level around 0.20 — four times the nominal. Anytime-valid inference closes this gap.

#### 15.1.2 Three eras of sequential testing

| Era | Method | Stopping flexibility | When you'd still use it |
|---|---|---|---|
| **1945 — Wald's SPRT** | Likelihood ratio against a *point* alternative $\theta_1$ | Continuous | When you genuinely know $\theta_1$ (almost never in product DS) |
| **1977–79 — Group-Sequential** (Pocock; O'Brien-Fleming; Lan-DeMets α-spending) | Adjusted critical values at a *finite* number of pre-planned interim looks | Looks must be pre-specified | Clinical trials, where peeks happen at planned DSMB meetings — common in biostats; rare in tech |
| **2015–22 — Anytime-Valid** (mSPRT / confidence sequences / e-values) | Likelihood-ratio mixture or supermartingale; valid at every $n$ | **Truly continuous, no pre-spec needed** | Modern tech A/B platforms (Optimizely, Adobe, Netflix, etc.) |

The Group-Sequential family is rigorous but operationally clunky — the analyst must commit, at the start, to the *exact* schedule of interim looks. Anytime-valid removes that constraint.

#### 15.1.3 The mathematical core — three equivalent framings

**(a) Mixture Sequential Probability Ratio Test (mSPRT, Robbins 1970).** For Gaussian outcomes with known variance $\sigma^2$ and a $N(0, \tau^2)$ mixing distribution on the alternative $\theta$:

$$
\Lambda_n \;=\; \sqrt{\frac{\sigma^2}{\sigma^2 + n \tau^2}} \cdot \exp\!\left( \frac{n^2 \bar X_n^2 \, \tau^2}{2\sigma^2 (\sigma^2 + n \tau^2)} \right)
$$

Reject the null at any $n$ if $\Lambda_n > 1/\alpha$. By Doob's optional-stopping theorem applied to the likelihood-ratio martingale, this controls type-I error **uniformly across all stopping times**, including data-dependent ones.

**(b) Confidence Sequence (Howard-Ramdas et al. 2021).** A sequence of intervals $(L_t, U_t)_{t \geq 1}$ such that

$$
\Pr\big(\theta \in (L_t, U_t) \;\;\text{for all } t \geq 1 \big) \;\geq\; 1 - \alpha
$$

— *simultaneous* coverage across the entire monitoring window. Dual to mSPRT: invert the test to get the interval. Howard et al. give nonparametric, time-uniform Chernoff-type bounds that work for sub-Gaussian, bounded, and sub-exponential outcomes without distributional assumptions on the data-generating process.

**(c) E-value / Test Martingale (Shafer-Vovk-Wang 2021-24; Grünwald-de Heide-Koolen).** The modern unification. An e-process $E_n$ is a nonnegative process with $\mathbb{E}_{H_0}[E_n] \leq 1$ for all $n$. The test "reject if $\sup_n E_n \geq 1/\alpha$" is anytime-valid by Ville's inequality. Both mSPRT and confidence sequences are special cases of e-processes — and e-values **combine across experiments by simple multiplication**, which enables clean meta-analysis and FWER control across portfolios. This is the framing modern industry research is converging on.

**(d) Design-based confidence sequences (Lindon, Malek, Bibaut et al. — Netflix 2022).** Construct the e-process under the *randomization distribution* induced by random assignment, rather than a model of the outcome. **Finite-sample valid with no distributional assumption.** Generalizes from i.i.d. samples to MAB, panel data, and time-series. This is what Netflix runs in production.

#### 15.1.4 The cost of validity, quantified

A fixed-horizon 95% CI for a mean has width $\sim 1.96 \sigma / \sqrt n$. The anytime-valid analog has width

$$
\sim \sigma \sqrt{2 \log\log n \, / \, n} \cdot \big(\text{constant of order 1}\big)
$$

— the law of the iterated logarithm rate, with a $\sqrt{\log\log n}$ inflation. Numerically, what this costs:

| $n$ | $\log\log n$ | Width inflation vs fixed-horizon | Sample-size penalty for same width |
|---|---|---|---|
| 100 | 1.53 | ~1.27× | ~1.6× |
| 1,000 | 1.93 | ~1.40× | ~2.0× |
| 10,000 | 2.22 | ~1.50× | ~2.3× |
| 1,000,000 | 2.63 | ~1.64× | ~2.7× |

So a "**~2× sample-size penalty**" is the right interview number — independent of the specific algorithm. Compare with peeking: at 10 looks, peeking inflates Type-I from 0.05 to 0.19; the *real* cost of naive peeking (the inflation in false-positive launches) is far worse than the 2× cost of doing it correctly.

**The Optimizely empirical result** (Johari, Koomen, Pekelis, Walsh 2017/2022, deployed across hundreds of thousands of experiments): the *median* always-valid experiment stops at roughly **30% of the fixed-horizon sample size**, because most experiments have effects large enough or small enough to detect well before the planned $n$. The 2× per-experiment penalty is way more than recovered by the portfolio-level early stopping.

#### 15.1.5 Decision procedures — what "stop early" actually means

Three distinct early-stop conditions:

| Condition | Statistical rule | Business action |
|---|---|---|
| **Efficacy stop** | Lower bound of CI exceeds zero (or the launch threshold) | **Launch** |
| **Futility stop** | Upper bound of CI below the practical MDE | **Don't launch — effect too small to matter** |
| **Safety stop / harm stop** | CI excludes zero in the wrong direction, OR a guardrail metric's CI breaches the no-go threshold | **Kill the experiment, revert** |

A well-designed always-valid system **monitors all three simultaneously** and stops on whichever fires first. The Truncated mSPRT line of work (e.g. Lin et al. 2025) specifically embeds practical-significance thresholds into the test so that "stop for futility" is a first-class decision rather than an afterthought.

**Anti-pattern:** running anytime-valid analysis but only checking the efficacy condition. You lose the main industry win — early kill of underperforming experiments — and revert to "ran the full horizon anyway."

#### 15.1.6 Industry deployments

| Company | Method | Notable result |
|---|---|---|
| **Optimizely** | mSPRT with Gaussian mixing (Johari et al. 2017/22) | Deployed across hundreds of thousands of experiments; median stop at ~30% of fixed-horizon $n$ |
| **Netflix** | Design-based confidence sequences (Lindon et al. 2022) | Sign-up-page experiment with 30k potential customers, stoppable on day 1 before 100 obs |
| **Adobe** | Asymptotic confidence sequences (Maharaj et al. 2023) | Thousands of Adobe Experience Platform experiments; integrates with sample-size calcs and lift metrics |
| **LinkedIn / Meta / Microsoft** | Hybrid: GST-style boundaries for guarded experiments + anytime-valid for routine ones | Most large-scale platforms have moved to some form of anytime-valid for the bulk of experiments |

#### 15.1.7 When *not* to use anytime-valid

| Situation | Why fixed-horizon wins |
|---|---|
| **Tiny experiments** (< a few hundred units total) | The $\log\log n$ penalty bites hard at small $n$; you'd pay 2.5× for very little flexibility benefit |
| **Cross-team launch decision frozen in advance** | A pre-committed launch rubric (§13) is itself a fixed-horizon design — adding sequential machinery confuses governance |
| **Regulator / auditor scrutiny** | Some regulators expect a fixed-horizon analysis; anytime-valid is harder to defend in a compliance review |
| **Effects you genuinely can't detect early** | If the metric is so noisy or the effect so dilute that you'll only see signal at the full horizon, anytime-valid doesn't help and you pay the 2× cost for nothing |
| **You don't have engineering support for continuous monitoring** | If "peeking" means a person looking at a dashboard once a week, group-sequential is operationally simpler and gives most of the benefit |

#### 15.1.8 Staff phrasing

> *"For experiments where opportunity cost is high and effects might be large, I'd run an anytime-valid sequential test — mSPRT for parametric outcomes or a design-based confidence sequence for finite-sample validity à la Netflix's published approach. The CI width inflates by $\sqrt{\log\log n}$ — about a 2× sample-size penalty per experiment — but the median experiment in the Optimizely deployment stops at ~30% of the fixed-horizon n, so portfolio velocity wins. I'd monitor all three of efficacy, futility, and guardrail-safety conditions simultaneously, with pre-committed launch thresholds. The wrong answer is 'run anytime-valid but only check efficacy' — you give up the main industrial benefit."*

#### 15.1.9 Further reading

- [Always Valid Inference: Continuous Monitoring of A/B Tests (Johari, Koomen, Pekelis, Walsh — Optimizely / Stanford, 2015→2022 OR)](https://arxiv.org/abs/1512.04922) — the foundational industrial paper; mSPRT formulation, Optimizely deployment.
- [Time-uniform, nonparametric, nonasymptotic confidence sequences (Howard, Ramdas, McAuliffe, Sekhon, Annals of Statistics 2021)](https://arxiv.org/abs/1810.08240) — the modern theoretical foundation.
- [Design-Based Confidence Sequences (Lindon, Malek, Bibaut et al. — Netflix 2022)](https://arxiv.org/abs/2210.08639) — randomization-based finite-sample validity (the §15.1.3(d) construction).
- [Anytime-Valid Confidence Sequences in an Enterprise A/B Testing Platform (Maharaj et al. — Adobe 2023)](https://arxiv.org/abs/2302.10108) — Adobe deployment with sample-size and lift handling.
- [Sequential A/B Testing Keeps the World Streaming Netflix (Part 1: Continuous Data)](https://netflixtechblog.com/sequential-a-b-testing-keeps-the-world-streaming-netflix-part-1-continuous-data-cba6c7ed49df) — Netflix Tech Blog operational walkthrough.
- [E-values: Calibration, Combination and Applications (Vovk-Wang, Annals 2021)](https://arxiv.org/abs/1912.06116) — the e-value unifying framework.
- [Truncated mSPRT for Practical Significance (Lin et al. 2025)](https://arxiv.org/abs/2509.07892) — embedding the practical-significance threshold directly in the test.

### 15.2 Regression-adjusted sequential testing — CUPED meets anytime-valid

The bigger insight: variance reduction (§5.4 CUPED) and anytime-valid sequential testing **compose**. Netflix's "Anytime-Valid Linear Models" line of work shows that the standard regression-adjusted estimator (subtract $\theta(X - \bar X)$ from the outcome) plugs into a confidence-sequence framework without breaking validity. You get the $\rho^2$ variance reduction *and* the peeking-allowed flexibility in one estimator.

Combined effect: a CUPED reduction of 50% plus a 1.5× anytime-valid penalty is still a **net ~33% sample-size reduction** over fixed-horizon naive analysis — with continuous monitoring.

### 15.3 Interleaving — the deep dive on ranker experiments

For ranker / recommender experiments, **interleaving** is the dominant industry technique. It compares two rankers by mixing their outputs into a *single* ranked list shown to a single user, then attributes credit per click to whichever ranker contributed the item. Each user is their own paired control — variance reduction is enormous because **between-user variance, which usually dominates, is removed**.

The reported speedups vs A/B testing are dramatic: **50× at Airbnb** (Bi et al. 2025, confirmed with 29 paired A/B + interleaving experiments), **60× at Amazon** (Bi et al. 2022), and Netflix has reported similar two-stage architectures for years.

#### 15.3.1 The three classical interleaving algorithms

| Algorithm | Construction | Credit attribution | Bias note |
|---|---|---|---|
| **Balanced Interleaving (BI)** — Joachims 2003 | Alternate items from rankers A and B so the top-$k$ list of $I$ always contains the top-$k_A$ from A and top-$k_B$ from B with $\|k_A - k_B\| \leq 1$ | A click is credited to *both* rankers if the item appears (above a threshold) in both lists. Winner = more clicks | **Biased on shift-by-one permutations:** if A = $[a,b,c,d]$ and B = $[b,c,d,a]$, BI's mix can give one ranker artificially more credit positions |
| **Team Draft (TD)** — Radlinski-Kurup-Joachims 2008 | Toss a coin per "round." The winning team picks its top remaining item, then the other team picks its top. Each item in the merged list is tagged with its team | Click → +1 for that item's team. Winner = team with more total clicks | **Mild bias on shift-by-one** but minimal in practice (Hofmann 2013 found it "negligible") |
| **Probabilistic Interleaving (PI)** — Hofmann et al. 2011 | Softmax both rankers' lists into probability distributions; sample items into $I$ stochastically | A click contributes credit summed over **all draft sequences** that could have produced this $I$ — unbiased but expensive to compute | **Unbiased** in theory, but visibly degrades the user experience because rankings are randomized; high system complexity |

**The 2 things to memorize:** (a) **Team Draft** is the dominant production choice — simple, low overhead, near-unbiased; (b) **Probabilistic Interleaving** is the unbiased gold standard but rarely shipped because it sacrifices UX.

#### 15.3.2 The statistical test — sign test on user preferences

The within-user paired structure naturally suggests a sign test:

For each user $i$ in the interleaving cohort, let $\tau_i = (\text{clicks team A}) - (\text{clicks team B})$. Then:

$$
\hat\tau_{\text{pref}} \;=\; \frac{1}{N} \!\left[\sum_i \mathbf{1}\{\tau_i > 0\} - \sum_i \mathbf{1}\{\tau_i < 0\}\right]
$$

The p-value is from a **proportion test** (equivalently, a binomial sign test) on the counts of A-preferring vs B-preferring users. Under the null of no preference difference, the expected proportion of A-preferring users is 0.5.

#### 15.3.3 Bias / fidelity gotchas (staff-level depth)

| Failure mode | What it looks like | Mitigation |
|---|---|---|
| **Shift-by-one** | A and B differ only by a small reordering; classical methods can spuriously prefer one | Either treat ties within an "equal zone" of $\alpha > 0$ positions as no-preference, or use Probabilistic Interleaving |
| **Set-level optimization** | Treatment ranker optimizes *diversity*, *fairness*, or another set-level objective; interleaving mixes the lists and breaks the optimization | Don't interleave — use A/B. (Airbnb specifically calls this out as a case where interleaving misled them.) |
| **Position bias** | If construction is asymmetric (e.g., team A always gets the top slot), clicks skew | Coin-toss the first slot per user / session; *empirically validate impression balance* every experiment |
| **Shared real-time features** | If both rankers consume signals from the *same* user (e.g., updated preferences from prior session), the stronger ranker freerides on signals "earned" by the weaker | Less of a problem for interleaving (both rankers see identical context within a pair) but a real failure mode for counterfactual evaluation — see §15.3.5 |
| **Conversion sparsity** | The reward signal is bookings/purchases, not clicks → very sparse → low statistical power | Use a hybrid metric (clicks + downstream); fall back to A/B if the conversion event is too rare even after the speedup |

**The Airbnb empirical practice:** every experiment runs an unbiasness sanity check, e.g., *"Listings shown: 0.00% Δ (p=0.91); shown first: −0.01% Δ (p=0.85)"* — confirming impression and position symmetry between teams. **Treat this as the SRM of interleaving** — if it fails, the experiment is invalid.

#### 15.3.4 Modern industry variations

- **Competitive Pair Team Draft (Airbnb 2025).** A single coin flip per search decides which ranker draws first (rather than a coin per round). Reduces noise in the team-draft mechanic and makes impression balance trivially auditable. Reports ~50× speedup, 82% directional agreement with paired A/B tests, $\rho = 0.6$ correlation in effect size across 29 experiments.
- **BI + Inverse Propensity Weighting (Amazon, Bi et al. 2022).** Reweights credit by the position-occupancy probability per ranker to debias BI. ~60× speedup; less extensible than CP-TD.
- **Counterfactual evaluation (Airbnb hybrid).** Don't interleave — show *one* randomized ranker per search and *compute* the counterfactual offline using both lists. **No UX disruption** since the user sees a normal page. Pairs with TD on different traffic to validate. ~15–100× speedup depending on the metric (the $\tau_g$ direct-decomposition metric hits ~100×).
- **Multileaving (>2 rankers).** Theory generalizes draft mechanics to $K$ teams (Schuth et al. 2014, Brost-Cox-Seldin-Stone 2016). Practical adoption is rare because per-team statistical power degrades; most teams just pair-compare a handful of candidates in parallel.

#### 15.3.5 When interleaving is the wrong tool

| Situation | Why interleaving fails | Use instead |
|---|---|---|
| The candidate rankers score *different items* (e.g., new content surface that the control doesn't index) | The merged list can't be constructed | A/B at the user level |
| You need a **long-term outcome** (retention, LTV) | Interleaving measures within-session preference only | A/B (almost always two-stage: interleaving prune → A/B confirm) |
| The change is to **set-level structure** (a layout change, a diversity constraint, a fairness re-ranking) | Interleaving violates the set property | A/B at the user level |
| The metric is **highly sparse** (conversion only, $< 0.5\%$ rate) | Speedup not enough to recover statistical power | A/B with CUPED, or hybrid click + conversion proxy |
| You're under **regulatory or audit scrutiny** | Interleaving has no analog of "this group saw treatment, that group saw control" → harder to explain | A/B for the on-record decision; interleaving as upstream R&D |

#### 15.3.6 The two-stage architecture in practice

The canonical Netflix / Airbnb pipeline:

```
50 candidate rankers from research
      |
      v
+-----+-----+
| INTERLEAVING (1 week, 50× variance reduction)
| Sign-test ranking; kill the bottom 90%
+-----+-----+
      |
      v
5 surviving rankers
      |
      v
+-----+-----+
| A/B TEST (4-8 weeks)
| Long-term engagement, retention, monetization
| Anytime-valid sequential CI for early stop (§15.1)
+-----+-----+
      |
      v
1 launched ranker
```

The total time from research idea → production launch is on the order of 6–10 weeks for a ranker that wins both stages — versus several quarters if every candidate had to go through a full A/B alone.

#### 15.3.7 Staff phrasing

> *"For ranker work I'd run two stages. Stage 1: interleaving — Team Draft with a per-search coin flip and a unbiasness sanity check on impression balance every experiment. That gives ~50× variance reduction so I can compare 20–50 rankers in a week and prune to the top handful by sign-test on user-level preferences. Stage 2: a standard A/B on the survivors for the long-term engagement and retention signal, ideally with anytime-valid sequential testing so we can stop early on clear wins. The two-stage pipeline cuts research-to-launch from quarters to weeks — the win is portfolio velocity, not per-experiment efficiency."*

**Citations:** [Innovating Faster on Personalization Algorithms at Netflix Using Interleaving](https://netflixtechblog.com/interleaving-in-online-experiments-at-netflix-a04ee392ec55) (Netflix Tech Blog); [Harnessing the Power of Interleaving and Counterfactual Evaluation for Airbnb Search Ranking](https://arxiv.org/abs/2508.00751) (Bi et al. 2025); [Optimized Interleaving for Online Retrieval Evaluation](https://www.microsoft.com/en-us/research/wp-content/uploads/2013/02/Radlinski_Optimized_WSDM2013.pdf.pdf) (Radlinski-Craswell, WSDM 2013); [An Improved Multileaving Algorithm for Online Ranker Evaluation](https://arxiv.org/abs/1608.00788) (Brost et al. 2016).

### 15.4 Quantile metrics and the quantile bootstrap

For streaming-quality and latency-class metrics (video startup time, rebuffer rate at the 99th percentile, page load), the **mean** is the wrong statistic — extreme tails are what users actually feel and what regulators care about. Netflix's approach: define metrics at specific quantiles ($p_{50}, p_{95}, p_{99}$) and use **quantile bootstrap** for valid CIs.

Mechanism:
- Define the metric as a quantile difference: $\hat\tau = q_{0.99}(Y_T) - q_{0.99}(Y_C)$.
- Bootstrap at the randomization unit (user / session): resample with replacement, recompute the quantile difference, repeat $B = 1{,}000$+ times.
- 95% CI from the 2.5th and 97.5th percentiles of the bootstrap distribution.

**Why bootstrap rather than delta method:** the delta method requires a smooth, differentiable functional with closed-form variance — quantile estimators don't have this in finite samples, and the asymptotic variance involves the density at the quantile (which itself needs estimation).

**Anytime-valid extension.** The Netflix line of work also extends confidence sequences to *quantile treatment effects* — you can sequentially monitor a $p_{99}$ latency improvement and stop early once the band excludes zero at any quantile of interest.

### 15.5 Heterogeneous treatment effects in production — the deep dive

A staff-level treatment of CATE estimation in production. The ATE answers *"does this work on average?"*; the CATE (Conditional Average Treatment Effect) answers *"who does this work for?"* The latter is what drives **targeting, personalization, and policy** decisions. The literature has matured rapidly between 2016 and 2025, and the production stack at LinkedIn / Uber / Booking / Netflix has converged on a small set of methods worth knowing.

#### 15.5.1 The CATE-vs-ATE gap — when ATE alone is incomplete

Two scenarios force you off the ATE:

| Scenario | Why CATE matters | Example |
|---|---|---|
| **Targeting under a budget** | The cost of treating is non-trivial; you want to treat only the subset that benefits enough to justify the cost | "Send a $5 promo to only the customers who'd be moved by it" |
| **Diagnosing a null** | A null aggregate effect can mask a large positive in one subgroup + a large negative in another | "Feature change is neutral overall, but power users love it and casual users hate it" |
| **Personalization** | Different users should see different treatments | "Show ranker A to new users, ranker B to repeat users" |
| **Policy learning** | The final decision is a function: who gets which treatment | "Decide who gets the upgrade prompt at all" |

The **distinction that confuses juniors:** CATE is the *estimand*; targeting / personalization / policy are the *decisions*. CATE estimation is a means; rarely is it itself the deliverable.

#### 15.5.2 The four meta-learners — S, T, X, R

The first frontier (Künzel-Sekhon-Bickel-Yu PNAS 2019). Each "meta-learner" wraps any ML model into a CATE estimator.

| Learner | Construction | $\hat\tau(x)$ formula | When it wins |
|---|---|---|---|
| **S-learner** (Single) | One model $\hat\mu(x, T)$ fit on combined data | $\hat\tau(x) = \hat\mu(x, 1) - \hat\mu(x, 0)$ | Simple; works when $T$ has strong predictive power; often surprisingly strong empirically |
| **T-learner** (Two) | Two models $\hat\mu_T(x)$ and $\hat\mu_C(x)$ fit separately on treated and control | $\hat\tau(x) = \hat\mu_T(x) - \hat\mu_C(x)$ | When treatment changes the response function shape; data plentiful |
| **X-learner** (Cross) | T-learner first, then *impute* counterfactuals on each side, then fit $\hat\tau_T$ and $\hat\tau_C$, combine with propensity weights | $\hat\tau(x) = g(x) \hat\tau_C(x) + (1 - g(x)) \hat\tau_T(x)$ | Highly imbalanced treatment / control (e.g. 5% treated, 95% control) |
| **R-learner** (Robinson-style) | Doubly orthogonal: residualize $Y$ and $T$ on $X$, then fit CATE on residuals weighted by $(T - \hat\pi(X))^2$ | Best general-purpose; theoretically grounded via orthogonal moment | Default when you need defensible CIs and have enough data |

**Empirical note** (Belkov et al. 2024 large-scale comparison on the Criteo Uplift v2.1 dataset, 14M rows): on imbalanced (85/15) marketing data, **S-learner with LightGBM achieved the highest Qini coefficient (0.376)**, with the top 20% of CATE-sorted customers capturing **77.7% of incremental conversions**. The X-learner did *not* outperform S-learner here — a finding consistent with finite-sample regularization effects. **Don't assume the most theoretically elegant learner wins on your data.**

#### 15.5.3 Causal forests and the "honesty" property

Wager-Athey (JASA 2018) — the gold standard for tree-based CATE estimation. A causal forest is a random forest where each tree estimates the CATE in its leaves rather than the response. **Honesty** is the property that the data used to *partition* a tree is disjoint from the data used to *estimate* the leaf treatment effect. This double-sample property is what gives causal forests their **pointwise asymptotic normality and consistent variance estimates** — you get a CI for the CATE at every $x$, not just a point estimate.

**Generalized Random Forests** (Athey-Tibshirani-Wager Annals 2019) extend this to any moment-condition estimator — CATE, IV, quantile, etc. — all in one framework. The reference implementation is the **`grf`** R package, also available in Python via econml.

**When causal forests win:**
- High-dimensional $X$ with nonlinear effect modifiers
- Need uncertainty quantification per individual (not just population-level CATE)
- Don't want to hand-pick interactions

**When they don't win:**
- Treatment effect is small relative to noise → BCF often does better (§15.5.4)
- Very high-dimensional sparse settings where DR-learner with elastic-net beats trees

#### 15.5.4 Bayesian Causal Forest (BCF) — for small effects in noise

Hahn-Murray-Carvalho (Bayesian Analysis 2020). A BART-based estimator that uses the **propensity score as a feature**, which mitigates **regularization-induced confounding (RIC)** — the bias that arises when ML regularization shrinks the treatment effect toward zero in regions of high propensity imbalance.

**When BCF beats causal forests:**
- Treatment effect is small relative to outcome noise
- Strong selection bias / observational data with confounding
- You want a full posterior on the CATE (not just CI)

Implementation: `bcf` R package, `bartpy` for the Python BART backend.

#### 15.5.5 Evaluating CATE — Qini curves, AUUC, calibration

The hardest part of CATE work isn't the model — it's the evaluation. Three standard tools:

**(a) Qini curve.** Sort users by predicted CATE in descending order; for each percentile $p$, plot:

$$
Q(p) = \sum_{i \in \text{top-}p\%} Y_i \cdot \mathbf{1}\{T_i=1\} - \frac{N_T(p)}{N_C(p)} \sum_{i \in \text{top-}p\%} Y_i \cdot \mathbf{1}\{T_i=0\}
$$

A perfect model's curve rises steeply then plateaus; a random model's is a diagonal. The **Qini coefficient** is the area between the model curve and the random diagonal — analogous to ROC's AUC.

**(b) AUUC** (Area Under the Uplift Curve) — alternative aggregation closely related to Qini; the two are typically reported together.

**(c) Calibration plot.** Bin observations by predicted CATE decile; compute the empirical ATE in each bin (treated mean − control mean); compare to predicted. **A well-calibrated CATE model has the calibration line on the 45° diagonal.** Imai-Ratkovic (2013) formalize this with the **GATES** statistic.

**The senior practice:** report all three. Qini + AUUC for ranking quality; calibration plot for the magnitude. Models that win on Qini but have poor calibration are useful for *targeting* (the *order* is right) but dangerous for *cost-benefit decisions* (the *magnitudes* are wrong).

#### 15.5.6 From CATE to policy — the policy-learning frontier

The decision isn't "what's the CATE?" but "who do we treat?" Athey-Wager (Econometrica 2021) develops **policy learning** as a separate estimand: find the function $\pi: X \to \{0, 1\}$ that maximizes expected value under a budget constraint.

**Two facts that surprise people:**

1. **Policy learning is sometimes easier than CATE estimation.** You don't need the *magnitude* of the treatment effect everywhere, just the *sign* at the decision boundary. A simple policy "treat top-30% by predicted CATE" often does almost as well as a sophisticated policy tree, with much less variance.

2. **A poor CATE model can support a good policy.** Even if $\hat\tau(x)$ is biased and noisy, its *ranking* of users might still pick the right top-$K$ for targeting. The Belkov et al. result above (top 20% capture 77% of incremental conversions) is this phenomenon.

**The Multi-Armed Qini (MAQ)** package (Sverdrup-Wager 2024) extends Qini-style evaluation to multi-arm and budget-constrained targeting policies. For multi-treatment problems (e.g. choosing one of N promotional offers per user), this is the modern standard.

#### 15.5.7 Industry deployment patterns

| Pattern | Industry example |
|---|---|
| **Promo targeting under a budget** | Uber Eats, DoorDash, Lyft — predict who'd convert with vs without a $5 promo; spend the budget on the highest-CATE users |
| **Feature on/off personalization** | Netflix — which users get the new player UI; LinkedIn — which members get InMail-from-recruiters |
| **Recommendation responsiveness** | Pinterest, Netflix — which users have CATE-high response to ranker changes; allocate experimentation traffic accordingly |
| **Pricing personalization** | Booking.com, Airbnb — surface-level price-segment differentiation (with regulatory caveats!) |
| **Notification frequency** | Meta, LinkedIn — how many notifications maximize each user's long-term engagement without churning |
| **Treatment ranking** | Netflix's published caveat (see 15.5.8) — when ranking treatments by CATE, the marginal-distribution issue bites |

#### 15.5.8 The marginal-distribution caveat (Netflix)

The Netflix-published gotcha: when ranking *treatments* (not subgroups) by their CATE, the naive ranking is biased if the treatments have different marginal distributions on the running covariate. Concretely: treatment A is mostly applied to users with feature $x_1$, treatment B to users with feature $x_2$. The CATE of A averaged over its actual recipients reflects the $x_1$ population; B's averages over the $x_2$ population — so comparing them isn't an apples-to-apples ranking.

**The Netflix fix:** use methods that explicitly upweight effects for users whose treatment assignment is most *unpredictable* given the covariates — i.e., focus on the **overlap region** where both treatments are plausible. This is conceptually the same as the overlap / propensity-trimming discipline in causal inference, applied at the treatment-comparison level.

#### 15.5.9 When NOT to use CATE

Five honest staff-level cases where CATE doesn't help:

| Situation | Why CATE fails |
|---|---|
| **Sample size too small for the effect size** | CATE estimation needs *much* more data than ATE — heuristically $4{-}10\times$ for similar precision per subgroup |
| **Treatment effect is genuinely homogeneous** | If $\tau(x) \approx \bar\tau$ for all $x$, you're fitting noise; report the ATE |
| **High-leverage subgroups** | Tiny subgroups with extreme CATE estimates dominate the Qini curve; check for n ≥ ~100 per leaf |
| **Calibration drift** | CATE estimates degrade over time; need monthly re-fitting and calibration monitoring in production |
| **Predictive heterogeneity ≠ causal heterogeneity** | Users with high *baseline* outcomes aren't necessarily users with high *treatment effect*. A junior mistake is fitting a CATE model that's really just predicting $Y(0)$ |

#### 15.5.10 Staff phrasing

> *"For CATE in production I'd start with the R-learner — it's the doubly-robust default with the cleanest CIs, but I'd also fit a causal forest from grf for the per-individual uncertainty quantification and an S-learner LightGBM as the empirical baseline since Belkov et al. show it surprisingly often wins on imbalanced marketing data. Evaluation is Qini coefficient and AUUC for ranking quality plus a calibration plot to check the magnitudes — a model can win on Qini but have miscalibrated magnitudes, which is dangerous for cost-benefit decisions. The framing trap is conflating CATE with policy: the deliverable is usually 'who do we treat under a budget?', and a simple top-K-by-CATE policy often does almost as well as a learned policy tree. The Netflix marginal-distribution caveat applies whenever you're ranking treatments, not subgroups."*

#### 15.5.11 Further reading

- [Recursive partitioning for heterogeneous causal effects (Athey-Imbens, PNAS 2016)](https://arxiv.org/abs/1504.01132) — the first causal-tree paper.
- [Estimation and Inference of Heterogeneous Treatment Effects using Random Forests (Wager-Athey, JASA 2018)](https://arxiv.org/abs/1510.04342) — the causal forest paper with honesty + asymptotic CIs.
- [Metalearners for estimating heterogeneous treatment effects using machine learning (Künzel-Sekhon-Bickel-Yu, PNAS 2019)](https://arxiv.org/abs/1706.03461) — the S/T/X-learner family.
- [Quasi-oracle estimation of heterogeneous treatment effects (Nie-Wager 2017/2021)](https://arxiv.org/abs/1712.04912) — the R-learner.
- [Generalized Random Forests (Athey-Tibshirani-Wager, Annals 2019)](https://arxiv.org/abs/1610.01271) — the `grf` framework.
- [Bayesian Regression Tree Models for Causal Inference (Hahn-Murray-Carvalho, Bayesian Analysis 2020)](https://arxiv.org/abs/1706.09523) — Bayesian Causal Forest.
- [Policy Learning with Observational Data (Athey-Wager, Econometrica 2021)](https://arxiv.org/abs/1702.02896) — policy learning as a separate estimand.
- [A Large-Scale Empirical Comparison of Meta-Learners and Causal Forests (Belkov et al. 2024)](https://arxiv.org/abs/2604.06123) — Criteo Uplift v2.1 14M-row benchmark; the source of the S-learner Qini = 0.376 result.
- [Multi-Armed Qini for budget-constrained targeting (Sverdrup-Wager 2024)](https://arxiv.org/abs/2403.11116) — the multi-arm policy-evaluation framework.

### 15.6 Multi-experiment platforms — the deep dive

At scale, experimentation isn't an experiment, it's a *platform*. LinkedIn runs **~41,000 concurrent A/B tests** on **700M+ members** with **35 trillion variant evaluations per day**; Google, Microsoft, Booking.com, and Meta operate at similar magnitudes. Naive A/B at scale falls apart along three axes — traffic exhaustion, interaction confounding, and operational risk. This subsection walks the technical and operational solutions.

#### 15.6.1 The scale problem

A platform that ran each experiment as a fresh 50/50 user split would saturate available traffic immediately. Three failure modes:

| Failure mode | Symptom |
|---|---|
| **Traffic exhaustion** | After ~5–10 simultaneous mutually-exclusive 50/50 experiments, no more headroom |
| **Interaction confounding** | Each user is in many experiments at once; if interactions are non-zero, effect estimates are biased |
| **Operational risk** | Without governance, a single bad experiment can take down a critical surface; without traceability, you can't tell which experiment caused a metric move |

#### 15.6.2 Three architectures, in order of sophistication

| Architecture | How traffic is allocated | When you'd use it |
|---|---|---|
| **Single-thread** | One experiment at a time, full traffic | Tiny startups; not viable at scale |
| **Mutual exclusion (multi-thread, non-overlapping)** | Each user in *at most one* experiment per surface | Pre-2010 default; still used for high-stakes UX changes |
| **Layered overlapping** (Google/Tang KDD'10; LinkedIn T-REX) | Hash-based assignment makes most experiments orthogonal; users in many simultaneously | Modern platform default |

#### 15.6.3 Layered overlapping — the Google/Tang KDD'10 framework

The dominant industry architecture (Tang, Agarwal, O'Brien, Meyer — Google KDD 2010) introduces a three-level hierarchy:

```
Domain                    e.g. "Web Search"  -- a surface / app boundary
└── Layer                 e.g. "ranker"      -- a related-changes bucket
    └── Experiment        e.g. "ranker_v17"  -- one specific A/B
```

Three rules give the architecture its power:

1. **Within a layer, experiments are mutually exclusive.** A user is in at most one experiment per layer. This is the *cost*.
2. **Across layers, experiments are orthogonal.** A user can be simultaneously in many experiments, one per layer. Independent random assignment per layer ensures expectations are unaffected by other layers. This is the *win*.
3. **A layer is owned by a team / system.** "Ranker" layer owned by ranking; "UI" layer owned by frontend; etc. Within-layer mutex is operationally natural (only one ranker active per user at a time).

Two extensions worth knowing:

- **Launch layers** — once an experiment ships to 100%, it moves to a separate "launched" layer so future experiments can layer underneath it without re-randomizing. Critical for incremental builds on top of shipped winners.
- **Biased layers / segment layers** — when an experiment must target a specific population (premium members, mobile-only), the layer is "biased" — assignment isn't uniform on the full traffic. Analysis must account for the targeting cohort.

#### 15.6.4 Hash-based assignment at scale — the LinkedIn formula

The serving path needs to evaluate variant assignment **for every request, for every experiment a user is in**. LinkedIn reports up to **1M cache reads/sec** under an RNG approach — unsustainable. The hash-based fix (deployed in LinkedIn's T-REX):

$$
\text{HASH}(\text{salt})(\text{member\_id}) \;=\; \text{FCrypt}\big(\text{concat}(\text{prefix}(\text{salt}, 4),\, \text{bytes}(\text{member\_id}))\big)
$$

Normalize the output to $[0, 1)$ by dividing by $F_{\max}$. The salt is the **experiment ID** (or the layer ID — same idea). Then:

```
hash_value = HASH(salt)(member_id) / F_MAX  ∈ [0, 1)
variant    = lookup_variant(hash_value)      # e.g. [0, 0.5) -> A, [0.5, 1) -> B
```

Three properties this gives:

- **Stateless.** No cache, no RPC, no database read on the hot path. Computed in-process.
- **Sticky.** Same `(salt, member_id)` always produces the same hash → same variant assignment across requests, sessions, devices.
- **Orthogonal across experiments.** Different salts produce independent hashes (verified by chi-squared independence tests in deployment).

LinkedIn reports **99.98% of variant evaluations are local** (no network call), making the latency budget essentially free. **35 trillion evaluations per day** are served with **200 GB total of member attribute data** (vs 26–390 TB/day for the cache-based RNG approach).

#### 15.6.5 Mutual exclusion vs orthogonal layering — when each

| Scenario | Choice |
|---|---|
| **Two experiments change the same UI element / metric path** | **Mutual exclusion** (same layer); orthogonal would create undefined behavior at the conflict point |
| **One ranker experiment, one notification experiment** | **Orthogonal** (different layers); near-zero interaction expected |
| **Two ranker experiments under development** | Mutual exclusion (same "ranker" layer) — only one ranker logic per user |
| **A ramping experiment competing with stable launched winners** | Layered, with the winners moved to launch layers and the new experiment in a fresh ramping layer |
| **A test of layout × ranker interaction** | A single factorial experiment in one layer — see §11 — rather than two orthogonal experiments |

#### 15.6.6 Multi-experiment analysis — when interactions matter

The orthogonality assumption is *in expectation*: any single user is in many experiments, and on average their effects don't interact. But interactions can be non-zero. Two responses:

**(a) Detection.** Platforms run automated pairwise interaction tests across active experiments. LinkedIn's published note: pairwise interactions are detectable; three-way and higher are "extremely rare." Detection runs at platform scale; investigators are alerted only when a pairwise interaction exceeds a threshold.

**(b) Joint analysis.** When you specifically want to estimate an interaction, fit a factorial-effect model across the relevant experiments:

$$
Y_{ij} = \alpha + \beta_A T_{Ai} + \beta_B T_{Bj} + \beta_{AB}(T_{Ai} \cdot T_{Bj}) + \epsilon_{ij}
$$

This requires the cell counts $T_A \times T_B$ to be balanced (LinkedIn's hash-based orthogonality gives this near-exactly) and enough power in each cell. The Netflix line of work extends this to anytime-valid factorial inference (§15.1).

#### 15.6.7 Platform-side governance and safety

A platform that runs 41,000 simultaneous experiments needs automated guardrails — humans can't review each. The infrastructure side:

| Component | What it does |
|---|---|
| **SRM monitor** | Automated chi-squared test on assignment ratios at every experiment, every hour; alerts on $p < 10^{-6}$ |
| **Auto-shutoff** | Hard-block on a configured guardrail metric breach (latency, error rate, revenue drop > $X$%) |
| **Ramp protocol** | New experiments start at 0.5% → 5% → 25% → 50% — limits blast radius |
| **Holdback management** | Long-lived 1–5% control population that doesn't get experimental treatments — enables long-term effect measurement |
| **Experiment registry** | Central system-of-record: every active experiment, its owner, its layer, its expected end date, its guardrails |
| **Metric repository** | Versioned metric definitions, so changing a metric definition doesn't silently change historical analyses |

#### 15.6.8 Industry numbers (for calibration)

| Company | Concurrent experiments | Member / unit base | Evaluations / day |
|---|---|---|---|
| **LinkedIn (T-REX)** | ~41,000 | ~700M | ~35 trillion |
| **Google** (Tang et al. 2010, original) | Hundreds simultaneously | Web search traffic | Not disclosed at exact volume |
| **Microsoft (ExP)** | ~10–20K | Bing + Office | Trillions |
| **Booking.com** | 1,000+ | ~250M monthly users | Tens of billions |
| **Netflix (XP)** | ~hundreds | ~250M members | ~hundreds of billions |
| **Airbnb** | ~1,000+ | ~150M monthly users | ~tens of billions |

These numbers are the floor for "platform-scale" — if a candidate says "we'd run a few experiments simultaneously" for a LinkedIn-scale problem, that's a junior-level frame.

#### 15.6.9 Staff phrasing

> *"At platform scale you don't run one experiment, you run tens of thousands. The dominant industry architecture is Tang-Agarwal's domain → layer → experiment hierarchy from KDD 2010: mutual exclusion within a layer, orthogonal across layers, with hash-based assignment so the serving path is stateless and sub-millisecond. LinkedIn's T-REX runs 41K concurrent experiments with 99.98% of assignments evaluated locally — no cache hit on the hot path. The platform side then needs automated SRM, auto-shutoff on guardrail breach, ramp protocols, a holdback population for long-term effects, and a centralized metric repository. Multi-experiment analysis closes the loop: pairwise interaction detection at platform scale, with joint factorial analysis when you specifically want to estimate an interaction. The interview test is whether you reach for layered orthogonality vs naive mutual-exclusion as the default."*

#### 15.6.10 Further reading

- [Overlapping Experiment Infrastructure: More, Better, Faster Experimentation (Tang, Agarwal, O'Brien, Meyer — Google KDD 2010)](https://research.google/pubs/overlapping-experiment-infrastructure-more-better-faster-experimentation/) — the foundational layered-overlapping paper.
- [Assign Experiment Variants at Scale in Online Controlled Experiments (Xu, Chen, Mao et al. — LinkedIn, 2022)](https://arxiv.org/abs/2212.08771) — hash-based assignment with the MD5+salt formula and the 35T/day scale.
- [A/B testing at LinkedIn: Assigning variants at scale (LinkedIn Engineering blog)](https://www.linkedin.com/blog/engineering/ab-testing-experimentation/a-b-testing-variant-assignment) — the operational walkthrough of T-REX.
- [Our evolution towards T-REX: The prehistory of experimentation infrastructure at LinkedIn](https://www.linkedin.com/blog/engineering/ab-testing-experimentation/our-evolution-towards-t-rex-the-prehistory-of-experimentation-i) — LinkedIn's architecture history.
- [Engineering for a Science-Centric Experimentation Platform (Diamantopoulos et al. — Netflix XP, 2019)](https://arxiv.org/abs/1910.03878) — Netflix's XP design philosophy.
- [It's All A/Bout Testing: The Netflix Experimentation Platform (Netflix Tech Blog)](https://netflixtechblog.com/its-all-a-bout-testing-the-netflix-experimentation-platform-4e1ca458c15) — the XP overview.
- [Testing for arbitrary interference on experimentation platforms (Saint-Jacques et al. — LinkedIn, 2017)](https://arxiv.org/abs/1704.01190) — platform-side interaction detection.

> **Case-walkthrough companion.** See [`examples/experimentation-platform-design.md`](../../examples/methods/experimentation-platform-design.md) for the step-by-step walkthrough of *"Design an experimentation platform for LinkedIn"* using this material — the 6-step framework for the interview answer.

### 15.7 Further reading — Netflix references

- [Sequential A/B Testing Keeps the World Streaming Netflix (Part 1: Continuous Data)](https://netflixtechblog.com/sequential-a-b-testing-keeps-the-world-streaming-netflix-part-1-continuous-data-cba6c7ed49df) — operational walkthrough of the always-valid framework.
- [Design-Based Confidence Sequences (Lindon et al., 2022)](https://arxiv.org/abs/2210.08639) — the technical paper underpinning §15.1.
- [Anytime-Valid Linear Models and Regression Adjusted Causal Inference](https://research.netflix.com/publication/anytime-valid-linear-models-and-regression-adjusted-causal-inference-in) — §15.2 reference.
- [Innovating Faster on Personalization Algorithms at Netflix Using Interleaving](https://netflixtechblog.com/interleaving-in-online-experiments-at-netflix-a04ee392ec55) — §15.3 reference.
- [Reimagining Experimentation Analysis at Netflix](https://netflixtechblog.com/reimagining-experimentation-analysis-at-netflix-71356393af21) — analysis-pipeline overview covering CUPED, sequential testing, quantile metrics, and CATE.
- [Quasi Experimentation at Netflix](https://netflixtechblog.com/quasi-experimentation-at-netflix-566b57d2e362) — server-level diff-in-diff on Open Connect (see also [`causal-inference-product.md`](./causal-inference-product.md)).
- [A Survey of Causal Inference Applications at Netflix](https://netflixtechblog.com/a-survey-of-causal-inference-applications-at-netflix-b62d25175e6f) and [Round 2](https://netflixtechblog.com/round-2-a-survey-of-causal-inference-applications-at-netflix-fd78328ee0bb) — broader catalog of CI methods in production.
- [It's All A/Bout Testing: The Netflix Experimentation Platform](https://netflixtechblog.com/its-all-a-bout-testing-the-netflix-experimentation-platform-4e1ca458c15) — the XP platform's design philosophy.
- [Engineering for a Science-Centric Experimentation Platform (Diamantopoulos et al., 2019)](https://arxiv.org/abs/1910.03878) — architectural paper on XP.

---

## 16. Frontier topics beyond Netflix — what's on the staff DS radar in 2025

Section §15 covers six Netflix-flavored frontier techniques. The six below are *also* frontier but live in a different industry literature — Lyft / DoorDash for switchback at scale, LinkedIn for network interference, Booking.com / Google for Bayesian A/B, and the post-2023 generative-AI experimentation wave.

### 16.1 Switchback designs at scale — Lyft / DoorDash / Uber

For products with **strong temporal demand patterns + supply-side spillover** (rideshare, food delivery, dynamic pricing), unit-level randomization violates SUTVA (§7) because the treated drivers/dashers aren't available for control orders in the same minute. The fix is **switchback**: assign treatment by **time slot × geography**, alternating.

**The carryover problem.** A treatment that boosts demand in slot $t$ pulls supply that should have served slot $t+1$. If you don't account for this, the second slot is contaminated. Two fixes:

| Fix | Mechanism |
|---|---|
| **Burn-in / dwell time** | Discard the first $k$ minutes of each slot from analysis. Lyft typically uses 10–30 min for ride-level effects |
| **Bias correction** | Model the carryover explicitly via an AR(1)-style residual structure on slot-level treatment effects |

**The slot-size tradeoff.** Long slots reduce carryover but lower experimental power (fewer effective units); short slots increase power but amplify carryover bias. Lyft's published recipe: choose slot length to make `dwell_time / slot_length ≤ 30%`, and model the residual carryover.

**Geo-time grid.** When supply is also geographically clustered, the unit becomes `(city × hour × day)`. DoorDash runs experiments on grids of `(market × dayparts)` where typical hour-of-day patterns matter.

**Citations.** [Bojinov, Simchi-Levi, Zhao — "Design and Analysis of Switchback Experiments" (Management Science 2023)](https://arxiv.org/abs/2009.00148); the Lyft Engineering blog has several published case studies on rider-level vs switchback comparisons.

### 16.2 Network interference detection at scale — ego clusters

LinkedIn's published work (Saint-Jacques et al. 2017, Karrer et al. 2021, Lin et al. 2023) addresses the practical question: **at platform scale, how do you detect when an experiment has network spillover, and how do you correct it?**

**Detection.** The simplest test: split treated users into those with many treated friends vs few treated friends, and check if outcomes differ. If yes, there's interference (assuming friendship correlation isn't itself confounded). LinkedIn formalizes this with **exposure mappings** (Aronow-Samii 2017): partition users by their "exposure" to treated peers and analyze each stratum.

**Correction — ego clusters.** Rather than randomize at the individual level, randomize **ego networks** — a focal user plus their N nearest neighbors. The trade-off is the usual one: ego clusters internalize spillover (good) but the effective sample size is smaller (worse), and there's bias-variance tradeoff in choosing cluster size.

**Modern variant — graph cluster randomization.** Partition the social graph into balanced clusters (e.g., via METIS or Louvain community detection), then randomize at the cluster level. Used in Meta / LinkedIn / Pinterest published work.

### 16.3 Bayesian A/B testing with decision-theoretic stopping

A small but growing industry trend, especially at Booking.com and parts of Google. Instead of frequentist p-values, compute the posterior on the treatment effect $\theta$ given data and a prior:

$$
P(\theta \mid \text{data}) \propto P(\text{data} \mid \theta) \cdot P(\theta)
$$

**The decision rule** isn't "is $p < 0.05$" but "does the expected loss of launching exceed the expected loss of not launching?" — a fully decision-theoretic stop:

$$
\text{Launch iff } \mathbb{E}_{\theta \sim P(\theta \mid \text{data})}[L(\text{not launch}, \theta)] > \mathbb{E}[L(\text{launch}, \theta)]
$$

where $L$ encodes the asymmetric costs (e.g., shipping a harmful change is much worse than missing a small win).

**Three advantages over frequentist.**
1. **Direct probability statements.** "Probability that treatment beats control is 0.94" is what the PM actually wants.
2. **Decision-theoretic stopping** is naturally anytime-valid under proper priors.
3. **Calibrated handling of small effects.** A weakly informative prior pulls implausibly large estimated effects toward zero.

**Three disadvantages.**
1. **Prior sensitivity.** Two analysts with different priors get different launch decisions. Mitigation: pre-commit a prior protocol.
2. **Computational cost.** MCMC or variational inference for non-Gaussian models is slower than t-tests.
3. **Auditability.** Frequentist tests are the default expected by most regulators and partners.

**Reference:** the Booking.com "Bayesian Experimentation" series on their tech blog; Stitch Fix has also published. Bayesian A/B isn't mainstream in tech the way frequentist is, but it's the standard answer when explicitly asked about it.

### 16.4 OEC drift — when north-star metrics stop tracking value

A staff-level operational point that doesn't appear in textbooks but is regularly raised in interviews: **your north-star OEC decays as the product evolves**.

The mechanism: an OEC is calibrated against historical evidence linking it to the goal metric. As the product surface changes (new features, new monetization, new user mix), the historical link weakens. Examples:

- "Time spent" was a great DAU-correlated OEC for Facebook in 2010. By 2018 it was a misleading OEC because passive scrolling rose while meaningful engagement fell.
- "Clicks" was the search-engine OEC for years. As the product moved to direct answers (Knowledge Panels, AI summaries), clicks dropped while user value rose.
- "Sessions per week" was a streaming OEC; binge-watching shifted the right metric to "engaged hours."

**The senior practice:** every 6–12 months, **re-validate** the link from OEC to the goal metric on a recent window of shipped experiments. If shipped wins on the OEC no longer predict goal-metric movement, the OEC needs refresh. A junior team rolls out an OEC and never revisits.

### 16.5 Experimentation for LLM / generative AI systems

A genuinely new frontier (2023+). LLM-based features differ from classical A/B in three ways:

| Difference | Implication |
|---|---|
| **No single "correct" output** | Click-through and conversion still work as metrics; quality is captured by win-rate or rating-based metrics |
| **High response variability** | Same prompt → different outputs → user clicks vary by sampling. Power requires either temperature = 0 (less natural) or substantial sample size with temperature > 0 |
| **Subjective quality dimensions** | "Helpfulness," "honesty," "harmlessness" aren't measurable from user behavior alone; need LLM-judge evaluation or human annotation |

**Three experimentation patterns emerging:**

1. **Win-rate experiments** (RLHF-style). Show users two LLM outputs (A vs B), they pick. Aggregate pairwise wins → preference ranking. Used at Anthropic, OpenAI, Cohere; the standard for model evaluation but heavy operational cost.
2. **LLM-as-judge for offline eval.** A stronger LLM scores outputs from candidate models on a held-out prompt set. Cheap, fast, but biased toward the judge's preferences and ungrounded in real-user behavior.
3. **Behavioral A/B on downstream conversion.** Did users follow up after the LLM response? Did they accept the suggestion? This is the most aligned with classical A/B but signal is weakest for subjective quality.

**The staff move:** combine all three — win-rate for product-quality validation, LLM-judge for fast iteration, behavioral A/B for the launch decision.

**Open frontier:** how to do CUPED-style variance reduction when the outcome is response quality? How to do anytime-valid sequential testing on win-rate data? Mostly unsolved as of 2025.

### 16.6 Pre-experiment platform health — A/A at scale and metric trustworthiness

At platform scale (40K+ concurrent experiments), the platform itself becomes the meta-experiment. Industry practice has evolved:

| Health check | What it does |
|---|---|
| **A/A tests as platform meta-experiments** | Run thousands of synthetic A/A tests continuously; flag any metric whose p-value distribution isn't uniform → its variance estimate is broken |
| **Metric trustworthiness score** | For each metric, track historical sensitivity / variance / churn — and flag metrics with degrading trustworthiness |
| **Cross-experiment metric drift detection** | Track when a metric's pre-period mean shifts between experiments; if it's drifting, the metric needs a calibration refresh |
| **Logging instrumentation tests** | Synthetic events triggered through the production path verify exposure logging is correct |
| **Experiment-platform A/B** | When you change the platform itself (a new randomizer, a new metric definition pipeline), A/B it against the old one before flipping fully |

Netflix has written on this — "metric trustworthiness" is treated as a first-class platform concern at the same priority as SRM.

---

## 17. Trustworthy at scale — Kohavi-Tang-Xu's "Trustworthy Online Controlled Experiments"

Kohavi, Tang, and Xu's *Trustworthy Online Controlled Experiments: A Practical Guide to A/B Testing* (Cambridge 2020) is the de facto industry reference, written by the leaders of the Microsoft, Google, and LinkedIn experimentation orgs. Most senior interviewers have read it. Below are the most-referenced ideas, mingled with where they connect to this playbook.

### 17.1 The Bing $100M experiment — why experimentation pays off

The book's opening case: a Microsoft Bing engineer proposed a tweak to how ad titles were displayed. The experiment showed a **~12% revenue lift** with no impact on user metrics — running annualized to **>$100M**. The PM had originally ranked the idea as low priority. The case illustrates why:

1. **Experts predict experiment outcomes poorly.** The book cites Microsoft data showing senior product leads correctly predict the direction of experiment outcomes only ~60% of the time, and the magnitude almost never.
2. **The cost of running an experiment is low; the cost of not running one is hidden but huge.** Implicit in every "we know what users want" decision is the bet that you're 80%+ correct. The book's empirical bet: you're closer to 60%.

**The interview-grade phrase:** *"The Trustworthy book's headline finding is that even senior teams predict experiment outcomes only ~60% accurately — so the value of running the experiment is much higher than the apparent cost. The $100M Bing ad-title example is the canonical illustration."*

### 17.2 The cultural maturity model — Crawl / Walk / Run / Fly

The book classifies experimentation orgs into four stages:

| Stage | Cadence | Capabilities |
|---|---|---|
| **Crawl** | 1–10 experiments / quarter | Single thread; no SRM monitoring; manual analysis; "ship what looks good" culture |
| **Walk** | 1–10 / month | Multiple experiments simultaneously; basic SRM; manual but standardized analysis; some governance |
| **Run** | 1–10 / week | Layered overlapping (§15.6.3); CUPED-as-default; automated alerts; central metric repository |
| **Fly** | 10+ / day, 1000s concurrent | Anytime-valid sequential default (§15.1); HTE in production (§15.5); platform-level governance; experimentation is part of every PM's daily workflow |

**Why this model matters for interviews.** When asked "how would you improve our experimentation practice?", anchoring against this model gives a structured answer: identify the current stage, name the next milestones, prioritize the capabilities that unblock the next stage transition.

### 17.3 Twyman's Law and the discipline of skepticism

Originally attributed to Tony Twyman (1922–2024) of British market research, the book makes **Twyman's Law** a central maxim:

> *"Any figure that looks interesting or different is usually wrong."*

Application: a surprising experiment result is **more likely** to be a bug, an SRM, a definitional change, or a peeking-inflated false positive than a real effect. The book's prescription: before celebrating a +20% result, run the full sanity-check battery — SRM, A/A on a control segment, metric-definition history, logging audit. Most surprises are explained by these.

**This is the empirical foundation of §6 (Trustworthy execution)** — the "pre-result checklist" is exactly the Twyman discipline operationalized.

### 17.4 The OEC framework — composition, gameability, sensitivity

The book's three-property test for an OEC, more rigorous than the textbook treatment:

| Property | Question |
|---|---|
| **Composability** | Does the OEC combine driver metrics into a single decision-grade scalar? (Weighted sum; weights pre-committed) |
| **Sensitivity** | Will the OEC move on the kinds of changes the team makes? (Validate against historical experiments) |
| **Gameability** | Can a team optimize the OEC while harming the goal metric? (Run the thought experiment explicitly) |

The book is sharp on **gameability**: the OEC must survive a team trying to game it. *"Time on site"* fails because notification spam moves it; *"sessions per week"* fails because manufactured re-engagement triggers move it. The OEC has to be insulated against the optimizer.

**Cross-reference.** §2 of this playbook covers OEC; the Kohavi book formalizes the gameability test as the highest-priority filter.

### 17.5 Numbing effects — the multiple-comparisons crisis at platform scale

When a platform runs 10,000 experiments per quarter, the family-wise false-positive rate at $\alpha = 0.05$ is **astronomical**. Even with BH correction, the effective threshold drops dramatically. The book's argument: at scale, you must **tier metrics by prior expectation** and apply stricter $\alpha$ to lower-prior metrics.

| Tier | Prior expectation of impact | $\alpha$ |
|---|---|---|
| Primary OEC | Expected to move | 0.05 |
| Secondary drivers | Possibly affected | 0.01 |
| Guardrails | Should not move | 0.005 |
| Long-tail / exploratory | Unknown | 0.001 |

**Cross-reference.** §2.3 (combined OEC) and §8.2 (multiple testing) implement this; the Kohavi framing makes it the platform's central anti-pollution mechanism.

### 17.6 The book's "rules" worth memorizing

Kohavi-Tang-Xu's most-cited practical rules (paraphrased):

1. **Compute experimentation value as 1 − P(correct without testing).** If your team predicts correctly 60% of the time, the experiment is valuable on 40% of decisions.
2. **Trust nothing in interpretation until you've cleared sanity checks** (Twyman's Law).
3. **The OEC is a contract** — once committed, don't change it during the experiment.
4. **Practical significance ≠ statistical significance.** State both thresholds before the result lands. (§8.5 launch quadrant.)
5. **Holdback is mandatory for any non-trivial launch.** A small permanent control is the only honest way to measure long-term effect.
6. **Variance reduction is the lever.** CUPED, triggering, stratification — adopt them as the platform default, not as advanced add-ons.
7. **Goodhart's Law applies to every metric.** "When a measure becomes a target, it ceases to be a good measure." Watch the gaming.
8. **Run the diagnostic test before the headline test.** SRM, A/A, instrumentation — every experiment, every time.
9. **Experiment scope ≤ team capacity to act.** Don't run 10× more experiments than you can interpret or ship.
10. **Compounding small wins.** A team that wins 30 0.5%-lift experiments per year compounds to ~16% — outpaces a team gambling on home runs.

### 17.7 Where the book deepens this playbook

The mapping back to existing sections, for quick reference:

| Book chapter / theme | This playbook |
|---|---|
| Ch 1–2: Why experiment; Bing $100M example | §1 strategic frame; §17.1 above |
| Ch 3: Twyman's Law; surprising-result skepticism | §6 trustworthy execution; §17.3 above |
| Ch 4: Cultural maturity (Crawl-Walk-Run-Fly) | §17.2 above |
| Ch 5: Speed matters | §15.1 anytime-valid; §15.3 interleaving |
| Ch 6: OEC | §2; §17.4 above |
| Ch 7: Statistics fundamentals | §4 sample-size; §6 SRM |
| Ch 8: A/A tests | §6.1 |
| Ch 9: Randomization | §3; §15.6.4 hash-based |
| Ch 10–11: Interpreting results, common traps | §8 |
| Ch 12: MAB | §10 + §15.1.3 |
| Ch 13: Variance reduction (CUPED) | §5; §15.2 |
| Ch 14: Long-term effects | §8.3; §15.6.7 holdback |
| Ch 15: Network effects | §7; §16.2 above |
| Ch 16–17: Heterogeneous effects; quasi-experiments | §15.5; [`causal-inference-product.md`](./causal-inference-product.md) |
| Ch 22: Common pitfalls | §6, §8, §14 |

### 17.8 Reference

- Ron Kohavi, Diane Tang, Ya Xu — *Trustworthy Online Controlled Experiments: A Practical Guide to A/B Testing*, Cambridge University Press, 2020. ISBN 978-1108724265. Companion site: [experimentguide.com](https://experimentguide.com).

---

## 18. Related notes

- [`ml-interview-prep/algorithms/notes/causal_inference.md`](../../../repos/ml-interview-prep/algorithms/notes/causal_inference.md) — DiD / RDD / IV / synthetic control / DML / uplift / sensitivity analysis.
- [`ml-interview-prep/algorithms/notes/time_series_forecasting.md`](../../../repos/ml-interview-prep/algorithms/notes/time_series_forecasting.md) — walk-forward validation, look-ahead bias, drift monitoring (parallels novelty/holdback discipline).
- [`examples/experiment-design.md`](../../examples/methods/experiment-design.md) — the shorter case-walkthrough version of A/B design (use this for the interview answer; this file for the playbook depth).
- [`examples/experimentation-platform-design.md`](../../examples/methods/experimentation-platform-design.md) — the LinkedIn "design a platform" system-design case walkthrough.
- [`examples/metrics-diagnosis.md`](../../examples/product-questions/metrics-diagnosis.md) — what to do when a metric *moved* and you have to investigate, not run an experiment.
