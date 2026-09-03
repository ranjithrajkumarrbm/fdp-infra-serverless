"""Kinesis -> rules -> DynamoDB Lambda entry point.

Trigger: a Kinesis event-source mapping delivers a batch of transaction records.
Each record's ``kinesis.data`` is base64-encoded JSON describing one transaction.

For every record we:
  1. decode + normalise the transaction,
  2. run the sample rule engine (see ``rules.py``) to get GOOD / CHALLENGE / BLOCK,
  3. buffer a decision row and write the batch to DynamoDB.

The mapping is configured with ``FunctionResponseTypes = ["ReportBatchItemFailures"]``
so we can return only the records that failed and let Kinesis retry those
without reprocessing the whole batch.
"""

from __future__ import annotations

import base64
import json
import logging
import os
from collections import Counter
from datetime import datetime, timezone

import rules
import dynamo

log = logging.getLogger()
log.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())


def _split_env_set(name: str) -> frozenset[str]:
    raw = os.environ.get(name, "")
    return frozenset(part.strip().upper() for part in raw.split(",") if part.strip())


CONFIG = rules.RuleConfig(
    block_amount=float(os.environ.get("RULE_BLOCK_AMOUNT", "10000")),
    challenge_amount=float(os.environ.get("RULE_CHALLENGE_AMOUNT", "2000")),
    blocked_countries=_split_env_set("RULE_BLOCKED_COUNTRIES"),
    high_risk_mcc=_split_env_set("RULE_HIGH_RISK_MCC"),
    max_txns_per_account_in_batch=int(os.environ.get("RULE_MAX_TXNS_PER_ACCOUNT", "5")),
)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _decode(record: dict) -> dict:
    payload = base64.b64decode(record["kinesis"]["data"])
    txn = json.loads(payload)
    if not isinstance(txn, dict):
        raise ValueError("transaction payload is not a JSON object")
    return txn


def _normalise(txn: dict) -> dict:
    """Coerce the fields the rules rely on; leave everything else untouched."""
    return {
        **txn,
        "transaction_id": str(
            txn.get("transaction_id") or txn.get("id") or txn.get("txn_id") or ""
        ),
        "account_id": str(txn.get("account_id") or txn.get("customer_id") or ""),
        "amount": float(txn.get("amount", 0) or 0),
        "currency": str(txn.get("currency", "")).upper(),
        "country": str(txn.get("country") or txn.get("country_code") or "").upper(),
        "mcc": str(txn.get("mcc", "")).strip(),
        "card_present": bool(txn.get("card_present", True)),
    }


def handler(event, context):
    records = event.get("Records", [])
    log.info("received %d kinesis record(s)", len(records))

    # First pass: decode + normalise so batch-level rules (velocity) can see
    # every transaction before we decide any of them.
    decoded: list[tuple[str, dict]] = []
    failures: list[dict] = []
    for record in records:
        seq = record["kinesis"]["sequenceNumber"]
        try:
            decoded.append((seq, _normalise(_decode(record))))
        except Exception:
            log.exception("could not decode record %s", seq)
            failures.append({"itemIdentifier": seq})

    account_counts = Counter(txn["account_id"] for _, txn in decoded if txn["account_id"])
    ctx = {"account_counts": account_counts}

    decision_rows: list[dict] = []
    tally = Counter()
    for seq, txn in decoded:
        try:
            outcome = rules.evaluate(txn, CONFIG, ctx)
            tally[outcome.decision] += 1
            decision_rows.append(
                {
                    "transaction_id": txn["transaction_id"] or seq,
                    "account_id": txn["account_id"],
                    "amount": txn["amount"],
                    "currency": txn["currency"],
                    "country": txn["country"],
                    "decision": outcome.decision,
                    "reason": "; ".join(outcome.reasons),
                    "rules_matched": outcome.rules_matched,
                    "kinesis_sequence_number": seq,
                    "processed_at": _now_iso(),
                    "source": "fdp-transaction-processor",
                }
            )
        except Exception:
            log.exception("rule evaluation failed for record %s", seq)
            failures.append({"itemIdentifier": seq})

    if decision_rows:
        try:
            written = dynamo.put_many(decision_rows)
            log.info(
                "wrote %d decision(s) to dynamodb: %s",
                written,
                dict(tally),
            )
        except Exception:
            # Whole-batch write failure - ask Kinesis to redeliver everything we
            # had not already flagged as a decode failure.
            log.exception("dynamodb write failed for batch")
            already = {f["itemIdentifier"] for f in failures}
            failures.extend(
                {"itemIdentifier": seq} for seq, _ in decoded if seq not in already
            )

    return {"batchItemFailures": failures}
