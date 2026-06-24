# Deep dive: Triggered analysis & counterfactual logging (Robinhood Instant)

> Expands **[§5.1 Filtering / triggering](../ab-testing-playbook.md#51-filtering--triggering--only-count-exposed-users)**. Triggering is "the single highest-leverage move in modern A/B practice" — this is a worked, production example of *why*, and of the subtle validity conditions that make it trustworthy. **§1–6** use a Robinhood credit-gate case (source project); **[§7](#7-step-by-step-walkthrough--a-more-common-case-youtube-up-next)** is a more common, step-by-step **YouTube "Up Next"** recommendation walkthrough with numbers.

---

## 1. The experiment

Robinhood **Instant** grants provisional credit at deposit time — before the ACH actually settles days later — so a real-time risk gate must decide *now* whether to front the money. We tested a new gate model.

| | |
|---|---|
| **Randomization unit** | **User** (`user_uuid`) |
| **Split** | **40 / 30 / 30** — control + two aggression thresholds of the treatment model |
| **Control** | Legacy gate: transfer-risk score, **no portfolio score** (collateral-blind) |
| **Treatment** | New gate: legacy score **+ portfolio credit-risk score** (collateral-aware) |
| **Scoring** | **Both** models score **every user daily** in a 3:00am batch; real-time **LTV** recomputed at deposit time |
| **Primary metric** | **NE (Negative-Equity) savings per user** |
| **Guardrails** | options trading revenue, total trading revenue, CX op-cost (~$10/false-positive) |

The decision that differs between arms is **whether the portfolio score flips the grant/block** at a given deposit.

---

## 2. What "triggered" means here — three nested levels

The treatment can only move NE through a specific **causal chain**, so the relevant population peels off in **three** stages — each one a *necessary condition* for the policy change to affect the outcome:

```
All assigned users (40/30/30)
        │  most never make an Instant deposit in the window
        ▼
L1 — EXPOSURE: requested an Instant deposit that fired the real-time gate
        │  ~95%+ are "pass / pass" — neither model would block them
        ▼
L2 — ACTED-UPON: would be BLOCKED BY EITHER model
        │         = old's block-set ∪ new's block-set, from BOTH scores, both arms
        ▼
L3 — OUTCOME-ELIGIBLE: the deposit FAILS TO LAND (NSF / ACH return)
        │         a landed deposit can NEVER create NE — real cash covers the credit
        ▼
   ANALYSIS UNIT
```

- **L1 (exposure)** drops everyone who never touched the gate — pure noise.
- **L2 (acted-upon) — the population actually used.** The set of deposits **at least one model would block** — equivalently, *everyone except passed-by-both*. Crucially it's computed from **both models' scores, identically in control and treatment** (the counterfactual fix to the naive "blocked by the *acting* model" trap, which would be a different set per arm — see §4). It's also the natural denominator for the operating-point guardrails (flag rate ≤3%, precision ≥80%, recall ≥60%), which are *rates over the flagged set*. The 2×2 of old×new decisions shows where the signal lives:

  | | **New: grant** | **New: block** |
  |---|---|---|
  | **Old: grant** | passed-by-both → **excluded** (no action either arm) | **new catches**: control grants → loss possible; treatment blocks → \$0 ⇒ **NE saved** |
  | **Old: block** | **new releases**: control blocks → \$0; treatment grants → loss possible ⇒ **NE added** | blocked-by-both → cancels in the NE *difference*, but stays in flag-rate / precision denominators |

  **Net NE savings = (saved on "catches") − (added on "releases").** That net is the true effect of switching policies — which is why you keep the whole union, not just one cell.
- **L3 (outcome-eligibility)** is the piece that's easy to forget. NE only materializes when the **deposit bounces**: if the ACH lands, the real money covers the provisional credit and there is **no loss no matter what the user traded**. Those landed deposits are *structural zeros* → remove them.

### Why L3 is valid — and why "portfolio went negative" is not

The loss chain is:

```
deposit → [gate grants?] → (if granted) user trades → portfolio equity may fall < 0
                                      and, independently, the ACH may BOUNCE
        NE  ⇔  (portfolio equity < 0)  AND  (deposit fails to land)
```

Necessary conditions for NE under the *grant* counterfactual:

| Condition | Driven by | Narrow on it? |
|---|---|---|
| (a) Instant **granted** | the treatment itself | — it *is* the treatment |
| (b) deposit **fails to land** (NSF / ACH return) | the customer's **external bank** — independent of RH's grant | ✅ **exogenous** → safe to narrow on |
| (c) portfolio equity **< 0** | the grant→trade path the treatment **causes** | ❌ **endogenous mediator** → collider bias |

So the analysis unit is **{Instant deposit} ∩ {blocked by either model} ∩ {deposit failed to land}**. The NE *difference* on it is dominated by the **new-catches** cell — control grants on a deposit that then bounced → realized loss; treatment blocks → \$0 — net of any **new-releases** loss the new model newly allows.

> **The test for any further narrowing:** *"would this variable's value change if I flipped the user's arm?"* Deposit-failure → **no** → safe to condition on. Portfolio-went-negative → **yes** (the grant caused the trading) → off-limits.

---

## 3. Why trigger — the dilution math

If only a fraction $p$ of assigned users can possibly differ between arms, the full-population (intent-to-treat) effect is diluted:

$$\delta_\text{ITT}=p\cdot\delta_\text{trig}\quad\Longleftrightarrow\quad \delta_\text{trig}=\frac{\delta_\text{ITT}}{p}=\frac{\text{ITT}}{\text{trigger rate}}.$$

Untriggered users have **identical** treatment/control outcomes, so they add variance to the difference estimate without adding signal. Required traffic to detect the effect at fixed power scales roughly as

$$\frac{N_\text{full}}{N_\text{triggered analysis}}\;\approx\;\frac{1}{p}\quad(\text{when per-user variance is comparable}).$$

With $p\approx5\%$, triggered analysis needs **~20× less traffic / ~20× less time** to reach the same power. This is exactly what "made detecting a 2-cent ARPU effect tractable inside one A/B cycle" — the diluted ITT signal was ~20× too small to see in a reasonable run, the triggered signal was not.

**The three levels compound.** The effective trigger rate is the product $p=p_\text{flag}\times p_\text{fail}$ (flag = blocked by either model, ~3–5%), so adding L3 (§2) shrinks $p$ further and grows the $1/p$ gain again — *and* it strips out structural zeros, which is the bigger win for a rare, zero-inflated, heavy-tailed loss metric like NE. The cost is a **floor on absolute volume**: failed-and-flagged deposits are rare, so you need enough deposit traffic to accumulate them — which is why control could be collapsed early (safety shown fast) while *threshold selection* needed several more weeks.

> **Report both numbers.** The **triggered effect** $\delta_\text{trig}$ is large and is the *mechanism* / decision number; the **full-population ARPU** ($\approx\$0.02$/yr $=p\cdot\delta_\text{trig}$) is the *business* number you scale back to for launch sizing. State which is which — quoting only the triggered effect overstates the launch impact.

---

## 4. The validity conditions (where triggered analysis goes wrong)

Triggering introduces a selection step, and a careless one reintroduces bias worse than the dilution it cured.

1. **Define the trigger on arm-invariant information.** The trigger set here is **"blocked by either model"** (the union of both block-sets), and **both models are batch-scored for every user regardless of arm**. So the trigger is computed identically on control and treatment — it is *not* a function of which arm the user landed in. ✔️
   - **Anti-pattern:** "triggered = blocked by the *acting* model." Then the treatment-arm triggered set = blocked-by-new, control-arm = blocked-by-old — **different populations → selection bias**. The fix is precisely the union-of-both-block-sets above: both scores, both arms.
2. **Counterfactual logging.** Because both scores exist for every depositor, you can reconstruct *what each model would have decided* for everyone — that's what lets you build the symmetric blocked-by-either set (L2). This is the rigorous form of triggering (§5.1, "counterfactual triggering").
3. **Never condition on a treatment-*affected* variable.** The trigger must be computed from quantities the treatment can't change (the two scores at the deposit timestamp), not from anything the grant decision influences (e.g., "users who were blocked", "users who traded", "users who churned"). Conditioning on a treatment-affected variable is collider bias. (Note this is about *causal* dependence, not timing — see point 6 for a downstream-but-exogenous variable you *can* use.)
4. **Trigger logged identically + at the right time.** The gate uses the latest **daily batch** portfolio score **+ real-time LTV** at the deposit moment, and LTV can flip the decision — so the counterfactual must be evaluated with the **serve-time inputs of both models**, with train/serve parity (the project logged real-time payloads during the PoC precisely for this).
5. **Watch differential triggering.** If the treatment *changed who deposits or how often the gate fires*, Level-1 composition could differ between arms. Here the trigger definition is arm-invariant (point 1), so the *set* is balanced; just verify the trigger **rate** matches across arms as an SRM-style check.
6. **You *may* narrow on a downstream variable — but only if it's exogenous to treatment.** Restricting to **failed-to-land** deposits (L3, §2) sharpens the population without bias, because the ACH bounce is set by the customer's external bank, not by the grant — it's a pre-determined covariate that merely *realizes* late. Conditioning on the **endogenous** "portfolio went negative" (which the grant→trade path causes) *is* collider bias. The discriminator is the flip-the-arm test in §2, not whether the variable is observed before or after the decision in wall-clock time.

---

## 5. Analysis recipe

1. **Build the triggered set (L3: blocked-by-either ∩ failed-to-land)** from both models' logged serve-time decisions plus the (exogenous) deposit-landing outcome, identically on all three arms.
2. **Compute the metric on that set per arm** — NE savings per triggered user; guardrails (options/total revenue, CX FP cost) also restricted to the triggered set (or its relevant sub-slice).
3. **Compare** each treatment threshold vs control on the triggered population; pick the better Pareto point (NE savings vs FP cost).
4. **Honor segment cost-asymmetry** within the triggered set — power users tuned to **≥70% precision** (FP cost dominates), retail to **≥60% recall** (FN dollars dominate).
5. **Scale back to ARPU** ($p\cdot\delta_\text{trig}$) for the launch decision; report both.
6. **Inference** is at the randomization unit (user) — and triggering doesn't change that. One deposit-decision per triggered user keeps it clean; if a user can trigger on multiple deposits, roll up to the user or cluster (→ [unit-of-analysis](unit-of-analysis.md)).

This is also why the rollout could **collapse control at week 4** (safety shown on the triggered set fast, because the triggered signal is ~20× denser) yet keep running ~6 weeks to separate the two treatment thresholds — threshold *selection* needs more triggered volume than the *safety* check did.

---

## 6. Pitfalls specific to this setting

- **Differential triggering** — verify trigger rate is equal across arms (it should be, by the arm-invariant definition; if not, something is leaking arm into the trigger).
- **Post-treatment selection** — never trigger on the realized decision/outcome; only on pre-decision scores.
- **Small triggered $n$** — triggering trades dilution for sample size; with ~5% trigger rate you still need enough deposit volume, which gates how early you can read threshold differences.
- **Generalization** — $\delta_\text{trig}$ describes only the triggered (blocked-by-either) set; don't quote it as the population effect. ARPU is the diluted number.
- **Trigger drift** — as the models/thresholds change, the flagged set changes; re-derive it per analysis cut rather than freezing a stale set.

---

## 7. Step-by-step walkthrough — a more common case: YouTube "Up Next"

The Robinhood case is a credit gate; the same machinery shows up far more often in **recommendation / ranker** tests. Here's the full loop with numbers.

**Setup.** YouTube tests a new **autoplay ("Up Next") recommendation model**.

| | |
|---|---|
| Randomization unit | **User**, 50/50, **10M users/arm** |
| Control | **old** model picks the autoplay video |
| Treatment | **new** model picks the autoplay video |
| Primary metric | **watch-time per user / week** |
| Guardrails | ads shown, satisfaction survey score, reported "not interested" rate |

### Step 1 — See the dilution (why naive analysis fails)
Compute watch-time/user across **all** assigned users → effect is tiny and buried in noise, because (a) many users never hit an autoplay event in the window, and (b) even when they do, the **new and old model often pick the same next video** → no possible difference. The all-up intent-to-treat (ITT) signal is ~$+0.4\%$ — too small to clear the noise floor in a normal run.

### Step 2 — Define the trigger (two levels, same as §2)
- **Exposure trigger:** user had ≥1 autoplay event during the experiment.
- **Decision-divergence trigger:** ≥1 autoplay event where the **new model's top pick ≠ old model's top pick**. ← this is the **analysis unit**. A user where both models always agree gets the identical video either way → zero T−C signal.

### Step 3 — Counterfactual logging (the enabling step)
On **every autoplay event in both arms**, run *both* models in shadow and log **both** top picks — the served pick **and** the counterfactual pick from the other model. Without this you'd only know the *acting* model's pick, and the triggered set wouldn't be definable on control. (This is the exact analog of dual-batch-scoring every user at Robinhood.)

### Step 4 — Build the triggered set symmetrically + sanity-check
Label a user "triggered" iff some logged autoplay event has differing picks — computed **identically on both arms** from the logged picks (arm-invariant). Then check:
- trigger **rate equal across arms** (an SRM-style check on the trigger itself);
- trigger uses **pre-action** info (the model's pick, fixed before the user clicks) — *not* "did the user click the autoplay" (that's post-treatment → collider bias).

```python
# both_picks logged per autoplay event, on BOTH arms
ev["diverged"] = ev["new_pick"] != ev["old_pick"]          # arm-invariant label
triggered = ev.groupby("user_id")["diverged"].any()         # ≥1 divergent event
df_t = df[df.user_id.isin(triggered[triggered].index)]      # symmetric triggered set
# metric on the triggered set, per arm
import statsmodels.formula.api as smf
smf.ols("watch_time ~ treat", data=df_t).fit(cov_type="HC1").summary()
```

### Step 5 — Compute the metric on the triggered set, per arm
Watch-time/user among triggered users, treatment vs control. Suppose the trigger rate is $p=20\%$ (rankers reorder far more often than a credit gate flips), so **2M triggered users/arm**, and the true effect there is **$\delta_\text{trig}=+2\%$**.

### Step 6 — Test and quantify the power win
Take watch-time with coefficient of variation $\text{CV}=\sigma/\mu\approx2$ (skewed). Using $n\approx 16\,\text{CV}^2/\text{MDE}_\text{rel}^2$ per arm:

| | Detect on… | MDE (rel) | Users needed/arm |
|---|---|---|---|
| **Naive (full pop)** | ITT $=+0.4\%$ | 0.004 | $16(2^2)/0.004^2\approx$ **4.0M** |
| **Triggered** | $\delta_\text{trig}=+2\%$ | 0.02 | $16(2^2)/0.02^2\approx$ **160K triggered** → $160\text{K}/0.2=$ **0.8M assigned** |

Same power for **~5× less traffic/time** — exactly the $1/p$ factor ($p=0.2$).

### Step 7 — Scale back to the launch number
The triggered effect is the *mechanism*; the *business* number is the diluted ITT: $\delta_\text{ITT}=p\cdot\delta_\text{trig}=0.2\times2\%=+0.4\%$ global watch-time. **Report both** — "+2% among the 20% of users the model actually re-ranks, ≈ +0.4% overall."

> **When do you need counterfactual logging vs. simple exposure triggering?** If the change is a surface that simply *fires or not* (a new shelf that appears only for searchers), an **exposure** trigger is enough — just remember to also log the *would-have-fired* flag on **control**. If the trigger is "the two policies **diverge**" (rankers, gates, pricing), you must log **both** decisions counterfactually, as above.

---

## 8. Interview soundbites

- "Randomization was at the user level, but the **analysis unit was the triggered set** — deposits **at least one model would block** (the union of both block-sets, from both scores, identically on both arms). ~95%+ are passed by both models and contribute zero T−C signal, so including them diluted the effect ~20×."
- "The trigger was **counterfactual**: both models scored every user daily, so I defined the trigger from both decisions identically on both arms — arm-invariant, so no differential-triggering bias."
- "The validity rule is: trigger on **arm-invariant** information only — quantities the treatment can't change. Trigger on the acting model's block and you compare two different populations; trigger on a treatment-*affected* outcome and it's collider bias. Timing doesn't matter — a downstream-but-exogenous variable is fine."
- "Triggering cut required traffic ~$1/p\approx20\times$, which is what made a **2-cent ARPU** effect detectable in one A/B cycle. I reported the dense triggered effect as the mechanism and the diluted ARPU as the launch number."
- "I narrowed once more on **outcome-eligibility**: NE can only happen on a deposit that **bounces**, so a landed deposit is a structural zero. That's a valid filter because the ACH bounce is exogenous to our grant — flipping the user's arm wouldn't change it. I did *not* filter on 'portfolio went negative,' because the grant→trade path causes that — conditioning on it would be collider bias."

---

*Back to playbook: [§5.1 Filtering / triggering](../ab-testing-playbook.md#51-filtering--triggering--only-count-exposed-users) · [deep-dive index](README.md)*
