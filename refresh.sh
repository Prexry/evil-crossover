#!/usr/bin/env bash
set -euo pipefail

# ================================================
# ORIGINAL BY santaklouse
# UPDATE AND EDIT BY PREXRY
# ================================================


CO_PWD=~/Applications/CrossOver.app/Contents/MacOS
test -d "${CO_PWD}" || CO_PWD=/Applications/CrossOver.app/Contents/MacOS

read -p "Please enter the path to CrossOver.app/Contents/MacOS (press Enter for default: ${CO_PWD}): " input_location
CO_PWD="${input_location:-$CO_PWD}"

if [ ! -d "${CO_PWD}" ]; then
  echo "Unable to detect app path. Exiting..."
  exit 1
fi

read -p "Are you sure you want to run this script? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

cd "${CO_PWD}"

PROC_NAME='CrossOver'

get_pids() {
  local out=""
  if command -v pgrep >/dev/null 2>&1; then
    out="$(pgrep -x "${PROC_NAME}" || true)"
  fi
  if [ -z "${out}" ] && command -v pidof >/dev/null 2>&1; then
    out="$(pidof "${PROC_NAME}" || true)"
  fi
  if [ -z "${out}" ]; then
    out="$(ps -Ac -o pid,comm | awk -v name="${PROC_NAME}" '$2==name {print $1}' || true)"
  fi
  echo "${out}" | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

pids="$(get_pids)"

if [ -n "${pids}" ]; then
  echo "killing existing ${PROC_NAME} pids: ${pids}"
  kill -9 ${pids} > /dev/null 2>&1 || true
fi

for i in ~/Library/Application\ Support/CrossOver/Bottles/*/system.reg; do
    if [ -f "$i" ]; then
        sed -i '' '/^\[Software\\\\CodeWeavers\\\\CrossOver\\\\cxoffice\]/,/^$/d' "$i"
    fi
done

for i in ~/Library/Application\ Support/CrossOver/Bottles/*; do
    if [ -d "$i" ]; then
        rm -rf "$i/.eval" "$i/.update-timestamp" || true
    fi
done

create_wrapper() {
  cat > CrossOver <<'EOF'
#!/usr/bin/env bash
PIDOF="$(which pidof 2>/dev/null || true)"
if [ -z "${PIDOF}" ]; then
  echo "pidof not found; falling back to pgrep/ps if needed"
fi

CO_PWD=~/Applications/CrossOver.app/Contents/MacOS
test -d "${CO_PWD}" || CO_PWD=/Applications/CrossOver.app/Contents/MacOS

test -d "${CO_PWD}" || (echo 'unable to detect app path. exiting...' && exit)

PWD="${CO_PWD}"
cd "${PWD}"

PROC_NAME='CrossOver'

pids="$(pgrep -x "${PROC_NAME}" 2>/dev/null || true)"
if [ -z "${pids}" ] && command -v pidof >/dev/null 2>&1; then
  pids="$(pidof "${PROC_NAME}" 2>/dev/null || true)"
fi
if [ -z "${pids}" ]; then
  pids="$(ps -Ac -o pid,comm | awk -v name="${PROC_NAME}" '$2==name {print $1}' || true)"
fi

[ "${pids}" ] && kill -9 ${pids} > /dev/null 2>&1 || true

sleep 3

DATETIME="$(date -u -v -3H '+%Y-%m-%dT%TZ')"

plutil -replace FirstRunDate -date "${DATETIME}" ~/Library/Preferences/com.codeweavers.CrossOver.plist || true
plutil -replace SULastCheckTime -date "${DATETIME}" ~/Library/Preferences/com.codeweavers.CrossOver.plist || true

/usr/bin/osascript -e "display notification \"trial fixed: date changed to ${DATETIME}\""

for i in ~/Library/Application\ Support/CrossOver/Bottles/*/system.reg; do
    if [ -f "$i" ]; then
        sed -i '' '/^\[Software\\\\CodeWeavers\\\\CrossOver\\\\cxoffice\]/,/^$/d' "$i"
    fi
done

for i in ~/Library/Application\ Support/CrossOver/Bottles/*; do
    if [ -d "$i" ]; then
        rm -rf "$i/.eval" "$i/.update-timestamp" || true
    fi
done

echo "${PWD}" > /tmp/co_log.log

if [ -x "${PWD}/CrossOver.origin" ]; then
  "${PWD}/CrossOver.origin" >> /tmp/co_log.log 2>&1 &
else
  if [ -x "${PWD}/CrossOver" ]; then
    "${PWD}/CrossOver" >> /tmp/co_log.log 2>&1 &
  fi
fi
EOF

  chmod +x CrossOver
}

if [ ! -f CrossOver.origin ] && [ -f CrossOver ]; then
  echo "preserving original CrossOver -> CrossOver.origin"
  mv CrossOver CrossOver.origin
fi

create_wrapper
echo "Done. CrossOver wrapper written/updated at: ${CO_PWD}/CrossOver"
echo "Please open CrossOver (it will launch the original in background and log to /tmp/co_log.log)"

echo "==============================================="
echo "ORIGINAL BY santaklouse"
echo "UPDATE & EDIT BY PREXRY"
echo "==============================================="
