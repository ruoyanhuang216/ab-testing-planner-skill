# Example — Anthropic tests a new Claude system prompt for code tasks

A worked illustration of the `/ab-test-plan` skill on an **LLM evaluation** problem — the §16.5 frontier where classical A/B methods strain because (1) there's no single correct output, (2) response variability is high, and (3) quality has subjective dimensions that aren't measurable from user behavior alone.

The skill's right answer is to **combine three evaluation modalities**: behavioral A/B (the launch-decision signal), offline LLM-as-judge (fast iteration on quality), and human-rater pairwise eval (the corroboration that catches LLM-judge bias).

> **Note on provenance.** The first-pass plan is the actual verbatim output from invoking `/ab-test-plan` on the prompt below. The depth-pass that follows tightens the LLM-specific subtleties.

---

## The prompt

```
/ab-test-plan Anthropic is considering a new system prompt for
Claude when handling coding-assistance tasks (refactor / debug /
explain-code / write-tests requests in Claude.ai and the Claude
Code CLI). The new prompt is hypothesized to produce more concise
responses with better code-quality. The change is server-side only
— same model weights, just different system prompt prepended at
inference. Plan the experiment. Assumptions: we have telemetry on
user behavior (turn count, follow-up rate, thumbs-up/down) but not
on the actual code quality of responses; can sample responses for
offline LLM-as-judge eval and a smaller human-rater eval;
subscription tiers are Free, Pro, Max, and Enterprise.
```

**Why this problem is a good illustration:**
- Pure §16.5 frontier — three evaluation modalities to compose
- No clean CUPED analog for response quality (the playbook explicitly flags this)
- Subjective quality measurement (LLM-judge has known bias toward its own style)
- Per-tier heterogeneity (Free / Pro / Max / Enterprise have different elasticity)
- Per-task-type heterogeneity (refactor / debug / explain / tests can have opposite signs)
- Sparse user feedback (thumbs-up ~3%, thumbs-down ~1.5%)
- Open-frontier acknowledgment is itself a staff move

---

## First pass — actual skill output

> *Captured verbatim from a real `/ab-test-plan` invocation. The skill loaded the playbook §16.5 from disk and produced the plan below.*

### 1. Problem framing

- **Decision the experiment informs:** Whether to ship the new system prompt as default for coding-classified turns, and on which subscription tier(s).
- **Pre-committed decision rubric:** Launch iff combined OEC (LLM-judge code quality + behavioral satisfaction signals) moves ≥ +5pp Elo-equivalent AND follow-up correction rate doesn't degrade by ≥ 2pp AND user-reported safety / refusal rate doesn't change. Auto-shutoff iff thumbs-down rate rises > 1.5pp absolute with $p < 0.005$.
- **Is A/B the right tool?** Yes, with the §16.5 caveat: **for an LLM system-prompt change, combine three evaluation modalities** — (1) **behavioral A/B** on telemetry (turn count, follow-up rate, thumbs), (2) **offline LLM-as-judge** on a sampled held-out prompt set, (3) **win-rate / pairwise human eval** on a smaller sample. The behavioral A/B is the launch-decision signal; the others validate quality. Per §16.5 open frontier: CUPED-style variance reduction for response quality is unsolved; we'll use sample-size brute force on the offline eval.

### 2. Hypothesis

- **Direction:** Treatment system prompt → shorter, more focused responses + better code quality → fewer follow-up corrections, higher thumbs-up, higher LLM-judge code-quality score, comparable refusal/safety.
- **Magnitude:**
  - **Tokens per response:** −15 to −30%
  - **Turn count to resolution:** −5 to −15%
  - **Thumbs-up rate:** +0.3 to +1.0 pp (sparse signal at ~3% baseline)
  - **Thumbs-down rate:** flat to −0.5pp (the harm guardrail)
  - **Follow-up message rate within 5 min:** −2 to −5 pp
  - **LLM-judge pairwise win-rate (treatment > control):** 52–58% (i.e., +5pp Elo-equivalent)
  - **Human-rater pairwise win-rate:** 52–60%
