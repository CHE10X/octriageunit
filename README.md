# Triage

![Control Plane Trusted](docs/assets/control-plane-trusted.svg) ![Read-Only Verified](docs/assets/read-only-verified.svg)

`triage` is the canonical CLI for Triage, a read-only control-plane diagnostic tool for OpenClaw environments.

When your gateway is degraded, `openclaw doctor` can't answer — it's asking the patient to diagnose itself. `triage` runs outside the gateway, reads directly from the filesystem and system tools, and tells you what's actually wrong.

**Works when OpenClaw doesn't.**

No telemetry. No mutation. No background services.

`triage` is the canonical command. `OCTriage` and `octriageunit` remain available as deprecated aliases during the transition window and print `Deprecated, use \`triage\``.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/acmeagentsupply/triage/main/install.sh | bash
```

First run:

```bash
triage --self-test && triage
```

![triage install and first run](docs/images/triage-hero.png)

The proof bundle is written to `~/triage-bundles/<timestamp>/` — real evidence files ready for review, support escalation, or pasting into an AI assistant.

---

## Why Triage, not `openclaw doctor`?

`openclaw doctor` checks health through the gateway. If the gateway is the problem, you get nothing useful.

`triage` is an external observer. It reads logs, sessions, and system state directly — no gateway required. That's the entire differentiator:

```
openclaw doctor  →  gateway checks itself   (useless when gateway is the problem)
triage           →  external observer        (works regardless of gateway state)
```

It's also read-only. There's no risk to running it in a degraded production environment.

---

## What It Checks

| Signal | What it checks |
|--------|---------------|
| `gateway` | Direct local HTTP probe owned by triage; optional sidecar telemetry if present |
| `sessions` | Agent count, session topology, orphan detection |
| `digest` | DIGEST.md freshness — memory system health |
| `disk` | Available disk space on the canonical root volume (`/`) |
| `verify` | Installed CLI SHA vs. recorded release checksum |

---

## Reading the Output

A healthy system:

```
gateway: OK (liveness)
sessions: NORMAL (agents=2 ...)
verify: MATCH
STATUS: [HEALTHY]
```

A degraded system:

```
! gateway: WARN (timeout_12s)
! disk: WARN (84% used)
STATUS: [DEGRADED] (disk=WARN)
```

Run it regularly, not just when something breaks.

---

## The Proof Bundle

Every run writes a timestamped bundle to `~/triage-bundles/`:

| File | Contents |
|------|----------|
| `bundle_summary.txt` | Version, timestamp, hostname |
| `gateway_health.json` | Baseline direct probe result written by triage |
| `gateway_health_enrichment.json` | Optional copied sidecar telemetry if present |
| `gateway_probe_meta.txt` | Probe target, path, latency, baseline state, telemetry state |
| `gateway_err_tail.txt` | Filtered tail of `gateway.err.log` |
| `agent_session_topology.txt` | Session counts, agent list, orphan detection |
| `verify_integrity.txt` | Installed SHA, expected SHA, verify state |
| `collector_status.txt` | Raw collector output lines |
| `collector_metadata.jsonl` | Per-collector timing, confidence, artifact state |
| `manifest.sha256` | SHA-256 checksums of all bundle artifacts |

**Using the bundle:** Paste contents into a support ticket, or send to an AI assistant with "here's my triage bundle, what's wrong?" The bundle format is designed for both.

---

## Gateway Health

`triage` now owns baseline gateway health directly. On a clean install it probes the configured local gateway URL itself, with no healthcheck writer, LaunchAgent, or prewritten file required.

Probe resolution order:

1. `OPENCLAW_GATEWAY_URL` if set
2. `~/.openclaw/openclaw.json` gateway settings if available
3. Fallback `http://127.0.0.1:18789`

Optional sidecar telemetry at `~/openclaw/health/gateway_health.json` is still consumed when present, but only as enrichment. If that file is missing, stale, or malformed, baseline gateway health still comes from the direct probe.

