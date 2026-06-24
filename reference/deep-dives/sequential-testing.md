# Deep dive: Anytime-valid sequential testing

> Expands **[§15.1–15.2](../ab-testing-playbook.md#151-anytime-valid-sequential-testing--the-deep-dive)** — the full mathematics, decision procedures, and deployments behind always-valid p-values and regression-adjusted sequential tests.

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


---
*Back to playbook: [§15 Frontier techniques](../ab-testing-playbook.md#15-frontier-techniques--the-netflix-style-staff-angle) · [deep-dive index](README.md)*
