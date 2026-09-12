#!/usr/bin/env sh
# Standalone real-hardware test for the acme.sh JetKVM deploy hook
# (jetkvm.sh, alongside this script -- copied from
# https://github.com/daemonhorn/acme.sh/blob/deploy/jetkvm-ssh/deploy/jetkvm.sh
# a.k.a. PR https://github.com/acmesh-official/acme.sh/pull/7254).
#
# This does NOT touch the OPNsense firewall or acme.sh's own
# certificate-issuance machinery. It feeds jetkvm_deploy() a throwaway
# self-signed cert/key pair and runs it directly against a real JetKVM
# device over SSH, so it only proves out the hook's own upload / atomic
# rename / permissions / reboot-apply mechanics.
#
# Prerequisites on THIS machine (not the firewall):
#   - openssl, ssh
#   - Already-trusted SSH access to the device as JETKVM_USER (i.e. the
#     device's Developer Mode SSH key field already has a public key this
#     machine holds the private half of -- confirm with, e.g.:
#         ssh root@<device> true
#
# Usage: edit the CONFIG block below, then run:  sh run_jetkvm_test.sh

set -e

########################################################################
# CONFIG -- edit these before running
########################################################################

JETKVM_HOST="jetkvm"     # REQUIRED: device IP or hostname, e.g. "192.168.1.50"
JETKVM_USER="root" # JetKVM only supports "root" over SSH
JETKVM_PORT="22"

# Leave unset/empty for a full test (the device WILL reboot to apply the
# cert). Set to "none" for a dry run that only uploads the files without
# rebooting -- useful for a first pass before committing to a reboot.
RESTART_CMD=""

# Set to 1 to regenerate the throwaway test cert even if one already
# exists from a previous run (e.g. to test with a fresh expiry/serial).
FORCE_NEW_CERT=0

########################################################################
# End of config -- shouldn't need to edit below this line
########################################################################

_here="$(cd "$(dirname "$0")" && pwd)"
_hook="$_here/jetkvm.sh"

if [ -z "$JETKVM_HOST" ]; then
  echo "ERROR: set JETKVM_HOST at the top of this script before running." >&2
  exit 1
fi

if [ ! -f "$_hook" ]; then
  echo "ERROR: $_hook not found (expected alongside this script)." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR: openssl is required (used to generate the throwaway test cert)." >&2
  exit 1
fi

_test_key="$_here/test.key"
_test_crt="$_here/test.crt"

if [ "$FORCE_NEW_CERT" = "1" ] || [ ! -f "$_test_key" ] || [ ! -f "$_test_crt" ]; then
  echo "Generating a throwaway self-signed test certificate..."
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$_test_key" -out "$_test_crt" -days 1 -nodes \
    -subj "/CN=jetkvm-hook-test.invalid" 2>/dev/null
else
  echo "Reusing existing test cert/key ($_test_crt / $_test_key). Set FORCE_NEW_CERT=1 to regenerate."
fi

echo
echo "Pre-flight: confirming SSH access to $JETKVM_USER@$JETKVM_HOST:$JETKVM_PORT ..."
if ! ssh -p "$JETKVM_PORT" -o BatchMode=yes -o ConnectTimeout=8 "$JETKVM_USER@$JETKVM_HOST" true; then
  echo "ERROR: could not SSH to $JETKVM_USER@$JETKVM_HOST:$JETKVM_PORT non-interactively." >&2
  echo "Confirm the device's Developer Mode SSH key includes this machine's public key, then retry." >&2
  exit 1
fi
echo "SSH access OK."
echo

# --- minimal stand-ins for the acme.sh helper functions jetkvm.sh calls ---
# (real acme.sh provides these; we don't need the rest of acme.sh just to
# exercise this one hook function directly)
_debug() { :; }
_secure_debug() { echo "[secure_debug] $1"; }
_info() { echo "[info] $*"; }
_err() { echo "[err] $*" >&2; }
_mktemp() { mktemp; }
_getdeployconf() { :; }
_savedeployconf() { echo "[saved] $1=$2"; }

# shellcheck source=jetkvm.sh
. "$_hook"

export DEPLOY_JETKVM_HOST="$JETKVM_HOST"
export DEPLOY_JETKVM_USER="$JETKVM_USER"
export DEPLOY_JETKVM_PORT="$JETKVM_PORT"
if [ -n "$RESTART_CMD" ]; then
  export DEPLOY_JETKVM_RESTART_CMD="$RESTART_CMD"
fi

echo "=== Running jetkvm_deploy() against $JETKVM_USER@$JETKVM_HOST:$JETKVM_PORT ==="
if jetkvm_deploy "jetkvm-hook-test.invalid" "$_test_key" "$_test_crt" "$_test_crt" "$_test_crt"; then
  _ret=0
else
  _ret=$?
fi
echo "=== exit code: $_ret ==="

echo
if [ "$_ret" -eq 0 ]; then
  cat <<EOF
PASS (hook reported success). Now confirm on the device itself:

  ssh $JETKVM_USER@$JETKVM_HOST -p $JETKVM_PORT \\
    'ls -la /userdata/jetkvm/tls/user-defined.crt /userdata/jetkvm/tls/user-defined.key'

Expect: user-defined.crt mode 0644, user-defined.key mode 0600, and no
leftover ".*.tmp.*" staged files in that directory.

If you did NOT set RESTART_CMD=none, the device has rebooted -- and if
its web UI already has "HTTPS Mode" set to "Custom" (Settings >
Network), its HTTPS listener is now serving this throwaway test cert.
You can confirm with (expect the CN to be "jetkvm-hook-test.invalid"):

  openssl s_client -connect $JETKVM_HOST:443 -servername $JETKVM_HOST </dev/null 2>/dev/null | openssl x509 -noout -subject
EOF
else
  echo "FAIL (hook reported failure, exit code $_ret). See [err] lines above."
fi
