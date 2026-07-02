#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

# ================================================
# CROSSOVER PATCHER
# BY PREXRY
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

APP_BUNDLE="$(cd "${CO_DIR}/../.." && pwd)"
APP_VERSION="$(defaults read "${APP_BUNDLE}/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo unknown)"
echo "Detected CrossOver version: ${APP_VERSION}"
echo "Bundle: ${APP_BUNDLE}"

echo ""
echo "Select an option:"
echo "1) Reset Trial (14 days - Plist Method)"
echo "2) Set Trial to 9999 days (Dylib Injection Method - RECOMMENDED)"
echo "3) Uninstall / Restore Original"
read -r -p "Choice (1-3): " OPTION

if [[ ! "$OPTION" =~ ^[1-3]$ ]]; then
    echo "Invalid option. Exiting."
    exit 1
fi

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
    echo "Stopping ${PROC_NAME}..."
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

cd "${CO_DIR}"
stop_proc "$$" "${PPID:-0}"
clean_bottles

if [ "$OPTION" == "3" ]; then
    if [ -f "${CO_DIR}/CrossOver.origin" ]; then
        mv -f "${CO_DIR}/CrossOver.origin" "${CO_DIR}/CrossOver"
        echo "Restored original CrossOver binary."
    else
        echo "No backup found. CrossOver appears to be unpatched."
    fi
    rm -f "${CO_DIR}/hook.dylib" 2>/dev/null || true
    echo "Uninstall complete."
    exit 0
fi

if [ ! -f "${CO_DIR}/CrossOver.origin" ]; then
  if [ ! -f "${CO_DIR}/CrossOver" ]; then
    echo "No CrossOver binary at ${CO_DIR}/CrossOver" >&2
    exit 1
  fi
  if file "${CO_DIR}/CrossOver" 2>/dev/null | grep -q 'Mach-O'; then
    echo "Preserving original CrossOver -> CrossOver.origin"
    if ! mv "${CO_DIR}/CrossOver" "${CO_DIR}/CrossOver.origin"; then
      echo "Failed to rename CrossOver to CrossOver.origin (permission denied?)" >&2
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

target="${CO_DIR}/CrossOver"
tmp="${target}.new"

if [ "$OPTION" == "1" ]; then
  echo "Writing Plist wrapper..."
  cat > "${tmp}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

CO_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$HOME/Library/Logs/CrossOver-wrapper.log"
PLIST="$HOME/Library/Preferences/com.codeweavers.CrossOver.plist"
FIRSTRUN="$(date -u -v -3H '+%Y-%m-%dT%TZ' 2>/dev/null || date -u -d '3 hours ago' '+%Y-%m-%dT%TZ' 2>/dev/null || true)"
SUCHECK="$(date -u -v -3H '+%Y-%m-%dT%TZ' 2>/dev/null || date -u -d '3 hours ago' '+%Y-%m-%dT%TZ' 2>/dev/null || true)"

if [ -n "${FIRSTRUN}" ] && [ -n "${SUCHECK}" ]; then
  [ -f "${PLIST}" ] || plutil -create xml1 "${PLIST}" 2>/dev/null || true
  plutil -replace FirstRunDate -date "${FIRSTRUN}" "${PLIST}" 2>>"${LOG_FILE}" || true
  plutil -replace SULastCheckTime -date "${SUCHECK}" "${PLIST}" 2>>"${LOG_FILE}" || true
fi

exec "${CO_DIR}/CrossOver.origin" "$@" >>"${LOG_FILE}" 2>&1
EOF

elif [ "$OPTION" == "2" ]; then

  if ! command -v clang >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then
      echo ""
      echo "==============================================="
      echo "xcli tools not found!"
      echo "They are required to compile the patch."
      echo "A prompt should appear on your screen shortly."
      echo "==============================================="
      xcode-select --install || true
      echo ""
      read -r -p "Press [Enter] ONLY AFTER the installation finishes to continue..."
  fi

  echo "Compiling Dylib Hook..."
  
  cat > "${CO_DIR}/hook.m" <<'EOF'
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

void swizzle(Class targetClass, char* selectorName, id block, char* types) {
  if (!targetClass) return;
  SEL selector = sel_registerName(selectorName);
  class_replaceMethod(targetClass, selector, imp_implementationWithBlock(block), types);
}

__attribute__((constructor)) static void setup() {
  swizzle(objc_getClass("CXApplication"), "isLicensed", ^BOOL(id self) { return YES; }, "B@:");
  swizzle(objc_getClass("CXApplication"), "isTrial", ^BOOL(id self) { return NO; }, "B@:");
  swizzle(objc_getClass("CXApplication"), "daysLeft", ^NSInteger(id self) { return 9999; }, "q@:");

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
      Class demoUtils = nil;
      for (int i = 0; i < 100; i++) {
        demoUtils = objc_lookUpClass("DemoUtils");
        if (demoUtils) {
          swizzle(demoUtils, "demoStatusForLicenseFile:andSig:", ^id(id self, id lic, id sig) { return @[ @NO, @"crazy", @"2099-01-01", @"i was crazy once", @NO ]; }, "@@:@@");
          break;
        }
        usleep(100000);
      }
  });

  Class nagClass = objc_getClass("DemoNagController");
  if (nagClass) {
    swizzle(nagClass, "showWindow:", ^void(id self, id sender) {
        if ([self respondsToSelector:@selector(runapp:)]) {
          [self performSelector:@selector(runapp:) withObject:nil];
        }
    }, "v@:@");
  }
  
  swizzle(objc_getClass("DemoBaseController"), "setExpirationText:", ^void(id self, id text) {}, "v@:@");
}
EOF
  clang -dynamiclib -framework Foundation -o "${CO_DIR}/hook.dylib" "${CO_DIR}/hook.m"
  rm "${CO_DIR}/hook.m"

  echo "Writing Dylib injection wrapper..."
  cat > "${tmp}" <<'EOF'
#!/usr/bin/env bash
CO_DIR="$(cd "$(dirname "$0")" && pwd)"
export DYLD_INSERT_LIBRARIES="${CO_DIR}/hook.dylib"
exec "${CO_DIR}/CrossOver.origin" "$@"
EOF
fi

chmod +x "${tmp}"
mv -f "${tmp}" "${target}"
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true

echo "==============================================="
echo "Done! CrossOver has been patched."
echo "BY PREXRY"
echo "==============================================="
