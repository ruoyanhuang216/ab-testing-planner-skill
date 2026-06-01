# A/B Testing Plan Generator — A Claude Code Skill

Give it a product problem; it produces a staff-DS-grade A/B testing plan.

This is a Claude Code [Skill](https://docs.claude.com/en/docs/agents/skills) that packages a 1,400-line staff-level A/B testing playbook (drawn from Netflix XP, LinkedIn T-REX, Microsoft ExP, the Kohavi-Tang-Xu *Trustworthy Online Controlled Experiments* book, and 2020s frontier research on anytime-valid sequential testing, interleaving, CUPED, and CATE) into a single slash command. You point it at a product problem, it walks the full plan.

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

## Example output

Given the prompt above (free-delivery-to-non-DashPass), the skill produces an end-to-end plan covering:
- Customer-level randomization stratified by recent order frequency
- CUPED with prior-30-day orders covariate (~50% variance reduction)
- Combined OEC = α·Δorders − β·Δsubsidy, with pre-committed weights
- DashPass renewal rate as the high-risk guardrail at α = 0.005
- 1.5% relative MDE → ~460k per arm with CUPED (vs 1.2M without)
- 2-week minimum duration; geo-randomized pilot in 5 markets first; 5% permanent holdback for long-term LTV measurement
- Decision rubric pre-committed: launch iff OEC ≥ MDE AND DashPass renewal ≥ baseline − 0.5pp

See `reference/ab-testing-playbook.md` §13 for the worked Doordash example this is based on.

## What's inside

```
ab-testing-planner-skill/
├── README.md                           ← this file
├── LICENSE                             ← MIT
├── skill/
│   └── SKILL.md                        ← the slash command definition + planning framework
└── reference/
    └── ab-testing-playbook.md          ← the staff-level playbook the skill draws from
```

The skill is intentionally lightweight — most of the value is in the planning framework encoded in `SKILL.md` plus the reference depth in the playbook. The skill reads the playbook at invocation time and applies the framework.

## Provenance

The reference playbook (`reference/ab-testing-playbook.md`, ~1,400 lines, 18 sections) is drawn from the [`ds-case-interview-skill`](https://github.com/ruoyanhuang216/ds-case-interview-skill) repo's deeper case-interview material, focused down to A/B testing specifics. It cross-references companion topics (causal inference, product sense, metric diagnosis) that aren't part of this skill but are part of the broader interview-prep set.

Headline sources behind the playbook:
- Kohavi, Tang, Xu — *Trustworthy Online Controlled Experiments* (Cambridge 2020)
- Lindon, Malek, Bibaut et al. (Netflix) — *Design-Based Confidence Sequences* (2022)
- Johari, Koomen, Pekelis, Walsh (Optimizely) — *Always Valid Inference* (Operations Research 2022)
- Tang, Agarwal, O'Brien, Meyer (Google) — *Overlapping Experiment Infrastructure* (KDD 2010)
- Xu et al. (LinkedIn) — *Assign Experiment Variants at Scale* (2022)
- Wager-Athey — *Estimation and Inference of Heterogeneous Treatment Effects using Random Forests* (JASA 2018)
- Künzel-Sekhon-Bickel-Yu — *Metalearners for HTE* (PNAS 2019)

Full citation set inline in `reference/ab-testing-playbook.md` §15.7, §15.5.11, §15.6.10, and elsewhere.

## License

MIT — see [LICENSE](./LICENSE). Use freely. If you ship a plan generated by this skill, no attribution required (though a star is appreciated).
