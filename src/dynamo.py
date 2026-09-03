"""Thin DynamoDB writer for transaction decisions.

Kept separate from the handler so the rule engine and the persistence layer can
be tested in isolation. Uses ``batch_writer`` so a Kinesis batch of N records
becomes a handful of ``BatchWriteItem`` calls rather than N ``PutItem`` calls.
"""

from __future__ import annotations

import decimal
import os
from typing import Iterable

import boto3

_TABLE_NAME = os.environ["TRANSACTIONS_TABLE_NAME"]
_PARTITION_KEY = os.environ.get("TABLE_PARTITION_KEY", "transaction_id")
_SORT_KEY = os.environ.get("TABLE_SORT_KEY", "").strip() or None

_table = boto3.resource("dynamodb").Table(_TABLE_NAME)


def _to_dynamo_number(value):
    """DynamoDB rejects float; round-trip through Decimal via str."""
    if isinstance(value, float):
        return decimal.Decimal(str(value))
    return value


def _clean(item: dict) -> dict:
    """Drop empty values DynamoDB would reject and fix number types."""
    out = {}
    for key, value in item.items():
        if value is None or value == "":
            continue
        out[key] = _to_dynamo_number(value)
    return out


def build_item(record: dict) -> dict:
    """Shape one decision record into a DynamoDB item.

    ``record`` is expected to carry at least ``transaction_id``; the partition
    (and optional sort) key attribute names are configurable via env so this
    works against whatever schema ``fdp-*-transactions`` actually uses.
    """
    item = dict(record)
    item.setdefault(_PARTITION_KEY, record.get("transaction_id"))
    if _SORT_KEY:
        item.setdefault(_SORT_KEY, record.get(_SORT_KEY) or record.get("processed_at"))
    return _clean(item)


def put_many(records: Iterable[dict]) -> int:
    """Write every decision record. Returns the count written."""
    written = 0
    with _table.batch_writer() as batch:
        for record in records:
            batch.put_item(Item=build_item(record))
            written += 1
    return written
