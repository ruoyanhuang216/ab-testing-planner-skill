# Example — Stripe rolls out new SCA / 3DS challenge flow for EU card payments

A worked illustration where the dominant constraint is **regulatory + sparse outcomes**. SCA (Strong Customer Authentication) under PSD2 is mandatory for EU payments — Stripe can't withhold security from a control group. The skill must reach for **quasi-experimental design** (per playbook §9) rather than randomized A/B, and the sparse fraud-rate outcome (~0.1%) makes power binding.

> **Note on provenance.** First-pass plan produced directly using SKILL.md + the loaded playbook. Depth-pass tightens regulatory and sparse-outcome subtleties.

---

## The prompt

```
/ab-test-plan Stripe is considering rolling out a new SCA / 3DS
challenge flow for European card payments. Goal is to reduce
checkout abandonment (a common SCA complaint) while maintaining
fraud rate at parity. The current 3DS flow is the version Stripe
has run since PSD2 enforcement in 2019; the new flow has a
smoother UX with risk-based exemption flagging. Regulatory
context: PSD2 mandates SCA on most EU consumer card payments;
we can't show some users no SCA. Stripe's customer base is
merchants of all sizes; we have no direct control over the
end-consumer. Plan the experiment.
```

**Why this problem is a good illustration:**
- Regulatory constraint — can't withhold security from control
- Sparse outcomes (fraud rate ~0.1%) make power binding
- Multi-stakeholder: merchants, cardholders, issuing banks
- Issuing bank is the upstream decision-maker for some risk decisions
- Cross-border (multiple EU countries with different transaction patterns)
- Skill must reach for §9 quasi-experimental design

---

## First pass

### 1. Problem framing

- **Decision the experiment informs:** Whether to ship the new SCA / 3DS flow as default for European card payments. The legacy flow doesn't go away — both will coexist for a transition period.
- **Pre-committed decision rubric:** Launch iff EU checkout abandonment ≥ 1pp absolute reduction AND fraud rate (chargeback + 3DS-bypass-attempt) ≤ baseline (zero degradation tolerated for regulatory reasons) AND issuing-bank challenge rate doesn't unexpectedly diverge AND auth rate ≥ baseline.
- **Is A/B the right tool?** **Yes for the merchant-controlled portion; quasi-experimental for the regulatory portion.** SCA mandate means we can't have a "no SCA" control. But we *can* A/B between **the legacy 3DS flow** (current default) and **the new 3DS flow** (treatment) — both satisfy the mandate. The right framework is a **conventional A/B at the merchant level** with **quasi-experimental cross-validation by issuing bank rollout** per §9 (since some issuing banks have legacy 3DS API behavior the new flow can't fully accommodate).

### 2. Hypothesis

- **Direction:** Smoother UX → fewer cardholder abandonments at the SCA step → higher conversion. Risk-based exemption flagging → fewer challenges for low-risk transactions → fewer abandonments AND maintained fraud parity (high-risk transactions still get challenges).
- **Magnitude:**
  - **EU checkout abandonment at SCA step:** −2 to −5pp absolute (currently ~15% of EU transactions abandon at SCA)
  - **Auth rate (% of attempted payments completing):** +1 to +3pp absolute
  - **Fraud rate:** flat (±5bps; statistical noise floor at this sparsity)
  - **Issuing bank challenge rate:** flat to −2pp (exemption flagging reduces challenges)
  - **Chargeback rate (delayed signal):** flat (with confidence interval after 60 days)
- **Mechanism:** Cardholders abandon during friction-heavy SCA challenges (typing OTP, switching apps for bank auth). Smoother UX + exemption flagging on genuinely low-risk transactions reduces both friction surfaces. Fraud is held at parity because high-risk transactions still face the same 3DS challenge.

### 3. Metric hierarchy

- **Goal metric:** Net authorized payment volume (auth × value) per merchant per month — the LTV proxy for Stripe.
- **OEC (combined, weights pre-committed):**

$$
\text{OEC} = 0.6 \cdot \Delta(\text{auth\_rate}) - 0.3 \cdot \Delta(\text{fraud\_rate}) - 0.1 \cdot \Delta(\text{chargeback\_rate})
$$

Authorization rate is the dense signal; fraud and chargeback are sparse but high-stakes guardrails included in the OEC with negative weights (so degradation counts against ship).

- **Guardrails (FWER at $\alpha = 0.005$, Holm-Bonferroni per §8.2):**
  - **Fraud rate** — regulatory zero-degradation tolerance
  - **Chargeback rate** — merchant-side cost
  - **Latency at SCA step** — cardholder experience
  - **3DS-bypass-attempt rate** — fraudster adversarial probing
  - **Issuing bank decline rate** — upstream rejection
