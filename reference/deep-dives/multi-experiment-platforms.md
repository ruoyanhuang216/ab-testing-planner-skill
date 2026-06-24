# Deep dive: Multi-experiment platforms

> Expands **[§15.6](../ab-testing-playbook.md#156-multi-experiment-platforms--the-deep-dive)** — layered overlapping designs, hash-based assignment, mutual exclusion, and platform governance.

### 15.6 Multi-experiment platforms — the deep dive

At scale, experimentation isn't an experiment, it's a *platform*. LinkedIn runs **~41,000 concurrent A/B tests** on **700M+ members** with **35 trillion variant evaluations per day**; Google, Microsoft, Booking.com, and Meta operate at similar magnitudes. Naive A/B at scale falls apart along three axes — traffic exhaustion, interaction confounding, and operational risk. This subsection walks the technical and operational solutions.

#### 15.6.1 The scale problem

A platform that ran each experiment as a fresh 50/50 user split would saturate available traffic immediately. Three failure modes:

| Failure mode | Symptom |
|---|---|
| **Traffic exhaustion** | After ~5–10 simultaneous mutually-exclusive 50/50 experiments, no more headroom |
| **Interaction confounding** | Each user is in many experiments at once; if interactions are non-zero, effect estimates are biased |
| **Operational risk** | Without governance, a single bad experiment can take down a critical surface; without traceability, you can't tell which experiment caused a metric move |

#### 15.6.2 Three architectures, in order of sophistication

| Architecture | How traffic is allocated | When you'd use it |
|---|---|---|
| **Single-thread** | One experiment at a time, full traffic | Tiny startups; not viable at scale |
| **Mutual exclusion (multi-thread, non-overlapping)** | Each user in *at most one* experiment per surface | Pre-2010 default; still used for high-stakes UX changes |
| **Layered overlapping** (Google/Tang KDD'10; LinkedIn T-REX) | Hash-based assignment makes most experiments orthogonal; users in many simultaneously | Modern platform default |

#### 15.6.3 Layered overlapping — the Google/Tang KDD'10 framework

The dominant industry architecture (Tang, Agarwal, O'Brien, Meyer — Google KDD 2010) introduces a three-level hierarchy:

```
Domain                    e.g. "Web Search"  -- a surface / app boundary
└── Layer                 e.g. "ranker"      -- a related-changes bucket
    └── Experiment        e.g. "ranker_v17"  -- one specific A/B
```

Three rules give the architecture its power:

1. **Within a layer, experiments are mutually exclusive.** A user is in at most one experiment per layer. This is the *cost*.
2. **Across layers, experiments are orthogonal.** A user can be simultaneously in many experiments, one per layer. Independent random assignment per layer ensures expectations are unaffected by other layers. This is the *win*.
3. **A layer is owned by a team / system.** "Ranker" layer owned by ranking; "UI" layer owned by frontend; etc. Within-layer mutex is operationally natural (only one ranker active per user at a time).

Two extensions worth knowing:

- **Launch layers** — once an experiment ships to 100%, it moves to a separate "launched" layer so future experiments can layer underneath it without re-randomizing. Critical for incremental builds on top of shipped winners.
- **Biased layers / segment layers** — when an experiment must target a specific population (premium members, mobile-only), the layer is "biased" — assignment isn't uniform on the full traffic. Analysis must account for the targeting cohort.

#### 15.6.4 Hash-based assignment at scale — the LinkedIn formula

The serving path needs to evaluate variant assignment **for every request, for every experiment a user is in**. LinkedIn reports up to **1M cache reads/sec** under an RNG approach — unsustainable. The hash-based fix (deployed in LinkedIn's T-REX):

$$
\text{HASH}(\text{salt})(\text{member\_id}) \;=\; \text{FCrypt}\big(\text{concat}(\text{prefix}(\text{salt}, 4),\, \text{bytes}(\text{member\_id}))\big)
$$

Normalize the output to $[0, 1)$ by dividing by $F_{\max}$. The salt is the **experiment ID** (or the layer ID — same idea). Then:

```
hash_value = HASH(salt)(member_id) / F_MAX  ∈ [0, 1)
variant    = lookup_variant(hash_value)      # e.g. [0, 0.5) -> A, [0.5, 1) -> B
```

Three properties this gives:

- **Stateless.** No cache, no RPC, no database read on the hot path. Computed in-process.
- **Sticky.** Same `(salt, member_id)` always produces the same hash → same variant assignment across requests, sessions, devices.
- **Orthogonal across experiments.** Different salts produce independent hashes (verified by chi-squared independence tests in deployment).

LinkedIn reports **99.98% of variant evaluations are local** (no network call), making the latency budget essentially free. **35 trillion evaluations per day** are served with **200 GB total of member attribute data** (vs 26–390 TB/day for the cache-based RNG approach).

#### 15.6.5 Mutual exclusion vs orthogonal layering — when each

| Scenario | Choice |
|---|---|
| **Two experiments change the same UI element / metric path** | **Mutual exclusion** (same layer); orthogonal would create undefined behavior at the conflict point |
| **One ranker experiment, one notification experiment** | **Orthogonal** (different layers); near-zero interaction expected |
| **Two ranker experiments under development** | Mutual exclusion (same "ranker" layer) — only one ranker logic per user |
| **A ramping experiment competing with stable launched winners** | Layered, with the winners moved to launch layers and the new experiment in a fresh ramping layer |
| **A test of layout × ranker interaction** | A single factorial experiment in one layer — see §11 — rather than two orthogonal experiments |

#### 15.6.6 Multi-experiment analysis — when interactions matter

The orthogonality assumption is *in expectation*: any single user is in many experiments, and on average their effects don't interact. But interactions can be non-zero. Two responses:

**(a) Detection.** Platforms run automated pairwise interaction tests across active experiments. LinkedIn's published note: pairwise interactions are detectable; three-way and higher are "extremely rare." Detection runs at platform scale; investigators are alerted only when a pairwise interaction exceeds a threshold.

**(b) Joint analysis.** When you specifically want to estimate an interaction, fit a factorial-effect model across the relevant experiments:

$$
Y_{ij} = \alpha + \beta_A T_{Ai} + \beta_B T_{Bj} + \beta_{AB}(T_{Ai} \cdot T_{Bj}) + \epsilon_{ij}
$$

This requires the cell counts $T_A \times T_B$ to be balanced (LinkedIn's hash-based orthogonality gives this near-exactly) and enough power in each cell. The Netflix line of work extends this to anytime-valid factorial inference (§15.1).

#### 15.6.7 Platform-side governance and safety

A platform that runs 41,000 simultaneous experiments needs automated guardrails — humans can't review each. The infrastructure side:

| Component | What it does |
|---|---|
| **SRM monitor** | Automated chi-squared test on assignment ratios at every experiment, every hour; alerts on $p < 10^{-6}$ |
| **Auto-shutoff** | Hard-block on a configured guardrail metric breach (latency, error rate, revenue drop > $X$%) |
| **Ramp protocol** | New experiments start at 0.5% → 5% → 25% → 50% — limits blast radius |
| **Holdback management** | Long-lived 1–5% control population that doesn't get experimental treatments — enables long-term effect measurement |
| **Experiment registry** | Central system-of-record: every active experiment, its owner, its layer, its expected end date, its guardrails |
| **Metric repository** | Versioned metric definitions, so changing a metric definition doesn't silently change historical analyses |

#### 15.6.8 Industry numbers (for calibration)

| Company | Concurrent experiments | Member / unit base | Evaluations / day |
|---|---|---|---|
| **LinkedIn (T-REX)** | ~41,000 | ~700M | ~35 trillion |
| **Google** (Tang et al. 2010, original) | Hundreds simultaneously | Web search traffic | Not disclosed at exact volume |
| **Microsoft (ExP)** | ~10–20K | Bing + Office | Trillions |
| **Booking.com** | 1,000+ | ~250M monthly users | Tens of billions |
| **Netflix (XP)** | ~hundreds | ~250M members | ~hundreds of billions |
| **Airbnb** | ~1,000+ | ~150M monthly users | ~tens of billions |

These numbers are the floor for "platform-scale" — if a candidate says "we'd run a few experiments simultaneously" for a LinkedIn-scale problem, that's a junior-level frame.

#### 15.6.9 Staff phrasing

> *"At platform scale you don't run one experiment, you run tens of thousands. The dominant industry architecture is Tang-Agarwal's domain → layer → experiment hierarchy from KDD 2010: mutual exclusion within a layer, orthogonal across layers, with hash-based assignment so the serving path is stateless and sub-millisecond. LinkedIn's T-REX runs 41K concurrent experiments with 99.98% of assignments evaluated locally — no cache hit on the hot path. The platform side then needs automated SRM, auto-shutoff on guardrail breach, ramp protocols, a holdback population for long-term effects, and a centralized metric repository. Multi-experiment analysis closes the loop: pairwise interaction detection at platform scale, with joint factorial analysis when you specifically want to estimate an interaction. The interview test is whether you reach for layered orthogonality vs naive mutual-exclusion as the default."*

#### 15.6.10 Further reading

- [Overlapping Experiment Infrastructure: More, Better, Faster Experimentation (Tang, Agarwal, O'Brien, Meyer — Google KDD 2010)](https://research.google/pubs/overlapping-experiment-infrastructure-more-better-faster-experimentation/) — the foundational layered-overlapping paper.
- [Assign Experiment Variants at Scale in Online Controlled Experiments (Xu, Chen, Mao et al. — LinkedIn, 2022)](https://arxiv.org/abs/2212.08771) — hash-based assignment with the MD5+salt formula and the 35T/day scale.
- [A/B testing at LinkedIn: Assigning variants at scale (LinkedIn Engineering blog)](https://www.linkedin.com/blog/engineering/ab-testing-experimentation/a-b-testing-variant-assignment) — the operational walkthrough of T-REX.
- [Our evolution towards T-REX: The prehistory of experimentation infrastructure at LinkedIn](https://www.linkedin.com/blog/engineering/ab-testing-experimentation/our-evolution-towards-t-rex-the-prehistory-of-experimentation-i) — LinkedIn's architecture history.
- [Engineering for a Science-Centric Experimentation Platform (Diamantopoulos et al. — Netflix XP, 2019)](https://arxiv.org/abs/1910.03878) — Netflix's XP design philosophy.
- [It's All A/Bout Testing: The Netflix Experimentation Platform (Netflix Tech Blog)](https://netflixtechblog.com/its-all-a-bout-testing-the-netflix-experimentation-platform-4e1ca458c15) — the XP overview.
- [Testing for arbitrary interference on experimentation platforms (Saint-Jacques et al. — LinkedIn, 2017)](https://arxiv.org/abs/1704.01190) — platform-side interaction detection.

> **Case-walkthrough companion.** See [`examples/experimentation-platform-design.md`](../case-walkthroughs/experimentation-platform-design.md) for the step-by-step walkthrough of *"Design an experimentation platform for LinkedIn"* using this material — the 6-step framework for the interview answer.


---
*Back to playbook: [§15 Frontier techniques](../ab-testing-playbook.md#15-frontier-techniques--the-netflix-style-staff-angle) · [deep-dive index](README.md)*
