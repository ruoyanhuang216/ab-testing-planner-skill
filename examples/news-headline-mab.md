# Example — News headline selection (the canonical MAB case)

A worked illustration where the skill correctly **rejects A/B testing as the right framework** and instead recommends **Thompson Sampling**. The problem has all four §10.2 ingredients for MAB: many candidate arms (8–12 headlines per story), short shelf-life (6 hours of peak traffic), high opportunity cost (each impression on a sub-optimal headline is real revenue), and repeated decisions (~50 stories/day).

> **Note on provenance.** The first-pass plan is the actual verbatim output from invoking `/ab-test-plan` on the prompt below. The depth-pass tightens the MAB-specific subtleties.

---

## The prompt

```
/ab-test-plan A digital news site (think Vox / The Verge / NYT
online news) wants to optimize headline selection for breaking
news articles. The editorial team writes 8 to 12 candidate
headlines per breaking story. Each story has a steep traffic
decay curve: roughly 80% of total views occur in the first 6
hours after publish, then traffic decays sharply. The site
publishes ~50 breaking stories per day across categories
(politics / world / business / sports / culture). Goal is to
maximize total article views and downstream subscription
conversions. We have full control over which headline is shown to
which visitor in real time. Plan the experiment.
```

**Why this problem is a good illustration:**
- Skill correctly refuses A/B and reaches for Thompson Sampling per §10
- 8–12 arms make per-arm A/B power infeasible
- 6-hour shelf-life rules out multi-week A/B
- Continuous opportunity cost makes uniform allocation expensive
- The canonical Yahoo / Reddit / Microsoft case study
- Subscription downstream signal (delayed) is a guardrail, not the bandit reward
- Clickbait drift is the Goodhart-Law risk staff candidates must surface

---

## First pass — actual skill output

> *Captured verbatim from a real `/ab-test-plan` invocation.*

### 1. Problem framing

- **Decision the experiment informs:** Which headline to show to each visitor for each breaking news article, in real time, across the article's traffic lifecycle.
- **Pre-committed decision rubric:** *Not a single launch decision* — this is a continuous optimization. The framework commits to: (a) Thompson Sampling allocates impressions; (b) at each story's 6-hour close, the **empirically best headline by posterior mean** is the "winning" headline; (c) the framework itself ships if median per-story view lift over the **uniform-allocation baseline** is ≥ +5% (validated in a 2-week A/B between "bandit-on" and "bandit-off" stories).
- **Is A/B the right tool?** **No. This is an MAB problem.** Per §10.2, this is the canonical MAB use case — many arms (8–12 headlines per story), high opportunity cost, continuous repeated decisions (50 stories/day), and short shelf-life (6 hours). User-level A/B is structurally wasteful here. The right framework is **Thompson Sampling per story**, with a meta-experiment to validate the bandit framework itself.

### 2. Hypothesis

- **Direction:** Thompson Sampling adaptive allocation per story → higher total clicks within the 6-hour window vs uniform allocation across the 8–12 candidates.
- **Magnitude (per §10.2 Yahoo / Reddit published benchmarks):**
  - **CTR gap between best and worst headline:** typically **2–5×**
  - **Lift over uniform random allocation:** **+15 to +40%** on total article views
  - **Lift over editor's single pre-launch choice:** **+5 to +15%**
  - **Subscription conversion uplift (downstream):** **+3 to +8%**
- **Mechanism:** Within the first 5–10% of impressions (5–10k views), the posterior converges enough that ~70% of remaining impressions go to the empirical leader. Total impressions on the best headline are massively higher than under uniform allocation.

### 3. Metric hierarchy

- **Goal metric:** Daily subscription conversions from organic article traffic.
- **OEC (bandit reward + composite meta-OEC):**

$$
\text{Reward}_{\text{bandit}} = \text{click\_event}
$$
$$
\text{OEC}_{\text{meta}} = 0.6 \cdot \Delta(\text{article\_views}) + 0.3 \cdot \Delta(\text{subscription\_CR}) - 0.1 \cdot \Delta(\text{bounce\_rate})
$$

Bandit reward is clicks (dense, immediate, learnable). Meta-experiment OEC weights views + subscription + bounce.

