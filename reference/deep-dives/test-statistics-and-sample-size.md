# Deep dive: Test statistics & sample size — assumptions, derivations, and resampling

> Expands **[§4 Sample size & MDE](../ab-testing-playbook.md#4-sample-size--mde--the-math-behind-the-number)** and **[§8.6 The test toolbox](../ab-testing-playbook.md#86-the-test-toolbox--which-test-for-which-statistic)**. The playbook gives the formula and the picker table; this file derives where the formulas come from, states the assumptions behind each test, and explains when to leave parametric land entirely (regression, advanced estimators, resampling).

---

## 0. The one idea that unifies everything

Almost every frequentist test is the same ratio:

$$\text{statistic} = \frac{\text{signal (estimated effect)}}{\text{noise (standard error of the estimate)}}$$

You reject the null when this exceeds a critical value. Two error rates govern the design:

- **Type I ($\alpha$)** — reject a true null (false positive). Sets the critical value $z_{1-\alpha/2}$.
- **Type II ($\beta$)** — fail to reject a false null (false negative). **Power** $= 1-\beta$.

**Every sample-size formula is derived the same way:** place the sampling distribution under $H_0$ and under $H_1$ on the same axis, require that the rejection threshold (set by $\alpha$) sits far enough into the $H_1$ distribution to capture $1-\beta$ of its mass, and solve for $n$. That single picture (§3.1) generates all the formulas below.

---

## 1. Common test statistics and their assumptions

### 1.1 z-test (mean or proportion, variance known / large $n$)

$$z = \frac{\hat\theta - \theta_0}{\text{SE}},\qquad \text{SE}=\frac{\sigma}{\sqrt n}$$

**Assumptions:** sampling distribution of $\hat\theta$ is normal (true exactly if data normal, approximately by the **CLT** for large $n$); variance known or estimated precisely enough to treat as known. In A/B tests with $n$ in the thousands, the t- and z-tests coincide — the z form is what you actually compute.

### 1.2 Welch's two-sample t-test (means) — the A/B default

$$t = \frac{\bar x_T - \bar x_C}{\sqrt{s_T^2/n_T + s_C^2/n_C}}$$

**Assumptions:** approximate normality of the *group means* (CLT), **independent** observations, finite variance. **Does not assume equal variances** — that's why it's the default over Student's pooled t-test. Treatment often changes the variance as well as the mean, so never assume homoscedasticity for free.

### 1.3 Student's pooled t-test — and why we avoid it

Same as Welch but pools variance: $s_p^2 = \frac{(n_T-1)s_T^2+(n_C-1)s_C^2}{n_T+n_C-2}$. **Extra assumption: equal variances.** When variances differ *and* group sizes differ, the pooled test has the wrong Type-I rate. Welch is nearly as powerful when variances are equal and far safer when they aren't — there's no good reason to prefer pooled in practice.

### 1.4 Two-proportion z-test / $\chi^2$ (binary metrics)

$$z = \frac{\hat p_T - \hat p_C}{\sqrt{\hat p(1-\hat p)\left(\tfrac1{n_T}+\tfrac1{n_C}\right)}},\quad \hat p = \text{pooled rate}$$

**Assumptions:** independent Bernoulli trials, **normal approximation to the binomial** valid (rule of thumb $np\ge 10$ and $n(1-p)\ge 10$). The $\chi^2$ test of independence is algebraically equivalent ($z^2=\chi^2$). When counts are tiny, use **Fisher's exact test**. Critically: this assumes **one independent trial per unit** — if you have multiple events per user, you're in the [unit-of-analysis trap](unit-of-analysis.md).

### 1.5 Paired t-test (before/after, matched)

Run a one-sample t-test on the per-unit differences $d_i = y_i - x_i$. **Assumption:** the *differences* are approximately normal; pairing removes between-unit variance, which is the entire point (see §3.3). This is the statistical engine behind matched designs and CUPED.

### 1.6 ANOVA $F$-test (3+ arms)

$$F = \frac{\text{MS}_\text{between}}{\text{MS}_\text{within}}$$

**Assumptions:** normality within groups, **equal variances** (homoscedasticity), independence. Tests the *omnibus* null "all means equal"; a rejection doesn't say which arm differs — follow with pairwise tests under multiplicity control (§4.5). For unequal variances use **Welch's ANOVA**; non-parametric analog is **Kruskal–Wallis**.

### 1.7 Ratio metrics (orders/sessions, CTR-per-pageview)

A ratio of sums has no clean i.i.d. variance because numerator and denominator are correlated random variables. Use the **delta method** (analytic) or the **bootstrap** — both at the randomization unit. Fully derived in the [unit-of-analysis deep dive §4–§6](unit-of-analysis.md).

### 1.8 Variance / spread

To test whether the *spread* changed, the **F-test for variances is dangerously non-robust to non-normality** — use **Levene's** or **Brown–Forsythe** test (ANOVA on absolute deviations from the group center) instead.

### Assumptions at a glance

| Test | Normality | Equal variance | Independence | Other |
|---|---|---|---|---|
| z / large-$n$ t | means (CLT) | — | ✅ | variance ≈ known |
| Welch t | means (CLT) | **not** required | ✅ | finite variance |
| Pooled t | means | **required** | ✅ | |
| 2-proportion z | binomial→normal | — | ✅ | $np,\,n(1-p)\ge10$ |
| Paired t | of differences | — | pairs indep. | |
| ANOVA F | within groups | **required** | ✅ | |
| F-test (var) | **strict** | — | ✅ | avoid → Levene |

---

## 2. When to go non-parametric

Reach for non-parametric tests when the parametric assumptions fail in a way the CLT can't rescue:

- **Small $n$ + non-normal** — the CLT hasn't kicked in, so the t-test's null distribution is wrong.
- **Heavy tails / outliers** — revenue, watch-time, latency. The mean and its variance are dominated by a few points; convergence to normality is slow and CIs are unreliable.
- **Ordinal or rank data** — Likert scores, ranked preferences, where means aren't even meaningful.
- **You care about the median or a quantile**, not the mean (p95 latency) → quantile methods, [§15.4](../ab-testing-playbook.md#154-quantile-metrics-and-the-quantile-bootstrap).
- **Unknown / weird distribution** where you can't justify any parametric family.

| Goal | Non-parametric tool | Null it actually tests |
|---|---|---|
| 2 groups, "shifted?" | **Mann–Whitney U** | stochastic dominance: $P(X_T>X_C)\ne\tfrac12$ |
| paired / 1-sample | **Wilcoxon signed-rank** | symmetric shift of differences |
| 3+ groups | **Kruskal–Wallis** | at least one group dominates |
| any statistic, exact | **permutation test** | sharp null of no effect |
| any statistic, CI | **bootstrap** | (gives CI/SE, not a sharp test) |

**The staff nuance — don't reflexively abandon the mean.** At A/B-test scale ($n$ in the tens of thousands), the CLT typically rescues the *mean* even for skewed metrics. The real problem with heavy tails isn't non-normality, it's **variance**: a few whales inflate $\sigma^2$ and destroy power. The usual fix is **not** Mann–Whitney (which silently changes the estimand to "probability of dominance," which the business didn't ask about) but rather **cap / winsorize / log-transform**, or **bootstrap the mean's CI**. Use:

- **Costs of non-parametric:** it answers a *different question* (ranks, not means/revenue), and under true normality the Mann–Whitney is ~**95.5%** as efficient as the t-test (asymptotic relative efficiency $3/\pi$) — you pay ~5% more sample. Under heavy tails its efficiency can *exceed* 1, which is when it genuinely earns its place.

---

## 3. Deriving the sample-size formula for each test

### 3.1 The master derivation (two-sample mean)

Estimator $\hat\Delta=\bar x_T-\bar x_C$. With equal per-arm size $n$ and variance $\sigma^2$:

$$\text{Var}(\hat\Delta)=\frac{\sigma^2}{n}+\frac{\sigma^2}{n}=\frac{2\sigma^2}{n},\qquad \text{SE}=\sqrt{\tfrac{2\sigma^2}{n}}$$

Reject when $|\hat\Delta|/\text{SE} > z_{1-\alpha/2}$. Under the alternative $\hat\Delta\sim N(\delta,\text{SE}^2)$, so

$$
\text{Power}=P\!\left(\frac{\hat\Delta}{\text{SE}}>z_{1-\alpha/2}\right)
=1-\Phi\!\left(z_{1-\alpha/2}-\frac{\delta}{\text{SE}}\right)\stackrel{!}{=}1-\beta.
$$

That requires $\dfrac{\delta}{\text{SE}}=z_{1-\alpha/2}+z_{1-\beta}$. Substitute $\text{SE}=\sqrt{2\sigma^2/n}$ and solve:

$$\boxed{\,n=\frac{2\sigma^2\,(z_{1-\alpha/2}+z_{1-\beta})^2}{\delta^2}\ \text{per arm}\,}$$

For $\alpha=0.05,\ \beta=0.20$: $(1.96+0.84)^2\approx7.84$, giving the **$n\approx 16\sigma^2/\delta^2$** rule of thumb in §4.1.

> **The part that matters most:** $\delta$ enters **squared in the denominator**. Halving the effect you want to detect *quadruples* the sample. The $(z_{1-\alpha/2}+z_{1-\beta})^2\approx7.84$ term is fixed by your $\alpha/\beta$ conventions; $\sigma^2$ is attacked by variance reduction (§4); $\delta$ is the business's call. This is why **MDE defense** (§4.3) is the senior move — it's the lever with quadratic leverage.

### 3.2 Proportions

Plug $\sigma^2=p(1-p)$ into the variance, keeping each arm's own rate:

$$n=\frac{(z_{1-\alpha/2}+z_{1-\beta})^2\,[\,p_C(1-p_C)+p_T(1-p_T)\,]}{\delta^2}.$$

Using a pooled $\bar p$ this collapses to $n\approx \dfrac{2(z_{...})^2\,\bar p(1-\bar p)}{\delta^2}$, i.e. the $16\sigma^2/\delta^2$ form with $\sigma^2=\bar p(1-\bar p)$. **Watch the relative-vs-absolute trap:** a "5% lift" on a 2% base is $\delta=0.001$ absolute — tiny denominator, enormous $n$. (This is exactly the success-vs-driver-metric gap worked in §4.4.)

### 3.3 Paired designs and CUPED — the variance-reduction multiplier

Pairing/adjustment doesn't change $\delta$; it shrinks $\sigma^2$. For a **paired** difference with correlation $\rho$ between pre and post:

$$\text{Var}(d)=\sigma_y^2+\sigma_x^2-2\rho\sigma_x\sigma_y=2\sigma^2(1-\rho)\quad(\text{equal }\sigma).$$

So the required $n$ scales by $(1-\rho)$. **CUPED** goes one better: it subtracts the *optimal* multiple of the pre-period covariate, $Y^\text{cuped}=Y-\theta(X-\bar X)$ with $\theta=\text{Cov}(Y,X)/\text{Var}(X)$, giving

$$\text{Var}(Y^\text{cuped})=\sigma^2(1-\rho^2)\;\Rightarrow\; n^\text{cuped}=(1-\rho^2)\,n.$$

> **Highlight:** a pre-period covariate correlated $\rho=0.7$ with the outcome cuts variance by $1-0.49=51\%$ — equivalent to *doubling* traffic, for free. This is the single biggest power lever after MDE, and it's why CUPED is "the staff-level differentiator" (§5.4). Effective sample size $n_\text{eff}=n/(1-\rho^2)$.

### 3.4 Unequal allocation

With ratio $k=n_T/n_C$, the balanced-design penalty for skew is a factor $\dfrac{(1+k)^2}{4k}$ on total sample. A 90/10 split ($k=9$) costs $\approx2.8\times$ the total of a 50/50 split for the same power. **Equal allocation is optimal under equal variance**; when variances differ, **Neyman allocation** $n_T/n_C=\sigma_T/\sigma_C$ is optimal (put more traffic where the noise is). Imbalance is sometimes accepted to cap exposure to a risky treatment — just know the power cost.

### 3.5 Multiple arms / multiple comparisons

Two effects inflate $n$: (1) ANOVA's omnibus power depends on the noncentrality $\lambda=n\,f^2$ (Cohen's $f$); (2) controlling family-wise error across $c$ comparisons replaces $z_{1-\alpha/2}$ with $z_{1-\alpha/(2c)}$ (Bonferroni), which grows the $(z_{...})^2$ term — **roughly logarithmically** in $c$, so it's a mild but real tax. FWER vs FDR tradeoffs are in §8.2.

