COLLECTOR_ID="gateway"
COLLECTOR_LABEL="Gateway"

collector_run() {
  local bundle_dir="$1"
  local enrichment_json="${HOME}/openclaw/health/gateway_health.json"
  local enrichment_txt="${HOME}/openclaw/health/gateway_health.txt"
  local err_log="${HOME}/.openclaw/ops/logs/gateway.err.log"
  local gw_log="${HOME}/.openclaw/ops/logs/gateway.log"
  local state="UNKNOWN"
  local note=""
  local probe_target=""
  local artifact_state="OK"
  local confidence="HIGH"
  local telemetry_state="UNAVAILABLE"
  local telemetry_note="telemetry_missing"
  local probe_result probe_note probe_http_code probe_latency_ms probe_path probe_curl_rc
  local telemetry_raw_status telemetry_latency_ms telemetry_file_age_secs

  probe_target="$(octu_gateway_base_url)"

  # Copy log tails for evidence
  if collect_log_window "${err_log}" "${bundle_dir}/gateway_err_tail.txt" 1; then :; else
    printf 'gateway.err.log not found at %s\n' "${err_log}" > "${bundle_dir}/gateway_err_tail.txt"
  fi
  if collect_log_window "${gw_log}" "${bundle_dir}/gateway_log_tail.txt"; then :; else
    printf 'gateway.log not found at %s\n' "${gw_log}" > "${bundle_dir}/gateway_log_tail.txt"
  fi

  probe_result="$(octu_gateway_probe "${probe_target}" "${bundle_dir}/gateway_health.json" "${bundle_dir}/gateway_health.txt")"
  state="${probe_result%%|*}"
  probe_result="${probe_result#*|}"
  probe_note="${probe_result%%|*}"
  probe_result="${probe_result#*|}"
  probe_http_code="${probe_result%%|*}"
  probe_result="${probe_result#*|}"
  probe_latency_ms="${probe_result%%|*}"
  probe_result="${probe_result#*|}"
  probe_path="${probe_result%%|*}"
  probe_curl_rc="${probe_result##*|}"

  if [[ "${state}" == "DOWN" ]]; then
    artifact_state="PARTIAL"
    confidence="MEDIUM"
  elif [[ "${state}" == "WARN" ]]; then
    confidence="MEDIUM"
  fi

  # Optional enrichment: consume if present, but never let it replace baseline probe truth.
  if [[ -f "${enrichment_json}" ]]; then
    cp "${enrichment_json}" "${bundle_dir}/gateway_health_enrichment.json" 2>/dev/null || true
    [[ -f "${enrichment_txt}" ]] && cp "${enrichment_txt}" "${bundle_dir}/gateway_health_enrichment.txt" 2>/dev/null || true

    telemetry_raw_status="$(python3 -c "import json; d=json.load(open('${enrichment_json}')); print(d.get('status','UNKNOWN'))" 2>/dev/null || echo "__MALFORMED__")"
    telemetry_latency_ms="$(python3 -c "import json; d=json.load(open('${enrichment_json}')); v=d.get('latency_ms'); print(v if v else '')" 2>/dev/null || echo "")"
    telemetry_file_age_secs="$(python3 -c "
import os, time, json
try:
    mtime = os.path.getmtime('${enrichment_json}')
    print(int(time.time() - mtime))
except:
    print(9999)
" 2>/dev/null || echo "9999")"

    if [[ "${telemetry_raw_status}" == "__MALFORMED__" ]]; then
      telemetry_state="MALFORMED"
      telemetry_note="telemetry_malformed"
    elif (( telemetry_file_age_secs > 120 )); then
      telemetry_state="STALE"
      telemetry_note="telemetry_stale_${telemetry_file_age_secs}s"
    elif [[ "${telemetry_raw_status}" == "OK" || "${telemetry_raw_status}" == "FAIL" ]]; then
      telemetry_state="AVAILABLE"
      telemetry_note="telemetry_${telemetry_raw_status,,}"
      [[ -n "${telemetry_latency_ms}" ]] && telemetry_note="${telemetry_note}_${telemetry_latency_ms}ms"
    else
      telemetry_state="UNKNOWN"
      telemetry_note="telemetry_status_${telemetry_raw_status}"
    fi
  fi

  note="${probe_note}"
  [[ -n "${probe_latency_ms}" ]] && note="${note}_${probe_latency_ms}ms"
  note="${note};telemetry=${telemetry_state}"
  [[ -n "${probe_http_code}" && "${probe_http_code}" != "000" ]] && note="${note};http=${probe_http_code}"
  [[ -n "${telemetry_note}" ]] && note="${note};${telemetry_note}"

  {
    printf 'probe_target: %s\n' "${probe_target}"
    printf 'probe_path: %s\n' "${probe_path:-unknown}"
    printf 'probe_http_code: %s\n' "${probe_http_code:-000}"
    printf 'probe_latency_ms: %s\n' "${probe_latency_ms:-}"
    printf 'probe_curl_exit: %s\n' "${probe_curl_rc:-}"
    printf 'baseline_state: %s\n' "${state}"
    printf 'telemetry_state: %s\n' "${telemetry_state}"
    printf 'telemetry_note: %s\n' "${telemetry_note}"
  } > "${bundle_dir}/gateway_probe_meta.txt"

  local bytes_captured
  bytes_captured="$(octu_sum_file_bytes \
    "${bundle_dir}/gateway_health.json" \
    "${bundle_dir}/gateway_health_enrichment.json" \
    "${bundle_dir}/gateway_err_tail.txt" \
    "${bundle_dir}/gateway_probe_meta.txt")"
  COLLECTOR_META_COMMAND="gateway_probe"
  COLLECTOR_META_EXIT_CODE="0"
  COLLECTOR_META_TIMED_OUT="false"
  COLLECTOR_META_BYTES_CAPTURED="${bytes_captured}"
  COLLECTOR_META_CONFIDENCE="${confidence}"
  COLLECTOR_META_ARTIFACT_STATE="${artifact_state}"
  COLLECTOR_META_RESULT_STATE="${state}"

  printf 'collector_status id=%s state=%s note=%s probe_target=%s telemetry=%s artifact_state=%s confidence=%s\n' \
    "$COLLECTOR_ID" "$state" "$note" "$probe_target" "$telemetry_state" "$artifact_state" "$confidence"
  case "$state" in
    OK) return 0 ;;
    WARN) return 10 ;;
    DOWN) return 20 ;;
    *) return 20 ;;
  esac
}