- **Guardrails (FWER at $\alpha = 0.005$, Holm-Bonferroni per §8.2):** bounce rate, time-on-page, subscription CR per article-view, brand safety / dignity score, editorial trust signal.
- **Counter metric:** **Cumulative regret** — how much we lose to suboptimal allocation.
- **Debug metrics:** per-arm posterior trajectory, time-to-convergence per story, allocation entropy, allocation correlation with editor's predicted ranking.
- **Gameability check (per §2.2):** **Clickbait drift** is the central risk. Mitigations: tight-$\alpha$ guardrails on bounce + time-on-page; editorial veto; periodic clickbait-pattern audit.

### 4. Randomization

- **Unit:** **Visitor-impression** (not visitor / not session). Each impression draws from the story's Thompson Sampling posterior. **No fixed split.**
- **Stratification:** Per-article bandit. Cross-story stratification by content category (politics / world / business / sports / culture) for the meta-experiment.
- **Targeting / eligibility:** All visitors during the first 24 hours. Returning visitors see the same headline they were originally shown.
- **SUTVA check:** Valid at impression level. Edge case: clickbait drift across stories monitored by brand-safety guardrail.
- **Contextual extension:** allocation can be conditioned on visitor features (referrer, device, geo) → **contextual Thompson Sampling**. Yahoo / Reddit / Microsoft run contextual variants in production per §10.3.

### 5. Sample size & duration

**Reframe for MAB:** the question isn't "how many users per arm" but "how fast does the bandit converge."

- **Bandit convergence per story:** Thompson Sampling with Beta-Bernoulli posteriors. With 10 arms, baseline CTR ≈ 3%, true best-vs-worst gap 2×: ~70% allocation to leader within ~5,000 impressions; ~90% within ~20,000. **Convergence is well within the 100k-view story lifecycle.**
- **Cold-start fix:** prime each arm's prior with 200 imputed pulls (Beta(6, 194) for 3% baseline) so the first 50 impressions don't have zero-inflated posteriors.
- **Meta-experiment duration (bandit-on vs bandit-off):** 2 weeks. Days 1–7 uniform baseline, days 8–14 bandit-on.
- **Sample size for meta-experiment OEC:** ~700 stories total (350 per condition). With $\sigma^2 \approx 25\%^2$ on per-story views, $n = 100$ stories per arm for 10% MDE — ample.
- **Ramp protocol:** week 1 sports + culture only; week 2 expand to politics / world / business after editorial review.

### 6. Trustworthy execution

- **A/A test:** 5 stories with all 10 arms set to identical headlines. Verify uniform convergence; CTR ±0.5pp.
- **SRM analog for MAB:** **arm-allocation diversity check** — alert if any arm gets < 1% of impressions in the first 1,000 per story.
- **Pre-launch sanity:** verify prior is reasonable; 5 dry-run shadow stories to check the assignment service.
- **Logging audit:** verify each impression's served arm is correctly attributed to the click event downstream — **single highest-impact pre-launch check** because mis-attribution destroys the bandit.

### 7. Interference & spillover

Not flagged at the impression level. Edge case: **clickbait drift across stories** — monitored by brand-safety guardrail, not modeled into bandit reward.

### 8. Decision rubric (pre-committed)

The launch quadrant applied to the **meta-experiment**, not individual stories.

- **Launch the bandit framework iff:** meta-experiment OEC ≥ +5% AND bounce rate ≥ baseline − 1pp AND subscription CR ≥ baseline − 0.2pp AND brand safety / editor trust pass.
- **Auto-shutoff per story:** if individual story bounce rate exceeds baseline + 5pp during the bandit run, that story's bandit is **frozen** and the leading headline at that moment is locked. Doesn't stop the framework.
- **Multiple-testing protocol (per §8.2):** primary OEC at $\alpha = 0.05$; bounce + subscription + brand safety at $\alpha = 0.005$ FWER.
- **Post-experiment analysis under MAB (per §10.4):** **standard t-tests are invalid** because Thompson Sampling allocation is not iid. Use **importance-weighted estimators** for per-arm effects within each story; **standard t-test on story-aggregate view counts** for the bandit-on vs bandit-off meta-experiment.

### 9. Long-term measurement

