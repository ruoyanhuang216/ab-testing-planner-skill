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

> **Companion notes.** Quasi-experimental detail (DiD/RDD/IV/synthetic control/DML, sensitivity analysis, uplift) lives in companion causal-inference notes. Time-series considerations (seasonality, novelty fade, holdback dynamics) overlap with companion time-series notes. This guide cross-links rather than duplicates.

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

> 📎 **Deep dive:** [The unit-of-analysis trap — ICC, DEFF, and the four fixes](deep-dives/unit-of-analysis.md) — the design-effect math, plus step-by-step worked examples (with code) for cluster-robust SEs and the cluster bootstrap.

**Example.** *Doordash, ranker tweak that may show different restaurants on different sessions.* If you randomize by user, the ranker is consistent per user → clean. If you randomize by session, a hungry customer's "good" session can pull the next session's expectation — and you have within-user correlation. The right answer depends on whether the change can be invisible across sessions; if yes, session randomization gives more power, but you must analyze with the right variance.

---

## 4. Sample size & MDE — the math behind the number

> 📎 **Deep dive:** [Test statistics & sample size — assumptions, derivations, and resampling](deep-dives/test-statistics-and-sample-size.md) — where each formula comes from (full derivations), the assumptions behind every test, when to go non-parametric, regression/advanced estimators, and the resampling toolbox (bootstrap, permutation, jackknife — when & how).

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

