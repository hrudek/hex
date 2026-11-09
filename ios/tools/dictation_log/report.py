"""Observational aggregates, not model evaluation or causal setting rankings."""
from __future__ import annotations

import collections
import hashlib
import hmac
import re
import statistics
import unicodedata

from archive import ISSUES, TEXT_FIELDS, TIMINGS, canonical, identifier

MAX_METRIC_TOKENS = 1000
LIMITS = ("Observational, self-selected ratings; small/confounded groups do not rank settings. "
          "No audio or ASR ground truth. Good is not a reference. "
          "Final-output→reference word edit rate is NOT ASR WER or semantic quality. "
          "Export scope is unknown unless explicitly marked all; absence never deletes data. "
          "Fingerprints use per-store HMAC, comparable only within this store, not encryption.")


def fingerprint(secret: bytes, value, domain: str = "settings") -> str:
    return hmac.new(secret, (domain + "\0" + canonical(value)).encode(), hashlib.sha256).hexdigest()[:16]


def settings(entry: dict, secret: bytes) -> dict:
    context = entry["context"]
    result = {key: context.get(key) if context.get(key) is not None else "unknown" for key in
              ("speechEngine", "speechLanguage", "style", "cleanupPath", "vocabularyEnabled",
               "upstreamCleanupEnabled", "typrCleanupEnabled")}
    for key in ("promptRevision", "guardRevision"):
        result[key] = entry.get(key) if entry.get(key) is not None else "unknown"
    terms = context.get("vocabularyTerms")
    vocab = context.get("vocabularySnapshot")
    if terms is not None:
        # Complete saved list; only applied terms are active configuration.
        enabled = context.get("vocabularyEnabled")
        active = terms if enabled is True else []
        result["activeVocabulary"] = ({"hmac": fingerprint(secret, active, "vocabulary"), "truncated": False}
                                      if enabled is not None else "unknown")
    elif vocab is not None:
        result["activeVocabulary"] = {"hmac": fingerprint(secret, vocab, "vocabulary"),
                                       "truncated": vocab["truncated"]}
    else:
        result["activeVocabulary"] = "unknown"
    return result


def distance(output: list[str], reference: list[str]) -> int:
    if output == reference:
        return 0
    if len(reference) > len(output):
        output, reference = reference, output
    row = list(range(len(reference) + 1))
    for i, left in enumerate(output, 1):
        next_row = [i]
        for j, right in enumerate(reference, 1):
            next_row.append(min(next_row[-1] + 1, row[j] + 1, row[j - 1] + (left != right)))
        row = next_row
    return row[-1]


def edit_metric(entry: dict) -> tuple[str, dict | None]:
    if entry["status"] != "finished":
        return "not_finished", None
    final, reference = entry.get("finalText"), entry.get("expectedText")
    if final is None or reference is None:
        return "missing_final_or_reference", None
    if final["truncated"] or reference["truncated"]:
        return "truncated", None
    # NFC only, case-sensitive whitespace tokens; punctuation remains attached.
    output = unicodedata.normalize("NFC", final["text"]).split()
    wanted = unicodedata.normalize("NFC", reference["text"]).split()
    if not wanted:
        return "empty_reference", None
    if max(len(output), len(wanted)) > MAX_METRIC_TOKENS:
        return "token_limit", None
    edits = distance(output, wanted)
    return "eligible", {"edits": edits, "referenceTokens": len(wanted), "wordEditRate": edits / len(wanted)}


def _code(secret: bytes, value: str, known: set[str], domain: str) -> str:
    return value if value in known else "unknown:hmac:" + fingerprint(secret, value, domain)


def _build(context: dict, secret: bytes) -> str:
    # No arbitrary imported labels in default output, including malformed future builds.
    values = [context.get("appVersion") or "unknown", context.get("appBuild") or "unknown"]
    return "/".join(v if v == "unknown" or re.fullmatch(r"[0-9]{1,16}(?:\.[0-9]{1,16}){0,3}", v or "")
                    else "unknown:hmac:" + fingerprint(secret, v, "build") for v in values)


