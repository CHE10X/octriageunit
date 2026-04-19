#!/usr/bin/env bash
# triage installer — works both from a cloned repo AND via curl pipe
#
# From repo:  bash scripts/install.sh [--user] [--verify-from-source] [--uninstall]
# Via curl:   curl -fsSL https://raw.githubusercontent.com/acmeagentsupply/triage/main/scripts/install.sh | bash
#
# SAFE: never modifies system config, restarts services, or writes outside install dir.

set -eo pipefail

REPO="https://github.com/acmeagentsupply/triage.git"
RAW="https://raw.githubusercontent.com/acmeagentsupply/triage/main"
BINARY_NAME="triage"
ALIAS_NAMES=("OCTriage" "octriageunit")
SYSTEM_PREFIX="/usr/local/bin"
USER_PREFIX="${HOME}/.local/bin"

# ── Helpers ──────────────────────────────────────────────────────────────────

info()  { printf '  \033[34m•\033[0m %s\n' "$*"; }
ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }
die()   { fail "$*"; exit 1; }

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else echo "unavailable"; fi
}

# Detect version — from local VERSION file or GitHub
get_version() {
  local src_dir="${1:-}"
  if [[ -n "$src_dir" && -f "${src_dir}/VERSION" ]]; then
    cat "${src_dir}/VERSION" | tr -d '[:space:]'
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "${RAW}/VERSION" 2>/dev/null | tr -d '[:space:]' || echo "unknown"
  else
    echo "unknown"
  fi
}

print_header() {
  local ver="${1:-}"
  printf '\n\033[1mtriage%s — Installer\033[0m\n' "${ver:+ v${ver}}"
  printf '  Read-only triage tool | No telemetry | Local-only | No gateway sidecar required\n\n'
}

# ── Detect execution context ─────────────────────────────────────────────────

# BASH_SOURCE[0] is empty/unset when the script is piped from curl
SCRIPT_FILE="${BASH_SOURCE:-}" ; SCRIPT_FILE="${SCRIPT_FILE%% *}"
REPO_ROOT=""
if [[ -n "$SCRIPT_FILE" && -f "$SCRIPT_FILE" ]]; then
  REPO_ROOT="$(cd "$(dirname "$SCRIPT_FILE")/.." 2>/dev/null && pwd)" || REPO_ROOT=""
fi

# If we have a repo root with the binary, use it; otherwise fetch from GitHub
SRC_BINARY=""
if [[ -n "$REPO_ROOT" && -f "${REPO_ROOT}/bin/control-plane-triage" ]]; then
  SRC_BINARY="${REPO_ROOT}/bin/control-plane-triage"
fi

copy_support_file() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")" || die "Cannot create directory for: ${dest}"
  cp "$src" "$dest" || die "Cannot copy support file to: ${dest}"
}

download_support_file() {
  local rel="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")" || die "Cannot create directory for: ${dest}"
  curl -fsSL "${RAW}/${rel}" -o "$dest" 2>/dev/null || die "Download failed: ${rel}"
}

install_support_tree() {
  local prefix="$1"
  local root support_lib collectors_dir collector src dest

  root="$(cd "${prefix}/.." && pwd)"
  support_lib="${root}/lib"
  collectors_dir="${support_lib}/collectors.d"

  mkdir -p "${collectors_dir}" || die "Cannot create support directory: ${collectors_dir}"

  if [[ -n "$REPO_ROOT" ]]; then
    copy_support_file "${REPO_ROOT}/VERSION" "${root}/VERSION"
    copy_support_file "${REPO_ROOT}/lib/status_reduce.sh" "${support_lib}/status_reduce.sh"
    if [[ -f "${REPO_ROOT}/lib/format.sh" ]]; then
      copy_support_file "${REPO_ROOT}/lib/format.sh" "${support_lib}/format.sh"
    fi
    while IFS= read -r src; do
      [[ -f "${src}" ]] || continue
      dest="${collectors_dir}/$(basename "${src}")"
      copy_support_file "${src}" "${dest}"
    done < <(find "${REPO_ROOT}/lib/collectors.d" -maxdepth 1 -type f -name '*.sh' | sort)
  else
    download_support_file "VERSION" "${root}/VERSION"
    download_support_file "lib/status_reduce.sh" "${support_lib}/status_reduce.sh"
    download_support_file "lib/format.sh" "${support_lib}/format.sh"
    for collector in 10_gateway.sh 20_sessions.sh 30_digest.sh 50_disk.sh 60_verify.sh; do
      download_support_file "lib/collectors.d/${collector}" "${collectors_dir}/${collector}"
    done
  fi
}