- **Mechanism:** New system prompt is more directive about response format and scope (answer the specific question; suggest minimal diffs not full rewrites; flag assumptions explicitly). Compresses output without losing correctness, reducing user follow-ups.

### 3. Metric hierarchy

- **Goal metric:** 30-day user retention × code-task completion rate (LTV proxy for Pro / Max / Enterprise).
- **OEC (combined, weights pre-committed):**

$$
\text{OEC} = 0.4 \cdot \Delta(\text{LLM\_judge\_winrate} - 0.5) + 0.3 \cdot \Delta(\text{thumbs\_up\_rate}) - 0.2 \cdot \Delta(\text{followup\_correction\_rate}) - 0.1 \cdot \Delta(\text{thumbs\_down\_rate})
$$

Combines all three §16.5 modalities into a decision-grade scalar.

- **Guardrails (FWER at $\alpha = 0.005$, Holm-Bonferroni per §8.2):**
  - Thumbs-down rate — harm signal, most operationally critical
  - Refusal rate
  - Safety / harmful-output rate (separate classifier on 1% sample)
  - Latency (TTFT and TPOT)
  - Pro / Max conversion
- **Counter metric:** **Response token count** — what's traded off.
- **Debug metrics:** conversation length distribution, code-block character count, % with code suggestions, refusal classifications by category, LLM-judge per-task-type scores.
- **Gameability check (per §2.2):** LLM-judge win-rate is gameable by team-tuning to match judge preferences. Mitigation: **stronger model frozen by separate team** as judge + **human-rater corroboration on 10% subsample**. If LLM-judge and human-rater diverge by > 2pp, distrust the LLM-judge.

### 4. Randomization

- **Unit:** **Conversation** (request-level) for behavioral arm; **prompt** (held-out sample) for offline arm. Conversation-level is appropriate — system prompt only affects code-classified turns, no within-user consistency value.
- **Stratification:** Subscription tier (Free / Pro / Max / Enterprise). Also **code-task type** (refactor / debug / explain / write-tests) post-hoc for analysis.
- **Targeting / eligibility:** Conversations where **first user message is classified as a code-task**. SSRM trap (per §3): if the new system prompt changes Claude's response style, follow-up messages may differ in classification — analyze on **first-turn classification** to fix the cohort.
- **SUTVA check:** Valid. Conversations are independent; no cross-conversation contamination at the system-prompt level.
- **If SUTVA violated:** N/A.

### 5. Sample size & duration