def summarize(records: list[dict], secret: bytes) -> dict:
    ratings = collections.Counter({"good": 0, "bad": 0, "unrated": 0})
    categories = collections.Counter()
    exclusions = collections.Counter()
    rates, total_edits, total_tokens = [], 0, 0
    timings = {name: [] for name in TIMINGS}
    references = complete_references = good_without_reference = unknown_settings = 0
    for entry in records:
        rating = entry["rating"] if entry.get("rating") is not None else "unrated"
        ratings[_code(secret, rating, {"good", "bad", "unrated"}, "rating")] += 1
        for code in set(entry.get("issues") or []):
            categories[_code(secret, code, ISSUES, "issue")] += 1
        reference = entry.get("expectedText")
        references += reference is not None
        complete_references += reference is not None and not reference["truncated"]
        good_without_reference += rating == "good" and reference is None
        unknown_settings += any(value == "unknown" for value in settings(entry, secret).values())
        for name in TIMINGS:
            if entry.get(name) is not None:
                timings[name].append(entry[name])
        reason, metric = edit_metric(entry)
        exclusions[reason] += 1
        if metric is not None:
            rates.append(metric["wordEditRate"])
            total_edits += metric["edits"]; total_tokens += metric["referenceTokens"]
    count = len(records)
    return {"entries": count, "sampleNotice": "too few data (n < 5)" if count < 5 else "observational; no ranking",
            "ratings": dict(sorted(ratings.items())), "ratingCoverage": (ratings["good"] + ratings["bad"]) / count if count else None,
            "referencesSupplied": references, "completeReferences": complete_references,
            "goodWithoutReference": good_without_reference, "unknownSettings": unknown_settings,
            "categories": dict(sorted(categories.items())),
            "timings": {name: {"count": len(values), "missing": count - len(values),
                               "medianMilliseconds": statistics.median(values) if values else None} for name, values in timings.items()},
            "finalOutputReferenceMetrics": {"label": "final-output→reference word edit rate; NOT ASR WER",
                "eligibilityCounts": dict(sorted(exclusions.items())), "count": len(rates),
                "median": statistics.median(rates) if rates else None,
                "pooled": total_edits / total_tokens if total_tokens else None,
                "tokenLimitPerSide": MAX_METRIC_TOKENS}}


def make_report(store, *, show_text: bool = False) -> dict:
    records, groups, archive_ids = [], collections.defaultdict(list), collections.defaultdict(set)
    text_rows = []
    for archive_id, entry_id, entry in store.records():
        records.append(entry); archive_ids[archive_id].add(entry_id)
        build = _build(entry["context"], store.secret)
        key = (build, fingerprint(store.secret, settings(entry, store.secret)))
        groups[key].append(entry)
        if show_text:
            text_rows.append({"archiveID": archive_id, "id": entry_id,
                              "fields": {key: entry.get(key) for key in TEXT_FIELDS},
                              "vocabulary": entry["context"].get("vocabularySnapshot"),
                              "vocabularyTerms": entry["context"].get("vocabularyTerms")})
    latest, latest_all, warnings = {}, {}, []
    evidence = {"rawEvidenceImports": 0, "exportsWithUnreadableFiles": 0,
                "exportsWithMigrationPending": 0, "maximumReportedUnreadableFiles": 0}
    for envelope, notices, ids in store.imports():
        evidence["rawEvidenceImports"] += 1
        evidence["exportsWithUnreadableFiles"] += envelope["unreadableFiles"] > 0
        evidence["exportsWithMigrationPending"] += envelope["legacyMigrationPending"]
        evidence["maximumReportedUnreadableFiles"] = max(evidence["maximumReportedUnreadableFiles"], envelope["unreadableFiles"])
        archive_id = identifier(envelope["archiveID"], "archiveID")
        latest[archive_id] = (envelope, ids)
        if envelope.get("scope") == "all":
            latest_all[archive_id] = ids
        warnings.extend(notices)
    archives = []
    for archive_id, ids in sorted(archive_ids.items()):
        envelope, newest = latest[archive_id]
        archives.append({"archiveID": archive_id, "retainedEntries": len(ids),
                         "latestImportScope": "all" if envelope.get("scope") == "all" else "unknown",
                         "latestUnreadableFiles": envelope["unreadableFiles"],
                         "latestLegacyMigrationPending": envelope["legacyMigrationPending"],
                         "absentFromLatestImport": len(ids - newest),
                         "absentFromLastWholeExport": len(ids - latest_all[archive_id]) if archive_id in latest_all else None,
                         "absenceMeaning": "observation only, never deletion evidence"})
    result = {"reportVersion": 1, "limits": LIMITS, "summary": summarize(records, store.secret),
              "groups": [{"build": build, "settingsHMAC": key, **summarize(rows, store.secret)}
                         for (build, key), rows in sorted(groups.items())],
              "archives": archives, "importEvidence": evidence, "warnings": sorted(set(warnings))}
    if show_text:
        result["text"] = text_rows
    return result


def human(report: dict) -> str:
    summary = report["summary"]
    lines = ["Typr local dictation report", report["limits"],
             f"Entries: {summary['entries']}; ratings: {canonical(summary['ratings'])}",
             f"Import evidence: {canonical(report['importEvidence'])}",
             f"Known rating coverage: {summary['ratingCoverage']}",
             f"References supplied: {summary['referencesSupplied']}; Good without reference: {summary['goodWithoutReference']}",
             f"Categories: {canonical(summary['categories'])}",
             f"Timing counts/medians: {canonical(summary['timings'])}",
             f"Reference metrics: {canonical(summary['finalOutputReferenceMetrics'])}"]
    for group in report["groups"]:
        lines.append(f"Build {group['build']} / settings HMAC {group['settingsHMAC']}: n={group['entries']}; {group['sampleNotice']}; ratings={canonical(group['ratings'])}")
    for archive in report["archives"]:
        lines.append(f"Archive observation: retained={archive['retainedEntries']}, latest scope={archive['latestImportScope']}, absent from latest import={archive['absentFromLatestImport']} (not deletion)")
    lines.extend("Warning: " + warning for warning in report["warnings"])
    if "text" in report:
        lines.append("Explicit --show-text output:\n" + canonical(report["text"]))
    return "\n".join(lines)
