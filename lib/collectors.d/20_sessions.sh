COLLECTOR_ID="sessions"
COLLECTOR_LABEL="Sessions"

collector_run() {
  local bundle_dir="$1"
  local sessions_root="${HOME}/.openclaw/agents"
  local agents=0 total=0 recent=0 orphan=0
  local active="unknown"
  local classification="UNKNOWN"
  local lineage="OK"
  local artifact_state="OK"
  local confidence="HIGH"
  local agent_dirs=0

  if [[ ! -d "${sessions_root}" ]]; then
    cat > "${bundle_dir}/agent_session_topology.txt" <<EOF
agents: 0
sessions_total: 0
sessions_recent: 0
orphan_transcripts: 0
active_sessions: unknown
agent_lineage: UNKNOWN
max_context_usage: unknown
classification: UNKNOWN
artifact_state: OK
confidence: MEDIUM
EOF
    COLLECTOR_META_COMMAND="sessions.json index"
    COLLECTOR_META_EXIT_CODE="0"
    COLLECTOR_META_TIMED_OUT="false"
    COLLECTOR_META_BYTES_CAPTURED="$(octu_file_bytes "${bundle_dir}/agent_session_topology.txt")"
    COLLECTOR_META_CONFIDENCE="MEDIUM"
    COLLECTOR_META_ARTIFACT_STATE="OK"
    COLLECTOR_META_RESULT_STATE="UNKNOWN"
    printf 'collector_status id=%s state=UNKNOWN agents=0 recent=0 orphan=0 total=0 lineage=UNKNOWN artifact_state=OK confidence=MEDIUM\n' "$COLLECTOR_ID"
    return 20
  fi

  # Enumerate sessions via sessions.json index files (canonical per Archer verdict 2026-04-13)
  # sessions.json is a dict: {session_key: {updatedAt: ms, ...}}
  # .jsonl files are content-only ground truth — do not walk them for enumeration
  local enum_result
  enum_result="$(python3 -c "
import json, glob, os, time

sessions_root = os.path.expanduser('${sessions_root}')
cutoff_ms = int((time.time() - 3600) * 1000)
agents = total = recent = 0
agent_dirs = 0

for agent_dir in sorted(glob.glob(sessions_root + '/*')):
    if os.path.basename(agent_dir) == '_orphaned_sessions' or not os.path.isdir(agent_dir):
        continue
    agent_dirs += 1

for idx in sorted(glob.glob(sessions_root + '/*/sessions/sessions.json')):
    agents += 1
    try:
        with open(idx) as f:
            d = json.load(f)
        if isinstance(d, dict):
            for sk, sv in d.items():
                if not isinstance(sv, dict):
                    continue
                total += 1
                ua = sv.get('updatedAt', 0)
                if isinstance(ua, (int, float)) and ua > cutoff_ms:
                    recent += 1
    except Exception:
        pass

# Orphans: files in _orphaned_sessions dir (informational only)
orphan = len(glob.glob(sessions_root + '/_orphaned_sessions/*.jsonl'))
print(agents, total, recent, orphan, agent_dirs)
" 2>/dev/null || echo "0 0 0 0")"
  read -r agents total recent orphan agent_dirs <<< "${enum_result}"

  # Classification — orphan count is informational only (Archer verdict 2026-04-13)
  # FANOUT_ANOMALY threshold raised to 500 — 105 sessions across 33 agents is normal
  if (( total > 500 )); then
    classification="FANOUT_ANOMALY"
  elif (( recent > 50 )); then
    classification="HIGH_ACTIVITY"
  elif (( agents > 0 )); then
    classification="NORMAL"
  elif (( agent_dirs > 0 )); then
    classification="INCOMPLETE"
    lineage="UNKNOWN"
    artifact_state="PARTIAL"
    confidence="LOW"
  fi

  cat > "${bundle_dir}/agent_session_topology.txt" <<EOF
agents: ${agents}
sessions_total: ${total}
sessions_recent: ${recent}
orphan_transcripts: ${orphan}
active_sessions: ${active}
agent_lineage: ${lineage}
max_context_usage: unknown
classification: ${classification}
artifact_state: ${artifact_state}
confidence: ${confidence}
EOF

  local bytes_captured
  bytes_captured="$(octu_file_bytes "${bundle_dir}/agent_session_topology.txt")"
  COLLECTOR_META_COMMAND="sessions.json index"
  COLLECTOR_META_EXIT_CODE="0"
  COLLECTOR_META_TIMED_OUT="false"
  COLLECTOR_META_BYTES_CAPTURED="${bytes_captured}"
  COLLECTOR_META_CONFIDENCE="${confidence}"
  COLLECTOR_META_ARTIFACT_STATE="${artifact_state}"
  COLLECTOR_META_RESULT_STATE="${classification}"

  printf 'collector_status id=%s state=%s agents=%s recent=%s orphan=%s total=%s lineage=%s artifact_state=%s confidence=%s\n' \
    "$COLLECTOR_ID" "$classification" "$agents" "$recent" "$orphan" "$total" "$lineage" "$artifact_state" "$confidence"
  case "$classification" in
    NORMAL) return 0 ;;
    UNKNOWN) return 20 ;;
    *) return 10 ;;
  esac
}