- **Holdback:** 5% of stories remain on uniform allocation permanently.
- **Long-term metrics:** 90-day subscription retention for users who landed on bandit-selected articles; aggregate bounce-rate trend; editor-trust survey at month 3.
- **Reverse experiment (per §8.3):** at month 3, switch 5% holdback to bandit-on AND switch 5% bandit-on stories to uniform. Validates steady-state — has the bandit overfit to short-term clicks?
- **Novelty / primacy mitigation:** bandit exploration handles novelty naturally; monitor **headline-style entropy** week-over-week to catch editor adaptation to bandit preferences.

### 10. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Clickbait drift** (Goodhart on CTR) | **High — dominant MAB-for-content risk** | Bounce + time-on-page guardrails at $\alpha = 0.005$; editor veto; brand-safety audit |
| Cold-start arm-starvation | High without mitigation | Prior-priming with 200 imputed pulls per arm; minimum 1% exploration floor |
| **Naive t-tests on bandit traffic** per §10.4 | High — common analyst mistake | Importance-weighted estimators; t-test on story-aggregate; document in pipeline |
| Subscription signal too delayed for bandit | Medium | Click as reward (dense); subscription as guardrail; aggregate via meta-experiment |
| Editor distrust | Medium-high | Transparent posterior dashboard; editor reviews top-3 at 6h; bandit suggests not decides for hard-news |
| Adversarial / fraudulent clicks | Medium | Bot-filter clicks before bandit reward; verify exposure attribution |
| Brand-safety failure on hard-news | Medium-high | Phase rollout: sports + culture first; politics / world / business with editorial gate |
| Bandit convergence misses tail-event headlines | Low-medium | Editor "force-promote" override for correction-notice cases |

### First-pass summary

Headline selection is **the canonical Thompson Sampling MAB case** per §10.2 — the skill correctly refuses A/B framing. Beta-Bernoulli per story with 200-pull primed priors, clicks as bandit reward, composite meta-OEC (views + subscription − bounce) for the bandit-on vs bandit-off meta-experiment (~700 stories, 2 weeks). Launch the framework iff per-story view lift ≥ +5% with bounce + subscription + brand-safety guardrails clean. Phase rollout: sports + culture first, then hard-news with editorial gate. Dominant risk: clickbait drift (Goodhart on CTR). Post-experiment analysis uses importance-weighted estimators per §10.4.

---

## Depth pass — senior iteration on MAB-specific subtleties

### A. Bandit choice — why Thompson Sampling not UCB or ε-greedy

The first pass said "Thompson Sampling" but didn't justify the choice over UCB or ε-greedy.

