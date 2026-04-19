# Proof Bundle Format

triage writes proof bundles under `~/triage-bundles/<timestamp>/`. Each bundle should be self-contained, easy to archive, and usable by another operator without needing access to the original terminal session.
triage writes proof bundles under `~/triage-bundles/<timestamp>/`. Each bundle should be self-contained, easy to archive, and usable by another operator without needing access to the original terminal session.

## Standard Files

### `bundle_summary.txt`

This file is the operator-facing index for the bundle. It should record:

- bundle creation timestamp
- host identifier and local user if available
- script version or git revision if available
- which collection steps ran, skipped, or failed
- a short summary of the most important findings

### `gateway_err_tail.txt`

This file should contain the last 200 relevant lines from the gateway error stream or equivalent local error source, with noisy or obviously irrelevant lines filtered out in a documented way. The goal is to preserve recent failure context without copying an entire log file into the bundle.

### `gateway_health.json`

This file is written by triage's direct baseline probe. It records the resolved gateway target, the path that answered, the HTTP response code, latency, and the baseline state (`OK`, `WARN`, or `DOWN`).

Key fields: `base_url`, `url`, `path`, `state`, `note`, `http_code`, `latency_ms`, `curl_exit_code`.

This file is produced on every normal triage run. Baseline gateway health no longer depends on a prewritten sidecar file.

### `gateway_health_enrichment.json`

If `~/openclaw/health/gateway_health.json` exists, triage copies it here as optional enrichment telemetry. Its absence must not change the baseline gateway state.

If present but stale or malformed, the collector should report that condition in metadata or notes without collapsing baseline health to `NOT_DETECTED`.

### `gateway_probe_meta.txt`

This file records the resolved probe target, selected path, HTTP code, curl exit code, baseline state, and optional telemetry state. It is the quick human-readable explanation for how the gateway collector classified the result.

### `agent_session_topology.txt`

This file records agent and session counts read from the sessions index. Key fields: `agents_detected`, `sessions_total`, `sessions_recent`, `orphan_transcripts`, `classification`.

### `collector_status.txt`

Concatenation of all collector status lines. Each line is a `collector_status id=<id> state=<state> ...` record. Used by the status reducer to compute the overall STATUS.

### `collector_metadata.jsonl`

One JSON object per collector recording: collector ID, command, exit code, timed-out flag, bytes captured, confidence level, artifact state, and result state. Useful for diagnosing slow or partial collectors.

### `verify_integrity.txt`

This file records three values for the installed CLI:

- `installed_sha`
- `expected_sha`
- `state` (`MATCH`, `MISMATCH`, or `UNKNOWN`)

`UNKNOWN` is valid when no authoritative expected checksum is available. In that case the bundle should preserve the uncertainty rather than guessing.

### `manifest.sha256`

This file should contain SHA256 checksums for every file in the bundle so operators can verify bundle integrity after copying or attaching it elsewhere.

## Formatting Expectations

- Text files should be plain UTF-8 or ASCII text.
- Timestamps should use a deterministic format where practical.
- File names should remain stable across releases unless there is a documented compatibility reason to change them.
- Any filtered or redacted output should be described in `bundle_summary.txt` so a reviewer knows what transformation occurred.
