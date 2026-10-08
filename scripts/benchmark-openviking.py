#!/usr/bin/env python3
# scripts/benchmark-openviking.py
"""Measure authenticated retrieval requests without recording prompts or results."""
import argparse
import json
import math
import os
from pathlib import Path
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, new_url):
        return None


def percentile(values, fraction):
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def measure(config, cases, rounds, timeout):
    url = config["url"].rstrip("/")
    parsed = urllib.parse.urlparse(url)
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("client URL must not contain credentials, query parameters, or a fragment")
    if parsed.scheme != "https" and not (parsed.scheme == "http" and parsed.hostname in ("127.0.0.1", "localhost", "::1")):
        raise ValueError("use a loopback HTTP URL or HTTPS")
    key = config.get("api_key")
    if not isinstance(key, str) or not key:
        raise ValueError("configure an authenticated USER client key first")
    opener = urllib.request.build_opener(NoRedirect())
    samples, errors = [], []
    attempt = 0
    for _ in range(rounds):
        for case in cases:
            attempt += 1
            request = urllib.request.Request(url + "/api/v1/search/find", data=json.dumps({
                "query": case["query"], "limit": 5, "telemetry": True,
            }).encode(), headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
            started = time.perf_counter()
            try:
                with opener.open(request, timeout=timeout) as response:
                    payload = json.load(response)
                result = payload["result"]
                samples.append({
                    "attempt": attempt,
                    "duration_ms": round((time.perf_counter() - started) * 1000, 2),
                    "server_ms": payload.get("telemetry", {}).get("summary", {}).get("duration_ms"),
                    "expected_marker_found": case.get("expected") in json.dumps(result) if case.get("expected") else None,
                })
            except urllib.error.HTTPError as error:
                errors.append({"attempt": attempt, "http_status": error.code})
            except (OSError, ValueError, KeyError):
                errors.append({"attempt": attempt, "request_failed": True})
    warm = [sample["duration_ms"] for sample in samples if sample["attempt"] > 1]
    hits = [sample["expected_marker_found"] for sample in samples if sample["expected_marker_found"] is not None]
    expected_attempts = sum(bool(case.get("expected")) for case in cases) * rounds
    return {
        "operation": "search.find",
        "attempts": len(cases) * rounds,
        "successes": len(samples),
        "errors": errors,
        "first_request_ms": next((sample["duration_ms"] for sample in samples if sample["attempt"] == 1), None),
        "warm_p50_ms": statistics.median(warm) if warm else None,
        "warm_p95_ms": percentile(warm, 0.95) if warm else None,
        "expected_marker_hit_rate": sum(hits) / expected_attempts if expected_attempts else None,
        "samples": samples,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=Path.home() / ".openviking/ovcli.conf")
    parser.add_argument("--cases", type=Path, required=True, help="JSON array containing query and optional expected marker")
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args()
    if not 1 <= args.rounds <= 100 or args.timeout <= 0:
        parser.error("use 1-100 rounds and a positive timeout")
    stat = args.config.stat()
    if stat.st_uid != os.getuid() or stat.st_mode & 0o077:
        raise ValueError("client config must be private and owned by you")
    cases = json.loads(args.cases.read_text())
    if not isinstance(cases, list) or not cases or any(not isinstance(case, dict) or not isinstance(case.get("query"), str) or not case["query"].strip() or ("expected" in case and not isinstance(case["expected"], str)) for case in cases):
        raise ValueError("provide at least one non-empty query")
    report = measure(json.loads(args.config.read_text()), cases, args.rounds, args.timeout)
    print(json.dumps(report, indent=2))
    return 1 if report["errors"] else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError) as error:
        print("benchmark-openviking: " + str(error), file=sys.stderr)
        raise SystemExit(1)
