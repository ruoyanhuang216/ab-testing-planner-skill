# A/B Testing Plan Generator — A Claude Code Skill

[![Claude Code Skill](https://img.shields.io/badge/Claude%20Code-Skill-d97757)](https://docs.claude.com/en/docs/agents/skills)

Give it a product problem; it produces a staff-DS-grade A/B testing plan.

This is a Claude Code [Skill](https://docs.claude.com/en/docs/agents/skills) that packages a ~1,600-line staff-level A/B testing playbook — plus focused deep-dive expansions and end-to-end case walkthroughs — (drawn from Netflix XP, LinkedIn T-REX, Microsoft ExP, the Kohavi-Tang-Xu *Trustworthy Online Controlled Experiments* book, and 2020s frontier research on anytime-valid sequential testing, interleaving, CUPED, and CATE) into a single slash command. You point it at a product problem, it walks the full plan.

## What it produces

A structured plan covering:

1. **Problem framing** — the decision the experiment informs; pre-committed decision rubric.
2. **Hypothesis** — direction and magnitude with rationale.
3. **Metric hierarchy** — goal / OEC (driver) / guardrails / counter / debug, with the gameability test.
4. **Randomization** — unit, stratification, targeting, eligibility, SUTVA check.
5. **Sample size & duration** — MDE defense, variance source, CUPED reduction, calculation, ramp protocol.
6. **Trustworthy execution** — A/A plan, SRM monitoring, pre-period sanity battery.
7. **Interference handling** — when user-level randomization is invalid (two-sided market, network), the switchback / geo / cluster alternatives.
8. **Decision rubric** — launch / don't-launch / inconclusive quadrant, pre-committed.
9. **Long-term measurement** — holdback policy, novelty/primacy mitigation, reverse-experiment plan.
10. **Risks & mitigations** — Simpson, peeking, multiple-comparisons, OEC drift, cross-experiment interactions.

It also flags when the problem **shouldn't** be an A/B test — e.g. when the unit can't be randomized (use quasi-experimental fallback), when the effect is too small to power, or when the decision is governance-blocked.

## Install

Copy or symlink the `skill/` directory to your Claude Code skills folder:

```bash
# Copy
cp -r skill/ ~/.claude/skills/ab-test-plan/

# Or symlink (recommended — gets updates when you pull)
ln -s "$(pwd)/skill" ~/.claude/skills/ab-test-plan
```

## Usage

In Claude Code, invoke the skill via slash command:

```
/ab-test-plan We're considering adding free delivery on orders > $15 for non-DashPass customers. Plan the experiment.
```

Or open-ended:

```
/ab-test-plan
```

…then describe your problem in the follow-up.

The skill will produce a full plan structured as above. If your problem is underspecified, the skill will surface 2–3 targeted clarifications before drafting the plan.

## Example outputs

**Brief example.** Given the prompt above (free-delivery-to-non-DashPass), the skill produces an end-to-end plan covering:
- Customer-level randomization stratified by recent order frequency
- CUPED with prior-30-day orders covariate (~50% variance reduction)
- Combined OEC = α·Δorders − β·Δsubsidy, with pre-committed weights
- DashPass renewal rate as the high-risk guardrail at α = 0.005
- 1.5% relative MDE → ~460k per arm with CUPED (vs 1.2M without)
- 2-week minimum duration; geo-randomized pilot in 5 markets first; 5% permanent holdback for long-term LTV measurement
- Decision rubric pre-committed: launch iff OEC ≥ MDE AND DashPass renewal ≥ baseline − 0.5pp

See `reference/ab-testing-playbook.md` §13 for the Doordash example this is based on.

**Full worked examples** (with iteration) — seven examples, each exercising a different staff-level dimension:

| Example | Dimension stressed |
|---|---|
| [`examples/spotify-shuffle-removal.md`](./examples/spotify-shuffle-removal.md) | User-level A/B with triggering + CUPED stacking + anytime-valid sequential. Variance reduction is the dominant move (20× efficiency gain). |
| [`examples/uber-eats-surge-pricing.md`](./examples/uber-eats-surge-pricing.md) | **Two-sided market** with hard SUTVA violation — switchback at market × 2-hour-slot granularity + synthetic-DiD geo overlay. Carryover is the dominant risk. |
| [`examples/anthropic-claude-system-prompt.md`](./examples/anthropic-claude-system-prompt.md) | **LLM evaluation** — three-modality combination (behavioral A/B + offline LLM-judge + human-rater pairwise). No clean CUPED for response quality (open frontier per §16.5). |
| [`examples/news-headline-mab.md`](./examples/news-headline-mab.md) | **MAB / Thompson Sampling** — the skill correctly refuses A/B and recommends MAB. The canonical Yahoo / Reddit headline-selection case with clickbait drift as the dominant Goodhart risk. |
| [`examples/linkedin-connect-to-follow.md`](./examples/linkedin-connect-to-follow.md) | **Network effects** — cluster randomization at Louvain community level with ego-cluster spillover bound. Multi-sided platform with per-tier ship decisions. |
| [`examples/stripe-sca-3ds-rollout.md`](./examples/stripe-sca-3ds-rollout.md) | **Regulatory + sparse outcomes** — PSD2 SCA mandate, fraud rate underpowered at meaningful MDE, DiD overlay on bank ACS rollout schedule, per-country ship decisions. |
| [`examples/substack-recommendation-reorder.md`](./examples/substack-recommendation-reorder.md) | **Ranker change with creator-side spillover** — §15.3 two-stage interleaving + A/B; long-tail collapse as the dominant CF-ranker risk; writer-as-customer treatment. |

Each example shows **both passes** of a staff-DS conversation:

1. **First pass** — the structured 10-component plan the skill produces from the problem statement alone (the "defensible draft"). Captured verbatim from an actual `/ab-test-plan` invocation.
2. **Depth pass** — the senior iteration that pushes on what the first pass surfaced but didn't fully flesh out. This is what the skill produces when you ask follow-up questions.

Read these end-to-end to see the iterative pattern that distinguishes a junior plan ("ship the first pass") from a staff plan ("first pass + the things a senior reviewer would push on"). Each example closes with a list of *other* realistic problems the framework would handle — each exposes a different staff-level dimension.

## What's inside

```
ab-testing-planner-skill/
├── README.md                           ← this file
├── LICENSE                             ← MIT
├── CONTRIBUTING.md
├── skill/
│   └── SKILL.md                        ← the slash command definition + 10-component planning framework
├── reference/
│   ├── ab-testing-playbook.md          ← the ~1,600-line staff-level playbook the skill draws from
│   ├── deep-dives/                     ← focused expansions of playbook sections (math, worked examples, code)
│   │   ├── unit-of-analysis.md             · §3 — ICC/DEFF, CRSE & cluster-bootstrap
│   │   ├── test-statistics-and-sample-size.md  · §4/§8.6 — tests, assumptions, derivations, resampling
│   │   ├── geo-randomization.md            · §7/§16.1 — marketplace interference (Uber)
│   │   ├── network-randomization.md        · §7/§16.2 — social-graph spillover, GATE
│   │   ├── triggered-analysis.md           · §5.1 — triggering, counterfactual logging
│   │   └── variance-reduction-examples.md  · §5 — a worked example per method
│   └── case-walkthroughs/              ← end-to-end interview-style case answers
│       ├── experiment-design.md            · the A/B design case answer
│       └── experimentation-platform-design.md  · the LinkedIn "design a platform" case
└── examples/                           ← seven full first-pass + depth-pass skill conversations
    └── spotify-shuffle-removal.md          · (and six others)
```

The skill is intentionally lightweight — most of the value is in the planning framework encoded in `SKILL.md` plus the reference depth. The skill reads the playbook at invocation time and applies the framework; for extra depth it can read the matching file under `reference/deep-dives/` or `reference/case-walkthroughs/`. The `examples/` folder shows what a complete senior-DS conversation with the skill looks like. **Everything the skill needs lives in this repo — no external/private dependencies.**

## Provenance

The reference playbook (`reference/ab-testing-playbook.md`, ~1,600 lines, 18 sections), the `reference/deep-dives/` expansions, and the `reference/case-walkthroughs/` are adapted from my broader staff-DS interview-prep notes, focused down to A/B testing specifics. They mention companion topics (causal inference, time-series, metric diagnosis, hypothesis-testing/DOE) that live outside this skill — those are referenced in prose only, so **this repo is fully self-contained for A/B testing**.

Headline sources behind the playbook:
- Kohavi, Tang, Xu — *Trustworthy Online Controlled Experiments* (Cambridge 2020)
- Lindon, Malek, Bibaut et al. (Netflix) — *Design-Based Confidence Sequences* (2022)
- Johari, Koomen, Pekelis, Walsh (Optimizely) — *Always Valid Inference* (Operations Research 2022)
- Tang, Agarwal, O'Brien, Meyer (Google) — *Overlapping Experiment Infrastructure* (KDD 2010)
- Xu et al. (LinkedIn) — *Assign Experiment Variants at Scale* (2022)
- Wager-Athey — *Estimation and Inference of Heterogeneous Treatment Effects using Random Forests* (JASA 2018)
- Künzel-Sekhon-Bickel-Yu — *Metalearners for HTE* (PNAS 2019)

Full citation set inline in `reference/ab-testing-playbook.md` §15.7, §15.5.11, §15.6.10, and elsewhere.

## Contributing

This repo uses a **feature-branch + no-fast-forward merge** workflow for all changes. See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for the branch-naming conventions, the merge protocol, and the structure to follow when adding a new worked example.

## License

MIT — see [LICENSE](./LICENSE). Use freely. If you ship a plan generated by this skill, no attribution required (though a star is appreciated).
