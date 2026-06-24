# Deep dive: Multiple hypothesis testing — FWER vs FDR

> Expands **[§8.2](../ab-testing-playbook.md#82-multiple-hypothesis-testing--fwer-vs-fdr)** — the full FWER (Bonferroni/Holm) vs FDR (Benjamini-Hochberg) treatment and the hybrid production platforms actually run.

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


---
*Back to playbook: [§8.2 Multiple hypothesis testing](../ab-testing-playbook.md#82-multiple-hypothesis-testing--fwer-vs-fdr) · [deep-dive index](README.md)*