# ── Self-test ────────────────────────────────────────────────────────────────

run_self_test() {
  local bin="$1"
  local runtime_root runtime_status runtime_collector
  info "Running self-test on installed binary..."
  bash -n "$bin" 2>/dev/null || die "Syntax check failed on installed binary"
  ok "Syntax check passed"
  local ver; ver="$("$bin" --version 2>/dev/null)" || die "--version flag failed"
  ok "--version: ${ver}"
  "$bin" --help 2>/dev/null | grep -q "Read-only" || die "--help missing safety guarantees"
  ok "--help prints safety guarantees"
  runtime_root="$(cd "$(dirname "$bin")/.." && pwd)"
  runtime_status="${runtime_root}/lib/status_reduce.sh"
  [[ -f "${runtime_status}" ]] || die "Missing runtime support file: ${runtime_status}"
  for runtime_collector in 10_gateway.sh 20_sessions.sh 30_digest.sh 50_disk.sh 60_verify.sh; do
    [[ -f "${runtime_root}/lib/collectors.d/${runtime_collector}" ]] || die "Missing collector: ${runtime_collector}"
  done
  ok "Runtime support files installed"
  local alias_path alias
  for alias in "${ALIAS_NAMES[@]}"; do
    alias_path="$(dirname "$bin")/${alias}"
    [[ -L "${alias_path}" ]] || die "Missing deprecated alias: ${alias_path}"
    "${alias_path}" --help 2>&1 | grep -q 'Deprecated, use `triage`' || die "Alias ${alias} missing deprecation notice"
    ok "Alias ${alias} prints deprecation notice"
  done
  ok "Self-test passed"
  info "Baseline gateway health is probed directly by triage; sidecar telemetry is optional"
}

# ── Verify from source ───────────────────────────────────────────────────────

run_verify_from_source() {
  local install_dir="${1:-${SYSTEM_PREFIX}}"
  local installed="${install_dir}/${BINARY_NAME}"
  printf '\n\033[1mVerify-From-Source\033[0m\n'
  [[ -f "$installed" ]] || die "triage not found at ${installed} — install first"

  local src_hash installed_hash
  if [[ -n "$SRC_BINARY" ]]; then
    src_hash="$(sha256_file "${SRC_BINARY}")"
  else
    info "Fetching source binary for comparison..."
    local tmp; tmp="$(mktemp /tmp/oct_verify_XXXXXX)"
    curl -fsSL "${RAW}/bin/control-plane-triage" -o "$tmp" 2>/dev/null || die "Could not fetch source binary"
    src_hash="$(sha256_file "$tmp")"
    rm -f "$tmp"
  fi
  installed_hash="$(sha256_file "${installed}")"
  info "Source SHA256:    ${src_hash}"
  info "Installed SHA256: ${installed_hash}"
  [[ "$src_hash" == "$installed_hash" ]] && { ok "SHA256 MATCH — installed binary matches source"; return 0; }
  fail "SHA256 MISMATCH"; return 1
}

# ── Install ──────────────────────────────────────────────────────────────────