- **Baseline:** thumbs-up ~3% of code-task conversations, thumbs-down ~1.5%, follow-up correction ~25%.
- **MDE on behavioral A/B:** 0.3pp absolute on thumbs-up. At $p = 0.03$, $\sigma^2 = 0.029$ → **$n = 51{,}500$ conversations per arm**, feasible at Claude scale within days.
- **MDE on LLM-judge eval:** 5pp pairwise win-rate above 50%. ~600 pairwise comparisons.
- **MDE on human rater:** 5pp pairwise win-rate. **300 paired comparisons** by 3-rater majority (inter-rater agreement > 0.6 Cohen's kappa).
- **Variance reduction (per §5, §16.5):** **No clean CUPED analog for response quality**. For behavioral metrics, stratify by tier × task-type with post-stratification (~20% reduction). For offline eval, use a **held-out prompt set matched to production task-type distribution** (the closest analog to CUPED).
- **Duration:** 2 weeks minimum behavioral (covers DOW and weekend coding); 1 week offline; 2 weeks human-rater (annotator throughput bottleneck).
- **Ramp protocol:** 1% → 5% → 25% → 50% over 3 days, then 50/50 for 11 days of behavioral. Offline + human eval run in parallel from day 1.

### 6. Trustworthy execution

- **A/A test:** 3-day A/A on production traffic. Also **A/A LLM-judge eval** on identical responses to verify the judge isn't biased toward length.
- **SRM monitoring:** chi-square on conversation-level ratios at $p < 10^{-6}$.
- **Pre-period sanity:** PSI on context features (tier, OS / platform, prompt length, code language) between arms; require < 0.1.
- **Logging audit:** verify the new system prompt was actually prepended on treatment requests — **don't trust the assignment service blindly**; verify token sequence on a sampled subset.

### 7. Interference & spillover

Not flagged. Each conversation is independent; the model doesn't retain state across conversations.

### 8. Decision rubric (pre-committed)

| | Practically meaningful | Not practically meaningful |
|---|---|---|
| **Stat sig** | **LAUNCH** (all three modalities agree) | Don't launch — OEC mis-specified |
| **Not stat sig** | Inconclusive — refine prompt, re-test | **DON'T LAUNCH** |

Specific thresholds:

- **Launch iff:** OEC ≥ +5pp Elo-equivalent AND follow-up correction ≥ baseline − 2pp AND thumbs-down ≤ baseline + 0.3pp AND LLM-judge and human-rater agree within 2pp AND no safety/refusal regression AND no SRM.
- **Auto-shutoff iff:** thumbs-down > baseline + 1.5pp with $p < 0.005$ OR critical safety classifier triggers on > 0.5% of treatment responses.
- **Multiple-testing protocol (per §8.2):** primary OEC at $\alpha = 0.05$; thumbs-down + refusal + safety at $\alpha = 0.005$ FWER; per-task-type breakouts at BH within tier.
- **Disagreement protocol:** if LLM-judge and human-rater eval disagree by > 2pp — **distrust the LLM-judge**, default to human-rater + behavioral A/B for the launch decision.

### 9. Long-term measurement

- **Holdback:** 5% permanent control on code-task conversations for 90 days. **Why 90 days not 12 months:** the system-prompt isn't a customer-facing slow-burn change; user adaptation is fast. Enough to catch (a) interaction with future model updates, (b) downstream subscription churn, (c) cumulative skill drift.
- **Long-term metrics:** Pro / Max retention, code-task return rate per user, conversation depth, subscription-tier upgrades.
- **Reverse experiment (per §8.3):** at month 2, switch a fresh sample back to the old prompt for 1 week — measures whether users adapted (sticky preference) or whether old prompt would still be preferred.
- **Novelty / primacy mitigation:** first 48h shows user surprise / adaptation; compute the second-week effect separately as steady-state.

### 10. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **LLM-judge bias** — judge model prefers its own style | **High — dominant LLM-eval risk** | Stronger frozen judge; human-rater 10% subsample; disagreement protocol |
| **Sparse thumbs signal** | High | 2-week minimum; powered for 0.3pp MDE |
| **Conciseness backfires on complex tasks** | Medium | Per-task-type breakout; ship per-task-type if signs diverge |
| **Subscription-tier heterogeneity** | Medium | Pre-register tier-level effects; ship per-tier if Enterprise degrades while Free lifts |
| **No CUPED for response quality** per §16.5 | Known limitation | Brute-force $n$; post-stratify on task type; LLM-judge as the offline-eval CUPED-substitute |
| Cross-experiment interaction with concurrent model updates | High — model team ships often | Mutual exclusion with model-update experiments; restart if model version changes mid-test |
| **Safety / refusal regression** | Low but high-impact | Separate safety classifier on 1% sample; auto-shutoff at 0.5% trigger |
| Prompt-injection attack surface | Low | Adversarial eval before launch |
| **User-perceived ≠ LLM-judge quality** | Medium | Behavioral signal is user-perceived; LLM-judge is assistive; weight behavioral higher in OEC |

### First-pass summary

Three-modality combined evaluation: **behavioral A/B** on conversation-level telemetry for the launch decision, **offline LLM-as-judge** on a held-out prompt set with a stronger frozen judge for fast iteration, **human-rater pairwise eval** on a 10% subsample for LLM-judge corroboration. OEC = 0.4·LLM-judge-winrate + 0.3·thumbs-up − 0.2·follow-up − 0.1·thumbs-down, pre-committed. Launch iff OEC ≥ +5pp AND all modalities agree AND no safety regression. **Per-tier and per-task-type breakouts mandatory**; ship per-segment if heterogeneity is large. Open-frontier acknowledgment per §16.5: no clean CUPED for response quality; brute-force sample size + post-stratification + LLM-judge as the offline-eval substitute.

---

## Depth pass — senior iteration

The first pass correctly reaches for §16.5's three-modality combination. The depth pass focuses on LLM-specific subtleties that the playbook flags as open frontier.

### A. The LLM-judge bias problem — beyond "use a frozen stronger judge"

The first pass cited the bias risk but the staff-level fix involves **multiple defensive layers**:

1. **Judge-pair ensemble.** Don't use one judge — use 3 different stronger LLMs (e.g., Claude Opus 4.7, GPT-5, Gemini 3.0). If they disagree, that's signal that the metric is fragile. Take the median win-rate across judges as the operational metric.
2. **Position bias correction.** Pairwise LLM-judges have known position bias (preferring A or B based on ordering). **Always present each comparison in both orders** and take the average. Drops noise meaningfully.
3. **Reference-free vs reference-based.** For some tasks (debug: there's a known bug to fix), use reference-based evaluation (judge has access to ground truth). For others (refactor: no single right answer), reference-free pairwise is the only option.
4. **Calibration with human raters.** Sample 5% of pairs for human eval; compute the **LLM-judge vs human agreement rate**. If it's < 70% on this task type, the LLM-judge isn't trustworthy enough for the launch decision.

### B. Response-quality variance reduction — closer to CUPED than §16.5 admits

§16.5 says "no clean CUPED analog for response quality." That's mostly true but two partial techniques work:

1. **Use the model's own confidence / logprob as a covariate.** Response quality correlates with the per-token entropy and the answer's logprob under the model. For each pair, compute the difference in mean logprob; use as a covariate in the win-rate regression. Typical reduction: 10–20%.
2. **Prompt-difficulty as a stratification variable.** Pre-classify the held-out eval prompts by difficulty (e.g., using token complexity, presence of error messages, code-language complexity). Stratify the eval set; analyze per-stratum then aggregate. This is post-stratification, which works well here.

### C. Multi-arm / multi-prompt — what the first pass doesn't say

The first pass treats this as a single A vs B comparison. In practice, Anthropic likely has **5–10 candidate prompt variants** to evaluate before picking the best. The framework should:

1. **Offline eval first**: run the LLM-judge eval on all 10 candidate prompts in parallel. Use a **Bradley-Terry / Elo model** to compute pairwise win-rates from all pairs. Rank.
2. **Top 2–3 candidates → behavioral A/B.** Only the offline winners are worth user-facing traffic.
3. **The behavioral A/B becomes A/B/C/D** (control + top 3 candidates). Multiple-testing correction: BH at $\alpha = 0.05$ across candidates.

This **two-stage architecture** mirrors the §15.3 interleaving pattern: cheap offline eval first, expensive user-facing eval second. Cuts the user-facing experimentation cost by 5–10×.

### D. The conciseness double-edged sword

The first pass mentioned "conciseness can backfire on complex tasks." A senior would operationalize:

1. **Pre-register the per-task-type analysis.** Refactor / debug / explain / tests are different cognitive operations. Conciseness is most likely positive for **debug** and **write-tests** (the user wants the answer fast); most likely negative for **explain-code** (the user wants thorough explanation). Pre-register expectations per task.
2. **Conciseness × user-experience-level interaction.** Free / new users often need more explanation; Enterprise / power users often want less. Stratify by tier × task-type.
3. **Length adaptation might be the right answer**, not a single prompt. If the data shows conciseness helps debug but hurts explain, ship a **task-classifier-conditional system prompt** rather than a global change.

### E. Open-frontier acknowledgment

§16.5 explicitly says: how to do CUPED-style variance reduction for response quality + anytime-valid sequential testing on win-rate data is **unsolved as of 2025**.

The first-pass plan acknowledges this. A senior wouldn't try to invent a solution; they'd:

1. **Be transparent in the experiment charter** that the offline eval relies on classical variance reduction techniques only
2. **Acknowledge that the LLM-judge result is the noisiest signal**; weight behavioral A/B higher in the OEC because behavioral has clean statistical foundations
3. **Treat the LLM-judge improvements over time as part of the research program**, not part of this single experiment's deliverable

### F. Subscription-tier and segment governance

The first pass surfaced tier-level analysis. The depth pass adds:

1. **Enterprise tier is its own product surface.** Enterprise customers have SLAs and audit trails — a change shipped without enterprise consent is a contract risk. **Default: exclude Enterprise from the initial experiment** unless explicitly contracted.
2. **API customers** (not in this prompt's scope) — but if the system prompt change were ever to ship to the API, that's a different governance question entirely. Document scope explicitly.
3. **Per-tier pricing and value perception.** A conciseness change that reduces tokens per response reduces the average cost-per-conversation but doesn't directly affect user value. Net contribution margin per tier should be a debug metric.

---

## Final consolidated summary

Anthropic's system-prompt change for Claude code-task turns is best executed as a **two-stage evaluation architecture**: first an offline LLM-judge eval on 10+ candidate prompts using a **judge-pair ensemble** (Claude Opus 4.7 + GPT-5 + Gemini 3.0) with position-bias correction and prompt-difficulty stratification; then a behavioral A/B/C/D on the top 2–3 offline survivors at the conversation level. Combined OEC = 0.4 LLM-judge-winrate-median + 0.3 thumbs-up − 0.2 follow-up − 0.1 thumbs-down, weights pre-committed. **Per-tier (Free / Pro / Max) and per-task-type (refactor / debug / explain / tests) breakouts are mandatory** — if heterogeneity is large (e.g. positive on debug but negative on explain), ship a **task-classifier-conditional** system prompt rather than a global change. Enterprise tier excluded from initial rollout pending contract review. **Open-frontier acknowledgment**: no clean CUPED for response quality (per §16.5); use model-logprob as a covariate (10–20% variance reduction) + prompt-difficulty stratification; brute-force sample size for the remainder. Launch iff combined OEC ≥ +5pp Elo-equivalent AND all judges agree AND no safety/refusal regression AND no SRM.

---

## Key takeaways from this example

1. **The §16.5 three-modality combination is the staff answer.** Behavioral A/B alone misses subjective quality; LLM-judge alone is biased; human-rater alone is too slow. Combine all three with a disagreement protocol.
2. **LLM-judge is the noisiest, most-defensible-attackable signal.** Use a stronger frozen judge ensemble, position-bias correction, and human-rater corroboration. Distrust the LLM-judge if it disagrees with human raters.
3. **Per-task-type heterogeneity is likely large.** Conciseness helps debug, may hurt explain. Don't ship globally; ship per-task-type conditional.
4. **Open-frontier honesty.** Per §16.5: CUPED for response quality is unsolved. Acknowledge this in the charter rather than fake a solution. Use partial techniques (model-logprob covariate + prompt-difficulty stratification) where applicable.
5. **Two-stage offline-then-online architecture.** Mirrors §15.3 interleaving: cheap offline eval to prune candidates, expensive online behavioral A/B to confirm. Saves 5–10× on user-facing traffic.
6. **Enterprise governance is real.** A system-prompt change shipped without enterprise consent is a contract risk. Scope explicitly.

## How this example was generated

```bash
# Install (one-time)
ln -s ~/ab-testing-planner-skill/skill ~/.claude/skills/ab-test-plan

# Invoke
/ab-test-plan Anthropic is considering a new system prompt for
Claude when handling coding-assistance tasks [...full prompt...]
```

The first-pass output is verbatim. The depth-pass below is the senior iteration.