**Gateway states:**

| State | Meaning |
|-------|---------|
| `OK` | Gateway reachable and healthy via direct probe |
| `WARN` | Gateway reachable but returned a degraded/error HTTP response |
| `DOWN` | Gateway unreachable from triage |

Telemetry enrichment states are reported in the gateway note and metadata:

| Telemetry | Meaning |
|-----------|---------|
| `AVAILABLE` | Optional enrichment file parsed successfully |
| `UNAVAILABLE` | Optional enrichment file absent |
| `STALE` | Optional enrichment file exists but is older than 120s |
| `MALFORMED` | Optional enrichment file exists but could not be parsed |

---

## verify States

| State | Meaning |
|-------|---------|
| `MATCH` | Binary matches the release checksum. Trust it. |
| `MISMATCH` | Binary has been modified since install. Reinstall before trusting output. |
| `UNKNOWN` | No authoritative checksum available. |

---

## Safety Guarantees

**Read-only:** Never modifies configuration, restarts services, or changes system state.

**No telemetry:** Zero outbound network calls. No phone-home behavior.

**Local-only:** All execution on the operator machine.

**Auditable:** `cat $(which triage)` shows the full script. No compiled binary, no hidden behavior.

**Proof bundle:** Writes only to `~/triage-bundles/`. Nothing else.

---

## Installation Options

**System install (recommended):**
```bash
curl -fsSL https://raw.githubusercontent.com/acmeagentsupply/triage/main/install.sh | bash
```

**User-only (no sudo required):**
```bash
curl -fsSL https://raw.githubusercontent.com/acmeagentsupply/triage/main/install.sh | bash -s -- --user
```

No background healthcheck service is required for baseline gateway status after install.

**Verify install matches source:**
```bash
bash scripts/install.sh --verify-from-source
```

**Uninstall:**
```bash
curl -fsSL https://raw.githubusercontent.com/acmeagentsupply/triage/main/scripts/uninstall.sh | bash
```

---

## Where Files Are Installed

| Item | Path |
|------|------|
| CLI binary | `/usr/local/bin/triage` (system) or `~/.local/bin/triage` (user) |
| Deprecated aliases | `/usr/local/bin/OCTriage`, `/usr/local/bin/octriageunit` |
| Proof bundles | `~/triage-bundles/<timestamp>/` |

---

## Verify Manually

```bash
shasum -a 256 $(which triage)
bash -n $(which triage)
```

Full trust posture: [docs/trust-doctrine.md](docs/trust-doctrine.md)

Bundle format spec: [docs/proof-bundle-format.md](docs/proof-bundle-format.md)

Quick reference: [CHEATSHEET.md](CHEATSHEET.md)

Uninstall instructions: [UNINSTALL.md](UNINSTALL.md)

Visual reference (print/PDF): [docs/cheatsheet-visual.html](docs/cheatsheet-visual.html)

---

## Threat Model

`triage` reads local process and platform state through operator-invoked system tools, then writes artifacts into a local proof bundle. It cannot repair services, rotate credentials, or validate remote state. The trust boundary is the local host.

---

## Something Broken?

1. `triage --self-test` — verify the tool is healthy before trusting its output
2. `triage` — capture the proof bundle
3. `ls ~/triage-bundles/` — find the latest bundle
4. Send `bundle_summary.txt` + `gateway_err_tail.txt` to support or an AI assistant

→ support@acmeagentsupply.com

---

## Want More?

Reliability scoring, RadCheck integration, and the full Acme agent stack are available at [acmeagentsupply.com](https://acmeagentsupply.com).

→ [acmeagentsupply.com](https://acmeagentsupply.com)

---

## License

MIT. See [LICENSE](LICENSE).

---

## Contributing

Open source under MIT. Issues and PRs welcome.

This repo is the OSS core. The commercial Acme stack (Observe panel, RadCheck trend, and more) lives at [acmeagentsupply.com](https://acmeagentsupply.com).
