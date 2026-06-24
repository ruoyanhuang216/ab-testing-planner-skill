# Example: Experiment Design Case

## Case Question

> "We're considering adding a 'Tips & Tricks' tooltip onboarding flow for new users of our photo editing app. How would you design an experiment to test whether it improves user retention?"

---

## Step 1: Clarify & Restate

**Restate**: "We want to test whether a new tooltip-based onboarding flow for new users improves retention in our photo editing app. I'll design an A/B experiment to measure this. Let me clarify a few things first."

**Clarifying questions**:
1. What does retention mean here? (Day-7 retention: % of new users who return on day 7)
2. Who qualifies as a "new user"? (First-time app openers)
3. What platforms? (iOS and Android)
4. Is there a current onboarding flow, or is this the first one? (Currently no onboarding — users go straight to the editor)
5. How big is our daily new user base? (~50K new users/day)
6. Any time pressure on the decision? (Want results within 3 weeks)

**Case type**: Experiment Design

**Objective**: *Design an A/B test to determine if tooltip onboarding improves D7 retention for new users*

---

## Step 2: Structure the Experiment

```
Experiment Design
├── Hypothesis
│   └── "Adding a tooltip onboarding flow will increase D7 retention 
│        by making new users discover key features faster, reducing 
│        early frustration and dropout."
│
├── Setup
│   ├── Unit of randomization: User (not session — onboarding is a one-time experience)
│   ├── Control: No onboarding (current experience)
│   ├── Treatment: Tooltip onboarding flow (5-step guided tour)
│   ├── Randomization split: 50/50
│   ├── Eligibility: New users only (first app open, no prior account)
│   └── Duration: 14 days enrollment + 7 days observation = 21 days total
│
├── Metrics
│   ├── Primary: D7 retention rate (binary: returned on day 7, yes/no)
│   ├── Secondary:
│   │   ├── D1, D3, D14 retention (retention curve shape)
│   │   ├── # of features used in first session
│   │   ├── # of photos edited in first 7 days
│   │   └── Time spent in first session
│   └── Guardrails:
│       ├── Onboarding completion rate (do users actually finish it?)
│       ├── First-session drop-off rate (do tooltips cause immediate exits?)
│       └── App uninstall rate within 24 hours
│
├── Sample Size & Power
│   ├── Baseline D7 retention: ~20% (assumed from historical data)
│   ├── Minimum detectable effect (MDE): 1 percentage point (20% → 21%)
│   ├── Significance level: α = 0.05 (two-sided)
│   ├── Power: 80%
│   ├── Required sample: ~31K per group (using proportions test formula)
│   └── At 50K new users/day, 50/50 split → 25K/group/day → ~2 days to enroll
│       (but need 7 more days for D7 observation → total ~9 days minimum)
│
└── Potential Pitfalls & Mitigations
    ├── Novelty effect: Users engage more just because it's new
    │   └── Mitigation: Run for 14 days enrollment, check if effect decays in later cohorts
    ├── Tooltip dismissal: Users might skip tooltips immediately
    │   └── Mitigation: Track tooltip completion rate as guardrail metric
    ├── Platform differences: iOS vs Android UX differences
    │   └── Mitigation: Stratify randomization by platform, analyze separately
    ├── Network effects: Unlikely for onboarding (users are independent)
    │   └── No mitigation needed
    └── Multiple testing: Several secondary metrics
        └── Mitigation: Pre-register primary metric; apply Bonferroni to secondary
```

---

## Step 3: Analyze (Pre-mortem)

**Hypothesis stated**: "I expect the tooltip onboarding to lift D7 retention by 1-3 percentage points, because users who discover core features (filters, crop, export) in their first session are more likely to return — similar to the 'aha moment' concept."

**What I'd check during the experiment**:
1. **Day 1**: Verify randomization is balanced (demographic/platform split similar across groups)
2. **Day 3**: Check guardrail metrics — if first-session drop-off rate spikes >5% in treatment, consider pausing
3. **Day 9+**: Start observing D7 retention for earliest cohorts
4. **Day 14**: Enrollment closes; wait for all users to hit D7 window
5. **Day 21**: Full analysis

**Quantification example**: "If baseline D7 retention is 20% and we see a 2pp lift (to 22%), that's a 10% relative improvement. With 50K new users/day, that's an additional 1,000 users retained per day, or ~365K additional retained users annually."

---

## Step 4: Synthesis

"The experiment is straightforward because onboarding is a one-time, user-level intervention with no network effects. The main risks are:
- **Novelty effect** — mitigated by running enrollment over 14 days and checking cohort consistency
- **Tooltip fatigue / dismissal** — tracked via completion rate guardrail
- **Platform variance** — handled via stratified randomization

The sample size requirements are easily met given our daily volume (need ~31K/group, get 25K/group/day)."

---

## Step 5: Recommendation & Decision Framework

"Here's how I'd make the launch decision:

| Scenario | D7 Retention Lift | First-Session Drop-off | Decision |
|---|---|---|---|
| Best case | >= 1pp, statistically significant | No increase | **Launch** |
| Mixed | >= 1pp, significant | Small increase (<2pp) | Launch with tooltip UX refinement |
| Neutral | < 1pp or not significant | No increase | Don't launch; iterate on tooltip content |
| Harmful | Any | Significant increase (>3pp) | **Kill** — tooltips are driving users away |

**Next steps if we launch**:
- Iterate on tooltip content based on which steps have the lowest completion rate
- Test tooltip-specific variants (e.g., fewer steps, video vs text, progressive disclosure)
- Extend to D30 retention measurement for long-term impact"

---

## Key Techniques Demonstrated

| Technique | Where Used |
|---|---|
| Clarify objective | Step 1 — confirmed D7 retention as primary metric |
| Structure before analysis | Step 2 — full experiment design laid out upfront |
| Hypothesis before data | Step 3 — stated expected lift and reasoning |
| Quantify impact | Step 3 — "1,000 additional retained users per day" |
| Anticipate problems | Step 2 — novelty effect, platform diff, multiple testing |
| Decision framework | Step 5 — pre-defined what each outcome means for launch |
| Guardrail metrics | Step 2 — protecting against unintended harm |