### 3.6 Clustered / ratio / geo metrics

When the analysis unit is finer than the randomization unit, multiply $n$ by the **design effect** $\text{DEFF}=1+(m-1)\rho$ (intra-cluster correlation $\rho$, cluster size $m$). For geo/marketplace designs the effective sample collapses toward the **number of clusters**, not users. Both fully derived in the [unit-of-analysis deep dive](unit-of-analysis.md).

### 3.7 Non-parametric sample size

No clean closed form. Two practical routes: (1) compute the parametric $n$ and **inflate by $1/\text{ARE}$** (≈ +5% for Mann–Whitney vs t under near-normality); (2) **simulate** — generate data under your assumed distribution and effect, run the test, repeat, and read off the empirical power. Simulation is the honest default for any non-standard estimator.

---

## 4. Regression-based evaluation

### 4.1 OLS *is* the t-test — then it does more

Regressing the outcome on a treatment indicator,

$$Y_i=\beta_0+\beta_1 T_i+\varepsilon_i,$$

gives $\hat\beta_1$ = exactly the difference in means, and its t-stat = the two-sample t-test (with robust SEs, Welch). The value of the regression frame is everything you can *add*:

### 4.2 Covariate adjustment (ANCOVA) = CUPED

Add pre-period covariates: $Y_i=\beta_0+\beta_1 T_i+\gamma^\top X_i+\varepsilon_i$. Because randomization makes $T\perp X$, $\hat\beta_1$ stays unbiased but its variance drops by $\sim(1-R^2)$, where $R^2$ is the covariates' explanatory power. This is CUPED expressed as regression, and it generalizes to many covariates at once.