- **Counter metric:** Auth-rate gain on **non-SCA transactions** (US, non-EU merchants) — should be flat. If it changes, there's instrumentation contamination.
- **Debug metrics:** abandonment by SCA challenge type (OTP / bank-app / biometric / exemption), per-country abandonment, per-issuing-bank challenge rate, transaction-amount distribution by treatment.
- **Gameability check (per §2.2):** "auth rate" gameable by exemption-flagging aggressively (which raises fraud). Mitigation: **fraud rate is in the OEC with negative weight**; if exemption flagging tradeoff hits fraud, OEC catches it.

### 4. Randomization

- **Unit:** **Merchant** (Stripe customer account). Why merchant not transaction: (a) merchant integrates Stripe via API; the new flow requires a one-time API integration update; (b) merchant-level decisions are consistent for the cardholder, who'd notice if checkout differed mid-session; (c) fraud-rate signal aggregates better at merchant level.
- **Stratification:** By merchant size (SMB / mid-market / enterprise; different baseline fraud rates), country (UK / FR / DE / IT / ES / NL — heterogeneous SCA enforcement and bank ecosystems), and category (e-commerce / subscription / marketplace).
- **Targeting / eligibility:** EU merchants currently using the Stripe Checkout flow. **Exclude:** merchants with custom 3DS implementations (cannot use the new flow); merchants whose volume is < $1k/month (signal too sparse).
- **SUTVA check:** Mostly valid. Two edge cases: (a) cardholders shopping at multiple Stripe merchants — they see different SCA flows at different merchants, may form a preference. Probably minor. (b) Issuing banks adapt their challenge rules to bulk Stripe traffic — relevant on a quarterly timescale, not in a 4-week test.
- **Quasi-experimental overlay (per §9):** for issuing banks rolling out their own 3DS API updates, use **DiD on bank-by-bank rollout schedule** (some banks roll out the new ACS server in March, others in September) — independent identification of the issuing-bank-side effect.

### 5. Sample size & duration

- **Baseline variance:** $\sigma^2(\text{auth\_rate}) = p(1-p) \approx 0.65 \cdot 0.35 = 0.23$ at merchant level (auth rate ~65% on EU SCA-applicable transactions).
- **MDE:** 1pp absolute on auth rate. $n = 16 \cdot 0.23 / 0.0001 = 36{,}800$ merchants per arm.
- **Realistic scope:** Stripe has ~100k+ active EU merchants. 50k per arm is feasible.
- **For fraud rate (sparse):** baseline 0.1%, MDE 0.01pp absolute. $n = 16 \cdot 0.001 \cdot 0.999 / 0.000001 = 16{,}000{,}000$ **transactions** per arm. At ~$1k/month average merchant volume and 100 transactions/month, that's 160k merchants × 100 txns × multiple months. **Fraud-rate power binding** — can't power for 0.01pp MDE within a single experiment.
- **Practical approach:** test for 5% relative fraud-rate change (MDE = 0.005pp), accepting that smaller fraud changes can't be detected in this experiment. **Use the chargeback-rate signal with 60-day lag as the post-launch sanity check** instead.
- **Variance reduction (per §5):** **Pre-period CUPED at merchant level** with prior-30-day auth rate and transaction volume; expected $\rho \approx 0.8$ → 64% reduction. Effective $n \approx 13{,}000$ merchants per arm for auth-rate MDE.
- **Duration:** 8 weeks minimum. Fraud and chargeback signals have 30–60-day reporting lag; the auth-rate signal lands faster.
- **Ramp protocol:** week 1 100 merchants (volunteer beta); week 2 1% of merchants; weeks 3–4 5%; weeks 5–8 50/50.

### 6. Trustworthy execution

- **A/A test:** 2-week A/A on 5,000 EU merchants prior to launch; verify auth-rate variance estimates and uniform p-distribution.
- **SRM monitoring:** chi-square on merchant assignment ratios at $p < 10^{-6}$.
- **Pre-period sanity:** PSI on merchant covariates (size, country, category, baseline auth) between arms; require < 0.1. **Critical check: verify the merchant population that *successfully integrated the new SCA API* matches between arms** — if some merchants in treatment fall back to legacy flow due to API integration failure, you have SSRM.
- **Logging audit:** verify which 3DS flow actually served each transaction (treatment / control / fallback). Mismatch between assignment and served flow is a known SCA-integration failure mode.

### 7. Interference & spillover

- Marginal cross-merchant cardholder effects (cardholder learns to expect the new flow at one merchant, applies preference at another) — small.
- **Issuing bank side** is the bigger spillover concern: banks adapt to aggregate 3DS challenge rates. Mitigated by the quasi-experimental bank-rollout overlay (§4 above).

