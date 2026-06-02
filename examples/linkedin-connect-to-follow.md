# Example — LinkedIn replaces Connect with Follow on suggested-connection cards

A worked illustration where the dominant design concern is **network interference** — Connect creates a bidirectional graph edge (mutual visibility, both can see each other's posts); Follow is unidirectional (asymmetric content distribution). Changing one to the other affects the *graph* of every user on the platform, which means user-level A/B isn't valid — treatment users behave differently *and* their connections (in control) see different content as a result. This is the canonical case for cluster randomization at the network-community level.

> **Note on provenance.** The first-pass plan follows the same structure the skill produces; produced directly using SKILL.md + the loaded playbook. The depth-pass tightens network-effect subtleties.

---

## The prompt

```
/ab-test-plan LinkedIn is considering replacing the "Connect"
button on suggested-connection cards (My Network → People You
May Know, search results, profile page) with a "Follow" button.
Connect is bidirectional (mutual accept; both can see each other's
posts), Follow is unidirectional (one-way; follower sees followee's
posts but not vice versa). Goal is to lower friction for content
distribution (followers don't require acceptance) while preserving
the professional-network value (recruiters want to see who's
connected to whom). Assumptions: change is on the suggested-card
button only; existing Connect functionality stays; subscription
tiers are Free / Premium / Sales Nav / Recruiter / Learning. Plan
the experiment.
```

**Why this problem is a good illustration:**
- Network effects are the dominant design constraint — user-level A/B is *structurally biased*
- Multi-sided platform — members, recruiters, content creators each affected differently
- Long-term graph-structure effects can't be observed in a 4-week test
- The skill must reach for §7 (interference) and §16.2 (network interference detection)
- LinkedIn has published on this specifically (Saint-Jacques 2017, Karrer 2021) — the skill cites those

---

## First pass

### 1. Problem framing

- **Decision the experiment informs:** Whether to replace Connect with Follow as the default button on suggested-connection cards (Connect remains available elsewhere). If yes, on which surfaces and for which subscription tiers.
- **Pre-committed decision rubric:** Launch iff composite OEC moves ≥ +1.5pp AND content-engagement-per-member doesn't degrade by ≥ 1% AND Recruiter pipeline metrics (mutual-Connect-based search) don't degrade by ≥ 2% AND new-member 30-day retention doesn't degrade by ≥ 0.5pp. Auto-shutoff iff Recruiter API call success rate drops > 5% with $p < 0.005$.
- **Is A/B the right tool?** **Yes, but user-level A/B is biased.** Per §7, this is a **network-interference problem**: treatment users follow more people → control users (who are network-neighbors of treatment users) see different content distribution → control's behavior is contaminated. The right design is **cluster randomization at the network-community level** per §7.1, with **ego-cluster analysis** per §16.2 to bound the interference. Validate with a small switchback or geo-pilot first per §7.2 sanity check.

### 2. Hypothesis

- **Direction:** Follow reduces friction → users initiate more connections (follow actions) per session → information flow up; mutual-Connect formation down → graph density up but mutual-edge density down → recruiter functionality degraded; content engagement (likes, comments) up due to expanded follow graph.
- **Magnitude:**
  - **Follow / Connect initiation rate on suggested cards:** +30 to +60% (mechanical — friction removed)
  - **Mutual Connect formation:** **−20 to −40%** (substitution to Follow)
  - **Content feed engagement per session:** +3 to +8% (more content from more sources)
  - **Recruiter Search "mutual connection" filter usage:** −15 to −30% (smaller mutual-connection graph per user)
  - **New-member 30-day retention:** ±0.3pp (probably flat — early experience friction reduced but social validation from mutual Connect reduced)
- **Mechanism:** Connect's bidirectional acceptance is a friction point; removing it accelerates content-graph growth. But Connect serves a separate purpose (professional vouching) that Follow doesn't replace. The hypothesis is that the content-distribution win dominates the vouching loss.

### 3. Metric hierarchy

- **Goal metric:** Daily Active Members × engagement-per-DAU × Premium / Recruiter retention rate.
- **OEC (combined, weights pre-committed):**

$$
\text{OEC} = 0.4 \cdot \Delta(\text{content\_engagement\_per\_member}) + 0.3 \cdot \Delta(\text{follow/connect\_initiation}) - 0.2 \cdot \Delta(\text{recruiter\_search\_value}) - 0.1 \cdot \Delta(\text{new\_member\_retention})
$$

Combines multi-sided market dynamics per §2.3.

- **Guardrails (FWER at $\alpha = 0.005$, Holm-Bonferroni per §8.2):**
  - **Recruiter Search response rate** (mutual-connection-based searches degrade with smaller mutual graph)
  - **Premium subscription retention** (Premium users use Connect for vouching)
  - **Misuse / spam reporting rate** (Follow lowers friction → easier abuse)
  - **Sales Navigator value-realized metric** (Sales Nav uses Connect for warm-intros)
- **Counter metric:** **Mutual Connect formation rate** — the cannibalization. If Follow purely substitutes for Connect, total social graph activity may not grow.
- **Debug metrics:** ratio of Follow to Connect among new actions, content-engagement decomposition by source (1st-degree connections vs follows), recruiter-side mutual-connection-graph density per profile, time-from-cards-view to first action.
- **Gameability check (per §2.2):** "follow initiation rate" gameable by making the button more prominent. Lock the UI per arm (Connect arm = Connect button; Follow arm = Follow button); don't change anything else.

### 4. Randomization

- **Unit:** **Network community** (graph cluster from Louvain or METIS partition on the bidirectional connection graph). Each community gets all-Follow or all-Connect treatment uniformly.
- **Stratification:** By cluster size (small / medium / large communities have different elasticity); by tier composition (Premium-heavy vs Free-heavy communities); by industry (tech / finance / healthcare have different network norms).
- **Targeting / eligibility:** All eligible LinkedIn members. **SSRM trap (per §3):** if Follow changes how often a user visits the suggested-cards surface, the cohort eligible for the "ever saw a card" analysis is itself differential. Fix the analysis cohort at pre-experiment snapshot.
- **SUTVA check:** **Violated at the user level** per §7. Within a cluster, all members get the same treatment → SUTVA holds at the cluster level. **Across-cluster contamination:** members frequently span multiple communities (a tech-startup founder may be in both "tech" and "VC" clusters) — partial spillover unavoidable.
- **If SUTVA violated:** **Cluster randomization** per §7.1 with **ego-cluster diagnostic** per §16.2 to quantify residual spillover.

### 5. Sample size & duration

- **Baseline variance:** $\sigma^2(\text{content\_engagement\_per\_member})$ at the cluster level ≈ 30%² (cluster-level variance is high because clusters differ in baseline behavior).
- **MDE:** 1.5% relative on the OEC.
- **Cluster-level $n$:** $16 \cdot 0.09 / (0.015)^2 = 64{,}000$ member-equivalents per arm. With clusters of average 5,000 members → ~13 clusters per arm. **This is the binding constraint — too few clusters for reliable inference.**
- **Realistic cluster design:** ~200 communities (100 per arm), each ~5,000–20,000 members → ~700M total member exposure. Cluster-robust SEs with N=100 clusters per arm are reliable.
- **Variance reduction (per §5):** **Pre-period CUPED at the cluster level** with prior-30-day cluster-aggregate engagement metrics. Expected $\rho \approx 0.7$ → 51% reduction. **Effective cluster $n \approx 50$ per arm**.
- **Duration:** **8 weeks minimum** because graph-structure effects take weeks to propagate. Week 1–2 button-click behavior change; week 3–8 second-order effects through feed.
- **Ramp protocol:** week 1 small pilot (5 clusters in tech industry — homogeneous, low risk), weeks 2–8 scale to 200 clusters.

### 6. Trustworthy execution

- **A/A test:** 2-week cluster-level A/A on 20 clusters (10 / 10); verify cluster-level metric variance and check no spurious cluster-level differences.
- **SRM analog:** verify the cluster-assignment service correctly serves the right button to all members of a given cluster (cluster membership is in flux as users connect / disconnect; pre-experiment freeze of cluster membership for the duration).
- **Pre-period sanity:** PSI on cluster-level covariates (size, industry mix, tier mix, baseline engagement) between treatment and control clusters; require < 0.1.
- **Logging audit:** verify Connect-button vs Follow-button impressions and click events are correctly attributed per cluster.

### 7. Interference & spillover (the critical section)

- **Type of interference:** **Network** — members of treatment cluster create follow / connect edges into control clusters → feed content propagates → control members see content they wouldn't otherwise.
- **Mitigation design (per §7.1, §16.2):**
  - **Primary:** Louvain cluster partition with average cluster size ~5–20k members; cluster-level treatment assignment.
  - **Ego-cluster diagnostic per §16.2:** for each user, define "1-hop exposure" as the fraction of their 1st-degree connections in the treatment arm. Stratify analysis by exposure tier (low / medium / high). If outcomes differ by exposure, residual spillover is non-zero and the cluster design is leaky.
  - **Validate cluster quality:** modularity of the Louvain partition should be > 0.4 (well-separated communities). If lower, increase cluster granularity.
- **Inference adjustment:**
  - **Cluster-robust SEs at the community level** (N=100 per arm; clean asymptotics)
  - **For ego-cluster strata:** stratified analysis with weighting; report the **per-stratum effect plus the overall**
  - **Spillover bound:** the Karrer-Saint-Jacques bound per §16.2 — under reasonable assumptions, residual spillover ≤ 10% of estimated effect

### 8. Decision rubric (pre-committed)

The launch quadrant per §8.5:

- **Launch iff:** OEC ≥ +1.5pp AND content engagement ≥ baseline − 1% AND Recruiter Search value ≥ baseline − 2% AND new-member retention ≥ baseline − 0.5pp AND no SRM AND ego-cluster spillover residual < 10%.
- **Auto-shutoff iff:** Recruiter API success rate drops > 5% with $p < 0.005$ OR Sales Navigator value-realized drops > 3% at $p < 0.005$.
- **Multiple-testing protocol (per §8.2):** primary OEC at $\alpha = 0.05$; Recruiter + Premium guardrails at $\alpha = 0.005$ FWER; secondary tier-level drivers at BH within tier.
- **Per-tier subgroup decision:** if Free/Premium shows positive but Recruiter shows negative, **ship per-tier** rather than globally. Recruiter users may need to keep Connect-prominent UI.

### 9. Long-term measurement

- **Holdback:** **15% of clusters** stay on Connect for 12 months. Required because graph-structure effects compound over months; user behavior and recruiter pipeline take quarters to stabilize.
- **Long-term metrics:** Premium / Recruiter retention by month, 90-day content-engagement trend, recruiter-funded-product (Talent Solutions, Sales Nav) revenue per Recruiter, mutual-connection graph density.
- **Reverse experiment (per §8.3):** at month 9, switch 10% of launched clusters back to Connect for 4 weeks. Validates steady-state — has the graph structure adapted to Follow?
- **Novelty / primacy mitigation:** plot OEC over time; cohort users by first-Follow-introduction date; new members joining after launch (who never saw Connect on suggested cards) as the steady-state benchmark.

### 10. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Cluster spillover** from cross-community members | **High** — fundamental cluster-design risk per §7 | Ego-cluster diagnostic per §16.2; stratify analysis by exposure tier; report spillover bound |
| Recruiter pipeline degradation (mutual-Connect-based search shrinks) | High | Recruiter Search value guardrail at $\alpha = 0.005$; per-tier subgroup analysis; willingness to ship per-tier |
| Premium-tier value erosion (vouching is part of Premium identity) | Medium | Premium retention guardrail; qualitative Premium-user research |
| Spam / misuse rises (Follow lowers friction) | Medium | Spam reporting + connection-decline rate as $\alpha = 0.005$ guardrail |
| **Long-term graph structure changes** (Follow-only ecosystem looks like Twitter not LinkedIn) | Medium-high over months | 15% cluster holdback for 12 months; reverse experiment at month 9; brand / mission review at month 6 |
| Cluster quality varies (some clusters more porous than others) | High | Louvain modularity > 0.4 requirement; per-cluster modularity reported; sensitivity to alternative partitions (METIS, Infomap) |
| Cross-experiment interaction with concurrent suggested-cards experiments | High | Mutual exclusion within suggested-cards UI layer per §15.6 |

### First-pass summary

LinkedIn Connect → Follow is best executed as a **cluster-randomized experiment at the network-community level** (~200 Louvain clusters, ~100 per arm, ~5–20k members each), with **ego-cluster diagnostic per §16.2 to quantify residual spillover**. Combined OEC = 0.4 content engagement + 0.3 follow initiation − 0.2 recruiter value − 0.1 new-member retention; weights pre-committed. 8-week duration (graph-structure effects take weeks to propagate); cluster-robust SEs at community level; 15% cluster holdback for 12 months. Per-tier breakouts mandatory — if Recruiter degrades but Free/Premium lifts, ship per-tier not globally. Dominant risks: cluster spillover (mitigated by ego-cluster strata + spillover bound), Recruiter pipeline degradation (tight-$\alpha$ guardrail), long-term graph-structure drift (12-month holdback + reverse experiment at month 9).

---

## Depth pass — senior iteration

### A. Cluster definition is the critical methodological choice

The first pass said "Louvain partition." A senior would push further:

1. **Multi-partition sensitivity.** Run the analysis under Louvain AND METIS AND Infomap. If effect estimates differ by > 30% across partitions, the cluster design is fragile. Worth re-running with finer (more clusters, more variance) or coarser (fewer clusters, more cohesion) granularity.
2. **Cluster definition should be based on engagement graph, not connection graph.** The bidirectional Connect graph is the most relevant graph but **engagement** (who likes whose posts) is what actually flows. The right cluster is on the engagement subgraph.
3. **Industry-specific cluster behavior.** Tech clusters are denser than government / academic clusters; the same partition algorithm yields different cluster qualities. Validate per-industry.

### B. Beyond ego-cluster — exposure mapping

The first pass cited "ego-cluster diagnostic." The general framework (Aronow-Samii 2017, cited in §16.2) is **exposure mapping**:

- Define each user's "exposure" as a function of their direct + indirect treatment exposure
- Stratify the analysis by exposure level
- Estimate the **direct effect** (effect of own assignment) and **spillover effect** (effect of neighbors' assignment) separately

This is more rigorous than ego-cluster strata for quantifying spillover, though more complex to implement at LinkedIn scale.

### C. Recruiter pipeline — separate measurement, not just a guardrail

The first pass treats Recruiter as a guardrail. In practice, **Recruiter is a separate revenue line and a separate product**; its measurement should be its own experiment:

1. **Recruiter-side ego experiment:** sample 1,000 Recruiter users, measure their pipeline funnel over the 8 weeks before and after their network's exposure to Follow.
2. **Talent Solutions revenue:** separately tracked. If shipping per-tier (Recruiter keeps Connect; everyone else gets Follow), tracking Talent Solutions revenue trajectory under that hybrid is a multi-quarter post-launch project, not part of this experiment.

### D. The Twitter-LinkedIn convergence question

The strategic question this experiment ultimately asks: **does LinkedIn want to be Twitter (Follow-only, asymmetric)?** A staff DS should surface this:

- Twitter / X has a Follow-only graph. Result: highly asymmetric content distribution; creator economy emerges; commodified content.
- LinkedIn's mission is "connecting the world's professionals to make them more productive and successful." Mutual Connect is the **professional vouching** primitive that distinguishes LinkedIn from Twitter.
- This experiment changes the default, but **if the experiment ships and Recruiter still works**, the platform is moving toward Twitter-like dynamics over years.
- A senior plan would include a **strategy review checkpoint at month 6** — has the network become more asymmetric? Is that the company's direction?

### E. Multi-tier rollout discipline

The first pass said "ship per-tier." Operationalized:

| Tier | Likely effect | Decision |
|---|---|---|
| Free | Net positive (more content, lower friction) | Default ship |
| Premium | Mixed (vouching value lost, content gained) | Ship iff Premium retention stays flat |
| Sales Navigator | Negative (warm-intro dependency) | Default keep Connect |
| Recruiter | Negative (mutual-search dependency) | Default keep Connect |
| Learning | Neutral | Ship along with Free |

The per-tier matrix should be pre-committed and the per-tier statistical tests pre-registered.

---

## Final consolidated summary

LinkedIn Connect → Follow is a network-interference problem where user-level A/B is structurally invalid. **Cluster-randomized experiment at the network-community level** with 200 Louvain clusters (validated against METIS / Infomap for partition sensitivity), 100 per arm, ~5–20k members each. **Ego-cluster diagnostic + exposure mapping** per Aronow-Samii to quantify residual spillover. 8-week duration; cluster-robust SEs; 15% cluster holdback for 12 months. **Per-tier ship decision** pre-committed (Free / Learning ship by default; Premium iff retention flat; Sales Nav and Recruiter default keep Connect). Recruiter pipeline gets a separate ego experiment, not just a guardrail. **Strategic review at month 6** on whether the graph-structure drift toward Twitter-like asymmetric content distribution aligns with company direction. Launch iff composite OEC ≥ +1.5pp AND all per-tier guardrails clean AND spillover bound under 10%.

---

## Key takeaways from this example

1. **User-level A/B is structurally invalid for network changes.** The skill must reach for cluster randomization per §7 and acknowledge §16.2's ego-cluster framework.
2. **Cluster definition matters more than algorithm choice.** Louvain vs METIS vs Infomap can produce 30%-different effect estimates; multi-partition sensitivity is the staff move.
3. **Ego-cluster strata bound spillover.** Stratify analysis by neighbor-exposure level; report the spillover bound.
4. **Multi-sided market = per-tier ship.** Free / Premium / Recruiter / Sales Nav have different dependencies on Connect's bidirectional graph; pre-commit per-tier ship decisions.
5. **The strategic question matters.** Connect-to-Follow is functionally a Twitter-vs-LinkedIn graph question; a 6-month strategy checkpoint sits above the experiment's tactical OEC.