### 4.3 Binary outcomes: LPM vs logistic

A **linear probability model** (OLS on a 0/1 outcome) gives the ATE directly and is usually fine for inference on the *average* effect at scale. **Logistic regression** models log-odds — better-calibrated probabilities and no out-of-range predictions, but the coefficient is an odds ratio, not the ATE (you must average marginal effects to recover it). Pick LPM when you want the risk difference, logistic when you want odds/probabilities.

### 4.4 Clustered & dependent data

Use **cluster-robust (sandwich) SEs** clustered on the randomization unit, or a **mixed-effects model** with a random intercept per cluster, when observations are nested (sessions in users, users in geos). Mechanics and the few-cluster caveat: [unit-of-analysis §5](unit-of-analysis.md).

### 4.5 Fixed effects & difference-in-differences

When you can't cleanly randomize, **two-way fixed effects / DiD** differences out time-invariant unit effects and common time shocks: $\hat\tau$ from $Y_{it}=\alpha_i+\lambda_t+\tau\,(T_i\cdot\text{Post}_t)+\varepsilon_{it}$. This is the workhorse for **geo experiments** and quasi-experiments (§9), with inference via randomization tests or wild-cluster bootstrap.

### 4.6 Heterogeneous treatment effects (CATE)

Add an interaction $T_i\times X_i$ to test whether the effect varies by segment. For high-dimensional or non-linear heterogeneity, move to **meta-learners (T/S/X-learner)** or **causal forests** (§15.5). Caveat: interaction tests are under-powered and a multiplicity minefield — pre-register the segments.

