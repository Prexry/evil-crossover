#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
# ================================================
# ORIGINAL BY santaklouse
# UPDATE AND EDIT BY PREXRY
# ================================================

PROC_NAME='CrossOver'

expand_path() {
  local p="$1"
  p="${p/#\~/$HOME}"
  p="${p%/}"
  printf '%s' "$p"
}

CO_DIR="$(expand_path "$HOME/Applications/CrossOver.app/Contents/MacOS")"
test -d "${CO_DIR}" || CO_DIR="/Applications/CrossOver.app/Contents/MacOS"

read -r -p "Please enter the path to CrossOver.app/Contents/MacOS (press Enter for default: ${CO_DIR}): " input_location || true
if [ -n "${input_location:-}" ]; then
  CO_DIR="$(expand_path "${input_location}")"
fi
if [ ! -d "${CO_DIR}" ]; then
  echo "Unable to detect app path. Exiting..." >&2
  exit 1
fi

read -r -p "Are you sure you want to run this script? (y/N): " confirm || exit 0
if [[ ! "${confirm:-}" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

APP_BUNDLE="$(cd "${CO_DIR}/../.." && pwd)"
APP_VERSION="$(defaults read "${APP_BUNDLE}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo unknown)"
echo "Detected CrossOver version: ${APP_VERSION}"
echo "Bundle: ${APP_BUNDLE}"

get_pids() {
  local self="${1:-0}" parent="${2:-0}"
  local raw=""
  if command -v pgrep >/dev/null 2>&1; then
    raw="$(pgrep -x "${PROC_NAME}" 2>/dev/null || true)"
  fi
  if [ -z "${raw}" ] && command -v pidof >/dev/null 2>&1; then
    raw="$(pidof "${PROC_NAME}" 2>/dev/null || true)"
  fi
  if [ -z "${raw}" ]; then
    raw="$(ps -Ac -o pid,comm | awk -v name="${PROC_NAME}" '$2==name {print $1}' || true)"
  fi
  printf '%s\n' "${raw}" | awk -v s="${self}" -v p="${parent}" 'NF && $1!=s && $1!=p {print $1}'
}

stop_proc() {
  local self="$1" parent="$2"
  local pids deadline
  pids="$(get_pids "${self}" "${parent}" | tr '\n' ' ')"
  pids="${pids%% }"; pids="${pids## }"
  if [ -n "${pids}" ] && [[ "${pids}" =~ ^[0-9\ ]+$ ]]; then
    echo "stopping ${PROC_NAME} pids: ${pids}"
    kill ${pids} >/dev/null 2>&1 || true
    deadline=$(( $(date +%s) + 8 ))
    while [ "$(date +%s)" -lt "${deadline}" ]; do
      pids="$(get_pids "${self}" "${parent}" | tr '\n' ' ')"
      pids="${pids%% }"; pids="${pids## }"
      [ -z "${pids}" ] && break
      sleep 0.5
    done
    if [ -n "${pids}" ] && [[ "${pids}" =~ ^[0-9\ ]+$ ]]; then
      echo "force killing ${PROC_NAME} pids: ${pids}"
      kill -9 ${pids} >/dev/null 2>&1 || true
    fi
  fi
}

clean_bottles() {
  local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
  [ -d "${bottles}" ] || return 0
  local f d ts
  ts="$(date +%Y%m%d%H%M%S)"
  for f in "${bottles}"/*/system.reg; do
    [ -f "${f}" ] || continue
    cp -p "${f}" "${f}.bak.${ts}" 2>/dev/null || true
    LC_ALL=C awk '
      BEGIN { skip=0 }
      /^\[Software\\\\CodeWeavers\\\\CrossOver\\\\cxoffice\]/ { skip=1; next }
      skip==1 && /^\[/ { skip=0 }
      skip==0 { print }
    ' "${f}" > "${f}.tmp" && mv "${f}.tmp" "${f}"
  done
  for d in "${bottles}"/*; do
    [ -d "${d}" ] || continue
    rm -rf "${d}/.eval" "${d}/.update-timestamp" 2>/dev/null || true
  done
}

write_wrapper() {
  local target="${CO_DIR}/CrossOver"
  local tmp="${target}.new"
  cat > "${tmp}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
# ================================================
# ORIGINAL BY santaklouse
# UPDATE AND EDIT BY PREXRY
# ================================================
PROC_NAME='CrossOver'
CO_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="${LOG_DIR}/CrossOver-wrapper.log"
mkdir -p "${LOG_DIR}"
touch "${LOG_FILE}" && chmod 600 "${LOG_FILE}" || true

get_pids() {
  local self="${1:-0}" parent="${2:-0}"
  local raw=""
  if command -v pgrep >/dev/null 2>&1; then
    raw="$(pgrep -x "${PROC_NAME}" 2>/dev/null || true)"
  fi
  if [ -z "${raw}" ] && command -v pidof >/dev/null 2>&1; then
    raw="$(pidof "${PROC_NAME}" 2>/dev/null || true)"
  fi
  if [ -z "${raw}" ]; then
    raw="$(ps -Ac -o pid,comm | awk -v name="${PROC_NAME}" '$2==name {print $1}' || true)"
  fi
  printf '%s\n' "${raw}" | awk -v s="${self}" -v p="${parent}" 'NF && $1!=s && $1!=p {print $1}'
}

stop_proc() {
  local self="$1" parent="$2"
  local pids deadline
  pids="$(get_pids "${self}" "${parent}" | tr '\n' ' ')"
  pids="${pids%% }"; pids="${pids## }"
  if [ -n "${pids}" ] && [[ "${pids}" =~ ^[0-9\ ]+$ ]]; then
    kill ${pids} >/dev/null 2>&1 || true
    deadline=$(( $(date +%s) + 8 ))
    while [ "$(date +%s)" -lt "${deadline}" ]; do
      pids="$(get_pids "${self}" "${parent}" | tr '\n' ' ')"
      pids="${pids%% }"; pids="${pids## }"
      [ -z "${pids}" ] && break
      sleep 0.5
    done
    if [ -n "${pids}" ] && [[ "${pids}" =~ ^[0-9\ ]+$ ]]; then
      kill -9 ${pids} >/dev/null 2>&1 || true
    fi
  fi
}

clean_bottles() {
  local bottles="$HOME/Library/Application Support/CrossOver/Bottles"
  [ -d "${bottles}" ] || return 0
  local f d ts
  ts="$(date +%Y%m%d%H%M%S)"
  for f in "${bottles}"/*/system.reg; do
    [ -f "${f}" ] || continue
    cp -p "${f}" "${f}.bak.${ts}" 2>/dev/null || true
    LC_ALL=C awk '
      BEGIN { skip=0 }
      /^\[Software\\\\CodeWeavers\\\\CrossOver\\\\cxoffice\]/ { skip=1; next }
      skip==1 && /^\[/ { skip=0 }
      skip==0 { print }
    ' "${f}" > "${f}.tmp" && mv "${f}.tmp" "${f}"
  done
  for d in "${bottles}"/*; do
    [ -d "${d}" ] || continue
    rm -rf "${d}/.eval" "${d}/.update-timestamp" 2>/dev/null || true
  done
}

stop_proc "$$" "${PPID:-0}"

PLIST="$HOME/Library/Preferences/com.codeweavers.CrossOver.plist"
DATETIME="$(date -u -v -3H '+%Y-%m-%dT%TZ' 2>/dev/null || date -u -d '3 hours ago' '+%Y-%m-%dT%TZ' 2>/dev/null || true)"
if [ -n "${DATETIME}" ]; then
  [ -f "${PLIST}" ] || plutil -create xml1 "${PLIST}" 2>/dev/null || true
  if plutil -replace FirstRunDate -date "${DATETIME}" "${PLIST}" 2>>"${LOG_FILE}" \
     && plutil -replace SULastCheckTime -date "${DATETIME}" "${PLIST}" 2>>"${LOG_FILE}"; then
    /usr/bin/osascript -e "display notification \"trial fixed: date changed to ${DATETIME}\"" >/dev/null 2>&1 || true
  else
    echo "warning: plutil update failed" >>"${LOG_FILE}"
  fi
fi

clean_bottles

echo "---- $(date) launching from ${CO_DIR} ----" >>"${LOG_FILE}"

if [ -x "${CO_DIR}/CrossOver.origin" ]; then
  exec "${CO_DIR}/CrossOver.origin" "$@" >>"${LOG_FILE}" 2>&1
else
  echo "no CrossOver.origin binary found in ${CO_DIR}" >>"${LOG_FILE}"
  exit 1
fi
EOF
  chmod +x "${tmp}"
  mv "${tmp}" "${target}"
}

cleanup_partial() {
  local rc=$?
  if [ ${rc} -ne 0 ]; then
    if [ -f "${CO_DIR}/CrossOver.origin" ] && [ ! -x "${CO_DIR}/CrossOver" ]; then
      echo "rolling back: restoring CrossOver.origin -> CrossOver" >&2
      mv -f "${CO_DIR}/CrossOver.origin" "${CO_DIR}/CrossOver" || true
    fi
    rm -f "${CO_DIR}/CrossOver.new" 2>/dev/null || true
  fi
}
trap cleanup_partial EXIT

cd "${CO_DIR}"

stop_proc "$$" "${PPID:-0}"
clean_bottles

if [ ! -f "${CO_DIR}/CrossOver.origin" ]; then
  if [ ! -f "${CO_DIR}/CrossOver" ]; then
    echo "no CrossOver binary at ${CO_DIR}/CrossOver" >&2
    exit 1
  fi
  if file "${CO_DIR}/CrossOver" 2>/dev/null | grep -q 'Mach-O'; then
    echo "preserving original CrossOver -> CrossOver.origin"
    if ! mv "${CO_DIR}/CrossOver" "${CO_DIR}/CrossOver.origin"; then
      echo "failed to rename CrossOver to CrossOver.origin (permission denied?)" >&2
      exit 1
    fi
  else
    echo "${CO_DIR}/CrossOver is not a Mach-O binary; refusing to proceed" >&2
    exit 1
  fi
fi

if [ ! -x "${CO_DIR}/CrossOver.origin" ]; then
  echo "CrossOver.origin is not executable; refusing to proceed" >&2
  exit 1
fi

write_wrapper

xattr -cr "${APP_BUNDLE}" 2>/dev/null || true

trap - EXIT

echo "Done. CrossOver wrapper written/updated at: ${CO_DIR}/CrossOver"
echo "Logs: ~/Library/Logs/CrossOver-wrapper.log"
echo "==============================================="
echo "ORIGINAL BY santaklouse"
echo "UPDATE & EDIT BY PREXRY"
echo "==============================================="