### 8. Decision rubric (pre-committed)

The launch quadrant per §8.5:

- **Launch iff:** OEC ≥ +0.5pp absolute AND fraud rate ≤ baseline (within 0.01pp) AND chargeback rate ≤ baseline + 5bps (allowing for 60-day reporting lag) AND issuing bank decline rate ≤ baseline + 2pp AND no SRM AND no SCA-integration failure rate > 1% in treatment.
- **Auto-shutoff iff:** fraud rate > baseline + 0.05pp with $p < 0.005$ OR issuing bank decline rate > baseline + 5pp with $p < 0.005$.
- **Multiple-testing protocol (per §8.2):** primary OEC at $\alpha = 0.05$; fraud + chargeback + bank decline at $\alpha = 0.005$ FWER; per-country breakouts at BH within tier.
- **Regulatory escalation:** if fraud rate moves > 0.02pp in *either* direction, escalate to Stripe Risk + legal team before any launch decision — the regulator may notice.

### 9. Long-term measurement

- **Holdback:** 5% of merchants stay on legacy 3DS for 12 months. Important because: (a) issuing bank adaptation is slow, (b) chargeback signals lag 60 days, (c) regulatory environment may evolve.
- **Long-term metrics:** auth rate trend, fraud trend, chargeback after 60 days, merchant retention, customer (cardholder) repeat-payment rate.
- **Reverse experiment (per §8.3):** at month 6, switch a fresh sample of merchants back to legacy 3DS for 4 weeks. Validates whether merchant + cardholder + issuing bank have all adapted to the new flow.
- **Novelty / primacy mitigation:** cardholder behavior at unfamiliar SCA challenge may be primacy-inflated (extra friction in week 1 from confusion). Plot abandonment by week-of-treatment.

### 10. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Fraud rate underpowered** to detect small but harmful changes | **High — sparse outcome problem** | Chargeback rate with 60-day lag as post-launch sanity; 5% holdback indefinitely for trend monitoring |
| **API integration failures** (treatment merchants fall back to legacy) | Medium | SCA-integration success rate as guardrail; pre-experiment merchant-onboarding QA; SSRM check |
| Issuing bank adaptation to aggregate Stripe traffic | Medium over months | Quasi-experimental DiD by bank rollout schedule; banker liaison; 12-month holdback |
| Regulatory scrutiny | Medium-high | Regulatory pre-screen; chargeback monitoring; legal team review of experiment design |
| Fraudster adversarial probing | Medium | 3DS-bypass-attempt rate as $\alpha = 0.005$ guardrail; security team monitoring |
| Per-country heterogeneity (DE / FR / NL may behave differently) | High | Pre-register per-country effects; ship per-country if heterogeneity is large |
| Merchant-side opt-in / opt-out churn | Low-medium | Pre-experiment merchant communication; opt-out closes within 24 hours of test start |
| Chargeback signal noise | High | Aggregate across merchant-months; bootstrap confidence intervals; supplement with merchant-survey signal |

### First-pass summary

Stripe SCA / 3DS rollout is best executed as **merchant-level A/B (50k per arm) with quasi-experimental DiD overlay on issuing bank rollout schedule**. Combined OEC = 0.6·auth − 0.3·fraud − 0.1·chargeback with weights pre-committed. **Fraud-rate detection is underpowered** at meaningful regulatory MDE; treat fraud as a guardrail with hard-zero-degradation tolerance, supplemented by 60-day chargeback signal and a 5% indefinite holdback for trend monitoring. 8-week duration; per-country and per-merchant-size breakouts mandatory. Auto-shutoff on fraud > +0.05pp at $p < 0.005$; regulatory escalation on any fraud movement > 0.02pp regardless of direction. Per-country ship decision if heterogeneity is large.

---

## Depth pass — senior iteration

### A. The fundamental power problem with fraud rates

The first pass acknowledged fraud-rate underpowering. A staff DS would push:

1. **Don't pretend to detect what you can't.** Stipulate up-front that fraud-rate changes below 0.01pp are undetectable in this experiment.
2. **Use chargeback signal at 60-day lag** as the post-launch confirmation. Chargebacks are 5–10× more common than initial-fraud detection and the signal stabilizes after 60 days.
3. **Use a Bayesian prior on fraud rate** (per §16.3 Bayesian A/B) — the historical fraud-rate posterior provides a tight prior; even small datasets can update it informatively. The launch decision becomes "what's the posterior probability fraud rose by more than 0.01pp" rather than "is the p-value < 0.05."
4. **5% indefinite holdback is the long-term fraud-rate trend monitor.** Run quarterly comparisons; auto-alert on sustained divergence.