---

## 5. More advanced evaluation approaches

| Situation | Approach | Why / pointer |
|---|---|---|
| Peeking / continuous monitoring | **Sequential / always-valid tests** (mSPRT, anytime-valid CIs) | fixed-$n$ p-values are invalid under peeking → §15.1 |
| Want P(treatment better), expected loss | **Bayesian A/B** (posteriors, decision-theoretic stopping) | natural for business loss framing → §16.3 |
| Tail metrics (p95 latency) | **Quantile regression / quantile treatment effects** | the mean is the wrong estimand → §15.4 |
| Non-compliance / partial adoption | **IV / CACE** (encouragement design) | recovers the effect on compliers |
| Nested/longitudinal data | **Mixed-effects (hierarchical) models** | random effects for clusters & time |

These all share the §0 logic — estimate an effect, quantify its uncertainty — but relax an assumption (fixed $n$, frequentist priors, mean-as-estimand, full compliance, independence) that a simple t-test bakes in.

---

## 6. Statistical resampling — the toolbox

When a closed-form variance is unavailable, wrong, or hard, **let the data generate the sampling distribution**. Three resampling families, each for a different job.

### 6.1 The bootstrap — estimate a sampling distribution by resampling *with replacement*

**Idea (plug-in principle):** the empirical distribution is your best estimate of the population, so resampling from it mimics drawing fresh samples. Algorithm:

