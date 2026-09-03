"""Sample fraud-decisioning rules for incoming transactions.

The engine is intentionally small and self-contained: each rule is a pure
function that inspects a normalised transaction dict and either returns a
``RuleHit`` or ``None``. ``evaluate`` runs them in priority order and collapses
the hits into a single decision.

Decisions
---------
``BLOCK``      - stop the transaction outright.
``CHALLENGE``  - allow only after step-up auth (e.g. 3-D Secure / OTP).
``GOOD``       - no rule fired; let it through.

Thresholds and lists come from the Lambda environment (see ``config`` in
``handler.py``) so they can be tuned per environment without a code change.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Optional

BLOCK = "BLOCK"
CHALLENGE = "CHALLENGE"
GOOD = "GOOD"

# BLOCK outranks CHALLENGE outranks GOOD.
_SEVERITY = {GOOD: 0, CHALLENGE: 1, BLOCK: 2}


@dataclass(frozen=True)
class RuleHit:
    rule: str
    decision: str
    reason: str


@dataclass(frozen=True)
class Decision:
    decision: str
    reasons: list[str]
    rules_matched: list[str]


@dataclass(frozen=True)
class RuleConfig:
    block_amount: float
    challenge_amount: float
    blocked_countries: frozenset[str]
    high_risk_mcc: frozenset[str]
    max_txns_per_account_in_batch: int


def _rule_amount_block(txn: dict, cfg: RuleConfig, ctx: dict) -> Optional[RuleHit]:
    if txn["amount"] >= cfg.block_amount:
        return RuleHit(
            "amount_over_block_threshold",
            BLOCK,
            f"amount {txn['amount']:.2f} >= block threshold {cfg.block_amount:.2f}",
        )
    return None


def _rule_blocked_country(txn: dict, cfg: RuleConfig, ctx: dict) -> Optional[RuleHit]:
    country = txn.get("country", "").upper()
    if country and country in cfg.blocked_countries:
        return RuleHit(
            "sanctioned_or_blocked_country",
            BLOCK,
            f"country {country} is on the block list",
        )
    return None


def _rule_amount_challenge(txn: dict, cfg: RuleConfig, ctx: dict) -> Optional[RuleHit]:
    if txn["amount"] >= cfg.challenge_amount:
        return RuleHit(
            "amount_over_challenge_threshold",
            CHALLENGE,
            f"amount {txn['amount']:.2f} >= challenge threshold {cfg.challenge_amount:.2f}",
        )
    return None


def _rule_card_not_present(txn: dict, cfg: RuleConfig, ctx: dict) -> Optional[RuleHit]:
    half = cfg.challenge_amount / 2
    if not txn.get("card_present", True) and txn["amount"] >= half:
        return RuleHit(
            "card_not_present_elevated_amount",
            CHALLENGE,
            f"card-not-present and amount {txn['amount']:.2f} >= {half:.2f}",
        )
    return None


def _rule_high_risk_mcc(txn: dict, cfg: RuleConfig, ctx: dict) -> Optional[RuleHit]:
    mcc = str(txn.get("mcc", "")).strip()
    if mcc and mcc in cfg.high_risk_mcc:
        return RuleHit(
            "high_risk_merchant_category",
            CHALLENGE,
            f"merchant category code {mcc} is high risk",
        )
    return None


def _rule_batch_velocity(txn: dict, cfg: RuleConfig, ctx: dict) -> Optional[RuleHit]:
    seen = ctx.get("account_counts", {}).get(txn.get("account_id"), 0)
    if seen > cfg.max_txns_per_account_in_batch:
        return RuleHit(
            "account_velocity_in_batch",
            CHALLENGE,
            f"{seen} transactions for this account in one batch "
            f"(> {cfg.max_txns_per_account_in_batch})",
        )
    return None


# Evaluation order is documentation only - the final decision is the most severe
# hit regardless of order - but keeping BLOCK rules first makes traces readable.
RULES: tuple[Callable[[dict, RuleConfig, dict], Optional[RuleHit]], ...] = (
    _rule_amount_block,
    _rule_blocked_country,
    _rule_amount_challenge,
    _rule_card_not_present,
    _rule_high_risk_mcc,
    _rule_batch_velocity,
)


def evaluate(txn: dict, cfg: RuleConfig, ctx: Optional[dict] = None) -> Decision:
    """Run every rule and fold the hits into one decision."""
    ctx = ctx or {}
    hits = [hit for rule in RULES if (hit := rule(txn, cfg, ctx)) is not None]

    if not hits:
        return Decision(GOOD, ["no rule matched"], [])

    winner = max(hits, key=lambda h: _SEVERITY[h.decision]).decision
    return Decision(
        decision=winner,
        reasons=[h.reason for h in hits],
        rules_matched=[h.rule for h in hits],
    )
