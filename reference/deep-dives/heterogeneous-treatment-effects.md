# Deep dive: Heterogeneous treatment effects (CATE) in production

> Expands **[§15.5](../ab-testing-playbook.md#155-heterogeneous-treatment-effects-in-production--the-deep-dive)** — meta-learners, causal forests, CATE evaluation, policy learning, and deployment patterns.

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


---
*Back to playbook: [§15 Frontier techniques](../ab-testing-playbook.md#15-frontier-techniques--the-netflix-style-staff-angle) · [deep-dive index](README.md)*