1. From your $n$ observations, draw $n$ **with replacement** → one bootstrap sample.
2. Recompute the statistic $\hat\theta^{*}$.
3. Repeat $B$ times. The spread of $\{\hat\theta^{*}\}$ estimates the sampling distribution of $\hat\theta$ → SE = its std; CI = its percentiles.

**When to bootstrap (the rules):**
- ✅ **No clean closed-form variance** — ratios, quantiles, Gini, a custom OEC, the output of a multi-step pipeline.
- ✅ **Skewed / heavy-tailed** metrics where you don't trust the normal approximation.
- ✅ **Cross-check** an analytic CI you're unsure about.
- ❌ **Closed form exists and is cheap** — don't bootstrap a simple mean for no reason.
- ❌ **Non-smooth functionals** — the sample **max/min** and extreme tail quantiles; the ordinary bootstrap is *inconsistent* here (use subsampling / extreme-value methods).
- ❌ **Tiny $n$** — with $n<\sim20$ the empirical distribution is too coarse to resample meaningfully.
- ⚠️ **Dependent data** — i.i.d. resampling destroys correlation; use the *cluster* or *block* bootstrap instead (below).

**How many resamples $B$:** $\ge 1{,}000$ for an SE; $\ge 10{,}000$ for percentile CIs and tail quantiles (you're estimating a 2.5th percentile of the bootstrap distribution, which itself needs many draws to stabilize).

**Resample at the independent unit.** If users own multiple sessions, resample **users** (drag all their sessions along) — the **cluster bootstrap**. Resampling sessions reintroduces the unit-of-analysis bug. Code and worked example: [unit-of-analysis §6](unit-of-analysis.md).

**Which CI flavor:**

| CI method | Idea | Use when |
|---|---|---|
| **Percentile** | take the 2.5 / 97.5 quantiles of $\{\hat\theta^*\}$ | quick, symmetric-ish, large $n$ |
| **Basic / pivotal** | reflect: $2\hat\theta-q_{1-\alpha/2},\,2\hat\theta-q_{\alpha/2}$ | mild bias |
| **BCa** (bias-corrected & accelerated) | adjusts percentiles for bias ($z_0$) and skew ($a$, via jackknife) | **skewed estimators — best general default** |
| **Studentized (bootstrap-t)** | bootstrap the t-ratio $(\hat\theta^*-\hat\theta)/\text{se}^*$ | best coverage, but needs an SE per replicate (nested, costly) |

### 6.2 Permutation (randomization) tests — for *p-values*

Where the bootstrap shines at CIs/SEs, permutation tests shine at **hypothesis testing**. Under the **sharp null** "treatment has no effect on anyone," the labels are exchangeable, so:

1. Pool all observations.
2. Randomly **re-assign** the treatment/control labels (respecting the original group sizes).
3. Recompute the test statistic.
4. Repeat; the **p-value = fraction of permutations at least as extreme** as observed.

Exact under exchangeability, assumption-light, and it mirrors *exactly how you randomized* — which makes it the gold standard for **few-cluster geo/switchback designs**. (Permutation tests a sharp null; the bootstrap targets a parameter — that's the conceptual divide.)

### 6.3 Jackknife — leave-one-out

Compute $\hat\theta_{(i)}$ omitting observation $i$; variance $\approx\frac{n-1}{n}\sum_i(\hat\theta_{(i)}-\bar\theta)^2$. Cheaper and deterministic, good for **smooth** statistics and for estimating the **acceleration** term in BCa. **Fails for non-smooth statistics** (e.g. the median) — prefer the bootstrap there.

### 6.4 Block / cluster / subsampling variants

- **Block bootstrap** — resample contiguous time blocks to preserve autocorrelation; essential for **switchback / time-series** designs.
- **Cluster bootstrap** — resample whole clusters; the fix for nested data ([unit-of-analysis](unit-of-analysis.md)).
- **Subsampling** ($m<n$ without replacement) — consistent even for the non-smooth functionals where the bootstrap fails.

```python
# Bootstrap CI for a ratio metric (percentile); resample the INDEPENDENT unit
import numpy as np
rng = np.random.default_rng(0)
def theta(d): return d["num"].sum() / d["den"].sum()      # e.g. orders / sessions
units = df["user_id"].unique()
by_u  = {u: g for u, g in df.groupby("user_id")}
boot  = [theta(pd.concat([by_u[u] for u in rng.choice(units, units.size, replace=True)]))
         for _ in range(10_000)]
ci = np.percentile(boot, [2.5, 97.5])

# Permutation p-value for a difference in means (sharp null)
obs = df.loc[df.t==1,"y"].mean() - df.loc[df.t==0,"y"].mean()
y, n1 = df["y"].to_numpy(), (df.t==1).sum()
null = [ (lambda s: s[:n1].mean()-s[n1:].mean())(rng.permutation(y)) for _ in range(10_000) ]
p = (np.abs(null) >= abs(obs)).mean()
```

---

## 7. Decision cheat-sheet

```
What are you comparing?
 ├─ means, 2 groups ........... Welch t  (n = 2σ²(z..)²/δ²)
 ├─ proportions ............... 2-prop z (σ² = p(1−p));  Fisher's exact if tiny
 ├─ means, 3+ groups .......... ANOVA F  (+ multiplicity control)
 ├─ before/after, matched ..... paired t (variance ×(1−ρ))
 ├─ ratio of sums ............. delta method / cluster bootstrap
 ├─ median / quantile ......... quantile bootstrap (§15.4)
 └─ whole distribution ........ KS / Anderson–Darling

Assumptions broken?
 ├─ skew/heavy tails .......... winsorize/log, or bootstrap the mean (NOT auto-MWU)
 ├─ small n + non-normal ...... non-parametric / permutation
 ├─ nested / clustered ........ cluster-robust SE / cluster bootstrap / mixed model
 ├─ peeking ................... sequential / always-valid (§15.1)
 └─ no closed-form variance ... bootstrap (B≥1k SE, ≥10k CI), BCa if skewed

Want more power without more traffic?
 └─ CUPED / covariate adjustment → variance ×(1−ρ²), n_eff = n/(1−ρ²)
```

---

## 8. Interview soundbites

- "Every sample-size formula is the same picture: push the rejection threshold set by $\alpha$ far enough into the alternative to capture $1-\beta$ of its mass. That gives $n=2\sigma^2(z_{1-\alpha/2}+z_{1-\beta})^2/\delta^2$ — and $\delta$ is squared, so it dominates."
- "Welch over pooled t by default — treatment changes variance, not just the mean."
- "I don't reflexively reach for Mann–Whitney on skewed data; the CLT usually saves the mean. I winsorize or bootstrap the mean's CI instead, because MWU silently changes the estimand to stochastic dominance."
- "CUPED cuts variance by $1-\rho^2$. A covariate correlated 0.7 with the outcome is worth doubling the traffic."
- "Bootstrap for CIs and SEs, permutation for p-values, and always resample the *randomization* unit — for skew use BCa, for the sample max use subsampling because the bootstrap is inconsistent there."

---

*Back to playbook: [§4 Sample size & MDE](../ab-testing-playbook.md#4-sample-size--mde--the-math-behind-the-number) · [§8.6 Test toolbox](../ab-testing-playbook.md#86-the-test-toolbox--which-test-for-which-statistic) · [deep-dive index](README.md)*