### B. The DiD overlay — what banks actually do

The first pass said "DiD on bank-by-bank rollout schedule." Operationalized:

- Issuing banks update their 3DS ACS (Access Control Server) at different times across 2024–2025
- Banks with later ACS updates can be control; banks with earlier ACS can be treatment
- DiD per bank: auth rate before vs after ACS update, treatment vs control banks
- Reverse-causality concern: bigger banks update first (selection) → confound. Mitigated by **synthetic control on bank-level pre-update metrics**.
- This identifies the **bank-side effect**, separate from the Stripe-side new-flow effect. Combined estimate = Stripe-side effect + bank-side effect; need both for a clean causal answer.

### C. Per-country governance

The first pass mentioned per-country heterogeneity. The depth pass:

- **PSD2 enforcement varies by country.** France was the strictest on exemption flagging; Germany the most flexible. The new flow's risk-based exemption flagging may run into French regulatory pushback.
- **Per-country issuing bank ecosystem matters.** UK uses Visa Secure heavily; DE uses Mastercard Identity Check; NL uses iDEAL with bank-specific challenges.
- **Per-country merchant economics differ.** Italian e-commerce merchants run razor-thin margins; a 1pp auth-rate improvement is worth more there than in Germany.
- **Operational fix:** treat France as its own phase. Pre-launch legal memo from French counsel. Per-country launch decision protocol.

### D. The cardholder-side experiment is missing

The first pass treats cardholders as a downstream object. In reality:
- Cardholders aren't randomized; they encounter the new flow at multiple merchants
- A consistent improvement at one merchant may improve subsequent merchant experience too (preference learning)
- **Stripe could approximate cardholder randomization** via card-bin-level cohorts (cards from certain issuers route to treatment merchants). This isn't a clean A/B but provides a triangulation point for the cardholder-side effect.

### E. The regulator as a second-order stakeholder

PSD2 regulatory bodies (EBA, national supervisors) monitor SCA implementation. A new flow that:
- Reduces 3DS challenge rate (exemption flagging) may trigger regulator review of whether Stripe is honoring the mandate
- Increases fraud rate (even slightly) triggers immediate regulatory inquiry

**Operationalized:**
1. Pre-experiment regulatory disclosure (or at least preparation of one)
2. Internal Stripe Risk + Legal sign-off on the experiment design
3. Monthly regulator-facing report during the experiment if requested
4. Public communications plan: how Stripe explains the new flow if asked

---

## Final consolidated summary

Stripe SCA / 3DS rollout is a **regulatory + sparse-outcome problem** requiring merchant-level A/B (50k per arm) with a quasi-experimental DiD overlay on issuing bank ACS rollout schedule, supplemented by Bayesian prior on fraud rate (per §16.3) since absolute fraud-rate power is binding. Combined OEC = 0.6·auth − 0.3·fraud − 0.1·chargeback; treat fraud as a hard-zero-tolerance guardrail with auto-shutoff and regulatory escalation. **Per-country ship decisions** (France phase separately due to strict PSD2 enforcement; UK / DE / NL each evaluated independently). 8-week experiment + 5% indefinite holdback for long-term fraud-rate trend monitoring. **Regulatory governance is part of the experiment, not separate** — pre-experiment legal memo, Risk + Legal sign-off, regulator-facing reporting if requested. Cardholder side approximated via card-bin cohorts for triangulation. Dominant risks: fraud underpowering (mitigated by chargeback at 60-day lag + Bayesian posterior + indefinite holdback), regulatory scrutiny (mitigated by pre-experiment regulatory disclosure and conservative auto-shutoff thresholds), per-country heterogeneity (mitigated by per-country ship decisions).

---

## Key takeaways

1. **Regulatory constraints don't kill A/B but reshape it.** SCA is mandatory; we can A/B between *two compliant flows*, not between SCA and no-SCA. The skill correctly identifies this.
2. **Sparse outcomes (fraud) are power-binding.** State the limitation explicitly; use Bayesian posterior framing per §16.3 and 60-day chargeback signal as the post-launch sanity check.
3. **Multi-stakeholder governance is part of the design.** Regulator, issuing banks, merchants, cardholders — each needs explicit handling. Pre-experiment legal memo is not optional.
4. **Per-country ship decisions are likely.** PSD2 enforcement varies; ship per-country rather than pretending one-size-fits-all.
5. **Quasi-experimental overlay strengthens identification.** Bank-by-bank ACS rollout DiD provides an independent estimate of the bank-side effect, separate from the Stripe-side new-flow effect.