A common probe — *lockout 10%, recovery pass-rate 50%, detect a 15% relative lift* — illustrates the **driver-vs-success-metric tradeoff**: the rare downstream success metric needs ~9× more users than the dense mid-funnel driver, because $\delta$ enters $n\approx 16\sigma^2/\delta^2$ *squared*. Power on the driver (when it's causally linked to success — §2.2), then validate the success metric on a long holdback.

> 📎 **Worked example:** [the full sample-size math, both metrics](deep-dives/worked-examples.md#uar-sample-size-example).

---

## 5. Variance reduction — the staff-level differentiator

For the same traffic, variance reduction is the lever that turns "we can't detect this" into "we can." Five techniques in roughly ascending sophistication.

> 📎 **Deep dive:** [Variance reduction — a worked example of each method](deep-dives/variance-reduction-examples.md) — a concrete, numeric example per technique (triggering, transformations, stratification, CUPED, paired/interleaving), how much each saves, what it costs, and how they compose multiplicatively.

### 5.1 Filtering / triggering — only count exposed users

> 📎 **Deep dive:** [Triggered analysis & counterfactual logging (Robinhood Instant)](deep-dives/triggered-analysis.md) — a production example: nested exposure vs decision-divergence triggers, the ~1/trigger-rate power gain, and the validity conditions (arm-invariant trigger, counterfactual logging, no post-treatment selection).

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

> 📎 **Deep dive:** [Geo randomization — coarse assignment, user-level questions (Uber)](deep-dives/geo-randomization.md) — why rider-level splits fail in a marketplace, why effective $n$ collapses to ~the number of cities, and how to analyze (DiD + CUPED + randomization inference, synthetic control for few markets).
>
> 📎 **Deep dive:** [Network / social-graph randomization](deep-dives/network-randomization.md) — why spillover travels along edges, the direct/spillover/GATE estimands, graph-cluster (Louvain/METIS) and saturation designs, and the edge-cut bias–variance knob.

| Design | Mechanism | Cost |
|---|---|---|
| **Cluster randomization** (neighborhoods, friend cliques) | Treat whole clusters identically | Fewer effective units → more variance |
| **Geo / market randomization** | Whole DMA / city goes treatment or control | Very few units, geographies differ |
| **Switchback** (time slot) | Same market alternates treatment / control by hour or day | Carryover, day-of-week effects |
| **Ego-network randomization** | Randomize seed, but include 1-hop neighbors in treated cluster | Hard to implement correctly |
| **Counterfactual matched markets** | Use a synthetic control on a separate market as the comparator | Requires SCM modeling — see companion causal-inference notes |

### 7.2 The two-sided-market case — Doordash flavor

For Doordash's market-level changes (new fee structure, expanded radius), the supply (restaurants, dashers) responds. Two valid designs:

1. **Switchback by market × time slot.** Run treatment for 2-hour windows alternating with control across markets. Effective when carryover decays within the slot duration. Risks: dinner-rush bias, dashers learning the schedule.
2. **Geo experiments (DMA-level).** Treat e.g. 30 cities, hold 30 as control, match on pre-period demand. Use synthetic-control style estimators (see companion causal-inference notes §Synthetic DiD). Few units → low power → MDE measured in single-digit percentage points typically.

**Sanity check before declaring a two-sided design.**
1. *How big is the spillover?* If small (e.g. 1% of treated drivers' deliveries displace control orders), unit-level randomization with a small interference adjustment can still be valid.
2. *Is your spillover model correct?* Misspecified spillover models bias the answer worse than no model.
3. *Could you measure spillover first?* Run a small switchback or geo to *estimate* the interference factor before committing to the design.

---

## 8. Reading results — pitfalls and their fixes

### 8.1 Peeking and sequential testing

Looking at the test early and stopping the moment it's "significant" inflates the type-I error far past $\alpha$.

**Why peeking inflates Type-I error.** Under H₀ (no real effect) the running test statistic is a *random walk* — as data accumulates the cumulative difference wanders around zero and the p-value bounces up and down. A fixed-horizon test asks "is it past the boundary *at the one pre-set endpoint*?" — true ~5% of the time by construction. A peeker instead asks "does it *ever* cross the boundary at any of my looks?" Each look is another (correlated) chance to cross, so the probability of crossing *at least once* accumulates — this is the multiple-comparisons problem (§8.2), but across *time* instead of across metrics. With continuous monitoring the walk crosses any fixed boundary with probability → 1, so a determined peeker reaches "significance" on pure noise almost surely.

An A/A simulation makes it concrete — peeking at 1 / 5 / 10 / 50 looks drives the false-positive rate from ~5% to ~30%; see the [worked example](deep-dives/worked-examples.md#aa-peeking-simulation).

The fixes:

- **Don't peek.** Pre-commit to a duration; only read at the end.
- **If you need to peek**, use **sequential testing** methods: mSPRT (mixture sequential probability ratio test), always-valid p-values (Howard et al.), group sequential boundaries (O'Brien-Fleming, Pocock). These *widen the decision boundary at each look* so the cumulative crossing probability stays at $\alpha$ — at the cost of some efficiency or stricter early thresholds. Full quantified treatment in **§15.1**.
- **For early stopping for *futility*** (no point continuing), use conditional power or predictive probability — both well-defined Bayesian / frequentist approaches.

### 8.2 Multiple hypothesis testing — FWER vs FDR

Testing many metrics or variants inflates false positives. Two control regimes: **FWER** (Bonferroni / Holm — bound the probability of *any* false positive; strict, for guardrails and regulatory decisions) vs **FDR** (Benjamini–Hochberg — bound the *expected fraction* of false discoveries among rejections; higher power, for exploratory metric sweeps). Production platforms run a **hybrid**: FWER-strict on a few critical guardrails, FDR across the long tail of secondary metrics.

> 📎 **Deep dive:** [FWER vs FDR — the procedures, the math, and the hybrid platforms actually run](deep-dives/multiple-comparisons.md).

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
- **Holdback experiment:** after launching, keep 1–5% of users on control indefinitely. Measure long-term effect on that holdback. Cross-reference companion time-series notes §Walk-forward retraining cadence — same discipline applies.
- **Reverse experiment:** post-launch, switch a fresh sample of users *back* to control. Did they degrade? You've measured the steady-state effect.

### 8.4 Simpson's paradox

The aggregated treatment effect disagrees with — even *reverses* — every subgroup's effect. It needs two ingredients together: (a) segments with very different baseline rates, **and** (b) a treatment/control split that's *imbalanced across those segments* (from an assignment bug or organic traffic mix).

**Example (a device-segmented reversal).** A new checkout flow can beat control *in every device segment* yet lose *in aggregate* when treatment is disproportionately served to the low-baseline (mobile) segment — aggregation confounds the *effect* with the *segment composition*. → [worked example with the numbers](deep-dives/worked-examples.md#simpsons-paradox-example).

**The specific fix — stratify and re-weight.** Compute the effect *within* each segment, then combine with weights equal to each segment's share of the **overall** population (not its per-arm share):

$$\widehat{\text{ATE}} = \sum_s w_s\,\big(\bar y_{s,\text{treat}} - \bar y_{s,\text{control}}\big), \qquad w_s = \frac{n_s}{N}$$

This is the post-stratification / Cochran–Mantel–Haenszel estimator. Two levels of fix:
- **Prevention (best):** **stratified randomization** — assign 50/50 *within* each segment, so the split is balanced by construction and Simpson can't arise from allocation. CUPED / regression adjustment that controls for the segment buys the same protection.
- **Diagnosis:** an imbalanced split within segments is usually an **SRM** symptom (§6.2) — check per-segment assignment ratios before trusting any aggregate.

*Staff reflex:* whenever the aggregate looks suspiciously different from the segments, suspect Simpson, and never report a pooled effect without confirming the arm split is balanced within the segments that drive the metric.

### 8.5 The launch decision quadrant

A two-by-two of *statistical* significance vs *practical* significance:

| | Practically meaningful | Not practically meaningful |
|---|---|---|
| **Stat sig** | **Launch.** | Don't launch — effect too small to matter; revisit OEC. |
| **Not stat sig** | Inconclusive — either re-run with more power *or* launch if CI overlaps the practical threshold (a "neutral with potential" decision). | **Don't launch.** Effect is plausibly zero or trivial. |

**Practical-but-not-statistical** with CI extending past the practical threshold is the most-debated quadrant. The senior answer is *"the experiment doesn't have power to conclude; either re-run powered for the smaller effect, or — if the cost of relaunching is high and the downside is small — launch as a calculated bet with monitoring."*

### 8.6 The test toolbox — which test for which statistic

> 📎 **Deep dive:** [Test statistics & sample size](deep-dives/test-statistics-and-sample-size.md) — assumptions behind each statistic, when non-parametric is (and isn't) the right call, and the resampling toolbox.

A/B analysis is "compare two groups," but *what* you compare — the **statistic** — decides the test. Lead with the right one; reach for a t-test on everything and an interviewer pounces.

| You're testing… | Parametric (≈ normal / large n) | Non-parametric / robust | Formula / notes |
|---|---|---|---|
| **Mean**, 2 groups | Welch's t-test (unequal var) | Mann–Whitney U; permutation test | $t=\dfrac{\bar x_1-\bar x_2}{\sqrt{s_1^2/n_1+s_2^2/n_2}}$; large $n$ → z |
| **Mean**, 1 group vs constant | one-sample t-test | Wilcoxon signed-rank | $t=(\bar x-\mu_0)/(s/\sqrt n)$ |
| **Mean**, before/after (paired) | paired t-test | Wilcoxon signed-rank | t-test on the per-unit differences |
| **Mean**, 3+ groups | one-way ANOVA ($F$) | Kruskal–Wallis | $F=\text{MS}_{\text{between}}/\text{MS}_{\text{within}}$ |
| **Proportion**, 1–2 groups | two-proportion z-test | Fisher's exact (small $n$) | pooled SE (Appendix A.6); $\chi^2$ is equivalent |
| **Proportion**, $r\times c$ table | $\chi^2$ test of independence | Fisher's exact | $\chi^2=\sum (O-E)^2/E$ |
| **Variance / spread** | F-test (2 grps — *normality-sensitive!*) | **Levene** / **Brown–Forsythe** (robust) | prefer Levene in practice |
| **Median / percentiles** | — (no clean normal test) | **quantile bootstrap**; Mood's median test | bootstrap the quantile's CI → **§15.4** |
| **Whole distribution / shape** | — | Kolmogorov–Smirnov; Anderson–Darling; $\chi^2$ GOF | for "did the *distribution* change," not just the mean |
| **Adaptive / sequential data** | mSPRT, always-valid p (**§15.1**) | — | iid tests are invalid under peeking/bandits |

Three rules of thumb: **(1)** rates/counts → proportion or count tests, not a t-test on a 0/1 column; **(2)** heavy-tailed or skewed metrics (revenue, latency) → Welch + a non-parametric or bootstrap cross-check, or analyze a **capped / winsorized** version; **(3)** if you care about the *tail* (p95 latency) not the average, test the **quantile** (§15.4), not the mean.

> **Cross-reference — the full test directory.** Derivations, assumptions, and the decision flowchart for every cell above live in a companion hypothesis-testing reference — Part 2 (means / proportions / variances / distributions), Part 8 (what happens when assumptions are violated), Part 9 (decision flowchart), and **Appendix A** (Wilcoxon signed-rank, Mann–Whitney U, Kruskal–Wallis, Fisher's exact, Levene / Brown–Forsythe, Friedman, binomial exact).

---

## 9. When you can't randomize — quasi-experiments

When A/B testing is impossible or impractical, the rigorous fallback is quasi-experimental causal inference. Brief map; deep treatment lives in companion causal-inference notes.

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

### 10.5 Worked example — MAB beats A/B for a short-lived headline test

*"5 headlines for a story that's hot for a day — A/B/n or bandit?"* A fixed even split wastes ~80% of impressions on non-winners while the story is still hot; Thompson Sampling shifts traffic to the leader as it learns. In simulation the bandit captures ~19% more clicks than the equal split — the **saved regret**. This is the canonical MAB-wins setting (§10.2): short shelf-life, direct per-impression opportunity cost, many arms.

> 📎 **Worked example:** [the simulation and the regret accounting](deep-dives/worked-examples.md#mab-vs-ab--short-lived-headline-test).

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

**The test statistics.** Code the two factors as $X, Y \in \{0,1\}$ (or $\pm 1$) and fit a regression with an interaction term:

$$y = \beta_0 + \beta_X X + \beta_Y Y + \beta_{XY}\,(X\cdot Y) + \varepsilon$$

- **Main effect of X** $=\beta_X$ (the ranker's effect at $Y=0$); **main effect of Y** $=\beta_Y$. Test each with its **t-statistic** $t=\hat\beta/\text{SE}(\hat\beta)$.
- **Interaction** $=\beta_{XY}$ — how much the two *together* differ from the sum of their parts; tested the same way (or a **two-way ANOVA** $F$-test per effect, equivalent for a balanced $2\times2$). $\beta_{XY}>0$ = synergy, $<0$ = antagonism / cannibalization.
- Powering the interaction needs **~4× the per-arm sample** of a main effect at the same MDE (the interaction contrast carries roughly twice the SE) — the usual reason teams can't conclude on it.

**Shipping decision logic.** Read the interaction *first*, then the main effects:

| Interaction $\beta_{XY}$ | Then look at | Ship decision |
|---|---|---|
| Not significant | each main effect independently | ship whichever factors individually win — they're additive, they don't interfere |
| Significant **> 0** (synergy) | — | ship **X and Y together**; the combo beats the parts (e.g. the new ranker only shines under the new layout) |
| Significant **< 0** (antagonism) | — | ship **only the better single factor**; shipping both destroys value (they cannibalize) |
| Not sig, under-powered | strong main effects | ship on the main effects, but **keep the combined cell as a monitored holdback** post-launch |

*Staff reflex:* the factorial earns its cost in the **antagonism** case — two features that each test positive *alone* but hurt *together*. Separate single-factor tests would green-light both and you'd ship a loss; the interaction term is the only thing that flags it. For the full $2^k$ machinery — effect contrasts, confounding / aliasing in fractional designs, and resolution — see the DOE notes in a companion DOE reference (Part 3), and the test-statistic directory in that hypothesis-testing reference (referenced in §8.6).

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

A full-stack staff answer to *"should Doordash extend free delivery to non-DashPass customers on orders > $15?"*, walked end to end: decide A/B is the right tool → frame a combined OEC (orders − subsidy weight) with DashPass-renewal as a tighter-$\alpha$ guardrail → user-level randomization, stratified, CUPED (~460K/arm vs 1.2M) → A/A + SRM + triggering on qualifying baskets → market-level interference check → pre-committed launch rubric → permanent 5% holdback for long-term LTV.

> 📎 **Worked example:** [the full six-step walkthrough](deep-dives/worked-examples.md#doordash-end-to-end--free-delivery-for-non-dashpass).

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

Fixed-horizon p-values are invalid under continuous monitoring (the §8.1 peeking problem). **Anytime-valid** methods — mSPRT, always-valid p-values / confidence sequences, and group-sequential boundaries (O'Brien–Fleming, Pocock) — stay valid at *every* look by widening the boundary as data accrues, trading some peak power for the freedom to stop anytime.

> 📎 **Deep dive:** [the peeking math, three equivalent framings, the cost of validity, decision procedures, and industry deployments](deep-dives/sequential-testing.md).

### 15.2 Regression-adjusted sequential testing — CUPED meets anytime-valid

CUPED-style regression adjustment composes with anytime-valid inference: adjust the outcome with a pre-period covariate, then run the sequential test on the residual — variance reduction and continuous monitoring at once.

> 📎 **Deep dive:** [regression-adjusted sequential testing](deep-dives/sequential-testing.md#152-regression-adjusted-sequential-testing--cuped-meets-anytime-valid).

### 15.3 Interleaving — the deep dive on ranker experiments

**Interleaving** blends two rankers' results into one list shown to one user and measures which side wins the clicks — each user is their own control, so between-user variance vanishes and it's **10–100× more sensitive** than a between-user A/B for ranking quality. Use it as a fast pre-screen, then confirm winners with a standard A/B.

> 📎 **Deep dive:** [the classical algorithms, the preference (sign) test, fidelity gotchas, and the two-stage interleaving→A/B architecture](deep-dives/interleaving.md).

### 15.4 Quantile metrics and the quantile bootstrap

For streaming-quality and latency-class metrics (video startup time, rebuffer rate at the 99th percentile, page load), the **mean** is the wrong statistic — extreme tails are what users actually feel and what regulators care about. Netflix's approach: define metrics at specific quantiles ($p_{50}, p_{95}, p_{99}$) and use **quantile bootstrap** for valid CIs.

Mechanism:
- Define the metric as a quantile difference: $\hat\tau = q_{0.99}(Y_T) - q_{0.99}(Y_C)$.
- Bootstrap at the randomization unit (user / session): resample with replacement, recompute the quantile difference, repeat $B = 1{,}000$+ times.
- 95% CI from the 2.5th and 97.5th percentiles of the bootstrap distribution.

**Why bootstrap rather than delta method:** the delta method requires a smooth, differentiable functional with closed-form variance — quantile estimators don't have this in finite samples, and the asymptotic variance involves the density at the quantile (which itself needs estimation).

**Anytime-valid extension.** The Netflix line of work also extends confidence sequences to *quantile treatment effects* — you can sequentially monitor a $p_{99}$ latency improvement and stop early once the band excludes zero at any quantile of interest.

### 15.5 Heterogeneous treatment effects in production — the deep dive

The ATE hides who the treatment helps or hurts. **CATE** methods estimate per-segment effects: meta-learners (S/T/X/R), causal forests (with the honesty property), and Bayesian Causal Forest for small effects in noise; evaluate with Qini / AUUC and calibration, then turn CATE into a targeting *policy*. Mind the marginal-distribution caveat and the multiplicity of segment tests.

> 📎 **Deep dive:** [meta-learners, causal forests, CATE evaluation, policy learning, and deployment patterns](deep-dives/heterogeneous-treatment-effects.md).

### 15.6 Multi-experiment platforms — the deep dive

Running thousands of concurrent experiments needs infrastructure, not just statistics. **Layered overlapping** designs (Google / Tang KDD'10) let each user join one experiment per layer; **hash-based assignment** (`hash(unitId · layerSalt) mod N`) gives stable, independent, reproducible bucketing; **mutual exclusion** isolates experiments that would interact while orthogonal layers maximize throughput — plus carryover / pre-experiment bias controls and platform governance.

> 📎 **Deep dive:** [architectures, the assignment formula, mutual-exclusion-vs-layering, and governance](deep-dives/multi-experiment-platforms.md).

### 15.7 Further reading — Netflix references

- [Sequential A/B Testing Keeps the World Streaming Netflix (Part 1: Continuous Data)](https://netflixtechblog.com/sequential-a-b-testing-keeps-the-world-streaming-netflix-part-1-continuous-data-cba6c7ed49df) — operational walkthrough of the always-valid framework.
- [Design-Based Confidence Sequences (Lindon et al., 2022)](https://arxiv.org/abs/2210.08639) — the technical paper underpinning §15.1.
- [Anytime-Valid Linear Models and Regression Adjusted Causal Inference](https://research.netflix.com/publication/anytime-valid-linear-models-and-regression-adjusted-causal-inference-in) — §15.2 reference.
- [Innovating Faster on Personalization Algorithms at Netflix Using Interleaving](https://netflixtechblog.com/interleaving-in-online-experiments-at-netflix-a04ee392ec55) — §15.3 reference.
- [Reimagining Experimentation Analysis at Netflix](https://netflixtechblog.com/reimagining-experimentation-analysis-at-netflix-71356393af21) — analysis-pipeline overview covering CUPED, sequential testing, quantile metrics, and CATE.
- [Quasi Experimentation at Netflix](https://netflixtechblog.com/quasi-experimentation-at-netflix-566b57d2e362) — server-level diff-in-diff on Open Connect (see also companion causal-inference notes).
- [A Survey of Causal Inference Applications at Netflix](https://netflixtechblog.com/a-survey-of-causal-inference-applications-at-netflix-b62d25175e6f) and [Round 2](https://netflixtechblog.com/round-2-a-survey-of-causal-inference-applications-at-netflix-fd78328ee0bb) — broader catalog of CI methods in production.
- [It's All A/Bout Testing: The Netflix Experimentation Platform](https://netflixtechblog.com/its-all-a-bout-testing-the-netflix-experimentation-platform-4e1ca458c15) — the XP platform's design philosophy.
- [Engineering for a Science-Centric Experimentation Platform (Diamantopoulos et al., 2019)](https://arxiv.org/abs/1910.03878) — architectural paper on XP.

---

## 16. Frontier topics beyond Netflix — what's on the staff DS radar in 2025

Section §15 covers six Netflix-flavored frontier techniques. The six below are *also* frontier but live in a different industry literature — Lyft / DoorDash for switchback at scale, LinkedIn for network interference, Booking.com / Google for Bayesian A/B, and the post-2023 generative-AI experimentation wave.

### 16.1 Switchback designs at scale — Lyft / DoorDash / Uber

> 📎 **Deep dive:** [Geo randomization (Uber)](deep-dives/geo-randomization.md) — switchback as the variance-reducing variant of geo, the effective-$n$ collapse, and the analysis recipe.

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

> 📎 **Deep dive:** [Network / social-graph randomization](deep-dives/network-randomization.md) — direct/spillover/GATE estimands and the exposure mapping, graph-cluster (Louvain/METIS) + saturation/two-stage designs, the edge-cut bias–variance knob, and cluster-level inference.

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
| Ch 16–17: Heterogeneous effects; quasi-experiments | §15.5; companion causal-inference notes |
| Ch 22: Common pitfalls | §6, §8, §14 |

### 17.8 Reference

- Ron Kohavi, Diane Tang, Ya Xu — *Trustworthy Online Controlled Experiments: A Practical Guide to A/B Testing*, Cambridge University Press, 2020. ISBN 978-1108724265. Companion site: [experimentguide.com](https://experimentguide.com).

---

## Appendix A — Foundations refresher: the Udacity / Google "A/B Testing" course

*A back-to-basics review of the canonical fundamentals, for warming up before an interview. The body of this playbook is staff-level; this appendix is the ground floor it stands on. Notes adapted from Google's Udacity course **"A/B Testing"** (Carrie Grimes & Caroline Buckey), via the community notes repo [`nktnlx/ab_testing_by_google_udacity`](https://github.com/nktnlx/ab_testing_by_google_udacity). The §-links point to where each idea is developed in depth above.*

Five modules in one pass, then a formula quick-card and the mapping back to the deep sections.

### A.1 Overview & the statistics core
- **The process:** hypothesis → choose metric → review statistics → design → analyze → decide.
- **CTR vs CTP.** *Click-through **rate*** = clicks / page-views (an event rate). *Click-through **probability*** = unique users who clicked / unique users (a per-user probability ≤ 1). Use CTP when the question is "did the user click *at all*" and the unit of analysis is the user.
- **Binomial → Normal.** A click-probability metric is binomial; for large n it's approximately Normal, which is what lets you use z-scores. SE of one proportion: `SE = √[p(1−p)/n]`. The normal approximation holds when `n·p > 5` (and `n·(1−p) > 5`).
- **Confidence interval:** `p̂ ± z·SE`; `z = 1.96` for 95%.
- **Hypothesis testing:** H₀ = "no difference," Hα = "difference"; two-tailed (direction-agnostic) vs one-tailed.
- **Two error rates:** α = P(reject H₀ | H₀ true) = Type I; β = P(fail to reject | Hα true) = Type II; **power = 1 − β** (conventionally 80%). Smaller α or higher power ⇒ larger n. → developed in **§4**.

### A.2 Policy & ethics
Four questions before running on people: **(1) Risk** — does participation exceed minimal risk? **(2) Benefit** — what's the upside, and who gets it? **(3) Alternatives** — what choices do participants have? **(4) Data sensitivity** — is the data sensitive (health, finance), and how is identity protected? Data classes by linkability: **identified → pseudonymous → anonymous → anonymized**.

### A.3 Choosing & characterizing metrics
- **Invariant (sanity) metrics** — should *not* differ across arms (population counts, the 50/50 split ratio, anything upstream of the change); used for sanity checks, not for measuring the effect. → **§6**.
- **Evaluation metrics** — the high-level business metric(s) plus detailed metrics, combined into an **OEC**. → **§2**, **§17.4**.
- **Build metrics from the funnel** — each step suggests a candidate; for each, *define* (high-level) → *specify* (exact formula) → *summarize* (sum / mean / median / percentile / rate / probability / ratio).
- **Sensitivity & robustness** — a good metric *moves when it should* (sensitive) and *is stable to irrelevant changes* (robust); validate with A/A tests and retrospective analysis.
- **Variance — analytic vs empirical.** Analytic variance (e.g. binomial `p(1−p)/n`) is only valid when the **unit of analysis = unit of diversion**. When they differ, analytic variance *under*-estimates the spread → measure it **empirically** (A/A test or bootstrap). → **§3**, **§6.1**.
- **A/A test** — same treatment in both arms; you should see no significant difference. Validates the pipeline, estimates real variability, and yields an **empirical CI**. → **§6.1**.

### A.4 Designing an experiment
- **Unit of diversion** — how users are assigned: **user-ID** (stable, cross-device, needs login), **anonymous cookie** (per browser/device), **event** (re-randomizes each event; for non-user-visible changes), **device-ID** (mobile), **IP** (coarse). The choice sets exposure consistency, variability, and ethics.
- **Unit of analysis vs unit of diversion** — if the analysis unit is finer than the diversion unit, observations correlate and true variance > analytic ⇒ use empirical variance. → **§3**.
- **Population & cohort** — who's eligible (targeting), and when to use a **cohort** (users present before *and* during) instead of the whole population — needed for learning effects or retention.
- **Learning effects** — **change aversion** (early dip) and **novelty** (early spike) both fade; run longer and/or use a cohort. → **§8.3**.
- **Sizing** — trade % traffic × duration × exposed fraction against risk; add pre-/post-periods for monitoring. → **§4**.

### A.5 Analyzing results
- **Sanity checks first.** Verify invariant metrics and the **group-size ratio** (expected 0.5; build a binomial CI around the observed split — this is **SRM**). If a check fails, *stop and debug* — don't read the result. → **§6.2**.
- **Single metric** — compute the difference `d̂` and its CI; it ships only if the CI clears **both** 0 (statistical significance) and `d_min` (practical significance). → **§8.5**.
- **Sign test** — a non-parametric cross-check (e.g. did the metric improve on most days?); agreement with the effect-size test builds confidence.
- **Simpson's paradox** — an aggregate effect can reverse within every subgroup; check segment-level. → **§8.4**.
- **Multiple comparisons** — more metrics ⇒ more false positives. **Bonferroni** (`α/m`; conservative, controls FWER) vs **FDR** (controls the false-discovery *proportion*; better for many metrics). → **§8.2**.
- **Launch decision** — statistically *and* practically significant, sanity checks pass, effect worth the cost/risk. → **§8.5**, **§12**.

### A.6 Formula quick-card

| Quantity | Formula |
|---|---|
| SE of one proportion | `√[p(1−p)/n]` |
| Normal-approx validity | `n·p > 5` and `n·(1−p) > 5` |
| 95% CI | `p̂ ± 1.96·SE` |
| Pooled SE (two proportions) | `√[ p̄(1−p̄)·(1/n_c + 1/n_e) ]`,  `p̄ = (x_c+x_e)/(n_c+n_e)` |
| Significance of a difference | CI of `d̂ = p_e − p_c` excludes 0 **and** exceeds `d_min` |
| Power / α conventions | power `= 1−β` (80%),  α (5%) |
| Bonferroni correction | test each of m metrics at `α/m` |

Worked numbers from the course's two-proportion test + a sample-size calc (verified output):

```python
import math
# Two-proportion CTP test (control vs experiment)
x_c, n_c = 974, 10072
x_e, n_e = 1242, 9886
p_c, p_e = x_c/n_c, x_e/n_e
p_pool = (x_c + x_e)/(n_c + n_e)
se = math.sqrt(p_pool*(1-p_pool)*(1/n_c + 1/n_e))    # pooled SE
d  = p_e - p_c                                        # +0.0289
ci = (d - 1.96*se, d + 1.96*se)                       # (+0.0202, +0.0376) → excludes 0

# Sample size PER ARM to detect d_min at alpha=5% (two-sided), power=80%
def sample_size(p, d_min, z_a=1.960, z_b=0.8416):
    return math.ceil(((z_a + z_b)**2 * 2*p*(1-p)) / d_min**2)
sample_size(0.10, 0.02)     # → 3533 users per arm
```

```
p_control=0.0967  p_exp=0.1256  diff=+0.0289
pooled SE=0.00445  95% CI=(+0.0202, +0.0376)  → significant
baseline p=0.10, MDE=0.02 → ~3,533 users per arm
```

### A.7 How the course maps onto this playbook

| Udacity module | Deepened here |
|---|---|
| Metrics, OEC, funnels | **§2**, **§17.4** |
| Variance: analytic vs empirical, bootstrap | **§3**, **§6.1**, **§15.4** |
| Sample size, power, MDE | **§4** |
| Unit of diversion vs analysis | **§3** |
| A/A tests, SRM, sanity checks | **§6** |
| Multiple comparisons (Bonferroni / FDR) | **§8.2** |
| Simpson's paradox | **§8.4** |
| Novelty / change aversion | **§8.3** |
| Launch decision | **§8.5**, **§12** |

*Use this appendix to warm up; use the numbered sections to go from "I know the definitions" to "I can defend the design under interrogation."*

---

## 18. Related notes

- companion causal-inference notes — DiD / RDD / IV / synthetic control / DML / uplift / sensitivity analysis.
- companion time-series notes — walk-forward validation, look-ahead bias, drift monitoring (parallels novelty/holdback discipline).
- [`examples/experiment-design.md`](case-walkthroughs/experiment-design.md) — the shorter case-walkthrough version of A/B design (use this for the interview answer; this file for the playbook depth).
- [`examples/experimentation-platform-design.md`](case-walkthroughs/experimentation-platform-design.md) — the LinkedIn "design a platform" system-design case walkthrough.
- companion metric-diagnosis notes — what to do when a metric *moved* and you have to investigate, not run an experiment.
- a companion hypothesis-testing reference — the hypothesis-test decision framework behind §8.6: means / proportions / variances / distributions, assumption violations, and the non-parametric test directory (Appendix A).
- a companion DOE reference — DOE depth behind §11: $2^k$ factorial effect estimation, ANOVA, blocking, confounding / aliasing, fractional designs.
