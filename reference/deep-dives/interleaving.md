# Deep dive: Interleaving for ranker experiments

> Expands **[§15.3](../ab-testing-playbook.md#153-interleaving--the-deep-dive-on-ranker-experiments)** — the classical algorithms, the preference test, fidelity gotchas, and the two-stage interleaving→A/B architecture.

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


---
*Back to playbook: [§15 Frontier techniques](../ab-testing-playbook.md#15-frontier-techniques--the-netflix-style-staff-angle) · [deep-dive index](README.md)*
