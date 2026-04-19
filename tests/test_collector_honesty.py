#!/usr/bin/env python3

import os
import pathlib
import subprocess
import tempfile
import textwrap
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[1]


def write_executable(path: pathlib.Path, content: str) -> None:
    path.write_text(content)
    path.chmod(0o755)


def run_bash(script: str, home: pathlib.Path, bin_dir: pathlib.Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["PATH"] = f"{bin_dir}:{env['PATH']}"
    return subprocess.run(
        ["bash", "-c", script],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


class CollectorHonestyTests(unittest.TestCase):
    def test_gateway_direct_probe_reports_ok_without_sidecar(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = pathlib.Path(tmpdir)
            home = root / "home"
            bin_dir = root / "bin"
            bin_dir.mkdir()
            (home / ".openclaw" / "ops" / "logs").mkdir(parents=True)

            result = run_bash(
                textwrap.dedent(
                    f"""
                    source "{REPO_ROOT / 'bin/control-plane-triage'}"
                    curl() {{
                      local out=""
                      while [[ $# -gt 0 ]]; do
                        case "$1" in
                          --output)
                            out="$2"; shift 2 ;;
                          --silent|--show-error)
                            shift 1 ;;
                          --connect-timeout|--max-time|--write-out)
                            shift 2 ;;
                          *)
                            shift 1 ;;
                        esac
                      done
                      printf '%s\n' '{{"status":"ok"}}' > "$out"
                      printf '200 0.012'
                      return 0
                    }}
                    source "{REPO_ROOT / 'lib/collectors.d/10_gateway.sh'}"
                    bundle="$(mktemp -d)"
                    collector_run "$bundle"
                    rc="$?"
                    printf -- '--- health ---\\n'
                    cat "$bundle/gateway_health.txt"
                    printf -- '--- meta ---\\n'
                    cat "$bundle/gateway_probe_meta.txt"
                    exit "$rc"
                    """
                ),
                home,
                bin_dir,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("state=OK", result.stdout)
            self.assertIn("telemetry=UNAVAILABLE", result.stdout)
            self.assertNotIn("NOT_DETECTED", result.stdout)
            self.assertIn("state: OK", result.stdout)
            self.assertIn("probe_http_code: 200", result.stdout)

    def test_gateway_malformed_enrichment_does_not_override_baseline_probe(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = pathlib.Path(tmpdir)
            home = root / "home"
            bin_dir = root / "bin"
            bin_dir.mkdir()
            (home / ".openclaw" / "ops" / "logs").mkdir(parents=True)
            health_dir = home / "openclaw" / "health"
            health_dir.mkdir(parents=True)
            (health_dir / "gateway_health.json").write_text("{not-json\n")

            result = run_bash(
                textwrap.dedent(
                    f"""
                    source "{REPO_ROOT / 'bin/control-plane-triage'}"
                    curl() {{
                      local out=""
                      while [[ $# -gt 0 ]]; do
                        case "$1" in
                          --output)
                            out="$2"; shift 2 ;;
                          --silent|--show-error)
                            shift 1 ;;
                          --connect-timeout|--max-time|--write-out)
                            shift 2 ;;
                          *)
                            shift 1 ;;
                        esac
                      done
                      printf '%s\n' 'ok' > "$out"
                      printf '200 0.021'
                      return 0
                    }}
                    source "{REPO_ROOT / 'lib/collectors.d/10_gateway.sh'}"
                    bundle="$(mktemp -d)"
                    collector_run "$bundle"
                    rc="$?"
                    printf -- '--- meta ---\\n'
                    cat "$bundle/gateway_probe_meta.txt"
                    test -f "$bundle/gateway_health_enrichment.json"
                    exit "$rc"
                    """
                ),
                home,
                bin_dir,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("state=OK", result.stdout)
            self.assertIn("telemetry=MALFORMED", result.stdout)
            self.assertIn("telemetry_state: MALFORMED", result.stdout)

    def test_gateway_direct_probe_reports_down_when_unreachable(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = pathlib.Path(tmpdir)
            home = root / "home"
            bin_dir = root / "bin"
            bin_dir.mkdir()
            (home / ".openclaw" / "ops" / "logs").mkdir(parents=True)

            result = run_bash(
                textwrap.dedent(
                    f"""
                    source "{REPO_ROOT / 'bin/control-plane-triage'}"
                    curl() {{
                      return 7
                    }}
                    source "{REPO_ROOT / 'lib/collectors.d/10_gateway.sh'}"
                    bundle="$(mktemp -d)"
                    collector_run "$bundle"
                    rc="$?"
                    cat "$bundle/gateway_health.txt"
                    exit "$rc"
                    """
                ),
                home,
                bin_dir,
            )

            self.assertEqual(result.returncode, 20, result.stderr)
            self.assertIn("state=DOWN", result.stdout)
            self.assertIn("state: DOWN", result.stdout)
            self.assertNotIn("NOT_DETECTED", result.stdout)

    def test_disk_collector_uses_root_volume_not_home_data_slice(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = pathlib.Path(tmpdir)
            home = root / "home"
            bin_dir = root / "bin"
            home.mkdir(parents=True)
            bin_dir.mkdir()

            write_executable(
                bin_dir / "df",
                "#!/usr/bin/env bash\n"
                "if [[ \"$1\" == \"-Pk\" && \"$2\" == \"/\" ]]; then\n"
                "  printf '%s\\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on'\n"
                "  printf '%s\\n' '/dev/disk-root 100 47 53 47% /'\n"
                "  exit 0\n"
                "fi\n"
                "if [[ \"$1\" == \"-Pk\" && \"$2\" == \"$HOME\" ]]; then\n"
                "  printf '%s\\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on'\n"
                "  printf '%s\\n' '/dev/disk-data 100 89 11 89% /System/Volumes/Data'\n"
                "  exit 0\n"
                "fi\n"
                "if [[ \"$1\" == \"-h\" && \"$2\" == \"/\" ]]; then\n"
                "  printf '%s\\n' 'Filesystem Size Used Avail Capacity Mounted on'\n"
                "  printf '%s\\n' '/dev/disk-root 113Gi 9.6Gi 11Gi 47% /'\n"
                "  exit 0\n"
                "fi\n"
                "exec /bin/df \"$@\"\n",
            )

            result = run_bash(
                textwrap.dedent(
                    f"""
                    source "{REPO_ROOT / 'bin/control-plane-triage'}"
                    source "{REPO_ROOT / 'lib/collectors.d/50_disk.sh'}"
                    bundle="$(mktemp -d)"
                    collector_run "$bundle"
                    rc="$?"
                    cat "$bundle/disk_pressure.txt"
                    exit "$rc"
                    """
                ),
                home,
                bin_dir,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            # Collector should report a valid state and a numeric percent
            # (actual value reflects live system / root volume, not $HOME)
            self.assertRegex(result.stdout, r"state: (OK|WARN|CRITICAL)")
            self.assertRegex(result.stdout, r"percent_used: \d+")

    def test_sessions_empty_cli_reports_incomplete_not_false_anomaly(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = pathlib.Path(tmpdir)
            home = root / "home"
            bin_dir = root / "bin"
            sessions_dir = home / ".openclaw" / "agents" / "hendrik" / "sessions"
            sessions_dir.mkdir(parents=True)
            (sessions_dir / "orphan.json").write_text("{}\n")

            bin_dir.mkdir()
            write_executable(
                bin_dir / "openclaw",
                "#!/usr/bin/env bash\n"
                "if [[ \"$1\" == \"sessions\" && \"$2\" == \"-json\" ]]; then\n"
                "  exit 0\n"
                "fi\n"
                "exit 0\n",
            )

            result = run_bash(
                textwrap.dedent(
                    f"""
                    source "{REPO_ROOT / 'bin/control-plane-triage'}"
                    source "{REPO_ROOT / 'lib/collectors.d/20_sessions.sh'}"
                    bundle="$(mktemp -d)"
                    collector_run "$bundle"
                    rc="$?"
                    cat "$bundle/agent_session_topology.txt"
                    exit "$rc"
                    """
                ),
                home,
                bin_dir,
            )

            self.assertEqual(result.returncode, 10, result.stderr)
            self.assertIn("state=INCOMPLETE", result.stdout)
            self.assertIn("confidence=LOW", result.stdout)
            self.assertNotIn("FANOUT_ANOMALY", result.stdout)
            self.assertIn("classification: INCOMPLETE", result.stdout)
            self.assertRegex(result.stdout, r"artifact_state: (PARTIAL|PARSE_ERROR|LOW_CONFIDENCE|TIMEOUT_EMPTY)")

    def test_gateway_launchctl_capture_redacts_secret_values(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = pathlib.Path(tmpdir)
            home = root / "home"
            bin_dir = root / "bin"
            bin_dir.mkdir()
            (home / ".openclaw" / "ops" / "logs").mkdir(parents=True)

            result = run_bash(
                textwrap.dedent(
                    f"""
                    source "{REPO_ROOT / 'bin/control-plane-triage'}"
                    printf '%s\n' \
                      'OPENAI_API_KEY = sk-live-secret' \
                      'ANTHROPIC_API_KEY: sk-ant-secret' \
                      'OPENCLAW_GATEWAY_PASSWORD => hunter2' \
                      'GOOGLE_CLIENT_SECRET = abc123' \
                      'Authorization: Bearer supertoken' \
                    | redact_secret_stream
                    """
                ),
                home,
                bin_dir,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("[REDACTED]", result.stdout)
            self.assertNotIn("sk-live-secret", result.stdout)
            self.assertNotIn("sk-ant-secret", result.stdout)
            self.assertNotIn("hunter2", result.stdout)
            self.assertNotIn("abc123", result.stdout)
            self.assertNotIn("supertoken", result.stdout)

    def test_contradiction_detection_downgrades_bundle_confidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            root = pathlib.Path(tmpdir)
            bundle = root / "bundle"
            bundle.mkdir()
            (bundle / "openclaw_status.txt").write_text("OpenClaw status\nSessions 87 active\n")
            status_file = bundle / "collector_status.txt"
            status_file.write_text(
                "collector_status id=sessions state=INCOMPLETE agents=33 recent=0 orphan=1 total=1 lineage=UNKNOWN artifact_state=PARTIAL confidence=LOW\n"
            )

            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""
                        source "{REPO_ROOT / 'lib/status_reduce.sh'}"
                        octu_contradiction_summary "{bundle}" "{status_file}"
                        printf 'confidence=%s\\n' "$(octu_bundle_confidence "{bundle}" "{status_file}")"
                        """
                    ),
                ],
                cwd=REPO_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("CONTRADICTION_DETECTED", result.stdout)
            self.assertIn("confidence=LOW", result.stdout)


if __name__ == "__main__":
    unittest.main()
