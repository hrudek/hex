"""Strict export validation. Error messages never quote imported field contents."""
from __future__ import annotations

import datetime as dt
import json
import math
import uuid
from dataclasses import dataclass
from pathlib import Path

MAX_INPUT_BYTES = 512 * 1024 * 1024
TEXT_FIELDS = ("recognized", "aiInput", "aiAnswer", "finalText", "cleanupOutput",
               "formattedText", "expectedText", "feedbackNote")
TIMINGS = ("asrMilliseconds", "cleanupMilliseconds", "modelMilliseconds", "stopToFinalMilliseconds")
ISSUES = {"misheard", "missing_or_shortened", "unwanted_rewrite", "punctuation_formatting",
          "vocabulary_name", "too_slow", "other"}


class Invalid(ValueError):
    """Safe, content-free diagnostic."""


def require(condition: bool, field: str) -> None:
    if not condition:
        raise Invalid(f"Invalid or missing field: {field}")


def canonical(value) -> str:
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"), allow_nan=False)


def identifier(value, field: str) -> str:
    require(isinstance(value, str), field)
    try:
        return str(uuid.UUID(value))
    except ValueError:
        raise Invalid(f"Invalid UUID field: {field}") from None


def utc(value, field: str) -> dt.datetime:
    require(isinstance(value, str), field)
    try:
        date = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        require(date.tzinfo is not None and date.utcoffset() == dt.timedelta(0), field)
        return date
    except ValueError:
        raise Invalid(f"Invalid UTC date field: {field}") from None


def integer(value, field: str, minimum: int = 0) -> None:
    require(type(value) is int and value >= minimum, field)


def text(value, field: str) -> None:
    if value is None:
        return
    require(isinstance(value, dict), field)
    require(isinstance(value.get("text"), str), field + ".text")
    try:
        size = len(value["text"].encode("utf-8"))
    except UnicodeError:
        raise Invalid(f"Invalid Unicode field: {field}") from None
    require(size <= 4000, field + ".text byte limit")
    require(type(value.get("truncated")) is bool, field + ".truncated")
    integer(value.get("originalUTF8Bytes"), field + ".originalUTF8Bytes")
    integer(value.get("wordCount"), field + ".wordCount")
    require(value["originalUTF8Bytes"] >= size, field + ".originalUTF8Bytes")
    require(value["truncated"] or value["originalUTF8Bytes"] == size, field + ".completeness")


def validate_entry(entry: dict, field: str) -> None:
    identifier(entry.get("id"), field + ".id")
    integer(entry.get("revision", 1), field + ".revision", 1)
    require(isinstance(entry.get("status"), str), field + ".status")
    context = entry.get("context")
    require(isinstance(context, dict), field + ".context")
    utc(context.get("createdAt"), field + ".context.createdAt")
    for name in ("vocabularyEnabled", "upstreamCleanupEnabled", "typrCleanupEnabled"):
        require(context.get(name) is None or type(context[name]) is bool, field + ".context." + name)
    for name in ("speechEngine", "speechLanguage", "style", "cleanupPath", "appBuild", "appVersion"):
        require(context.get(name) is None or isinstance(context[name], str), field + ".context." + name)
    for name in ("promptRevision", "guardRevision", "rating"):
        require(entry.get(name) is None or isinstance(entry[name], str), field + "." + name)
    for name in TEXT_FIELDS:
        text(entry.get(name), field + "." + name)
    text(context.get("vocabularySnapshot"), field + ".context.vocabularySnapshot")
    terms = context.get("vocabularyTerms")
    require(terms is None or (isinstance(terms, list) and len(terms) <= 100
            and all(isinstance(term, str) and len(term) <= 64 for term in terms)),
            field + ".context.vocabularyTerms")
    require(entry.get("issues") is None or (isinstance(entry["issues"], list)
            and all(isinstance(code, str) for code in entry["issues"])), field + ".issues")
    for name in TIMINGS:
        value = entry.get(name)
        require(value is None or (type(value) in (int, float) and value >= 0 and math.isfinite(value)), field + "." + name)
    for name in ("ratingOrder", "referenceOrder"):
        order = entry.get(name)
        if order is not None:
            require(isinstance(order, dict), field + "." + name)
            utc(order.get("modifiedAt"), field + "." + name + ".modifiedAt")
            require(isinstance(order.get("origin"), str), field + "." + name + ".origin")
            identifier(order.get("eventID"), field + "." + name + ".eventID")


def _pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            raise Invalid("Duplicate JSON object key")
        result[key] = value
    return result


def _constant(_value):
    raise Invalid("Non-finite JSON number")


@dataclass
class Export:
    raw: bytes
    envelope: dict
    entries: list[dict]
    warnings: list[str]
    source_count: int


def read_export(path: Path) -> Export:
    try:
        with path.open("rb") as source:
            raw = source.read(MAX_INPUT_BYTES + 1)
    except OSError:
        raise Invalid("Cannot read input file") from None
    require(len(raw) <= MAX_INPUT_BYTES, "input exceeds 512 MiB limit")
    try:
        value = json.loads(raw.decode("utf-8-sig"), object_pairs_hook=_pairs, parse_constant=_constant)
    except json.JSONDecodeError as error:
        raise Invalid(f"Invalid JSON at line {error.lineno}, column {error.colno}") from None
    except (UnicodeError, RecursionError):
        raise Invalid("Invalid UTF-8 or excessively nested JSON") from None
    require(isinstance(value, dict), "envelope")
    require(value.get("format") == "typr.dictation-log", "format (unsupported)")
    require(type(value.get("exportVersion")) is int and value["exportVersion"] == 1, "exportVersion (unsupported)")
    identifier(value.get("archiveID"), "archiveID")
    utc(value.get("exportedAt"), "exportedAt")
    require(value.get("dateEncoding") == "ISO-8601 UTC", "dateEncoding")
    require(isinstance(value.get("appBuild"), str), "appBuild")
    integer(value.get("unreadableFiles"), "unreadableFiles")
    require(type(value.get("legacyMigrationPending")) is bool, "legacyMigrationPending")
    require(isinstance(value.get("entries"), list), "entries")
    warnings = ["export scope unknown: not proof of a complete archive"] if value.get("scope") != "all" else []
    if len(value["entries"]) == 1:
        warnings.append("one-entry export: single-entry versus small archive is not distinguishable")
    if value["unreadableFiles"]:
        warnings.append("export reports unreadable source files")
    if value["legacyMigrationPending"]:
        warnings.append("export reports pending legacy migration")
    entries = []
    for i, entry in enumerate(value["entries"]):
        require(isinstance(entry, dict), f"entries[{i}]")
        schema = entry.get("schemaVersion")
        require(type(schema) is int, f"entries[{i}].schemaVersion")
        if schema not in (1, 2):
            warnings.append(f"entries[{i}]: unsupported entry schema skipped; raw evidence retained")
            continue
        validate_entry(entry, f"entries[{i}]")
        entries.append(entry)
    envelope = {key: item for key, item in value.items() if key != "entries"}
    return Export(raw, envelope, entries, warnings, len(value["entries"]))
