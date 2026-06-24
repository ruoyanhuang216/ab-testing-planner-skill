# Deep dive: Network / social-graph randomization

> Expands **[§7 Interference, SUTVA, and two-sided markets](../ab-testing-playbook.md#7-interference-sutva-and-two-sided-markets)** (the social-network case + §7.1 ego-network design) and **[§16.2 Network interference detection at scale — ego clusters](../ab-testing-playbook.md#162-network-interference-detection-at-scale--ego-clusters)**. Same coarse-randomize / fine-analyze tension as [geo randomization](geo-randomization.md), but the spillover travels along **graph edges** (friendships, follows, messages) instead of a shared supply pool — which changes both the *design* (how you cut the graph) and the *estimand* (you now care about direct **and** spillover effects).

---

## 1. The change we're testing

A social product tests a **one-tap reshare** that makes it easier to push a post into friends' feeds. Hypothesis: more resharing → more content in feeds → **higher sessions/user and content created/user**.

Analysis unit = **user**. But the treatment's whole mechanism is *social*, so individual randomization breaks.

---

## 2. Why individual randomization fails — and what it silently estimates

When a **treated** user reshares more, their **friends see more content** — including friends assigned to **control**. So:

- **Control is contaminated upward.** Control users near treated users behave more like treated users → the treatment–control gap **shrinks** → you **underestimate** the effect (attenuation toward zero). Spillover can even flip a guardrail's sign.
- **You're not measuring the launch quantity.** A launch ships to *everyone*. The number you need is the **global average treatment effect (GATE)** — outcomes in a world where 100% are treated vs 0%. Individual randomization at, say, 50% treated measures a **diluted partial-exposure** effect, not the GATE.

```
Individual split (leaks)                 Graph-cluster split (contains)
  T ──edge──► C   (control sees          ┌── cluster A (all T) ──┐  ┌── cluster B (all C) ──┐
  T ──edge──► C    treated content)      │  T─T─T  most edges    │  │  C─C─C internal       │
  C ──edge──► T                          │  internal            │  │                        │
   ⇒ T−C attenuated, ≠ GATE              └── few edges cut ─────►└── leak only on cut edges ─┘
```

---

## 3. The estimands you must separate

Under interference, the single "ATE" splits into three quantities (via an **exposure mapping**, Aronow–Samii 2017 — outcomes depend on your *own* treatment **and** your neighbors'):

| Estimand | Question | How to get it |
|---|---|---|
| **Direct effect** | effect of *my* treatment, holding neighbors fixed | within-cluster T vs C at a fixed saturation |
| **Spillover (indirect)** | effect of my *neighbors'* treatment on me | compare across saturations / exposure strata |
| **GATE (total / global)** | everyone treated vs nobody — *the launch number* | extrapolate direct + spillover to 100% saturation |

A clean working model is **linear-in-fraction-treated**:

$$Y_i=\alpha+\underbrace{\beta}_{\text{direct}}Z_i+\underbrace{\gamma}_{\text{spillover}}\,\bar Z_{\mathcal N(i)}+\varepsilon_i$$

where $Z_i$ is own treatment and $\bar Z_{\mathcal N(i)}$ is the fraction of $i$'s neighbors treated. Then $\textbf{GATE}\approx\beta+\gamma$ (set $Z_i=1,\ \bar Z=1$), while a naive individual A/B at 50% saturation recovers only $\approx\beta+\tfrac12\gamma$ — biased unless $\gamma=0$.

---

## 4. Detecting interference before you trust a result

Cheap diagnostics that flag spillover (LinkedIn-style, §16.2):

1. **Treated-friends gradient.** Among treated users, split by *number/fraction of treated friends* and check if outcomes trend. A slope ⇒ interference (assuming friend-correlation isn't itself confounded).
2. **Exposure stratification.** Bucket users by exposure ($\bar Z_{\mathcal N(i)}$) and compare strata — the Aronow–Samii formalization of the above.
3. **Two-randomization A/A.** Compare individual-randomized vs cluster-randomized estimates of the *same* feature; a gap quantifies the interference bias.

---

## 5. Designs that contain network spillover

| Design | Mechanism | Cost / knob |
|---|---|---|
| **Graph cluster randomization** | Partition the graph into communities (**Louvain / METIS**), randomize whole clusters | Cross-cluster edges still leak; few clusters → variance |
| **Ego-cluster randomization** | Treat a focal "ego" + its 1-hop neighbors as a unit | Egos overlap → must dedupe; partial containment |
| **Saturation / two-stage (Hudgens–Halloran)** | Assign clusters to a saturation level $\pi\in\{25\%,50\%,75\%\}$, then randomize individuals within at rate $\pi$ | Best for *measuring* spillover; more complex |

**The central knob — the edge-cut fraction.** Cluster quality is governed by

$$\phi=\frac{\#\text{edges crossing clusters}}{\#\text{total edges}}.$$

Leakage is roughly proportional to $\phi$. Louvain/METIS exist precisely to **minimize $\phi$ subject to balanced cluster sizes**. This is the design's defining **bias–variance tradeoff**:

- **Bigger / coarser clusters →** fewer edges cut → **less bias** (less leakage), but **fewer clusters → higher variance**, lower power.
- **Smaller / finer clusters →** more clusters → **more power**, but more cut edges → **more bias**.

> Same lesson as geo: your **effective sample size is the number of clusters**, not users ($\text{DEFF}=1+(m-1)\rho$, $n_\text{eff}\!\to\!G/\rho$; see [unit-of-analysis](unit-of-analysis.md)). Communities are large, so you typically have *few* clusters — power is the binding constraint.

**Saturation designs are how you actually get the GATE.** By running clusters at several saturations and fitting the §3 model, you trace the **dose–response of spillover** and extrapolate to $\pi=1$ — recovering direct, spillover, and total effects instead of one diluted blend.

---

## 6. Analysis

1. **Analyze at the cluster level** (or with cluster as the unit of inference) — the randomization unit, exactly as in [geo §5](geo-randomization.md).
2. **Estimate direct + spillover** by regressing outcomes on own-treatment and neighbor-exposure (§3 model); for design-based rigor use **Horvitz–Thompson / IPW** estimators weighting by each unit's exposure probability.
3. **Get valid p-values with few clusters** via **randomization (permutation) inference** or **wild cluster bootstrap** — never trust asymptotic cluster-robust SEs when $G$ is small (same caveat as geo).
4. **Report the GATE** for the launch decision, with direct/spillover as the mechanism story.

```python
import statsmodels.formula.api as smf
import networkx as nx
from networkx.algorithms.community import louvain_communities

# 1. Partition the graph and randomize whole communities
comms = louvain_communities(G, seed=0)              # minimize edge-cut, balanced
cluster_of = {u: c for c, nodes in enumerate(comms) for u in nodes}
# assign each cluster (not user) to treatment → df.Z (own), df.cluster

# 2. Neighbor exposure: fraction of each user's friends that are treated
df["exposure"] = [ np.mean([df.Z[v] for v in G.neighbors(u)]) for u in df.user ]

# 3. Direct (Z) + spillover (exposure), SEs clustered on the randomization unit
m = smf.ols("y ~ Z + exposure", data=df).fit(
        cov_type="cluster", cov_kwds={"groups": df["cluster"]})
gate = m.params["Z"] + m.params["exposure"]         # extrapolate to full saturation
# p-value: prefer randomization inference over the cluster SE when #clusters is small
```

---

## 7. What I'd actually recommend

1. **Design:** graph cluster randomization via Louvain, choosing cluster granularity to push edge-cut $\phi$ low while keeping enough clusters for power; add a **saturation arm** if measuring spillover magnitude matters for the decision.
2. **Primary estimand:** the **GATE** (launch number), with direct vs spillover decomposed as the mechanism.
3. **Inference:** cluster-level, **randomization inference** for p-values.
4. **Pre-launch:** run the treated-friends-gradient diagnostic to confirm whether interference is even material — if $\gamma\approx0$, a plain individual A/B is fine and far cheaper.

---

## 8. Pitfalls specific to this design

- **Edge-cut leakage** — residual contamination on cross-cluster edges; report $\phi$ and treat it as a bias bound.
- **Few clusters** — the recurring trap: huge user counts hide a tiny effective $n$; never quote normal-theory SEs.
- **Unstable / overlapping communities** — the graph changes over time and egos overlap; freeze the partition pre-experiment and dedupe egos.
- **Heavy-tailed degree** — a few super-connected hubs dominate both exposure and variance; consider capping or stratifying by degree.
- **Extrapolation risk** — GATE from a linear saturation model assumes the dose–response is linear; validate with ≥3 saturation levels.

---

## 9. Interview soundbites

- "On a social graph, individual randomization leaks across friendship edges — control near treated users drifts toward treated behavior, so the A/B **attenuates** the effect and doesn't even estimate the launch quantity."
- "The launch number is the **GATE** — everyone-treated vs nobody. I separate **direct** and **spillover** effects via an exposure mapping; a 50%-saturation A/B only gives $\beta+\tfrac12\gamma$."
- "I randomize **graph clusters** (Louvain/METIS) to internalize edges; the design knob is the **edge-cut fraction** $\phi$ — lower $\phi$ means less bias, but coarser clusters mean fewer effective units and less power."
- "To actually measure spillover I use a **saturation / two-stage design** and extrapolate the dose–response to full saturation. Inference is cluster-level with randomization inference, because #clusters is small."

---

*Back to playbook: [§7 Interference & two-sided markets](../ab-testing-playbook.md#7-interference-sutva-and-two-sided-markets) · [§16.2 Network interference detection](../ab-testing-playbook.md#162-network-interference-detection-at-scale--ego-clusters) · [deep-dive index](README.md)*