do_install() {
  local prefix="$1"
  local dest="${prefix}/${BINARY_NAME}"
  local checksum_file="${dest}.sha256"
  local alias alias_path
  local ver

  mkdir -p "$prefix" || die "Cannot create directory: ${prefix}"

  if [[ -n "$SRC_BINARY" ]]; then
    # From repo
    ver="$(get_version "$REPO_ROOT")"
    cp "$SRC_BINARY" "$dest" || die "Cannot copy to: ${dest}"
  else
    # From GitHub (curl-pipe mode)
    info "Downloading binary from GitHub..."
    ver="$(get_version)"
    curl -fsSL "${RAW}/bin/control-plane-triage" -o "$dest" 2>/dev/null || die "Download failed"
  fi

  install_support_tree "$prefix"
  chmod +x "$dest" || die "Cannot chmod: ${dest}"
  for alias in "${ALIAS_NAMES[@]}"; do
    alias_path="${prefix}/${alias}"
    ln -sfn "${BINARY_NAME}" "${alias_path}" || die "Cannot create alias: ${alias_path}"
  done
  printf '%s  %s\n' "$(sha256_file "${dest}")" "$(basename "${dest}")" > "${checksum_file}" || die "Cannot write checksum: ${checksum_file}"
  ok "Installed: ${dest}"
  ok "Aliases:   ${prefix}/OCTriage, ${prefix}/octriageunit"
  ok "Version:   ${ver}"
  ok "SHA256:    $(sha256_file "${dest}")"
  run_self_test "$dest"
  printf '\n  Run: \033[1mtriage --help\033[0m\n\n'
}

# ── Uninstall ────────────────────────────────────────────────────────────────

  do_uninstall() {
  local removed=0
  local alias
  for prefix in "${SYSTEM_PREFIX}" "${USER_PREFIX}"; do
    local dest="${prefix}/${BINARY_NAME}"
    local checksum_file="${dest}.sha256"
    local root="$(cd "${prefix}/.." && pwd)"
    if [[ -f "$dest" ]]; then
      rm -f "$dest"; ok "Removed: ${dest}"; removed=$((removed+1))
    fi
    for alias in "${ALIAS_NAMES[@]}"; do
      if [[ -L "${prefix}/${alias}" || -f "${prefix}/${alias}" ]]; then
        rm -f "${prefix}/${alias}"
        ok "Removed: ${prefix}/${alias}"
        removed=$((removed+1))
      fi
    done
    [[ -f "${checksum_file}" ]] && rm -f "${checksum_file}"
    [[ -f "${root}/VERSION" ]] && rm -f "${root}/VERSION"
    [[ -f "${root}/lib/status_reduce.sh" ]] && rm -f "${root}/lib/status_reduce.sh"
    [[ -f "${root}/lib/format.sh" ]] && rm -f "${root}/lib/format.sh"
    if [[ -d "${root}/lib/collectors.d" ]]; then
      rm -f "${root}/lib/collectors.d"/10_gateway.sh \
            "${root}/lib/collectors.d"/20_sessions.sh \
            "${root}/lib/collectors.d"/30_digest.sh \
            "${root}/lib/collectors.d"/50_disk.sh \
            "${root}/lib/collectors.d"/60_verify.sh \
            "${root}/lib/collectors.d"/70_doctor.sh \
            "${root}/lib/collectors.d"/70_doctor.sh.retired
    fi
  done
  [[ $removed -eq 0 ]] && info "Nothing to remove (triage not found in standard locations)"
  info "Proof bundles in ~/triage-bundles/ are NOT removed (your data)"
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  local arg="${1:-}"
  local ver; ver="$(get_version "${REPO_ROOT:-}")"
  print_header "$ver"

  case "$arg" in
    --user)
      info "Installing to ${USER_PREFIX} (user install, no sudo required)"
      do_install "${USER_PREFIX}"
      ;;
    --verify-from-source)
      local prefix="${SYSTEM_PREFIX}"
      [[ "${2:-}" == "--user" ]] && prefix="${USER_PREFIX}"
      run_verify_from_source "${prefix}"
      ;;
    --uninstall)
      do_uninstall
      ;;
    --help|-h)
      printf 'Usage: bash scripts/install.sh [--user] [--verify-from-source] [--uninstall]\n'
      ;;
    "")
      if [[ -w "${SYSTEM_PREFIX}" ]]; then
        info "Installing to ${SYSTEM_PREFIX}"
        do_install "${SYSTEM_PREFIX}"
      else
        info "${SYSTEM_PREFIX} not writable — falling back to user install"
        do_install "${USER_PREFIX}"
      fi
      ;;
    *)
      die "Unknown argument: ${arg}"
      ;;
  esac
}

main "$@"
