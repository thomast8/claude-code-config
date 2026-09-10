# Combining review evidence

A review is read-only unless the user authorises fixes. Assess each claim against the actual diff, acceptance criteria and repository guidance. Agreement between models is corroboration, not proof.

## Finding record

Record file and line, impact severity (P0–P4), confidence/evidence strength, concrete failure scenario, reproduction or deterministic trace, scope and proposed fix. Never infer severity from confidence or the number of reviewers repeating a claim.

Merge duplicate reports only when they identify the same underlying failure, not merely nearby lines. Keep contradictory evidence explicit and investigate it before asking the user to arbitrate. Put plausible unreproduced concerns under Unverified, with the missing evidence.

## Action

- Confirmed in-scope defect or acceptance blocker: fix when implementation is authorised, then verify the fix.
- Material security, permissions or data-integrity risk: state impact and evidence; do not hide a release blocker to meet a review cap.
- Adjacent improvement, style suggestion or pre-existing issue: record separately; do not expand the patch automatically.
- Read-only review: report findings without modifying code, even if every reviewer agrees.

After implementation and in-scope tests are green, run one bounded review and at most one remediation pass. Use targeted checks for the fixes; do not launch repeated full reviews until consensus. Report unresolved blockers. Output confirmed bugs first, then refactor debris, then optional nits when requested. State reviewer failures and verification limits without claiming an exhaustive clean bill of health.

Review suppressions in the actual diff against the repository's quality policy. Do not add or weaken suppressions, baselines or exceptions without the required authorisation.
