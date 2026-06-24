# Example: Design an Experimentation Platform (LinkedIn case)

## Case Question

> *"Design an experimentation platform for LinkedIn. Walk me through how you'd approach this."*

This is a system-design case crossing **product DS**, **infrastructure**, and **statistics**. It's a favorite at LinkedIn / Microsoft / Meta / Netflix interviews and shows up in modified forms at any company with a serious experimentation org. The interviewer is testing whether you understand:

1. The scale problem (you can't naively run a single A/B per surface),
2. The infrastructure (assignment, serving, logging, analysis),
3. The statistical layer (variance reduction, sequential testing, multi-experiment analysis),
4. The governance side (SRM, ramps, guardrails, holdbacks),
5. The product specifics (LinkedIn is a multi-sided market with sparse outcomes).

**Companion playbook:** [`../ab-testing-playbook.md`](../ab-testing-playbook.md) §15.6 covers the technical depth (Tang KDD 2010, LinkedIn T-REX architecture, hash-based assignment math). Use this file for the *interview answer*; that one for the *backing depth*.

---

## Step 1: Clarify & Restate (90 seconds, don't skip)

Restate the question, then ask **3–4 clarifiers** that materially change the answer. Pick from:

1. **Scale and stage** — Is this a greenfield design or replacing an existing platform? What's the member count and target experiment volume?
2. **User surface** — Is this for the consumer feed, recruiter products, jobs, learning, ads, or everything?
3. **Change types** — UI tweaks, ranker/recommender changes, ML models, pricing, infra (CDN / backend)? Each implies different randomization units and analysis methods.
4. **Decision authority** — Who decides launches? Is this self-service for any team, or analyst-gated?
5. **Build vs buy** — Are we considering external platforms (Optimizely, LaunchDarkly, Eppo, GrowthBook) or building internally?

**Suggested anchor:** *"I'll assume we're designing the central in-house platform across all LinkedIn surfaces — member-facing, recruiter, ads — at ~700M members and ~40K concurrent experiments as the target capacity. The platform is self-service for product/eng teams, with analyst guardrails for high-stakes launches."*

This grounds you in real LinkedIn scale (the published numbers) and sets the scope.

---

## Step 2: Frame the Architecture (the issue tree)

A complete experimentation platform has **ten components**. Walk them on the whiteboard in this layered order — request flow on top, offline flow underneath:

```
ONLINE / HOT PATH (request-time, sub-ms budget)
├── 1. Experiment registry         (which experiments exist, who owns them)
├── 2. Targeting & eligibility     (who's eligible for each experiment)
├── 3. Assignment / randomization  (hash-based, stateless, sticky)
├── 4. Config serving              (variant config delivered to clients)
└── 5. Exposure logging            (record who saw what — the SRM source)

OFFLINE / WARM PATH (minutes-to-hours)
├── 6. Event ingestion             (clicks, sessions, downstream metrics)
├── 7. Metric definitions          (versioned, governed metric repository)
├── 8. Analysis engine             (CUPED, sequential, segmentation, HTE)
├── 9. Decision UI                 (analyst & PM dashboards)
└── 10. Governance & safety        (SRM, auto-shutoff, ramps, holdbacks)
```

**Senior framing:** *"I'll walk the online hot path first — assignment has to be sub-millisecond and stateless at trillions of evaluations per day — then the offline analysis layer where most of the statistical sophistication lives. I'll close on platform governance, which is where most platforms underinvest."*

---

## Step 3: Walk the Hot Path

### 3.1 Experiment registry

A central system-of-record. Every experiment has:

| Field | Why |
|---|---|
| Unique ID + version | Used as the hash salt for assignment |
| Owner team | Accountability + SRM alert routing |
| Layer assignment | Which Tang/Agarwal layer this lives in (see 3.3) |
| Targeting rule | Pre-experiment eligibility (geo, platform, segment) |
| Variant config | The actual treatment payload(s) |
| Lifecycle state | `draft / ramping / full / completed / launched / killed` |
| Guardrail thresholds | Metric breach conditions for auto-shutoff |
| Expected end date | For abandoned-experiment cleanup |

### 3.2 Targeting & eligibility — and the sticky-cohort trap

Static targeting (geo, platform) is easy. **The gotcha:** if targeting depends on something the treatment can change (e.g., "free users only" — but the treatment is a paid offer), you get an SSRM (Sample Ratio Mismatch). The fix is to **fix the targeting cohort at the pre-experiment snapshot** and don't re-evaluate during ramp. This is the production-grade move.

### 3.3 Assignment & randomization — the layered overlapping architecture

Pre-2010 platforms used **mutual exclusion**: one experiment per user per surface. Math says you saturate at ~10 simultaneous 50/50 experiments. The dominant modern architecture (Google's Tang-Agarwal KDD 2010, deployed at LinkedIn as T-REX):

```
Domain                    "Web Feed"   -- surface boundary
└── Layer                 "Feed Ranker" -- related-changes bucket
    └── Experiment        "feed_v17"   -- one A/B
```

**Three rules:**
1. **Within a layer**, experiments are mutually exclusive (a user is in *at most one* experiment per layer).
2. **Across layers**, experiments are orthogonal (a user can be in many simultaneously, one per layer).
3. **Each layer is owned by one team or one related system** (Feed Ranker layer, Notification layer, Onboarding layer, etc.).

**The hash-based assignment formula** (the LinkedIn T-REX paper):

$$
\text{hash}(\text{member\_id}, \text{salt}) \;=\; \text{MD5}\big(\text{prefix}(\text{salt}, 4) \,\Vert\, \text{bytes}(\text{member\_id})\big)
$$

Normalize to $[0,1)$; map to a variant via $[0, 0.5) \to A$, $[0.5, 1) \to B$. **Critical properties:**

- **Stateless** — no DB / cache / RPC on the hot path. LinkedIn reports **99.98% of evaluations are local**.
- **Sticky** — same member always gets the same variant for the same experiment.
- **Orthogonal across experiments** — different salts produce independent hashes (verifiable via chi-squared independence test in deployment).
- **Cheap** — LinkedIn serves **~35 trillion evaluations/day on 200 GB of member attributes** with this scheme.

**Two extensions worth naming:**
- **Launch layers** — when an experiment ships to 100%, it moves to a separate layer so new experiments don't have to compete with the launched winner.
- **Biased layers** — when an experiment targets a non-random segment (Premium-only, mobile-only), the layer's assignment is non-uniform; analysis has to account for this targeting cohort.

### 3.4 Config serving — push or pull?

Client gets the variant configuration. Two patterns:
- **Push (server-rendered):** server evaluates assignment and renders the treatment. Simpler for short-lived experiments; latency-good for UI.
- **Pull (client-fetched):** client requests variant configs at session start. Better for client-rich apps (mobile); needs a config CDN.

LinkedIn's pattern: server-side evaluation for the assignment, with treatment configs cached at the client. Lookup is hash-only on each request.

### 3.5 Exposure logging — the SRM-grade source of truth

Every variant evaluation produces an **exposure event** logged with `(member_id, experiment_id, variant, timestamp)`. This is the source for the SRM check (§6 below). **Don't conflate exposure with treatment effect logging** — exposures fire even if the variant config isn't actually used downstream; the SRM check is on exposures (was assignment fair), the effect estimate is on outcomes (did treatment change behavior).

---

## Step 4: Walk the Offline Path

### 4.1 Event ingestion

The platform doesn't own raw events — those come from the existing data pipeline (page views, clicks, messages sent, jobs applied, premium upgrades, etc.). The platform owns the **join** between events and exposures.

### 4.2 Metric definitions — the governed repository

The single most-underappreciated component. A **central versioned metric registry**:

| Required for each metric |
|---|
| Owner team, definition (formula on raw events), unit-of-analysis declaration, dimension tags |
| Version history (so changing a definition doesn't silently change historical analyses) |
| Coverage matrix — which experiments use this metric |
| Sensitivity / typical variance from historical experiments |

**The trap:** decentralized metric definitions → every team computes "DAU" slightly differently → experiment results aren't comparable. Fix this once.

### 4.3 Analysis engine — the statistical sophistication layer

The platform's analysis defaults are where staff DS earns their keep. **What a modern engine supports:**

| Capability | Why it matters |
|---|---|
| **CUPED / regression adjustment** | 30–50% variance reduction — see [`notes/ab-testing-staff-level.md`](../ab-testing-playbook.md) §5.4 |
| **Triggering analysis** | For features that only fire for a fraction of users — see §5.1 |
| **Anytime-valid sequential testing** | Continuous monitoring without inflating Type-I error — see §15.1 |
| **Segmentation** | Pre-registered segments (new / returning / premium / mobile / etc.) |
| **Heterogeneous treatment effects** | Causal forests / meta-learners — see §15.5 |
| **Quantile metrics + bootstrap** | For latency / streaming-quality outcomes — see §15.4 |
| **Multi-experiment pairwise interaction detection** | Surface interactions between active experiments — see §15.6 |
| **Long-term effects via holdback** | Permanent 1–5% control population — see §8.3 |
| **Delta-method for ratio metrics** | When analysis unit ≠ randomization unit |

**A junior answer says "we'd run a t-test." A senior answer names ≥ 5 of the above.**

### 4.4 Decision UI

The analyst-facing view. Three audiences:
- **Experiment owner (PM / eng):** "Should I launch this?" — focused on OEC, guardrails, segmentation.
- **Analyst:** "What's going on here?" — full statistical detail, custom segments, raw data access.
- **Leadership:** "Portfolio rollup" — what's running, what shipped, what got killed and why.

---

## Step 5: Platform Governance (where most platforms underinvest)

At 40K simultaneous experiments, humans can't review every one. The infrastructure has to enforce safety:

| Mechanism | What it does |
|---|---|
| **SRM monitor** | Chi-squared test on assignment ratios for every experiment every hour; alerts at $p < 10^{-6}$ |
| **Auto-shutoff** | Hard-block on guardrail metric breach (latency, errors, revenue drop > $X$%) |
| **Ramp protocol** | 0.5% → 5% → 25% → 50% → 100%, with mandatory dwell time at each level |
| **Long-lived holdback** | Permanent 1–5% control population that doesn't receive any experimental treatments — enables long-term LTV measurement |
| **Abandoned-experiment cleanup** | Auto-conclude or migrate experiments past expected-end-date |
| **Layer ownership audits** | Periodic review that no layer has been silently overloaded |

---

## Step 6: LinkedIn-Specific Considerations

This is where the case becomes LinkedIn-specific (vs a generic platform answer) and earns the extra senior signal:

### 6.1 Multi-sided market — multiple unit-of-analysis decisions

LinkedIn has four major user types: **members**, **recruiters**, **advertisers**, and **content creators**. Each requires a different randomization unit:

| Surface | Randomization unit | Why |
|---|---|---|
| Feed ranker change | Member | Consistent UX, member-level metrics |
| Recruiter Search ranker | Recruiter (or contract) | Recruiter is the customer; member-level would split decisions |
| Ad pacing algorithm | Advertiser (or campaign) | Pacing is per-campaign decision |
| Creator analytics | Creator | Creator-level decisions, creator-level metrics |

A change that crosses these (e.g., a feed change that affects what recruiters see in their network) needs the **coarsest** unit — likely member — but with cross-side metrics.

### 6.2 Network effects (creator → viewer)

Posts created by Member A are viewed by Member B's network. A naive member-level A/B for a posting-incentive treatment biases the control group up (control members see treatment members' extra posts). Fix:

- **Cluster randomization** at the network-community level, or
- **Switchback** by time slot (but creator behavior is sticky, so dwell is long), or
- **Geo experiments** at the country / region level for high-stakes changes.

The Saint-Jacques et al. (LinkedIn, 2017) paper specifically covers interference-detection at LinkedIn scale — worth referencing.

### 6.3 Sparse outcomes — jobs, hires, recruiter responses

Many of LinkedIn's most important outcomes are very rare:
- Job applications per session ≈ 1%
- Hires per applicant ≈ 5%
- Recruiter InMail acceptance ≈ 25%

For these, **member-level CUPED with pre-period activity as the covariate** is essential — without it, MDE is so large the experiment can't be powered. For *hires*, a downstream rare event, the platform should support a **hybrid metric** (e.g., applications + estimated hire propensity) to recover power.

### 6.4 Premium / Free segmentation

Many LinkedIn experiments target Free members trying to convert to Premium, or Premium members trying to retain. The platform should:
- Track `premium_status_at_assignment` and stratify on it.
- Allow **conditional experiments** on the Free-to-Premium funnel (the conversion event itself).
- Watch for SSRM if the treatment changes upgrade rates during ramp.

### 6.5 Holdbacks for long-term LTV

A platform decision a candidate should name: **always keep a 1–5% holdback** that's never been exposed to *any* shipped experiment in the past 12 months. This is the only way to measure long-term cumulative effect of the launch portfolio. LinkedIn (and Netflix) have published on the architectural / governance work this requires.

---

## Recap — the one-sentence senior answer

> *"I'd build a layered overlapping platform on the Tang-Agarwal KDD 2010 pattern — domain → layer → experiment hierarchy, hash-based assignment with member ID + experiment salt for stateless sub-ms evaluation, mutual exclusion within a layer and orthogonal across. The analysis layer supports CUPED-adjusted estimates as the default, anytime-valid sequential CIs for early stopping, pre-registered segments and CATE estimation for targeting, and multi-experiment pairwise interaction detection. Governance enforces automated SRM checks, hard auto-shutoff on guardrail breach, mandatory ramp protocols, and a permanent 1–5% holdback for long-term LTV. The LinkedIn specifics: per-side randomization units (member / recruiter / advertiser / creator), cluster or geo randomization for creator-network effects, and CUPED for the sparse-outcome metrics like jobs applied and hires. Target capacity: ~40K simultaneous experiments at ~700M members and ~35T evaluations per day, which is roughly where LinkedIn's published T-REX platform operates."*

---

## Common pitfalls in this case

1. **Jumping to t-tests without naming the assignment architecture.** The interviewer wants to see you understand mutual exclusion vs orthogonal layering first.
2. **Not naming hash-based assignment.** Cache-based assignment doesn't scale and is the easy distinguisher between senior and junior answers.
3. **Forgetting governance.** A platform that doesn't have automated SRM, auto-shutoff, and ramp protocols is one bad launch away from a crisis. Name them.
4. **Ignoring the multi-sided market.** "LinkedIn members" is not the only randomization unit — recruiters and advertisers are different decisions.
5. **No holdback discussion.** Permanent 1–5% holdback is the only way to measure long-term cumulative effects; not mentioning it is a senior tell.
6. **Treating metric definitions as trivial.** Decentralized metric definitions is the single most common platform-debt source; a senior answer names a centralized versioned metric repository.

---

## Related notes

- [`../ab-testing-playbook.md`](../ab-testing-playbook.md) §15 — the full staff-level frontier playbook backing this case.
- companion causal-inference notes §4 — quasi-experimental fallbacks when randomization isn't viable (e.g., infrastructure changes).
- [`examples/experiment-design.md`](experiment-design.md) — the simpler "design *an* experiment" case, vs designing *the platform that runs the experiments*.
- [Tang et al. KDD 2010 — Overlapping Experiment Infrastructure](https://research.google/pubs/overlapping-experiment-infrastructure-more-better-faster-experimentation/) — the canonical paper.
- [LinkedIn T-REX assignment paper (Xu et al. 2022)](https://arxiv.org/abs/2212.08771) — the hash-based assignment details.
- [LinkedIn Engineering — A/B testing variant assignment](https://www.linkedin.com/blog/engineering/ab-testing-experimentation/a-b-testing-variant-assignment) — the operational walkthrough.