| Algorithm | Why it wins / loses here |
|---|---|
| **ε-greedy** | $O(K^{1/3} T^{2/3})$ regret per §10.4 — wastes exploration on known-bad arms. Bad for headlines where some are obviously weak. |
| **UCB** | Optimal $\sqrt{KT \log T}$ but **deterministic given history** — multiple instances of the bandit (multiple stories' visitors at the same time) all pull the same arm, creating thundering-herd attribution issues. Not ideal for high-QPS impression-serving. |
| **Thompson Sampling** | Optimal regret + **randomized**, so concurrent impressions naturally distribute across the posterior. Standard production choice for online content. |

### B. The contextual extension is probably worth the cost

The first pass mentioned contextual bandits as an option. For news headlines, context matters:
- **Referrer** (social / search / direct) — different intent, different headline elasticity
- **Time of day** — morning commute vs evening browsing have different attention budgets
- **Device** (mobile / desktop) — character-count and tone preferences differ
- **Reader history** (logged-in users) — content category preferences

**LinUCB or Neural Contextual Bandit** (production-grade) typically delivers an additional **5–15% CTR lift** over per-story stochastic Thompson Sampling. Worth the engineering cost for a site with ~50 stories/day × 100k views per story.

### C. The downstream-subscription gap — reward shaping

The bandit optimizes CTR (dense, immediate). The goal is subscription conversion (sparse, delayed). The standard trick: **reward shaping** — blend the click reward with a delayed subscription signal:

$$
\text{Reward}_{\text{shaped}} = \text{click} + \lambda \cdot \text{subscription\_within\_session}
$$

where $\lambda$ is calibrated such that the per-impression expected subscription value equals the per-impression expected click value × historical click-to-subscribe ratio. **Caveat:** subscription within session is rare (~0.3% of clicks); the variance contribution is large. Most production deployments **leave subscription out of the reward and use it as a guardrail only**, which is what the first pass did. The "right" answer is open-frontier per §16.5 reward-design literature.

### D. Editor-bandit collaboration — a UX problem more than an ML problem

The first pass mentioned editor trust briefly. In production, the workflow is:
1. Editor writes 8–12 candidate headlines
2. Bandit shows them at 6h close ranked by posterior mean + confidence
3. Editor can **promote or demote** any headline (overrides the bandit's allocation for the next interval)
4. Editor can **veto** a headline (removes it from the bandit's arm set)
5. Bandit logs editor overrides for post-mortem learning

The bandit framework needs editor-friendly tooling to be operationally accepted, regardless of algorithmic correctness.

### E. Cross-story learning — meta-bandit / hierarchical bandit

Each story being its own bandit ignores the fact that **editor style patterns generalize**: a writer who prefers question-form headlines that work for them probably has predictable patterns. Hierarchical Bayesian models share information across stories within the same editor / category:

- **Editor-level hyperpriors:** per-editor mean CTR distribution
- **Category-level hyperpriors:** per-category baseline CTR

Result: the bandit cold-starts faster on new stories (the prior is more informative) — earlier convergence per story, better aggregate views. Used at Reddit and Microsoft per published case studies.

### F. The auditability frontier — why content platforms still need A/B too

§10.3 lists "auditability matters" as a reason A/B beats MAB. For news content, the audit question is: **did the framework systematically bias toward sensationalist content?** Answering this requires:
- Periodic offline A/B (bandit-on vs uniform on a sample of stories) for ongoing audit
- Transparency in the bandit's allocation logs
- Independent third-party review for politically-sensitive content

These don't replace the bandit but layer on top. The 5% permanent uniform holdback is the operational implementation.

---

## Final consolidated summary

Headline selection on breaking news is the canonical Thompson Sampling MAB case, with **per-story Beta-Bernoulli posteriors, prior-primed at 200 imputed pulls per arm, clicks as the bandit reward, and a contextual extension** (LinUCB or neural contextual bandit) for an additional 5–15% lift on top. The meta-experiment validates the framework via 2-week bandit-on vs bandit-off on ~700 stories; launch iff median per-story view lift ≥ +5% over uniform with bounce / subscription / brand-safety guardrails clean. Phase rollout: sports + culture first, hard-news with editorial gate. **Dominant risk is clickbait drift (Goodhart on CTR)**, mitigated by tight-$\alpha$ guardrails on bounce + time-on-page, editor veto rights, brand-safety audits, and a 5% permanent uniform holdback. **Post-experiment analysis must use importance-weighted estimators per §10.4** — naive t-tests on bandit traffic give the wrong answer. Subscription is a delayed signal kept as a guardrail rather than reward-shaped into the bandit; this is an open-frontier compromise per §16.5.

---

## Key takeaways from this example

1. **The skill correctly refuses A/B and recommends MAB.** This is the framework-level staff move — recognizing when the problem doesn't fit the default tool.
2. **Per-story Thompson Sampling, not cross-story.** Each breaking news story is its own bandit; the meta-experiment validates the framework, not individual stories.
3. **Click as bandit reward; subscription as guardrail.** The bandit needs a dense, immediate reward; the long-term subscription signal sits in the meta-OEC.
4. **Clickbait drift is the dominant risk.** Goodhart's Law applies — optimizing CTR alone produces sensationalist headlines. Tight-$\alpha$ guardrails on bounce and time-on-page are the mitigation.
5. **Post-experiment analysis is not a t-test.** Per §10.4, naive analysis of MAB-allocated traffic is invalid. Importance-weighted estimators for per-arm effects; standard t-test only on the meta-experiment aggregates.
6. **Editor collaboration is a UX problem.** The bandit is a tool; editors keep veto rights and promotional overrides. Operational acceptance ≠ algorithmic correctness.

## How this example was generated

```bash
# Install (one-time)
ln -s ~/ab-testing-planner-skill/skill ~/.claude/skills/ab-test-plan

# Invoke
/ab-test-plan A digital news site (think Vox / The Verge / NYT
online news) wants to optimize headline selection [...full prompt...]
```

The first-pass output is verbatim. The depth-pass below is the senior iteration.
